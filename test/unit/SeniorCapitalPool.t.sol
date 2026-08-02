// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20Errors} from "../../lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";

import {ISeniorCapitalPool} from "../../src/interfaces/ISeniorCapitalPool.sol";
import {SeniorCapitalPool} from "../../src/SeniorCapitalPool.sol";

import {EveUSDCTestBase} from "../helpers/EveUSDCTestBase.sol";

contract MockRiskManager {}

contract SeniorCapitalPoolTest is EveUSDCTestBase {
    SeniorCapitalPool internal pool;

    address internal owner;
    address internal riskManager;
    address internal sponsor;
    address internal liquidReceiver;
    bytes32 internal bucketId;

    function setUp() public override {
        super.setUp();

        owner = makeAddr("owner");
        riskManager = address(new MockRiskManager());
        sponsor = makeAddr("sponsor");
        liquidReceiver = makeAddr("liquidReceiver");
        bucketId = keccak256("pool-bucket");

        pool = new SeniorCapitalPool(address(eveUSDC), owner, riskManager);
    }

    function test_DepositMintsSharesAndTransfersEveUSDC() public {
        uint256 assets = 100e18;
        _seedEveUSDC(alice, assets);

        vm.startPrank(alice);
        eveUSDC.approve(address(pool), assets);
        uint256 shares = pool.deposit(assets, alice);
        vm.stopPrank();

        assertEq(shares, assets);
        assertEq(pool.balanceOf(alice), shares);
        assertEq(pool.totalSupply(), shares);
        assertEq(pool.totalAssets(), assets);
        assertEq(pool.availableCapital(), assets);
        assertEq(eveUSDC.balanceOf(address(pool)), assets);
    }

    function test_RedeemBurnsSharesAndReturnsAvailableCapital() public {
        uint256 assets = 100e18;
        _deposit(alice, assets);

        vm.prank(alice);
        uint256 redeemed = pool.redeem(40e18, receiver, alice);

        assertEq(redeemed, 40e18);
        assertEq(pool.balanceOf(alice), 60e18);
        assertEq(pool.totalAssets(), 60e18);
        assertEq(pool.availableCapital(), 60e18);
        assertEq(eveUSDC.balanceOf(receiver), 40e18);
    }

    function test_WithdrawWithAllowanceConsumesOnlyRequiredShares() public {
        uint256 assets = 100e18;
        _deposit(alice, assets);

        vm.prank(alice);
        pool.approve(bob, 50e18);

        vm.prank(bob);
        uint256 shares = pool.withdraw(30e18, receiver, alice);

        assertEq(shares, 30e18);
        assertEq(pool.allowance(alice, bob), 20e18);
        assertEq(pool.balanceOf(alice), 70e18);
        assertEq(eveUSDC.balanceOf(receiver), 30e18);
    }

    function test_RevenueIncreasesNavAndBenefitsExistingShares() public {
        _deposit(alice, 100e18);
        _seedEveUSDC(sponsor, 50e18);

        vm.startPrank(sponsor);
        eveUSDC.approve(address(pool), 50e18);
        pool.notifyRevenue(50e18);
        vm.stopPrank();

        assertEq(pool.totalAssets(), 150e18);
        assertApproxEqAbs(pool.previewRedeem(100e18), 150e18, 1);
        assertEq(pool.availableCapital(), 150e18);
    }

    function test_DepositorAfterRevenueReceivesFewerShares() public {
        _deposit(alice, 100e18);
        _sponsorRevenue(100e18);

        _seedEveUSDC(bob, 100e18);

        vm.startPrank(bob);
        eveUSDC.approve(address(pool), 100e18);
        uint256 shares = pool.deposit(100e18, bob);
        vm.stopPrank();

        assertApproxEqAbs(shares, 50e18, 1);
        assertEq(pool.balanceOf(alice), 100e18);
        assertApproxEqAbs(pool.balanceOf(bob), 50e18, 1);
    }

    function test_ReservedCapitalBlocksWithdrawalsWithoutChangingNav() public {
        _deposit(alice, 100e18);

        vm.prank(riskManager);
        pool.reserveCapital(70e18);

        assertEq(pool.totalAssets(), 100e18);
        assertEq(pool.availableCapital(), 30e18);
        assertEq(pool.maxWithdraw(alice), 30e18);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ISeniorCapitalPool.InsufficientAvailableCapital.selector, 31e18, 30e18));
        pool.withdraw(31e18, receiver, alice);
    }

    function test_ReleasingReservedCapitalRestoresAvailability() public {
        _deposit(alice, 100e18);

        vm.startPrank(riskManager);
        pool.reserveCapital(70e18);
        pool.releaseReservedCapital(40e18);
        vm.stopPrank();

        assertEq(pool.reservedCapital(), 30e18);
        assertEq(pool.availableCapital(), 70e18);
        assertEq(pool.maxWithdraw(alice), 70e18);
    }

    function test_ActiveExposureBlocksAvailabilityAndLossReducesNav() public {
        _deposit(alice, 100e18);

        vm.startPrank(riskManager);
        pool.increaseActiveExposure(60e18);
        pool.recordRealizedLoss(25e18);
        vm.stopPrank();

        assertEq(pool.activeExposure(), 35e18);
        assertEq(pool.realizedLosses(), 25e18);
        assertEq(pool.totalAssets(), 75e18);
        assertEq(pool.availableCapital(), 40e18);
        assertEq(pool.previewRedeem(100e18), 75e18);
    }

    function test_BucketReserveDeployRepayAndLossAccounting() public {
        _deposit(alice, 100e18);

        vm.startPrank(riskManager);
        pool.reserveCapitalForBucket(bucketId, 70e18);
        pool.deployReservedCapitalForBucket(bucketId, riskManager, 50e18);
        vm.stopPrank();

        ISeniorCapitalPool.PoolBucketAccounting memory accounting = pool.bucketAccounting(bucketId);
        assertEq(accounting.reservedCapital, 20e18);
        assertEq(accounting.activeExposure, 50e18);
        assertEq(pool.reservedCapital(), 20e18);
        assertEq(pool.activeExposure(), 50e18);
        assertEq(pool.totalAssets(), 100e18);
        assertEq(pool.availableCapital(), 30e18);
        assertEq(eveUSDC.balanceOf(riskManager), 50e18);

        vm.startPrank(riskManager);
        eveUSDC.approve(address(pool), 15e18);
        pool.repayActiveExposureForBucket(bucketId, 15e18);
        pool.recordRealizedLossForBucket(bucketId, 10e18);
        vm.stopPrank();

        accounting = pool.bucketAccounting(bucketId);
        assertEq(accounting.reservedCapital, 20e18);
        assertEq(accounting.activeExposure, 25e18);
        assertEq(accounting.realizedLosses, 10e18);
        assertEq(pool.activeExposure(), 25e18);
        assertEq(pool.realizedLosses(), 10e18);
        assertEq(pool.totalAssets(), 90e18);
        assertEq(pool.availableCapital(), 45e18);
    }

    function test_BucketAccountingGuardsAccessAndBalances() public {
        _deposit(alice, 100e18);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ISeniorCapitalPool.NotRiskManager.selector, alice));
        pool.reserveCapitalForBucket(bucketId, 1e18);

        vm.startPrank(riskManager);
        pool.reserveCapitalForBucket(bucketId, 10e18);
        vm.expectRevert(abi.encodeWithSelector(ISeniorCapitalPool.InsufficientReservedCapital.selector, 11e18, 10e18));
        pool.deployReservedCapitalForBucket(bucketId, riskManager, 11e18);
        pool.deployReservedCapitalForBucket(bucketId, riskManager, 10e18);
        vm.expectRevert(abi.encodeWithSelector(ISeniorCapitalPool.InsufficientActiveExposure.selector, 11e18, 10e18));
        pool.recordRealizedLossForBucket(bucketId, 11e18);
        vm.stopPrank();
    }

    function test_RecoveryAndInsuranceAllocationsReduceNavAndAvailability() public {
        _deposit(alice, 100e18);

        vm.startPrank(riskManager);
        pool.allocateRecovery(15e18);
        pool.allocateInsurance(10e18);
        vm.stopPrank();

        assertEq(pool.recoveryAllocation(), 15e18);
        assertEq(pool.insuranceAllocation(), 10e18);
        assertEq(pool.totalAssets(), 75e18);
        assertEq(pool.availableCapital(), 75e18);
        assertEq(pool.previewRedeem(100e18), 75e18);
    }

    function test_ReleasingRecoveryAndInsuranceAllocationsRestoresNav() public {
        _deposit(alice, 100e18);

        vm.startPrank(riskManager);
        pool.allocateRecovery(15e18);
        pool.allocateInsurance(10e18);
        pool.releaseRecoveryAllocation(5e18);
        pool.releaseInsuranceAllocation(4e18);
        vm.stopPrank();

        assertEq(pool.recoveryAllocation(), 10e18);
        assertEq(pool.insuranceAllocation(), 6e18);
        assertEq(pool.totalAssets(), 84e18);
        assertEq(pool.availableCapital(), 84e18);
    }

    function test_RevertWhen_NonRiskManagerUsesAccountingHooks() public {
        _deposit(alice, 100e18);

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(ISeniorCapitalPool.NotRiskManager.selector, alice));
        pool.reserveCapital(1);
        vm.expectRevert(abi.encodeWithSelector(ISeniorCapitalPool.NotRiskManager.selector, alice));
        pool.increaseActiveExposure(1);
        vm.expectRevert(abi.encodeWithSelector(ISeniorCapitalPool.NotRiskManager.selector, alice));
        pool.allocateRecovery(1);
        vm.expectRevert(abi.encodeWithSelector(ISeniorCapitalPool.NotRiskManager.selector, alice));
        pool.allocateInsurance(1);
        vm.expectRevert(abi.encodeWithSelector(ISeniorCapitalPool.NotRiskManager.selector, alice));
        pool.recordRealizedLoss(1);
        vm.stopPrank();
    }

    function test_OwnerCanSetRiskManager() public {
        address nextRiskManager = address(new MockRiskManager());

        vm.prank(owner);
        pool.setRiskManager(nextRiskManager);

        assertEq(pool.riskManager(), nextRiskManager);
    }

    function test_RevertWhen_NonOwnerSetsRiskManager() public {
        address nextRiskManager = address(new MockRiskManager());

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ISeniorCapitalPool.NotOwner.selector, alice));
        pool.setRiskManager(nextRiskManager);
    }

    function test_RevertWhen_NotifyRevenueUsesNonAssetToken() public {
        _deposit(alice, 100e18);

        vm.prank(sponsor);
        vm.expectRevert(abi.encodeWithSelector(ISeniorCapitalPool.InvalidRevenueAsset.selector, address(usdc)));
        pool.notifyRevenue(address(usdc), 1);
    }

    function test_RevertWhen_RevenueArrivesBeforeBootstrap() public {
        _seedEveUSDC(sponsor, 1e18);

        vm.startPrank(sponsor);
        eveUSDC.approve(address(pool), 1e18);
        vm.expectRevert(ISeniorCapitalPool.PoolUninitialized.selector);
        pool.notifyRevenue(1e18);
        vm.stopPrank();
    }

    function test_PreBootstrapDonationBlocksDepositsUntilOwnerRecovers() public {
        _seedEveUSDC(sponsor, 3e18);
        vm.prank(sponsor);
        eveUSDC.transfer(address(pool), 3e18);

        _seedEveUSDC(alice, 1e18);

        vm.startPrank(alice);
        eveUSDC.approve(address(pool), 1e18);
        vm.expectRevert(abi.encodeWithSelector(ISeniorCapitalPool.PreBootstrapAssetsPresent.selector, 3e18));
        pool.deposit(1e18, alice);
        vm.stopPrank();

        vm.prank(owner);
        uint256 recovered = pool.recoverPreBootstrapAssets(liquidReceiver);

        assertEq(recovered, 3e18);
        assertEq(eveUSDC.balanceOf(liquidReceiver), 3e18);

        vm.prank(alice);
        pool.deposit(1e18, alice);

        assertEq(pool.balanceOf(alice), 1e18);
    }

    function test_RevertWhen_RecoverPreBootstrapAssetsAfterOperationalAccounting() public {
        _deposit(alice, 100e18);

        vm.prank(riskManager);
        pool.allocateInsurance(10e18);

        vm.prank(alice);
        pool.redeem(100e18, alice, alice);

        vm.prank(owner);
        vm.expectRevert(ISeniorCapitalPool.OutstandingPoolAccounting.selector);
        pool.recoverPreBootstrapAssets(receiver);
    }

    function test_RevertWhen_WithdrawExceedsAllowance() public {
        _deposit(alice, 100e18);

        vm.prank(alice);
        pool.approve(bob, 9e18);

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(ISeniorCapitalPool.InsufficientAllowance.selector, bob, alice, 10e18, 9e18)
        );
        pool.withdraw(10e18, receiver, alice);
    }

    function test_RevertWhen_DepositExceedsAllowance() public {
        _seedEveUSDC(alice, 100e18);

        vm.startPrank(alice);
        eveUSDC.approve(address(pool), 99e18);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(pool), 99e18, 100e18)
        );
        pool.deposit(100e18, alice);
        vm.stopPrank();
    }

    function _deposit(address account, uint256 assets) internal returns (uint256 shares) {
        _seedEveUSDC(account, assets);

        vm.startPrank(account);
        eveUSDC.approve(address(pool), assets);
        shares = pool.deposit(assets, account);
        vm.stopPrank();
    }

    function _sponsorRevenue(uint256 assets) internal {
        _seedEveUSDC(sponsor, assets);

        vm.startPrank(sponsor);
        eveUSDC.approve(address(pool), assets);
        pool.sponsorAssetRevenue(assets);
        vm.stopPrank();
    }

    function _seedEveUSDC(address account, uint256 assets) internal {
        _prefundAndMint(account, assets);
    }
}
