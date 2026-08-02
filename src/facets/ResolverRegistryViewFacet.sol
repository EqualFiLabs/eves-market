// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC1155} from "../../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";

import {IEveIdentity} from "../interfaces/IEveIdentity.sol";
import {IResolverRegistryFacet} from "../interfaces/IResolverRegistryFacet.sol";
import {Errors} from "../libraries/Errors.sol";
import {LibCLOBBook} from "../libraries/LibCLOBBook.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibResolverJury} from "../libraries/LibResolverJury.sol";
import {LibResolverRewards} from "../libraries/LibResolverRewards.sol";

contract ResolverRegistryViewFacet {
    function eveIdentity() external view returns (address) {
        return LibResolverJury.store().eveIdentity;
    }

    function resolverDashboard(address owner)
        external
        view
        returns (
            IResolverRegistryFacet.ResolverIdentityView memory identity,
            IResolverRegistryFacet.ResolverJuryConfigView memory config,
            IResolverRegistryFacet.ResolverEpochPoolView memory epochPool
        )
    {
        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        uint256 identityId;
        if (jury.eveIdentity != address(0)) {
            identityId = IEveIdentity(jury.eveIdentity).identityOf(owner);
        }

        identity = _viewResolverIdentity(jury, state, identityId);
        config = _viewResolverJuryConfig(jury.eveIdentity, state.config.resolverJuryConfig);
        epochPool = _viewResolverEpochPool(jury, state);
    }

    function resolverIdentity(uint256 identityId)
        external
        view
        returns (IResolverRegistryFacet.ResolverIdentityView memory view_)
    {
        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        view_ = _viewResolverIdentity(jury, LibEveMarket.store(), identityId);
    }

    function resolverIdentityByOwner(address owner)
        external
        view
        returns (IResolverRegistryFacet.ResolverIdentityView memory view_)
    {
        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        uint256 identityId;
        if (jury.eveIdentity != address(0)) {
            identityId = IEveIdentity(jury.eveIdentity).identityOf(owner);
        }

        view_ = _viewResolverIdentity(jury, LibEveMarket.store(), identityId);
    }

    function resolverJuryConfig() external view returns (IResolverRegistryFacet.ResolverJuryConfigView memory view_) {
        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        view_ = _viewResolverJuryConfig(jury.eveIdentity, LibEveMarket.store().config.resolverJuryConfig);
    }

    function identityByOwner(address owner) external view returns (uint256 identityId) {
        address identityContract = LibResolverJury.store().eveIdentity;
        if (identityContract == address(0)) {
            return 0;
        }

        return IEveIdentity(identityContract).identityOf(owner);
    }

    function isEligibleResolver(uint256 identityId, bytes32 disputeId) external view returns (bool) {
        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        return _viewIsEligibleResolver(jury, LibEveMarket.store(), identityId, disputeId);
    }

    function hasConflict(uint256 identityId, bytes32 marketId) external view returns (bool) {
        return _viewHasConflict(LibResolverJury.store(), LibEveMarket.store(), identityId, marketId);
    }

    function resolverLifecycleState(uint256 identityId) external view returns (uint8) {
        LibResolverJury.ResolverIdentityRecord storage record = LibResolverJury.store().identities[identityId];
        return uint8(_viewEffectiveLifecycle(record, LibEveMarket.store().config.resolverJuryConfig));
    }

    function creatorReputation(uint256 identityId)
        external
        view
        returns (IResolverRegistryFacet.CreatorReputationView memory view_)
    {
        LibResolverJury.CreatorReputation storage rep = LibResolverJury.store().creatorRep[identityId];
        view_ = IResolverRegistryFacet.CreatorReputationView({
            marketsCreated: rep.marketsCreated,
            marketsResolved: rep.marketsResolved,
            disputesRaised: rep.disputesRaised,
            outcomesUpheld: rep.outcomesUpheld,
            outcomesOverturned: rep.outcomesOverturned,
            totalVolume: rep.totalVolume,
            cumulativeSettleDelay: rep.cumulativeSettleDelay
        });
    }

    function resolverReputation(uint256 identityId)
        external
        view
        returns (IResolverRegistryFacet.ResolverReputationView memory view_)
    {
        LibResolverJury.ResolverReputation storage rep = LibResolverJury.store().resolverRep[identityId];
        view_ = IResolverRegistryFacet.ResolverReputationView({
            activationTimestamp: rep.activationTimestamp,
            totalSelections: rep.totalSelections,
            commitCount: rep.commitCount,
            revealCount: rep.revealCount,
            missedCommitCount: rep.missedCommitCount,
            missedRevealCount: rep.missedRevealCount,
            invalidRevealCount: rep.invalidRevealCount,
            finalAgreementCount: rep.finalAgreementCount,
            slashCount: rep.slashCount,
            minorityUpheldCount: rep.minorityUpheldCount
        });
    }

    function eligibleResolverCount() external view returns (uint256 count) {
        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        return _viewEligibleResolverCount(jury, state);
    }

    function activeResolverCount() external view returns (uint256) {
        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        return jury.resolverEpochs[jury.currentResolverEpoch].activeSet.length;
    }

    function activeResolverEpochSize() external view returns (uint16) {
        return LibEveMarket.store().config.resolverJuryConfig.activeEpochSize;
    }

    function activeResolverAt(uint256 index) external view returns (uint256 identityId) {
        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        return jury.resolverEpochs[jury.currentResolverEpoch].activeSet[index];
    }

    function currentResolverEpoch() external view returns (uint64) {
        return LibResolverJury.store().currentResolverEpoch;
    }

    function resolverEpoch(uint64 epochId)
        external
        view
        returns (IResolverRegistryFacet.ResolverEpochView memory view_)
    {
        LibResolverJury.ResolverEpoch storage epoch = LibResolverJury.store().resolverEpochs[epochId];
        view_ = IResolverRegistryFacet.ResolverEpochView({
            epochId: epoch.epochId,
            startTime: epoch.startTime,
            endTime: epoch.endTime,
            rotationOpenedAt: epoch.rotationOpenedAt,
            commitDeadline: epoch.commitDeadline,
            revealDeadline: epoch.revealDeadline,
            selectionDeadline: epoch.selectionDeadline,
            seedReferenceBlock: epoch.seedReferenceBlock,
            validRevealCount: epoch.validRevealCount,
            seed: epoch.seed,
            seedFinalized: epoch.seedFinalized,
            selectionFinalized: epoch.selectionFinalized,
            candidateCount: epoch.candidates.length,
            scoreSubmittedCount: epoch.scoreSubmittedCount,
            selectedCount: epoch.selected.length,
            activeCount: epoch.activeSet.length
        });
    }

    function resolverEpochCandidate(uint64 epochId, uint256 identityId)
        external
        view
        returns (IResolverRegistryFacet.ResolverEpochCandidateView memory view_)
    {
        LibResolverJury.ResolverEpochCandidate storage candidate =
            LibResolverJury.store().resolverEpochs[epochId].candidateByIdentity[identityId];
        view_ = IResolverRegistryFacet.ResolverEpochCandidateView({
            optedIn: candidate.optedIn,
            selected: candidate.selected,
            scoreSubmitted: candidate.scoreSubmitted,
            score: candidate.score,
            hasCommitted: candidate.randomness.hasCommitted,
            hasRevealed: candidate.randomness.hasRevealed
        });
    }

    function previewResolverRewards(uint256 identityId, address token)
        external
        view
        returns (uint128 accrued, uint128 claimed, uint128 claimable)
    {
        return LibResolverRewards.claimable(identityId, token);
    }

    function _viewResolverIdentity(
        LibResolverJury.ResolverJuryStorage storage jury,
        LibEveMarket.EveMarketStorage storage state,
        uint256 identityId
    ) internal view returns (IResolverRegistryFacet.ResolverIdentityView memory view_) {
        if (identityId == 0) {
            return view_;
        }

        LibResolverJury.ResolverIdentityRecord storage record = jury.identities[identityId];
        LibEveMarket.ResolverJuryConfig storage config = state.config.resolverJuryConfig;
        address identityContract = jury.eveIdentity;
        address owner;
        bool creatorRole;
        bool resolverRole;
        if (identityContract != address(0)) {
            IEveIdentity identityToken = IEveIdentity(identityContract);
            owner = identityToken.ownerOf(identityId);
            creatorRole = identityToken.hasCreatorRole(identityId);
            resolverRole = identityToken.hasResolverRole(identityId);
        }

        view_ = IResolverRegistryFacet.ResolverIdentityView({
            identityId: identityId,
            owner: owner,
            creatorRole: creatorRole,
            resolverRole: resolverRole,
            lifecycle: uint8(record.lifecycle),
            effectiveLifecycle: uint8(_viewEffectiveLifecycle(record, config)),
            resolverStake: record.resolverStake,
            activationTimestamp: record.activationTimestamp,
            activeAt: _viewBoundedTimestamp(record.activationTimestamp, config.activationDelay),
            exitTimestamp: record.exitTimestamp,
            withdrawableAt: _viewBoundedTimestamp(record.exitTimestamp, config.exitCooldown),
            unresolvedCommittees: record.unresolvedCommittees,
            slashLockUntil: record.slashLockUntil,
            slashLockActive: record.slashLockActive,
            currentEpochMember: _viewIsCurrentEpochMember(jury, identityId),
            globallyEligible: _viewIsEligibleResolver(jury, state, identityId, bytes32(0))
        });
    }

    function _viewResolverJuryConfig(address identityContract, LibEveMarket.ResolverJuryConfig storage config)
        internal
        view
        returns (IResolverRegistryFacet.ResolverJuryConfigView memory view_)
    {
        uint256 committeeSizeCount = config.committeeSizesByRound.length;
        uint16[] memory committeeSizes = new uint16[](committeeSizeCount);
        for (uint256 index; index < committeeSizeCount; ++index) {
            committeeSizes[index] = config.committeeSizesByRound[index];
        }

        view_ = IResolverRegistryFacet.ResolverJuryConfigView({
            eveIdentity: identityContract,
            identityMintFeeToken: config.identityMintFeeToken,
            identityMintFee: config.identityMintFee,
            resolverSeatStake: config.resolverSeatStake,
            epochCandidateFeeToken: config.epochCandidateFeeToken,
            epochCandidateFeeAmount: config.epochCandidateFeeAmount,
            activeEpochSize: config.activeEpochSize,
            resolverEpochDuration: config.resolverEpochDuration,
            resolverRotationWindow: config.resolverRotationWindow,
            epochRandomnessCommitDuration: config.epochRandomnessCommitDuration,
            epochRandomnessRevealDuration: config.epochRandomnessRevealDuration,
            epochSelectionDuration: config.epochSelectionDuration,
            minEpochRandomnessReveals: config.minEpochRandomnessReveals,
            activationDelay: config.activationDelay,
            exitCooldown: config.exitCooldown,
            participationThresholdBps: config.participationThresholdBps,
            concurrencyLimit: config.concurrencyLimit,
            participationGraceCount: config.participationGraceCount,
            conflictPositionThreshold: config.conflictPositionThreshold,
            committeeSizesByRound: committeeSizes,
            maxAppealRounds: config.maxAppealRounds,
            appealBondMultiplierBps: config.appealBondMultiplierBps,
            randomnessCommitDuration: config.randomnessCommitDuration,
            randomnessRevealDuration: config.randomnessRevealDuration,
            commitDuration: config.commitDuration,
            revealDuration: config.revealDuration,
            appealWindow: config.appealWindow,
            randomnessTimeout: config.randomnessTimeout,
            quorum: config.quorum,
            redrawLimit: config.redrawLimit,
            lowQuorumMode: uint8(config.lowQuorumMode),
            tieBreakMode: uint8(config.tieBreakMode),
            randomnessFailureMode: uint8(config.randomnessFailureMode),
            minRandomnessReveals: config.minRandomnessReveals,
            allEligibleFallbackCap: config.allEligibleFallbackCap,
            missedCommitSlashBps: config.missedCommitSlashBps,
            missedRevealSlashBps: config.missedRevealSlashBps,
            invalidRevealSlashBps: config.invalidRevealSlashBps,
            slashCooldown: config.slashCooldown,
            protocolFeeAllocationBps: config.protocolFeeAllocationBps,
            appealSuccessRoutingBps: config.appealSuccessRoutingBps,
            appealFailureRoutingBps: config.appealFailureRoutingBps,
            incentiveSelectCommittee: config.incentiveSelectCommittee,
            incentiveCloseCommit: config.incentiveCloseCommit,
            incentiveCloseReveal: config.incentiveCloseReveal,
            incentiveOpenAppeal: config.incentiveOpenAppeal,
            incentiveFinalize: config.incentiveFinalize,
            incentiveRandomness: config.incentiveRandomness
        });
    }

    function _viewResolverEpochPool(
        LibResolverJury.ResolverJuryStorage storage jury,
        LibEveMarket.EveMarketStorage storage state
    ) internal view returns (IResolverRegistryFacet.ResolverEpochPoolView memory view_) {
        view_ = IResolverRegistryFacet.ResolverEpochPoolView({
            currentEpochId: jury.currentResolverEpoch,
            activeResolverCount: jury.resolverEpochs[jury.currentResolverEpoch].activeSet.length,
            eligibleResolverCount: _viewEligibleResolverCount(jury, state),
            activeEpochSize: state.config.resolverJuryConfig.activeEpochSize
        });
    }

    function _viewEligibleResolverCount(
        LibResolverJury.ResolverJuryStorage storage jury,
        LibEveMarket.EveMarketStorage storage state
    ) internal view returns (uint256 count) {
        uint256 length = jury.resolverEpochs[jury.currentResolverEpoch].activeSet.length;
        for (uint256 index; index < length; ++index) {
            if (_viewIsEligibleResolver(
                    jury, state, jury.resolverEpochs[jury.currentResolverEpoch].activeSet[index], bytes32(0)
                )) {
                ++count;
            }
        }
    }

    function _viewBoundedTimestamp(uint64 timestamp, uint64 delay) internal pure returns (uint64) {
        if (timestamp == 0) {
            return 0;
        }

        uint256 delayed = uint256(timestamp) + delay;
        return delayed > type(uint64).max ? type(uint64).max : uint64(delayed);
    }

    function _viewEffectiveLifecycle(
        LibResolverJury.ResolverIdentityRecord storage record,
        LibEveMarket.ResolverJuryConfig storage config
    ) internal view returns (LibResolverJury.ResolverLifecycle lifecycle) {
        lifecycle = record.lifecycle;
        if (
            lifecycle == LibResolverJury.ResolverLifecycle.ResolverCandidate
                && block.timestamp >= uint256(record.activationTimestamp) + config.activationDelay
        ) {
            return LibResolverJury.ResolverLifecycle.ResolverActive;
        }
    }

    function _viewIsEligibleResolver(
        LibResolverJury.ResolverJuryStorage storage jury,
        LibEveMarket.EveMarketStorage storage state,
        uint256 identityId,
        bytes32 disputeId
    ) internal view returns (bool) {
        address identityContract = jury.eveIdentity;
        if (identityContract == address(0) || !_viewIsCurrentEpochMember(jury, identityId)) {
            return false;
        }
        if (!IEveIdentity(identityContract).hasResolverRole(identityId)) {
            return false;
        }

        LibResolverJury.ResolverIdentityRecord storage record = jury.identities[identityId];
        LibEveMarket.ResolverJuryConfig storage config = state.config.resolverJuryConfig;
        if (_viewEffectiveLifecycle(record, config) != LibResolverJury.ResolverLifecycle.ResolverActive) {
            return false;
        }
        if (record.resolverStake != config.resolverSeatStake) {
            return false;
        }
        if (record.slashLockActive && block.timestamp < record.slashLockUntil) {
            return false;
        }
        if (config.concurrencyLimit != 0 && record.unresolvedCommittees >= config.concurrencyLimit) {
            return false;
        }
        if (!_viewMeetsParticipationThreshold(jury.resolverRep[identityId], config)) {
            return false;
        }

        bytes32 marketId = jury.disputes[disputeId].marketId;
        return marketId == bytes32(0) || !_viewHasConflict(jury, state, identityId, marketId);
    }

    function _viewMeetsParticipationThreshold(
        LibResolverJury.ResolverReputation storage reputation,
        LibEveMarket.ResolverJuryConfig storage config
    ) internal view returns (bool) {
        if (reputation.totalSelections < config.participationGraceCount) {
            return true;
        }
        if (reputation.totalSelections == 0) {
            return config.participationThresholdBps == 0;
        }
        return uint256(reputation.revealCount) * 10_000
            >= uint256(reputation.totalSelections) * config.participationThresholdBps;
    }

    function _viewHasConflict(
        LibResolverJury.ResolverJuryStorage storage jury,
        LibEveMarket.EveMarketStorage storage state,
        uint256 identityId,
        bytes32 marketId
    ) internal view returns (bool) {
        address identityContract = jury.eveIdentity;
        if (
            identityContract == address(0) || marketId == bytes32(0)
                || jury.identities[identityId].lifecycle == LibResolverJury.ResolverLifecycle.None
        ) {
            return false;
        }

        address owner = IEveIdentity(identityContract).ownerOf(identityId);
        if (state.markets[marketId].creator == owner && owner != address(0)) {
            return true;
        }

        uint256 threshold = state.config.resolverJuryConfig.conflictPositionThreshold;
        if (threshold == 0) {
            return false;
        }

        LibEveMarket.Market storage market = state.markets[marketId];
        if (market.positionToken == address(0)) {
            return false;
        }
        if (
            market.marketType == LibEveMarket.MarketType.CLOB || market.marketType == LibEveMarket.MarketType.PARIMUTUEL
        ) {
            IERC1155 positionToken = IERC1155(market.positionToken);
            if (
                positionToken.balanceOf(owner, market.yesPositionId) > threshold
                    || positionToken.balanceOf(owner, market.noPositionId) > threshold
            ) {
                return true;
            }
            if (market.marketType == LibEveMarket.MarketType.CLOB) {
                return _viewHasEscrowedOutcomeInventory(
                    state,
                    owner,
                    _viewMarketBookId(market, marketId, true),
                    marketId,
                    market.positionToken,
                    market.yesPositionId,
                    threshold
                )
                    || _viewHasEscrowedOutcomeInventory(
                    state,
                    owner,
                    _viewMarketBookId(market, marketId, false),
                    marketId,
                    market.positionToken,
                    market.noPositionId,
                    threshold
                );
            }

            return false;
        }
        if (market.marketType == LibEveMarket.MarketType.MULTI_OUTCOME_ORDERBOOK) {
            IERC1155 positionToken = IERC1155(market.positionToken);
            uint8 outcomeCount = state.multiOutcomeMarkets[marketId].outcomeCount;
            for (uint8 outcome; outcome < outcomeCount; ++outcome) {
                uint256 positionId = state.multiOutcomePositionIds[marketId][outcome];
                if (
                    positionToken.balanceOf(owner, positionId) > threshold
                        || _viewHasEscrowedOutcomeInventory(
                            state,
                            owner,
                            _viewMultiOutcomeBookId(state, marketId, outcome),
                            marketId,
                            market.positionToken,
                            positionId,
                            threshold
                        )
                ) {
                    return true;
                }
            }
        }

        return false;
    }

    function _viewHasEscrowedOutcomeInventory(
        LibEveMarket.EveMarketStorage storage state,
        address owner,
        bytes32 bookId,
        bytes32 marketId,
        address positionToken,
        uint256 positionId,
        uint256 threshold
    ) internal view returns (bool) {
        LibEveMarket.Book storage book = state.books[bookId];
        if (
            book.bookId != bookId || book.marketId != marketId || book.assetType != LibEveMarket.BookAssetType.ERC1155
                || book.baseToken != positionToken || book.baseTokenId != positionId
        ) {
            return false;
        }

        return state.bookMakerAskExposure[bookId][owner] > threshold;
    }

    function _viewMarketBookId(LibEveMarket.Market storage market, bytes32 marketId, bool isYesSide)
        internal
        view
        returns (bytes32 bookId)
    {
        bookId = isYesSide ? market.yesBookId : market.noBookId;
        if (bookId == bytes32(0)) {
            bookId = LibCLOBBook.marketBookId(marketId, isYesSide);
        }
    }

    function _viewMultiOutcomeBookId(LibEveMarket.EveMarketStorage storage state, bytes32 marketId, uint8 outcome)
        internal
        view
        returns (bytes32 bookId)
    {
        bookId = state.multiOutcomeBookIds[marketId][outcome];
        if (bookId == bytes32(0)) {
            bookId = LibCLOBBook.multiOutcomeBookId(marketId, outcome);
        }
    }

    function _viewIsCurrentEpochMember(LibResolverJury.ResolverJuryStorage storage jury, uint256 identityId)
        internal
        view
        returns (bool)
    {
        LibResolverJury.ResolverEpoch storage current = jury.resolverEpochs[jury.currentResolverEpoch];
        uint256 length = current.activeSet.length;
        for (uint256 index; index < length; ++index) {
            if (current.activeSet[index] == identityId) {
                return true;
            }
        }
        return false;
    }
}
