// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {LendingTestBase} from "../helpers/LendingTestBase.sol";

contract LendingIntegrationTest is LendingTestBase {
    function test_FullLifecycleWithRealVaultEveUsdcAndLending() public {
        uint256 aliceShares = _depositAndApproveShares(alice, 1_000e6);
        uint256 loanId = _directBorrow(alice, 400e6, 14 days, 300e6, receiver);
        uint256 originationFee = uint256(300e6) * DEFAULT_ORIGINATION_FEE_BPS / 10_000;
        uint256 retainedOriginationFee = _retainedFeeShare(originationFee);

        assertEq(vault.totalAssets(), 1_000e6 + retainedOriginationFee);
        assertEq(vault.balanceOf(address(lending)), 400e6);
        assertEq(vault.balanceOf(alice), aliceShares - 400e6);
        assertEq(eveUSDC.balanceOf(receiver), _netBorrowed(300e6, originationFee));
        assertEq(lending.outstandingPrincipal(), _loanDebt(loanId));
        assertEq(vault.totalAssets(), _managedAssets(vault));

        _notifyRevenue(100e6);

        uint256 extensionFee = _loanExtensionFee(loanId);
        uint256 retainedExtensionFee = _retainedFeeShare(extensionFee);
        _seedEveUSDC(alice, _loanDebt(loanId) + _loanExtensionFee(loanId));
        vm.prank(alice);
        eveUSDC.approve(address(lending), type(uint256).max);
        _extendLoan(alice, loanId, 3 days);
        _directRepay(alice, loanId, false, alice);

        assertTrue(lending.loanState(loanId).repaid);
        assertEq(lending.outstandingPrincipal(), 0);
        assertEq(vault.outstandingPrincipal(), 0);
        assertEq(vault.balanceOf(address(lending)), 0);
        assertEq(vault.balanceOf(alice), aliceShares);
        assertEq(vault.totalAssets(), 1_100e6 + retainedOriginationFee + retainedExtensionFee);
        assertEq(vault.totalAssets(), _managedAssets(vault));
    }

    function test_NonBorrowerCanDepositAndRedeemWhileLoanOutstanding() public {
        _depositAndApproveShares(alice, 1_000e6);
        uint256 loanId = _directBorrow(alice, 400e6, 30 days, 300e6, alice);
        uint256 outstandingBeforeBob = lending.outstandingPrincipal();

        _seedEveUSDC(bob, 500e6);
        _approveAsset(bob, 500e6);

        uint256 expectedBobShares = vault.previewDeposit(500e6);

        vm.prank(bob);
        uint256 bobShares = vault.deposit(500e6, bob);

        assertEq(bobShares, expectedBobShares);
        assertEq(lending.outstandingPrincipal(), outstandingBeforeBob);
        assertEq(vault.totalAssets(), _managedAssets(vault));
        assertFalse(lending.loanState(loanId).repaid);

        uint256 redeemShares = bobShares / 2;
        uint256 expectedAssetsOut = vault.previewRedeem(redeemShares);
        uint256 bobBefore = eveUSDC.balanceOf(bob);

        vm.prank(bob);
        uint256 assetsOut = vault.redeem(redeemShares, bob, bob);

        assertEq(assetsOut, expectedAssetsOut);
        assertEq(eveUSDC.balanceOf(bob) - bobBefore, assetsOut);
        assertEq(lending.outstandingPrincipal(), outstandingBeforeBob);
        assertFalse(lending.loanState(loanId).repaid);
        assertEq(vault.balanceOf(address(lending)), 400e6);
        assertEq(vault.totalAssets(), _managedAssets(vault));
    }

    function test_AumAccrualDuringActiveLoansUsesManagedAssetsModel() public {
        _depositAndApproveShares(alice, 1_000e6);
        uint256 loanId = _directBorrow(alice, 400e6, 30 days, 300e6, alice);

        uint256 managedAssetsBefore = vault.totalAssets();
        uint256 onHandBefore = eveUSDC.balanceOf(address(vault));

        vm.warp(block.timestamp + 30 days);

        uint256 feeRecipientBefore = eveUSDC.balanceOf(feeRecipient);
        uint256 feeAssets = vault.accrueAum();
        uint256 managedModelFee = _theoreticalFeeWad(managedAssetsBefore, vault.aumFeeBps(), 30) / WAD;
        uint256 onHandOnlyFee = _theoreticalFeeWad(onHandBefore, vault.aumFeeBps(), 30) / WAD;

        assertApproxEqAbs(feeAssets, managedModelFee, 1);
        assertGt(feeAssets, onHandOnlyFee);
        assertEq(eveUSDC.balanceOf(feeRecipient) - feeRecipientBefore, feeAssets);
        assertEq(lending.outstandingPrincipal(), _loanDebt(loanId));
        assertEq(vault.totalAssets(), managedAssetsBefore - feeAssets);
        assertEq(vault.totalAssets(), _managedAssets(vault));
    }
}
