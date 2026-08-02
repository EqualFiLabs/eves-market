// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISEveUSDCLending} from "../../src/interfaces/ISEveUSDCLending.sol";

import {LendingTestBase} from "../helpers/LendingTestBase.sol";

contract LendingInvariantPropertiesTest is LendingTestBase {
    /// @dev Feature: seveusdc-maker-lending, Property 13: Collateral Escrow Invariant
    function testFuzz_CollateralEscrowInvariant(uint128 aliceSeed, uint128 bobSeed, uint128 carolSeed) public {
        uint256 aliceShares = _depositAndApproveShares(alice, bound(uint256(aliceSeed), 100, 1_000_000e6));
        uint256 bobShares = _depositAndApproveShares(bob, bound(uint256(bobSeed), 100, 1_000_000e6));
        uint256 carolShares = _depositAndApproveShares(carol, bound(uint256(carolSeed), 100, 1_000_000e6));

        uint256 aliceLoanId =
            _directBorrow(alice, aliceShares / 2, 7 days, lending.maxBorrowForShares(aliceShares / 2) / 2, alice);
        uint256 bobLoanId =
            _directBorrow(bob, bobShares / 3, 7 days, lending.maxBorrowForShares(bobShares / 3) / 2, bob);
        _directBorrow(carol, carolShares / 4, 7 days, lending.maxBorrowForShares(carolShares / 4) / 2, carol);

        _seedDebtAndApprove(alice, _loanDebt(aliceLoanId));
        _directRepay(alice, aliceLoanId, false, alice);

        vm.warp(block.timestamp + 8 days + DEFAULT_GRACE_PERIOD);
        _recoverLoan(receiver, bobLoanId);

        assertGe(vault.balanceOf(address(lending)), _sumActiveCollateralShares());
    }

    /// @dev Feature: seveusdc-maker-lending, Property 14: Loan State Exclusivity
    function testFuzz_LoanStateExclusivity(uint128 depositSeed, uint128 collateralSeed, uint128 borrowSeed) public {
        uint256 depositAssets = bound(uint256(depositSeed), 1_000e6, 1_000_000e6);
        uint256 aliceShares = _depositAndApproveShares(alice, depositAssets);
        uint256 bobShares = _depositAndApproveShares(bob, depositAssets);

        uint256 aliceCollateral = bound(uint256(collateralSeed), 3, aliceShares / 2);
        uint256 bobCollateral = bound(uint256(collateralSeed), 3, bobShares / 2);
        uint256 aliceLoanId = _directBorrow(
            alice,
            aliceCollateral,
            2 days,
            bound(uint256(borrowSeed), 1, lending.maxBorrowForShares(aliceCollateral)),
            alice
        );
        uint256 bobLoanId = _directBorrow(
            bob, bobCollateral, 2 days, bound(uint256(borrowSeed), 1, lending.maxBorrowForShares(bobCollateral)), bob
        );

        _seedDebtAndApprove(alice, _loanDebt(aliceLoanId));
        _directRepay(alice, aliceLoanId, false, alice);

        vm.warp(block.timestamp + 4 days);
        _recoverLoan(receiver, bobLoanId);

        for (uint256 loanId = 1; loanId < lending.nextLoanId(); ++loanId) {
            ISEveUSDCLending.Loan memory loan = lending.loanState(loanId);
            assertFalse(loan.repaid && loan.defaultResolved);
        }
    }

    /// @dev Feature: seveusdc-maker-lending, Property 15: Outstanding Principal Sum Invariant
    function testFuzz_OutstandingPrincipalSumInvariant(uint128 aliceSeed, uint128 bobSeed, uint128 carolSeed) public {
        uint256 aliceShares = _depositAndApproveShares(alice, bound(uint256(aliceSeed), 1_000e6, 1_000_000e6));
        uint256 bobShares = _depositAndApproveShares(bob, bound(uint256(bobSeed), 1_000e6, 1_000_000e6));
        uint256 carolShares = _depositAndApproveShares(carol, bound(uint256(carolSeed), 1_000e6, 1_000_000e6));

        uint256 aliceLoanId =
            _directBorrow(alice, aliceShares / 4, 7 days, lending.maxBorrowForShares(aliceShares / 4) / 2, alice);
        uint256 bobLoanId =
            _directBorrow(bob, bobShares / 4, 7 days, lending.maxBorrowForShares(bobShares / 4) / 2, bob);
        _directBorrow(carol, carolShares / 4, 7 days, lending.maxBorrowForShares(carolShares / 4) / 2, carol);

        _seedDebtAndApprove(alice, _loanDebt(aliceLoanId));
        _directRepay(alice, aliceLoanId, false, alice);

        vm.warp(block.timestamp + 8 days + DEFAULT_GRACE_PERIOD);
        _recoverLoan(receiver, bobLoanId);

        uint256 expectedOutstanding = _sumActiveDebtPrincipal();
        assertEq(lending.outstandingPrincipal(), expectedOutstanding);
        assertEq(vault.outstandingPrincipal(), expectedOutstanding);
    }
}
