// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {IBondManagerFacet} from "../interfaces/IBondManagerFacet.sol";
import {IOBRResolutionFacet} from "../interfaces/IOBRResolutionFacet.sol";
import {IResolverJuryFacet} from "../interfaces/IResolverJuryFacet.sol";
import {IEveIdentity} from "../interfaces/IEveIdentity.sol";
import {IResolverRegistryFacet} from "../interfaces/IResolverRegistryFacet.sol";
import {Errors} from "../libraries/Errors.sol";
import {Events} from "../libraries/Events.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibMultiOutcome} from "../libraries/LibMultiOutcome.sol";
import {LibReentrancy} from "../libraries/LibReentrancy.sol";
import {LibResolverJury} from "../libraries/LibResolverJury.sol";
import {LibResolverRewards} from "../libraries/LibResolverRewards.sol";

contract ResolverJuryFacet is IResolverJuryFacet {
    using SafeERC20 for IERC20;

    bytes32 internal constant DISPUTE_DOMAIN = keccak256("eve.dispute");
    uint8 internal constant MULTI_OUTCOME_INVALID = 255;
    uint256 internal constant BLOCKHASH_LOOKUP_WINDOW = 256;

    modifier resolverJuryNonReentrant() {
        LibReentrancy.enter();
        _;
        LibReentrancy.exit();
    }

    function initiateDispute(bytes32 marketId) external override {
        if (msg.sender != address(this)) {
            revert Errors.InternalCallOnly(msg.sender);
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Market storage market = state.markets[marketId];
        if (market.marketId != marketId) {
            revert Errors.MarketNotFound(marketId);
        }
        if (market.state != LibEveMarket.MarketState.Disputed) {
            revert Errors.MarketNotDisputed(marketId);
        }

        bytes32 disputeId = disputeIdForMarket(marketId);
        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        LibResolverJury.Dispute storage dispute = jury.disputes[disputeId];
        if (dispute.finalized) {
            revert Errors.DisputeAlreadyFinalized(disputeId);
        }
        if (dispute.marketId != bytes32(0)) {
            revert Errors.MarketAlreadyExists(marketId);
        }

        bool isMultiOutcome = market.marketType == LibEveMarket.MarketType.MULTI_OUTCOME_ORDERBOOK;
        uint8 outcomeCount = isMultiOutcome ? state.multiOutcomeMarkets[marketId].outcomeCount : 2;

        dispute.marketId = marketId;
        dispute.isMultiOutcome = isMultiOutcome;
        dispute.outcomeCount = outcomeCount;
        dispute.state = LibResolverJury.DisputeState.CommitteeSelectionPending;
        dispute.currentRound = 0;
        dispute.disputeBondBase = _initialAppealBondBase(state, marketId);
        dispute.rounds[0].round = 0;
        jury.disputeIdByMarket[marketId] = disputeId;

        emit Events.ResolverJuryInitiated(disputeId, marketId, 0);
    }

    function openRandomnessCommit(bytes32 disputeId) external override resolverJuryNonReentrant {
        LibResolverJury.Dispute storage dispute = _requireRandomnessDispute(disputeId);
        LibResolverJury.DisputeRound storage round = dispute.rounds[dispute.currentRound];
        if (
            round.randomnessCommitDeadline != 0 || round.randomnessRevealDeadline != 0 || round.seed != bytes32(0)
                || round.allEligibleFallback
        ) {
            revert Errors.RandomnessNotReady(disputeId);
        }

        LibEveMarket.MarketConfig storage marketConfig = LibEveMarket.store().config;
        LibEveMarket.ResolverJuryConfig storage config = marketConfig.resolverJuryConfig;
        if (config.randomnessCommitDuration == 0) {
            revert Errors.InvalidConfigValue("randomnessCommitDuration");
        }

        round.randomnessAttempt += 1;
        round.randomnessCommitDeadline = uint64(block.timestamp + config.randomnessCommitDuration);
        round.randomnessRevealDeadline = 0;
        round.randomnessReferenceBlock = 0;
        round.validRevealCount = 0;
        round.randomnessAccumulator = bytes32(0);
        round.seed = bytes32(0);
        round.allEligibleFallback = false;
        _payCallerIncentive(marketConfig, config.incentiveRandomness);
    }

    function commitRandomness(bytes32 disputeId, bytes32 commitment) external override {
        if (commitment == bytes32(0)) {
            revert Errors.InvalidAmount(0);
        }

        LibResolverJury.Dispute storage dispute = _requireRandomnessDispute(disputeId);
        LibResolverJury.DisputeRound storage round = dispute.rounds[dispute.currentRound];
        _requireRandomnessCommitOpen(disputeId, round);

        uint256 identityId = LibResolverJury.requireIdentityId(LibResolverJury.store().eveIdentity, msg.sender);
        if (!IResolverRegistryFacet(address(this)).isEligibleResolver(identityId, disputeId)) {
            revert Errors.ResolverNotActive(identityId);
        }

        LibResolverJury.RandomnessContribution storage contribution = round.randomness[identityId];
        if (contribution.attempt == round.randomnessAttempt && contribution.hasCommitted) {
            revert Errors.AlreadyCommitted(identityId);
        }

        contribution.commitment = commitment;
        contribution.hasCommitted = true;
        contribution.hasRevealed = false;
        contribution.revealedValue = bytes32(0);
        contribution.attempt = round.randomnessAttempt;

        emit Events.RandomnessCommitted(disputeId, dispute.currentRound, identityId);
    }

    function closeRandomnessCommit(bytes32 disputeId) external override resolverJuryNonReentrant {
        LibResolverJury.Dispute storage dispute = _requireRandomnessDispute(disputeId);
        LibResolverJury.DisputeRound storage round = dispute.rounds[dispute.currentRound];
        if (round.randomnessCommitDeadline == 0 || round.randomnessRevealDeadline != 0) {
            revert Errors.RandomnessNotReady(disputeId);
        }
        if (block.timestamp < round.randomnessCommitDeadline) {
            revert Errors.RandomnessNotReady(disputeId);
        }

        LibEveMarket.MarketConfig storage marketConfig = LibEveMarket.store().config;
        LibEveMarket.ResolverJuryConfig storage config = marketConfig.resolverJuryConfig;
        if (config.randomnessRevealDuration == 0) {
            revert Errors.InvalidConfigValue("randomnessRevealDuration");
        }

        round.randomnessRevealDeadline = uint64(block.timestamp + config.randomnessRevealDuration);
        round.randomnessReferenceBlock = 0;
        _payCallerIncentive(marketConfig, config.incentiveRandomness);
    }

    function revealRandomness(bytes32 disputeId, bytes32 value, bytes32 salt) external override {
        LibResolverJury.Dispute storage dispute = _requireRandomnessDispute(disputeId);
        LibResolverJury.DisputeRound storage round = dispute.rounds[dispute.currentRound];
        _requireRandomnessRevealOpen(disputeId, round);

        uint256 identityId = LibResolverJury.requireIdentityId(LibResolverJury.store().eveIdentity, msg.sender);
        LibResolverJury.RandomnessContribution storage contribution = round.randomness[identityId];
        if (contribution.attempt != round.randomnessAttempt || !contribution.hasCommitted) {
            revert Errors.JuryCommitmentMismatch(identityId);
        }
        if (contribution.hasRevealed) {
            revert Errors.AlreadyRevealed(identityId);
        }
        if (keccak256(abi.encode(disputeId, identityId, value, salt)) != contribution.commitment) {
            revert Errors.JuryCommitmentMismatch(identityId);
        }

        contribution.hasRevealed = true;
        contribution.revealedValue = value;
        round.validRevealCount += 1;
        round.randomnessAccumulator = keccak256(abi.encode(round.randomnessAccumulator, identityId, value));

        emit Events.RandomnessRevealed(disputeId, dispute.currentRound, identityId);
    }

    function closeRandomnessReveal(bytes32 disputeId) external override resolverJuryNonReentrant {
        LibResolverJury.Dispute storage dispute = _requireRandomnessDispute(disputeId);
        LibResolverJury.DisputeRound storage round = dispute.rounds[dispute.currentRound];
        _requireRandomnessRevealReadyToClose(disputeId, round);

        LibEveMarket.MarketConfig storage marketConfig = LibEveMarket.store().config;
        LibEveMarket.ResolverJuryConfig storage config = marketConfig.resolverJuryConfig;
        if (round.validRevealCount < config.minRandomnessReveals) {
            _applyRandomnessFallback(disputeId, dispute, round, config);
            _payCallerIncentive(marketConfig, config.incentiveRandomness);
            return;
        }

        if (
            round.randomnessReferenceBlock == 0
                || block.number > uint256(round.randomnessReferenceBlock) + BLOCKHASH_LOOKUP_WINDOW
        ) {
            _scheduleRandomnessReferenceBlock(disputeId, dispute, round);
            _payCallerIncentive(marketConfig, config.incentiveRandomness);
            return;
        }
        if (block.number <= round.randomnessReferenceBlock) {
            revert Errors.RandomnessNotReady(disputeId);
        }

        bytes32 delayedBlockEntropy = blockhash(round.randomnessReferenceBlock);
        if (delayedBlockEntropy == bytes32(0)) {
            _scheduleRandomnessReferenceBlock(disputeId, dispute, round);
            _payCallerIncentive(marketConfig, config.incentiveRandomness);
            return;
        }

        round.seed = _deriveRandomnessSeed(disputeId, round.randomnessAccumulator, delayedBlockEntropy);
        _payCallerIncentive(marketConfig, config.incentiveRandomness);
    }

    function _scheduleRandomnessReferenceBlock(
        bytes32 disputeId,
        LibResolverJury.Dispute storage dispute,
        LibResolverJury.DisputeRound storage round
    ) internal {
        round.randomnessReferenceBlock = uint64(block.number + 1);
        emit Events.RandomnessSeedReferenceBlockSet(disputeId, dispute.currentRound, round.randomnessReferenceBlock);
    }

    function selectCommittee(bytes32 disputeId) external override resolverJuryNonReentrant {
        LibResolverJury.Dispute storage dispute = _requireCommitteeSelectionDispute(disputeId);
        LibResolverJury.DisputeRound storage round = dispute.rounds[dispute.currentRound];
        if (round.committeeSize != 0 || round.committee.length != 0) {
            revert Errors.InvalidCommitteeSize(round.committeeSize);
        }

        LibEveMarket.MarketConfig storage marketConfig = LibEveMarket.store().config;
        LibEveMarket.ResolverJuryConfig storage config = marketConfig.resolverJuryConfig;
        uint16 committeeSize = _committeeSizeForRound(config, dispute.currentRound);
        if (config.commitDuration < 1 hours || config.commitDuration > 7 days) {
            revert Errors.InvalidConfigValue("commitDuration");
        }

        uint256[] memory eligible = _eligibleResolversForDispute(disputeId);
        if (round.allEligibleFallback) {
            if (eligible.length == 0 || eligible.length > config.allEligibleFallbackCap) {
                revert Errors.RandomnessFallbackUnavailable(disputeId);
            }
            _persistCommittee(dispute, round, eligible, bytes32(0));
            _payCallerIncentive(marketConfig, config.incentiveSelectCommittee);
            return;
        }

        if (round.seed == bytes32(0)) {
            revert Errors.RandomnessNotReady(disputeId);
        }
        if (eligible.length < committeeSize) {
            revert Errors.RandomnessFallbackUnavailable(disputeId);
        }

        uint256[] memory selected = new uint256[](committeeSize);
        if (eligible.length == committeeSize) {
            for (uint256 index; index < committeeSize; ++index) {
                selected[index] = eligible[index];
            }
        } else {
            uint256 remaining = eligible.length;
            for (uint256 index; index < committeeSize; ++index) {
                uint256 draw = uint256(keccak256(abi.encode(round.seed, index))) % remaining;
                selected[index] = eligible[draw];
                eligible[draw] = eligible[remaining - 1];
                --remaining;
            }
        }

        _persistCommittee(dispute, round, selected, round.seed);
        _payCallerIncentive(marketConfig, config.incentiveSelectCommittee);
    }

    function closeCommit(bytes32 disputeId) external override resolverJuryNonReentrant {
        LibResolverJury.Dispute storage dispute =
            _requirePhaseDispute(disputeId, LibResolverJury.DisputeState.CommitOpen);
        LibResolverJury.DisputeRound storage round = dispute.rounds[dispute.currentRound];
        if (round.commitDeadline == 0 || block.timestamp < round.commitDeadline) {
            revert Errors.CommitPhaseClosed(disputeId);
        }

        LibEveMarket.MarketConfig storage marketConfig = LibEveMarket.store().config;
        LibEveMarket.ResolverJuryConfig storage config = marketConfig.resolverJuryConfig;
        if (config.revealDuration == 0) {
            revert Errors.InvalidConfigValue("revealDuration");
        }

        _slashMissedCommits(dispute, round, config);
        round.revealDeadline = uint64(block.timestamp + config.revealDuration);
        dispute.state = LibResolverJury.DisputeState.RevealOpen;
        _payCallerIncentive(marketConfig, config.incentiveCloseCommit);
    }

    function closeRevealAndTally(bytes32 disputeId) external override resolverJuryNonReentrant {
        LibResolverJury.Dispute storage dispute =
            _requirePhaseDispute(disputeId, LibResolverJury.DisputeState.RevealOpen);
        LibResolverJury.DisputeRound storage round = dispute.rounds[dispute.currentRound];
        if (round.revealDeadline == 0 || block.timestamp < round.revealDeadline) {
            revert Errors.RevealPhaseClosed(disputeId);
        }

        LibEveMarket.MarketConfig storage marketConfig = LibEveMarket.store().config;
        LibEveMarket.ResolverJuryConfig storage config = marketConfig.resolverJuryConfig;
        _slashMissedReveals(dispute, round, config);
        if (round.validRevealCount < config.quorum) {
            _applyLowQuorumFallback(dispute, round, config);
            _payCallerIncentive(marketConfig, config.incentiveCloseReveal);
            return;
        }

        (uint8 winner, bool uniqueWinner) = _strictPluralityWinner(dispute, round);
        if (uniqueWinner) {
            _setProvisionalResult(dispute, round, winner, config);
            _payCallerIncentive(marketConfig, config.incentiveCloseReveal);
            return;
        }

        if (config.tieBreakMode == LibEveMarket.TieBreakMode.ResolveInvalid) {
            _setProvisionalResult(dispute, round, _invalidOutcomeFor(dispute), config);
            _payCallerIncentive(marketConfig, config.incentiveCloseReveal);
            return;
        }

        _openNextSelectionRound(dispute);
        _payCallerIncentive(marketConfig, config.incentiveCloseReveal);
    }

    function openAppeal(bytes32 disputeId) external override resolverJuryNonReentrant {
        LibResolverJury.Dispute storage dispute = _requireAppealOpenDispute(disputeId);
        LibResolverJury.DisputeRound storage round = dispute.rounds[dispute.currentRound];
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.ResolverJuryConfig storage config = state.config.resolverJuryConfig;

        if (dispute.currentRound >= config.maxAppealRounds) {
            revert Errors.MaxAppealRoundsReached(dispute.currentRound);
        }

        uint256 nextRoundValue = uint256(dispute.currentRound) + 1;
        if (nextRoundValue > type(uint8).max) {
            revert Errors.InvalidAmount(nextRoundValue);
        }

        uint8 nextRound = uint8(nextRoundValue);
        uint16 nextCommitteeSize = _committeeSizeForRound(config, nextRound);
        if (nextCommitteeSize <= round.committeeSize) {
            revert Errors.InvalidCommitteeSize(nextCommitteeSize);
        }

        uint128 requiredBond = _requiredAppealBond(dispute, config, nextRound);
        address bondToken = _appealBondToken(state);
        _requireAppealBondFunding(bondToken, requiredBond);

        dispute.appealBond[nextRound] = requiredBond;
        dispute.appellant[nextRound] = msg.sender;
        dispute.currentRound = nextRound;
        dispute.state = LibResolverJury.DisputeState.CommitteeSelectionPending;

        LibResolverJury.DisputeRound storage next = dispute.rounds[nextRound];
        next.round = nextRound;

        emit Events.AppealOpened(disputeId, nextRound, msg.sender, requiredBond);
        IERC20(bondToken).safeTransferFrom(msg.sender, address(this), requiredBond);
        _payCallerIncentive(state.config, config.incentiveOpenAppeal);
    }

    function finalizeDispute(bytes32 disputeId) external override resolverJuryNonReentrant {
        LibResolverJury.Dispute storage dispute = _requireFinalizableDispute(disputeId);
        LibResolverJury.DisputeRound storage round = dispute.rounds[dispute.currentRound];
        uint8 finalResult = round.provisionalResult;

        dispute.finalResult = finalResult;
        dispute.finalized = true;
        dispute.state = LibResolverJury.DisputeState.Finalized;

        _releaseCommitteeObligations(dispute);
        IResolverRegistryFacet(address(this)).applyFinalityReputation(disputeId, finalResult);
        _routeAppealBonds(disputeId, dispute, LibEveMarket.store(), finalResult);
        _distributeResolverRewards(disputeId, dispute);
        IOBRResolutionFacet(address(this)).finalizeFromJury(dispute.marketId, finalResult);

        emit Events.DisputeFinalized(disputeId, dispute.marketId, finalResult);
        LibEveMarket.MarketConfig storage marketConfig = LibEveMarket.store().config;
        _payCallerIncentive(marketConfig, marketConfig.resolverJuryConfig.incentiveFinalize);
    }

    function applyRandomnessFallback(bytes32 disputeId) external override resolverJuryNonReentrant {
        LibResolverJury.Dispute storage dispute = _requireRandomnessDispute(disputeId);
        LibResolverJury.DisputeRound storage round = dispute.rounds[dispute.currentRound];
        LibEveMarket.MarketConfig storage marketConfig = LibEveMarket.store().config;
        LibEveMarket.ResolverJuryConfig storage config = marketConfig.resolverJuryConfig;
        if (round.randomnessRevealDeadline == 0 || block.timestamp < round.randomnessRevealDeadline) {
            revert Errors.RandomnessNotReady(disputeId);
        }
        if (round.validRevealCount >= config.minRandomnessReveals) {
            revert Errors.RandomnessFallbackUnavailable(disputeId);
        }

        _applyRandomnessFallback(disputeId, dispute, round, config);
        _payCallerIncentive(marketConfig, config.incentiveRandomness);
    }

    function commitVote(bytes32 disputeId, bytes32 commitment) external override {
        if (commitment == bytes32(0)) {
            revert Errors.InvalidAmount(0);
        }

        LibResolverJury.Dispute storage dispute =
            _requirePhaseDispute(disputeId, LibResolverJury.DisputeState.CommitOpen);
        LibResolverJury.DisputeRound storage round = dispute.rounds[dispute.currentRound];
        if (round.commitDeadline == 0 || block.timestamp >= round.commitDeadline) {
            revert Errors.CommitPhaseClosed(disputeId);
        }

        uint256 identityId = LibResolverJury.requireIdentityId(LibResolverJury.store().eveIdentity, msg.sender);
        if (!round.inCommittee[identityId]) {
            revert Errors.NotCommitteeMember(identityId);
        }
        if (round.hasCommitted[identityId]) {
            revert Errors.AlreadyCommitted(identityId);
        }

        round.hasCommitted[identityId] = true;
        round.commitment[identityId] = commitment;
        LibResolverJury.store().resolverRep[identityId].commitCount += 1;

        emit Events.VoteCommitted(disputeId, dispute.currentRound, identityId);
    }

    function revealVote(bytes32 disputeId, uint8 outcome, bytes32 salt) external override {
        LibResolverJury.Dispute storage dispute =
            _requirePhaseDispute(disputeId, LibResolverJury.DisputeState.RevealOpen);
        LibResolverJury.DisputeRound storage round = dispute.rounds[dispute.currentRound];
        if (round.revealDeadline == 0 || block.timestamp >= round.revealDeadline) {
            revert Errors.RevealPhaseClosed(disputeId);
        }

        uint256 identityId = LibResolverJury.requireIdentityId(LibResolverJury.store().eveIdentity, msg.sender);
        if (!round.inCommittee[identityId]) {
            revert Errors.NotCommitteeMember(identityId);
        }
        if (!round.hasCommitted[identityId]) {
            revert Errors.JuryCommitmentMismatch(identityId);
        }
        if (round.slashedThisRound[identityId]) {
            revert Errors.AlreadyRevealed(identityId);
        }
        if (round.hasRevealed[identityId]) {
            revert Errors.AlreadyRevealed(identityId);
        }
        if (keccak256(abi.encode(disputeId, identityId, outcome, salt)) != round.commitment[identityId]) {
            _markInvalidReveal(dispute, round, identityId, LibEveMarket.store().config.resolverJuryConfig);
            return;
        }
        if (!_isValidJuryOutcome(dispute, outcome)) {
            _markInvalidReveal(dispute, round, identityId, LibEveMarket.store().config.resolverJuryConfig);
            return;
        }

        round.hasRevealed[identityId] = true;
        round.revealedOutcome[identityId] = outcome;
        round.validRevealCount += 1;
        round.tally[outcome] += 1;
        LibResolverJury.store().resolverRep[identityId].revealCount += 1;

        emit Events.VoteRevealed(disputeId, dispute.currentRound, identityId, outcome);
    }

    function disputeView(bytes32 disputeId) external view override returns (DisputeView memory view_) {
        LibResolverJury.Dispute storage dispute = LibResolverJury.store().disputes[disputeId];
        LibResolverJury.DisputeRound storage round = dispute.rounds[dispute.currentRound];
        view_ = DisputeView({
            disputeId: disputeId,
            marketId: dispute.marketId,
            state: uint8(dispute.state),
            currentRound: dispute.currentRound,
            finalResult: dispute.finalResult,
            finalized: dispute.finalized,
            isMultiOutcome: dispute.isMultiOutcome,
            outcomeCount: dispute.outcomeCount,
            disputeBondBase: dispute.disputeBondBase,
            rewardPoolBond: dispute.rewardPoolBond,
            rewardsDistributed: dispute.rewardsDistributed,
            reputationApplied: dispute.reputationApplied,
            committeeSize: round.committeeSize,
            validRevealCount: round.validRevealCount,
            randomnessCommitDeadline: round.randomnessCommitDeadline,
            randomnessRevealDeadline: round.randomnessRevealDeadline,
            commitDeadline: round.commitDeadline,
            revealDeadline: round.revealDeadline,
            appealDeadline: round.appealDeadline,
            provisionalResult: round.provisionalResult,
            hasProvisional: round.hasProvisional,
            randomnessAttempt: round.randomnessAttempt,
            randomnessReferenceBlock: round.randomnessReferenceBlock,
            seed: round.seed,
            randomnessAccumulator: round.randomnessAccumulator,
            allEligibleFallback: round.allEligibleFallback
        });
    }

    function committeeMembers(bytes32 disputeId, uint8 round)
        external
        view
        override
        returns (uint256[] memory identityIds)
    {
        identityIds = LibResolverJury.store().disputes[disputeId].rounds[round].committee;
    }

    function outcomeTally(bytes32 disputeId, uint8 round)
        external
        view
        override
        returns (uint8[] memory outcomes, uint256[] memory counts)
    {
        LibResolverJury.Dispute storage dispute = LibResolverJury.store().disputes[disputeId];
        LibResolverJury.DisputeRound storage disputeRound = dispute.rounds[round];
        if (dispute.isMultiOutcome) {
            uint256 length = uint256(dispute.outcomeCount) + 1;
            outcomes = new uint8[](length);
            counts = new uint256[](length);
            for (uint8 outcome; outcome < dispute.outcomeCount; ++outcome) {
                outcomes[outcome] = outcome;
                counts[outcome] = disputeRound.tally[outcome];
            }
            outcomes[length - 1] = MULTI_OUTCOME_INVALID;
            counts[length - 1] = disputeRound.tally[MULTI_OUTCOME_INVALID];
            return (outcomes, counts);
        }

        outcomes = new uint8[](3);
        counts = new uint256[](3);
        outcomes[0] = uint8(LibEveMarket.MarketOutcome.Yes);
        outcomes[1] = uint8(LibEveMarket.MarketOutcome.No);
        outcomes[2] = uint8(LibEveMarket.MarketOutcome.Invalid);
        counts[0] = disputeRound.tally[outcomes[0]];
        counts[1] = disputeRound.tally[outcomes[1]];
        counts[2] = disputeRound.tally[outcomes[2]];
    }

    function revealedVote(bytes32 disputeId, uint8 round, uint256 identityId)
        external
        view
        override
        returns (bool revealed, uint8 outcome)
    {
        LibResolverJury.DisputeRound storage disputeRound = LibResolverJury.store().disputes[disputeId].rounds[round];
        revealed = disputeRound.hasRevealed[identityId];
        outcome = disputeRound.revealedOutcome[identityId];
    }

    function provisionalResult(bytes32 disputeId) external view override returns (uint8 outcome, bool isFinal) {
        LibResolverJury.Dispute storage dispute = LibResolverJury.store().disputes[disputeId];
        if (dispute.finalized) {
            return (dispute.finalResult, true);
        }

        LibResolverJury.DisputeRound storage round = dispute.rounds[dispute.currentRound];
        return (round.provisionalResult, false);
    }

    function disputeIdForMarket(bytes32 marketId) public pure returns (bytes32 disputeId) {
        disputeId = keccak256(abi.encode(DISPUTE_DOMAIN, marketId));
    }

    function _requireOpenDispute(bytes32 disputeId) internal view {
        if (LibResolverJury.store().disputes[disputeId].finalized) {
            revert Errors.DisputeAlreadyFinalized(disputeId);
        }
    }

    function _requirePhaseDispute(bytes32 disputeId, LibResolverJury.DisputeState expectedState)
        internal
        view
        returns (LibResolverJury.Dispute storage dispute)
    {
        dispute = LibResolverJury.store().disputes[disputeId];
        if (dispute.finalized) {
            revert Errors.DisputeAlreadyFinalized(disputeId);
        }
        if (dispute.marketId == bytes32(0)) {
            revert Errors.MarketNotFound(dispute.marketId);
        }
        if (dispute.state != expectedState) {
            if (expectedState == LibResolverJury.DisputeState.CommitOpen) {
                revert Errors.CommitPhaseClosed(disputeId);
            }
            revert Errors.RevealPhaseClosed(disputeId);
        }
    }

    function _requireAppealOpenDispute(bytes32 disputeId)
        internal
        view
        returns (LibResolverJury.Dispute storage dispute)
    {
        dispute = LibResolverJury.store().disputes[disputeId];
        if (dispute.finalized) {
            revert Errors.DisputeAlreadyFinalized(disputeId);
        }
        if (dispute.marketId == bytes32(0)) {
            revert Errors.MarketNotFound(dispute.marketId);
        }
        if (dispute.state != LibResolverJury.DisputeState.AppealOpen) {
            revert Errors.AppealWindowClosed(disputeId);
        }

        LibResolverJury.DisputeRound storage round = dispute.rounds[dispute.currentRound];
        if (!round.hasProvisional || round.appealDeadline == 0 || block.timestamp >= round.appealDeadline) {
            revert Errors.AppealWindowClosed(disputeId);
        }
    }

    function _requireFinalizableDispute(bytes32 disputeId)
        internal
        view
        returns (LibResolverJury.Dispute storage dispute)
    {
        dispute = LibResolverJury.store().disputes[disputeId];
        if (dispute.finalized) {
            revert Errors.DisputeAlreadyFinalized(disputeId);
        }
        if (dispute.marketId == bytes32(0)) {
            revert Errors.MarketNotFound(dispute.marketId);
        }
        if (dispute.state != LibResolverJury.DisputeState.AppealOpen) {
            revert Errors.AppealWindowClosed(disputeId);
        }

        LibResolverJury.DisputeRound storage round = dispute.rounds[dispute.currentRound];
        if (!round.hasProvisional || round.appealDeadline == 0 || block.timestamp < round.appealDeadline) {
            revert Errors.AppealWindowClosed(disputeId);
        }
    }

    function _requireRandomnessDispute(bytes32 disputeId)
        internal
        view
        returns (LibResolverJury.Dispute storage dispute)
    {
        dispute = LibResolverJury.store().disputes[disputeId];
        if (dispute.finalized) {
            revert Errors.DisputeAlreadyFinalized(disputeId);
        }
        if (dispute.marketId == bytes32(0)) {
            revert Errors.MarketNotFound(dispute.marketId);
        }
        if (dispute.state != LibResolverJury.DisputeState.CommitteeSelectionPending) {
            revert Errors.RandomnessNotReady(disputeId);
        }
    }

    function _requireCommitteeSelectionDispute(bytes32 disputeId)
        internal
        view
        returns (LibResolverJury.Dispute storage dispute)
    {
        dispute = _requireRandomnessDispute(disputeId);
    }

    function _committeeSizeForRound(LibEveMarket.ResolverJuryConfig storage config, uint8 round)
        internal
        view
        returns (uint16 committeeSize)
    {
        if (round >= config.committeeSizesByRound.length) {
            revert Errors.InvalidCommitteeSize(0);
        }

        committeeSize = config.committeeSizesByRound[round];
        if (committeeSize == 0 || committeeSize % 2 == 0) {
            revert Errors.InvalidCommitteeSize(committeeSize);
        }
    }

    function _requireRandomnessCommitOpen(bytes32 disputeId, LibResolverJury.DisputeRound storage round) internal view {
        if (
            round.randomnessAttempt == 0 || round.randomnessCommitDeadline == 0 || round.randomnessRevealDeadline != 0
                || block.timestamp > round.randomnessCommitDeadline
        ) {
            revert Errors.RandomnessNotReady(disputeId);
        }
    }

    function _requireRandomnessRevealOpen(bytes32 disputeId, LibResolverJury.DisputeRound storage round) internal view {
        if (
            round.randomnessRevealDeadline == 0 || block.timestamp > round.randomnessRevealDeadline
                || round.seed != bytes32(0) || round.allEligibleFallback
        ) {
            revert Errors.RandomnessNotReady(disputeId);
        }
    }

    function _requireRandomnessRevealReadyToClose(bytes32 disputeId, LibResolverJury.DisputeRound storage round)
        internal
        view
    {
        if (round.randomnessRevealDeadline == 0 || block.timestamp < round.randomnessRevealDeadline) {
            revert Errors.RandomnessNotReady(disputeId);
        }
        if (round.seed != bytes32(0) || round.allEligibleFallback) {
            revert Errors.RandomnessNotReady(disputeId);
        }
    }

    function _applyRandomnessFallback(
        bytes32 disputeId,
        LibResolverJury.Dispute storage dispute,
        LibResolverJury.DisputeRound storage round,
        LibEveMarket.ResolverJuryConfig storage config
    ) internal {
        if (config.randomnessFailureMode == LibEveMarket.RandomnessFailureMode.Retry) {
            if (config.randomnessCommitDuration == 0) {
                revert Errors.InvalidConfigValue("randomnessCommitDuration");
            }

            emit Events.RandomnessFailure(
                disputeId, dispute.currentRound, uint8(config.randomnessFailureMode), round.validRevealCount
            );
            round.randomnessAttempt += 1;
            round.randomnessCommitDeadline = uint64(block.timestamp + config.randomnessCommitDuration);
            round.randomnessRevealDeadline = 0;
            round.randomnessReferenceBlock = 0;
            round.validRevealCount = 0;
            round.randomnessAccumulator = bytes32(0);
            round.seed = bytes32(0);
            round.allEligibleFallback = false;
            return;
        }

        if (config.randomnessFailureMode == LibEveMarket.RandomnessFailureMode.AllEligible) {
            uint256 eligibleCount = _eligibleResolverCountForDispute(disputeId);
            if (eligibleCount == 0 || eligibleCount > config.allEligibleFallbackCap) {
                revert Errors.RandomnessFallbackUnavailable(disputeId);
            }

            emit Events.RandomnessFailure(
                disputeId, dispute.currentRound, uint8(config.randomnessFailureMode), round.validRevealCount
            );
            round.allEligibleFallback = true;
            return;
        }

        revert Errors.RandomnessFallbackUnavailable(disputeId);
    }

    function _eligibleResolverCountForDispute(bytes32 disputeId) internal view returns (uint256 count) {
        IResolverRegistryFacet registry = IResolverRegistryFacet(address(this));
        uint256 activeCount = registry.activeResolverCount();
        for (uint256 index; index < activeCount; ++index) {
            uint256 identityId = registry.activeResolverAt(index);
            if (registry.isEligibleResolver(identityId, disputeId)) {
                ++count;
            }
        }
    }

    function _eligibleResolversForDispute(bytes32 disputeId) internal view returns (uint256[] memory eligible) {
        IResolverRegistryFacet registry = IResolverRegistryFacet(address(this));
        uint256 activeCount = registry.activeResolverCount();
        uint256 eligibleCount;
        for (uint256 index; index < activeCount; ++index) {
            if (registry.isEligibleResolver(registry.activeResolverAt(index), disputeId)) {
                ++eligibleCount;
            }
        }

        eligible = new uint256[](eligibleCount);
        uint256 writeIndex;
        for (uint256 index; index < activeCount; ++index) {
            uint256 identityId = registry.activeResolverAt(index);
            if (registry.isEligibleResolver(identityId, disputeId)) {
                eligible[writeIndex] = identityId;
                ++writeIndex;
            }
        }
    }

    function _persistCommittee(
        LibResolverJury.Dispute storage dispute,
        LibResolverJury.DisputeRound storage round,
        uint256[] memory selected,
        bytes32 seed
    ) internal {
        round.committeeSize = uint16(selected.length);
        round.commitDeadline = uint64(block.timestamp + LibEveMarket.store().config.resolverJuryConfig.commitDuration);
        round.validRevealCount = 0;
        dispute.state = LibResolverJury.DisputeState.CommitOpen;

        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        for (uint256 index; index < selected.length; ++index) {
            uint256 identityId = selected[index];
            round.committee.push(identityId);
            round.inCommittee[identityId] = true;
            if (!dispute.everSelected[identityId]) {
                dispute.everSelected[identityId] = true;
                dispute.allSelected.push(identityId);
            }
            jury.identities[identityId].unresolvedCommittees += 1;
            jury.resolverRep[identityId].totalSelections += 1;
        }

        emit Events.CommitteeSelected(
            disputeIdForMarket(dispute.marketId), round.round, round.committeeSize, seed, selected
        );
    }

    function _applyLowQuorumFallback(
        LibResolverJury.Dispute storage dispute,
        LibResolverJury.DisputeRound storage round,
        LibEveMarket.ResolverJuryConfig storage config
    ) internal {
        if (config.lowQuorumMode == LibEveMarket.LowQuorumMode.FinalizeInvalid) {
            _setProvisionalResult(dispute, round, _invalidOutcomeFor(dispute), config);
            return;
        }

        if (config.lowQuorumMode == LibEveMarket.LowQuorumMode.Escalate) {
            _openNextSelectionRound(dispute);
            return;
        }

        if (round.redrawsUsed >= config.redrawLimit) {
            _setProvisionalResult(dispute, round, _invalidOutcomeFor(dispute), config);
            return;
        }

        round.redrawsUsed += 1;
        _clearRoundForRedraw(dispute, round);
        dispute.state = LibResolverJury.DisputeState.CommitteeSelectionPending;
    }

    function _strictPluralityWinner(LibResolverJury.Dispute storage dispute, LibResolverJury.DisputeRound storage round)
        internal
        view
        returns (uint8 winner, bool uniqueWinner)
    {
        uint256 topCount;
        bool tied;
        if (dispute.isMultiOutcome) {
            for (uint8 outcome; outcome < dispute.outcomeCount; ++outcome) {
                (winner, topCount, tied) = _considerTally(round, outcome, winner, topCount, tied);
            }
            (winner, topCount, tied) = _considerTally(round, MULTI_OUTCOME_INVALID, winner, topCount, tied);
        } else {
            (winner, topCount, tied) =
                _considerTally(round, uint8(LibEveMarket.MarketOutcome.Yes), winner, topCount, tied);
            (winner, topCount, tied) =
                _considerTally(round, uint8(LibEveMarket.MarketOutcome.No), winner, topCount, tied);
            (winner, topCount, tied) =
                _considerTally(round, uint8(LibEveMarket.MarketOutcome.Invalid), winner, topCount, tied);
        }

        uniqueWinner = topCount != 0 && !tied;
    }

    function _considerTally(
        LibResolverJury.DisputeRound storage round,
        uint8 outcome,
        uint8 currentWinner,
        uint256 topCount,
        bool tied
    ) internal view returns (uint8 winner, uint256 nextTopCount, bool nextTied) {
        uint256 count = round.tally[outcome];
        if (count > topCount) {
            return (outcome, count, false);
        }
        if (count == topCount) {
            return (currentWinner, topCount, true);
        }
        return (currentWinner, topCount, tied);
    }

    function _setProvisionalResult(
        LibResolverJury.Dispute storage dispute,
        LibResolverJury.DisputeRound storage round,
        uint8 outcome,
        LibEveMarket.ResolverJuryConfig storage config
    ) internal {
        round.provisionalResult = outcome;
        round.hasProvisional = true;
        round.appealDeadline = uint64(block.timestamp + config.appealWindow);
        dispute.state = LibResolverJury.DisputeState.AppealOpen;
    }

    function _slashMissedCommits(
        LibResolverJury.Dispute storage dispute,
        LibResolverJury.DisputeRound storage round,
        LibEveMarket.ResolverJuryConfig storage config
    ) internal {
        uint256 length = round.committee.length;
        for (uint256 index; index < length; ++index) {
            uint256 identityId = round.committee[index];
            if (!round.hasCommitted[identityId]) {
                LibResolverJury.store().resolverRep[identityId].missedCommitCount += 1;
                _slashResolver(dispute, round, identityId, config.missedCommitSlashBps, config);
            }
        }
    }

    function _slashMissedReveals(
        LibResolverJury.Dispute storage dispute,
        LibResolverJury.DisputeRound storage round,
        LibEveMarket.ResolverJuryConfig storage config
    ) internal {
        uint256 length = round.committee.length;
        for (uint256 index; index < length; ++index) {
            uint256 identityId = round.committee[index];
            if (round.hasCommitted[identityId] && !round.hasRevealed[identityId] && !round.slashedThisRound[identityId])
            {
                LibResolverJury.store().resolverRep[identityId].missedRevealCount += 1;
                _slashResolver(dispute, round, identityId, config.missedRevealSlashBps, config);
            }
        }
    }

    function _markInvalidReveal(
        LibResolverJury.Dispute storage dispute,
        LibResolverJury.DisputeRound storage round,
        uint256 identityId,
        LibEveMarket.ResolverJuryConfig storage config
    ) internal {
        LibResolverJury.store().resolverRep[identityId].invalidRevealCount += 1;
        _slashResolver(dispute, round, identityId, config.invalidRevealSlashBps, config);
    }

    function _slashResolver(
        LibResolverJury.Dispute storage dispute,
        LibResolverJury.DisputeRound storage round,
        uint256 identityId,
        uint16 slashBps,
        LibEveMarket.ResolverJuryConfig storage config
    ) internal {
        if (round.slashedThisRound[identityId]) {
            return;
        }
        if (slashBps == 0 || slashBps > 10_000) {
            revert Errors.InvalidConfigValue("slashBps");
        }

        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        LibResolverJury.ResolverIdentityRecord storage record = jury.identities[identityId];
        uint128 slashAmount = uint128((uint256(record.resolverStake) * slashBps) / 10_000);

        round.slashedThisRound[identityId] = true;
        if (slashAmount != 0) {
            record.resolverStake -= slashAmount;
            LibResolverRewards.distributeSlashedStake(identityId, LibEveMarket.store().config.eveToken, slashAmount);
        }
        record.slashLockActive = true;
        record.slashLockUntil = uint64(block.timestamp + config.slashCooldown);
        jury.resolverRep[identityId].slashCount += 1;

        emit Events.ResolverSlashed(disputeIdForMarket(dispute.marketId), round.round, identityId, slashAmount);
    }

    function _releaseCommitteeObligations(LibResolverJury.Dispute storage dispute) internal {
        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        for (uint256 roundIndex; roundIndex <= dispute.currentRound; ++roundIndex) {
            LibResolverJury.DisputeRound storage round = dispute.rounds[uint8(roundIndex)];
            uint256 length = round.committee.length;
            for (uint256 index; index < length; ++index) {
                uint256 identityId = round.committee[index];
                if (jury.identities[identityId].unresolvedCommittees != 0) {
                    jury.identities[identityId].unresolvedCommittees -= 1;
                }
            }
        }
    }

    function _distributeResolverRewards(bytes32 disputeId, LibResolverJury.Dispute storage dispute) internal {
        if (dispute.rewardsDistributed) {
            revert Errors.RewardsAlreadyDistributed(disputeId);
        }

        dispute.rewardsDistributed = true;

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.MarketConfig storage config = state.config;
        _distributeProtocolFeeRewards(disputeId, dispute, state, config);

        uint128 rewardPool = dispute.rewardPoolBond;
        if (rewardPool == 0) {
            return;
        }
        if (config.eveToken == address(0)) {
            revert Errors.ZeroAddress();
        }

        _distributeTokenRewards(disputeId, dispute, config.eveToken, rewardPool, config.eveTreasury);
    }

    function _distributeProtocolFeeRewards(
        bytes32 disputeId,
        LibResolverJury.Dispute storage dispute,
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.MarketConfig storage config
    ) internal {
        uint16 allocationBps = config.resolverJuryConfig.protocolFeeAllocationBps;
        if (allocationBps == 0) {
            return;
        }
        if (allocationBps > 10_000) {
            revert Errors.InvalidConfigValue("protocolFeeAllocationBps");
        }

        LibEveMarket.Market storage market = state.markets[dispute.marketId];
        uint128 accrued = market.protocolFeesAccrued;
        if (accrued == 0) {
            return;
        }

        uint256 rewardPool = _bpsShare(accrued, allocationBps);
        if (rewardPool == 0) {
            return;
        }
        if (rewardPool > type(uint128).max) {
            revert Errors.InvalidAmount(rewardPool);
        }
        if (market.collateralToken == address(0)) {
            revert Errors.ZeroAddress();
        }

        uint128 rewardPool128 = uint128(rewardPool);
        market.protocolFeesAccrued = accrued - rewardPool128;
        market.totalFeePool -= rewardPool128;
        _distributeTokenRewards(disputeId, dispute, market.collateralToken, rewardPool, config.eveTreasury);
    }

    function _routeAppealBonds(
        bytes32 disputeId,
        LibResolverJury.Dispute storage dispute,
        LibEveMarket.EveMarketStorage storage state,
        uint8 finalResult
    ) internal {
        for (uint8 round = 1; round <= dispute.currentRound; ++round) {
            uint128 bond = dispute.appealBond[round];
            if (bond == 0) {
                continue;
            }

            address bondToken = _appealBondToken(state);
            address treasury = state.config.eveTreasury;
            if (treasury == address(0)) {
                revert Errors.ZeroAddress();
            }

            dispute.appealBond[round] = 0;
            bool appealSucceeded = finalResult != dispute.rounds[round - 1].provisionalResult;
            address claimant = _bondClaimantForOutcome(state, dispute.marketId, finalResult);
            if (appealSucceeded) {
                _routeSuccessfulAppealBond(
                    disputeId, dispute, bondToken, treasury, claimant, dispute.appellant[round], bond
                );
            } else {
                _routeFailedAppealBond(disputeId, dispute, bondToken, treasury, claimant, bond);
            }
        }
    }

    function _routeSuccessfulAppealBond(
        bytes32 disputeId,
        LibResolverJury.Dispute storage dispute,
        address bondToken,
        address treasury,
        address claimant,
        address appellant,
        uint128 bond
    ) internal {
        LibEveMarket.ResolverJuryConfig storage config = LibEveMarket.store().config.resolverJuryConfig;
        uint16[4] storage routing = config.appealSuccessRoutingBps;
        if (_sumRouting4(routing) != 10_000) {
            revert Errors.InvalidRoutingSplit();
        }

        uint256 appellantShare = _bpsShare(bond, routing[0]);
        uint256 rewardShare = _bpsShare(bond, routing[1]);
        uint256 treasuryShare = _bpsShare(bond, routing[2]);
        uint256 claimantShare = _bpsShare(bond, routing[3]);
        uint256 routed = appellantShare + rewardShare + treasuryShare + claimantShare;
        treasuryShare += uint256(bond) - routed;

        _transferIfNonzero(bondToken, appellant, appellantShare);
        _distributeTokenRewards(disputeId, dispute, bondToken, rewardShare, treasury);
        _routeClaimantShare(bondToken, treasury, claimant, claimantShare);
        _transferIfNonzero(bondToken, treasury, treasuryShare);
    }

    function _routeFailedAppealBond(
        bytes32 disputeId,
        LibResolverJury.Dispute storage dispute,
        address bondToken,
        address treasury,
        address claimant,
        uint128 bond
    ) internal {
        LibEveMarket.ResolverJuryConfig storage config = LibEveMarket.store().config.resolverJuryConfig;
        uint16[3] storage routing = config.appealFailureRoutingBps;
        if (_sumRouting3(routing) != 10_000) {
            revert Errors.InvalidRoutingSplit();
        }

        uint256 rewardShare = _bpsShare(bond, routing[0]);
        uint256 treasuryShare = _bpsShare(bond, routing[1]);
        uint256 claimantShare = _bpsShare(bond, routing[2]);
        uint256 routed = rewardShare + treasuryShare + claimantShare;
        treasuryShare += uint256(bond) - routed;

        _distributeTokenRewards(disputeId, dispute, bondToken, rewardShare, treasury);
        _routeClaimantShare(bondToken, treasury, claimant, claimantShare);
        _transferIfNonzero(bondToken, treasury, treasuryShare);
    }

    function _distributeTokenRewards(
        bytes32 disputeId,
        LibResolverJury.Dispute storage dispute,
        address token,
        uint256 rewardPool,
        address treasury
    ) internal {
        if (rewardPool == 0) {
            return;
        }
        if (token == address(0) || treasury == address(0)) {
            revert Errors.ZeroAddress();
        }

        uint256 recipientCount = _validRewardRecipientCount(dispute);
        if (recipientCount == 0) {
            _transferIfNonzero(token, treasury, rewardPool);
            return;
        }

        uint256 perRecipient = uint256(rewardPool) / recipientCount;
        uint256 distributed;
        address eveIdentity = LibResolverJury.store().eveIdentity;
        if (eveIdentity == address(0)) {
            revert Errors.ZeroAddress();
        }

        uint256 selectedCount = dispute.allSelected.length;
        for (uint256 index; index < selectedCount; ++index) {
            uint256 identityId = dispute.allSelected[index];
            if (!_hasValidRevealInAnyRound(dispute, identityId)) {
                continue;
            }

            address recipient = IEveIdentity(eveIdentity).ownerOf(identityId);
            distributed += perRecipient;
            _transferIfNonzero(token, recipient, perRecipient);
            emit Events.RewardDistributed(disputeId, identityId, recipient, token, perRecipient);
        }

        uint256 remainder = uint256(rewardPool) - distributed;
        if (remainder != 0) {
            _transferIfNonzero(token, treasury, remainder);
        }
    }

    function _routeClaimantShare(address token, address treasury, address claimant, uint256 amount) internal {
        if (claimant == address(0)) {
            _transferIfNonzero(token, treasury, amount);
            return;
        }

        _transferIfNonzero(token, claimant, amount);
    }

    function _transferIfNonzero(address token, address recipient, uint256 amount) internal {
        if (amount == 0) {
            return;
        }
        if (recipient == address(0)) {
            revert Errors.ZeroAddress();
        }

        address bondToken = LibEveMarket.store().config.bondToken;
        if (token == bondToken) {
            if (amount > type(uint128).max) {
                revert Errors.InvalidAmount(amount);
            }
            IBondManagerFacet(address(this)).routeBond(recipient, uint128(amount));
            return;
        }

        IERC20(token).safeTransfer(recipient, amount);
    }

    function _bondClaimantForOutcome(LibEveMarket.EveMarketStorage storage state, bytes32 marketId, uint8 outcome)
        internal
        view
        returns (address claimant)
    {
        LibEveMarket.Resolution[] storage history = state.resolutionHistory[marketId];
        for (uint256 index = history.length; index > 0; --index) {
            LibEveMarket.Resolution storage proposal = history[index - 1];
            if (proposal.proposedOutcome == outcome) {
                return proposal.proposer;
            }
        }
    }

    function _bpsShare(uint256 amount, uint16 bps) internal pure returns (uint256) {
        return (amount * bps) / 10_000;
    }

    function _sumRouting4(uint16[4] storage routing) internal view returns (uint256 sum) {
        for (uint256 index; index < 4; ++index) {
            sum += routing[index];
        }
    }

    function _sumRouting3(uint16[3] storage routing) internal view returns (uint256 sum) {
        for (uint256 index; index < 3; ++index) {
            sum += routing[index];
        }
    }

    function _validRewardRecipientCount(LibResolverJury.Dispute storage dispute) internal view returns (uint256 count) {
        uint256 selectedCount = dispute.allSelected.length;
        for (uint256 index; index < selectedCount; ++index) {
            if (_hasValidRevealInAnyRound(dispute, dispute.allSelected[index])) {
                ++count;
            }
        }
    }

    function _hasValidRevealInAnyRound(LibResolverJury.Dispute storage dispute, uint256 identityId)
        internal
        view
        returns (bool)
    {
        for (uint256 roundIndex; roundIndex <= dispute.currentRound; ++roundIndex) {
            if (dispute.rounds[uint8(roundIndex)].hasRevealed[identityId]) {
                return true;
            }
        }

        return false;
    }

    function _initialAppealBondBase(LibEveMarket.EveMarketStorage storage state, bytes32 marketId)
        internal
        view
        returns (uint128 base)
    {
        base = state.resolutions[marketId].bondAmount;
        if (base != 0) {
            return base;
        }
        if (state.config.resolutionBondL2 != 0) {
            return state.config.resolutionBondL2;
        }
        return state.config.resolutionBondL1;
    }

    function _appealBondToken(LibEveMarket.EveMarketStorage storage state) internal view returns (address bondToken) {
        bondToken = state.config.bondToken;
        if (bondToken == address(0)) {
            revert Errors.ZeroAddress();
        }
    }

    function _payCallerIncentive(LibEveMarket.MarketConfig storage config, uint128 amount) internal {
        if (amount == 0) {
            return;
        }

        address token = config.bondToken;
        if (token == address(0)) {
            revert Errors.ZeroAddress();
        }

        IERC20(token).safeTransfer(msg.sender, amount);
    }

    function _requiredAppealBond(
        LibResolverJury.Dispute storage dispute,
        LibEveMarket.ResolverJuryConfig storage config,
        uint8 targetRound
    ) internal view returns (uint128 requiredBond) {
        if (dispute.disputeBondBase == 0) {
            revert Errors.InvalidAmount(0);
        }
        if (config.appealBondMultiplierBps <= 10_000) {
            revert Errors.InvalidConfigValue("appealBondMultiplierBps");
        }

        uint256 amount = dispute.disputeBondBase;
        for (uint8 round = 0; round < targetRound; ++round) {
            amount = _mulDivUp(amount, config.appealBondMultiplierBps, 10_000);
            if (amount > type(uint128).max) {
                revert Errors.InvalidAmount(amount);
            }
        }

        requiredBond = uint128(amount);
    }

    function _mulDivUp(uint256 amount, uint256 multiplier, uint256 divisor) internal pure returns (uint256) {
        return (amount * multiplier + divisor - 1) / divisor;
    }

    function _requireAppealBondFunding(address bondToken, uint128 requiredBond) internal view {
        IERC20 token = IERC20(bondToken);
        uint256 balance = token.balanceOf(msg.sender);
        uint256 allowance = token.allowance(msg.sender, address(this));
        uint256 provided = balance < allowance ? balance : allowance;
        if (provided < requiredBond) {
            revert Errors.AppealBondTooLow(requiredBond, _toUint128OrMax(provided));
        }
    }

    function _toUint128OrMax(uint256 value) internal pure returns (uint128) {
        return value > type(uint128).max ? type(uint128).max : uint128(value);
    }

    function _openNextSelectionRound(LibResolverJury.Dispute storage dispute) internal {
        uint256 nextRound = uint256(dispute.currentRound) + 1;
        if (nextRound > type(uint8).max) {
            revert Errors.InvalidAmount(nextRound);
        }

        dispute.currentRound = uint8(nextRound);
        dispute.rounds[dispute.currentRound].round = dispute.currentRound;
        dispute.state = LibResolverJury.DisputeState.CommitteeSelectionPending;
    }

    function _clearRoundForRedraw(LibResolverJury.Dispute storage dispute, LibResolverJury.DisputeRound storage round)
        internal
    {
        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        uint256 length = round.committee.length;
        for (uint256 index; index < length; ++index) {
            uint256 identityId = round.committee[index];
            round.inCommittee[identityId] = false;
            round.commitment[identityId] = bytes32(0);
            round.hasCommitted[identityId] = false;
            round.hasRevealed[identityId] = false;
            round.revealedOutcome[identityId] = 0;
            if (jury.identities[identityId].unresolvedCommittees != 0) {
                jury.identities[identityId].unresolvedCommittees -= 1;
            }
        }
        delete round.committee;

        _clearRoundTally(dispute, round);
        round.committeeSize = 0;
        round.validRevealCount = 0;
        round.randomnessCommitDeadline = 0;
        round.randomnessRevealDeadline = 0;
        round.randomnessReferenceBlock = 0;
        round.commitDeadline = 0;
        round.revealDeadline = 0;
        round.appealDeadline = 0;
        round.provisionalResult = 0;
        round.hasProvisional = false;
        round.seed = bytes32(0);
        round.randomnessAccumulator = bytes32(0);
        round.allEligibleFallback = false;
    }

    function _clearRoundTally(LibResolverJury.Dispute storage dispute, LibResolverJury.DisputeRound storage round)
        internal
    {
        if (dispute.isMultiOutcome) {
            for (uint8 outcome; outcome < dispute.outcomeCount; ++outcome) {
                round.tally[outcome] = 0;
            }
            round.tally[MULTI_OUTCOME_INVALID] = 0;
            return;
        }

        round.tally[uint8(LibEveMarket.MarketOutcome.Yes)] = 0;
        round.tally[uint8(LibEveMarket.MarketOutcome.No)] = 0;
        round.tally[uint8(LibEveMarket.MarketOutcome.Invalid)] = 0;
    }

    function _invalidOutcomeFor(LibResolverJury.Dispute storage dispute) internal view returns (uint8) {
        return dispute.isMultiOutcome ? MULTI_OUTCOME_INVALID : uint8(LibEveMarket.MarketOutcome.Invalid);
    }

    function _isValidJuryOutcome(LibResolverJury.Dispute storage dispute, uint8 outcome) internal view returns (bool) {
        if (dispute.isMultiOutcome) {
            return LibMultiOutcome.isValidResolution(outcome, dispute.outcomeCount);
        }

        return outcome == uint8(LibEveMarket.MarketOutcome.Yes) || outcome == uint8(LibEveMarket.MarketOutcome.No)
            || outcome == uint8(LibEveMarket.MarketOutcome.Invalid);
    }

    function _deriveRandomnessSeed(bytes32 disputeId, bytes32 validRevealAccumulator, bytes32 delayedBlockEntropy)
        internal
        pure
        returns (bytes32 seed)
    {
        seed = keccak256(abi.encode(disputeId, validRevealAccumulator, delayedBlockEntropy));
    }
}
