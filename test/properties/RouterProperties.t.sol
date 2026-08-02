// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {VaultTestBase} from "../helpers/VaultTestBase.sol";
import {LibEveUSDCUnits} from "../../src/libraries/LibEveUSDCUnits.sol";

contract RouterPropertiesTest is VaultTestBase {
    /// @dev Feature: eveusdc-collateral-vault, Property 19: Router Round-Trip
    function testFuzz_RouterRoundTripReturnsUsdcMinusAumFees(uint128 amountSeed, uint8 epochsSeed) public {
        uint256 amount = bound(uint256(amountSeed), 1e6, 1_000_000e6);

        usdc.mint(alice, amount);

        vm.startPrank(alice);
        usdc.approve(address(diamond), amount);
        uint256 shares = router.wrapAndDeposit(amount, alice);
        vm.stopPrank();

        uint256 epochs = bound(uint256(epochsSeed), 0, 30);
        vm.warp(block.timestamp + epochs * vault.epochLength());

        uint256 expectedAssets = vault.previewRedeem(shares);
        uint256 expectedUsdcOut =
            LibEveUSDCUnits.convertibleEveUSDC(expectedAssets) / LibEveUSDCUnits.USDC_TO_EVEUSDC_SCALE;

        vm.startPrank(alice);
        vault.approve(address(diamond), shares);
        uint256 usdcOut = router.redeemAndUnwrap(shares, alice);
        vm.stopPrank();

        assertEq(usdcOut, expectedUsdcOut);
        assertLe(usdcOut, amount);
        _assertRouterBalancesZero();
    }
}
