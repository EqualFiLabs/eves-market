// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {CurveCLOBTypes} from "../types/CurveCLOBTypes.sol";
import {MLOPredictionTypes} from "../types/MLOPredictionTypes.sol";
import {IMLOPredictionAdapterFacet} from "../interfaces/IMLOPredictionAdapterFacet.sol";
import {Errors} from "./Errors.sol";
import {Events} from "./Events.sol";
import {LibBookAccess} from "./LibBookAccess.sol";
import {LibBookAccounting} from "./LibBookAccounting.sol";
import {LibBookPricing} from "./LibBookPricing.sol";
import {LibCLOBBook} from "./LibCLOBBook.sol";
import {LibCTF} from "./LibCTF.sol";
import {LibCurveEscrow} from "./LibCurveEscrow.sol";
import {LibCurveIndex} from "./LibCurveIndex.sol";
import {LibCurveMath} from "./LibCurveMath.sol";
import {LibEveMarket} from "./LibEveMarket.sol";
import {LibMarkOracle} from "./LibMarkOracle.sol";
import {LibMarketAccess} from "./LibMarketAccess.sol";
import {LibMLORecovery} from "./LibMLORecovery.sol";
import {LibProductAdapter} from "./LibProductAdapter.sol";

library LibBuyExecution {
    using SafeERC20 for IERC20;

    enum FillMode {
        RouteOrder,
        BestAsk
    }

    struct Quote {
        uint128 sharesOut;
        uint128 fee;
        uint128 price;
        uint128 collateralUsed;
    }

    struct RouteTotals {
        uint128 sharesOut;
        uint128 totalCollateralUsed;
        uint128 totalFeePaid;
        uint128 remainingCollateral;
        uint256 filledCurveCount;
    }

    struct RouteRequest {
        bytes32 bookId;
        bytes32 marketId;
        bool isYesSide;
        address payer;
        address taker;
        address receiver;
    }

    function fillCurve(
        uint256 curveId,
        uint128 collateralIn,
        uint128 minSharesOut,
        uint32 expectedGeneration,
        bytes32 expectedCommitment,
        address payer,
        address receiver
    ) internal returns (uint128 sharesOut) {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        Quote memory quote = prepareExecution(state, curveId, collateralIn, expectedGeneration, expectedCommitment);

        if (quote.sharesOut < minSharesOut) {
            revert Errors.SlippageExceeded(quote.sharesOut, minSharesOut);
        }
        if (quote.sharesOut == 0) {
            return 0;
        }

        LibEveMarket.StoredCurve storage curve = state.curves[curveId];
        if (curve.maker == payer) {
            revert Errors.SelfFillNotAllowed(curveId, curve.maker, payer);
        }
        LibEveMarket.Book storage book = state.books[curve.bookId];
        Quote memory executedQuote = executeFill(
            state,
            curveId,
            RouteRequest({
                bookId: curve.bookId,
                marketId: book.marketId,
                isYesSide: curve.isYesSide,
                payer: payer,
                taker: payer,
                receiver: receiver
            }),
            quote
        );
        sharesOut = executedQuote.sharesOut;
    }

    function fillBest(CurveCLOBTypes.FillBestParams memory params, FillMode mode)
        internal
        returns (CurveCLOBTypes.FillBestResult memory result)
    {
        return fillBest(params, mode, params.payer);
    }

    function fillBest(CurveCLOBTypes.FillBestParams memory params, FillMode mode, address taker)
        internal
        returns (CurveCLOBTypes.FillBestResult memory result)
    {
        LibEveMarket.Market storage market = LibMarketAccess.requireTradingMarket(LibEveMarket.store(), params.marketId);
        bytes32 bookId = LibBookAccess.marketSideBookId(market, params.isYesSide);
        result = fillBookBest(
            CurveCLOBTypes.FillBookParams({
                bookId: bookId,
                maxQuoteIn: params.maxCollateralIn,
                minBaseOut: params.minSharesOut,
                maxAveragePrice: params.maxAveragePrice,
                curveIds: params.curveIds,
                expectedGenerations: params.expectedGenerations,
                expectedCommitments: params.expectedCommitments,
                payer: params.payer,
                receiver: params.receiver
            }),
            mode,
            taker
        );
    }

    function fillBookBest(CurveCLOBTypes.FillBookParams memory params, FillMode mode)
        internal
        returns (CurveCLOBTypes.FillBestResult memory result)
    {
        return fillBookBest(params, mode, params.payer);
    }

    function fillBookBest(CurveCLOBTypes.FillBookParams memory params, FillMode mode, address taker)
        internal
        returns (CurveCLOBTypes.FillBestResult memory result)
    {
        if (params.payer == address(0) || params.receiver == address(0)) {
            revert Errors.InvalidAmount(0);
        }
        if (params.curveIds.length != params.expectedGenerations.length) {
            revert Errors.ArrayLengthMismatch(params.curveIds.length, params.expectedGenerations.length);
        }
        if (params.curveIds.length != params.expectedCommitments.length) {
            revert Errors.ArrayLengthMismatch(params.curveIds.length, params.expectedCommitments.length);
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Book storage book = LibBookAccess.requireExecutableBook(state, params.bookId);
        RouteRequest memory request = RouteRequest({
            bookId: params.bookId,
            marketId: book.marketId,
            isYesSide: book.isYesSide,
            payer: params.payer,
            taker: taker,
            receiver: params.receiver
        });
        LibMLORecovery.maintainCurves(state, params.curveIds);

        RouteTotals memory totals;
        totals.remainingCollateral = params.maxQuoteIn;
        if (mode == FillMode.BestAsk) {
            totals = routeBestAskCurves(state, params, request, totals);
        } else {
            totals = routeCurvesInOrder(state, params, request, totals);
        }

        result = finalizeRoute(request, totals, params.minBaseOut, params.maxAveragePrice);
    }

    function previewBookExecution(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bookId,
        uint128 quoteIn,
        uint256[] calldata curveIds
    ) internal view returns (uint128 baseOut, uint128 fee, uint128 averagePrice, uint128 unfilledQuote) {
        LibEveMarket.Book storage book = state.books[bookId];
        if (book.bookId != bookId || !LibCLOBBook.canExecute(book) || !bookAssetIdsMatch(book)) {
            return (0, 0, 0, quoteIn);
        }

        uint128 remainingQuote = quoteIn;
        uint128 totalQuoteUsed;

        for (uint256 index = 0; index < curveIds.length && remainingQuote != 0; ++index) {
            LibEveMarket.StoredCurve storage curve = state.curves[curveIds[index]];
            if (
                curve.bookId != bookId || !curve.active || curve.curveSide != LibEveMarket.CurveSide.ASK
                    || curve.remainingVolume == 0 || LibCurveMath.isExpired(state, curve)
            ) {
                continue;
            }
            if (
                !LibProductAdapter.isEscrowBackedCurve(state, curveIds[index])
                    && !state.adapterCurveMetadata[curveIds[index]].active
            ) continue;

            Quote memory quote = quoteCurve(state, curveIds[index], curve, remainingQuote);
            if (quote.sharesOut == 0) {
                continue;
            }

            baseOut += quote.sharesOut;
            fee += quote.fee;
            totalQuoteUsed += quote.collateralUsed;
            remainingQuote -= quote.collateralUsed;
        }

        if (baseOut != 0) {
            averagePrice = LibBookPricing.averagePrice(book, totalQuoteUsed, baseOut);
        }
        unfilledQuote = quoteIn - totalQuoteUsed;
    }

    function routeCurvesInOrder(
        LibEveMarket.EveMarketStorage storage state,
        CurveCLOBTypes.FillBookParams memory params,
        RouteRequest memory request,
        RouteTotals memory totals
    ) internal returns (RouteTotals memory updatedTotals) {
        for (uint256 index = 0; index < params.curveIds.length && totals.remainingCollateral != 0; ++index) {
            totals = routeSingleCurve(
                state,
                params.curveIds[index],
                params.expectedGenerations[index],
                params.expectedCommitments[index],
                request,
                totals
            );
        }
        updatedTotals = totals;
    }

    function routeBestAskCurves(
        LibEveMarket.EveMarketStorage storage state,
        CurveCLOBTypes.FillBookParams memory params,
        RouteRequest memory request,
        RouteTotals memory totals
    ) internal returns (RouteTotals memory updatedTotals) {
        bool[] memory consumed = new bool[](params.curveIds.length);
        while (totals.remainingCollateral != 0) {
            (uint256 index, bool found) = selectBestAskCurveIndex(state, params, consumed, request.bookId);
            if (!found) {
                break;
            }
            consumed[index] = true;
            totals = routeSingleCurve(
                state,
                params.curveIds[index],
                params.expectedGenerations[index],
                params.expectedCommitments[index],
                request,
                totals
            );
        }
        updatedTotals = totals;
    }

    function selectBestAskCurveIndex(
        LibEveMarket.EveMarketStorage storage state,
        CurveCLOBTypes.FillBookParams memory params,
        bool[] memory consumed,
        bytes32 bookId
    ) internal view returns (uint256 bestIndex, bool found) {
        uint128 bestPrice;
        uint256 bestCurveId;
        for (uint256 index = 0; index < params.curveIds.length; ++index) {
            if (consumed[index]) {
                continue;
            }
            uint256 curveId = params.curveIds[index];
            LibEveMarket.StoredCurve storage curve = state.curves[curveId];
            if (
                curve.bookId != bookId || !curve.active || curve.curveSide != LibEveMarket.CurveSide.ASK
                    || curve.remainingVolume == 0 || LibCurveMath.isExpired(state, curve)
            ) {
                continue;
            }
            if (!LibProductAdapter.isEscrowBackedCurve(state, curveId) && !state.adapterCurveMetadata[curveId].active) {
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

    function prepareExecution(
        LibEveMarket.EveMarketStorage storage state,
        uint256 curveId,
        uint128 collateralIn,
        uint32 expectedGeneration,
        bytes32 expectedCommitment
    ) internal view returns (Quote memory quote) {
        LibEveMarket.StoredCurve storage curve = state.curves[curveId];
        if (!curve.active) {
            revert Errors.CurveNotActive(curveId);
        }
        if (curve.curveSide != LibEveMarket.CurveSide.ASK) {
            revert Errors.InvalidAmount(uint8(curve.curveSide));
        }
        if (expectedGeneration != curve.generation) {
            revert Errors.GenerationMismatch(expectedGeneration, curve.generation);
        }

        bytes32 commitment = LibCurveMath.curveCommitment(curve.packed);
        if (expectedCommitment != commitment) {
            revert Errors.CommitmentMismatch(expectedCommitment, commitment);
        }

        LibEveMarket.Book storage book = LibBookAccess.requireExecutableBook(state, curve.bookId);
        if (!LibCLOBBook.canExecute(book)) {
            revert Errors.MarketNotTrading(book.marketId);
        }
        if (!bookAssetIdsMatch(book)) {
            revert Errors.BookNotActive(curve.bookId);
        }
        if (LibCurveMath.isExpired(state, curve)) {
            revert Errors.CurveExpired(curveId);
        }

        quote = quoteCurve(state, curveId, curve, collateralIn);
    }

    function executeFill(
        LibEveMarket.EveMarketStorage storage state,
        uint256 curveId,
        RouteRequest memory request,
        Quote memory quote
    ) internal returns (Quote memory executedQuote) {
        LibEveMarket.StoredCurve storage curve = state.curves[curveId];
        LibEveMarket.Book storage book = state.books[curve.bookId];
        if (!LibProductAdapter.isEscrowBackedCurve(state, curveId)) {
            MLOPredictionTypes.MLOAskFillResult memory mloResult = IMLOPredictionAdapterFacet(address(this))
                .executeMLOAskFromRoute(
                    MLOPredictionTypes.MLOAskFillRequest({
                        curveId: curveId,
                        collateralIn: quote.collateralUsed,
                        minSharesOut: quote.sharesOut,
                        expectedGeneration: curve.generation,
                        expectedCommitment: LibCurveMath.curveCommitment(curve.packed),
                        fundingSource: request.payer,
                        taker: request.taker,
                        receiver: request.receiver,
                        fundingIsEscrowed: request.payer == address(this)
                    })
                );
            return Quote({
                sharesOut: mloResult.fill.sharesOut,
                fee: mloResult.fill.feePaid,
                price: LibCurveMath.currentPrice(state, curve),
                collateralUsed: mloResult.fill.collateralUsed
            });
        }
        LibProductAdapter.requireEscrowBackedCurve(state, curveId);
        if (
            book.assetType == LibEveMarket.BookAssetType.ERC20
                && book.baseTransferMode == LibEveMarket.BaseTransferMode.BALANCE_DELTA
        ) {
            executedQuote = executeDeltaAskFill(state, curveId, request, quote);
            return executedQuote;
        }
        uint128 grossCost = quote.collateralUsed - quote.fee;
        LibBookAccounting.FeeShares memory fees = LibBookAccounting.feeSharesForBook(state, book, quote.fee);
        IERC20 quoteToken = IERC20(book.quoteToken);

        LibCurveIndex.decreaseAskRemaining(state, curveId, quote.sharesOut);
        LibBookAccounting.recordBookAndMarketFill(
            state, book, curve.maker, quote.price, quote.collateralUsed, quote.fee, fees
        );
        LibMarkOracle.recordFill(state, book, quote.price, quote.sharesOut, grossCost);

        if (quote.collateralUsed != 0 && request.payer != address(this)) {
            LibCurveEscrow.transferExactERC20From(book.quoteToken, request.payer, address(this), quote.collateralUsed);
        }
        if (grossCost != 0) {
            quoteToken.safeTransfer(curve.maker, grossCost);
        }
        LibBookAccounting.payBookQuoteFees(state, book, fees);

        LibCurveEscrow.transferBaseFromEscrow(book, request.receiver, quote.sharesOut);

        emit Events.CurveFilled(
            curveId, curve.maker, request.receiver, quote.collateralUsed, quote.sharesOut, quote.fee
        );

        executedQuote = quote;
    }

    function routeSingleCurve(
        LibEveMarket.EveMarketStorage storage state,
        uint256 curveId,
        uint32 expectedGeneration,
        bytes32 expectedCommitment,
        RouteRequest memory request,
        RouteTotals memory totals
    ) internal returns (RouteTotals memory updatedTotals) {
        Quote memory quote = prepareExecution(
            state, curveId, totals.remainingCollateral, expectedGeneration, expectedCommitment
        );
        LibEveMarket.StoredCurve storage curve = state.curves[curveId];

        if (curve.bookId != request.bookId) {
            revert Errors.CurveBookMismatch(request.bookId, curve.bookId);
        }
        if (
            request.marketId != bytes32(0) && !state.multiOutcomeMarkets[request.marketId].exists
                && curve.isYesSide != request.isYesSide
        ) {
            revert Errors.CurveSideMismatch(request.isYesSide, curve.isYesSide);
        }
        if (curve.maker == request.taker) {
            revert Errors.SelfFillNotAllowed(curveId, curve.maker, request.taker);
        }

        if (quote.sharesOut == 0) {
            return totals;
        }

        Quote memory executedQuote = executeFill(state, curveId, request, quote);

        totals.sharesOut += executedQuote.sharesOut;
        totals.totalCollateralUsed += executedQuote.collateralUsed;
        totals.totalFeePaid += executedQuote.fee;
        totals.remainingCollateral -= executedQuote.collateralUsed;
        totals.filledCurveCount += 1;

        updatedTotals = totals;
    }

    function executeDeltaAskFill(
        LibEveMarket.EveMarketStorage storage state,
        uint256 curveId,
        RouteRequest memory request,
        Quote memory quote
    ) internal returns (Quote memory executedQuote) {
        LibEveMarket.StoredCurve storage curve = state.curves[curveId];
        LibEveMarket.Book storage book = state.books[curve.bookId];
        IERC20 quoteToken = IERC20(book.quoteToken);

        if (quote.collateralUsed != 0 && request.payer != address(this)) {
            LibCurveEscrow.transferExactERC20From(book.quoteToken, request.payer, address(this), quote.collateralUsed);
        }

        LibCurveIndex.decreaseAskRemaining(state, curveId, quote.sharesOut);
        uint128 actualBaseOut = LibCurveEscrow.transferBaseFromEscrow(book, request.receiver, quote.sharesOut);
        uint128 grossCost = LibBookPricing.grossCostFor(book, actualBaseOut, quote.price);
        uint128 fee = LibCurveMath.feeFor(grossCost, book.feeConfig.entryFeeBps);
        uint128 collateralUsed = grossCost + fee;
        if (collateralUsed > quote.collateralUsed) {
            revert Errors.BaseTransferDeltaMismatch(book.baseToken, quote.sharesOut, actualBaseOut);
        }

        LibBookAccounting.FeeShares memory fees = LibBookAccounting.feeSharesForBook(state, book, fee);
        LibBookAccounting.recordBookAndMarketFill(state, book, curve.maker, quote.price, collateralUsed, fee, fees);
        LibMarkOracle.recordFill(state, book, quote.price, actualBaseOut, grossCost);

        if (grossCost != 0) {
            quoteToken.safeTransfer(curve.maker, grossCost);
        }
        LibBookAccounting.payBookQuoteFees(state, book, fees);
        if (request.payer != address(this) && quote.collateralUsed > collateralUsed) {
            quoteToken.safeTransfer(request.payer, quote.collateralUsed - collateralUsed);
        }

        executedQuote = Quote({sharesOut: actualBaseOut, fee: fee, price: quote.price, collateralUsed: collateralUsed});
        emit Events.CurveFilled(curveId, curve.maker, request.receiver, collateralUsed, actualBaseOut, fee);
    }

    function finalizeRoute(
        RouteRequest memory request,
        RouteTotals memory totals,
        uint128 minSharesOut,
        uint128 maxAveragePrice
    ) internal returns (CurveCLOBTypes.FillBestResult memory result) {
        if (totals.sharesOut < minSharesOut) {
            revert Errors.SlippageExceeded(totals.sharesOut, minSharesOut);
        }
        uint128 averagePrice;
        if (totals.sharesOut != 0) {
            averagePrice = LibBookPricing.averagePrice(
                LibEveMarket.store().books[request.bookId], totals.totalCollateralUsed, totals.sharesOut
            );
        }
        if (averagePrice > maxAveragePrice) {
            revert Errors.AveragePriceExceeded(averagePrice, maxAveragePrice);
        }

        emit Events.TradeRouted(
            request.marketId,
            request.receiver,
            request.isYesSide,
            totals.totalCollateralUsed,
            totals.sharesOut,
            averagePrice,
            totals.filledCurveCount
        );

        result = CurveCLOBTypes.FillBestResult({
            sharesOut: totals.sharesOut,
            collateralUsed: totals.totalCollateralUsed,
            feePaid: totals.totalFeePaid,
            averagePrice: averagePrice,
            unfilledCollateral: totals.remainingCollateral
        });
    }

    function quoteCurve(
        LibEveMarket.EveMarketStorage storage state,
        uint256 curveId,
        LibEveMarket.StoredCurve storage curve,
        uint128 collateralIn
    ) internal view returns (Quote memory quote) {
        (quote.sharesOut, quote.fee, quote.price, quote.collateralUsed) =
            LibCurveMath.quoteAsk(state, curve, collateralIn);
        if (quote.sharesOut != 0 && !LibProductAdapter.isEscrowBackedCurve(state, curveId)) {
            LibEveMarket.Book storage book = state.books[curve.bookId];
            uint128 grossCost = LibBookPricing.grossCostForUp(book, quote.sharesOut, quote.price);
            quote.fee = LibCurveMath.feeFor(grossCost, book.feeConfig.entryFeeBps);
            quote.collateralUsed = grossCost + quote.fee;
        }
    }

    function bookAssetIdsMatch(LibEveMarket.Book storage book) internal view returns (bool) {
        if (book.assetType != LibEveMarket.BookAssetType.ERC1155 || book.marketId == bytes32(0)) {
            return true;
        }

        LibEveMarket.Market storage market = LibEveMarket.store().markets[book.marketId];
        if (market.marketId == bytes32(0) || market.positionTokenType != LibEveMarket.PositionTokenType.CTF) {
            return true;
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.MultiOutcomeMarket storage multi = state.multiOutcomeMarkets[book.marketId];
        if (multi.exists) {
            LibEveMarket.PositionMetadata storage metadata = state.positionMetadata[book.baseToken][book.baseTokenId];
            return book.baseToken == market.positionToken && metadata.exists && metadata.marketId == book.marketId
                && metadata.outcome < multi.outcomeCount
                && state.multiOutcomePositionIds[book.marketId][metadata.outcome] == book.baseTokenId
                && state.multiOutcomeBookIds[book.marketId][metadata.outcome] == book.bookId;
        }

        (uint256 yesPositionId, uint256 noPositionId) =
            LibCTF.derivePositionIds(market.positionToken, market.collateralToken, market.conditionId);
        uint256 expected = book.isYesSide ? yesPositionId : noPositionId;
        return expected == book.baseTokenId;
    }
}
