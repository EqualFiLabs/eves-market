// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {CanonicalWETH9} from "../../src/mocks/CanonicalWETH9.sol";

contract CanonicalWETH9Test is Test {
    CanonicalWETH9 internal weth;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal spender = address(0x51EAD);

    event Approval(address indexed src, address indexed guy, uint256 wad);
    event Transfer(address indexed src, address indexed dst, uint256 wad);
    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);

    function setUp() public {
        weth = new CanonicalWETH9();
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
    }

    function test_MetadataMatchesCanonicalWETH9() public view {
        assertEq(weth.name(), "Wrapped Ether");
        assertEq(weth.symbol(), "WETH");
        assertEq(weth.decimals(), 18);
    }

    function test_DepositMintsWETHAndEmitsDeposit() public {
        vm.prank(alice);
        vm.expectEmit(true, false, false, true, address(weth));
        emit Deposit(alice, 2 ether);
        weth.deposit{value: 2 ether}();

        assertEq(weth.balanceOf(alice), 2 ether);
        assertEq(weth.totalSupply(), 2 ether);
        assertEq(address(weth).balance, 2 ether);
    }

    function test_ReceiveMintsWETHLikeCanonicalFallback() public {
        vm.prank(alice);
        vm.expectEmit(true, false, false, true, address(weth));
        emit Deposit(alice, 1 ether);
        (bool ok,) = address(weth).call{value: 1 ether}("");

        assertTrue(ok);
        assertEq(weth.balanceOf(alice), 1 ether);
        assertEq(weth.totalSupply(), 1 ether);
        assertEq(address(weth).balance, 1 ether);
    }

    function test_WithdrawBurnsWETHAndTransfersETH() public {
        vm.prank(alice);
        weth.deposit{value: 3 ether}();

        uint256 aliceEthBefore = alice.balance;

        vm.prank(alice);
        vm.expectEmit(true, false, false, true, address(weth));
        emit Withdrawal(alice, 1 ether);
        weth.withdraw(1 ether);

        assertEq(weth.balanceOf(alice), 2 ether);
        assertEq(weth.totalSupply(), 2 ether);
        assertEq(address(weth).balance, 2 ether);
        assertEq(alice.balance, aliceEthBefore + 1 ether);
    }

    function test_ApproveTransferAndTransferFromMatchWETH9() public {
        vm.prank(alice);
        weth.deposit{value: 5 ether}();

        vm.prank(alice);
        vm.expectEmit(true, true, false, true, address(weth));
        emit Approval(alice, spender, 2 ether);
        assertTrue(weth.approve(spender, 2 ether));

        vm.prank(spender);
        vm.expectEmit(true, true, false, true, address(weth));
        emit Transfer(alice, bob, 1 ether);
        assertTrue(weth.transferFrom(alice, bob, 1 ether));

        assertEq(weth.balanceOf(alice), 4 ether);
        assertEq(weth.balanceOf(bob), 1 ether);
        assertEq(weth.allowance(alice, spender), 1 ether);

        vm.prank(bob);
        vm.expectEmit(true, true, false, true, address(weth));
        emit Transfer(bob, alice, 0.25 ether);
        assertTrue(weth.transfer(alice, 0.25 ether));

        assertEq(weth.balanceOf(alice), 4.25 ether);
        assertEq(weth.balanceOf(bob), 0.75 ether);
    }

    function test_MaxAllowanceIsNotDecremented() public {
        vm.prank(alice);
        weth.deposit{value: 5 ether}();

        vm.prank(alice);
        weth.approve(spender, type(uint256).max);

        vm.prank(spender);
        weth.transferFrom(alice, bob, 1 ether);

        assertEq(weth.allowance(alice, spender), type(uint256).max);
        assertEq(weth.balanceOf(alice), 4 ether);
        assertEq(weth.balanceOf(bob), 1 ether);
    }

    function test_RevertWhen_WithdrawExceedsBalance() public {
        vm.prank(alice);
        vm.expectRevert();
        weth.withdraw(1);
    }
}
