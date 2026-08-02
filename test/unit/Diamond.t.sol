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
    uint64 internal constant TEST_GOVERNANCE_DELAY = 15 minutes;

    event GovernanceDelayUpdated(uint64 previousDelay, uint64 newDelay);

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

    function test_FinalizationInstallsConfiguredGovernanceDelay() public {
        vm.prank(owner);
        DiamondCutFacet(address(diamond)).finalizeGovernanceDelay(owner, TEST_GOVERNANCE_DELAY);

        assertTrue(DiamondCutFacet(address(diamond)).governanceDelayFinalized());
        assertEq(DiamondCutFacet(address(diamond)).governanceDelay(), TEST_GOVERNANCE_DELAY);
    }

    function test_GovernanceDelayChangeUsesCurrentDelayAndOnlyAffectsNewSchedules() public {
        uint64 newDelay = 2 hours;
        address newOwner = makeAddr("snapshot-owner");
        bytes memory ownershipCall = abi.encodeCall(OwnershipFacet.transferOwnership, (newOwner));
        bytes memory delayCall = abi.encodeCall(DiamondCutFacet.setGovernanceDelay, (newDelay));

        vm.prank(owner);
        DiamondCutFacet(address(diamond)).finalizeGovernanceDelay(owner, TEST_GOVERNANCE_DELAY);
        vm.startPrank(owner);
        (, uint256 ownershipReadyAt) = DiamondCutFacet(address(diamond)).scheduleGovernanceOperation(ownershipCall);
        (, uint256 delayReadyAt) = DiamondCutFacet(address(diamond)).scheduleGovernanceOperation(delayCall);
        vm.stopPrank();

        assertEq(ownershipReadyAt, block.timestamp + TEST_GOVERNANCE_DELAY);
        assertEq(delayReadyAt, ownershipReadyAt);

        bytes32 delayOperationId = DiamondCutFacet(address(diamond)).governanceOperationId(delayCall);
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.GovernanceOperationTimelocked.selector, delayOperationId, delayReadyAt)
        );
        DiamondCutFacet(address(diamond)).setGovernanceDelay(newDelay);

        vm.warp(delayReadyAt);
        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit GovernanceDelayUpdated(TEST_GOVERNANCE_DELAY, newDelay);
        DiamondCutFacet(address(diamond)).setGovernanceDelay(newDelay);

        assertEq(DiamondCutFacet(address(diamond)).governanceDelay(), newDelay);
        assertEq(
            DiamondCutFacet(address(diamond))
                .governanceOperationReadyAt(DiamondCutFacet(address(diamond)).governanceOperationId(ownershipCall)),
            ownershipReadyAt
        );

        bytes memory feeCall = abi.encodeCall(OwnershipFacet.setMarketCreationFee, (55e6));
        vm.prank(owner);
        (, uint256 feeReadyAt) = DiamondCutFacet(address(diamond)).scheduleGovernanceOperation(feeCall);
        assertEq(feeReadyAt, block.timestamp + newDelay);
    }

    function test_GovernanceCanChooseZeroOrFullUint64Delay() public {
        vm.prank(owner);
        DiamondCutFacet(address(diamond)).finalizeGovernanceDelay(owner, 0);

        bytes memory maxDelayCall = abi.encodeCall(DiamondCutFacet.setGovernanceDelay, (type(uint64).max));
        vm.startPrank(owner);
        (, uint256 readyAt) = DiamondCutFacet(address(diamond)).scheduleGovernanceOperation(maxDelayCall);
        assertEq(readyAt, block.timestamp);
        DiamondCutFacet(address(diamond)).setGovernanceDelay(type(uint64).max);

        bytes memory feeCall = abi.encodeCall(OwnershipFacet.setMarketCreationFee, (1));
        (, uint256 feeReadyAt) = DiamondCutFacet(address(diamond)).scheduleGovernanceOperation(feeCall);
        vm.stopPrank();

        assertEq(feeReadyAt, block.timestamp + type(uint64).max);
    }

    function test_RevertWhen_GovernanceDelayChangeIsUnfinalizedUnscheduledOrUnauthorized() public {
        vm.prank(owner);
        vm.expectRevert(Errors.GovernanceDelayNotFinalized.selector);
        DiamondCutFacet(address(diamond)).setGovernanceDelay(1 hours);

        vm.prank(owner);
        DiamondCutFacet(address(diamond)).finalizeGovernanceDelay(owner, TEST_GOVERNANCE_DELAY);

        bytes memory callData = abi.encodeCall(DiamondCutFacet.setGovernanceDelay, (1 hours));
        bytes32 operationId = DiamondCutFacet(address(diamond)).governanceOperationId(callData);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Errors.GovernanceOperationNotScheduled.selector, operationId));
        DiamondCutFacet(address(diamond)).setGovernanceDelay(1 hours);

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotContractOwner.selector, outsider));
        DiamondCutFacet(address(diamond)).setGovernanceDelay(1 hours);
    }

    function test_FinalizedGovernanceRequiresExactDelayedOwnershipCall() public {
        address newOwner = makeAddr("delayed-owner");
        vm.prank(owner);
        DiamondCutFacet(address(diamond)).finalizeGovernanceDelay(owner, TEST_GOVERNANCE_DELAY);
        bytes memory callData = abi.encodeCall(OwnershipFacet.transferOwnership, (newOwner));
        bytes32 operationId = DiamondCutFacet(address(diamond)).governanceOperationId(callData);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Errors.GovernanceOperationNotScheduled.selector, operationId));
        OwnershipFacet(address(diamond)).transferOwnership(newOwner);

        vm.prank(owner);
        (, uint256 readyAt) = DiamondCutFacet(address(diamond)).scheduleGovernanceOperation(callData);
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
        DiamondCutFacet(address(diamond)).finalizeGovernanceDelay(owner, TEST_GOVERNANCE_DELAY);
        vm.prank(owner);
        (, uint256 readyAt) = DiamondCutFacet(address(diamond)).scheduleGovernanceOperation(callData);
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
        DiamondCutFacet(address(diamond)).finalizeGovernanceDelay(owner, TEST_GOVERNANCE_DELAY);
        bytes memory callData = abi.encodeCall(OwnershipFacet.transferOwnership, (newOwner));
        bytes32 operationId = DiamondCutFacet(address(diamond)).governanceOperationId(callData);
        vm.prank(owner);
        (, uint256 readyAt) = DiamondCutFacet(address(diamond)).scheduleGovernanceOperation(callData);
        uint256 elapsed = bound(uint256(elapsedRaw), 0, TEST_GOVERNANCE_DELAY - 1);
        vm.warp(readyAt - TEST_GOVERNANCE_DELAY + elapsed);

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
