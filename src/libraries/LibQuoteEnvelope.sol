// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IQuoteEnvelopeFacet} from "../interfaces/IQuoteEnvelopeFacet.sol";
import {Errors} from "./Errors.sol";
import {LibBookAccess} from "./LibBookAccess.sol";
import {LibBookPricing} from "./LibBookPricing.sol";
import {LibEveMarket} from "./LibEveMarket.sol";
import {LibMarginAccount} from "./LibMarginAccount.sol";
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
        if (params.expiresAt <= block.timestamp) {
            revert IQuoteEnvelopeFacet.QuoteEnvelopeExpired(0, params.expiresAt);
        }

        LibEveMarket.Book storage book = _requireEnvelopeBook(state, params.bookId);
        _validateCreatePrices(book, params);
        MarginTypes.MarginBucket storage bucket = state.marginBuckets[params.bucketId];
        if (!bucket.exists) {
            revert IQuoteEnvelopeFacet.QuoteEnvelopeBucketNotFound(params.bucketId);
        }
        if (bucket.operator != msg.sender) {
            revert IQuoteEnvelopeFacet.NotQuoteEnvelopeOperator(msg.sender, bucket.operator);
        }

        bytes32 expectedRiskDomain = LibMarginAccount.riskDomainForMarketBook(book.marketId, params.bookId);
        if (bucket.riskDomainId != expectedRiskDomain) {
            revert IQuoteEnvelopeFacet.QuoteEnvelopeRiskDomainMismatch(
                params.bucketId, expectedRiskDomain, bucket.riskDomainId
            );
        }
        _enforceBucketCanIncreaseRiskForBook(state, params.bucketId, bucket, params.bookId);

        uint128 reservedRisk = _riskFor(state, params.bookId, side, params.maxVolume, params.minPrice, params.maxPrice);
        if (reservedRisk == 0) {
            revert IQuoteEnvelopeFacet.QuoteEnvelopeRiskIsZero();
        }

        LibRiskEngine.increaseOpenOrderRiskForBook(state, params.bucketId, params.bookId, reservedRisk);

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
        QuoteEnvelopeTypes.StoredQuoteEnvelope storage envelope = _requireEnvelope(state, envelopeId);
        _enforceOperator(envelope);
        _enforceActiveAndFresh(envelopeId, envelope);
        _validateVolume(update.volume, envelope.maxVolume);
        _validatePrices(update.startPrice, envelope.minPrice, envelope.maxPrice);
        _validatePrices(update.endPrice, envelope.minPrice, envelope.maxPrice);
        _enforceBucketCanIncreaseRiskForBook(
            state, envelope.bucketId, state.marginBuckets[envelope.bucketId], envelope.bookId
        );

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
        view_ = QuoteEnvelopeTypes.QuoteEnvelopeView({
            envelopeId: envelopeId,
            operator: envelope.operator,
            bucketId: envelope.bucketId,
            bookId: envelope.bookId,
            riskDomainId: bucket.riskDomainId,
            side: envelope.side,
            bucketState: bucket.state,
            maxVolume: envelope.maxVolume,
            currentVolume: envelope.currentVolume,
            minPrice: envelope.minPrice,
            maxPrice: envelope.maxPrice,
            currentStartPrice: envelope.currentStartPrice,
            currentEndPrice: envelope.currentEndPrice,
            reservedRisk: envelope.reservedRisk,
            expiresAt: envelope.expiresAt,
            generation: envelope.generation,
            active: envelope.active,
            canUpdate: _canUpdate(state, envelope)
        });
    }

    function previewRisk(
        LibEveMarket.EveMarketStorage storage state,
        QuoteEnvelopeTypes.CreateQuoteEnvelopeParams calldata params
    ) internal view returns (uint256 reservedRisk) {
        LibEveMarket.CurveSide side = _validateSide(params.side);
        _validateVolume(params.maxVolume, params.maxVolume);
        LibEveMarket.Book storage book = _requireEnvelopeBook(state, params.bookId);
        _validateCreatePrices(book, params);
        reservedRisk = _riskFor(state, params.bookId, side, params.maxVolume, params.minPrice, params.maxPrice);
    }

    function canUpdate(LibEveMarket.EveMarketStorage storage state, uint256 envelopeId) internal view returns (bool) {
        QuoteEnvelopeTypes.StoredQuoteEnvelope storage envelope = state.quoteEnvelopes[envelopeId];
        if (envelope.operator == address(0)) {
            return false;
        }
        return _canUpdate(state, envelope);
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
        unchecked {
            envelope.generation += 1;
        }
        LibRiskEngine.releaseOpenOrderRisk(state, envelope.bucketId, releasedRisk);

        emit IQuoteEnvelopeFacet.QuoteEnvelopeCancelled(envelopeId, releasedRisk, envelope.generation);
    }

    function _riskFor(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bookId,
        LibEveMarket.CurveSide side,
        uint128 maxVolume,
        uint128 minPrice,
        uint128 maxPrice
    ) private view returns (uint128 reservedRisk) {
        LibEveMarket.Book storage book = state.books[bookId];
        if (side == LibEveMarket.CurveSide.BID) {
            return LibBookPricing.grossCostFor(book, maxVolume, maxPrice);
        }

        uint128 complement = book.priceDenominator - minPrice;
        reservedRisk = LibBookPricing.grossCostFor(book, maxVolume, complement);
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
        QuoteEnvelopeTypes.StoredQuoteEnvelope storage envelope
    ) private view returns (bool) {
        return envelope.active && block.timestamp < envelope.expiresAt
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
