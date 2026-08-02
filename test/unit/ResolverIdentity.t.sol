// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "../../lib/forge-std/src/Test.sol";

import {IEveIdentity} from "src/interfaces/IEveIdentity.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Events} from "src/libraries/Events.sol";
import {EveIdentity} from "src/tokens/EveIdentity.sol";

contract ResolverIdentityTest is Test {
    address internal diamond = makeAddr("diamond");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal outsider = makeAddr("outsider");

    EveIdentity internal identity;

    function setUp() public {
        identity = new EveIdentity(diamond, "Eve Identity", "EVE-ID");
    }

    function test_ConstructorSetsMetadataAndDiamond() public view {
        assertEq(identity.diamond(), diamond);
        assertEq(identity.name(), "Eve Identity");
        assertEq(identity.symbol(), "EVE-ID");
    }

    function test_DiamondCanMintIdentityAndEmitFields() public {
        vm.expectEmit(true, true, true, true);
        emit IEveIdentity.Transfer(address(0), alice, 1);
        vm.expectEmit(true, true, false, true);
        emit Events.IdentityMinted(1, alice);

        vm.prank(diamond);
        uint256 identityId = identity.mint(alice);

        assertEq(identityId, 1);
        assertEq(identity.ownerOf(identityId), alice);
        assertEq(identity.identityOf(alice), identityId);
        assertEq(identity.balanceOf(alice), 1);
        assertEq(identity.totalMinted(), 1);
    }

    function test_DuplicateMintRevertsWithoutMintingAgain() public {
        vm.prank(diamond);
        identity.mint(alice);

        vm.expectRevert(abi.encodeWithSelector(Errors.IdentityAlreadyOwned.selector, alice));
        vm.prank(diamond);
        identity.mint(alice);

        assertEq(identity.totalMinted(), 1);
        assertEq(identity.balanceOf(alice), 1);
    }

    function test_NonDiamondCannotMintOrSetRoles() public {
        vm.expectRevert(abi.encodeWithSelector(IEveIdentity.NotDiamond.selector, outsider));
        vm.prank(outsider);
        identity.mint(alice);

        vm.prank(diamond);
        uint256 identityId = identity.mint(alice);

        vm.expectRevert(abi.encodeWithSelector(IEveIdentity.NotDiamond.selector, outsider));
        vm.prank(outsider);
        identity.setRoles(identityId, true, true);
    }

    function test_DiamondCanToggleRolesIndependently() public {
        vm.prank(diamond);
        uint256 identityId = identity.mint(alice);

        vm.expectEmit(true, false, false, true);
        emit Events.IdentityRolesUpdated(identityId, true, false);
        vm.prank(diamond);
        identity.setRoles(identityId, true, false);

        assertTrue(identity.hasCreatorRole(identityId));
        assertFalse(identity.hasResolverRole(identityId));

        vm.expectEmit(true, false, false, true);
        emit Events.IdentityRolesUpdated(identityId, false, true);
        vm.prank(diamond);
        identity.setRoles(identityId, false, true);

        assertFalse(identity.hasCreatorRole(identityId));
        assertTrue(identity.hasResolverRole(identityId));
    }

    function test_IdentityConfersZeroVotingWeight() public {
        vm.prank(diamond);
        uint256 identityId = identity.mint(alice);

        assertEq(identity.votingWeightOf(identityId), 0);
    }

    function test_TransferAndApprovalSurfacesAlwaysRevert() public {
        vm.prank(diamond);
        uint256 identityId = identity.mint(alice);

        vm.expectRevert(Errors.IdentityTransferDisabled.selector);
        vm.prank(alice);
        identity.transferFrom(alice, bob, identityId);

        vm.expectRevert(Errors.IdentityTransferDisabled.selector);
        vm.prank(alice);
        identity.safeTransferFrom(alice, bob, identityId);

        vm.expectRevert(Errors.IdentityTransferDisabled.selector);
        vm.prank(alice);
        identity.safeTransferFrom(alice, bob, identityId, "");

        vm.expectRevert(Errors.IdentityApprovalDisabled.selector);
        vm.prank(alice);
        identity.approve(bob, identityId);

        vm.expectRevert(Errors.IdentityApprovalDisabled.selector);
        vm.prank(alice);
        identity.setApprovalForAll(bob, true);

        assertEq(identity.ownerOf(identityId), alice);
        assertEq(identity.getApproved(identityId), address(0));
        assertFalse(identity.isApprovedForAll(alice, bob));
    }
}
