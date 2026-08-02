// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISEveUSDCLending} from "../../src/interfaces/ISEveUSDCLending.sol";

import {LendingTestBase} from "../helpers/LendingTestBase.sol";

contract LendingRepayPropertiesTest is LendingTestBase {
    /// @dev Feature: seveusdc-maker-lending, Property 4: Repayment Returns Correct Value
    function testFuzz_RepaymentReturnsCorrectValue(
        uint128 depositSeed,
        uint128 collateralSeed,
        uint128 borrowSeed,
        uint128 revenueSeed,
        bool delegated,
        bool redeemUnderlying
    ) public {
        uint256 depositAssets = bound(uint256(depositSeed), 100, 1_000_000e6);
        uint256 collateralHolder = delegated
            ? _depositAndApproveShares(approvedRouter, depositAssets)
            : _depositAndApproveShares(alice, depositAssets);
        uint256 collateralShares = bound(uint256(collateralSeed), 3, collateralHolder);
        uint256 borrowAmount = bound(uint256(borrowSeed), 1, lending.maxBorrowForShares(collateralShares));
        uint256 revenueAssets = bound(uint256(revenueSeed), 1, 100_000e6);

        if (delegated) {
            _setApprovedRouter(approvedRouter, true);
        }

        uint256 loanId = delegated
            ? _delegatedBorrow(approvedRouter, collateralShares, 7 days, borrowAmount, delegatedRecipient, alice)
            : _directBorrow(alice, collateralShares, 7 days, borrowAmount, alice);

        _notifyRevenue(revenueAssets);

        uint256 debtPrincipal = _loanDebt(loanId);
        uint256 expectedAssetsOut = vault.previewRedeem(collateralShares);
        address payer = delegated ? approvedRouter : alice;
        _seedDebtAndApprove(payer, debtPrincipal);

        uint256 sharesBefore = vault.balanceOf(alice);
        uint256 recipientBefore = eveUSDC.balanceOf(receiver);

        if (delegated) {
            _delegatedRepay(approvedRouter, loanId, redeemUnderlying, receiver);
        } else {
            _directRepay(alice, loanId, redeemUnderlying, receiver);
        }

        ISEveUSDCLending.Loan memory loan = lending.loanState(loanId);
        assertTrue(loan.repaid);
        assertEq(lending.outstandingPrincipal(), 0);

        if (redeemUnderlying) {
            assertEq(eveUSDC.balanceOf(receiver) - recipientBefore, expectedAssetsOut);
            assertEq(vault.balanceOf(alice), sharesBefore);
        } else {
            assertEq(vault.balanceOf(alice), sharesBefore + collateralShares);
        }
    }

    /// @dev Feature: seveusdc-maker-lending, Property 5: Repayment Time Boundary
    function testFuzz_RepaymentTimeBoundary(uint128 depositSeed, uint128 collateralSeed, uint128 borrowSeed) public {
        uint256 depositAssets = bound(uint256(depositSeed), 100, 1_000_000e6);
        uint256 aliceShares = _depositAndApproveShares(alice, depositAssets);
        uint256 bobShares = _depositAndApproveShares(bob, depositAssets);
        uint256 aliceCollateral = bound(uint256(collateralSeed), 3, aliceShares);
        uint256 bobCollateral = bound(uint256(collateralSeed), 3, bobShares);
        uint256 aliceBorrow = bound(uint256(borrowSeed), 1, lending.maxBorrowForShares(aliceCollateral));

        uint256 inWindowLoanId = _directBorrow(alice, aliceCollateral, 3 days, aliceBorrow, alice);
        uint256 debtPrincipal = _loanDebt(inWindowLoanId);
        _seedDebtAndApprove(alice, debtPrincipal);

        vm.warp(block.timestamp + 3 days + lending.loanState(inWindowLoanId).gracePeriodSecondsSnapshot);
        _directRepay(alice, inWindowLoanId, false, alice);
        assertTrue(lending.loanState(inWindowLoanId).repaid);

        uint256 bobBorrow = bound(uint256(borrowSeed), 1, lending.maxBorrowForShares(bobCollateral));
        uint256 expiredLoanId = _directBorrow(bob, bobCollateral, 2 days, bobBorrow, bob);
        _seedDebtAndApprove(bob, _loanDebt(expiredLoanId));

        vm.warp(block.timestamp + 2 days + lending.loanState(expiredLoanId).gracePeriodSecondsSnapshot + 1);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(ISEveUSDCLending.RepaymentWindowExpired.selector, expiredLoanId));
        lending.repay(expiredLoanId, false, bob);
    }
}
