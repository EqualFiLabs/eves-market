// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IEveUSDC} from "../../src/interfaces/IEveUSDC.sol";

import {EveUSDCTestBase} from "../helpers/EveUSDCTestBase.sol";

contract EveUSDCPropertiesTest is EveUSDCTestBase {
    function testFuzz_WrapUnwrapRoundTrip(uint256 amountSeed) public {
        uint256 amount = bound(amountSeed, 1, 1_000_000e6);

        usdc.mint(alice, amount);

        vm.startPrank(alice);
        usdc.approve(address(eveUSDC), amount);
        uint256 minted = eveUSDC.wrap(amount, alice);
        uint256 usdcOut = eveUSDC.unwrap(minted, alice);
        vm.stopPrank();

        assertEq(minted, amount * USDC_TO_EVEUSDC_SCALE);
        assertEq(usdcOut, amount);
        assertEq(usdc.balanceOf(alice), amount);
        assertEq(usdc.balanceOf(address(eveUSDC)), 0);
        assertEq(eveUSDC.totalSupply(), 0);
    }

    function testFuzz_UsdcBackingInvariantHoldsAcrossValidOperationSequence(
        uint128 wrapSeedOne,
        uint128 unwrapSeedOne,
        uint128 mintSeed,
        uint128 burnSeed,
        uint128 wrapSeedTwo,
        uint128 unwrapSeedTwo
    ) public {
        uint256 wrapOne = bound(uint256(wrapSeedOne), 1, 1_000_000e6);
        uint256 wrapTwo = bound(uint256(wrapSeedTwo), 0, 1_000_000e6);

        usdc.mint(alice, wrapOne + 1_000_000e6);

        vm.startPrank(alice);
        usdc.approve(address(eveUSDC), type(uint256).max);
        eveUSDC.wrap(wrapOne, alice);
        vm.stopPrank();
        _assertBackingInvariant();

        uint256 unwrapOneUsdc = bound(uint256(unwrapSeedOne), 0, eveUSDC.balanceOf(alice) / USDC_TO_EVEUSDC_SCALE);
        if (unwrapOneUsdc != 0) {
            vm.prank(alice);
            eveUSDC.unwrap(unwrapOneUsdc * USDC_TO_EVEUSDC_SCALE, alice);
            _assertBackingInvariant();
        }

        uint256 backedMintUsdc = bound(uint256(mintSeed), 0, 1_000_000e6);
        if (backedMintUsdc != 0) {
            uint256 backedMint = backedMintUsdc * USDC_TO_EVEUSDC_SCALE;
            usdc.mint(address(eveUSDC), backedMintUsdc);

            vm.prank(onramp);
            eveUSDC.mint(bob, backedMint);
            _assertBackingInvariant();
        }

        uint256 burnAmount = bound(uint256(burnSeed), 0, eveUSDC.balanceOf(bob));
        if (burnAmount != 0) {
            vm.prank(offramp);
            eveUSDC.burn(bob, burnAmount);
            _assertBackingInvariant();
        }

        if (wrapTwo != 0) {
            vm.prank(alice);
            eveUSDC.wrap(wrapTwo, alice);
            _assertBackingInvariant();
        }

        uint256 unwrapTwoUsdc = bound(uint256(unwrapSeedTwo), 0, eveUSDC.balanceOf(alice) / USDC_TO_EVEUSDC_SCALE);
        if (unwrapTwoUsdc != 0) {
            vm.prank(alice);
            eveUSDC.unwrap(unwrapTwoUsdc * USDC_TO_EVEUSDC_SCALE, alice);
            _assertBackingInvariant();
        }

        _assertBackingInvariant();
    }

    function testFuzz_MintBurnAccessControl(address caller, uint128 mintSeed, uint128 burnSeed) public {
        vm.assume(caller != address(0) && caller != onramp && caller != offramp);

        uint256 backing = bound(uint256(mintSeed), 1, 1_000_000e6);
        uint256 minted = backing * USDC_TO_EVEUSDC_SCALE;

        usdc.mint(address(eveUSDC), backing);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IEveUSDC.UnauthorizedMinter.selector, caller));
        eveUSDC.mint(alice, minted);

        vm.prank(onramp);
        eveUSDC.mint(alice, minted);

        uint256 burned = bound(uint256(burnSeed), 1, minted);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IEveUSDC.UnauthorizedBurner.selector, caller));
        eveUSDC.burn(alice, burned);

        vm.prank(offramp);
        eveUSDC.burn(alice, burned);

        assertEq(eveUSDC.balanceOf(alice), minted - burned);
        assertEq(eveUSDC.totalSupply(), minted - burned);
        _assertBackingInvariant();
    }
}
