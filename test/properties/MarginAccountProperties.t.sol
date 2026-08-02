// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {EveUSDC} from "../../src/EveUSDC.sol";
import {MarginAccountFacet} from "../../src/facets/MarginAccountFacet.sol";
import {IMarginAccountFacet} from "../../src/interfaces/IMarginAccountFacet.sol";
import {MarginTypes} from "../../src/types/MarginTypes.sol";
import {TestBase} from "../helpers/TestBase.sol";

contract MarginAccountPropertiesTest is TestBase {
    bytes32 internal constant RISK_DOMAIN = keccak256("margin-property-risk-domain");

    EveUSDC internal eveUSDC;
    address internal riskManager;

    function setUp() public override {
        super.setUp();

        riskManager = makeAddr("riskManager");
        eveUSDC = new EveUSDC(address(usdc), makeAddr("onramp"), makeAddr("offramp"));

        vm.startPrank(owner);
        diamond.registerFacet(address(new MarginAccountFacet()), _marginSelectors());
        IMarginAccountFacet(address(diamond)).setMarginAsset(address(eveUSDC));
        IMarginAccountFacet(address(diamond)).setMarginRiskManager(riskManager);
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

        _wrapEveUSDC(maker, deposited / 1e12);

        vm.startPrank(maker);
        eveUSDC.approve(address(diamond), deposited);
        IMarginAccountFacet(address(diamond)).depositMargin(deposited, maker);
        bytes32 bucketId;
        if (allocated != 0) {
            bucketId = IMarginAccountFacet(address(diamond)).allocateBucketMargin(RISK_DOMAIN, allocated);
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
        assertEq(eveUSDC.balanceOf(address(diamond)), deposited - withdrawn);
        assertEq(eveUSDC.balanceOf(taker), withdrawn);
    }

    function testFuzz_LockedRiskCannotBeWithdrawnThroughBucketRelease(
        uint256 depositSeed,
        uint256 reserveSeed,
        uint256 releaseSeed
    ) public {
        uint256 deposited = bound(depositSeed, 1, 1_000_000e6) * 1e12;
        uint256 reserved = bound(reserveSeed, 1, deposited);
        uint256 releaseAttempt = bound(releaseSeed, deposited - reserved + 1, deposited);

        _wrapEveUSDC(maker, deposited / 1e12);

        vm.startPrank(maker);
        eveUSDC.approve(address(diamond), deposited);
        IMarginAccountFacet(address(diamond)).depositMargin(deposited, maker);
        bytes32 bucketId = IMarginAccountFacet(address(diamond)).allocateBucketMargin(RISK_DOMAIN, deposited);
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

    function testFuzz_RiskManagerCannotReserveMoreThanBucketMargin(uint256 depositSeed, uint256 reserveSeed) public {
        uint256 deposited = bound(depositSeed, 1, 1_000_000e6) * 1e12;
        uint256 reserveAttempt = bound(reserveSeed, deposited + 1, type(uint128).max);

        _wrapEveUSDC(maker, deposited / 1e12);

        vm.startPrank(maker);
        eveUSDC.approve(address(diamond), deposited);
        IMarginAccountFacet(address(diamond)).depositMargin(deposited, maker);
        bytes32 bucketId = IMarginAccountFacet(address(diamond)).allocateBucketMargin(RISK_DOMAIN, deposited);
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

        _wrapEveUSDC(maker, deposited / 1e12);

        vm.startPrank(maker);
        eveUSDC.approve(address(diamond), deposited);
        IMarginAccountFacet(address(diamond)).depositMargin(deposited, maker);
        bytes32 bucketId = IMarginAccountFacet(address(diamond)).allocateBucketMargin(RISK_DOMAIN, deposited);
        vm.stopPrank();

        vm.prank(owner);
        IMarginAccountFacet(address(diamond))
            .setRiskDomainFundingConfig(RISK_DOMAIN, MarginTypes.FundingMode.BorrowRate, ratePerSecondWad);

        vm.prank(riskManager);
        IMarginAccountFacet(address(diamond)).recordBucketDebt(bucketId, debt);

        vm.warp(block.timestamp + firstElapsed);
        IMarginAccountFacet(address(diamond)).accrueBucketFundingNow(bucketId);
        uint256 firstLiability = IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId).fundingLiability;

        vm.warp(block.timestamp + secondElapsed);
        IMarginAccountFacet(address(diamond)).accrueBucketFundingNow(bucketId);
        uint256 secondLiability = IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId).fundingLiability;

        assertGt(firstLiability, 0);
        assertGe(secondLiability, firstLiability);
    }

    function _wrapEveUSDC(address account, uint256 usdcAmount) internal {
        usdc.mint(account, usdcAmount);

        vm.startPrank(account);
        usdc.approve(address(eveUSDC), usdcAmount);
        eveUSDC.wrap(usdcAmount, account);
        vm.stopPrank();
    }

    function _marginSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](40);
        selectors[0] = IMarginAccountFacet.marginConfig.selector;
        selectors[1] = IMarginAccountFacet.depositMargin.selector;
        selectors[2] = IMarginAccountFacet.withdrawMargin.selector;
        selectors[3] = IMarginAccountFacet.allocateBucketMargin.selector;
        selectors[4] = IMarginAccountFacet.releaseBucketMargin.selector;
        selectors[5] = IMarginAccountFacet.getMarginAccount.selector;
        selectors[6] = IMarginAccountFacet.getMarginBucket.selector;
        selectors[7] = IMarginAccountFacet.bucketIdFor.selector;
        selectors[8] = IMarginAccountFacet.riskDomainForBook.selector;
        selectors[9] = IMarginAccountFacet.riskDomainForMarketBook.selector;
        selectors[10] = IMarginAccountFacet.canBucketIncreaseRisk.selector;
        selectors[11] = IMarginAccountFacet.setMarginAsset.selector;
        selectors[12] = IMarginAccountFacet.setMarginRiskManager.selector;
        selectors[13] = IMarginAccountFacet.setWarningRiskIncreaseAllowed.selector;
        selectors[14] = IMarginAccountFacet.reserveBucketRisk.selector;
        selectors[15] = IMarginAccountFacet.releaseReservedBucketRisk.selector;
        selectors[16] = IMarginAccountFacet.activateReservedBucketRisk.selector;
        selectors[17] = IMarginAccountFacet.releaseActiveBucketRisk.selector;
        selectors[18] = IMarginAccountFacet.recordBucketProfit.selector;
        selectors[19] = IMarginAccountFacet.recordBucketLoss.selector;
        selectors[20] = IMarginAccountFacet.setBucketState.selector;
        selectors[21] = IMarginAccountFacet.allocateBucketMarginWithKind.selector;
        selectors[22] = IMarginAccountFacet.getBucketRisk.selector;
        selectors[23] = IMarginAccountFacet.bucketLockedRisk.selector;
        selectors[24] = IMarginAccountFacet.canBucketIncreaseRiskForBook.selector;
        selectors[25] = IMarginAccountFacet.riskDomainOracleConfig.selector;
        selectors[26] = IMarginAccountFacet.setRiskDomainOracleConfig.selector;
        selectors[27] = IMarginAccountFacet.increaseOpenOrderRisk.selector;
        selectors[28] = IMarginAccountFacet.releaseOpenOrderRisk.selector;
        selectors[29] = IMarginAccountFacet.moveOpenOrderToPositionRisk.selector;
        selectors[30] = IMarginAccountFacet.releasePositionRisk.selector;
        selectors[31] = IMarginAccountFacet.recordBucketDebt.selector;
        selectors[32] = IMarginAccountFacet.repayBucketDebt.selector;
        selectors[33] = IMarginAccountFacet.accrueBucketFunding.selector;
        selectors[34] = IMarginAccountFacet.settleBucketFunding.selector;
        selectors[35] = IMarginAccountFacet.recordBucketUnrealizedPnl.selector;
        selectors[36] = IMarginAccountFacet.recordBucketRecoveryPnl.selector;
        selectors[37] = IMarginAccountFacet.recordBucketBadDebt.selector;
        selectors[38] = IMarginAccountFacet.setRiskDomainFundingConfig.selector;
        selectors[39] = IMarginAccountFacet.accrueBucketFundingNow.selector;
    }
}
