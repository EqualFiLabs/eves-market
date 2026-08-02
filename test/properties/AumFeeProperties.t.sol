// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {SEveUSDCVault} from "../../src/SEveUSDCVault.sol";

import {VaultTestBase} from "../helpers/VaultTestBase.sol";

contract AumFeePropertiesTest is VaultTestBase {
    /// @dev Feature: eveusdc-collateral-vault, Property 9: AUM Fee Compounding Correctness
    function testFuzz_AumFeeMatchesCompoundingToWithinOneUnit(uint16 feeSeed, uint128 depositSeed, uint8 epochsSeed)
        public
    {
        uint16 feeBps = uint16(bound(uint256(feeSeed), 1, 10_000));
        vault = _deployVault(feeBps);

        uint256 assets = bound(uint256(depositSeed), 1, 1_000_000e6);
        _depositSeeded(alice, assets, alice);

        uint256 epochs = bound(uint256(epochsSeed), 1, 30);
        vm.warp(block.timestamp + epochs * vault.epochLength());

        uint256 feeRecipientBefore = eveUSDC.balanceOf(feeRecipient);
        uint256 feeAssets = vault.accrueAum();
        uint256 actualFee = eveUSDC.balanceOf(feeRecipient) - feeRecipientBefore;
        uint256 theoreticalFeeAssets = _theoreticalFeeWad(assets, feeBps, epochs) / WAD;

        assertEq(feeAssets, actualFee);
        assertApproxEqAbs(feeAssets, theoreticalFeeAssets, 1);
    }

    /// @dev Feature: eveusdc-collateral-vault, Property 10: Timestamp Epoch-Aligned Advancement
    function testFuzz_LastAccrualTimestampAdvancesByWholeEpochs(
        uint128 depositSeed,
        uint8 epochsSeed,
        uint40 remainderSeed
    ) public {
        uint256 assets = bound(uint256(depositSeed), 1, 1_000_000e6);
        _depositSeeded(alice, assets, alice);

        uint64 start = vault.lastAccrualTimestamp();
        uint256 epochs = bound(uint256(epochsSeed), 1, 30);
        uint256 remainderSeconds = bound(uint256(remainderSeed), 0, vault.epochLength() - 1);
        vm.warp(block.timestamp + epochs * vault.epochLength() + remainderSeconds);

        vault.accrueAum();

        assertEq(vault.lastAccrualTimestamp(), start + uint64(epochs * vault.epochLength()));
    }

    /// @dev Feature: eveusdc-collateral-vault, Property 11: Permissionless AUM Accrual
    function testFuzz_AnyCallerGetsSameAccrualResult(
        uint16 feeSeed,
        uint128 depositSeed,
        uint8 epochsSeed,
        address callerA,
        address callerB
    ) public {
        vm.assume(callerA != address(0) && callerB != address(0));

        uint16 feeBps = uint16(bound(uint256(feeSeed), 1, 10_000));
        vault = _deployVault(feeBps);
        SEveUSDCVault mirrorVault = _deployVault(feeBps);

        uint256 assets = bound(uint256(depositSeed), 1, 1_000_000e6);

        _seedEveUSDC(alice, assets * 2);
        vm.startPrank(alice);
        eveUSDC.approve(address(vault), assets);
        eveUSDC.approve(address(mirrorVault), assets);
        vault.deposit(assets, alice);
        mirrorVault.deposit(assets, alice);
        vm.stopPrank();

        uint256 epochs = bound(uint256(epochsSeed), 1, 30);
        vm.warp(block.timestamp + epochs * vault.epochLength());

        vm.prank(callerA);
        uint256 feeA = vault.accrueAum();

        vm.prank(callerB);
        uint256 feeB = mirrorVault.accrueAum();

        assertEq(feeA, feeB);
        assertEq(vault.totalAssets(), mirrorVault.totalAssets());
        assertEq(vault.lastAccrualTimestamp(), mirrorVault.lastAccrualTimestamp());
    }

    /// @dev Feature: eveusdc-collateral-vault, Property 12: Fee Remainder Cumulative Precision
    function testFuzz_FeeRemainderTracksCumulativePrecision(
        uint8 firstEpochsSeed,
        uint8 secondEpochsSeed,
        uint8 thirdEpochsSeed
    ) public {
        vault = _deployVault(10_000);
        _depositSeeded(alice, 100, alice);

        uint256[3] memory epochs = [
            bound(uint256(firstEpochsSeed), 1, 30),
            bound(uint256(secondEpochsSeed), 1, 30),
            bound(uint256(thirdEpochsSeed), 1, 30)
        ];

        uint256 expectedAssets = vault.totalAssets();
        uint256 preciseFeeWadAccumulated;

        for (uint256 index = 0; index < epochs.length; ++index) {
            vm.warp(block.timestamp + epochs[index] * vault.epochLength());
            vault.accrueAum();

            uint256 preciseFeeWad = _theoreticalFeeWadUsingRpow(expectedAssets, vault.aumFeeBps(), epochs[index]);
            preciseFeeWadAccumulated += preciseFeeWad;
            expectedAssets -= preciseFeeWad / WAD;
        }

        uint256 transferredFeeWad = eveUSDC.balanceOf(feeRecipient) * WAD;
        uint256 accountedFeeWad = transferredFeeWad + vault.feeRemainderWad();

        assertApproxEqAbs(accountedFeeWad, preciseFeeWadAccumulated, WAD);
        assertLt(vault.feeRemainderWad(), WAD);
    }
}
