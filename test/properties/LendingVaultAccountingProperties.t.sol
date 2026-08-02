// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISEveUSDCLending} from "../../src/interfaces/ISEveUSDCLending.sol";
import {ISEveUSDCVaultLending} from "../../src/interfaces/ISEveUSDCVaultLending.sol";

import {LendingTestBase} from "../helpers/LendingTestBase.sol";

contract LendingVaultAccountingPropertiesTest is LendingTestBase {
    /// @dev Feature: seveusdc-maker-lending, Property 9: Managed-Assets Invariant
    function testFuzz_ManagedAssetsInvariant(
        uint128 depositSeed,
        uint128 debtSeed,
        uint128 feeSeed,
        uint128 lossSeed,
        bool resolveAsDefault
    ) public {
        uint256 depositAssets = bound(uint256(depositSeed), 1, 1_000_000e6);
        _depositSeeded(alice, depositAssets, alice);
        _setLendingContract(address(this));

        uint256 debtPrincipal = bound(uint256(debtSeed), 1, depositAssets);
        uint256 feeAmount = bound(uint256(feeSeed), 0, debtPrincipal);
        uint256 borrowAmount = debtPrincipal - feeAmount;

        vault.reportLoan(debtPrincipal);
        vault.disburseLoan(receiver, borrowAmount, feeAmount);

        assertEq(vault.totalAssets(), _managedAssets(vault));
        assertEq(vault.totalAssets(), depositAssets);

        if (resolveAsDefault) {
            uint256 recognizedLoss = bound(uint256(lossSeed), 0, debtPrincipal);

            // Synthetic accounting shortcut: restore debt cash to the vault, then
            // recognize a loss amount to cover the default-bookkeeping branch.
            _seedEveUSDC(address(this), debtPrincipal);
            eveUSDC.transfer(address(vault), debtPrincipal);
            vault.reportDefault(debtPrincipal, recognizedLoss);

            assertEq(vault.outstandingPrincipal(), 0);
            assertEq(vault.recognizedLosses(), recognizedLoss);
            assertEq(vault.totalAssets(), _managedAssets(vault));
            assertEq(vault.totalAssets(), depositAssets - recognizedLoss);
        } else {
            _seedEveUSDC(address(this), debtPrincipal);
            eveUSDC.transfer(address(vault), debtPrincipal);
            vault.reportRepayment(debtPrincipal);

            assertEq(vault.outstandingPrincipal(), 0);
            assertEq(vault.recognizedLosses(), 0);
            assertEq(vault.totalAssets(), _managedAssets(vault));
            assertEq(vault.totalAssets(), depositAssets);
        }
    }

    /// @dev Feature: seveusdc-maker-lending, Property 10: Self-Borrow Isolation Invariant
    function testFuzz_SelfBorrowIsolationInvariant(
        uint128 aliceDepositSeed,
        uint128 bobDepositSeed,
        uint128 collateralSeed,
        uint128 borrowSeed
    ) public {
        uint256 aliceAssets = bound(uint256(aliceDepositSeed), 100, 1_000_000e6);
        uint256 bobAssets = bound(uint256(bobDepositSeed), 100, 1_000_000e6);

        uint256 aliceShares = _depositAndApproveShares(alice, aliceAssets);
        uint256 bobShares = _depositAndApproveShares(bob, bobAssets);
        uint256 collateralShares = bound(uint256(collateralSeed), 3, aliceShares);
        uint256 borrowAmount = bound(uint256(borrowSeed), 1, lending.maxBorrowForShares(collateralShares));
        uint256 bobPreviewBefore = vault.previewRedeem(bobShares);
        uint256 totalSupplyBefore = eveUSDC.totalSupply();

        uint256 loanId = _directBorrow(alice, collateralShares, 7 days, borrowAmount, receiver);

        ISEveUSDCLending.Loan memory loan = lending.loanState(loanId);
        assertEq(loan.borrower, alice);
        assertEq(vault.balanceOf(address(lending)), collateralShares);
        assertEq(vault.balanceOf(bob), bobShares);
        assertGe(vault.previewRedeem(bobShares), bobPreviewBefore);
        assertEq(eveUSDC.totalSupply(), totalSupplyBefore);
    }

    /// @dev Feature: seveusdc-maker-lending, Property 11: Share Price Invariance on Borrow and Repay
    function testFuzz_SharePriceInvarianceOnBorrowAndRepay(
        uint128 depositSeed,
        uint128 revenueSeed,
        uint128 debtSeed,
        uint128 feeSeed,
        uint128 probeSeed
    ) public {
        uint256 depositAssets = bound(uint256(depositSeed), 2, 1_000_000e6);
        uint256 revenueAssets = bound(uint256(revenueSeed), 1, 1_000_000e6);

        uint256 aliceShares = _depositSeeded(alice, depositAssets, alice);
        _notifyRevenue(revenueAssets);
        _setLendingContract(address(this));

        uint256 probeShares = bound(uint256(probeSeed), 1, aliceShares);
        uint256 assetsBefore = vault.previewRedeem(probeShares);

        uint256 debtPrincipal = bound(uint256(debtSeed), 1, eveUSDC.balanceOf(address(vault)));
        uint256 feeAmount = bound(uint256(feeSeed), 0, debtPrincipal);
        uint256 borrowAmount = debtPrincipal - feeAmount;

        vault.reportLoan(debtPrincipal);
        vault.disburseLoan(receiver, borrowAmount, feeAmount);

        assertEq(vault.previewRedeem(probeShares), assetsBefore);

        _seedEveUSDC(address(this), debtPrincipal);
        eveUSDC.transfer(address(vault), debtPrincipal);
        vault.reportRepayment(debtPrincipal);

        assertEq(vault.previewRedeem(probeShares), assetsBefore);
    }

    /// @dev Feature: seveusdc-maker-lending, Property 17: Vault Report and Disbursement Access Control
    function testFuzz_VaultReportAndDisbursementAccessControl(address caller, uint128 debtSeed, uint128 feeSeed)
        public
    {
        vm.assume(caller != address(0) && caller != address(this));

        _setLendingContract(address(this));

        uint256 debtPrincipal = bound(uint256(debtSeed), 1, 1_000_000e6);
        uint256 feeAmount = bound(uint256(feeSeed), 0, debtPrincipal);

        vm.startPrank(caller);

        vm.expectRevert(abi.encodeWithSelector(ISEveUSDCVaultLending.NotLendingContract.selector, caller));
        vault.reportLoan(debtPrincipal);

        vm.expectRevert(abi.encodeWithSelector(ISEveUSDCVaultLending.NotLendingContract.selector, caller));
        vault.reportRepayment(debtPrincipal);

        vm.expectRevert(abi.encodeWithSelector(ISEveUSDCVaultLending.NotLendingContract.selector, caller));
        vault.reportDefault(debtPrincipal, feeAmount);

        vm.expectRevert(abi.encodeWithSelector(ISEveUSDCVaultLending.NotLendingContract.selector, caller));
        vault.disburseLoan(receiver, debtPrincipal - feeAmount, feeAmount);

        vm.stopPrank();
    }
}
