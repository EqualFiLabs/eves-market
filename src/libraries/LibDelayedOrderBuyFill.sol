// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {CurveCLOBTypes} from "../types/CurveCLOBTypes.sol";
import {MLOPredictionTypes} from "../types/MLOPredictionTypes.sol";
import {LibBuyExecution} from "./LibBuyExecution.sol";
import {LibDelayedOrder} from "./LibDelayedOrder.sol";
import {LibDelayedOrderRoute} from "./LibDelayedOrderRoute.sol";
import {LibEveMarket} from "./LibEveMarket.sol";
import {LibMLOPredictionFill} from "./LibMLOPredictionFill.sol";
import {LibProductAdapter} from "./LibProductAdapter.sol";

library LibDelayedOrderBuyFill {
    function executeDelayedBuyFill(
        LibEveMarket.DelayedOrder storage order,
        LibDelayedOrderRoute.PreparedRoute memory prepared,
        uint128 minBaseOut,
        uint128 maxAveragePrice
    ) public returns (CurveCLOBTypes.FillBestResult memory fill) {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Book storage book = state.books[order.bookId];
        LibBuyExecution.RouteRequest memory request = LibBuyExecution.RouteRequest({
            bookId: order.bookId,
            marketId: book.marketId,
            isYesSide: book.isYesSide,
            payer: address(this),
            receiver: order.owner
        });

        LibDelayedOrder.setActiveProcessor(msg.sender);
        LibBuyExecution.RouteTotals memory totals = _routeDelayedBuy(state, order, prepared, request);
        LibDelayedOrder.setActiveProcessor(address(0));

        fill = LibBuyExecution.finalizeRoute(request, totals, minBaseOut, maxAveragePrice);
    }

    function _routeDelayedBuy(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.DelayedOrder storage order,
        LibDelayedOrderRoute.PreparedRoute memory prepared,
        LibBuyExecution.RouteRequest memory request
    ) private returns (LibBuyExecution.RouteTotals memory totals) {
        totals.remainingCollateral = order.remainingAmount;
        for (uint256 index; index < prepared.curveIds.length && totals.remainingCollateral != 0; ++index) {
            uint256 curveId = prepared.curveIds[index];
            if (LibProductAdapter.isEscrowBackedCurve(state, curveId)) {
                totals = LibBuyExecution.routeSingleCurve(
                    state,
                    curveId,
                    prepared.expectedGenerations[index],
                    prepared.expectedCommitments[index],
                    request,
                    totals
                );
                continue;
            }
            MLOPredictionTypes.FillResult memory mloFill = _fillEscrowedMLOAsk(
                state,
                order.owner,
                curveId,
                totals.remainingCollateral,
                prepared.expectedGenerations[index],
                prepared.expectedCommitments[index]
            );
            totals.sharesOut += mloFill.fill.sharesOut;
            totals.totalCollateralUsed += mloFill.fill.collateralUsed;
            totals.totalFeePaid += mloFill.fill.feePaid;
            totals.remainingCollateral -= mloFill.fill.collateralUsed;
            if (mloFill.fill.sharesOut != 0) {
                totals.filledCurveCount += 1;
            }
        }
    }

    function _fillEscrowedMLOAsk(
        LibEveMarket.EveMarketStorage storage state,
        address receiver,
        uint256 curveId,
        uint128 collateralIn,
        uint32 expectedGeneration,
        bytes32 expectedCommitment
    ) private returns (MLOPredictionTypes.FillResult memory mloFill) {
        mloFill = LibMLOPredictionFill.fillAskCurve(
            state,
            MLOPredictionTypes.MLOFillRequest({
                curveId: curveId,
                collateralIn: collateralIn,
                minSharesOut: 0,
                expectedGeneration: expectedGeneration,
                expectedCommitment: expectedCommitment,
                payer: address(this),
                receiver: receiver,
                payerIsEscrowed: true
            })
        );
    }
}
