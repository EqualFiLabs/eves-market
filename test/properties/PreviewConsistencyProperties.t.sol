// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {VaultTestBase} from "../helpers/VaultTestBase.sol";

contract PreviewConsistencyPropertiesTest is VaultTestBase {
    /// @dev Feature: eveusdc-collateral-vault, Property 14: Preview Consistency With Actual Operations
    function testFuzz_PreviewsMatchActualOperations(uint128 aliceSeed, uint128 bobSeed, uint8 epochsSeed) public {
        uint256 aliceAssets = bound(uint256(aliceSeed), 10, 1_000_000e6);
        uint256 bobAssets = bound(uint256(bobSeed), 10, 1_000_000e6);

        _depositSeeded(alice, aliceAssets, alice);
        _depositSeeded(bob, bobAssets, bob);

        uint256 epochs = bound(uint256(epochsSeed), 0, 30);
        vm.warp(block.timestamp + epochs * vault.epochLength());

        uint256 depositAssets = bound(uint256(aliceSeed), 1, 100_000e6);
        uint256 previewDepositShares = vault.previewDeposit(depositAssets);
        _seedEveUSDC(alice, depositAssets);
        _approveAsset(alice, depositAssets);
        vm.prank(alice);
        uint256 depositShares = vault.deposit(depositAssets, receiver);
        assertEq(depositShares, previewDepositShares);

        uint256 mintShares = bound(uint256(bobSeed), 1, 100_000e6);
        uint256 previewMintAssets = vault.previewMint(mintShares);
        _seedEveUSDC(bob, previewMintAssets);
        _approveAsset(bob, previewMintAssets);
        vm.prank(bob);
        uint256 mintedAssets = vault.mint(mintShares, receiver);
        assertEq(mintedAssets, previewMintAssets);

        uint256 withdrawAssets = bound(uint256(aliceSeed), 1, vault.previewRedeem(vault.balanceOf(alice)));
        uint256 previewWithdrawShares = vault.previewWithdraw(withdrawAssets);
        vm.prank(alice);
        uint256 withdrawnShares = vault.withdraw(withdrawAssets, carol, alice);
        assertEq(withdrawnShares, previewWithdrawShares);

        uint256 redeemShares = bound(uint256(bobSeed), 1, vault.balanceOf(bob));
        uint256 previewRedeemAssets = vault.previewRedeem(redeemShares);
        vm.prank(bob);
        uint256 redeemedAssets = vault.redeem(redeemShares, carol, bob);
        assertEq(redeemedAssets, previewRedeemAssets);
    }

    /// @dev Feature: eveusdc-collateral-vault, Property 15: previewAccruedAum Consistency
    function testFuzz_PreviewAccruedAumMatchesActualAccrual(uint128 depositSeed, uint8 epochsSeed) public {
        uint256 assets = bound(uint256(depositSeed), 1, 1_000_000e6);
        _depositSeeded(alice, assets, alice);

        uint256 epochs = bound(uint256(epochsSeed), 1, 30);
        vm.warp(block.timestamp + epochs * vault.epochLength());

        (uint256 previewFeeAssets, uint256 previewEpochs) = vault.previewAccruedAum();
        uint64 previousTimestamp = vault.lastAccrualTimestamp();
        uint256 actualFeeAssets = vault.accrueAum();

        assertEq(actualFeeAssets, previewFeeAssets);
        assertEq(vault.lastAccrualTimestamp(), previousTimestamp + uint64(previewEpochs * vault.epochLength()));
    }

    /// @dev Feature: eveusdc-collateral-vault, Property 16: totalAssets Matches Managed-Assets Formula
    function testFuzz_TotalAssetsMatchesManagedAssetsFormula(uint128 aliceSeed, uint128 bobSeed, uint128 revenueSeed)
        public
    {
        uint256 aliceAssets = bound(uint256(aliceSeed), 1, 1_000_000e6);
        uint256 bobAssets = bound(uint256(bobSeed), 1, 1_000_000e6);
        uint256 revenueAssets = bound(uint256(revenueSeed), 1, 1_000_000e6);

        _depositSeeded(alice, aliceAssets, alice);
        _depositSeeded(bob, bobAssets, bob);
        _notifyRevenue(revenueAssets);

        uint256 aliceHalfShares = bound(vault.balanceOf(alice) / 2, 1, vault.balanceOf(alice));
        vm.prank(alice);
        vault.redeem(aliceHalfShares, receiver, alice);

        assertEq(vault.totalAssets(), _managedAssets(vault));
    }
}
