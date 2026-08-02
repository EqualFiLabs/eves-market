// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Math} from "../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

import {ISEveUSDCVault} from "../../src/interfaces/ISEveUSDCVault.sol";

import {VaultTestBase} from "../helpers/VaultTestBase.sol";

contract VaultSharePropertiesTest is VaultTestBase {
    /// @dev Feature: eveusdc-collateral-vault, Property 4: Deposit Produces Correct Shares
    function testFuzz_DepositProducesCorrectShares(
        bool seededVault,
        uint128 seedAssets,
        uint128 depositSeed,
        uint8 epochsSeed
    ) public {
        if (seededVault) {
            uint256 initialAssets = bound(uint256(seedAssets), 1, 1_000_000e6);
            _depositSeeded(alice, initialAssets, alice);
        }

        uint256 assets = bound(uint256(depositSeed), 1, 1_000_000e6);
        uint256 expectedShares = _expectedDepositShares(vault, assets);
        uint256 previewShares = vault.previewDeposit(assets);

        uint256 epochs = bound(uint256(epochsSeed), 0, 30);
        vm.warp(block.timestamp + epochs * vault.epochLength());

        expectedShares = _expectedDepositShares(vault, assets);
        previewShares = vault.previewDeposit(assets);

        _seedEveUSDC(bob, assets);
        _approveAsset(bob, assets);

        uint256 assetBalanceBefore = eveUSDC.balanceOf(bob);
        vm.prank(bob);
        uint256 shares = vault.deposit(assets, receiver);

        assertEq(shares, expectedShares);
        assertEq(shares, previewShares);
        assertEq(eveUSDC.balanceOf(bob), assetBalanceBefore - assets);
        assertEq(vault.balanceOf(receiver), shares);
    }

    /// @dev Feature: eveusdc-collateral-vault, Property 5: Mint Produces Correct Asset Pull
    function testFuzz_MintPullsExpectedAssets(bool seededVault, uint128 seedAssets, uint128 shareSeed, uint8 epochsSeed)
        public
    {
        if (seededVault) {
            uint256 initialAssets = bound(uint256(seedAssets), 1, 1_000_000e6);
            _depositSeeded(alice, initialAssets, alice);
        }

        uint256 sharesToMint = bound(uint256(shareSeed), 1, 1_000_000e6);
        uint256 epochs = bound(uint256(epochsSeed), 0, 30);
        vm.warp(block.timestamp + epochs * vault.epochLength());

        uint256 expectedAssets = _expectedMintAssets(vault, sharesToMint);
        uint256 previewAssets = vault.previewMint(sharesToMint);

        _seedEveUSDC(bob, expectedAssets);
        _approveAsset(bob, expectedAssets);

        uint256 assetBalanceBefore = eveUSDC.balanceOf(bob);
        vm.prank(bob);
        uint256 assetsPulled = vault.mint(sharesToMint, receiver);

        assertEq(assetsPulled, expectedAssets);
        assertEq(assetsPulled, previewAssets);
        assertEq(eveUSDC.balanceOf(bob), assetBalanceBefore - assetsPulled);
        assertEq(vault.balanceOf(receiver), sharesToMint);
    }

    /// @dev Feature: eveusdc-collateral-vault, Property 6: Withdraw Burns Correct Shares
    function testFuzz_WithdrawBurnsExpectedShares(uint128 depositSeed, uint128 withdrawSeed, uint8 epochsSeed) public {
        uint256 depositAssets = bound(uint256(depositSeed), 2, 1_000_000e6);
        _depositSeeded(alice, depositAssets, alice);

        uint256 epochs = bound(uint256(epochsSeed), 0, 30);
        vm.warp(block.timestamp + epochs * vault.epochLength());

        uint256 maxAssets = vault.previewRedeem(vault.balanceOf(alice));
        uint256 assets = bound(uint256(withdrawSeed), 1, maxAssets);
        uint256 expectedShares = _expectedWithdrawShares(vault, assets);
        uint256 previewShares = vault.previewWithdraw(assets);
        uint256 receiverAssetsBefore = eveUSDC.balanceOf(receiver);

        vm.prank(alice);
        uint256 sharesBurned = vault.withdraw(assets, receiver, alice);

        assertEq(sharesBurned, expectedShares);
        assertEq(sharesBurned, previewShares);
        assertEq(eveUSDC.balanceOf(receiver), receiverAssetsBefore + assets);
        assertEq(vault.balanceOf(alice), depositAssets - sharesBurned);
    }

    /// @dev Feature: eveusdc-collateral-vault, Property 7: Redeem Returns Correct Assets
    function testFuzz_RedeemReturnsExpectedAssets(uint128 depositSeed, uint128 redeemSeed, uint8 epochsSeed) public {
        uint256 depositAssets = bound(uint256(depositSeed), 2, 1_000_000e6);
        _depositSeeded(alice, depositAssets, alice);

        uint256 epochs = bound(uint256(epochsSeed), 0, 30);
        vm.warp(block.timestamp + epochs * vault.epochLength());

        uint256 shares = bound(uint256(redeemSeed), 1, vault.balanceOf(alice));
        uint256 expectedAssets = _expectedRedeemAssets(vault, shares);
        uint256 previewAssets = vault.previewRedeem(shares);
        uint256 receiverAssetsBefore = eveUSDC.balanceOf(receiver);

        vm.prank(alice);
        uint256 assetsOut = vault.redeem(shares, receiver, alice);

        assertEq(assetsOut, expectedAssets);
        assertEq(assetsOut, previewAssets);
        assertEq(eveUSDC.balanceOf(receiver), receiverAssetsBefore + assetsOut);
        assertEq(vault.balanceOf(alice), depositAssets - shares);
    }

    /// @dev Feature: eveusdc-collateral-vault, Property 8: Allowance Consumption on Delegated Operations
    function testFuzz_DelegatedOperationsConsumeAllowance(
        uint128 depositSeed,
        uint128 actionSeed,
        bool useWithdraw,
        uint8 epochsSeed
    ) public {
        uint256 depositAssets = bound(uint256(depositSeed), 2, 1_000_000e6);
        _depositSeeded(alice, depositAssets, alice);

        uint256 epochs = bound(uint256(epochsSeed), 0, 30);
        vm.warp(block.timestamp + epochs * vault.epochLength());

        uint256 requiredShares;
        if (useWithdraw) {
            uint256 maxAssets = vault.previewRedeem(vault.balanceOf(alice));
            uint256 assets = bound(uint256(actionSeed), 1, maxAssets);
            requiredShares = vault.previewWithdraw(assets);

            vm.prank(alice);
            vault.approve(carol, requiredShares);

            vm.prank(carol);
            uint256 burned = vault.withdraw(assets, receiver, alice);

            assertEq(burned, requiredShares);
            assertEq(vault.allowance(alice, carol), 0);
        } else {
            requiredShares = bound(uint256(actionSeed), 1, vault.balanceOf(alice));
            uint256 expectedAssets = vault.previewRedeem(requiredShares);

            vm.prank(alice);
            vault.approve(carol, requiredShares);

            vm.prank(carol);
            uint256 redeemedAssets = vault.redeem(requiredShares, receiver, alice);

            assertEq(redeemedAssets, expectedAssets);
            assertEq(vault.allowance(alice, carol), 0);
        }
    }

    function testFuzz_DelegatedOperationsRevertOnInsufficientAllowance(
        uint128 depositSeed,
        uint128 actionSeed,
        bool useWithdraw
    ) public {
        uint256 depositAssets = bound(uint256(depositSeed), 2, 1_000_000e6);
        _depositSeeded(alice, depositAssets, alice);

        if (useWithdraw) {
            uint256 maxAssets = vault.previewRedeem(vault.balanceOf(alice));
            uint256 assets = bound(uint256(actionSeed), 1, maxAssets);
            uint256 requiredShares = vault.previewWithdraw(assets);

            vm.prank(alice);
            vault.approve(carol, requiredShares - 1);

            vm.prank(carol);
            vm.expectRevert(
                abi.encodeWithSelector(
                    ISEveUSDCVault.InsufficientAllowance.selector, carol, alice, requiredShares, requiredShares - 1
                )
            );
            vault.withdraw(assets, receiver, alice);
        } else {
            uint256 shares = bound(uint256(actionSeed), 2, vault.balanceOf(alice));

            vm.prank(alice);
            vault.approve(carol, shares - 1);

            vm.prank(carol);
            vm.expectRevert(
                abi.encodeWithSelector(ISEveUSDCVault.InsufficientAllowance.selector, carol, alice, shares, shares - 1)
            );
            vault.redeem(shares, receiver, alice);
        }
    }
}
