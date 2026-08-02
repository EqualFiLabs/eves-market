// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Math} from "../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {ISEveUSDCLending} from "../../src/interfaces/ISEveUSDCLending.sol";

import {LendingTestBase} from "../helpers/LendingTestBase.sol";

contract LendingBorrowPropertiesTest is LendingTestBase {
    /// @dev Feature: seveusdc-maker-lending, Property 1: Borrow Computation Correctness
    function testFuzz_BorrowComputationCorrectness(
        uint128 depositSeed,
        uint128 collateralSeed,
        uint128 borrowSeed,
        uint32 durationSeed
    ) public {
        ISEveUSDCLending.LendingConfig memory cfg = _config();
        uint256 depositAssets = bound(uint256(depositSeed), 10, 1_000_000e6);
        uint256 mintedShares = _depositAndApproveShares(alice, depositAssets);
        uint256 collateralShares = bound(uint256(collateralSeed), 3, mintedShares);
        uint256 durationSeconds = bound(uint256(durationSeed), cfg.minDurationSeconds, cfg.maxDurationSeconds);
        uint256 maxBorrow = lending.maxBorrowForShares(collateralShares);
        uint256 borrowAmount = bound(uint256(borrowSeed), 1, maxBorrow);

        (uint256 debtPrincipal, uint256 originationFee) = lending.previewBorrowTerms(collateralShares, borrowAmount);
        uint256 collateralAssets = vault.convertToAssets(collateralShares);
        uint256 maxDebt = Math.mulDiv(collateralAssets, cfg.maxLtvBps, 10_000);
        uint256 receiverBefore = eveUSDC.balanceOf(receiver);
        uint256 escrowBefore = vault.balanceOf(address(lending));
        uint256 netBorrowed = debtPrincipal - originationFee;

        uint256 loanId = _directBorrow(alice, collateralShares, durationSeconds, borrowAmount, receiver);

        ISEveUSDCLending.Loan memory loan = lending.loanState(loanId);
        assertEq(loan.collateralShares, collateralShares);
        assertEq(loan.netBorrowed, netBorrowed);
        assertEq(loan.debtPrincipal, debtPrincipal);
        assertEq(loan.originationFeeCharged, originationFee);
        assertEq(uint256(loan.maturityTime), uint256(loan.startTime) + durationSeconds);
        assertLe(uint256(loan.debtPrincipal), maxDebt);
        assertEq(eveUSDC.balanceOf(receiver) - receiverBefore, netBorrowed);
        assertEq(vault.balanceOf(address(lending)) - escrowBefore, collateralShares);
    }

    /// @dev Feature: seveusdc-maker-lending, Property 2: Duration Bounds Enforcement
    function testFuzz_DurationBoundsEnforcement(
        uint128 depositSeed,
        uint128 collateralSeed,
        uint128 borrowSeed,
        uint32 badSeed
    ) public {
        ISEveUSDCLending.LendingConfig memory cfg = _config();
        uint256 depositAssets = bound(uint256(depositSeed), 10, 1_000_000e6);
        uint256 aliceShares = _depositAndApproveShares(alice, depositAssets);
        uint256 bobShares = _depositAndApproveShares(bob, depositAssets);

        uint256 aliceCollateral = bound(uint256(collateralSeed), 3, aliceShares);
        uint256 bobCollateral = bound(uint256(collateralSeed), 3, bobShares);
        uint256 aliceBorrow = bound(uint256(borrowSeed), 1, lending.maxBorrowForShares(aliceCollateral));
        uint256 bobBorrow = bound(uint256(borrowSeed), 1, lending.maxBorrowForShares(bobCollateral));

        _directBorrow(alice, aliceCollateral, cfg.minDurationSeconds, aliceBorrow, receiver);
        _directBorrow(bob, bobCollateral, cfg.maxDurationSeconds, bobBorrow, receiver);

        uint256 lowDuration = bound(uint256(badSeed), 0, cfg.minDurationSeconds - 1);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISEveUSDCLending.InvalidDuration.selector, lowDuration, cfg.minDurationSeconds, cfg.maxDurationSeconds
            )
        );
        lending.borrow(aliceCollateral, lowDuration, aliceBorrow, receiver);

        uint256 highDuration = uint256(cfg.maxDurationSeconds) + 1 + uint256(badSeed);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISEveUSDCLending.InvalidDuration.selector, highDuration, cfg.minDurationSeconds, cfg.maxDurationSeconds
            )
        );
        lending.borrow(aliceCollateral, highDuration, aliceBorrow, receiver);
    }

    /// @dev Feature: seveusdc-maker-lending, Property 3: Config Snapshot Integrity
    function testFuzz_ConfigSnapshotIntegrity(
        uint16 originationSeed,
        uint16 extensionSeed,
        uint32 minSeed,
        uint32 spanSeed,
        uint32 graceSeed,
        uint128 depositSeed,
        uint128 collateralSeed,
        uint128 borrowSeed,
        uint32 durationSeed
    ) public {
        uint32 minDuration = uint32(bound(uint256(minSeed), 1 hours, 30 days));
        uint32 maxDuration = uint32(bound(uint256(minDuration) + uint256(spanSeed), uint256(minDuration), 400 days));
        uint32 gracePeriod = uint32(bound(uint256(graceSeed), 0, 30 days));

        uint16 expectedOriginationBps = uint16(bound(uint256(originationSeed), 0, 500));
        uint16 expectedExtensionBps = uint16(bound(uint256(extensionSeed), 0, 500));

        _setLendingConfig(
            DEFAULT_MAX_LTV_BPS, expectedOriginationBps, expectedExtensionBps, minDuration, maxDuration, gracePeriod
        );

        ISEveUSDCLending.LendingConfig memory snapshotCfg = _config();

        uint256 depositAssets = bound(uint256(depositSeed), 10, 1_000_000e6);
        uint256 mintedShares = _depositAndApproveShares(alice, depositAssets);
        uint256 collateralShares = bound(uint256(collateralSeed), 3, mintedShares);
        uint256 borrowAmount = bound(uint256(borrowSeed), 1, lending.maxBorrowForShares(collateralShares));
        uint256 durationSeconds = bound(uint256(durationSeed), minDuration, maxDuration);

        uint256 loanId = _directBorrow(alice, collateralShares, durationSeconds, borrowAmount, receiver);
        ISEveUSDCLending.Loan memory loan = lending.loanState(loanId);

        _setLendingConfig(DEFAULT_MAX_LTV_BPS, 499, 499, 2 days, 300 days, 5 days);

        assertEq(loan.gracePeriodSecondsSnapshot, snapshotCfg.gracePeriodSeconds);
        assertEq(loan.originationFeeBpsSnapshot, snapshotCfg.originationFeeBps);
        assertEq(loan.extensionFeeBpsSnapshot, snapshotCfg.extensionFeeBps);
    }
}
