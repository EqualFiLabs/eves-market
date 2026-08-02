// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC1155Receiver} from "../../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155Receiver.sol";

import {DiamondCutFacet} from "../../src/facets/DiamondCutFacet.sol";
import {Errors} from "../../src/libraries/Errors.sol";

import {DiamondFixture, RoutingProbeFacet, RoutingProbeFacetV2} from "../helpers/DiamondFixtures.sol";

contract DiamondPropertiesTest is DiamondFixture {
    // Feature: eve-prediction-market, Property 2: frozen selector immutability
    function testFuzz_FrozenSelectorsCannotBeReplacedOrRemoved(uint8 selectorSeed) public {
        bytes4[] memory probeSelectors = _routingProbeSelectors();
        bytes4 selector = probeSelectors[bound(selectorSeed, 0, probeSelectors.length - 1)];
        bytes4[] memory frozenSelectors = new bytes4[](1);
        frozenSelectors[0] = selector;

        vm.prank(owner);
        DiamondCutFacet(address(diamond)).freezeFacet(frozenSelectors);

        vm.expectRevert(abi.encodeWithSelector(Errors.SelectorFrozen.selector, selector));
        _replaceFacet(address(routingProbeV2), frozenSelectors);

        vm.expectRevert(abi.encodeWithSelector(Errors.SelectorFrozen.selector, selector));
        _removeSelectors(frozenSelectors);
    }

    // Feature: eve-prediction-market, Property 34: diamond selector routing
    function testFuzz_DiamondSelectorRouting(uint256 newWord) public {
        RoutingProbeFacet(address(diamond)).storeWord(newWord);

        assertEq(RoutingProbeFacet(address(diamond)).readWord(), newWord);
        assertEq(RoutingProbeFacet(address(diamond)).version(), 1);
    }

    // Feature: eve-prediction-market, Property 40: ERC-1155 receiver compliance
    function test_DiamondReturnsErc1155ReceiverMagicValues() public {
        bytes4 singleResult =
            IERC1155Receiver(address(diamond)).onERC1155Received(address(this), address(this), 1, 1, "");
        bytes4 batchResult = IERC1155Receiver(address(diamond))
            .onERC1155BatchReceived(address(this), address(this), new uint256[](0), new uint256[](0), "");

        assertEq(singleResult, IERC1155Receiver.onERC1155Received.selector);
        assertEq(batchResult, IERC1155Receiver.onERC1155BatchReceived.selector);
    }
}
