// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Strings} from "../../../lib/openzeppelin-contracts/contracts/utils/Strings.sol";

import {IParlayTicketToken} from "../../interfaces/IParlayTicketToken.sol";
import {Errors} from "../../libraries/Errors.sol";
import {Events} from "../../libraries/Events.sol";
import {LibCollateralProfile} from "../../libraries/LibCollateralProfile.sol";
import {LibEveMarket} from "../../libraries/LibEveMarket.sol";
import {LibFeeRouting} from "../../libraries/LibFeeRouting.sol";
import {LibParlay} from "../../libraries/LibParlay.sol";
import {LibReentrancy} from "../../libraries/LibReentrancy.sol";
import {LibSeniorCapital} from "../../libraries/LibSeniorCapital.sol";
import {ParlayTypes} from "../../types/ParlayTypes.sol";

abstract contract ParlayBase {
    using SafeERC20 for IERC20;

    uint8 internal constant YES_OUTCOME = uint8(LibEveMarket.MarketOutcome.Yes);
    uint8 internal constant NO_OUTCOME = uint8(LibEveMarket.MarketOutcome.No);
    uint8 internal constant INVALID_OUTCOME = uint8(LibEveMarket.MarketOutcome.Invalid);
    uint128 internal constant DEFAULT_COLLATERAL_PAYOUT_UNIT = 1 ether;

    struct ParlayCollateralContext {
        uint8 profileId;
        address collateralToken;
        uint128 payoutUnit;
        uint128 underwritingFee;
    }

    modifier nonReentrant() {
        LibReentrancy.enter();
        _;
        LibReentrancy.exit();
    }

    function _validateTemplateTerms(
        ParlayTypes.ParlayLeg[] calldata legs,
        ParlayTypes.PayoutTier[] calldata payoutTiers,
        ParlayTypes.InvalidPolicy invalidPolicy
    ) internal view {
        if (uint8(invalidPolicy) > uint8(ParlayTypes.InvalidPolicy.InvalidCountsAsMiss)) {
            revert Errors.ParlayInvalidPolicy(uint8(invalidPolicy));
        }
        if (legs.length < LibParlay.MIN_LEGS || legs.length > LibParlay.MAX_LEGS) {
            revert Errors.ParlayLegCountInvalid(legs.length);
        }
        for (uint256 index = 0; index < legs.length; ++index) {
            _validateLegMarket(legs[index].marketId);
            _validateRequiredOutcome(legs[index].marketId, legs[index].requiredOutcome);
            if (index != 0) {
                if (legs[index].marketId == legs[index - 1].marketId) {
                    revert Errors.ParlayDuplicateMarket(legs[index].marketId);
                }
                if (uint256(legs[index].marketId) <= uint256(legs[index - 1].marketId)) {
                    revert Errors.ParlayNonCanonicalLegs(legs[index - 1].marketId, legs[index].marketId);
                }
            }
        }
        _validatePayoutTiers(payoutTiers, legs.length);
    }

    function _validatePayoutTiers(ParlayTypes.PayoutTier[] calldata payoutTiers, uint256 legCount) internal pure {
        if (payoutTiers.length == 0) {
            revert Errors.ParlayInvalidPayoutTiers();
        }

        uint8 previousMinHits = type(uint8).max;
        uint128 previousPayout = type(uint128).max;
        for (uint256 index = 0; index < payoutTiers.length; ++index) {
            ParlayTypes.PayoutTier calldata tier = payoutTiers[index];
            if (tier.minHits == 0 || tier.minHits > legCount || tier.payout == 0) {
                revert Errors.ParlayInvalidPayoutTiers();
            }
            if (index != 0 && (tier.minHits >= previousMinHits || tier.payout > previousPayout)) {
                revert Errors.ParlayInvalidPayoutTiers();
            }
            previousMinHits = tier.minHits;
            previousPayout = tier.payout;
        }
    }

    function _validateLegMarket(bytes32 marketId) internal view {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        if (state.comboMarkets[marketId].exists) {
            revert Errors.ParlayUnsupportedMarketType(marketId, type(uint8).max);
        }

        LibEveMarket.Market storage market = state.markets[marketId];
        if (market.marketId != marketId) {
            revert Errors.MarketNotFound(marketId);
        }
        if (
            market.marketType != LibEveMarket.MarketType.CLOB && market.marketType != LibEveMarket.MarketType.PARIMUTUEL
                && market.marketType != LibEveMarket.MarketType.MULTI_OUTCOME_ORDERBOOK
        ) {
            revert Errors.ParlayUnsupportedMarketType(marketId, uint8(market.marketType));
        }
        if (!_isFillableMarket(market)) {
            revert Errors.ParlayMarketNotFillable(marketId, uint8(market.state), uint8(market.outcome));
        }
    }

    function _validateRequiredOutcome(bytes32 marketId, uint8 requiredOutcome) internal view {
        LibEveMarket.Market storage market = LibEveMarket.store().markets[marketId];
        if (market.marketType == LibEveMarket.MarketType.MULTI_OUTCOME_ORDERBOOK) {
            LibEveMarket.MultiOutcomeMarket storage multi = LibEveMarket.store().multiOutcomeMarkets[marketId];
            if (!multi.exists || requiredOutcome >= multi.outcomeCount) {
                revert Errors.ParlayUnsupportedOutcome(requiredOutcome);
            }
            return;
        }

        if (requiredOutcome != YES_OUTCOME && requiredOutcome != NO_OUTCOME) {
            revert Errors.ParlayUnsupportedOutcome(requiredOutcome);
        }
    }

    function _validateFillableTemplate(uint256 templateId, uint64 fillDeadline) internal view {
        LibParlay.Storage storage state = LibParlay.store();
        LibParlay.ParlayTemplate storage template_ = _requireTemplate(state, templateId);
        uint64 earliestExpiry = type(uint64).max;
        for (uint256 index = 0; index < template_.legCount; ++index) {
            bytes32 marketId = state.templateLegs[templateId][index].marketId;
            LibEveMarket.Market storage market = LibEveMarket.store().markets[marketId];
            if (!_isFillableMarket(market)) {
                revert Errors.ParlayMarketNotFillable(marketId, uint8(market.state), uint8(market.outcome));
            }
            if (market.expiryTime < earliestExpiry) {
                earliestExpiry = market.expiryTime;
            }
        }
        if (fillDeadline > earliestExpiry) {
            revert Errors.ExpiryTooLate(fillDeadline, earliestExpiry);
        }
    }

    function _validatePostedTerms(
        uint128 expectedMaxPayout,
        uint128 maxPayoutPerUnit,
        uint128 units,
        uint64 fillDeadline
    ) internal view {
        if (units == 0) {
            revert Errors.InvalidAmount(units);
        }
        if (fillDeadline <= block.timestamp) {
            revert Errors.ParlayExpired(fillDeadline);
        }
        if (maxPayoutPerUnit != expectedMaxPayout) {
            revert Errors.ParlayMaxPayoutMismatch(expectedMaxPayout, maxPayoutPerUnit);
        }
    }

    function _createParlayTermsIfMissing(
        LibParlay.Storage storage state,
        ParlayTypes.ParlayLeg[] calldata legs,
        ParlayTypes.PayoutTier[] calldata payoutTiers,
        ParlayTypes.InvalidPolicy invalidPolicy,
        string calldata metadataHint
    ) internal returns (uint256 templateId) {
        _validateTemplateTerms(legs, payoutTiers, invalidPolicy);

        templateId = LibParlay.templateIdFor(legs, payoutTiers, invalidPolicy);
        if (state.templates[templateId].exists) {
            return templateId;
        }

        state.templates[templateId] = LibParlay.ParlayTemplate({
            creator: msg.sender,
            maxPayoutPerUnit: payoutTiers[0].payout,
            invalidPolicy: uint8(invalidPolicy),
            legCount: uint8(legs.length),
            tierCount: uint8(payoutTiers.length),
            exists: true
        });
        state.templateMetadataHints[templateId] = metadataHint;

        for (uint256 index = 0; index < legs.length; ++index) {
            state.templateLegs[templateId][index] = legs[index];
        }
        for (uint256 index = 0; index < payoutTiers.length; ++index) {
            state.templatePayoutTiers[templateId][index] = payoutTiers[index];
        }

        emit Events.ParlayTemplateCreated(templateId, msg.sender, legs, payoutTiers, uint8(invalidPolicy), metadataHint);
    }

    function _isFillableMarket(LibEveMarket.Market storage market) internal view returns (bool) {
        if (market.outcome != LibEveMarket.MarketOutcome.Unresolved) {
            return false;
        }
        if (block.timestamp >= market.expiryTime) {
            return false;
        }
        return market.state == LibEveMarket.MarketState.Scheduled || market.state == LibEveMarket.MarketState.Trading;
    }

    function _mintIntoBucket(
        LibParlay.Storage storage state,
        uint256 templateId,
        ParlayTypes.SourceType sourceType,
        uint256 sourceId,
        address underwriter,
        uint128 premiumPerUnit,
        uint128 maxPayoutPerUnit,
        uint128 units,
        uint256 escrowLocked,
        ParlayCollateralContext memory collateralContext,
        address receiver
    ) internal returns (uint256 ticketId) {
        ticketId = LibParlay.ticketIdFor(templateId, sourceType, sourceId, underwriter, maxPayoutPerUnit);
        LibParlay.ParlayTicketBucket storage bucket = state.ticketBuckets[ticketId];
        if (bucket.templateId == 0) {
            bucket.templateId = templateId;
            bucket.sourceId = sourceId;
            bucket.underwriter = underwriter;
            bucket.collateralToken = collateralContext.collateralToken;
            bucket.premiumPerUnit = premiumPerUnit;
            bucket.maxPayoutPerUnit = maxPayoutPerUnit;
            bucket.payoutUnit = collateralContext.payoutUnit;
            bucket.sourceType = uint8(sourceType);
            bucket.collateralProfileId = collateralContext.profileId;
        }

        bucket.unitsMinted += units;
        bucket.escrowRemaining += escrowLocked;
        IParlayTicketToken(_requireConfig().ticketToken).mint(receiver, ticketId, units);
    }

    function _routeFlatFee(IERC20 collateralToken, uint256 ticketId, uint256 sourceId, uint8 sourceType, uint256 fee)
        internal
    {
        if (fee == 0) {
            emit Events.ParlayFlatFeeRouted(ticketId, sourceId, sourceType, 0, 0, 0);
            return;
        }

        LibParlay.Config storage config = _requireConfig();
        uint256 rawSeniorPoolAmount = (fee * config.seniorPoolFeeBps) / LibParlay.BPS_DENOMINATOR;
        uint256 feeRecipientAmount = fee - rawSeniorPoolAmount;

        LibFeeRouting.SeniorPoolFeeRoute memory route =
            LibFeeRouting.previewSeniorPoolFeeRoute(address(collateralToken), rawSeniorPoolAmount);
        uint256 seniorPoolAmount = route.seniorPoolAmount;
        feeRecipientAmount += route.treasuryAmount;

        if (seniorPoolAmount != 0) {
            LibSeniorCapital.accrueFees(
                LibSeniorCapital.s(), seniorPoolAmount, LibSeniorCapital.FEE_SOURCE_PARLAY, bytes32(ticketId)
            );
        }

        if (feeRecipientAmount != 0) {
            collateralToken.safeTransfer(config.feeRecipient, feeRecipientAmount);
        }

        emit Events.ParlayFlatFeeRouted(ticketId, sourceId, sourceType, fee, seniorPoolAmount, feeRecipientAmount);
    }

    function _scoreTemplate(LibParlay.Storage storage state, uint256 templateId)
        internal
        view
        returns (uint8 hits, uint8 misses, uint8 invalids)
    {
        LibParlay.ParlayTemplate storage template_ = _requireTemplate(state, templateId);
        for (uint256 index = 0; index < template_.legCount; ++index) {
            ParlayTypes.ParlayLeg storage leg = state.templateLegs[templateId][index];
            LibEveMarket.Market storage market = LibEveMarket.store().markets[leg.marketId];
            if (market.state != LibEveMarket.MarketState.Resolved) {
                revert Errors.ParlayLegUnresolved(leg.marketId);
            }
            if (
                market.marketType != LibEveMarket.MarketType.MULTI_OUTCOME_ORDERBOOK
                    && market.outcome == LibEveMarket.MarketOutcome.Unresolved
            ) {
                revert Errors.ParlayLegUnresolved(leg.marketId);
            }

            (bool invalid, uint8 outcome) = _parlayLegOutcome(market, leg.marketId);
            if (invalid) {
                ++invalids;
                if (template_.invalidPolicy == uint8(ParlayTypes.InvalidPolicy.InvalidCountsAsMiss)) {
                    ++misses;
                }
            } else if (outcome == leg.requiredOutcome) {
                ++hits;
            } else {
                ++misses;
            }
        }
    }

    function _parlayLegOutcome(LibEveMarket.Market storage market, bytes32 marketId)
        internal
        view
        returns (bool invalid, uint8 outcome)
    {
        if (market.marketType == LibEveMarket.MarketType.MULTI_OUTCOME_ORDERBOOK) {
            LibEveMarket.MultiOutcomeMarket storage multi = LibEveMarket.store().multiOutcomeMarkets[marketId];
            if (!multi.resolved) {
                revert Errors.ParlayLegUnresolved(marketId);
            }
            invalid = multi.invalid;
            outcome = multi.resolvedOutcome;
        } else {
            outcome = uint8(market.outcome);
            invalid = outcome == INVALID_OUTCOME;
        }
    }

    function _payoutForHits(LibParlay.Storage storage state, uint256 templateId, uint8 hits)
        internal
        view
        returns (uint128 payout)
    {
        LibParlay.ParlayTemplate storage template_ = _requireTemplate(state, templateId);
        for (uint256 index = 0; index < template_.tierCount; ++index) {
            ParlayTypes.PayoutTier storage tier = state.templatePayoutTiers[templateId][index];
            if (hits >= tier.minHits) {
                return tier.payout;
            }
        }
    }

    function _requireConfig() internal view returns (LibParlay.Config storage config) {
        config = LibParlay.store().config;
        if (config.ticketToken == address(0) || config.feeRecipient == address(0)) {
            revert Errors.ParlayNotConfigured();
        }
    }

    function _requireTemplate(LibParlay.Storage storage state, uint256 templateId)
        internal
        view
        returns (LibParlay.ParlayTemplate storage template_)
    {
        template_ = state.templates[templateId];
        if (!template_.exists) {
            revert Errors.ParlayTemplateNotFound(templateId);
        }
    }

    function _requireOffer(LibParlay.Storage storage state, uint256 offerId)
        internal
        view
        returns (LibParlay.ParlayOffer storage offer)
    {
        offer = state.offers[offerId];
        if (offer.maker == address(0)) {
            revert Errors.ParlayOfferNotFound(offerId);
        }
    }

    function _requireRequest(LibParlay.Storage storage state, uint256 requestId)
        internal
        view
        returns (LibParlay.ParlayRequest storage request)
    {
        request = state.requests[requestId];
        if (request.requester == address(0)) {
            revert Errors.ParlayRequestNotFound(requestId);
        }
    }

    function _requireParlayBudget(LibParlay.Storage storage state, uint256 budgetId)
        internal
        view
        returns (LibParlay.SharedBudget storage budget)
    {
        budget = state.budgets[budgetId];
        if (budget.owner == address(0)) {
            revert Errors.ParlayBudgetNotFound(budgetId);
        }
    }

    function _requireBudgetOwner(LibParlay.SharedBudget storage budget) internal view {
        if (msg.sender != budget.owner) {
            revert Errors.ParlayBudgetWrongOwner(msg.sender, budget.owner);
        }
    }

    function _requireActiveBudget(uint256 budgetId, LibParlay.SharedBudget storage budget) internal view {
        if (!budget.active) {
            revert Errors.ParlayBudgetInactive(budgetId);
        }
    }

    function _requireBudgetMode(LibParlay.SharedBudget storage budget, ParlayTypes.BudgetMode expectedMode)
        internal
        view
    {
        uint8 expected = uint8(expectedMode);
        if (budget.mode != expected) {
            revert Errors.ParlayBudgetWrongMode(expected, budget.mode);
        }
    }

    function _budgetCollateralContext(LibParlay.SharedBudget storage budget)
        internal
        view
        returns (ParlayCollateralContext memory context)
    {
        if (budget.collateralToken == address(0)) {
            return _defaultParlayCollateral();
        }

        context = ParlayCollateralContext({
            profileId: budget.collateralProfileId,
            collateralToken: budget.collateralToken,
            payoutUnit: budget.payoutUnit,
            underwritingFee: _parlayUnderwritingFeeForBudgetProfile(budget.collateralProfileId)
        });
    }

    function _activeBudgetCollateralContext(LibParlay.SharedBudget storage budget)
        internal
        view
        returns (ParlayCollateralContext memory context)
    {
        context = _budgetCollateralContext(budget);
        if (context.profileId == 0) {
            ParlayCollateralContext memory defaultContext = _defaultParlayCollateral();
            if (defaultContext.collateralToken != context.collateralToken) {
                revert Errors.ParlayCollateralMismatch(
                    bytes32(0), context.collateralToken, defaultContext.collateralToken
                );
            }
            if (defaultContext.payoutUnit != context.payoutUnit) {
                revert Errors.InvalidAmount(defaultContext.payoutUnit);
            }
            context.underwritingFee = defaultContext.underwritingFee;
            return context;
        }

        ParlayCollateralContext memory activeContext = _parlayCollateralFor(context.profileId);
        if (activeContext.collateralToken != context.collateralToken) {
            revert Errors.ParlayCollateralMismatch(bytes32(0), context.collateralToken, activeContext.collateralToken);
        }
        if (activeContext.payoutUnit != context.payoutUnit) {
            revert Errors.InvalidAmount(activeContext.payoutUnit);
        }
        context.underwritingFee = activeContext.underwritingFee;
    }

    function _requireBudgetCollateralProfile(
        LibParlay.SharedBudget storage budget,
        uint256 budgetId,
        uint8 collateralProfileId
    ) internal view returns (ParlayCollateralContext memory context) {
        context = _activeBudgetCollateralContext(budget);
        if (context.profileId != collateralProfileId) {
            revert Errors.ParlayBudgetCollateralProfileMismatch(budgetId, context.profileId, collateralProfileId);
        }
    }

    function _parlayUnderwritingFeeForBudgetProfile(uint8 collateralProfileId)
        internal
        view
        returns (uint128 underwritingFee)
    {
        if (collateralProfileId == 0) {
            return _requireConfig().underwritingFee;
        }
        underwritingFee = LibEveMarket.store().parlayUnderwritingFeeByProfile[collateralProfileId];
    }

    function _availableBudget(LibParlay.SharedBudget storage budget) internal view returns (uint256 available) {
        available = budget.deposited - budget.consumed;
    }

    function _consumeBudget(
        LibParlay.SharedBudget storage budget,
        uint256 budgetId,
        uint256 sourceId,
        ParlayTypes.SourceType sourceType,
        ParlayTypes.BudgetMode expectedMode,
        uint256 amount
    ) internal {
        _requireActiveBudget(budgetId, budget);
        _requireBudgetMode(budget, expectedMode);
        uint256 available = _availableBudget(budget);
        if (amount > available) {
            revert Errors.ParlayBudgetInsufficient(amount, available);
        }
        budget.consumed += amount;
        emit Events.ParlayBudgetConsumed(
            budgetId, sourceId, uint8(sourceType), amount, budget.consumed, available - amount
        );
    }

    function _requireBucket(LibParlay.Storage storage state, uint256 ticketId)
        internal
        view
        returns (LibParlay.ParlayTicketBucket storage bucket)
    {
        bucket = state.ticketBuckets[ticketId];
        if (bucket.underwriter == address(0)) {
            revert Errors.ParlayTicketNotFound(ticketId);
        }
    }

    function _requireActiveOffer(uint256 offerId, LibParlay.ParlayOffer storage offer) internal view {
        if (!offer.active || offer.remainingUnits == 0) {
            revert Errors.ParlayInactive(offerId);
        }
        if (block.timestamp > offer.fillDeadline) {
            revert Errors.ParlayExpired(offerId);
        }
    }

    function _requireActiveRequest(uint256 requestId, LibParlay.ParlayRequest storage request) internal view {
        if (!request.active || request.remainingUnits == 0) {
            revert Errors.ParlayInactive(requestId);
        }
        if (block.timestamp > request.fillDeadline) {
            revert Errors.ParlayExpired(requestId);
        }
    }

    function _decreaseRemainingUnits(uint256 id, uint128 units, uint128 remainingUnits) internal pure {
        if (units == 0) {
            revert Errors.InvalidAmount(units);
        }
        if (units > remainingUnits) {
            revert Errors.InsufficientVolume(units, remainingUnits);
        }
        id;
    }

    function _collateralToken() internal view returns (IERC20 collateralToken) {
        address token = LibEveMarket.store().config.collateralToken;
        if (token == address(0)) {
            revert Errors.ZeroAddress();
        }
        collateralToken = IERC20(token);
    }

    function _storedParlayCollateralToken(address token) internal view returns (IERC20 collateralToken) {
        if (token == address(0)) {
            return _collateralToken();
        }
        collateralToken = IERC20(token);
    }

    function _defaultParlayCollateral() internal view returns (ParlayCollateralContext memory context) {
        LibParlay.Config storage config = _requireConfig();
        address token = LibEveMarket.store().config.collateralToken;
        if (token == address(0)) {
            revert Errors.ZeroAddress();
        }

        context = ParlayCollateralContext({
            profileId: 0,
            collateralToken: token,
            payoutUnit: DEFAULT_COLLATERAL_PAYOUT_UNIT,
            underwritingFee: config.underwritingFee
        });
    }

    function _parlayCollateralFor(uint8 collateralProfileId)
        internal
        view
        returns (ParlayCollateralContext memory context)
    {
        if (collateralProfileId == 0) {
            return _defaultParlayCollateral();
        }

        LibEveMarket.EveMarketStorage storage marketState = LibEveMarket.store();
        LibEveMarket.CollateralProfile storage profile =
            LibCollateralProfile.requireEnabled(marketState, collateralProfileId);

        context = ParlayCollateralContext({
            profileId: collateralProfileId,
            collateralToken: profile.collateralToken,
            payoutUnit: profile.payoutUnit,
            underwritingFee: marketState.parlayUnderwritingFeeByProfile[collateralProfileId]
        });
    }

    function _enforceParlayTicketToken(address ticketToken) internal view {
        if (ticketToken == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (ticketToken.code.length == 0) {
            revert Errors.ContractHasNoCode(ticketToken);
        }
        try IParlayTicketToken(ticketToken).diamond() returns (address diamond) {
            if (diamond != address(this)) {
                revert Errors.InvalidContractInterface(ticketToken, IParlayTicketToken.diamond.selector);
            }
        } catch {
            revert Errors.InvalidContractInterface(ticketToken, IParlayTicketToken.diamond.selector);
        }
    }

    function _invalidPolicyLabel(uint8 invalidPolicy) internal pure returns (string memory) {
        if (invalidPolicy == uint8(ParlayTypes.InvalidPolicy.VoidInvalidLegs)) {
            return "VoidInvalidLegs";
        }
        return "InvalidCountsAsMiss";
    }

    function _legsJson(LibParlay.Storage storage state, uint256 templateId, uint8 legCount)
        internal
        view
        returns (string memory json)
    {
        json = "[";
        for (uint256 index = 0; index < legCount; ++index) {
            ParlayTypes.ParlayLeg storage leg = state.templateLegs[templateId][index];
            json = string.concat(
                json,
                index == 0 ? "" : ",",
                '{"market_id":"',
                Strings.toHexString(uint256(leg.marketId), 32),
                '","required_outcome":"',
                leg.requiredOutcome == YES_OUTCOME ? "YES" : "NO",
                '"}'
            );
        }
        json = string.concat(json, "]");
    }

    function _tiersJson(LibParlay.Storage storage state, uint256 templateId, uint8 tierCount)
        internal
        view
        returns (string memory json)
    {
        json = "[";
        for (uint256 index = 0; index < tierCount; ++index) {
            ParlayTypes.PayoutTier storage tier = state.templatePayoutTiers[templateId][index];
            json = string.concat(
                json,
                index == 0 ? "" : ",",
                '{"min_hits":',
                Strings.toString(tier.minHits),
                ',"payout":"',
                Strings.toString(tier.payout),
                '"}'
            );
        }
        json = string.concat(json, "]");
    }
}
