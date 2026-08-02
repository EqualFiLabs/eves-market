// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC1155Receiver} from "../../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155Receiver.sol";

import {FunctionNotFound} from "../../src/EveMarketDiamond.sol";
import {DiamondCutFacet} from "../../src/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "../../src/facets/DiamondLoupeFacet.sol";
import {OwnershipFacet} from "../../src/facets/OwnershipFacet.sol";
import {Errors} from "../../src/libraries/Errors.sol";

import {DiamondFixture, RoutingProbeFacet, RoutingProbeFacetV2, StateProbeFacet} from "../helpers/DiamondFixtures.sol";
import {MockCurveProfile} from "../helpers/MockCurveProfile.sol";

contract DiamondTest is DiamondFixture {
    function test_FacetRegistrationAndLoupeViewsStayInSync() public view {
        assertEq(OwnershipFacet(address(diamond)).owner(), owner);
        assertEq(
            DiamondLoupeFacet(address(diamond)).facetAddress(DiamondCutFacet.diamondCut.selector), address(cutFacet)
        );
        assertEq(
            DiamondLoupeFacet(address(diamond)).facetAddress(DiamondLoupeFacet.facets.selector), address(loupeFacet)
        );
        assertEq(
            DiamondLoupeFacet(address(diamond)).facetAddress(OwnershipFacet.setOrderbookEntryFeeBps.selector),
            address(ownershipFacet)
        );

        address[] memory facetAddresses_ = DiamondLoupeFacet(address(diamond)).facetAddresses();
        assertEq(facetAddresses_.length, 5);

        bytes4[] memory probeSelectors =
            DiamondLoupeFacet(address(diamond)).facetFunctionSelectors(address(routingProbe));
        assertEq(probeSelectors.length, 3);
        assertEq(probeSelectors[0], RoutingProbeFacet.storeWord.selector);
        assertEq(probeSelectors[1], RoutingProbeFacet.readWord.selector);
        assertEq(probeSelectors[2], RoutingProbeFacet.version.selector);

        DiamondLoupeFacet.Facet[] memory allFacets = DiamondLoupeFacet(address(diamond)).facets();
        assertEq(allFacets.length, 5);
    }

    function test_SelectorRoutingDelegatesToProbeFacet() public {
        RoutingProbeFacet(address(diamond)).storeWord(42);

        assertEq(RoutingProbeFacet(address(diamond)).readWord(), 42);
        assertEq(RoutingProbeFacet(address(diamond)).version(), 1);
    }

    function test_RevertWhen_NonOwnerCallsDiamondCut() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = RoutingProbeFacet.version.selector;

        DiamondCutFacet.FacetCut[] memory cuts = new DiamondCutFacet.FacetCut[](1);
        cuts[0] = DiamondCutFacet.FacetCut({
            facetAddress: address(routingProbeV2),
            action: DiamondCutFacet.FacetCutAction.Replace,
            functionSelectors: selectors
        });

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotContractOwner.selector, outsider));
        DiamondCutFacet(address(diamond)).diamondCut(cuts, address(0), new bytes(0));
    }

    function test_RevertWhen_NonOwnerCallsOwnershipSetter() public {
        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotContractOwner.selector, outsider));
        OwnershipFacet(address(diamond)).setOrderbookEntryFeeBps(77);
    }

    function test_TransferOwnershipMovesAdminRights() public {
        address newOwner = makeAddr("new-owner");

        vm.prank(owner);
        OwnershipFacet(address(diamond)).transferOwnership(newOwner);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotContractOwner.selector, owner));
        OwnershipFacet(address(diamond)).setOrderbookEntryFeeBps(91);

        vm.prank(newOwner);
        OwnershipFacet(address(diamond)).setOrderbookEntryFeeBps(91);
        vm.prank(newOwner);
        OwnershipFacet(address(diamond)).setMarketCreationFee(55e6);

        assertEq(OwnershipFacet(address(diamond)).owner(), newOwner);
        assertEq(StateProbeFacet(address(diamond)).orderbookEntryFeeBps(), 91);
        assertEq(StateProbeFacet(address(diamond)).marketCreationFee(), 55e6);
    }

    function test_OwnerCanRegisterCurveProfile() public {
        MockCurveProfile curveProfile = new MockCurveProfile();

        vm.prank(owner);
        OwnershipFacet(address(diamond)).registerCurveProfile(9, address(curveProfile));

        assertEq(StateProbeFacet(address(diamond)).curveProfile(9), address(curveProfile));
    }

    function test_FrozenSelectorsRejectReplaceAndRemove() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = RoutingProbeFacet.version.selector;

        vm.prank(owner);
        DiamondCutFacet(address(diamond)).freezeFacet(selectors);

        vm.expectRevert(abi.encodeWithSelector(Errors.SelectorFrozen.selector, RoutingProbeFacet.version.selector));
        _replaceFacet(address(routingProbeV2), selectors);

        vm.expectRevert(abi.encodeWithSelector(Errors.SelectorFrozen.selector, RoutingProbeFacet.version.selector));
        _removeSelectors(selectors);

        assertTrue(DiamondCutFacet(address(diamond)).isSelectorFrozen(RoutingProbeFacet.version.selector));
    }

    function test_UnknownSelectorReverts() public {
        (bool success, bytes memory returndata) = address(diamond).call(hex"deadbeef");
        assertFalse(success);

        bytes4 errorSelector;
        assembly {
            errorSelector := mload(add(returndata, 0x20))
        }

        assertEq(errorSelector, FunctionNotFound.selector);
    }

    function test_Erc1155ReceiverCallbacksReturnMagicValues() public {
        bytes4 singleResult =
            IERC1155Receiver(address(diamond)).onERC1155Received(address(this), address(this), 1, 1, "");
        bytes4 batchResult = IERC1155Receiver(address(diamond))
            .onERC1155BatchReceived(address(this), address(this), new uint256[](0), new uint256[](0), "");

        assertEq(singleResult, IERC1155Receiver.onERC1155Received.selector);
        assertEq(batchResult, IERC1155Receiver.onERC1155BatchReceived.selector);
    }
}
