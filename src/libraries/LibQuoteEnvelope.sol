// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IQuoteEnvelopeFacet} from "../interfaces/IQuoteEnvelopeFacet.sol";
import {Errors} from "./Errors.sol";
import {LibBookAccess} from "./LibBookAccess.sol";
import {LibBookPricing} from "./LibBookPricing.sol";
import {LibEveMarket} from "./LibEveMarket.sol";
import {LibMarginAccount} from "./LibMarginAccount.sol";
import {LibMLOScenarioMath} from "./LibMLOScenarioMath.sol";
import {LibMLOScenarioRisk} from "./LibMLOScenarioRisk.sol";
import {LibRiskEngine} from "./LibRiskEngine.sol";
import {MarginTypes} from "../types/MarginTypes.sol";
import {QuoteEnvelopeTypes} from "../types/QuoteEnvelopeTypes.sol";

library LibQuoteEnvelope {
    function createEnvelope(
        LibEveMarket.EveMarketStorage storage state,
        QuoteEnvelopeTypes.CreateQuoteEnvelopeParams calldata params
    ) internal returns (uint256 envelopeId) {
        LibEveMarket.CurveSide side = _validateSide(params.side);
        _validateVolume(params.initialVolume, params.maxVolume);

        LibEveMarket.Book storage book = _requireEnvelopeBook(state, params.bookId);
        _validateEnvelopeExpiry(state, book, params.expiresAt);
        _validateCreatePrices(book, params);
        MarginTypes.MarginBucket storage bucket = state.marginBuckets[params.bucketId];
        if (!bucket.exists) {
            revert IQuoteEnvelopeFacet.QuoteEnvelopeBucketNotFound(params.bucketId);
        }
        if (bucket.operator != msg.sender) {
            revert IQuoteEnvelopeFacet.NotQuoteEnvelopeOperator(msg.sender, bucket.operator);
        }
        if (bucket.kind != MarginTypes.BucketKind.MLO) {
            revert IQuoteEnvelopeFacet.QuoteEnvelopeBucketKindMismatch(params.bucketId, bucket.kind);
        }

        (bytes32 marketId, uint8 outcomeIndex, uint8 outcomeCount) =
            LibMLOScenarioRisk.contextForBook(state, params.bookId);
        bytes32 expectedRiskDomain = LibMarginAccount.riskDomainForMarket(marketId);
        if (bucket.riskDomainId != expectedRiskDomain) {
            revert IQuoteEnvelopeFacet.QuoteEnvelopeRiskDomainMismatch(
                params.bucketId, expectedRiskDomain, bucket.riskDomainId
            );
        }
        LibRiskEngine.accrueConfiguredFunding(state, params.bucketId);
        _enforceBucketCanIncreaseRiskForBook(state, params.bucketId, bucket, params.bookId);

        uint128 reservedRisk = _riskFor(
            state,
            params.bookId,
            side,
            params.initialVolume,
            params.minPrice,
            params.maxPrice,
            outcomeIndex,
            outcomeCount
        );
        // A fully taker-funded ASK can have zero maximum loss after rounding
        // (for example, one atomic share at the full payout price). It remains
        // a valid quote because no maker or Senior capital is at risk.
        if (reservedRisk == 0 && side != LibEveMarket.CurveSide.ASK) {
            revert IQuoteEnvelopeFacet.QuoteEnvelopeRiskIsZero();
        }

        LibMLOScenarioRisk.addOpenReservation(
            state,
            params.bucketId,
            marketId,
            outcomeIndex,
            outcomeCount,
            LibMLOScenarioMath.Side(params.side),
            params.initialVolume,
            side == LibEveMarket.CurveSide.ASK ? params.minPrice : params.maxPrice,
            book.priceDenominator
        );
        LibRiskEngine.enforceScenarioInitialMarginAfter(state, params.bucketId, 0);

        envelopeId = ++state.nextQuoteEnvelopeId;
        state.quoteEnvelopes[envelopeId] = QuoteEnvelopeTypes.StoredQuoteEnvelope({
            operator: msg.sender,
            bucketId: params.bucketId,
            bookId: params.bookId,
            side: params.side,
            maxVolume: params.maxVolume,
            currentVolume: params.initialVolume,
            minPrice: params.minPrice,
            maxPrice: params.maxPrice,
            currentStartPrice: params.initialStartPrice,
            currentEndPrice: params.initialEndPrice,
            reservedRisk: reservedRisk,
            remainingRiskVolume: params.initialVolume,
            marketId: marketId,
            outcomeIndex: outcomeIndex,
            outcomeCount: outcomeCount,
            expiresAt: params.expiresAt,
            generation: 1,
            active: true
        });
        state.operatorQuoteEnvelopeIds[msg.sender].push(envelopeId);
        state.bookQuoteEnvelopeIds[params.bookId].push(envelopeId);

        emit IQuoteEnvelopeFacet.QuoteEnvelopeCreated(
            envelopeId,
            msg.sender,
            params.bucketId,
            params.bookId,
            side,
            params.maxVolume,
            reservedRisk,
            params.expiresAt
        );
    }

    function updateEnvelope(
        LibEveMarket.EveMarketStorage storage state,
        uint256 envelopeId,
        QuoteEnvelopeTypes.QuoteEnvelopeUpdate calldata update
    ) internal returns (uint32 generation) {
        validateUpdate(state, envelopeId, update, false);
        QuoteEnvelopeTypes.StoredQuoteEnvelope storage envelope = state.quoteEnvelopes[envelopeId];
        uint128 previousRiskVolume = envelope.remainingRiskVolume;
        if (update.volume > previousRiskVolume) {
            _enforceBucketCanIncreaseRiskForBook(
                state, envelope.bucketId, state.marginBuckets[envelope.bucketId], envelope.bookId
            );
        }
        if (update.volume != previousRiskVolume) {
            resizeReservation(state, envelopeId, update.volume);
            if (update.volume > previousRiskVolume) {
                LibRiskEngine.enforceScenarioInitialMarginAfter(state, envelope.bucketId, 0);
            }
        }
        generation = applyUpdate(state, envelopeId, update);
    }

    function validateUpdate(
        LibEveMarket.EveMarketStorage storage state,
        uint256 envelopeId,
        QuoteEnvelopeTypes.QuoteEnvelopeUpdate calldata update,
        bool allowZeroVolume
    ) internal view {
        QuoteEnvelopeTypes.StoredQuoteEnvelope storage envelope = _requireEnvelope(state, envelopeId);
        _enforceOperator(envelope);
        _enforceActiveAndFresh(envelopeId, envelope);
        if (update.volume != 0 || !allowZeroVolume) _validateVolume(update.volume, envelope.maxVolume);
        _validatePrices(update.startPrice, envelope.minPrice, envelope.maxPrice);
        _validatePrices(update.endPrice, envelope.minPrice, envelope.maxPrice);
    }

    function applyUpdate(
        LibEveMarket.EveMarketStorage storage state,
        uint256 envelopeId,
        QuoteEnvelopeTypes.QuoteEnvelopeUpdate calldata update
    ) internal returns (uint32 generation) {
        QuoteEnvelopeTypes.StoredQuoteEnvelope storage envelope = state.quoteEnvelopes[envelopeId];
        envelope.currentVolume = update.volume;
        envelope.currentStartPrice = update.startPrice;
        envelope.currentEndPrice = update.endPrice;
        unchecked {
            envelope.generation += 1;
        }

        generation = envelope.generation;
        emit IQuoteEnvelopeFacet.QuoteEnvelopeUpdated(
            envelopeId, update.volume, update.startPrice, update.endPrice, generation
        );
    }

    function resizeReservation(LibEveMarket.EveMarketStorage storage state, uint256 envelopeId, uint128 newRiskVolume)
        internal
        returns (uint128 previousRiskVolume, uint128 newReservedRisk)
    {
        QuoteEnvelopeTypes.StoredQuoteEnvelope storage envelope = state.quoteEnvelopes[envelopeId];
        previousRiskVolume = envelope.remainingRiskVolume;
        if (newRiskVolume == previousRiskVolume) return (previousRiskVolume, envelope.reservedRisk);

        uint256 boundPrice = envelope.side == uint8(LibEveMarket.CurveSide.ASK) ? envelope.minPrice : envelope.maxPrice;
        uint256 denominator = state.books[envelope.bookId].priceDenominator;
        LibMLOScenarioRisk.replaceOpenReservation(
            state,
            envelope.bucketId,
            envelope.marketId,
            envelope.outcomeIndex,
            envelope.outcomeCount,
            LibMLOScenarioMath.Side(envelope.side),
            previousRiskVolume,
            newRiskVolume,
            boundPrice,
            denominator
        );

        envelope.remainingRiskVolume = newRiskVolume;
        newReservedRisk = newRiskVolume == 0
            ? 0
            : uint128(
                LibMLOScenarioRisk.reservationRisk(
                    LibMLOScenarioMath.Side(envelope.side),
                    newRiskVolume,
                    boundPrice,
                    denominator,
                    envelope.outcomeIndex,
                    envelope.outcomeCount
                )
            );
        envelope.reservedRisk = newReservedRisk;
    }

    function requireUnbound(LibEveMarket.EveMarketStorage storage state, uint256 envelopeId) internal view {
        _requireEnvelope(state, envelopeId);
        uint256 boundCurveSlot = state.mloEnvelopeCurveIds[envelopeId];
        if (boundCurveSlot != 0 && state.curves[boundCurveSlot - 1].active) {
            revert Errors.QuoteEnvelopeBoundToAdapterCurve(envelopeId, boundCurveSlot - 1);
        }
    }

    function cancelEnvelope(LibEveMarket.EveMarketStorage storage state, uint256 envelopeId) internal {
        QuoteEnvelopeTypes.StoredQuoteEnvelope storage envelope = _requireEnvelope(state, envelopeId);
        _enforceOperator(envelope);
        _cancelEnvelope(state, envelopeId, envelope);
    }

    function viewEnvelope(LibEveMarket.EveMarketStorage storage state, uint256 envelopeId)
        internal
        view
        returns (QuoteEnvelopeTypes.QuoteEnvelopeView memory view_)
    {
        QuoteEnvelopeTypes.StoredQuoteEnvelope storage envelope = _requireEnvelope(state, envelopeId);
        MarginTypes.MarginBucket storage bucket = state.marginBuckets[envelope.bucketId];
        _copyEnvelopeViewBase(view_, envelopeId, envelope, bucket);
        _copyEnvelopeViewPricing(view_, envelope);
        view_.canUpdate = _canUpdate(state, envelopeId, envelope);
    }

    function _copyEnvelopeViewBase(
        QuoteEnvelopeTypes.QuoteEnvelopeView memory view_,
        uint256 envelopeId,
        QuoteEnvelopeTypes.StoredQuoteEnvelope storage envelope,
        MarginTypes.MarginBucket storage bucket
    ) private view {
        view_.envelopeId = envelopeId;
        view_.operator = envelope.operator;
        view_.bucketId = envelope.bucketId;
        view_.bookId = envelope.bookId;
        view_.riskDomainId = bucket.riskDomainId;
        view_.side = envelope.side;
        view_.bucketState = bucket.state;
        view_.expiresAt = envelope.expiresAt;
        view_.generation = envelope.generation;
        view_.active = envelope.active;
    }

    function _copyEnvelopeViewPricing(
        QuoteEnvelopeTypes.QuoteEnvelopeView memory view_,
        QuoteEnvelopeTypes.StoredQuoteEnvelope storage envelope
    ) private view {
        view_.maxVolume = envelope.maxVolume;
        view_.currentVolume = envelope.currentVolume;
        view_.minPrice = envelope.minPrice;
        view_.maxPrice = envelope.maxPrice;
        view_.currentStartPrice = envelope.currentStartPrice;
        view_.currentEndPrice = envelope.currentEndPrice;
        view_.reservedRisk = envelope.reservedRisk;
        view_.remainingRiskVolume = envelope.remainingRiskVolume;
        view_.marketId = envelope.marketId;
        view_.outcomeIndex = envelope.outcomeIndex;
        view_.outcomeCount = envelope.outcomeCount;
    }

    function previewRisk(
        LibEveMarket.EveMarketStorage storage state,
        QuoteEnvelopeTypes.CreateQuoteEnvelopeParams calldata params
    ) internal view returns (uint256 reservedRisk) {
        LibEveMarket.CurveSide side = _validateSide(params.side);
        _validateVolume(params.initialVolume, params.maxVolume);
        LibEveMarket.Book storage book = _requireEnvelopeBook(state, params.bookId);
        _validateEnvelopeExpiry(state, book, params.expiresAt);
        _validateCreatePrices(book, params);
        (, uint8 outcomeIndex, uint8 outcomeCount) = LibMLOScenarioRisk.contextForBook(state, params.bookId);
        reservedRisk = _riskFor(
            state,
            params.bookId,
            side,
            params.initialVolume,
            params.minPrice,
            params.maxPrice,
            outcomeIndex,
            outcomeCount
        );
    }

    function canUpdate(LibEveMarket.EveMarketStorage storage state, uint256 envelopeId) internal view returns (bool) {
        QuoteEnvelopeTypes.StoredQuoteEnvelope storage envelope = state.quoteEnvelopes[envelopeId];
        if (envelope.operator == address(0)) {
            return false;
        }
        return _canUpdate(state, envelopeId, envelope);
    }

    function _cancelEnvelope(
        LibEveMarket.EveMarketStorage storage state,
        uint256 envelopeId,
        QuoteEnvelopeTypes.StoredQuoteEnvelope storage envelope
    ) private {
        uint256 boundCurveSlot = state.mloEnvelopeCurveIds[envelopeId];
        if (boundCurveSlot != 0 && state.curves[boundCurveSlot - 1].active) {
            revert Errors.QuoteEnvelopeBoundToAdapterCurve(envelopeId, boundCurveSlot - 1);
        }
        _enforceActive(envelopeId, envelope);
        uint128 releasedRisk = envelope.reservedRisk;
        envelope.active = false;
        envelope.currentVolume = 0;
        envelope.reservedRisk = 0;
        uint128 remainingRiskVolume = envelope.remainingRiskVolume;
        envelope.remainingRiskVolume = 0;
        unchecked {
            envelope.generation += 1;
        }
        if (remainingRiskVolume != 0) {
            LibMLOScenarioRisk.removeOpenReservation(
                state,
                envelope.bucketId,
                envelope.marketId,
                envelope.outcomeIndex,
                envelope.outcomeCount,
                LibMLOScenarioMath.Side(envelope.side),
                remainingRiskVolume,
                envelope.side == uint8(LibEveMarket.CurveSide.ASK) ? envelope.minPrice : envelope.maxPrice,
                state.books[envelope.bookId].priceDenominator
            );
        }

        emit IQuoteEnvelopeFacet.QuoteEnvelopeCancelled(envelopeId, releasedRisk, envelope.generation);
    }

    function _riskFor(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bookId,
        LibEveMarket.CurveSide side,
        uint128 maxVolume,
        uint128 minPrice,
        uint128 maxPrice,
        uint8 outcomeIndex,
        uint8 outcomeCount
    ) private view returns (uint128 reservedRisk) {
        LibEveMarket.Book storage book = state.books[bookId];
        LibMLOScenarioMath.Side scenarioSide = LibMLOScenarioMath.Side(uint8(side));
        uint256 boundPrice = side == LibEveMarket.CurveSide.BID ? maxPrice : minPrice;
        reservedRisk = uint128(
            LibMLOScenarioRisk.reservationRisk(
                scenarioSide, maxVolume, boundPrice, book.priceDenominator, outcomeIndex, outcomeCount
            )
        );
    }

    function _requireEnvelopeBook(LibEveMarket.EveMarketStorage storage state, bytes32 bookId)
        private
        view
        returns (LibEveMarket.Book storage book)
    {
        book = LibBookAccess.requireExecutableBook(state, bookId);
        if (
            book.marketId == bytes32(0) || book.assetType != LibEveMarket.BookAssetType.ERC1155
                || book.pricingMode != LibEveMarket.BookPricingMode.PREDICTION_PAYOUT
        ) {
            revert IQuoteEnvelopeFacet.UnsupportedQuoteEnvelopeBook(bookId);
        }
    }

    function _validateCreatePrices(
        LibEveMarket.Book storage book,
        QuoteEnvelopeTypes.CreateQuoteEnvelopeParams calldata params
    ) private view {
        _validatePriceBounds(params.minPrice, params.maxPrice);
        LibBookPricing.validateTick(book, params.minPrice);
        LibBookPricing.validateTick(book, params.maxPrice);
        _validatePrices(params.initialStartPrice, params.minPrice, params.maxPrice);
        _validatePrices(params.initialEndPrice, params.minPrice, params.maxPrice);
    }

    function _validateEnvelopeExpiry(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.Book storage book,
        uint64 expiresAt
    ) private view {
        if (expiresAt <= block.timestamp) {
            revert IQuoteEnvelopeFacet.QuoteEnvelopeExpired(0, expiresAt);
        }

        LibEveMarket.Market storage market = state.markets[book.marketId];
        uint64 maximumExpiry = book.expiryTime < market.expiryTime ? book.expiryTime : market.expiryTime;
        if (expiresAt > maximumExpiry) {
            revert Errors.ExpiryTooLate(expiresAt, maximumExpiry);
        }
    }

    function _requireEnvelope(LibEveMarket.EveMarketStorage storage state, uint256 envelopeId)
        private
        view
        returns (QuoteEnvelopeTypes.StoredQuoteEnvelope storage envelope)
    {
        envelope = state.quoteEnvelopes[envelopeId];
        if (envelope.operator == address(0)) {
            revert IQuoteEnvelopeFacet.QuoteEnvelopeNotFound(envelopeId);
        }
    }

    function _canUpdate(
        LibEveMarket.EveMarketStorage storage state,
        uint256 envelopeId,
        QuoteEnvelopeTypes.StoredQuoteEnvelope storage envelope
    ) private view returns (bool) {
        uint256 boundCurveSlot = state.mloEnvelopeCurveIds[envelopeId];
        bool boundToActiveCurve = boundCurveSlot != 0 && state.curves[boundCurveSlot - 1].active;
        return !boundToActiveCurve && envelope.active && block.timestamp < envelope.expiresAt
            && LibMarginAccount.canIncreaseRiskForBook(state, envelope.bucketId, envelope.bookId);
    }

    function _enforceBucketCanIncreaseRiskForBook(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bucketId,
        MarginTypes.MarginBucket storage bucket,
        bytes32 bookId
    ) private view {
        LibRiskEngine.enforceCanIncreaseRiskForBook(state, bucketId, bucket, bookId);
    }

    function _enforceOperator(QuoteEnvelopeTypes.StoredQuoteEnvelope storage envelope) private view {
        if (msg.sender != envelope.operator) {
            revert IQuoteEnvelopeFacet.NotQuoteEnvelopeOperator(msg.sender, envelope.operator);
        }
    }

    function _enforceActiveAndFresh(uint256 envelopeId, QuoteEnvelopeTypes.StoredQuoteEnvelope storage envelope)
        private
        view
    {
        _enforceActive(envelopeId, envelope);
        if (block.timestamp >= envelope.expiresAt) {
            revert IQuoteEnvelopeFacet.QuoteEnvelopeExpired(envelopeId, envelope.expiresAt);
        }
    }

    function _enforceActive(uint256 envelopeId, QuoteEnvelopeTypes.StoredQuoteEnvelope storage envelope) private view {
        if (!envelope.active) {
            revert IQuoteEnvelopeFacet.QuoteEnvelopeInactive(envelopeId);
        }
    }

    function _validateSide(uint8 side) private pure returns (LibEveMarket.CurveSide curveSide) {
        if (side > uint8(LibEveMarket.CurveSide.BID)) {
            revert IQuoteEnvelopeFacet.InvalidQuoteEnvelopeSide(side);
        }
        curveSide = LibEveMarket.CurveSide(side);
    }

    function _validateVolume(uint128 volume, uint128 maxVolume) private pure {
        if (volume == 0 || volume > maxVolume) {
            revert IQuoteEnvelopeFacet.InvalidQuoteEnvelopeVolume(volume, maxVolume);
        }
    }

    function _validatePriceBounds(uint128 minPrice, uint128 maxPrice) private pure {
        if (minPrice == 0 || minPrice > maxPrice) {
            revert IQuoteEnvelopeFacet.InvalidQuoteEnvelopePriceBounds(minPrice, maxPrice);
        }
    }

    function _validatePrices(uint128 price, uint128 minPrice, uint128 maxPrice) private pure {
        if (price < minPrice || price > maxPrice) {
            revert IQuoteEnvelopeFacet.QuoteEnvelopePriceOutOfBounds(price, minPrice, maxPrice);
        }
    }
}
