// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {DiamondCutFacet} from "../../src/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "../../src/facets/DiamondLoupeFacet.sol";
import {OBRResolutionFacet} from "../../src/facets/OBRResolutionFacet.sol";
import {ResolverJuryFacet} from "../../src/facets/ResolverJuryFacet.sol";
import {ResolverRegistryFacet} from "../../src/facets/ResolverRegistryFacet.sol";
import {ResolverJuryInit} from "../../src/init/ResolverJuryInit.sol";
import {IOBRResolutionFacet} from "../../src/interfaces/IOBRResolutionFacet.sol";
import {IResolverJuryFacet} from "../../src/interfaces/IResolverJuryFacet.sol";
import {IResolverRegistryFacet} from "../../src/interfaces/IResolverRegistryFacet.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {LibMarketCreation} from "../../src/libraries/LibMarketCreation.sol";
import {LibResolverJury} from "../../src/libraries/LibResolverJury.sol";
import {EveIdentity} from "../../src/tokens/EveIdentity.sol";

import {ResolutionFixture, StateProbeFacet} from "../helpers/DiamondFixtures.sol";

contract ResolverJuryMigrationTest is ResolutionFixture {
    bytes32 internal constant DISPUTE_DOMAIN = keccak256("eve.dispute");

    ResolverRegistryFacet internal migrationRegistryFacet;
    ResolverJuryFacet internal migrationJuryFacet;
    OBRResolutionFacet internal migrationObrFacet;
    EveIdentity internal migrationIdentity;

    function setUp() public override {
        super.setUp();

        _removeSelectors(_resolverJurySelectors());
    }

    function test_DiamondCutMigrationPreservesFastPathAndRoutesNewEscalation() public {
        (bytes32 preUpgradeMarketId,) = _createPendingMarket("Migration fast path", "resolution", 7 days);
        ExpectedMarketData memory expected = _expectedFromStored(preUpgradeMarketId);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(preUpgradeMarketId, 1);

        (,,,,,, uint64 disputeDeadline,) = StateProbeFacet(address(diamond)).getStoredResolution(preUpgradeMarketId);

        _applyResolverJuryMigration();

        vm.warp(disputeDeadline);
        IOBRResolutionFacet(address(diamond)).finalizeResolution(preUpgradeMarketId);

        _assertResolvedStatus(preUpgradeMarketId, expected.marketId, 1);
        _assertPayout(expected.conditionId, 1, 0, 1);

        (bytes32 escalatedMarketId,) = _createPendingMarket("Migration jury route", "resolution", 8 days);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(escalatedMarketId, 1);

        vm.prank(challengerOne);
        IOBRResolutionFacet(address(diamond)).disputeResolution(escalatedMarketId, 2);

        vm.prank(challengerTwo);
        IOBRResolutionFacet(address(diamond)).disputeResolution(escalatedMarketId, 3);

        vm.prank(challengerThree);
        IOBRResolutionFacet(address(diamond)).disputeResolution(escalatedMarketId, 1);

        bytes32 disputeId = _disputeIdForMarket(escalatedMarketId);
        IResolverJuryFacet.DisputeView memory dispute = IResolverJuryFacet(address(diamond)).disputeView(disputeId);
        (,,,,,, uint8 marketState,) = StateProbeFacet(address(diamond)).getStoredMarketStatus(escalatedMarketId);

        assertEq(dispute.marketId, escalatedMarketId);
        assertEq(dispute.state, uint8(LibResolverJury.DisputeState.CommitteeSelectionPending));
        assertFalse(dispute.finalized);
        assertEq(marketState, uint8(LibEveMarket.MarketState.Disputed));
    }

    function _applyResolverJuryMigration() internal {
        migrationRegistryFacet = new ResolverRegistryFacet();
        migrationJuryFacet = new ResolverJuryFacet();
        migrationObrFacet = new OBRResolutionFacet();
        migrationIdentity = new EveIdentity(address(diamond), "Eve Identity", "EVE-ID");

        DiamondCutFacet.FacetCut[] memory cuts = new DiamondCutFacet.FacetCut[](3);
        cuts[0] = DiamondCutFacet.FacetCut({
            facetAddress: address(migrationRegistryFacet),
            action: DiamondCutFacet.FacetCutAction.Add,
            functionSelectors: _resolverRegistrySelectors()
        });
        cuts[1] = DiamondCutFacet.FacetCut({
            facetAddress: address(migrationJuryFacet),
            action: DiamondCutFacet.FacetCutAction.Add,
            functionSelectors: _resolverJuryInterfaceSelectors()
        });
        cuts[2] = DiamondCutFacet.FacetCut({
            facetAddress: address(migrationObrFacet),
            action: DiamondCutFacet.FacetCutAction.Replace,
            functionSelectors: _obrResolutionSelectors()
        });

        ResolverJuryInit init = new ResolverJuryInit();

        vm.prank(owner);
        DiamondCutFacet(address(diamond))
            .diamondCut(
                cuts, address(init), abi.encodeCall(ResolverJuryInit.initResolverJury, (address(migrationIdentity)))
            );

        assertEq(
            DiamondLoupeFacet(address(diamond)).facetAddress(IResolverRegistryFacet.mintIdentity.selector),
            address(migrationRegistryFacet)
        );
        assertEq(
            DiamondLoupeFacet(address(diamond)).facetAddress(IResolverJuryFacet.initiateDispute.selector),
            address(migrationJuryFacet)
        );
        assertEq(
            DiamondLoupeFacet(address(diamond)).facetAddress(IOBRResolutionFacet.disputeResolution.selector),
            address(migrationObrFacet)
        );

        uint256 identityId = IResolverRegistryFacet(address(diamond)).mintIdentity();
        assertEq(migrationIdentity.ownerOf(identityId), address(this));
    }

    function _resolverRegistrySelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](23);
        selectors[0] = IResolverRegistryFacet.mintIdentity.selector;
        selectors[1] = IResolverRegistryFacet.setCreatorRole.selector;
        selectors[2] = IResolverRegistryFacet.setResolverRole.selector;
        selectors[3] = IResolverRegistryFacet.depositResolverStake.selector;
        selectors[4] = IResolverRegistryFacet.openResolverEpochRotation.selector;
        selectors[5] = IResolverRegistryFacet.requestResolverExit.selector;
        selectors[6] = IResolverRegistryFacet.withdrawResolverStake.selector;
        selectors[7] = IResolverRegistryFacet.eveIdentity.selector;
        selectors[8] = IResolverRegistryFacet.resolverDashboard.selector;
        selectors[9] = IResolverRegistryFacet.resolverIdentity.selector;
        selectors[10] = IResolverRegistryFacet.resolverIdentityByOwner.selector;
        selectors[11] = IResolverRegistryFacet.resolverJuryConfig.selector;
        selectors[12] = IResolverRegistryFacet.identityByOwner.selector;
        selectors[13] = IResolverRegistryFacet.isEligibleResolver.selector;
        selectors[14] = IResolverRegistryFacet.hasConflict.selector;
        selectors[15] = IResolverRegistryFacet.resolverLifecycleState.selector;
        selectors[16] = IResolverRegistryFacet.creatorReputation.selector;
        selectors[17] = IResolverRegistryFacet.resolverReputation.selector;
        selectors[18] = IResolverRegistryFacet.eligibleResolverCount.selector;
        selectors[19] = IResolverRegistryFacet.activeResolverCount.selector;
        selectors[20] = IResolverRegistryFacet.activeResolverEpochSize.selector;
        selectors[21] = IResolverRegistryFacet.activeResolverAt.selector;
        selectors[22] = IResolverRegistryFacet.applyFinalityReputation.selector;
    }

    function _resolverJuryInterfaceSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](19);
        selectors[0] = IResolverJuryFacet.initiateDispute.selector;
        selectors[1] = IResolverJuryFacet.openRandomnessCommit.selector;
        selectors[2] = IResolverJuryFacet.commitRandomness.selector;
        selectors[3] = IResolverJuryFacet.closeRandomnessCommit.selector;
        selectors[4] = IResolverJuryFacet.revealRandomness.selector;
        selectors[5] = IResolverJuryFacet.closeRandomnessReveal.selector;
        selectors[6] = IResolverJuryFacet.selectCommittee.selector;
        selectors[7] = IResolverJuryFacet.closeCommit.selector;
        selectors[8] = IResolverJuryFacet.closeRevealAndTally.selector;
        selectors[9] = IResolverJuryFacet.openAppeal.selector;
        selectors[10] = IResolverJuryFacet.finalizeDispute.selector;
        selectors[11] = IResolverJuryFacet.applyRandomnessFallback.selector;
        selectors[12] = IResolverJuryFacet.commitVote.selector;
        selectors[13] = IResolverJuryFacet.revealVote.selector;
        selectors[14] = IResolverJuryFacet.disputeView.selector;
        selectors[15] = IResolverJuryFacet.committeeMembers.selector;
        selectors[16] = IResolverJuryFacet.outcomeTally.selector;
        selectors[17] = IResolverJuryFacet.revealedVote.selector;
        selectors[18] = IResolverJuryFacet.provisionalResult.selector;
    }

    function _disputeIdForMarket(bytes32 marketId) internal pure returns (bytes32 disputeId) {
        disputeId = keccak256(abi.encode(DISPUTE_DOMAIN, marketId));
    }

    function _expectedFromStored(bytes32 marketId) internal view returns (ExpectedMarketData memory expected) {
        (,, bytes32 questionId, bytes32 conditionId, uint256 yesPositionId, uint256 noPositionId) =
            StateProbeFacet(address(diamond)).getStoredMarketCore(marketId);

        expected.marketId = marketId;
        expected.questionId = questionId;
        expected.resolutionId = LibMarketCreation.resolutionIdFor(marketId);
        expected.conditionId = conditionId;
        expected.yesPositionId = yesPositionId;
        expected.noPositionId = noPositionId;
    }

    function _assertResolvedStatus(bytes32 marketId, bytes32 expectedMarketId, uint8 expectedOutcome) internal view {
        (bytes32 storedMarketId,,,,, uint8 outcome, uint8 state,) =
            StateProbeFacet(address(diamond)).getStoredMarketStatus(marketId);

        assertEq(storedMarketId, expectedMarketId);
        assertEq(outcome, expectedOutcome);
        assertEq(state, uint8(LibEveMarket.MarketState.Resolved));
    }

    function _assertPayout(bytes32 conditionId, uint256 expectedYes, uint256 expectedNo, uint256 expectedDenominator)
        internal
        view
    {
        (,,, bool prepared, bool reported, uint256 payoutDenominator) =
            conditionalTokens.getConditionDetails(conditionId);
        uint256[] memory payouts = conditionalTokens.getPayoutNumerators(conditionId);

        assertTrue(prepared);
        assertTrue(reported);
        assertEq(payoutDenominator, expectedDenominator);
        assertEq(payouts[0], expectedYes);
        assertEq(payouts[1], expectedNo);
    }
}
