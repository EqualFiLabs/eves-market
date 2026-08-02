// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC1155Receiver} from "../../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155Receiver.sol";

import {FunctionNotFound} from "../../src/EveMarketDiamond.sol";
import {DiamondCutFacet} from "../../src/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "../../src/facets/DiamondLoupeFacet.sol";
import {OwnershipFacet} from "../../src/facets/OwnershipFacet.sol";
import {FeeConfigFacet} from "../../src/facets/FeeConfigFacet.sol";
import {Errors} from "../../src/libraries/Errors.sol";

import {DiamondFixture, RoutingProbeFacet, RoutingProbeFacetV2, StateProbeFacet} from "../helpers/DiamondFixtures.sol";
import {MockCurveProfile} from "../helpers/MockCurveProfile.sol";

contract GovernanceInitProbe {
    bytes32 internal constant WORD_SLOT = bytes32(uint256(keccak256("eve.prediction.market.routing.probe.word")) - 1);

    function initialize(uint256 value) external {
        bytes32 slot = WORD_SLOT;
        assembly {
            sstore(slot, value)
        }
    }
}

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
            DiamondLoupeFacet(address(diamond)).facetAddress(FeeConfigFacet.setOrderbookEntryFeeBps.selector),
            address(feeConfigFacet)
        );

        address[] memory facetAddresses_ = DiamondLoupeFacet(address(diamond)).facetAddresses();
        assertEq(facetAddresses_.length, 6);

        bytes4[] memory probeSelectors =
            DiamondLoupeFacet(address(diamond)).facetFunctionSelectors(address(routingProbe));
        assertEq(probeSelectors.length, 3);
        assertEq(probeSelectors[0], RoutingProbeFacet.storeWord.selector);
        assertEq(probeSelectors[1], RoutingProbeFacet.readWord.selector);
        assertEq(probeSelectors[2], RoutingProbeFacet.version.selector);

        DiamondLoupeFacet.Facet[] memory allFacets = DiamondLoupeFacet(address(diamond)).facets();
        assertEq(allFacets.length, 6);
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
        FeeConfigFacet(address(diamond)).setOrderbookEntryFeeBps(77);
    }

    function test_TransferOwnershipMovesAdminRights() public {
        address newOwner = makeAddr("new-owner");

        vm.prank(owner);
        OwnershipFacet(address(diamond)).transferOwnership(newOwner);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotContractOwner.selector, owner));
        FeeConfigFacet(address(diamond)).setOrderbookEntryFeeBps(91);

        vm.prank(newOwner);
        FeeConfigFacet(address(diamond)).setOrderbookEntryFeeBps(91);
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

    function test_RevertWhen_FreezingUnroutedSelector() public {
        bytes4 unroutedSelector = bytes4(keccak256("unroutedSelector()"));
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = unroutedSelector;

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Errors.SelectorMissing.selector, unroutedSelector));
        DiamondCutFacet(address(diamond)).freezeFacet(selectors);
        assertFalse(DiamondCutFacet(address(diamond)).isSelectorFrozen(unroutedSelector));
    }

    function test_FinalizedGovernanceRequiresExactDelayedOwnershipCall() public {
        address newOwner = makeAddr("delayed-owner");
        vm.prank(owner);
        DiamondCutFacet(address(diamond)).finalizeGovernanceDelay(owner);
        bytes memory callData = abi.encodeCall(OwnershipFacet.transferOwnership, (newOwner));
        bytes32 operationId = DiamondCutFacet(address(diamond)).governanceOperationId(callData);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Errors.GovernanceOperationNotScheduled.selector, operationId));
        OwnershipFacet(address(diamond)).transferOwnership(newOwner);

        vm.prank(owner);
        (, uint64 readyAt) = DiamondCutFacet(address(diamond)).scheduleGovernanceOperation(callData);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Errors.GovernanceOperationTimelocked.selector, operationId, readyAt));
        OwnershipFacet(address(diamond)).transferOwnership(newOwner);

        vm.warp(readyAt);
        vm.prank(owner);
        OwnershipFacet(address(diamond)).transferOwnership(newOwner);
        assertEq(OwnershipFacet(address(diamond)).owner(), newOwner);
        assertEq(DiamondCutFacet(address(diamond)).governanceOperationReadyAt(operationId), 0);
    }

    function test_DelayedCutCoversInitializerAndCannotReplay() public {
        GovernanceInitProbe init = new GovernanceInitProbe();
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = RoutingProbeFacet.version.selector;
        DiamondCutFacet.FacetCut[] memory cuts = new DiamondCutFacet.FacetCut[](1);
        cuts[0] = DiamondCutFacet.FacetCut({
            facetAddress: address(routingProbeV2),
            action: DiamondCutFacet.FacetCutAction.Replace,
            functionSelectors: selectors
        });
        bytes memory initData = abi.encodeCall(GovernanceInitProbe.initialize, (77));
        bytes memory callData = abi.encodeCall(DiamondCutFacet.diamondCut, (cuts, address(init), initData));

        vm.prank(owner);
        DiamondCutFacet(address(diamond)).finalizeGovernanceDelay(owner);
        vm.prank(owner);
        (, uint64 readyAt) = DiamondCutFacet(address(diamond)).scheduleGovernanceOperation(callData);
        vm.warp(readyAt);
        vm.prank(owner);
        DiamondCutFacet(address(diamond)).diamondCut(cuts, address(init), initData);

        assertEq(RoutingProbeFacet(address(diamond)).version(), 2);
        assertEq(RoutingProbeFacet(address(diamond)).readWord(), 77);
        bytes32 operationId = DiamondCutFacet(address(diamond)).governanceOperationId(callData);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Errors.GovernanceOperationNotScheduled.selector, operationId));
        DiamondCutFacet(address(diamond)).diamondCut(cuts, address(init), initData);
    }

    function testFuzz_FinalizedGovernanceCannotExecuteBeforeReady(uint32 elapsedRaw) public {
        address newOwner = makeAddr("fuzz-delayed-owner");
        vm.prank(owner);
        DiamondCutFacet(address(diamond)).finalizeGovernanceDelay(owner);
        bytes memory callData = abi.encodeCall(OwnershipFacet.transferOwnership, (newOwner));
        bytes32 operationId = DiamondCutFacet(address(diamond)).governanceOperationId(callData);
        vm.prank(owner);
        (, uint64 readyAt) = DiamondCutFacet(address(diamond)).scheduleGovernanceOperation(callData);
        uint256 elapsed = bound(uint256(elapsedRaw), 0, 7 days - 1);
        vm.warp(uint256(readyAt) - 7 days + elapsed);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Errors.GovernanceOperationTimelocked.selector, operationId, readyAt));
        OwnershipFacet(address(diamond)).transferOwnership(newOwner);
        assertEq(OwnershipFacet(address(diamond)).owner(), owner);

        vm.warp(readyAt);
        vm.prank(owner);
        OwnershipFacet(address(diamond)).transferOwnership(newOwner);
        assertEq(OwnershipFacet(address(diamond)).owner(), newOwner);
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
