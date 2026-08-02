// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISEveUSDCLending} from "../../src/interfaces/ISEveUSDCLending.sol";

import {LendingTestBase} from "../helpers/LendingTestBase.sol";

contract LendingDefaultPropertiesTest is LendingTestBase {
    /// @dev Feature: seveusdc-maker-lending, Property 7: Default Detection Correctness
    function testFuzz_DefaultDetectionCorrectness(uint128 depositSeed, uint128 collateralSeed, uint128 borrowSeed)
        public
    {
        uint256 depositAssets = bound(uint256(depositSeed), 100, 1_000_000e6);
        uint256 aliceShares = _depositAndApproveShares(alice, depositAssets);
        uint256 bobShares = _depositAndApproveShares(bob, depositAssets);
        uint256 aliceCollateral = bound(uint256(collateralSeed), 3, aliceShares);
        uint256 bobCollateral = bound(uint256(collateralSeed), 3, bobShares);
        uint256 aliceBorrow = bound(uint256(borrowSeed), 1, lending.maxBorrowForShares(aliceCollateral));
        uint256 bobBorrow = bound(uint256(borrowSeed), 1, lending.maxBorrowForShares(bobCollateral));

        uint256 repaidLoanId = _directBorrow(alice, aliceCollateral, 2 days, aliceBorrow, alice);
        _seedDebtAndApprove(alice, _loanDebt(repaidLoanId));
        _directRepay(alice, repaidLoanId, false, alice);
        assertFalse(lending.isDefaulted(repaidLoanId));

        uint256 defaultedLoanId = _directBorrow(bob, bobCollateral, 2 days, bobBorrow, bob);
        assertFalse(lending.isDefaulted(defaultedLoanId));

        vm.warp(block.timestamp + 2 days + lending.loanState(defaultedLoanId).gracePeriodSecondsSnapshot);
        assertFalse(lending.isDefaulted(defaultedLoanId));

        vm.warp(block.timestamp + 1);
        assertTrue(lending.isDefaulted(defaultedLoanId));

        _recoverLoan(carol, defaultedLoanId);
        assertFalse(lending.isDefaulted(defaultedLoanId));
    }

    /// @dev Feature: seveusdc-maker-lending, Property 8: Default Recovery Accounting
    function testFuzz_DefaultRecoveryAccounting(
        uint128 depositSeed,
        uint128 collateralSeed,
        uint128 borrowSeed,
        uint128 revenueSeed,
        bool induceLoss
    ) public {
        uint256 depositAssets = bound(uint256(depositSeed), 1_000e6, 1_000_000e6);

        if (induceLoss) {
            vm.prank(owner);
            vault.setAumFeeBps(10_000);
            _setLendingConfig(9_500, 0, 0, 1 days, 400 days, 1 days);
        } else {
            vm.prank(owner);
            vault.setAumFeeBps(0);
            _setLendingConfig(9_500, 0, 0, 1 days, 30 days, 1 days);
        }

        uint256 mintedShares = _depositAndApproveShares(alice, depositAssets);
        uint256 collateralCap = induceLoss ? mintedShares / 4 : mintedShares / 2;
        uint256 collateralShares = bound(uint256(collateralSeed), 3, collateralCap);
        uint256 borrowAmount = induceLoss
            ? lending.maxBorrowForShares(collateralShares)
            : bound(uint256(borrowSeed), 1, lending.maxBorrowForShares(collateralShares));
        uint256 durationSeconds = induceLoss ? 365 days : 2 days;

        uint256 loanId = _directBorrow(alice, collateralShares, durationSeconds, borrowAmount, alice);

        if (!induceLoss) {
            _notifyRevenue(bound(uint256(revenueSeed), 1, 100_000e6));
        }

        vm.warp(block.timestamp + durationSeconds + lending.loanState(loanId).gracePeriodSecondsSnapshot + 1);

        uint256 debtPrincipal = _loanDebt(loanId);
        uint256 onHandBeforeRecovery = eveUSDC.balanceOf(address(vault));
        (uint256 previewFeeAssets,) = vault.previewAccruedAum();
        uint256 onHandAfterAccrual = onHandBeforeRecovery - previewFeeAssets;
        uint256 recovered = vault.previewRedeem(collateralShares);
        uint256 expectedLoss = recovered >= debtPrincipal ? 0 : debtPrincipal - recovered;
        vm.assume(expectedLoss <= onHandAfterAccrual);
        uint256 expectedTotalAssets = onHandAfterAccrual - expectedLoss;

        _recoverLoan(receiver, loanId);

        ISEveUSDCLending.Loan memory loan = lending.loanState(loanId);
        assertTrue(loan.defaultResolved);
        assertEq(lending.outstandingPrincipal(), 0);
        assertEq(vault.outstandingPrincipal(), 0);
        assertEq(vault.recognizedLosses(), expectedLoss);
        assertEq(vault.totalAssets(), _managedAssets(vault));
        assertEq(vault.totalAssets(), expectedTotalAssets);
    }
}
