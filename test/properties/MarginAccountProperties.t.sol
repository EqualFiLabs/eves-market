// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {MockCollateral} from "../helpers/MockCollateral.sol";
import {MarginAccountFacet} from "../../src/facets/MarginAccountFacet.sol";
import {MarginTypes} from "../../src/types/MarginTypes.sol";
import {TestBase} from "../helpers/TestBase.sol";
import {
    IMarginTestFacet as IMarginAccountFacet,
    MarginAccountingHarnessFacet,
    MarginAccountingHarnessSelectors
} from "../helpers/MarginAccountingHarnessFacet.sol";

contract MarginAccountPropertiesTest is TestBase {
    bytes32 internal constant RISK_DOMAIN = keccak256("margin-property-risk-domain");

    MockCollateral internal collateral;
    address internal riskManager;

    function setUp() public override {
        super.setUp();

        riskManager = makeAddr("riskManager");
        collateral = new MockCollateral();

        vm.startPrank(owner);
        diamond.registerFacet(address(new MarginAccountFacet()), _marginSelectors());
        diamond.registerFacet(address(new MarginAccountingHarnessFacet()), MarginAccountingHarnessSelectors.harness());
        IMarginAccountFacet(address(diamond)).setMarginAsset(address(collateral));
        vm.stopPrank();
    }

    function testFuzz_FreeAndAllocatedMarginTrackDepositsWithdrawalsAndBucketMoves(
        uint256 depositSeed,
        uint256 allocateSeed,
        uint256 releaseSeed,
        uint256 withdrawSeed
    ) public {
        uint256 deposited = bound(depositSeed, 1, 1_000_000e6) * 1e12;
        uint256 allocated = bound(allocateSeed, 0, deposited);
        uint256 released = bound(releaseSeed, 0, allocated);
        uint256 withdrawableAfterRelease = deposited - allocated + released;
        uint256 withdrawn = bound(withdrawSeed, 0, withdrawableAfterRelease);

        _fundCollateral(maker, deposited / 1e12);

        vm.startPrank(maker);
        collateral.approve(address(diamond), deposited);
        IMarginAccountFacet(address(diamond)).depositMargin(deposited, maker);
        bytes32 bucketId;
        if (allocated != 0) {
            bucketId = IMarginAccountFacet(address(diamond)).allocateBucketMargin(RISK_DOMAIN, allocated, 1);
        }
        if (released != 0) {
            IMarginAccountFacet(address(diamond)).releaseBucketMargin(bucketId, released);
        }
        if (withdrawn != 0) {
            IMarginAccountFacet(address(diamond)).withdrawMargin(withdrawn, taker);
        }
        vm.stopPrank();

        MarginTypes.MarginAccount memory account = IMarginAccountFacet(address(diamond)).getMarginAccount(maker);

        assertEq(account.freeMargin + account.allocatedMargin, deposited - withdrawn);
        assertEq(account.freeMargin, deposited - allocated + released - withdrawn);
        assertEq(account.allocatedMargin, allocated - released);
        assertEq(collateral.balanceOf(address(diamond)), deposited - withdrawn);
        assertEq(collateral.balanceOf(taker), withdrawn);
    }

    function testFuzz_LockedRiskCannotBeWithdrawnThroughBucketRelease(
        uint256 depositSeed,
        uint256 reserveSeed,
        uint256 releaseSeed
    ) public {
        uint256 deposited = bound(depositSeed, 1, 1_000_000e6) * 1e12;
        uint256 reserved = bound(reserveSeed, 1, deposited);
        uint256 releaseAttempt = bound(releaseSeed, deposited - reserved + 1, deposited);

        _fundCollateral(maker, deposited / 1e12);

        vm.startPrank(maker);
        collateral.approve(address(diamond), deposited);
        IMarginAccountFacet(address(diamond)).depositMargin(deposited, maker);
        bytes32 bucketId = IMarginAccountFacet(address(diamond)).allocateBucketMargin(RISK_DOMAIN, deposited, 1);
        vm.stopPrank();

        vm.prank(riskManager);
        IMarginAccountFacet(address(diamond)).reserveBucketRisk(bucketId, reserved);

        vm.prank(maker);
        vm.expectRevert();
        IMarginAccountFacet(address(diamond)).releaseBucketMargin(bucketId, releaseAttempt);

        MarginTypes.MarginAccount memory account = IMarginAccountFacet(address(diamond)).getMarginAccount(maker);
        MarginTypes.MarginBucket memory bucket = IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId);

        assertEq(account.freeMargin, 0);
        assertEq(account.allocatedMargin, deposited);
        assertEq(bucket.marginAllocated, deposited);
        assertEq(bucket.reservedRisk, reserved);
        assertEq(bucket.openOrderRisk, reserved);
    }

    function testFuzz_RiskAccountingCannotReserveMoreThanBucketMargin(uint256 depositSeed, uint256 reserveSeed) public {
        uint256 deposited = bound(depositSeed, 1, 1_000_000e6) * 1e12;
        uint256 reserveAttempt = bound(reserveSeed, deposited + 1, type(uint128).max);

        _fundCollateral(maker, deposited / 1e12);

        vm.startPrank(maker);
        collateral.approve(address(diamond), deposited);
        IMarginAccountFacet(address(diamond)).depositMargin(deposited, maker);
        bytes32 bucketId = IMarginAccountFacet(address(diamond)).allocateBucketMargin(RISK_DOMAIN, deposited, 1);
        vm.stopPrank();

        vm.prank(riskManager);
        vm.expectRevert();
        IMarginAccountFacet(address(diamond)).reserveBucketRisk(bucketId, reserveAttempt);

        MarginTypes.MarginBucket memory bucket = IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId);
        assertEq(bucket.reservedRisk, 0);
        assertEq(bucket.openOrderRisk, 0);
        assertEq(bucket.activeRisk, 0);
        assertEq(bucket.positionRisk, 0);
        assertEq(bucket.marginAllocated, deposited);
    }

    function testFuzz_ConfiguredFundingLiabilityIsMonotonic(
        uint256 debtSeed,
        uint256 rateSeed,
        uint256 firstElapsedSeed,
        uint256 secondElapsedSeed
    ) public {
        uint256 deposited = 1_000_000e18;
        uint256 debt = bound(debtSeed, 1, deposited);
        uint128 ratePerSecondWad = uint128(bound(rateSeed, 1, 1e16));
        uint256 firstElapsed = bound(firstElapsedSeed, 1, 30 days);
        uint256 secondElapsed = bound(secondElapsedSeed, 1, 30 days);

        _fundCollateral(maker, deposited / 1e12);

        vm.startPrank(maker);
        collateral.approve(address(diamond), deposited);
        IMarginAccountFacet(address(diamond)).depositMargin(deposited, maker);
        bytes32 bucketId = IMarginAccountFacet(address(diamond)).allocateBucketMargin(RISK_DOMAIN, deposited, 1);
        vm.stopPrank();

        vm.prank(owner);
        IMarginAccountFacet(address(diamond))
            .setRiskDomainFundingConfig(RISK_DOMAIN, MarginTypes.FundingMode.BorrowRate, ratePerSecondWad);

        vm.prank(riskManager);
        IMarginAccountFacet(address(diamond)).recordBucketDebt(bucketId, debt);

        vm.warp(block.timestamp + firstElapsed);
        IMarginAccountFacet(address(diamond)).accrueBucketFundingNow(bucketId);
        MarginTypes.MarginBucket memory firstBucket = IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId);
        uint256 firstAccrualWad = firstBucket.fundingAccrued * 1e18 + firstBucket.fundingRemainderWad;

        vm.warp(block.timestamp + secondElapsed);
        IMarginAccountFacet(address(diamond)).accrueBucketFundingNow(bucketId);
        MarginTypes.MarginBucket memory secondBucket = IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId);
        uint256 secondAccrualWad = secondBucket.fundingAccrued * 1e18 + secondBucket.fundingRemainderWad;

        assertGt(firstAccrualWad, 0);
        assertGt(secondAccrualWad, firstAccrualWad);
        assertGe(secondBucket.fundingLiability, firstBucket.fundingLiability);
    }

    function _fundCollateral(address account, uint256 usdcAmount) internal {
        collateral.mint(account, usdcAmount * 1e12);
    }

    function _marginSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = MarginAccountingHarnessSelectors.production();
    }
}
