// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISEveUSDCLending} from "../../src/interfaces/ISEveUSDCLending.sol";

import {LendingTestBase} from "../helpers/LendingTestBase.sol";

contract BorrowForExtensionTest is LendingTestBase {
    function test_ApprovedRouterCanCallBorrowFor() public {
        uint256 collateralShares = 300e6;
        uint256 borrowAmount = 200e6;
        uint256 durationSeconds = 10 days;

        _depositAndApproveShares(approvedRouter, 500e6);
        _setApprovedRouter(approvedRouter, true);

        uint256 loanId = _delegatedBorrow(
            approvedRouter, collateralShares, durationSeconds, borrowAmount, delegatedRecipient, alice
        );

        ISEveUSDCLending.Loan memory loan = lending.loanState(loanId);
        assertEq(loan.borrower, alice);
        assertEq(loan.collateralShares, collateralShares);
        assertEq(loan.debtPrincipal, borrowAmount);
        assertEq(vault.balanceOf(address(lending)), collateralShares);
        assertEq(vault.balanceOf(approvedRouter), 200e6);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(eveUSDC.balanceOf(delegatedRecipient), loan.netBorrowed);
    }

    function test_ApprovedRouterCanCallRepayFor() public {
        uint256 collateralShares = 300e6;
        uint256 borrowAmount = 200e6;

        _depositAndApproveShares(approvedRouter, 500e6);
        _setApprovedRouter(approvedRouter, true);

        uint256 loanId = _delegatedBorrow(approvedRouter, collateralShares, 10 days, borrowAmount, receiver, alice);
        uint256 debtPrincipal = _loanDebt(loanId);

        _seedDebtAndApprove(approvedRouter, debtPrincipal);
        _delegatedRepay(approvedRouter, loanId, false, receiver);

        ISEveUSDCLending.Loan memory loan = lending.loanState(loanId);
        assertTrue(loan.repaid);
        assertEq(vault.balanceOf(alice), collateralShares);
        assertEq(vault.balanceOf(address(lending)), 0);
        assertEq(lending.outstandingPrincipal(), 0);
    }

    function test_RevertWhen_UnapprovedCallerUsesDelegatedPaths() public {
        _depositAndApproveShares(approvedRouter, 500e6);

        vm.prank(approvedRouter);
        vm.expectRevert(abi.encodeWithSelector(ISEveUSDCLending.NotApprovedRouter.selector, approvedRouter));
        lending.borrowFor(300e6, 10 days, 200e6, delegatedRecipient, alice);

        _depositAndApproveShares(alice, 500e6);
        uint256 loanId = _directBorrow(alice, 200e6, 7 days, 100e6, alice);
        _seedDebtAndApprove(approvedRouter, _loanDebt(loanId));

        vm.prank(approvedRouter);
        vm.expectRevert(abi.encodeWithSelector(ISEveUSDCLending.NotApprovedRouter.selector, approvedRouter));
        lending.repayFor(loanId, false, receiver);
    }

    function test_DelegatedRepaymentReturnsSharesToBorrowerOrAssetsToRecipient() public {
        uint256 collateralShares = 300e6;
        uint256 borrowAmount = 200e6;

        _depositAndApproveShares(approvedRouter, 1_000e6);
        _setApprovedRouter(approvedRouter, true);

        uint256 shareLoanId =
            _delegatedBorrow(approvedRouter, collateralShares, 10 days, borrowAmount, delegatedRecipient, alice);
        _seedDebtAndApprove(approvedRouter, _loanDebt(shareLoanId));
        _delegatedRepay(approvedRouter, shareLoanId, false, receiver);

        assertEq(vault.balanceOf(alice), collateralShares);

        uint256 redeemLoanId =
            _delegatedBorrow(approvedRouter, collateralShares, 10 days, borrowAmount, delegatedRecipient, alice);
        _notifyRevenue(60e6);

        uint256 expectedAssetsOut = vault.previewRedeem(collateralShares);
        _seedDebtAndApprove(approvedRouter, _loanDebt(redeemLoanId));

        uint256 receiverBefore = eveUSDC.balanceOf(receiver);
        _delegatedRepay(approvedRouter, redeemLoanId, true, receiver);

        assertEq(eveUSDC.balanceOf(receiver) - receiverBefore, expectedAssetsOut);
        assertEq(vault.balanceOf(address(lending)), 0);
        assertEq(vault.balanceOf(alice), collateralShares);
    }
}
