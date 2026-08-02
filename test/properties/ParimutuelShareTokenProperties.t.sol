// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "../../lib/forge-std/src/Test.sol";

import {IParimutuelShareToken} from "src/interfaces/IParimutuelShareToken.sol";
import {ParimutuelShareToken} from "src/tokens/ParimutuelShareToken.sol";

contract ParimutuelShareTokenPropertiesTest is Test {
    address internal diamond = makeAddr("diamond");
    address internal alice = makeAddr("alice");

    ParimutuelShareToken internal token;

    function setUp() public {
        token = new ParimutuelShareToken(diamond, "ipfs://parimutuel/{id}.json");
    }

    function testFuzz_NonDiamondCannotMint(address caller, address receiver, uint256 id, uint256 amount) public {
        vm.assume(caller != diamond);

        // Feature: parimutuel-facet, Property 3: ParimutuelShareToken access control
        vm.expectRevert(abi.encodeWithSelector(IParimutuelShareToken.NotDiamond.selector, caller));
        vm.prank(caller);
        token.mint(receiver, id, amount);
    }

    function testFuzz_NonDiamondCannotBurn(address caller, address from, uint256 id, uint256 amount) public {
        vm.assume(caller != diamond);

        // Feature: parimutuel-facet, Property 3: ParimutuelShareToken access control
        vm.expectRevert(abi.encodeWithSelector(IParimutuelShareToken.NotDiamond.selector, caller));
        vm.prank(caller);
        token.burn(from, id, amount);
    }

    function testFuzz_MintBurnRoundTripRestoresBalance(address account, uint256 id, uint256 amount) public {
        vm.assume(account != address(0));
        vm.assume(account.code.length == 0);
        amount = bound(amount, 1, type(uint128).max);

        uint256 startingBalance = token.balanceOf(account, id);

        // Feature: parimutuel-facet, Property 4: ParimutuelShareToken mint-burn round-trip
        vm.startPrank(diamond);
        token.mint(account, id, amount);
        token.burn(account, id, amount);
        vm.stopPrank();

        assertEq(token.balanceOf(account, id), startingBalance);
    }

    function testFuzz_StandardTransfersUpdateBalances(address receiver, uint256 id, uint256 amount) public {
        vm.assume(receiver != address(0));
        vm.assume(receiver != alice);
        vm.assume(receiver.code.length == 0);
        amount = bound(amount, 1, type(uint128).max);

        vm.prank(diamond);
        token.mint(alice, id, amount);

        // Feature: parimutuel-facet, Property 4: ParimutuelShareToken mint-burn round-trip
        vm.prank(alice);
        token.safeTransferFrom(alice, receiver, id, amount, "");

        assertEq(token.balanceOf(alice, id), 0);
        assertEq(token.balanceOf(receiver, id), amount);
    }
}
