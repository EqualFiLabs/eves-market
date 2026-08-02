// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {CurveCLOBTypes} from "../types/CurveCLOBTypes.sol";
import {LibDelayedOrder} from "./LibDelayedOrder.sol";
import {LibDelayedOrderFacet} from "./LibDelayedOrderFacet.sol";
import {LibDelayedOrderRoute} from "./LibDelayedOrderRoute.sol";
import {LibDelayedOrderSellFill} from "./LibDelayedOrderSellFill.sol";
import {LibEveMarket} from "./LibEveMarket.sol";

library LibDelayedOrderMarketSell {
    function processMarketSell(
        LibEveMarket.EveMarketStorage storage state,
        uint256 orderId,
        LibEveMarket.DelayedOrder storage order,
        LibEveMarket.Book storage book,
        LibDelayedOrderRoute.PreparedRoute memory prepared
    ) public {
        if (prepared.curveIds.length == 0) {
            _cancelSell(orderId, order, book);
            return;
        }

        LibDelayedOrderRoute.SellPreview memory preview =
            LibDelayedOrderRoute.previewSell(state, book, order.remainingAmount, prepared, 0);
        if (preview.quoteOut < order.minOut) {
            _cancelSell(orderId, order, book);
            return;
        }

        CurveCLOBTypes.SellBookResult memory sell =
            LibDelayedOrderSellFill.executeDelayedSellFill(order, prepared, order.minOut);
        uint128 creditedBase = sell.unfilledBase;
        if (creditedBase != 0) {
            LibDelayedOrderFacet.creditBase(order.owner, book, creditedBase);
        }

        order.remainingAmount = 0;
        order.status = creditedBase == 0
            ? LibEveMarket.DelayedOrderStatus.Filled
            : LibEveMarket.DelayedOrderStatus.PartiallyFilled;
        LibDelayedOrder.advanceHead(order.bookId);
        LibDelayedOrderFacet.emitProcessed(
            orderId, order, msg.sender, sell.baseSold, sell.quoteOut, 0, creditedBase, 0, sell.feePaid
        );
    }

    function _cancelSell(uint256 orderId, LibEveMarket.DelayedOrder storage order, LibEveMarket.Book storage book)
        private
    {
        uint128 creditedBase = order.remainingAmount;
        if (creditedBase != 0) {
            LibDelayedOrderFacet.creditBase(order.owner, book, creditedBase);
        }
        order.remainingAmount = 0;
        order.status = LibEveMarket.DelayedOrderStatus.Cancelled;
        LibDelayedOrder.advanceHead(order.bookId);
        LibDelayedOrderFacet.emitProcessed(orderId, order, msg.sender, 0, 0, 0, creditedBase, 0, 0);
    }
}
