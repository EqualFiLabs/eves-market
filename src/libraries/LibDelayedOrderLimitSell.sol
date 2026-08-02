// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {CurveCLOBTypes} from "../types/CurveCLOBTypes.sol";
import {LibCurveStorage} from "./LibCurveStorage.sol";
import {LibDelayedOrder} from "./LibDelayedOrder.sol";
import {LibDelayedOrderFacet} from "./LibDelayedOrderFacet.sol";
import {LibDelayedOrderRoute} from "./LibDelayedOrderRoute.sol";
import {LibDelayedOrderSellFill} from "./LibDelayedOrderSellFill.sol";
import {LibEveMarket} from "./LibEveMarket.sol";

library LibDelayedOrderLimitSell {
    function processLimitSell(
        LibEveMarket.EveMarketStorage storage state,
        uint256 orderId,
        LibEveMarket.DelayedOrder storage order,
        LibEveMarket.Book storage book,
        LibDelayedOrderRoute.PreparedRoute memory prepared
    ) public {
        CurveCLOBTypes.SellBookResult memory sell;
        if (prepared.curveIds.length != 0) {
            LibDelayedOrderRoute.SellPreview memory preview =
                LibDelayedOrderRoute.previewSell(state, book, order.remainingAmount, prepared, order.limitPrice);
            if (preview.baseSold != 0) {
                sell = LibDelayedOrderSellFill.executeDelayedSellFill(order, prepared, 0);
            }
        }

        uint128 remainingBase = sell.unfilledBase == 0 && sell.baseSold == 0 ? order.remainingAmount : sell.unfilledBase;
        uint256 restingCurveId = _restLimitSellRemainder(state, order, remainingBase);
        order.remainingAmount = 0;
        order.restingCurveId = restingCurveId;
        if (restingCurveId != 0) {
            order.status = LibEveMarket.DelayedOrderStatus.Resting;
        } else if (sell.baseSold != 0 && remainingBase == 0) {
            order.status = LibEveMarket.DelayedOrderStatus.Filled;
        } else if (sell.baseSold != 0) {
            order.status = LibEveMarket.DelayedOrderStatus.PartiallyFilled;
        } else {
            order.status = LibEveMarket.DelayedOrderStatus.Cancelled;
        }
        LibDelayedOrder.advanceHead(order.bookId);
        LibDelayedOrderFacet.emitProcessed(
            orderId, order, msg.sender, sell.baseSold, sell.quoteOut, 0, 0, restingCurveId, sell.feePaid
        );
    }

    function _restLimitSellRemainder(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.DelayedOrder storage order,
        uint128 remainingBase
    ) private returns (uint256 restingCurveId) {
        if (remainingBase == 0) {
            return 0;
        }

        restingCurveId = LibCurveStorage.createFlatCurveFromEscrow(
            state,
            LibCurveStorage.FlatCurveFromEscrowParams({
                bookId: order.bookId,
                maker: order.owner,
                curveSide: LibEveMarket.CurveSide.ASK,
                volume: remainingBase,
                quoteEscrow: 0,
                price: uint72(order.limitPrice),
                durationMinutes: state.config.delayedOrderRestingDurationMinutes
            })
        );
    }
}
