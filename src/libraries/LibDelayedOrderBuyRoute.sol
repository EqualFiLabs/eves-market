// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {MLOPredictionTypes} from "../types/MLOPredictionTypes.sol";
import {LibBuyExecution} from "./LibBuyExecution.sol";
import {LibDelayedOrderEscrowAskFill} from "./LibDelayedOrderEscrowAskFill.sol";
import {LibDelayedOrderMLOAskFill} from "./LibDelayedOrderMLOAskFill.sol";
import {LibDelayedOrderRoute} from "./LibDelayedOrderRoute.sol";
import {LibEveMarket} from "./LibEveMarket.sol";
import {LibProductAdapter} from "./LibProductAdapter.sol";

library LibDelayedOrderBuyRoute {
    function routeDelayedBuy(
        LibEveMarket.DelayedOrder storage order,
        LibDelayedOrderRoute.PreparedRoute memory prepared,
        LibBuyExecution.RouteRequest memory request
    ) public returns (LibBuyExecution.RouteTotals memory totals) {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        totals.remainingCollateral = order.remainingAmount;
        for (uint256 index; index < prepared.curveIds.length && totals.remainingCollateral != 0; ++index) {
            uint256 curveId = prepared.curveIds[index];
            if (LibProductAdapter.isEscrowBackedCurve(state, curveId)) {
                totals = LibDelayedOrderEscrowAskFill.fillEscrowedAsk(
                    curveId, prepared.expectedGenerations[index], prepared.expectedCommitments[index], request, totals
                );
                continue;
            }
            MLOPredictionTypes.MLOAskFillResult memory mloFill = LibDelayedOrderMLOAskFill.fillEscrowedMLOAsk(
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
}
