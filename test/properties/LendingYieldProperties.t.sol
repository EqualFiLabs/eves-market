// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Math} from "../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {ISEveUSDCLending} from "../../src/interfaces/ISEveUSDCLending.sol";

import {LendingTestBase} from "../helpers/LendingTestBase.sol";

contract LendingYieldPropertiesTest is LendingTestBase {
    /// @dev Feature: seveusdc-maker-lending, Property 16: Yield Preservation During Loan
    function testFuzz_YieldPreservationDuringLoan(
        uint128 depositSeed,
        uint128 collateralSeed,
        uint128 borrowSeed,
        uint128 revenueSeed
    ) public {
        uint256 depositAssets = bound(uint256(depositSeed), 10e6, 1_000_000e6);
        uint256 mintedShares = _depositAndApproveShares(alice, depositAssets);
        uint256 collateralShares = bound(uint256(collateralSeed), 1e6, mintedShares);
        uint256 borrowAmount = bound(uint256(borrowSeed), 1, lending.maxBorrowForShares(collateralShares));
        uint256 revenueMin = Math.ceilDiv(vault.totalSupply(), collateralShares);
        uint256 revenueAssets = bound(uint256(revenueSeed), revenueMin, 1_000_000e6);

        uint256 loanId = _directBorrow(alice, collateralShares, 14 days, borrowAmount, alice);
        uint256 assetsBefore = vault.convertToAssets(collateralShares);

        _notifyRevenue(revenueAssets);

        assertFalse(lending.loanState(loanId).repaid);
        assertFalse(lending.loanState(loanId).defaultResolved);
        assertGt(vault.convertToAssets(collateralShares), assetsBefore);
    }
}
