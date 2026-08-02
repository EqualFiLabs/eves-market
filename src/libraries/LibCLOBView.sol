// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {CurveCLOBTypes} from "../types/CurveCLOBTypes.sol";
import {LibBookPricing} from "./LibBookPricing.sol";
import {LibCLOBBook} from "./LibCLOBBook.sol";
import {LibCTF} from "./LibCTF.sol";
import {LibCurveMath} from "./LibCurveMath.sol";
import {LibCurvePacking} from "./LibCurvePacking.sol";
import {LibEveMarket} from "./LibEveMarket.sol";
import {LibProductAdapter} from "./LibProductAdapter.sol";
import {ProductAdapterTypes} from "../types/ProductAdapterTypes.sol";

library LibCLOBView {
    enum PreviewRouteMode {
        InputOrder,
        BestAsk
    }

    struct Quote {
        uint128 baseOut;
        uint128 fee;
        uint128 price;
        uint128 quoteUsed;
    }

    struct PreviewTotals {
        uint128 baseOut;
        uint128 quoteUsed;
        uint128 fee;
    }

    function curveInfo(LibEveMarket.EveMarketStorage storage state, uint256 curveId)
        internal
        view
        returns (CurveCLOBTypes.CurveInfo memory info)
    {
        LibEveMarket.StoredCurve storage curve = state.curves[curveId];
        if (curve.bookId == bytes32(0)) {
            return info;
        }

        LibEveMarket.Book storage book = state.books[curve.bookId];
        LibCurvePacking.CurveParams memory params = LibCurvePacking.unpack(curve.packed);
        ProductAdapterTypes.AdapterCurveMetadata memory adapterMetadata =
            LibProductAdapter.adapterCurveMetadata(state, curveId);

        info = CurveCLOBTypes.CurveInfo({
            curveId: curveId,
            bookId: curve.bookId,
            marketId: book.marketId,
            maker: curve.maker,
            isYesSide: curve.isYesSide,
            curveSide: curve.curveSide,
            assetType: book.assetType,
            baseToken: book.baseToken,
            baseTokenId: book.baseTokenId,
            quoteToken: book.quoteToken,
            active: curve.active,
            currentPrice: LibCurveMath.currentPrice(state, curve),
            remainingVolume: curve.remainingVolume,
            quoteEscrowRemaining: curve.quoteEscrowRemaining,
            startPrice: params.startPrice,
            endPrice: params.endPrice,
            durationMinutes: params.durationMinutes,
            profileId: params.profileId,
            tickPresetId: params.tickPresetId,
            packed: curve.packed,
            createdAt: curve.createdAt,
            expiresAt: LibCurveMath.expiresAt(state, curve, params.durationMinutes),
            generation: curve.generation,
            backingKind: adapterMetadata.backingKind,
            adapterKind: adapterMetadata.adapterKind,
            adapterBucketId: adapterMetadata.bucketId,
            adapterRiskDomainId: adapterMetadata.riskDomainId,
            adapterDataKey: adapterMetadata.adapterDataKey,
            adapterActive: adapterMetadata.active
        });
    }

    function curveCommitment(LibEveMarket.EveMarketStorage storage state, uint256 curveId)
        internal
        view
        returns (uint32 generation, bytes32 commitment)
    {
        LibEveMarket.StoredCurve storage curve = state.curves[curveId];
        generation = curve.generation;
        commitment = curve.bookId == bytes32(0) ? bytes32(0) : LibCurveMath.curveCommitment(curve.packed);
    }

    function previewCurveQuote(LibEveMarket.EveMarketStorage storage state, uint256 curveId, uint128 quoteIn)
        internal
        view
        returns (uint128 baseOut, uint128 fee, uint128 price, uint128 makerTopUp)
    {
        LibEveMarket.StoredCurve storage curve = state.curves[curveId];
        if (curve.bookId == bytes32(0) || !curve.active || curve.curveSide != LibEveMarket.CurveSide.ASK) {
            return (0, 0, 0, 0);
        }

        price = LibCurveMath.currentPrice(state, curve);

        LibEveMarket.Book storage book = state.books[curve.bookId];
        if (LibCurveMath.isExpired(state, curve) || !LibCLOBBook.canExecute(book) || !bookAssetIdsMatch(state, book)) {
            return (0, 0, price, 0);
        }

        Quote memory quote = _quoteAsk(state, curve, quoteIn);
        return (quote.baseOut, quote.fee, quote.price, makerTopUp);
    }

    function previewMarketExecution(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 marketId,
        bool isYesSide,
        uint128 quoteIn,
        uint256[] calldata curveIds
    ) internal view returns (uint128 baseOut, uint128 fee, uint128 averagePrice, uint128 unfilledQuote) {
        LibEveMarket.Market storage market = state.markets[marketId];
        bytes32 bookId = isYesSide ? market.yesBookId : market.noBookId;
        if (market.marketId != marketId || bookId == bytes32(0)) {
            return (0, 0, 0, quoteIn);
        }

        return previewBookExecution(state, bookId, quoteIn, curveIds, PreviewRouteMode.InputOrder);
    }

    function previewBookExecution(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bookId,
        uint128 quoteIn,
        uint256[] calldata curveIds,
        PreviewRouteMode mode
    ) internal view returns (uint128 baseOut, uint128 fee, uint128 averagePrice, uint128 unfilledQuote) {
        LibEveMarket.Book storage book = state.books[bookId];
        if (book.bookId != bookId || !LibCLOBBook.canExecute(book) || !bookAssetIdsMatch(state, book)) {
            return (0, 0, 0, quoteIn);
        }

        PreviewTotals memory totals = mode == PreviewRouteMode.BestAsk
            ? _previewBestAskRoute(state, bookId, quoteIn, curveIds)
            : _previewInputOrderRoute(state, bookId, quoteIn, curveIds);

        baseOut = totals.baseOut;
        fee = totals.fee;
        if (totals.baseOut != 0) {
            averagePrice = LibBookPricing.averagePrice(book, totals.quoteUsed, totals.baseOut);
        }
        unfilledQuote = quoteIn - totals.quoteUsed;
    }

    function bookTopOfBook(LibEveMarket.EveMarketStorage storage state, bytes32 bookId)
        internal
        view
        returns (uint128 bestAskPrice, uint128 bestBidPrice, uint128 midpointPrice, uint128 lastTradePrice)
    {
        LibEveMarket.Book storage book = state.books[bookId];
        if (book.bookId != bookId) {
            return (0, 0, 0, 0);
        }

        bool hasAsk;
        bool hasBid;
        uint256[] storage curveIds = state.bookCurveIds[bookId];
        for (uint256 index = 0; index < curveIds.length; ++index) {
            LibEveMarket.StoredCurve storage curve = state.curves[curveIds[index]];
            if (
                !curve.active || curve.remainingVolume == 0 || LibCurveMath.isExpired(state, curve)
                    || !LibCLOBBook.canExecute(book)
            ) {
                continue;
            }

            uint128 price = LibCurveMath.currentPrice(state, curve);
            if (curve.curveSide == LibEveMarket.CurveSide.ASK) {
                if (!hasAsk || price < bestAskPrice) {
                    bestAskPrice = price;
                    hasAsk = true;
                }
            } else if (!hasBid || price > bestBidPrice) {
                bestBidPrice = price;
                hasBid = true;
            }
        }

        lastTradePrice = uint128(book.lastTradePrice);
        if (hasAsk && hasBid) {
            midpointPrice = uint128((uint256(bestAskPrice) + uint256(bestBidPrice)) / 2);
        }
    }

    function marketTopOfBook(LibEveMarket.EveMarketStorage storage state, bytes32 marketId)
        internal
        view
        returns (
            uint128 bestYesPrice,
            uint128 bestNoPrice,
            uint128 midpointPrice,
            uint128 lastTradePrice,
            uint128 displayPrice
        )
    {
        LibEveMarket.Market storage market = state.markets[marketId];
        if (market.marketId != marketId) {
            return (0, 0, 0, 0, 0);
        }

        bool hasYes;
        bool hasNo;
        (bestYesPrice, hasYes) = _bestAskPrice(state, market.yesBookId);
        (bestNoPrice, hasNo) = _bestAskPrice(state, market.noBookId);
        lastTradePrice = uint128(market.lastTradePrice);

        LibEveMarket.Book storage noBook = state.books[market.noBookId];
        if (hasYes && hasNo) {
            uint128 noDisplayPrice = LibBookPricing.complementPrice(noBook, bestNoPrice);
            midpointPrice = uint128((uint256(bestYesPrice) + uint256(noDisplayPrice)) / 2);
            displayPrice = midpointPrice;
        } else if (hasYes) {
            displayPrice = bestYesPrice;
        } else if (hasNo) {
            displayPrice = LibBookPricing.complementPrice(noBook, bestNoPrice);
        } else {
            displayPrice = lastTradePrice;
        }
    }

    function bookAssetIdsMatch(LibEveMarket.EveMarketStorage storage state, LibEveMarket.Book storage book)
        internal
        view
        returns (bool)
    {
        if (book.assetType != LibEveMarket.BookAssetType.ERC1155 || book.marketId == bytes32(0)) {
            return true;
        }

        LibEveMarket.Market storage market = state.markets[book.marketId];
        if (market.marketId == bytes32(0) || market.positionTokenType != LibEveMarket.PositionTokenType.CTF) {
            return true;
        }

        (uint256 yesPositionId, uint256 noPositionId) =
            LibCTF.derivePositionIds(market.positionToken, market.collateralToken, market.conditionId);
        uint256 expected = book.isYesSide ? yesPositionId : noPositionId;
        return expected == book.baseTokenId;
    }

    function _previewInputOrderRoute(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bookId,
        uint128 quoteIn,
        uint256[] calldata curveIds
    ) private view returns (PreviewTotals memory totals) {
        uint128 remainingQuote = quoteIn;
        for (uint256 index = 0; index < curveIds.length && remainingQuote != 0; ++index) {
            LibEveMarket.StoredCurve storage curve = state.curves[curveIds[index]];
            if (!_isPreviewableAsk(state, curve, bookId)) {
                continue;
            }

            Quote memory quote = _quoteAsk(state, curve, remainingQuote);
            if (quote.baseOut == 0) {
                continue;
            }

            totals.baseOut += quote.baseOut;
            totals.fee += quote.fee;
            totals.quoteUsed += quote.quoteUsed;
            remainingQuote -= quote.quoteUsed;
        }
    }

    function _previewBestAskRoute(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bookId,
        uint128 quoteIn,
        uint256[] calldata curveIds
    ) private view returns (PreviewTotals memory totals) {
        uint128 remainingQuote = quoteIn;
        bool[] memory consumed = new bool[](curveIds.length);
        while (remainingQuote != 0) {
            (uint256 index, bool found) = _selectBestAskCurveIndex(state, bookId, curveIds, consumed);
            if (!found) {
                break;
            }
            consumed[index] = true;

            Quote memory quote = _quoteAsk(state, state.curves[curveIds[index]], remainingQuote);
            if (quote.baseOut == 0) {
                continue;
            }

            totals.baseOut += quote.baseOut;
            totals.fee += quote.fee;
            totals.quoteUsed += quote.quoteUsed;
            remainingQuote -= quote.quoteUsed;
        }
    }

    function _selectBestAskCurveIndex(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bookId,
        uint256[] calldata curveIds,
        bool[] memory consumed
    ) private view returns (uint256 bestIndex, bool found) {
        uint128 bestPrice;
        uint256 bestCurveId;
        for (uint256 index = 0; index < curveIds.length; ++index) {
            if (consumed[index]) {
                continue;
            }

            uint256 curveId = curveIds[index];
            LibEveMarket.StoredCurve storage curve = state.curves[curveId];
            if (!_isPreviewableAsk(state, curve, bookId)) {
                continue;
            }

            uint128 price = LibCurveMath.currentPrice(state, curve);
            if (!found || price < bestPrice || (price == bestPrice && curveId < bestCurveId)) {
                bestIndex = index;
                bestPrice = price;
                bestCurveId = curveId;
                found = true;
            }
        }
    }

    function _bestAskPrice(LibEveMarket.EveMarketStorage storage state, bytes32 bookId)
        private
        view
        returns (uint128 bestAskPrice, bool found)
    {
        LibEveMarket.Book storage book = state.books[bookId];
        uint256[] storage curveIds = state.bookCurveIds[bookId];
        for (uint256 index = 0; index < curveIds.length; ++index) {
            LibEveMarket.StoredCurve storage curve = state.curves[curveIds[index]];
            if (!_isPreviewableAsk(state, curve, bookId) || !LibCLOBBook.canExecute(book)) {
                continue;
            }

            uint128 price = LibCurveMath.currentPrice(state, curve);
            if (!found || price < bestAskPrice) {
                bestAskPrice = price;
                found = true;
            }
        }
    }

    function _isPreviewableAsk(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.StoredCurve storage curve,
        bytes32 bookId
    ) private view returns (bool) {
        return curve.bookId == bookId && curve.active && curve.curveSide == LibEveMarket.CurveSide.ASK
            && curve.remainingVolume != 0 && !LibCurveMath.isExpired(state, curve);
    }

    function _quoteAsk(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.StoredCurve storage curve,
        uint128 quoteIn
    ) private view returns (Quote memory quote) {
        (quote.baseOut, quote.fee, quote.price, quote.quoteUsed) = LibCurveMath.quoteAsk(state, curve, quoteIn);
    }
}
