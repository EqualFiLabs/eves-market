// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {DelayedOrderTypes} from "../types/DelayedOrderTypes.sol";
import {Errors} from "./Errors.sol";
import {Events} from "./Events.sol";
import {LibDelayedOrder} from "./LibDelayedOrder.sol";
import {LibDelayedOrderFacet} from "./LibDelayedOrderFacet.sol";
import {LibDelayedOrderLimitBuy} from "./LibDelayedOrderLimitBuy.sol";
import {LibDelayedOrderMarketBuy} from "./LibDelayedOrderMarketBuy.sol";
import {LibDelayedOrderRoute} from "./LibDelayedOrderRoute.sol";
import {LibDelayedOrderSell} from "./LibDelayedOrderSell.sol";
import {LibEveMarket} from "./LibEveMarket.sol";

library LibDelayedOrderExecution {
    function processExecutableOrder(
        LibEveMarket.EveMarketStorage storage state,
        uint256 orderId,
        LibEveMarket.DelayedOrder storage order,
        DelayedOrderTypes.DelayedOrderRoute calldata route
    ) public {
        bytes32 actualRouteHash = LibDelayedOrder.routeHash(
            route.curveIds, route.expectedGenerations, route.expectedCommitments
        );
        if (actualRouteHash != order.routeHash) {
            revert Errors.DelayedOrderRouteMismatch(orderId, order.routeHash, actualRouteHash);
        }

        LibEveMarket.Book storage book = state.books[order.bookId];
        if (order.kind == LibEveMarket.DelayedOrderKind.MarketBuy) {
            LibDelayedOrderRoute.PreparedRoute memory prepared =
                LibDelayedOrderRoute.prepareValidAskRoute(state, order, book, route);
            LibDelayedOrderMarketBuy.processMarketBuy(state, orderId, order, book, prepared);
            return;
        }
        if (order.kind == LibEveMarket.DelayedOrderKind.LimitBuy) {
            LibDelayedOrderRoute.PreparedRoute memory prepared =
                LibDelayedOrderRoute.prepareValidAskRoute(state, order, book, route);
            LibDelayedOrderLimitBuy.processLimitBuy(state, orderId, order, book, prepared);
            return;
        }
        if (order.kind == LibEveMarket.DelayedOrderKind.MarketSell) {
            LibDelayedOrderRoute.PreparedRoute memory prepared =
                LibDelayedOrderRoute.prepareValidBidRoute(state, order, book, route);
            LibDelayedOrderSell.processMarketSell(state, orderId, order, book, prepared);
            return;
        }
        if (order.kind == LibEveMarket.DelayedOrderKind.LimitSell) {
            LibDelayedOrderRoute.PreparedRoute memory prepared =
                LibDelayedOrderRoute.prepareValidBidRoute(state, order, book, route);
            LibDelayedOrderSell.processLimitSell(state, orderId, order, book, prepared);
            return;
        }

        revert Errors.UnsupportedDelayedOrderKind(uint8(order.kind));
    }

    function expireHeadOrder(uint256 orderId, LibEveMarket.DelayedOrder storage order, uint64 sequence) public {
        if (order.sequence != sequence) {
            revert Errors.InvalidAmount(sequence);
        }

        LibEveMarket.Book storage book = LibEveMarket.store().books[order.bookId];
        uint128 creditedQuote;
        uint128 creditedBase;
        if (LibDelayedOrderFacet.isBuyOrder(order.kind)) {
            creditedQuote = order.remainingAmount;
            if (creditedQuote != 0) {
                LibDelayedOrder.creditQuote(order.owner, book.quoteToken, creditedQuote);
            }
        } else {
            creditedBase = order.remainingAmount;
            if (creditedBase != 0) {
                LibDelayedOrderFacet.creditBase(order.owner, book, creditedBase);
            }
        }
        order.remainingAmount = 0;
        order.status = LibEveMarket.DelayedOrderStatus.Expired;
        LibDelayedOrder.advanceHead(order.bookId);
        emit Events.DelayedOrderExpired(orderId, order.bookId, order.owner, creditedQuote, creditedBase);
        LibDelayedOrderFacet.emitProcessed(orderId, order, msg.sender, 0, 0, creditedQuote, creditedBase, 0, 0);
    }
}
