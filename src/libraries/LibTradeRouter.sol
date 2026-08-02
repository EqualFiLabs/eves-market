// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {CurveCLOBTypes} from "../types/CurveCLOBTypes.sol";
import {ITradeRouter} from "../interfaces/ITradeRouter.sol";
import {Errors} from "./Errors.sol";
import {LibBookAccounting} from "./LibBookAccounting.sol";
import {LibBuyExecution} from "./LibBuyExecution.sol";
import {LibCurveMath} from "./LibCurveMath.sol";
import {LibEveMarket} from "./LibEveMarket.sol";
import {LibMarketAccess} from "./LibMarketAccess.sol";
import {LibRouter} from "./LibRouter.sol";

library LibTradeRouter {
    struct BuyQuote {
        uint128 sharesOut;
        uint128 fee;
        uint128 price;
        uint128 collateralUsed;
    }

    function requireMarket(bytes32 marketId) internal view returns (LibEveMarket.Market storage market) {
        market = LibMarketAccess.requireExistingMarket(LibEveMarket.store(), marketId);
    }

    function requireMarketCollateral(LibEveMarket.Market storage market, address routerCollateral) internal view {
        if (market.collateralToken != routerCollateral) {
            revert ITradeRouter.MarketCollateralMismatch(market.collateralToken, routerCollateral);
        }
    }

    function routerParams(CurveCLOBTypes.FillBestParams calldata params)
        internal
        view
        returns (CurveCLOBTypes.FillBestParams memory rewritten)
    {
        rewritten = routerParams(params, params.maxCollateralIn);
    }

    function routerParams(CurveCLOBTypes.FillBestParams calldata params, uint128 maxCollateralIn)
        internal
        view
        returns (CurveCLOBTypes.FillBestParams memory rewritten)
    {
        rewritten = CurveCLOBTypes.FillBestParams({
            marketId: params.marketId,
            isYesSide: params.isYesSide,
            maxCollateralIn: maxCollateralIn,
            minSharesOut: params.minSharesOut,
            maxAveragePrice: params.maxAveragePrice,
            curveIds: params.curveIds,
            expectedGenerations: params.expectedGenerations,
            expectedCommitments: params.expectedCommitments,
            payer: address(this),
            receiver: params.receiver
        });
    }

    function previewRetainedBuyFeeBalance(CurveCLOBTypes.FillBestParams memory params)
        internal
        view
        returns (uint128 retainedFeeBalance)
    {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Market storage market = state.markets[params.marketId];
        if (market.marketId != params.marketId || !LibMarketAccess.canExecute(market)) {
            return 0;
        }
        bytes32 bookId = params.isYesSide ? market.yesBookId : market.noBookId;
        LibEveMarket.Book storage book = state.books[bookId];

        uint128 remainingCollateral = params.maxCollateralIn;
        for (uint256 index = 0; index < params.curveIds.length && remainingCollateral != 0; ++index) {
            LibEveMarket.StoredCurve storage curve = state.curves[params.curveIds[index]];
            if (
                curve.bookId != bookId || !curve.active || curve.curveSide != LibEveMarket.CurveSide.ASK
                    || curve.remainingVolume == 0 || LibCurveMath.isExpired(state, curve)
            ) {
                continue;
            }

            BuyQuote memory quote = quoteBuyCurve(state, curve, remainingCollateral);
            if (quote.sharesOut == 0) {
                continue;
            }

            retainedFeeBalance += LibBookAccounting.retainedBuyFeeBalance(state, book, quote.fee);
            remainingCollateral -= quote.collateralUsed;
        }
    }

    function previewRetainedBookBuyFeeBalance(CurveCLOBTypes.FillBookParams memory params)
        internal
        view
        returns (uint128 retainedFeeBalance)
    {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Book storage book = state.books[params.bookId];
        uint128 remainingCollateral = params.maxQuoteIn;
        bool[] memory consumed = new bool[](params.curveIds.length);
        for (uint256 routed; routed < params.curveIds.length && remainingCollateral != 0; ++routed) {
            (uint256 index, bool found) =
                LibBuyExecution.selectBestAskCurveIndex(state, params, consumed, params.bookId);
            if (!found) break;
            consumed[index] = true;
            LibEveMarket.StoredCurve storage curve = state.curves[params.curveIds[index]];
            BuyQuote memory quote = quoteBuyCurve(state, curve, remainingCollateral);
            if (quote.sharesOut == 0) continue;
            retainedFeeBalance += LibBookAccounting.retainedBuyFeeBalance(state, book, quote.fee);
            remainingCollateral -= quote.collateralUsed;
        }
    }

    function validateOrderParams(CurveCLOBTypes.FillBestParams calldata params) internal pure {
        if (params.maxCollateralIn == 0) {
            revert ITradeRouter.ZeroAmount();
        }
        LibRouter.requireReceiver(params.receiver);
    }

    function validateSellParams(ITradeRouter.SellBestParams calldata params) internal pure {
        validateSellRouteParams(params);
        LibRouter.requireReceiver(params.receiver);
    }

    function validateSellRouteParams(ITradeRouter.SellBestParams calldata params) internal pure {
        if (params.maxSharesIn == 0) {
            revert ITradeRouter.ZeroAmount();
        }
        if (params.curveIds.length != params.expectedGenerations.length) {
            revert Errors.ArrayLengthMismatch(params.curveIds.length, params.expectedGenerations.length);
        }
        if (params.curveIds.length != params.expectedCommitments.length) {
            revert Errors.ArrayLengthMismatch(params.curveIds.length, params.expectedCommitments.length);
        }
    }

    function quoteBuyCurve(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.StoredCurve storage curve,
        uint128 collateralIn
    ) internal view returns (BuyQuote memory quote) {
        (quote.sharesOut, quote.fee, quote.price, quote.collateralUsed) =
            LibCurveMath.quoteAsk(state, curve, collateralIn);
    }
}
