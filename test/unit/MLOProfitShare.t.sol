// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {MLOInsuranceFund} from "../../src/MLOInsuranceFund.sol";
import {MarginAccountFacet} from "../../src/facets/MarginAccountFacet.sol";
import {MLOPredictionRecoveryFacet} from "../../src/facets/MLOPredictionRecoveryFacet.sol";
import {MLOProfitShareFacet} from "../../src/facets/MLOProfitShareFacet.sol";
import {SeniorCapitalFacet} from "../../src/facets/SeniorCapitalFacet.sol";
import {SeniorCapitalViewFacet} from "../../src/facets/SeniorCapitalViewFacet.sol";
import {IMLOPredictionAdapterFacet} from "../../src/interfaces/IMLOPredictionAdapterFacet.sol";
import {IMLOProfitShareFacet} from "../../src/interfaces/IMLOProfitShareFacet.sol";
import {IMarginAccountFacet as IProductionMarginAccountFacet} from "../../src/interfaces/IMarginAccountFacet.sol";
import {ISeniorCapitalFacet} from "../../src/interfaces/ISeniorCapitalFacet.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {MarginTypes} from "../../src/types/MarginTypes.sol";
import {MLOProfitShareTypes} from "../../src/types/MLOProfitShareTypes.sol";
import {MockCollateral} from "../helpers/MockCollateral.sol";
import {
    IMarginTestFacet as IMarginAccountFacet,
    MarginAccountingHarnessFacet,
    MarginAccountingHarnessSelectors
} from "../helpers/MarginAccountingHarnessFacet.sol";
import {TestBase} from "../helpers/TestBase.sol";

