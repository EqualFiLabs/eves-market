// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {CurveCLOBTypes} from "../types/CurveCLOBTypes.sol";
import {LibDelayedOrder} from "./LibDelayedOrder.sol";
import {LibDelayedOrderBuyFill} from "./LibDelayedOrderBuyFill.sol";
import {LibDelayedOrderFacet} from "./LibDelayedOrderFacet.sol";
import {LibDelayedOrderRoute} from "./LibDelayedOrderRoute.sol";
import {LibEveMarket} from "./LibEveMarket.sol";

library LibDelayedOrderMarketBuy {
    function processMarketBuy(
        LibEveMarket.EveMarketStorage storage state,
        uint256 orderId,
        LibEveMarket.DelayedOrder storage order,
        LibEveMarket.Book storage book,
        LibDelayedOrderRoute.PreparedRoute memory prepared
    ) public {
        if (prepared.curveIds.length == 0) {
            _cancelBuy(orderId, order, book, 0, 0, 0);
            return;
        }

        uint128 maxAveragePrice = order.maxAveragePrice == 0 ? type(uint128).max : order.maxAveragePrice;
        LibDelayedOrderRoute.FillPreview memory preview =
            LibDelayedOrderRoute.previewFill(state, book, order.remainingAmount, prepared, maxAveragePrice);
        if (preview.sharesOut < order.minOut || preview.averagePrice > maxAveragePrice) {
            _cancelBuy(orderId, order, book, 0, 0, 0);
            return;
        }

        CurveCLOBTypes.FillBestResult memory fill =
            LibDelayedOrderBuyFill.executeDelayedBuyFill(order, prepared, order.minOut, maxAveragePrice);
        uint128 creditedQuote = fill.unfilledCollateral;
        if (creditedQuote != 0) {
            LibDelayedOrder.creditQuote(order.owner, book.quoteToken, creditedQuote);
        }

        order.remainingAmount = 0;
        order.status = creditedQuote == 0
            ? LibEveMarket.DelayedOrderStatus.Filled
            : LibEveMarket.DelayedOrderStatus.PartiallyFilled;
        LibDelayedOrder.advanceHead(order.bookId);
        LibDelayedOrderFacet.emitProcessed(
            orderId, order, msg.sender, fill.collateralUsed, fill.sharesOut, creditedQuote, 0, 0, fill.feePaid
        );
    }

    function _cancelBuy(
        uint256 orderId,
        LibEveMarket.DelayedOrder storage order,
        LibEveMarket.Book storage book,
        uint128 filledIn,
        uint128 filledOut,
        uint128 feePaid
    ) private {
        uint128 creditedQuote = order.remainingAmount;
        if (creditedQuote != 0) {
            LibDelayedOrder.creditQuote(order.owner, book.quoteToken, creditedQuote);
        }
        order.remainingAmount = 0;
        order.status = LibEveMarket.DelayedOrderStatus.Cancelled;
        LibDelayedOrder.advanceHead(order.bookId);
        LibDelayedOrderFacet.emitProcessed(
            orderId, order, msg.sender, filledIn, filledOut, creditedQuote, 0, 0, feePaid
        );
    }
}
