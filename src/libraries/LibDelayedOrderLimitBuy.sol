// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {CurveCLOBTypes} from "../types/CurveCLOBTypes.sol";
import {LibCurveStorage} from "./LibCurveStorage.sol";
import {LibDelayedOrder} from "./LibDelayedOrder.sol";
import {LibDelayedOrderBuyFill} from "./LibDelayedOrderBuyFill.sol";
import {LibDelayedOrderFacet} from "./LibDelayedOrderFacet.sol";
import {LibDelayedOrderRoute} from "./LibDelayedOrderRoute.sol";
import {LibEveMarket} from "./LibEveMarket.sol";

library LibDelayedOrderLimitBuy {
    function processLimitBuy(
        LibEveMarket.EveMarketStorage storage state,
        uint256 orderId,
        LibEveMarket.DelayedOrder storage order,
        LibEveMarket.Book storage book,
        LibDelayedOrderRoute.PreparedRoute memory prepared
    ) public {
        CurveCLOBTypes.FillBestResult memory fill;
        if (prepared.curveIds.length != 0) {
            LibDelayedOrderRoute.FillPreview memory preview =
                LibDelayedOrderRoute.previewFill(state, book, order.remainingAmount, prepared, order.limitPrice);
            if (preview.sharesOut != 0 && preview.averagePrice <= order.limitPrice) {
                fill = LibDelayedOrderBuyFill.executeDelayedBuyFill(order, prepared, 0, order.limitPrice);
            }
        }

        uint128 remainingQuote =
            fill.unfilledCollateral == 0 && fill.collateralUsed == 0 ? order.remainingAmount : fill.unfilledCollateral;
        (uint256 restingCurveId, uint128 creditedQuote) = _restLimitBuyRemainder(state, order, book, remainingQuote);
        order.remainingAmount = 0;
        order.restingCurveId = restingCurveId;
        if (restingCurveId != 0) {
            order.status = LibEveMarket.DelayedOrderStatus.Resting;
        } else if (fill.sharesOut != 0 && remainingQuote == 0) {
            order.status = LibEveMarket.DelayedOrderStatus.Filled;
        } else if (fill.sharesOut != 0) {
            order.status = LibEveMarket.DelayedOrderStatus.PartiallyFilled;
        } else {
            order.status = LibEveMarket.DelayedOrderStatus.Cancelled;
        }
        LibDelayedOrder.advanceHead(order.bookId);
        LibDelayedOrderFacet.emitProcessed(
            orderId,
            order,
            msg.sender,
            fill.collateralUsed,
            fill.sharesOut,
            creditedQuote,
            0,
            restingCurveId,
            fill.feePaid
        );
    }

    function _restLimitBuyRemainder(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.DelayedOrder storage order,
        LibEveMarket.Book storage book,
        uint128 remainingQuote
    ) private returns (uint256 restingCurveId, uint128 creditedQuote) {
        if (remainingQuote == 0) {
            return (0, 0);
        }

        (uint128 volume, uint128 dust) =
            LibDelayedOrder.bidVolumeFromEscrow(remainingQuote, order.limitPrice, book.priceDenominator);
        creditedQuote = dust;
        uint128 quoteEscrow = remainingQuote - dust;
        if (volume == 0 || quoteEscrow == 0) {
            LibDelayedOrder.creditQuote(order.owner, book.quoteToken, remainingQuote);
            return (0, remainingQuote);
        }

        if (dust != 0) {
            LibDelayedOrder.creditQuote(order.owner, book.quoteToken, dust);
        }
        restingCurveId = LibCurveStorage.createFlatCurveFromEscrow(
            state,
            LibCurveStorage.FlatCurveFromEscrowParams({
                bookId: order.bookId,
                maker: order.owner,
                curveSide: LibEveMarket.CurveSide.BID,
                volume: volume,
                quoteEscrow: quoteEscrow,
                price: uint72(order.limitPrice),
                durationMinutes: state.config.delayedOrderRestingDurationMinutes
            })
        );
    }
}