contract MLOProfitShareTest is TestBase {
    MockCollateral internal collateral;
    MLOInsuranceFund internal insurance;
    address internal riskManager;
    address internal seniorDepositor;

    function setUp() public override {
        super.setUp();
        collateral = new MockCollateral();
        riskManager = makeAddr("riskManager");
        seniorDepositor = makeAddr("seniorDepositor");

        vm.startPrank(owner);
        diamond.registerFacet(address(new MarginAccountFacet()), MarginAccountingHarnessSelectors.production());
        diamond.registerFacet(address(new MarginAccountingHarnessFacet()), MarginAccountingHarnessSelectors.harness());
        diamond.registerFacet(address(new MLOProfitShareFacet()), _profitShareSelectors());
        diamond.registerFacet(address(new SeniorCapitalFacet()), _seniorSelectors());
        diamond.registerFacet(address(new SeniorCapitalViewFacet()), _seniorViewSelectors());
        diamond.registerFacet(address(new MLOPredictionRecoveryFacet()), _recoverySelectors());
        IMarginAccountFacet(address(diamond)).setMarginAsset(address(collateral));
        insurance = new MLOInsuranceFund(address(collateral), address(diamond), address(diamond));
        IMLOPredictionAdapterFacet(address(diamond)).setMLORecoveryConfig(address(insurance), 5_000, 50);
        IMLOProfitShareFacet(address(diamond)).initializeMLOProfitSplit(7_500, 2_000, 500);
        vm.stopPrank();
    }

    function test_NetProfitSplitsBetweenMakerSeniorAndInsurance() public {
        _activateSenior(100e18);
        bytes32 bucketId = _depositAndAllocate(100e18, keccak256("profit-split"));
        _recordProfit(bucketId, 20e18);

        MLOProfitShareTypes.ProfitRelease memory preview =
            IMLOProfitShareFacet(address(diamond)).previewMLOProfitRelease(bucketId, 115e18);
        assertEq(preview.principalReturned, 100e18);
        assertEq(preview.profitRecognized, 15e18);
        assertEq(preview.makerCredit, 115e18);
        MLOProfitShareTypes.BucketRewardView memory reward =
            IMLOProfitShareFacet(address(diamond)).mloBucketProfitReward(bucketId, seniorDepositor);
        assertEq(reward.accountClaimable, 4e18);

        vm.prank(maker);
        MLOProfitShareTypes.ProfitRelease memory release =
            IMarginAccountFacet(address(diamond)).releaseBucketMargin(bucketId, 115e18);

        assertEq(release.principalReturned, 100e18);
        assertEq(release.profitRecognized, 15e18);
        assertEq(release.makerCredit, 115e18);
        assertEq(release.seniorShare, 0);
        assertEq(release.insuranceShare, 0);
        assertEq(insurance.totalProfitShare(), 1e18);
        assertEq(collateral.balanceOf(address(insurance)), 1e18);
        assertEq(IMarginAccountFacet(address(diamond)).getMarginAccount(maker).freeMargin, 115e18);

        vm.prank(maker);
        IMarginAccountFacet(address(diamond)).withdrawMargin(115e18, maker);
        vm.prank(seniorDepositor);
        IMLOProfitShareFacet(address(diamond)).claimMLOBucketProfitReward(bucketId, seniorDepositor);
        assertEq(collateral.balanceOf(maker), 115e18);
        assertEq(collateral.balanceOf(seniorDepositor), 4e18);
        assertEq(collateral.balanceOf(address(diamond)), 100e18);
    }

    function test_EmptySeniorPoolRedirectsSeniorShareToInsurance() public {
        bytes32 bucketId = _depositAndAllocate(100e18, keccak256("empty-senior"));
        _recordProfit(bucketId, 20e18);

        vm.prank(maker);
        MLOProfitShareTypes.ProfitRelease memory release =
            IMarginAccountFacet(address(diamond)).releaseBucketMargin(bucketId, 115e18);

        assertEq(release.makerCredit, 115e18);
        assertEq(release.seniorShare, 0);
        assertEq(release.seniorRedirectedToInsurance, 0);
        assertEq(release.insuranceShare, 0);
        assertEq(insurance.totalProfitShare(), 5e18);

        _activateSenior(100e18);
        assertEq(ISeniorCapitalFacet(address(diamond)).pendingSeniorCapitalFees(seniorDepositor), 0);
    }

    function test_LossMustBeRecoveredBeforeNewProfitIsShared() public {
        _activateSenior(100e18);
        bytes32 bucketId = _depositAndAllocate(100e18, keccak256("high-water"));
        vm.prank(riskManager);
        IMarginAccountFacet(address(diamond)).recordBucketLoss(bucketId, 30e18);
        _recordProfit(bucketId, 20e18);

        vm.prank(maker);
        MLOProfitShareTypes.ProfitRelease memory first =
            IMarginAccountFacet(address(diamond)).releaseBucketMargin(bucketId, 90e18);
        assertEq(first.profitRecognized, 0);
        assertEq(first.makerCredit, 90e18);

        MLOProfitShareTypes.BucketProfitAccount memory account =
            IMLOProfitShareFacet(address(diamond)).mloBucketProfitAccount(bucketId);
        assertEq(account.remainingCapitalBasis, 10e18);

        _recordProfit(bucketId, 20e18);
        vm.prank(maker);
        MLOProfitShareTypes.ProfitRelease memory second =
            IMarginAccountFacet(address(diamond)).releaseBucketMargin(bucketId, 17.5e18);
        assertEq(second.principalReturned, 10e18);
        assertEq(second.profitRecognized, 7.5e18);
        assertEq(second.makerCredit, 17.5e18);
        assertEq(second.seniorShare, 0);
        assertEq(second.insuranceShare, 0);
        assertEq(
            IMLOProfitShareFacet(address(diamond)).mloBucketProfitReward(bucketId, seniorDepositor).accountClaimable,
            2e18
        );
        assertEq(insurance.totalProfitShare(), 0.5e18);
    }

    function test_CumulativeRoundingCannotBeAvoidedByMicroReleases() public {
        _activateSenior(100e18);
        bytes32 bucketId = _depositAndAllocate(100e18, keccak256("rounding"));
        for (uint256 recognized = 1; recognized <= 21; ++recognized) {
            _recordProfit(bucketId, 1);
            if (recognized == 19) {
                assertEq(
                    IMLOProfitShareFacet(address(diamond))
                    .mloBucketProfitReward(bucketId, seniorDepositor)
                    .accountClaimable,
                    4
                );
                assertEq(insurance.totalProfitShare(), 0);
            } else if (recognized == 20) {
                assertEq(
                    IMLOProfitShareFacet(address(diamond))
                    .mloBucketProfitReward(bucketId, seniorDepositor)
                    .accountClaimable,
                    4
                );
                assertEq(insurance.totalProfitShare(), 1);
            }
        }

        MLOProfitShareTypes.BucketProfitAccount memory account =
            IMLOProfitShareFacet(address(diamond)).mloBucketProfitAccount(bucketId);
        assertEq(account.cumulativeProfitRecognized, 21);
        assertEq(account.seniorShareSettled, 4);
        assertEq(account.insuranceShareSettled, 1);
        assertEq(account.seniorRewardFunded, 4);
        assertEq(
            IMLOProfitShareFacet(address(diamond)).mloBucketProfitReward(bucketId, seniorDepositor).accountClaimable, 4
        );
        vm.prank(maker);
        IMarginAccountFacet(address(diamond)).releaseBucketMargin(bucketId, 100e18 + 16);
        assertEq(IMarginAccountFacet(address(diamond)).getMarginAccount(maker).freeMargin, 100e18 + 16);
    }

    function test_TopUpDoesNotConvertExistingProfitIntoPrincipal() public {
        _activateSenior(100e18);
        bytes32 bucketId = _depositAndAllocate(100e18, keccak256("top-up"));
        _recordProfit(bucketId, 20e18);

        collateral.mint(maker, 50e18);
        vm.startPrank(maker);
        collateral.approve(address(diamond), 50e18);
        IMarginAccountFacet(address(diamond)).depositMargin(50e18, maker);
        IMarginAccountFacet(address(diamond)).allocateBucketMargin(keccak256("top-up"), 50e18, 1);
        MLOProfitShareTypes.ProfitRelease memory principal =
            IMarginAccountFacet(address(diamond)).releaseBucketMargin(bucketId, 150e18);
        MLOProfitShareTypes.ProfitRelease memory profit =
            IMarginAccountFacet(address(diamond)).releaseBucketMargin(bucketId, 15e18);
        vm.stopPrank();

        assertEq(principal.profitRecognized, 0);
        assertEq(profit.profitRecognized, 15e18);
        assertEq(profit.seniorShare, 0);
        assertEq(profit.insuranceShare, 0);
        assertEq(
            IMLOProfitShareFacet(address(diamond)).mloBucketProfitReward(bucketId, seniorDepositor).accountClaimable,
            4e18
        );
    }

    function testFuzz_WithdrawalPartitionCannotChangeProfitEntitlements(
        uint96 principalRaw,
        uint96 profitRaw,
        uint96 firstReleaseRaw
    ) public {
        uint256 principal = bound(uint256(principalRaw), 1e6, 1e24);
        uint256 profit = bound(uint256(profitRaw), 1, 1e24);
        uint256 firstRelease = bound(uint256(firstReleaseRaw), 0, profit);
        _activateSenior(1e18);
        bytes32 bucketId = _depositAndAllocate(principal, keccak256(abi.encode(principal, profit)));
        if (firstRelease != 0) _recordProfit(bucketId, firstRelease);
        if (firstRelease != profit) _recordProfit(bucketId, profit - firstRelease);

        vm.prank(maker);
        IMarginAccountFacet(address(diamond)).releaseBucketMargin(bucketId, principal);

        uint256 expectedInsurance = profit * 500 / 10_000;
        uint256 expectedNonMaker = profit * 2_500 / 10_000;
        uint256 expectedSenior = expectedNonMaker - expectedInsurance;
        MLOProfitShareTypes.BucketProfitAccount memory account =
            IMLOProfitShareFacet(address(diamond)).mloBucketProfitAccount(bucketId);
        assertEq(account.cumulativeProfitRecognized, profit);
        assertEq(account.seniorShareSettled, expectedSenior);
        assertEq(account.insuranceShareSettled, expectedInsurance);
        assertEq(insurance.totalProfitShare(), expectedInsurance);
        assertEq(
            IMLOProfitShareFacet(address(diamond)).mloBucketProfitReward(bucketId, seniorDepositor).accountClaimable,
            expectedSenior
        );
        assertEq(IMarginAccountFacet(address(diamond)).getMarginAccount(maker).freeMargin, principal);
        assertEq(
            IProductionMarginAccountFacet(address(diamond)).getMarginBucket(bucketId).marginAllocated,
            profit - expectedNonMaker
        );
    }

    function test_LateSeniorActivationCannotDiluteRiskCohort() public {
        _activateSeniorFor(seniorDepositor, 900e18);
        bytes32 bucketId = _depositAndAllocate(100e18, keccak256("historical-cohort"));

        _activateSeniorFor(maker, 100e18);
        _recordProfit(bucketId, 20e18);

        MLOProfitShareTypes.BucketRewardView memory honestReward =
            IMLOProfitShareFacet(address(diamond)).mloBucketProfitReward(bucketId, seniorDepositor);
        MLOProfitShareTypes.BucketRewardView memory lateReward =
            IMLOProfitShareFacet(address(diamond)).mloBucketProfitReward(bucketId, maker);
        assertEq(honestReward.snapshotStored, 900e18);
        assertEq(honestReward.eligibleStored, 900e18);
        assertEq(honestReward.accountClaimable, 4e18);
        assertEq(lateReward.eligibleStored, 0);
        assertEq(lateReward.accountClaimable, 0);

        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSelector(IMLOProfitShareFacet.NoMLOBucketProfitReward.selector, bucketId, maker));
        IMLOProfitShareFacet(address(diamond)).claimMLOBucketProfitReward(bucketId, maker);
    }

    function test_RiskCohortRewardsAreProportionalAndClaimOrderIndependent() public {
        address secondProvider = makeAddr("second-provider");
        _activateSeniorFor(seniorDepositor, 900e18);
        _activateSeniorFor(secondProvider, 100e18);
        bytes32 bucketId = _depositAndAllocate(100e18, keccak256("cohort-proportions"));
        _recordProfit(bucketId, 20e18);

        assertEq(
            IMLOProfitShareFacet(address(diamond)).mloBucketProfitReward(bucketId, seniorDepositor).accountClaimable,
            3.6e18
        );
        assertEq(
            IMLOProfitShareFacet(address(diamond)).mloBucketProfitReward(bucketId, secondProvider).accountClaimable,
            0.4e18
        );
        vm.prank(secondProvider);
        IMLOProfitShareFacet(address(diamond)).claimMLOBucketProfitReward(bucketId, secondProvider);
        vm.prank(seniorDepositor);
        IMLOProfitShareFacet(address(diamond)).claimMLOBucketProfitReward(bucketId, seniorDepositor);
        MLOProfitShareTypes.BucketProfitAccount memory account =
            IMLOProfitShareFacet(address(diamond)).mloBucketProfitAccount(bucketId);
        assertEq(account.seniorRewardClaimed, account.seniorRewardFunded);
    }

    function test_QueuedExitCannotDiluteNewRiskCohort() public {
        address activeProvider = makeAddr("active-provider");
        _activateSeniorFor(seniorDepositor, 100e18);
        _activateSeniorFor(activeProvider, 900e18);

        vm.prank(seniorDepositor);
        ISeniorCapitalFacet(address(diamond)).requestSeniorCapitalExit(100e18, seniorDepositor);
        bytes32 bucketId = _depositAndAllocate(100e18, keccak256("queued-exit-cohort"));
        _recordProfit(bucketId, 20e18);

        MLOProfitShareTypes.BucketRewardView memory queuedReward =
            IMLOProfitShareFacet(address(diamond)).mloBucketProfitReward(bucketId, seniorDepositor);
        MLOProfitShareTypes.BucketRewardView memory activeReward =
            IMLOProfitShareFacet(address(diamond)).mloBucketProfitReward(bucketId, activeProvider);
        assertEq(queuedReward.snapshotStored, 900e18);
        assertEq(queuedReward.eligibleStored, 0);
        assertEq(queuedReward.accountClaimable, 0);
        assertEq(activeReward.eligibleStored, 900e18);
        assertEq(activeReward.accountClaimable, 4e18);
    }

    function test_ActivationAfterProfitRecognitionReceivesNoHistoricalReward() public {
        bytes32 bucketId = _depositAndAllocate(100e18, keccak256("terminal-activation"));
        _recordProfit(bucketId, 20e18);

        _activateSeniorFor(maker, 1);

        assertEq(IMLOProfitShareFacet(address(diamond)).mloBucketProfitReward(bucketId, maker).accountClaimable, 0);
        assertEq(insurance.totalProfitShare(), 5e18);
        vm.prank(maker);
        IMarginAccountFacet(address(diamond)).releaseBucketMargin(bucketId, 115e18);
        assertEq(IMarginAccountFacet(address(diamond)).getMarginAccount(maker).freeMargin, 115e18);
    }

    function test_TimelockedSplitOnlyAffectsNewBuckets() public {
        bytes32 firstBucket = _depositAndAllocate(10e18, keccak256("old-split"));

        vm.prank(owner);
        IMLOProfitShareFacet(address(diamond)).scheduleMLOProfitSplit(8_000, 1_000, 1_000);
        MLOProfitShareTypes.PendingProfitSplit memory pending =
            IMLOProfitShareFacet(address(diamond)).pendingMLOProfitSplit();

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(IMLOProfitShareFacet.MLOProfitSplitTimelocked.selector, pending.executableAt)
        );
        IMLOProfitShareFacet(address(diamond)).executeMLOProfitSplit();

        vm.warp(pending.executableAt);
        vm.prank(owner);
        IMLOProfitShareFacet(address(diamond)).executeMLOProfitSplit();
        bytes32 secondBucket = _depositAndAllocate(10e18, keccak256("new-split"));

        MLOProfitShareTypes.BucketProfitAccount memory first =
            IMLOProfitShareFacet(address(diamond)).mloBucketProfitAccount(firstBucket);
        MLOProfitShareTypes.BucketProfitAccount memory second =
            IMLOProfitShareFacet(address(diamond)).mloBucketProfitAccount(secondBucket);
        assertEq(first.split.makerBps, 7_500);
        assertEq(first.split.seniorBps, 2_000);
        assertEq(first.split.insuranceBps, 500);
        assertEq(first.split.version, 1);
        assertEq(second.split.makerBps, 8_000);
        assertEq(second.split.seniorBps, 1_000);
        assertEq(second.split.insuranceBps, 1_000);
        assertEq(second.split.version, 2);
    }

    function test_ExpiredSplitProposalCannotExecuteAndCanBeRescheduled() public {
        vm.prank(owner);
        IMLOProfitShareFacet(address(diamond)).scheduleMLOProfitSplit(8_000, 1_000, 1_000);
        MLOProfitShareTypes.PendingProfitSplit memory stale =
            IMLOProfitShareFacet(address(diamond)).pendingMLOProfitSplit();
        assertEq(stale.split.version, 2);
        assertGt(stale.expiresAt, stale.executableAt);

        vm.warp(uint256(stale.expiresAt) + 1);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IMLOProfitShareFacet.MLOProfitSplitExpired.selector, stale.expiresAt));
        IMLOProfitShareFacet(address(diamond)).executeMLOProfitSplit();
        assertEq(IMLOProfitShareFacet(address(diamond)).activeMLOProfitSplit().version, 1);

        vm.prank(owner);
        IMLOProfitShareFacet(address(diamond)).scheduleMLOProfitSplit(8_000, 1_000, 1_000);
        MLOProfitShareTypes.PendingProfitSplit memory replacement =
            IMLOProfitShareFacet(address(diamond)).pendingMLOProfitSplit();
        assertEq(replacement.split.version, 2);
        assertGt(replacement.executableAt, stale.expiresAt);
        vm.warp(replacement.executableAt);
        vm.prank(owner);
        IMLOProfitShareFacet(address(diamond)).executeMLOProfitSplit();
        assertEq(IMLOProfitShareFacet(address(diamond)).activeMLOProfitSplit().version, 2);
    }

    function test_InitialAllocationPinsExpectedSplitVersion() public {
        collateral.mint(maker, 10e18);
        vm.startPrank(maker);
        collateral.approve(address(diamond), 10e18);
        IMarginAccountFacet(address(diamond)).depositMargin(10e18, maker);
        vm.expectRevert(abi.encodeWithSelector(IMLOProfitShareFacet.MLOProfitSplitVersionMismatch.selector, 2, 1));
        IMarginAccountFacet(address(diamond)).allocateBucketMargin(keccak256("pinned-version"), 10e18, 2);
        bytes32 bucketId =
            IMarginAccountFacet(address(diamond)).allocateBucketMargin(keccak256("pinned-version"), 10e18, 1);
        vm.stopPrank();

        assertEq(IMLOProfitShareFacet(address(diamond)).mloBucketProfitAccount(bucketId).split.version, 1);
    }

    function test_AllocationRevertsWhenGovernanceActivatesNewTermsFirst() public {
        vm.prank(owner);
        IMLOProfitShareFacet(address(diamond)).scheduleMLOProfitSplit(8_000, 1_000, 1_000);
        MLOProfitShareTypes.PendingProfitSplit memory pending =
            IMLOProfitShareFacet(address(diamond)).pendingMLOProfitSplit();
        vm.warp(pending.executableAt);
        vm.prank(owner);
        IMLOProfitShareFacet(address(diamond)).executeMLOProfitSplit();

        collateral.mint(maker, 10e18);
        vm.startPrank(maker);
        collateral.approve(address(diamond), 10e18);
        IMarginAccountFacet(address(diamond)).depositMargin(10e18, maker);
        vm.expectRevert(abi.encodeWithSelector(IMLOProfitShareFacet.MLOProfitSplitVersionMismatch.selector, 1, 2));
        IMarginAccountFacet(address(diamond)).allocateBucketMargin(keccak256("ordered-version"), 10e18, 1);
        vm.stopPrank();
    }

    function test_ClosedBucketCanReleaseOnlyWithoutObligations() public {
        bytes32 bucketId = _depositAndAllocate(100e18, keccak256("closed"));
        vm.prank(riskManager);
        IMarginAccountFacet(address(diamond)).reserveBucketRisk(bucketId, 1e18);
        vm.prank(riskManager);
        IMarginAccountFacet(address(diamond)).setBucketState(bucketId, MarginTypes.BucketState.Closed);

        vm.prank(maker);
        vm.expectRevert(
            abi.encodeWithSelector(IProductionMarginAccountFacet.ClosedBucketHasObligations.selector, bucketId, 1e18)
        );
        IMarginAccountFacet(address(diamond)).releaseBucketMargin(bucketId, 1e18);

        vm.prank(riskManager);
        IMarginAccountFacet(address(diamond)).releaseReservedBucketRisk(bucketId, 1e18);
        vm.prank(maker);
        MLOProfitShareTypes.ProfitRelease memory release =
            IMarginAccountFacet(address(diamond)).releaseBucketMargin(bucketId, 100e18);
        assertEq(release.makerCredit, 100e18);
    }

    function test_NonMLOBucketReleaseRemainsUnshared() public {
        collateral.mint(maker, 100e18);
        vm.startPrank(maker);
        collateral.approve(address(diamond), 100e18);
        IMarginAccountFacet(address(diamond)).depositMargin(100e18, maker);
        bytes32 bucketId = IMarginAccountFacet(address(diamond))
            .allocateBucketMarginWithKind(keccak256("generic"), 100e18, MarginTypes.BucketKind.PredictionTrader, 0);
        vm.stopPrank();

        vm.prank(riskManager);
        IMarginAccountFacet(address(diamond)).setBucketState(bucketId, MarginTypes.BucketState.Closed);
        vm.prank(maker);
        vm.expectRevert(
            abi.encodeWithSelector(
                IProductionMarginAccountFacet.BucketMarginFrozen.selector, bucketId, MarginTypes.BucketState.Closed
            )
        );
        IMarginAccountFacet(address(diamond)).releaseBucketMargin(bucketId, 100e18);

        vm.prank(riskManager);
        IMarginAccountFacet(address(diamond)).setBucketState(bucketId, MarginTypes.BucketState.Healthy);
        vm.prank(maker);
        MLOProfitShareTypes.ProfitRelease memory release =
            IMarginAccountFacet(address(diamond)).releaseBucketMargin(bucketId, 100e18);

        assertEq(release.makerCredit, 100e18);
        assertEq(release.seniorShare, 0);
        assertEq(release.insuranceShare, 0);
    }

    function test_RevertWhen_ScheduledSplitDoesNotTotalOneHundredPercent() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IMLOProfitShareFacet.InvalidMLOProfitSplit.selector, 7_500, 2_000, 499));
        IMLOProfitShareFacet(address(diamond)).scheduleMLOProfitSplit(7_500, 2_000, 499);
    }

    function test_ReleasePreviewRejectsImpossibleAmounts() public {
        bytes32 bucketId = _depositAndAllocate(100e18, keccak256("preview-bounds"));

        vm.expectRevert(IProductionMarginAccountFacet.ZeroAmount.selector);
        IMLOProfitShareFacet(address(diamond)).previewMLOProfitRelease(bucketId, 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                IProductionMarginAccountFacet.InsufficientBucketMargin.selector, bucketId, 100e18 + 1, 100e18
            )
        );
        IMLOProfitShareFacet(address(diamond)).previewMLOProfitRelease(bucketId, 100e18 + 1);
    }

    function test_OnlyOwnerCanScheduleAndOwnerCanCancel() public {
        vm.prank(taker);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotContractOwner.selector, taker));
        IMLOProfitShareFacet(address(diamond)).scheduleMLOProfitSplit(8_000, 1_000, 1_000);

        vm.startPrank(owner);
        IMLOProfitShareFacet(address(diamond)).scheduleMLOProfitSplit(8_000, 1_000, 1_000);
        IMLOProfitShareFacet(address(diamond)).cancelMLOProfitSplit();
        vm.stopPrank();

        assertFalse(IMLOProfitShareFacet(address(diamond)).pendingMLOProfitSplit().exists);
        vm.prank(owner);
        vm.expectRevert(IMLOProfitShareFacet.NoPendingMLOProfitSplit.selector);
        IMLOProfitShareFacet(address(diamond)).executeMLOProfitSplit();
    }

    function _depositAndAllocate(uint256 assets, bytes32 riskDomainId) internal returns (bytes32 bucketId) {
        collateral.mint(maker, assets);
        vm.startPrank(maker);
        collateral.approve(address(diamond), assets);
        IMarginAccountFacet(address(diamond)).depositMargin(assets, maker);
        uint256 expectedVersion = IMLOProfitShareFacet(address(diamond)).activeMLOProfitSplit().version;
        bucketId = IMarginAccountFacet(address(diamond)).allocateBucketMargin(riskDomainId, assets, expectedVersion);
        vm.stopPrank();
        if (ISeniorCapitalFacet(address(diamond)).seniorCapitalState().totalStored != 0) {
            // This narrow harness hook reaches the production reservation snapshot without
            // constructing an economically unrelated quote solely for profit-account tests.
            IMarginAccountFacet(address(diamond)).snapshotSeniorRiskCohort(bucketId, 1);
        }
    }

    function _recordProfit(bytes32 bucketId, uint256 assets) internal {
        collateral.mint(riskManager, assets);
        vm.startPrank(riskManager);
        collateral.approve(address(diamond), assets);
        IMarginAccountFacet(address(diamond)).recordBucketProfit(bucketId, assets);
        vm.stopPrank();
    }

    function _activateSenior(uint256 assets) internal {
        _activateSeniorFor(seniorDepositor, assets);
    }

    function _activateSeniorFor(address account, uint256 assets) internal {
        collateral.mint(account, assets);
        vm.startPrank(account);
        collateral.approve(address(diamond), assets);
        ISeniorCapitalFacet(address(diamond)).depositSeniorCapital(assets);
        vm.stopPrank();
        vm.warp(uint256(ISeniorCapitalFacet(address(diamond)).seniorCapitalAccount(account).pendingSince) + 24 hours);
        vm.prank(account);
        ISeniorCapitalFacet(address(diamond)).activateSeniorCapital();
    }

    function _profitShareSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](10);
        selectors[0] = IMLOProfitShareFacet.initializeMLOProfitSplit.selector;
        selectors[1] = IMLOProfitShareFacet.scheduleMLOProfitSplit.selector;
        selectors[2] = IMLOProfitShareFacet.cancelMLOProfitSplit.selector;
        selectors[3] = IMLOProfitShareFacet.executeMLOProfitSplit.selector;
        selectors[4] = IMLOProfitShareFacet.activeMLOProfitSplit.selector;
        selectors[5] = IMLOProfitShareFacet.pendingMLOProfitSplit.selector;
        selectors[6] = IMLOProfitShareFacet.mloBucketProfitAccount.selector;
        selectors[7] = IMLOProfitShareFacet.previewMLOProfitRelease.selector;
        selectors[8] = IMLOProfitShareFacet.mloBucketProfitReward.selector;
        selectors[9] = IMLOProfitShareFacet.claimMLOBucketProfitReward.selector;
    }

    function _seniorSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](9);
        selectors[0] = ISeniorCapitalFacet.depositSeniorCapital.selector;
        selectors[1] = ISeniorCapitalFacet.withdrawPendingSeniorCapital.selector;
        selectors[2] = ISeniorCapitalFacet.activateSeniorCapital.selector;
        selectors[3] = ISeniorCapitalFacet.requestSeniorCapitalExit.selector;
        selectors[4] = ISeniorCapitalFacet.cancelSeniorCapitalExit.selector;
        selectors[5] = ISeniorCapitalFacet.processSeniorCapitalExits.selector;
        selectors[6] = ISeniorCapitalFacet.claimSeniorCapitalFees.selector;
        selectors[7] = ISeniorCapitalFacet.donateSeniorCapitalFees.selector;
        selectors[8] = ISeniorCapitalFacet.claimSeniorCapitalExit.selector;
    }

    function _seniorViewSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](6);
        selectors[0] = ISeniorCapitalFacet.seniorCapitalState.selector;
        selectors[1] = ISeniorCapitalFacet.seniorCapitalAccount.selector;
        selectors[2] = ISeniorCapitalFacet.seniorCapitalExit.selector;
        selectors[3] = ISeniorCapitalFacet.seniorCapitalBucket.selector;
        selectors[4] = ISeniorCapitalFacet.pendingSeniorCapitalFees.selector;
        selectors[5] = ISeniorCapitalFacet.claimableSeniorCapitalExit.selector;
    }

    function _recoverySelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = IMLOPredictionAdapterFacet.mloRecoveryConfig.selector;
        selectors[1] = IMLOPredictionAdapterFacet.setMLORecoveryConfig.selector;
    }
}
