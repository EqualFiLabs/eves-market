// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {IGnosisConditionalTokens} from "../interfaces/IGnosisConditionalTokens.sol";
import {ITradeRouter} from "../interfaces/ITradeRouter.sol";
import {CurveCLOBTypes} from "../types/CurveCLOBTypes.sol";
import {Errors} from "./Errors.sol";
import {Events} from "./Events.sol";
import {LibBookAccess} from "./LibBookAccess.sol";
import {LibBookAccounting} from "./LibBookAccounting.sol";
import {LibBookPricing} from "./LibBookPricing.sol";
import {LibCLOBBook} from "./LibCLOBBook.sol";
import {LibCTF} from "./LibCTF.sol";
import {LibCurveEscrow} from "./LibCurveEscrow.sol";
import {LibCurveMath} from "./LibCurveMath.sol";
import {LibCurvePacking} from "./LibCurvePacking.sol";
import {LibEveMarket} from "./LibEveMarket.sol";
import {LibMarketAccess} from "./LibMarketAccess.sol";

library LibSellExecution {
    using SafeERC20 for IERC20;

    uint256 internal constant PRICE_SCALE = LibCurvePacking.PRICE_SCALE;

    enum DirectBidSettlement {
        RetainInDiamond,
        TransferToReceiver
    }

    struct SellRouteTotals {
        uint128 sharesSold;
        uint128 collateralOut;
        uint128 feePaid;
        uint128 remainingShares;
        uint256 filledCurveCount;
    }

    struct SellQuote {
        uint128 sharesOut;
        uint128 grossCost;
        uint128 fee;
        uint128 collateralOut;
        uint128 price;
    }

    function immediateContext(address source, address receiver)
        internal
        pure
        returns (CurveCLOBTypes.SellExecutionContext memory context)
    {
        context = CurveCLOBTypes.SellExecutionContext({
            source: source, seller: source, receiver: receiver, useEscrowedBase: false
        });
    }

    function sellBookBest(
        CurveCLOBTypes.SellBookParams memory params,
        CurveCLOBTypes.SellExecutionContext memory context
    ) internal returns (CurveCLOBTypes.SellBookResult memory result) {
        if (params.maxBaseIn == 0) {
            revert Errors.InvalidAmount(0);
        }
        if (context.source == address(0) || context.seller == address(0) || context.receiver == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (params.curveIds.length != params.expectedGenerations.length) {
            revert Errors.ArrayLengthMismatch(params.curveIds.length, params.expectedGenerations.length);
        }
        if (params.curveIds.length != params.expectedCommitments.length) {
            revert Errors.ArrayLengthMismatch(params.curveIds.length, params.expectedCommitments.length);
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Book storage book = LibBookAccess.requireExecutableBook(state, params.bookId);
        if (!LibCLOBBook.canExecute(book)) {
            revert Errors.MarketNotTrading(book.marketId);
        }

        uint128 remainingBase = params.maxBaseIn;
        uint256 filledCurveCount;
        bool[] memory consumed = new bool[](params.curveIds.length);
        while (remainingBase != 0) {
            (uint256 index, bool found) = selectBestBidCurveIndex(state, params.bookId, params.curveIds, consumed);
            if (!found) {
                break;
            }
            consumed[index] = true;
            SellQuote memory executedQuote = executeSelectedBidRoute(
                state, book, params, context, index, remainingBase, DirectBidSettlement.TransferToReceiver
            );
            if (executedQuote.sharesOut == 0) {
                continue;
            }
            result.baseSold += executedQuote.sharesOut;
            result.quoteOut += executedQuote.collateralOut;
            result.feePaid += executedQuote.fee;
            remainingBase -= executedQuote.sharesOut;
            filledCurveCount += 1;
        }

        if (result.quoteOut < params.minQuoteOut) {
            revert Errors.SlippageExceeded(result.quoteOut, params.minQuoteOut);
        }
        if (result.baseSold != 0) {
            result.averagePrice = LibBookPricing.averagePrice(book, result.quoteOut, result.baseSold);
        }
        result.unfilledBase = remainingBase;

        emit Events.TradeRouted(
            book.marketId,
            context.seller,
            book.isYesSide,
            result.quoteOut,
            result.baseSold,
            result.averagePrice,
            filledCurveCount
        );
    }

    function previewSellBest(ITradeRouter.SellBestParams memory params)
        internal
        view
        returns (ITradeRouter.SellBestResult memory result)
    {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Market storage market = LibMarketAccess.requireTradingMarket(state, params.marketId);
        validatePositionIdsIfCTF(market);

        SellRouteTotals memory totals;
        totals.remainingShares = params.maxSharesIn;

        for (uint256 index = 0; index < params.curveIds.length && totals.remainingShares != 0; ++index) {
            totals = previewSingleSellCurve(
                state,
                params,
                params.curveIds[index],
                params.expectedGenerations[index],
                params.expectedCommitments[index],
                totals
            );
        }

        uint128 averagePrice;
        if (totals.sharesSold != 0) {
            averagePrice = uint128((uint256(totals.collateralOut) * PRICE_SCALE) / uint256(totals.sharesSold));
        }

        result = ITradeRouter.SellBestResult({
            sharesSold: totals.sharesSold,
            collateralOut: totals.collateralOut,
            feePaid: totals.feePaid,
            averagePrice: averagePrice,
            unfilledShares: totals.remainingShares
        });
    }

    function sellBest(ITradeRouter.SellBestParams memory params, CurveCLOBTypes.SellExecutionContext memory context)
        internal
        returns (ITradeRouter.SellBestResult memory result)
    {
        if (context.source == address(0) || context.seller == address(0) || context.receiver == address(0)) {
            revert ITradeRouter.ZeroAddress();
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Market storage market = LibMarketAccess.requireTradingMarket(state, params.marketId);
        validatePositionIdsIfCTF(market);

        SellRouteTotals memory totals;
        totals.remainingShares = params.maxSharesIn;

        for (uint256 index = 0; index < params.curveIds.length && totals.remainingShares != 0; ++index) {
            totals = routeSingleSellCurve(
                state,
                params,
                params.curveIds[index],
                params.expectedGenerations[index],
                params.expectedCommitments[index],
                context,
                totals
            );
        }

        if (totals.collateralOut < params.minCollateralOut) {
            revert Errors.SlippageExceeded(totals.collateralOut, params.minCollateralOut);
        }

        uint128 averagePrice;
        if (totals.sharesSold != 0) {
            averagePrice = uint128((uint256(totals.collateralOut) * PRICE_SCALE) / uint256(totals.sharesSold));
        }

        emit Events.TradeRouted(
            params.marketId,
            context.seller,
            params.isYesSide,
            totals.collateralOut,
            totals.sharesSold,
            averagePrice,
            totals.filledCurveCount
        );

        result = ITradeRouter.SellBestResult({
            sharesSold: totals.sharesSold,
            collateralOut: totals.collateralOut,
            feePaid: totals.feePaid,
            averagePrice: averagePrice,
            unfilledShares: totals.remainingShares
        });
    }

    function previewSingleSellCurve(
        LibEveMarket.EveMarketStorage storage state,
        ITradeRouter.SellBestParams memory params,
        uint256 curveId,
        uint32 expectedGeneration,
        bytes32 expectedCommitment,
        SellRouteTotals memory totals
    ) internal view returns (SellRouteTotals memory updatedTotals) {
        LibEveMarket.StoredCurve storage curve = state.curves[curveId];
        LibEveMarket.Book storage book = state.books[curve.bookId];

        validateSellCurve(
            state, curveId, curve, params.marketId, params.isYesSide, expectedGeneration, expectedCommitment
        );

        SellQuote memory quote = curve.curveSide == LibEveMarket.CurveSide.BID
            ? quoteDirectBidCurve(state, book, curve, totals.remainingShares)
            : quoteComplementSellCurve(state, curve, totals.remainingShares);
        if (quote.sharesOut == 0) {
            return totals;
        }

        totals.sharesSold += quote.sharesOut;
        totals.collateralOut += quote.collateralOut;
        totals.feePaid += quote.fee;
        totals.remainingShares -= quote.sharesOut;
        totals.filledCurveCount += 1;
        updatedTotals = totals;
    }

    function routeSingleSellCurve(
        LibEveMarket.EveMarketStorage storage state,
        ITradeRouter.SellBestParams memory params,
        uint256 curveId,
        uint32 expectedGeneration,
        bytes32 expectedCommitment,
        CurveCLOBTypes.SellExecutionContext memory context,
        SellRouteTotals memory totals
    ) internal returns (SellRouteTotals memory updatedTotals) {
        LibEveMarket.StoredCurve storage curve = state.curves[curveId];
        validateSellCurve(
            state, curveId, curve, params.marketId, params.isYesSide, expectedGeneration, expectedCommitment
        );
        if (curve.maker == context.seller) {
            revert Errors.SelfFillNotAllowed(curveId, curve.maker, context.seller);
        }

        SellQuote memory quote = curve.curveSide == LibEveMarket.CurveSide.BID
            ? quoteDirectBidCurve(state, state.books[curve.bookId], curve, totals.remainingShares)
            : quoteComplementSellCurve(state, curve, totals.remainingShares);
        if (quote.sharesOut == 0) {
            return totals;
        }

        if (curve.curveSide == LibEveMarket.CurveSide.BID) {
            executeDirectBidFill(
                state, curveId, curve, state.books[curve.bookId], quote, context, DirectBidSettlement.RetainInDiamond
            );
        } else {
            executeComplementSellFill(
                state,
                IGnosisConditionalTokens(state.markets[params.marketId].positionToken),
                curveId,
                curve,
                state.markets[params.marketId],
                params.isYesSide,
                quote,
                context
            );
        }

        totals.sharesSold += quote.sharesOut;
        totals.collateralOut += quote.collateralOut;
        totals.feePaid += quote.fee;
        totals.remainingShares -= quote.sharesOut;
        totals.filledCurveCount += 1;
        updatedTotals = totals;
    }

    function executeSelectedBidRoute(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.Book storage book,
        CurveCLOBTypes.SellBookParams memory params,
        CurveCLOBTypes.SellExecutionContext memory context,
        uint256 index,
        uint128 remainingBase,
        DirectBidSettlement settlement
    ) internal returns (SellQuote memory executedQuote) {
        uint256 curveId = params.curveIds[index];
        LibEveMarket.StoredCurve storage curve = state.curves[curveId];
        validateBookBidCurve(
            params.bookId, curveId, curve, params.expectedGenerations[index], params.expectedCommitments[index]
        );
        if (curve.maker == context.seller) {
            revert Errors.SelfFillNotAllowed(curveId, curve.maker, context.seller);
        }

        SellQuote memory quote = quoteBookBidCurve(book, curve, remainingBase);
        if (quote.sharesOut == 0) {
            return executedQuote;
        }

        executedQuote = executeDirectBidFill(state, curveId, curve, book, quote, context, settlement);
    }

    function selectBestBidCurveIndex(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bookId,
        uint256[] memory curveIds,
        bool[] memory consumed
    ) internal view returns (uint256 bestIndex, bool found) {
        uint128 bestPrice;
        uint256 bestCurveId;
        for (uint256 index = 0; index < curveIds.length; ++index) {
            if (consumed[index]) {
                continue;
            }
            uint256 curveId = curveIds[index];
            LibEveMarket.StoredCurve storage curve = state.curves[curveId];
            if (
                curve.bookId != bookId || !curve.active || curve.curveSide != LibEveMarket.CurveSide.BID
                    || curve.remainingVolume == 0 || curve.quoteEscrowRemaining == 0
                    || LibCurveMath.isExpired(state, curve)
            ) {
                continue;
            }
            uint128 price = LibCurveMath.currentPrice(state, curve);
            if (!found || price > bestPrice || (price == bestPrice && curveId < bestCurveId)) {
                bestIndex = index;
                bestPrice = price;
                bestCurveId = curveId;
                found = true;
            }
        }
    }

    function validateBookBidCurve(
        bytes32 bookId,
        uint256 curveId,
        LibEveMarket.StoredCurve storage curve,
        uint32 expectedGeneration,
        bytes32 expectedCommitment
    ) internal view {
        if (!curve.active) {
            revert Errors.CurveNotActive(curveId);
        }
        if (curve.curveSide != LibEveMarket.CurveSide.BID) {
            revert Errors.InvalidAmount(uint8(curve.curveSide));
        }
        if (curve.bookId != bookId) {
            revert Errors.CurveBookMismatch(bookId, curve.bookId);
        }
        if (expectedGeneration != curve.generation) {
            revert Errors.GenerationMismatch(expectedGeneration, curve.generation);
        }
        bytes32 commitment = LibCurveMath.curveCommitment(curve.packed);
        if (expectedCommitment != commitment) {
            revert Errors.CommitmentMismatch(expectedCommitment, commitment);
        }
        if (LibCurveMath.isExpired(LibEveMarket.store(), curve)) {
            revert Errors.CurveExpired(curveId);
        }
    }

    function validateSellCurve(
        LibEveMarket.EveMarketStorage storage state,
        uint256 curveId,
        LibEveMarket.StoredCurve storage curve,
        bytes32 marketId,
        bool soldYesSide,
        uint32 expectedGeneration,
        bytes32 expectedCommitment
    ) internal view {
        if (!curve.active) {
            revert Errors.CurveNotActive(curveId);
        }
        if (expectedGeneration != curve.generation) {
            revert Errors.GenerationMismatch(expectedGeneration, curve.generation);
        }
        bytes32 commitment = LibCurveMath.curveCommitment(curve.packed);
        if (expectedCommitment != commitment) {
            revert Errors.CommitmentMismatch(expectedCommitment, commitment);
        }
        LibEveMarket.Book storage book = state.books[curve.bookId];
        if (book.marketId != marketId) {
            revert Errors.CurveMarketMismatch(marketId, book.marketId);
        }

        LibEveMarket.Market storage market = LibMarketAccess.requireTradingMarket(state, book.marketId);
        if (curve.curveSide == LibEveMarket.CurveSide.BID) {
            if (curve.isYesSide != soldYesSide) {
                revert Errors.CurveSideMismatch(soldYesSide, curve.isYesSide);
            }
        } else {
            if (curve.isYesSide == soldYesSide) {
                revert Errors.CurveSideMismatch(!soldYesSide, curve.isYesSide);
            }
            requireCTFPositionMarket(market);
        }

        validatePositionIdsIfCTF(market);
        if (LibCurveMath.isExpired(state, curve)) {
            revert Errors.CurveExpired(curveId);
        }
    }

    function quoteBookBidCurve(LibEveMarket.Book storage book, LibEveMarket.StoredCurve storage curve, uint128 baseIn)
        internal
        view
        returns (SellQuote memory quote)
    {
        (quote.sharesOut, quote.fee, quote.price, quote.grossCost) =
            LibCurveMath.quoteBid(book, LibEveMarket.store(), curve, baseIn);
        if (quote.fee > quote.grossCost) {
            revert ITradeRouter.SellProceedsInsufficient(quote.grossCost, quote.fee);
        }
        quote.collateralOut = quote.grossCost - quote.fee;
    }

    function quoteDirectBidCurve(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.Book storage book,
        LibEveMarket.StoredCurve storage curve,
        uint128 sharesIn
    ) internal view returns (SellQuote memory quote) {
        (quote.sharesOut, quote.fee, quote.price, quote.grossCost) = LibCurveMath.quoteBid(book, state, curve, sharesIn);
        if (quote.fee > quote.grossCost) {
            revert ITradeRouter.SellProceedsInsufficient(quote.grossCost, quote.fee);
        }
        quote.collateralOut = quote.grossCost - quote.fee;
    }

    function quoteComplementSellCurve(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.StoredCurve storage curve,
        uint128 sharesIn
    ) internal view returns (SellQuote memory quote) {
        if (sharesIn == 0 || curve.remainingVolume == 0) {
            return quote;
        }

        quote.sharesOut = sharesIn > curve.remainingVolume ? curve.remainingVolume : sharesIn;
        LibEveMarket.Book storage book = state.books[curve.bookId];
        quote.price = LibCurveMath.currentPrice(state, curve);
        quote.grossCost = LibBookPricing.grossCostFor(book, quote.sharesOut, quote.price);
        quote.fee = LibCurveMath.feeFor(quote.grossCost, book.feeConfig.entryFeeBps);

        uint128 collateralValue = quote.sharesOut;
        uint128 collateralUsed = quote.grossCost + quote.fee;
        if (collateralUsed > collateralValue) {
            revert ITradeRouter.SellProceedsInsufficient(collateralValue, collateralUsed);
        }

        quote.collateralOut = collateralValue - collateralUsed;
    }

    function executeDirectBidFill(
        LibEveMarket.EveMarketStorage storage state,
        uint256 curveId,
        LibEveMarket.StoredCurve storage curve,
        LibEveMarket.Book storage book,
        SellQuote memory quote,
        CurveCLOBTypes.SellExecutionContext memory context,
        DirectBidSettlement settlement
    ) internal returns (SellQuote memory executedQuote) {
        uint128 actualBaseSold = context.useEscrowedBase
            ? LibCurveEscrow.transferBaseFromEscrow(book, curve.maker, quote.sharesOut)
            : LibCurveEscrow.transferBaseFromSeller(book, context.source, curve.maker, quote.sharesOut);
        if (actualBaseSold != quote.sharesOut) {
            uint128 grossCost = LibBookPricing.grossCostFor(book, actualBaseSold, quote.price);
            uint128 fee = LibCurveMath.feeFor(grossCost, book.feeConfig.entryFeeBps);
            if (fee > grossCost) {
                revert ITradeRouter.SellProceedsInsufficient(grossCost, fee);
            }
            quote = SellQuote({
                sharesOut: actualBaseSold,
                grossCost: grossCost,
                fee: fee,
                collateralOut: grossCost - fee,
                price: quote.price
            });
        }

        LibBookAccounting.FeeShares memory fees = LibBookAccounting.feeSharesForBook(state, book, quote.fee);

        curve.remainingVolume -= quote.sharesOut;
        curve.quoteEscrowRemaining -= quote.grossCost;
        LibBookAccounting.recordBookAndMarketFill(
            state, book, curve.maker, quote.price, quote.grossCost, quote.fee, fees
        );

        if (settlement == DirectBidSettlement.TransferToReceiver && quote.collateralOut != 0) {
            IERC20(book.quoteToken).safeTransfer(context.receiver, quote.collateralOut);
        }
        LibBookAccounting.payBookQuoteFees(state, book, fees);

        emit Events.CurveFilled(curveId, curve.maker, context.seller, quote.grossCost, quote.sharesOut, quote.fee);
        executedQuote = quote;
    }

    function executeComplementSellFill(
        LibEveMarket.EveMarketStorage storage state,
        IGnosisConditionalTokens ctf,
        uint256 curveId,
        LibEveMarket.StoredCurve storage curve,
        LibEveMarket.Market storage market,
        bool soldYesSide,
        SellQuote memory quote,
        CurveCLOBTypes.SellExecutionContext memory context
    ) internal {
        IERC20 collateralToken = IERC20(market.collateralToken);
        uint256 soldPositionId = soldYesSide ? market.yesPositionId : market.noPositionId;
        LibEveMarket.Book storage book = state.books[curve.bookId];
        LibBookAccounting.FeeShares memory fees = LibBookAccounting.feeSharesForBook(state, book, quote.fee);

        LibCTF.prepareMarketCondition(market.positionToken, market.resolutionId);
        if (!context.useEscrowedBase) {
            ctf.safeTransferFrom(context.source, address(this), soldPositionId, quote.sharesOut, "");
        }
        LibCTF.mergeCollateral(market.positionToken, market.collateralToken, market.conditionId, quote.sharesOut);

        LibBookAccounting.payBookQuoteFees(state, book, fees);

        if (quote.grossCost != 0) {
            collateralToken.safeTransfer(curve.maker, quote.grossCost);
        }

        uint128 collateralUsed = quote.grossCost + quote.fee;
        curve.remainingVolume -= quote.sharesOut;
        LibBookAccounting.recordMarketOnlyFill(
            market, curve.maker, uint128(PRICE_SCALE - quote.price), collateralUsed, quote.fee, fees
        );
        LibBookAccounting.recordBookOnlyFill(book, curve.maker, quote.price, collateralUsed, quote.fee, fees);

        emit Events.CurveFilled(curveId, curve.maker, context.seller, collateralUsed, quote.sharesOut, quote.fee);
    }

    function requireCTFPositionMarket(LibEveMarket.Market storage market) internal view {
        if (market.positionTokenType != LibEveMarket.PositionTokenType.CTF) {
            revert Errors.PositionTokenTypeMismatch(
                market.marketId, uint8(LibEveMarket.PositionTokenType.CTF), uint8(market.positionTokenType)
            );
        }
    }

    function validatePositionIds(LibEveMarket.Market storage market) internal view {
        (uint256 yesPositionId, uint256 noPositionId) =
            LibCTF.derivePositionIds(market.positionToken, market.collateralToken, market.conditionId);
        if (yesPositionId != market.yesPositionId) {
            revert Errors.PositionIdMismatch(yesPositionId, market.yesPositionId);
        }
        if (noPositionId != market.noPositionId) {
            revert Errors.PositionIdMismatch(noPositionId, market.noPositionId);
        }
    }

    function validatePositionIdsIfCTF(LibEveMarket.Market storage market) internal view {
        if (market.positionTokenType != LibEveMarket.PositionTokenType.CTF) {
            return;
        }
        validatePositionIds(market);
    }
}
