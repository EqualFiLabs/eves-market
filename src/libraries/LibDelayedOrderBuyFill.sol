// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {CurveCLOBTypes} from "../types/CurveCLOBTypes.sol";
import {LibBuyExecution} from "./LibBuyExecution.sol";
import {LibDelayedOrder} from "./LibDelayedOrder.sol";
import {LibDelayedOrderBuyRoute} from "./LibDelayedOrderBuyRoute.sol";
import {LibDelayedOrderRoute} from "./LibDelayedOrderRoute.sol";
import {LibEveMarket} from "./LibEveMarket.sol";

library LibDelayedOrderBuyFill {
    function executeDelayedBuyFill(
        LibEveMarket.DelayedOrder storage order,
        LibDelayedOrderRoute.PreparedRoute memory prepared,
        uint128 minBaseOut,
        uint128 maxAveragePrice
    ) public returns (CurveCLOBTypes.FillBestResult memory fill) {
        LibEveMarket.Book storage book = LibEveMarket.store().books[order.bookId];
        LibBuyExecution.RouteRequest memory request = LibBuyExecution.RouteRequest({
            bookId: order.bookId,
            marketId: book.marketId,
            isYesSide: book.isYesSide,
            payer: address(this),
            taker: order.owner,
            receiver: order.owner
        });

        LibDelayedOrder.setActiveProcessor(msg.sender);
        LibBuyExecution.RouteTotals memory totals = LibDelayedOrderBuyRoute.routeDelayedBuy(order, prepared, request);
        LibDelayedOrder.setActiveProcessor(address(0));

        fill = LibBuyExecution.finalizeRoute(request, totals, minBaseOut, maxAveragePrice);
    }
}
