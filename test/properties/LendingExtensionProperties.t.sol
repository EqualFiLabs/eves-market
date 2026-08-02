// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISEveUSDCLending} from "../../src/interfaces/ISEveUSDCLending.sol";

import {LendingTestBase} from "../helpers/LendingTestBase.sol";

contract LendingExtensionPropertiesTest is LendingTestBase {
    /// @dev Feature: seveusdc-maker-lending, Property 6: Extension Arithmetic
    function testFuzz_ExtensionArithmetic(
        uint128 depositSeed,
        uint128 collateralSeed,
        uint128 borrowSeed,
        uint32 durationSeed,
        uint32 extensionSeed
    ) public {
        ISEveUSDCLending.LendingConfig memory cfg = _config();
        uint256 depositAssets = bound(uint256(depositSeed), 100, 1_000_000e6);
        uint256 mintedShares = _depositAndApproveShares(alice, depositAssets);
        uint256 collateralShares = bound(uint256(collateralSeed), 3, mintedShares);
        uint256 durationSeconds = bound(uint256(durationSeed), cfg.minDurationSeconds, cfg.maxDurationSeconds - 1);
        uint256 borrowAmount = bound(uint256(borrowSeed), 1, lending.maxBorrowForShares(collateralShares));

        uint256 loanId = _directBorrow(alice, collateralShares, durationSeconds, borrowAmount, alice);
        ISEveUSDCLending.Loan memory loanBefore = lending.loanState(loanId);

        uint256 maxAdditional = cfg.maxDurationSeconds - durationSeconds;
        uint256 additionalSeconds = bound(uint256(extensionSeed), 1, maxAdditional);
        uint256 expectedExtensionFee = _loanExtensionFee(loanId);
        uint256 expectedRecipientShare = _feeRecipientShare(expectedExtensionFee);
        uint256 feeRecipientBefore = eveUSDC.balanceOf(feeRecipient);

        if (expectedExtensionFee != 0) {
            _seedDebtAndApprove(alice, expectedExtensionFee);
        }

        _extendLoan(alice, loanId, additionalSeconds);

        ISEveUSDCLending.Loan memory loanAfter = lending.loanState(loanId);
        assertEq(uint256(loanAfter.durationSeconds), uint256(loanBefore.durationSeconds) + additionalSeconds);
        assertEq(uint256(loanAfter.maturityTime), uint256(loanBefore.maturityTime) + additionalSeconds);
        assertEq(eveUSDC.balanceOf(feeRecipient) - feeRecipientBefore, expectedRecipientShare);
    }
}
