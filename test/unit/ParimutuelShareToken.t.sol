// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "../../lib/forge-std/src/Test.sol";

import {IParimutuelShareToken} from "src/interfaces/IParimutuelShareToken.sol";
import {ParimutuelShareToken} from "src/tokens/ParimutuelShareToken.sol";

contract ParimutuelShareTokenTest is Test {
    address internal diamond = makeAddr("diamond");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal outsider = makeAddr("outsider");

    ParimutuelShareToken internal token;

    uint256 internal constant YES_POSITION_ID = 111;
    uint256 internal constant NO_POSITION_ID = 222;

    function setUp() public {
        token = new ParimutuelShareToken(diamond, "ipfs://parimutuel/{id}.json");
    }

    function test_ConstructorSetsDiamondAndUri() public view {
        assertEq(token.diamond(), diamond);
        assertEq(token.uri(YES_POSITION_ID), "ipfs://parimutuel/{id}.json");
    }

    function test_DiamondCanMintAndBurn() public {
        vm.prank(diamond);
        token.mint(alice, YES_POSITION_ID, 1_000);

        assertEq(token.balanceOf(alice, YES_POSITION_ID), 1_000);

        vm.prank(diamond);
        token.burn(alice, YES_POSITION_ID, 400);

        assertEq(token.balanceOf(alice, YES_POSITION_ID), 600);
    }

    function test_NonDiamondMintReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IParimutuelShareToken.NotDiamond.selector, outsider));
        vm.prank(outsider);
        token.mint(alice, YES_POSITION_ID, 1);
    }

    function test_NonDiamondBurnReverts() public {
        vm.prank(diamond);
        token.mint(alice, NO_POSITION_ID, 1);

        vm.expectRevert(abi.encodeWithSelector(IParimutuelShareToken.NotDiamond.selector, outsider));
        vm.prank(outsider);
        token.burn(alice, NO_POSITION_ID, 1);
    }

    function test_StandardErc1155TransfersRemainUnrestricted() public {
        vm.prank(diamond);
        token.mint(alice, YES_POSITION_ID, 1_000);

        vm.prank(alice);
        token.safeTransferFrom(alice, bob, YES_POSITION_ID, 250, "");

        assertEq(token.balanceOf(alice, YES_POSITION_ID), 750);
        assertEq(token.balanceOf(bob, YES_POSITION_ID), 250);
    }

    function test_ApprovedOperatorCanTransferShares() public {
        vm.prank(diamond);
        token.mint(alice, YES_POSITION_ID, 1_000);

        vm.prank(alice);
        token.setApprovalForAll(outsider, true);

        vm.prank(outsider);
        token.safeTransferFrom(alice, bob, YES_POSITION_ID, 400, "");

        assertEq(token.balanceOf(alice, YES_POSITION_ID), 600);
        assertEq(token.balanceOf(bob, YES_POSITION_ID), 400);
    }
}
