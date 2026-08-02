// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {CanonicalWETH9} from "../../src/mocks/CanonicalWETH9.sol";
import {EveETH} from "../../src/tokens/EveETH.sol";

contract EveETHTest is Test {
    CanonicalWETH9 internal weth;
    EveETH internal eveETH;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    event Wrapped(address indexed caller, address indexed receiver, uint256 amount);
    event Unwrapped(address indexed caller, address indexed receiver, uint256 amount);

    function setUp() public {
        weth = new CanonicalWETH9();
        eveETH = new EveETH(address(weth));

        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
    }

    function test_MetadataAndBackingAsset() public view {
        assertEq(eveETH.name(), "eveETH");
        assertEq(eveETH.symbol(), "eveETH");
        assertEq(eveETH.decimals(), 18);
        assertEq(eveETH.weth(), address(weth));
    }

    function test_WrapTransfersWETHAndMintsEveETH() public {
        vm.prank(alice);
        weth.deposit{value: 3 ether}();

        vm.prank(alice);
        weth.approve(address(eveETH), 2 ether);

        vm.prank(alice);
        vm.expectEmit(true, true, false, true, address(eveETH));
        emit Wrapped(alice, bob, 2 ether);
        uint256 minted = eveETH.wrap(2 ether, bob);

        assertEq(minted, 2 ether);
        assertEq(eveETH.balanceOf(bob), 2 ether);
        assertEq(eveETH.totalSupply(), 2 ether);
        assertEq(weth.balanceOf(alice), 1 ether);
        assertEq(weth.balanceOf(address(eveETH)), 2 ether);
    }

    function test_UnwrapBurnsEveETHandReturnsWETH() public {
        vm.prank(alice);
        weth.deposit{value: 3 ether}();

        vm.startPrank(alice);
        weth.approve(address(eveETH), 2 ether);
        eveETH.wrap(2 ether, alice);
        vm.expectEmit(true, true, false, true, address(eveETH));
        emit Unwrapped(alice, bob, 1.25 ether);
        uint256 wethOut = eveETH.unwrap(1.25 ether, bob);
        vm.stopPrank();

        assertEq(wethOut, 1.25 ether);
        assertEq(eveETH.balanceOf(alice), 0.75 ether);
        assertEq(eveETH.totalSupply(), 0.75 ether);
        assertEq(weth.balanceOf(bob), 1.25 ether);
        assertEq(weth.balanceOf(address(eveETH)), 0.75 ether);
    }

    function test_WrapPreservesOneToOneBackingAcrossReceivers() public {
        vm.prank(alice);
        weth.deposit{value: 5 ether}();

        vm.startPrank(alice);
        weth.approve(address(eveETH), 5 ether);
        eveETH.wrap(2 ether, alice);
        eveETH.wrap(3 ether, bob);
        vm.stopPrank();

        assertEq(eveETH.totalSupply(), 5 ether);
        assertEq(weth.balanceOf(address(eveETH)), 5 ether);
        assertEq(eveETH.balanceOf(alice), 2 ether);
        assertEq(eveETH.balanceOf(bob), 3 ether);
    }

    function test_RevertWhen_ConstructedWithZeroWETH() public {
        vm.expectRevert(EveETH.ZeroAddress.selector);
        new EveETH(address(0));
    }

    function test_RevertWhen_WrapZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(EveETH.ZeroAmount.selector);
        eveETH.wrap(0, alice);
    }

    function test_RevertWhen_WrapToZeroAddress() public {
        vm.prank(alice);
        weth.deposit{value: 1 ether}();

        vm.prank(alice);
        weth.approve(address(eveETH), 1 ether);

        vm.prank(alice);
        vm.expectRevert(EveETH.ZeroAddress.selector);
        eveETH.wrap(1 ether, address(0));
    }

    function test_RevertWhen_UnwrapZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(EveETH.ZeroAmount.selector);
        eveETH.unwrap(0, alice);
    }

    function test_RevertWhen_UnwrapToZeroAddress() public {
        vm.prank(alice);
        weth.deposit{value: 1 ether}();

        vm.startPrank(alice);
        weth.approve(address(eveETH), 1 ether);
        eveETH.wrap(1 ether, alice);
        vm.expectRevert(EveETH.ZeroAddress.selector);
        eveETH.unwrap(1 ether, address(0));
        vm.stopPrank();
    }

    function test_RevertWhen_UnwrapExceedsBalance() public {
        vm.prank(alice);
        vm.expectRevert();
        eveETH.unwrap(1, alice);
    }
}
