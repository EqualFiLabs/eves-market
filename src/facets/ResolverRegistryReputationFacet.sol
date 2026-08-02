// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Errors} from "../libraries/Errors.sol";
import {Events} from "../libraries/Events.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibResolverJury} from "../libraries/LibResolverJury.sol";

contract ResolverRegistryReputationFacet {
    function applyFinalityReputation(bytes32 disputeId, uint8 finalResult) external {
        if (msg.sender != address(this)) {
            revert Errors.InternalCallOnly(msg.sender);
        }

        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        LibResolverJury.Dispute storage dispute = jury.disputes[disputeId];
        if (dispute.reputationApplied) {
            return;
        }
        if (dispute.marketId == bytes32(0)) {
            revert Errors.MarketNotFound(dispute.marketId);
        }

        dispute.reputationApplied = true;
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();

        _reputationApplyCreatorFinality(jury, state, dispute.marketId, finalResult);
        _reputationApplyResolverFinality(jury, dispute, finalResult);
    }

    function _reputationApplyCreatorFinality(
        LibResolverJury.ResolverJuryStorage storage jury,
        LibEveMarket.EveMarketStorage storage state,
        bytes32 marketId,
        uint8 finalResult
    ) internal {
        address creator = state.markets[marketId].creator;
        if (creator == address(0)) {
            return;
        }

        uint256 creatorIdentityId = jury.identityByOwner[creator];
        if (creatorIdentityId == 0) {
            return;
        }

        LibResolverJury.CreatorReputation storage reputation = jury.creatorRep[creatorIdentityId];
        reputation.marketsResolved += 1;
        if (_reputationCreatorProposedOutcome(state, marketId) == finalResult) {
            reputation.outcomesUpheld += 1;
        } else {
            reputation.outcomesOverturned += 1;
        }

        emit Events.CreatorReputationUpdated(
            creatorIdentityId,
            reputation.marketsCreated,
            reputation.marketsResolved,
            reputation.disputesRaised,
            reputation.outcomesUpheld,
            reputation.outcomesOverturned
        );
    }

    function _reputationApplyResolverFinality(
        LibResolverJury.ResolverJuryStorage storage jury,
        LibResolverJury.Dispute storage dispute,
        uint8 finalResult
    ) internal {
        uint256 selectedCount = dispute.allSelected.length;
        for (uint256 index; index < selectedCount; ++index) {
            uint256 identityId = dispute.allSelected[index];
            LibResolverJury.ResolverReputation storage reputation = jury.resolverRep[identityId];
            if (_reputationResolverAgreedWithFinalResult(dispute, identityId, finalResult)) {
                reputation.finalAgreementCount += 1;
            }

            emit Events.ResolverReputationUpdated(
                identityId,
                reputation.totalSelections,
                reputation.commitCount,
                reputation.revealCount,
                reputation.finalAgreementCount,
                reputation.slashCount
            );
        }
    }

    function _reputationResolverAgreedWithFinalResult(
        LibResolverJury.Dispute storage dispute,
        uint256 identityId,
        uint8 finalResult
    ) internal view returns (bool) {
        for (uint8 round; round <= dispute.currentRound; ++round) {
            LibResolverJury.DisputeRound storage disputeRound = dispute.rounds[round];
            if (disputeRound.hasRevealed[identityId] && disputeRound.revealedOutcome[identityId] == finalResult) {
                return true;
            }
        }

        return false;
    }

    function _reputationCreatorProposedOutcome(LibEveMarket.EveMarketStorage storage state, bytes32 marketId)
        internal
        view
        returns (uint8)
    {
        LibEveMarket.Resolution storage current = state.resolutions[marketId];
        if (current.proposer != address(0)) {
            return current.proposedOutcome;
        }

        LibEveMarket.Resolution[] storage history = state.resolutionHistory[marketId];
        if (history.length == 0) {
            return uint8(LibEveMarket.MarketOutcome.Unresolved);
        }

        return history[history.length - 1].proposedOutcome;
    }
}
