// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Math} from "../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {ISEveUSDCLending} from "../../src/interfaces/ISEveUSDCLending.sol";

import {LendingTestBase} from "../helpers/LendingTestBase.sol";

contract LendingPreviewPropertiesTest is LendingTestBase {
    /// @dev Feature: seveusdc-maker-lending, Property 12: Preview Consistency
    function testFuzz_PreviewConsistency(
        uint128 depositSeed,
        uint128 collateralSeed,
        uint128 borrowSeed,
        uint32 durationSeed
    ) public {
        ISEveUSDCLending.LendingConfig memory cfg = _config();
        uint256 depositAssets = bound(uint256(depositSeed), 100, 1_000_000e6);
        uint256 mintedShares = _depositAndApproveShares(alice, depositAssets);
        uint256 collateralShares = bound(uint256(collateralSeed), 3, mintedShares);
        uint256 borrowAmount = bound(uint256(borrowSeed), 1, lending.maxBorrowForShares(collateralShares));
        uint256 durationSeconds = bound(uint256(durationSeed), cfg.minDurationSeconds, cfg.maxDurationSeconds);

        (uint256 previewDebtPrincipal, uint256 previewOriginationFee) =
            lending.previewBorrowTerms(collateralShares, borrowAmount);
        uint256 actualMaxBorrow = lending.maxBorrowForShares(collateralShares);
        uint256 expectedMaxBorrow = Math.mulDiv(vault.convertToAssets(collateralShares), cfg.maxLtvBps, 10_000);

        uint256 loanId = _directBorrow(alice, collateralShares, durationSeconds, borrowAmount, receiver);
        ISEveUSDCLending.Loan memory loan = lending.loanState(loanId);

        assertEq(previewDebtPrincipal, loan.debtPrincipal);
        assertEq(previewOriginationFee, loan.originationFeeCharged);
        assertEq(lending.previewRequiredRepayment(loanId), loan.debtPrincipal);
        assertEq(actualMaxBorrow, expectedMaxBorrow);
    }
}
