// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {SEveUSDCVault} from "../../src/SEveUSDCVault.sol";

import {VaultTestBase} from "../helpers/VaultTestBase.sol";

contract VaultRevenuePropertiesTest is VaultTestBase {
    /// @dev Feature: eveusdc-collateral-vault, Property 13: Revenue Notification Increases Assets Without Minting Shares
    function testFuzz_NotifyRevenueIncreasesAssetsWithoutMintingShares(
        uint128 depositSeed,
        uint128 revenueSeed,
        uint8 epochsSeed
    ) public {
        uint256 depositAssets = bound(uint256(depositSeed), 1, 1_000_000e6);
        uint256 revenueAssets = bound(uint256(revenueSeed), 1, 1_000_000e6);
        _depositSeeded(alice, depositAssets, alice);

        uint256 epochs = bound(uint256(epochsSeed), 0, 30);
        vm.warp(block.timestamp + epochs * vault.epochLength());

        uint256 totalSupplyBefore = vault.totalSupply();
        (uint256 pendingFee,) = vault.previewAccruedAum();
        uint256 redeemAllBefore = vault.previewRedeem(totalSupplyBefore);
        uint256 expectedAssetsAfter = vault.totalAssets() - pendingFee + revenueAssets;

        _notifyRevenue(revenueAssets);

        assertEq(vault.totalSupply(), totalSupplyBefore);
        assertEq(vault.totalAssets(), expectedAssetsAfter);
        assertEq(vault.previewRedeem(totalSupplyBefore), expectedAssetsAfter);
        assertGt(vault.previewRedeem(totalSupplyBefore), redeemAllBefore);
    }

    /// @dev Feature: eveusdc-collateral-vault, Property 17: Share Fairness — Deposit-Revenue-Redeem Monotonicity
    function testFuzz_DepositBeforeRevenueRedeemsMoreThanDeposited(
        uint128 aliceSeed,
        uint128 bobSeed,
        uint128 revenueSeed
    ) public {
        vault = _deployVault(0);

        uint256 aliceAssets = bound(uint256(aliceSeed), 1e6, 1_000_000e6);
        uint256 bobAssets = bound(uint256(bobSeed), 1e6, 1_000_000e6);
        uint256 revenueAssets = bound(uint256(revenueSeed), 1e6, 1_000_000e6);

        uint256 aliceShares = _depositSeeded(alice, aliceAssets, alice);
        _notifyRevenue(revenueAssets);

        uint256 bobSharesPreview = vault.previewDeposit(bobAssets);
        uint256 virtualShareValue = vault.previewRedeem(VAULT_VIRTUAL_SHARES);
        vm.assume(bobSharesPreview != 0);
        uint256 bobShares = _depositSeeded(bob, bobAssets, bob);

        assertEq(bobShares, bobSharesPreview);

        uint256 aliceReceiverBefore = eveUSDC.balanceOf(receiver);
        vm.prank(alice);
        uint256 aliceAssetsOut = vault.redeem(aliceShares, receiver, alice);
        uint256 aliceReceived = eveUSDC.balanceOf(receiver) - aliceReceiverBefore;

        uint256 bobReceiverBefore = eveUSDC.balanceOf(carol);
        vm.prank(bob);
        uint256 bobAssetsOut = vault.redeem(bobShares, carol, bob);
        uint256 bobReceived = eveUSDC.balanceOf(carol) - bobReceiverBefore;

        assertEq(aliceAssetsOut, aliceReceived);
        assertEq(bobAssetsOut, bobReceived);
        assertGt(aliceAssetsOut, aliceAssets);
        assertLe(bobAssetsOut, bobAssets + virtualShareValue + 1);
    }
}
