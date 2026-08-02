// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {SEveUSDCVault} from "../../src/SEveUSDCVault.sol";
import {ISEveUSDCVault} from "../../src/interfaces/ISEveUSDCVault.sol";

import {VaultTestBase} from "../helpers/VaultTestBase.sol";

contract GovernancePropertiesTest is VaultTestBase {
    /// @dev Feature: eveusdc-collateral-vault, Property 20: Governance Setters Accrue Before Update
    function testFuzz_SetAumFeeBpsAccruesAtOldRateBeforeUpdating(
        uint16 oldFeeSeed,
        uint16 newFeeSeed,
        uint128 depositSeed,
        uint8 epochsSeed
    ) public {
        uint16 oldFeeBps = uint16(bound(uint256(oldFeeSeed), 1, 10_000));
        uint16 newFeeBps = uint16(bound(uint256(newFeeSeed), 0, 10_000));
        vault = _deployVault(oldFeeBps);
        SEveUSDCVault mirrorVault =
            new SEveUSDCVault(address(eveUSDC), owner, makeAddr("mirror-fee-recipient"), oldFeeBps, revenueNotifier);

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

        address mirrorFeeRecipient = mirrorVault.feeRecipient();
        uint256 mirrorFeeRecipientBefore = eveUSDC.balanceOf(mirrorFeeRecipient);
        vm.prank(owner);
        uint256 mirrorFeeAssets = mirrorVault.accrueAum();
        uint256 mirrorFeeDelta = eveUSDC.balanceOf(mirrorFeeRecipient) - mirrorFeeRecipientBefore;

        uint256 feeRecipientBefore = eveUSDC.balanceOf(feeRecipient);
        vm.prank(owner);
        vault.setAumFeeBps(newFeeBps);
        uint256 feeDelta = eveUSDC.balanceOf(feeRecipient) - feeRecipientBefore;

        assertEq(mirrorFeeAssets, mirrorFeeDelta);
        assertEq(feeDelta, mirrorFeeDelta);
        assertEq(vault.lastAccrualTimestamp(), mirrorVault.lastAccrualTimestamp());
        assertEq(vault.aumFeeBps(), newFeeBps);
    }

    /// @dev Feature: eveusdc-collateral-vault, Property 21: Governance Access Control
    function testFuzz_OnlyOwnerCanCallGovernanceSetters(address caller, uint16 newFeeSeed, address newRecipient)
        public
    {
        vm.assume(caller != address(0) && caller != owner && newRecipient != address(0));

        uint16 newFeeBps = uint16(bound(uint256(newFeeSeed), 0, 10_000));

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(ISEveUSDCVault.NotOwner.selector, caller));
        vault.setAumFeeBps(newFeeBps);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(ISEveUSDCVault.NotOwner.selector, caller));
        vault.setFeeRecipient(newRecipient);
    }
}
