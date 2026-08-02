// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {IBondManagerFacet} from "../interfaces/IBondManagerFacet.sol";
import {IBondTokenGateFacet} from "../interfaces/IBondTokenGateFacet.sol";
import {IOBRResolutionFacet} from "../interfaces/IOBRResolutionFacet.sol";
import {IResolverJuryFacet} from "../interfaces/IResolverJuryFacet.sol";
import {Errors} from "../libraries/Errors.sol";
import {Events} from "../libraries/Events.sol";
import {LibCTF} from "../libraries/LibCTF.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibMultiOutcome} from "../libraries/LibMultiOutcome.sol";
import {LibParimutuel} from "../libraries/LibParimutuel.sol";
import {LibReentrancy} from "../libraries/LibReentrancy.sol";
import {LibResolverJury} from "../libraries/LibResolverJury.sol";

contract OBRResolutionFacet is IOBRResolutionFacet {
    using SafeERC20 for IERC20;

    uint8 internal constant OUTCOME_YES = uint8(LibEveMarket.MarketOutcome.Yes);
    uint8 internal constant OUTCOME_NO = uint8(LibEveMarket.MarketOutcome.No);
    uint8 internal constant OUTCOME_INVALID = uint8(LibEveMarket.MarketOutcome.Invalid);

    modifier nonReentrant() {
        LibReentrancy.enter();
        _;
        LibReentrancy.exit();
    }

    function settleMarket(bytes32 marketId, uint8 outcome) external {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Market storage market = _loadPendingExpiredMarket(state, marketId);
        _validateOutcome(state, market, outcome);

        if (msg.sender != market.creator) {
            revert Errors.NotMarketCreator(msg.sender, market.creator);
        }

        uint64 graceDeadline = _creatorGraceDeadline(market, state.config.creatorSettleGrace);
        if (block.timestamp >= graceDeadline) {
            revert Errors.CreatorGraceExpired(marketId);
        }

        _recordProposal(state, marketId, msg.sender, outcome, 0, 0, _disputeDeadline(state.config));
        market.state = LibEveMarket.MarketState.Disputed;

        emit Events.CreatorSettled(marketId, outcome);
    }

    function settleMarketEarly(bytes32 marketId, uint8 outcome) external nonReentrant {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Market storage market = _loadTradingMarketForEarlySettlement(state, marketId);
        _validateOutcome(state, market, outcome);

        if (msg.sender != market.creator) {
            revert Errors.NotMarketCreator(msg.sender, market.creator);
        }

        _recordProposal(state, marketId, msg.sender, outcome, 0, 0, _disputeDeadline(state.config));
        market.state = LibEveMarket.MarketState.Disputed;

        emit Events.CreatorSettled(marketId, outcome);
        emit Events.EarlyCreatorSettled(marketId, outcome);
    }

    function openResolution(bytes32 marketId, uint8 outcome) external nonReentrant {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Market storage market = _loadPendingExpiredMarket(state, marketId);
        _validateOutcome(state, market, outcome);

        uint64 graceDeadline = _creatorGraceDeadline(market, state.config.creatorSettleGrace);
        if (block.timestamp < graceDeadline) {
            revert Errors.CreatorGraceActive(marketId);
        }

        if (block.timestamp >= graceDeadline + state.config.openResolutionTimeout) {
            revert Errors.OpenResolutionExpired(marketId);
        }

        uint128 requiredBond = _bondAmountForLevel(state.config, 1);

        IBondTokenGateFacet(address(this)).lockResolutionBond(msg.sender, 1);
        _recordBond(state, marketId, msg.sender, requiredBond);
        _recordProposal(state, marketId, msg.sender, outcome, 1, requiredBond, _disputeDeadline(state.config));

        market.state = LibEveMarket.MarketState.Disputed;

        emit Events.OpenResolutionStarted(marketId, msg.sender, outcome);
    }

    function disputeResolution(bytes32 marketId, uint8 counterOutcome) external nonReentrant {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Market storage market = state.markets[marketId];

        if (market.state != LibEveMarket.MarketState.Disputed) {
            revert Errors.NoActiveResolution(marketId);
        }
        if (_hasResolverJuryDispute(marketId)) {
            revert Errors.ResolutionNotReady(marketId);
        }

        LibEveMarket.Resolution storage current = state.resolutions[marketId];
        if (current.proposer == address(0)) {
            revert Errors.NoActiveResolution(marketId);
        }

        _validateOutcome(state, market, counterOutcome);

        if (block.timestamp >= current.disputeDeadline) {
            revert Errors.DisputeWindowClosed(marketId);
        }

        if (counterOutcome == current.proposedOutcome) {
            revert Errors.SameOutcome(current.proposedOutcome, counterOutcome);
        }

        uint8 previousLevel = current.escalationLevel;
        uint8 nextLevel = _nextEscalationLevel(current.escalationLevel, state.config.maxEscalation);
        uint128 requiredBond = _bondAmountForLevel(state.config, nextLevel);

        _markLatestProposalDisputed(state, marketId);

        IBondTokenGateFacet(address(this)).lockResolutionBond(msg.sender, nextLevel);
        _recordBond(state, marketId, msg.sender, requiredBond);
        _recordProposal(
            state, marketId, msg.sender, counterOutcome, nextLevel, requiredBond, _disputeDeadline(state.config)
        );

        emit Events.ResolutionDisputed(marketId, msg.sender, counterOutcome, nextLevel);

        if (previousLevel >= state.config.maxEscalation) {
            _initiateResolverJury(marketId);
        }
    }

    function getResolutionHistory(bytes32 marketId)
        external
        view
        returns (ResolutionInfo[] memory history, uint8 currentEscalationLevel, uint64 disputeDeadline, bool isActive)
    {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Market storage market = state.markets[marketId];
        if (market.marketId != marketId) {
            revert Errors.MarketNotFound(marketId);
        }

        LibEveMarket.Resolution[] storage storedHistory = state.resolutionHistory[marketId];
        history = new ResolutionInfo[](storedHistory.length);

        for (uint256 index = 0; index < storedHistory.length; ++index) {
            LibEveMarket.Resolution storage proposal = storedHistory[index];
            history[index] = ResolutionInfo({
                proposer: proposal.proposer,
                proposedOutcome: proposal.proposedOutcome,
                escalationLevel: proposal.escalationLevel,
                disputed: proposal.disputed,
                bondAmount: proposal.bondAmount,
                proposedAt: proposal.proposedAt,
                disputeDeadline: proposal.disputeDeadline,
                snapshotBlock: proposal.snapshotBlock
            });
        }

        LibEveMarket.Resolution storage current = state.resolutions[marketId];
        currentEscalationLevel = current.escalationLevel;
        disputeDeadline = current.disputeDeadline;
        isActive = market.state == LibEveMarket.MarketState.Disputed;
    }

    function finalizeResolution(bytes32 marketId) external nonReentrant {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Market storage market = state.markets[marketId];

        if (market.marketId != marketId) {
            revert Errors.MarketNotFound(marketId);
        }

        _syncExpiredMarket(market);

        if (market.state == LibEveMarket.MarketState.Pending) {
            _finalizeMissingResolution(state, market, marketId);
            return;
        }

        if (market.state == LibEveMarket.MarketState.Resolved) {
            revert Errors.MarketAlreadyResolved(marketId);
        }
        if (_hasResolverJuryDispute(marketId)) {
            revert Errors.ResolutionNotReady(marketId);
        }

        if (market.state != LibEveMarket.MarketState.Disputed) {
            revert Errors.ResolutionNotReady(marketId);
        }

        LibEveMarket.Resolution storage resolution = state.resolutions[marketId];
        if (resolution.proposer == address(0)) {
            revert Errors.NoActiveResolution(marketId);
        }

        if (block.timestamp < resolution.disputeDeadline) {
            revert Errors.ResolutionNotReady(marketId);
        }

        _finalizeOutcome(
            state,
            market,
            marketId,
            resolution.proposedOutcome,
            _winningResolver(state, marketId, resolution.proposedOutcome)
        );
    }

    function finalizeFromJury(bytes32 marketId, uint8 finalResult) external {
        if (msg.sender != address(this)) {
            revert Errors.InternalCallOnly(msg.sender);
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Market storage market = state.markets[marketId];
        if (market.marketId != marketId) {
            revert Errors.MarketNotFound(marketId);
        }
        if (market.state == LibEveMarket.MarketState.Resolved) {
            revert Errors.MarketAlreadyResolved(marketId);
        }
        if (market.state != LibEveMarket.MarketState.Disputed || !_hasResolverJuryDispute(marketId)) {
            revert Errors.ResolutionNotReady(marketId);
        }

        _validateOutcome(state, market, finalResult);
        _finalizeOutcome(state, market, marketId, finalResult, _winningResolver(state, marketId, finalResult));
    }

    function getMarketStatus(bytes32 marketId)
        external
        view
        returns (uint8 state_, uint8 outcome_, uint64 disputeDeadline, uint128 creatorFeesEscrowed)
    {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Market storage market = state.markets[marketId];

        state_ = uint8(market.state);
        outcome_ = _storedOutcome(state, market);
        disputeDeadline = state.resolutions[marketId].disputeDeadline;
        creatorFeesEscrowed = market.creatorFeesEscrowed;
    }

    function _loadPendingExpiredMarket(LibEveMarket.EveMarketStorage storage state, bytes32 marketId)
        internal
        returns (LibEveMarket.Market storage market)
    {
        market = state.markets[marketId];

        if (market.marketId != marketId) {
            revert Errors.MarketNotFound(marketId);
        }

        _syncExpiredMarket(market);

        if (market.state == LibEveMarket.MarketState.Resolved) {
            revert Errors.MarketAlreadyResolved(marketId);
        }

        if (market.state != LibEveMarket.MarketState.Pending) {
            revert Errors.MarketNotPending(marketId);
        }

        if (block.timestamp < market.expiryTime) {
            revert Errors.MarketNotExpired(marketId);
        }
    }

    function _loadTradingMarketForEarlySettlement(LibEveMarket.EveMarketStorage storage state, bytes32 marketId)
        internal
        returns (LibEveMarket.Market storage market)
    {
        market = state.markets[marketId];

        if (market.marketId != marketId) {
            revert Errors.MarketNotFound(marketId);
        }

        if (market.state == LibEveMarket.MarketState.Resolved) {
            revert Errors.MarketAlreadyResolved(marketId);
        }

        if (market.state == LibEveMarket.MarketState.Scheduled && block.timestamp >= market.tradingStartTime) {
            market.state = LibEveMarket.MarketState.Trading;
        }

        if (
            market.state != LibEveMarket.MarketState.Trading || block.timestamp < market.tradingStartTime
                || block.timestamp >= market.expiryTime
        ) {
            revert Errors.MarketNotTrading(marketId);
        }
    }

    function _syncExpiredMarket(LibEveMarket.Market storage market) internal {
        if (market.state == LibEveMarket.MarketState.Scheduled && block.timestamp >= market.tradingStartTime) {
            market.state = LibEveMarket.MarketState.Trading;
        }

        if (market.state != LibEveMarket.MarketState.Trading) {
            return;
        }

        if (block.timestamp < market.expiryTime) {
            revert Errors.MarketNotExpired(market.marketId);
        }

        if (block.timestamp >= market.expiryTime) {
            market.state = LibEveMarket.MarketState.Pending;
            emit Events.MarketExpired(market.marketId);
        }
    }

    function _recordBond(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 marketId,
        address proposer,
        uint128 amount
    ) internal {
        if (amount != 0) {
            state.bondedByMarket[marketId][proposer] += amount;
        }
    }

    function _recordProposal(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 marketId,
        address proposer,
        uint8 outcome,
        uint8 escalationLevel,
        uint128 bondAmount,
        uint64 disputeDeadline
    ) internal {
        LibEveMarket.Resolution memory proposal = LibEveMarket.Resolution({
            marketId: marketId,
            proposer: proposer,
            proposedOutcome: outcome,
            escalationLevel: escalationLevel,
            disputed: false,
            bondAmount: bondAmount,
            reservedBondAmount: 0,
            proposedAt: uint64(block.timestamp),
            disputeDeadline: disputeDeadline,
            snapshotBlock: 0
        });

        state.resolutions[marketId] = proposal;
        state.resolutionHistory[marketId].push(proposal);
    }

    function _markLatestProposalDisputed(LibEveMarket.EveMarketStorage storage state, bytes32 marketId) internal {
        LibEveMarket.Resolution[] storage history = state.resolutionHistory[marketId];
        uint256 historyLength = history.length;
        if (historyLength == 0) {
            return;
        }

        history[historyLength - 1].disputed = true;
    }

    function _validateOutcome(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.Market storage market,
        uint8 outcome
    ) internal view {
        if (market.marketType == LibEveMarket.MarketType.MULTI_OUTCOME_ORDERBOOK) {
            LibEveMarket.MultiOutcomeMarket storage multi = state.multiOutcomeMarkets[market.marketId];
            if (!multi.exists || !LibMultiOutcome.isValidResolution(outcome, multi.outcomeCount)) {
                revert Errors.InvalidOutcome(outcome);
            }
            return;
        }

        if (outcome < OUTCOME_YES || outcome > OUTCOME_INVALID) {
            revert Errors.InvalidOutcome(outcome);
        }
    }

    function _bondAmountForLevel(LibEveMarket.MarketConfig storage config, uint8 escalationLevel)
        internal
        view
        returns (uint128 amount)
    {
        if (escalationLevel == 1) {
            return config.resolutionBondL1;
        }

        if (escalationLevel >= 2) {
            return config.resolutionBondL2;
        }

        return 0;
    }

    function _nextEscalationLevel(uint8 currentLevel, uint8 maxEscalation) internal pure returns (uint8) {
        if (currentLevel >= maxEscalation) {
            return maxEscalation;
        }

        return currentLevel + 1;
    }

    function _creatorGraceDeadline(LibEveMarket.Market storage market, uint64 creatorSettleGrace)
        internal
        view
        returns (uint64)
    {
        return market.expiryTime + creatorSettleGrace;
    }

    function _disputeDeadline(LibEveMarket.MarketConfig storage config) internal view returns (uint64) {
        return uint64(block.timestamp) + config.disputeWindow;
    }

    function _initiateResolverJury(bytes32 marketId) internal {
        IResolverJuryFacet(address(this)).initiateDispute(marketId);
    }

    function _hasResolverJuryDispute(bytes32 marketId) internal view returns (bool) {
        return LibResolverJury.store().disputeIdByMarket[marketId] != bytes32(0);
    }

    function _finalizeMissingResolution(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.Market storage market,
        bytes32 marketId
    ) internal {
        uint64 timeoutDeadline = _creatorGraceDeadline(market, state.config.creatorSettleGrace)
        + state.config.openResolutionTimeout;
        if (block.timestamp < timeoutDeadline) {
            revert Errors.ResolutionNotReady(marketId);
        }

        _finalizeOutcome(state, market, marketId, OUTCOME_INVALID, address(0));
    }

    function _finalizeOutcome(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.Market storage market,
        bytes32 marketId,
        uint8 outcome,
        address rewardRecipient
    ) internal {
        uint8 creatorOutcome = _creatorSettledOutcome(state, marketId, market.creator);
        uint128 creatorFeesEscrowedAtFinalization = market.creatorFeesEscrowed;
        uint128 creationBondAtFinalization = market.creationBond;
        bool creatorSettledHonestly = creatorOutcome != 0 && creatorOutcome == outcome;

        if (market.marketType == LibEveMarket.MarketType.MULTI_OUTCOME_ORDERBOOK) {
            _finalizeMultiOutcomeMarket(state, marketId, outcome);
            market.outcome = outcome == LibMultiOutcome.OUTCOME_INVALID
                ? LibEveMarket.MarketOutcome.Invalid
                : LibEveMarket.MarketOutcome.Unresolved;
        } else {
            market.outcome = LibEveMarket.MarketOutcome(outcome);
        }
        market.state = LibEveMarket.MarketState.Resolved;
        market.resolutionTime = uint64(block.timestamp);
        market.creatorSettledHonestly = creatorSettledHonestly;
        market.creatorFeeEligible =
            creatorSettledHonestly && outcome != OUTCOME_INVALID && creatorFeesEscrowedAtFinalization != 0;
        market.creationBondReturnable = creatorSettledHonestly && creationBondAtFinalization != 0;

        _settleRecordedBonds(state, marketId, outcome);
        _settleCreationBond(state, market, marketId, rewardRecipient);
        _routeCreatorFees(state, market, marketId, outcome, rewardRecipient);

        if (market.marketType == LibEveMarket.MarketType.CLOB) {
            _reportOutcome(marketId, market.positionToken, market.resolutionId, outcome);
        } else if (market.marketType == LibEveMarket.MarketType.PARIMUTUEL) {
            _finalizeParimutuelPool(marketId, outcome);
        }

        emit Events.ResolutionFinalized(marketId, outcome);
        emit Events.CreatorSettlementEvaluated(
            marketId, market.creator, creatorOutcome, outcome, creatorSettledHonestly
        );
        emit Events.CreatorFeeEligibilitySet(
            marketId, market.creator, market.creatorFeeEligible, creatorFeesEscrowedAtFinalization
        );
        emit Events.CreationBondReturnabilitySet(
            marketId, market.creator, market.creationBondReturnable, creationBondAtFinalization
        );
    }

    function _finalizeParimutuelPool(bytes32 marketId, uint8 outcome) internal {
        LibEveMarket.MarketOutcome rawOutcome = LibEveMarket.MarketOutcome(outcome);
        LibParimutuel.Pool storage pool = LibParimutuel.store().pools[marketId];
        (LibEveMarket.MarketOutcome effectiveOutcome, uint128 totalClaimableShares) =
            LibParimutuel.finalizePool(pool, rawOutcome);

        emit Events.ParimutuelFinalized(
            marketId, outcome, uint8(effectiveOutcome), pool.payoutPoolAtResolution, totalClaimableShares
        );
    }

    function _finalizeMultiOutcomeMarket(LibEveMarket.EveMarketStorage storage state, bytes32 marketId, uint8 outcome)
        internal
    {
        LibEveMarket.MultiOutcomeMarket storage multi = state.multiOutcomeMarkets[marketId];
        if (!multi.exists || !LibMultiOutcome.isValidResolution(outcome, multi.outcomeCount)) {
            revert Errors.InvalidOutcome(outcome);
        }

        multi.resolved = true;
        multi.invalid = outcome == LibMultiOutcome.OUTCOME_INVALID;
        multi.resolvedOutcome = outcome;
        multi.payoutDenominator = multi.invalid ? multi.outcomeCount : 1;

        emit Events.MultiOutcomeResolved(marketId, outcome, multi.invalid, multi.payoutDenominator);
        emit Events.PayoutReported(marketId, outcome, keccak256(abi.encode(multi.outcomeCount, outcome)));
    }

    function _settleCreationBond(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.Market storage market,
        bytes32 marketId,
        address rewardRecipient
    ) internal {
        uint128 creationBond = market.creationBond;
        if (creationBond == 0 || market.creationBondReleased) {
            return;
        }
        address bondToken = state.config.bondToken;
        if (bondToken == address(0)) {
            revert Errors.ZeroAddress();
        }

        market.creationBondReleased = true;

        if (market.creationBondReturnable) {
            IERC20(bondToken).safeTransfer(market.creator, creationBond);
            emit Events.CreationBondReleased(marketId, market.creator, creationBond);
            return;
        }

        uint256 treasuryShare = creationBond;

        if (rewardRecipient != address(0) && rewardRecipient != market.creator) {
            uint256 resolverReward = uint256(creationBond) / 10;
            treasuryShare -= resolverReward;
            IERC20(bondToken).safeTransfer(rewardRecipient, resolverReward);
        }

        IERC20(bondToken).safeTransfer(state.config.eveTreasury, treasuryShare);
        emit Events.CreationBondSlashed(marketId, market.creator, rewardRecipient, creationBond);
    }

    function _routeCreatorFees(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.Market storage market,
        bytes32 marketId,
        uint8 outcome,
        address rewardRecipient
    ) internal {
        uint128 escrowed = market.creatorFeesEscrowed;
        if (escrowed == 0) {
            return;
        }

        if (market.creatorFeeEligible) {
            return;
        }

        uint8 creatorOutcome = _creatorSettledOutcome(state, marketId, market.creator);
        uint256 treasuryShare = escrowed;
        IERC20 collateralToken = IERC20(market.collateralToken);

        market.creatorFeesEscrowed = 0;

        if (
            creatorOutcome != 0 && creatorOutcome != outcome && outcome != OUTCOME_INVALID
                && rewardRecipient != address(0) && rewardRecipient != market.creator
        ) {
            uint256 challengerReward = uint256(escrowed) / 10;
            treasuryShare -= challengerReward;
            collateralToken.safeTransfer(rewardRecipient, challengerReward);
        }

        collateralToken.safeTransfer(state.config.eveTreasury, treasuryShare);
        emit Events.CreatorFeesForfeited(marketId, escrowed);
    }

    function _creatorSettledOutcome(LibEveMarket.EveMarketStorage storage state, bytes32 marketId, address creator)
        internal
        view
        returns (uint8)
    {
        LibEveMarket.Resolution[] storage history = state.resolutionHistory[marketId];
        for (uint256 index = 0; index < history.length; ++index) {
            LibEveMarket.Resolution storage proposal = history[index];
            if (proposal.proposer == creator && proposal.escalationLevel == 0) {
                return proposal.proposedOutcome;
            }
        }

        return 0;
    }

    function _settleRecordedBonds(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 marketId,
        uint8 finalOutcome
    ) internal {
        LibEveMarket.Resolution[] storage history = state.resolutionHistory[marketId];

        for (uint256 index = 0; index < history.length; ++index) {
            LibEveMarket.Resolution storage proposal = history[index];
            if (proposal.bondAmount == 0) {
                continue;
            }

            if (proposal.proposedOutcome == finalOutcome) {
                IBondManagerFacet(address(this)).returnBond(marketId, index);
            } else {
                IBondManagerFacet(address(this)).slashBond(marketId, index, state.config.eveTreasury);
            }
        }
    }

    function _winningResolver(LibEveMarket.EveMarketStorage storage state, bytes32 marketId, uint8 outcome)
        internal
        view
        returns (address)
    {
        LibEveMarket.Resolution[] storage history = state.resolutionHistory[marketId];
        for (uint256 index = history.length; index > 0; --index) {
            LibEveMarket.Resolution storage proposal = history[index - 1];
            if (proposal.proposedOutcome == outcome) {
                return proposal.proposer;
            }
        }

        return address(0);
    }

    function _storedOutcome(LibEveMarket.EveMarketStorage storage state, LibEveMarket.Market storage market)
        internal
        view
        returns (uint8 outcome)
    {
        LibEveMarket.MultiOutcomeMarket storage multi = state.multiOutcomeMarkets[market.marketId];
        if (multi.exists && multi.resolved) {
            return multi.resolvedOutcome;
        }
        return uint8(market.outcome);
    }

    function _reportOutcome(bytes32 marketId, address conditionalTokens, bytes32 questionId, uint8 outcome) internal {
        uint256[] memory payouts = new uint256[](2);

        if (outcome == OUTCOME_YES) {
            payouts[0] = 1;
        } else if (outcome == OUTCOME_NO) {
            payouts[1] = 1;
        } else {
            payouts[0] = 1;
            payouts[1] = 1;
        }

        LibCTF.prepareMarketCondition(conditionalTokens, questionId);
        LibCTF.reportOutcome(conditionalTokens, questionId, payouts);
        emit Events.PayoutReported(marketId, outcome, keccak256(abi.encode(payouts[0], payouts[1])));
    }
}
