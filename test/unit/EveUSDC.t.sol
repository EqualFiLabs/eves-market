// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20Errors} from "../../lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";

import {IEveUSDC} from "../../src/interfaces/IEveUSDC.sol";

import {EveUSDCTestBase} from "../helpers/EveUSDCTestBase.sol";

contract EveUSDCTest is EveUSDCTestBase {
    event Wrapped(address indexed caller, address indexed to, uint256 amount);
    event Unwrapped(address indexed caller, address indexed to, uint256 amount);

    function test_RevertWhen_WrapAmountIsZero() public {
        vm.prank(alice);
        vm.expectRevert(IEveUSDC.ZeroAmount.selector);
        eveUSDC.wrap(0, receiver);
    }

    function test_RevertWhen_UnwrapAmountIsZero() public {
        vm.prank(alice);
        vm.expectRevert(IEveUSDC.ZeroAmount.selector);
        eveUSDC.unwrap(0, receiver);
    }

    function test_RevertWhen_WrapExceedsUsdcBalance() public {
        uint256 amount = 25e6;

        usdc.mint(alice, amount - 1);

        vm.startPrank(alice);
        usdc.approve(address(eveUSDC), amount);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, amount - 1, amount)
        );
        eveUSDC.wrap(amount, alice);
        vm.stopPrank();
    }

    function test_RevertWhen_WrapExceedsUsdcAllowance() public {
        uint256 amount = 25e6;
        uint256 approved = amount - 1;

        usdc.mint(alice, amount);

        vm.startPrank(alice);
        usdc.approve(address(eveUSDC), approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(eveUSDC), approved, amount)
        );
        eveUSDC.wrap(amount, alice);
        vm.stopPrank();
    }

    function test_RevertWhen_UnwrapExceedsEveUSDCBalance() public {
        uint256 amount = USDC_TO_EVEUSDC_SCALE;

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, amount));
        eveUSDC.unwrap(amount, receiver);
    }

    function test_RevertWhen_UnwrapAmountIsNotConvertibleToUsdc() public {
        uint256 amount = EVEUSDC_UNIT - 1;

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IEveUSDC.NonConvertibleEveUSDC.selector, amount));
        eveUSDC.unwrap(amount, receiver);
    }

    function test_MetadataAndRoleViewsMatchSpec() public view {
        assertEq(eveUSDC.name(), "eveUSDC");
        assertEq(eveUSDC.symbol(), "eveUSDC");
        assertEq(eveUSDC.decimals(), 18);
        assertEq(eveUSDC.usdc(), address(usdc));
        assertEq(eveUSDC.onramp(), onramp);
        assertEq(eveUSDC.offramp(), offramp);
    }

    function test_WrapPullsUsdcMints1To1AndEmitsEvent() public {
        uint256 amount = 125e6;
        uint256 expectedMinted = 125e18;

        usdc.mint(alice, amount);

        vm.startPrank(alice);
        usdc.approve(address(eveUSDC), amount);

        vm.expectEmit(true, true, false, true, address(eveUSDC));
        emit Wrapped(alice, receiver, amount);

        uint256 minted = eveUSDC.wrap(amount, receiver);
        vm.stopPrank();

        assertEq(minted, expectedMinted);
        assertEq(usdc.balanceOf(alice), 0);
        assertEq(usdc.balanceOf(address(eveUSDC)), amount);
        assertEq(eveUSDC.balanceOf(receiver), expectedMinted);
        assertEq(eveUSDC.totalSupply(), expectedMinted);
    }

    function test_UnwrapBurnsEveUSDCTransfersUsdcAndEmitsEvent() public {
        uint256 usdcAmount = 125e6;
        uint256 eveUSDCAmount = 125e18;

        _wrapFrom(alice, usdcAmount, alice);

        vm.startPrank(alice);
        vm.expectEmit(true, true, false, true, address(eveUSDC));
        emit Unwrapped(alice, receiver, usdcAmount);
        uint256 usdcOut = eveUSDC.unwrap(eveUSDCAmount, receiver);
        vm.stopPrank();

        assertEq(usdcOut, usdcAmount);
        assertEq(eveUSDC.balanceOf(alice), 0);
        assertEq(eveUSDC.totalSupply(), 0);
        assertEq(usdc.balanceOf(address(eveUSDC)), 0);
        assertEq(usdc.balanceOf(receiver), usdcAmount);
    }

    function test_RevertWhen_NonOnrampMints() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IEveUSDC.UnauthorizedMinter.selector, alice));
        eveUSDC.mint(receiver, 1);
    }

    function test_RevertWhen_NonOfframpBurns() public {
        _prefundAndMint(alice, 1);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IEveUSDC.UnauthorizedBurner.selector, alice));
        eveUSDC.burn(alice, 1);
    }

    function test_OnrampMintAndOfframpBurnSucceed() public {
        uint256 minted = 80e18;
        uint256 burned = 30e18;

        _prefundAndMint(alice, minted);

        vm.prank(offramp);
        eveUSDC.burn(alice, burned);

        assertEq(eveUSDC.balanceOf(alice), minted - burned);
        assertEq(eveUSDC.totalSupply(), minted - burned);
        _assertBackingInvariant();
    }
}
