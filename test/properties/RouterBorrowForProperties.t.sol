// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISEveUSDCLending} from "../../src/interfaces/ISEveUSDCLending.sol";

import {RouterTestBase} from "../helpers/RouterTestBase.sol";

contract RouterBorrowForPropertiesTest is RouterTestBase {
    /// @dev Feature: maker-lending-router, Property 1: borrowFor Creates Loan Attributed to onBehalfOf
    function testFuzz_BorrowForCreatesLoanAttributedToOnBehalfOf(
        uint128 depositSeed,
        uint128 collateralSeed,
        uint128 borrowSeed,
        uint32 durationSeed
    ) public {
        uint256 depositAssets = bound(uint256(depositSeed), 10 * USDC_UNIT, 1_000_000e6);
        uint256 routerShares = _seedRouterShares(depositAssets);
        uint256 collateralShares = bound(uint256(collateralSeed), 2 * USDC_UNIT, routerShares);
        uint256 maxBorrow = lending.maxBorrowForShares(collateralShares);
        vm.assume(maxBorrow >= USDC_UNIT);

        uint256 borrowAmount = _boundBorrow(uint256(borrowSeed), maxBorrow);
        uint256 durationSeconds = bound(uint256(durationSeed), DEFAULT_MIN_DURATION, DEFAULT_MAX_DURATION);

        uint256 receiverBefore = eveUSDC.balanceOf(routerReceiver);
        uint256 loanId = _routerBorrowFor(collateralShares, durationSeconds, borrowAmount, routerReceiver, borrower);

        ISEveUSDCLending.Loan memory loan = _loanState(loanId);
        assertEq(loan.borrower, borrower);
        assertEq(uint256(loan.collateralShares), collateralShares);
        assertEq(uint256(loan.debtPrincipal), borrowAmount);
        assertEq(vault.balanceOf(address(lending)), collateralShares);
        assertEq(vault.balanceOf(address(router)), routerShares - collateralShares);
        assertEq(eveUSDC.balanceOf(routerReceiver) - receiverBefore, uint256(loan.netBorrowed));
    }

    /// @dev Feature: maker-lending-router, Property 2: repayFor Access Control
    function testFuzz_RepayForAccessControl(uint128 depositSeed, uint128 collateralSeed, uint128 borrowSeed) public {
        uint256 depositAssets = bound(uint256(depositSeed), 10 * USDC_UNIT, 1_000_000e6);
        uint256 routerShares = _seedRouterShares(depositAssets);
        uint256 collateralShares = bound(uint256(collateralSeed), 2 * USDC_UNIT, routerShares);
        uint256 maxBorrow = lending.maxBorrowForShares(collateralShares);
        vm.assume(maxBorrow >= USDC_UNIT);

        uint256 borrowAmount = _boundBorrow(uint256(borrowSeed), maxBorrow);
        uint256 loanId = _routerBorrowFor(collateralShares, 7 days, borrowAmount, routerReceiver, borrower);
        uint256 repaymentAmount = _loanDebt(loanId);

        _seedEveUSDC(outsider, repaymentAmount);
        vm.prank(outsider);
        eveUSDC.approve(address(lending), type(uint256).max);

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(ISEveUSDCLending.NotApprovedRouter.selector, outsider));
        lending.repayFor(loanId, false, address(0));

        _seedRouterDebtAndApprove(repaymentAmount);
        _routerRepayFor(loanId, false, address(0));

        assertTrue(_loanState(loanId).repaid);
        assertEq(vault.balanceOf(borrower), collateralShares);
        assertEq(vault.balanceOf(address(lending)), 0);
    }
}
