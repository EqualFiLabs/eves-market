// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {CurveCLOBTypes} from "../types/CurveCLOBTypes.sol";
import {LibCurveStorage} from "./LibCurveStorage.sol";
import {LibDelayedOrder} from "./LibDelayedOrder.sol";
import {LibDelayedOrderFacet} from "./LibDelayedOrderFacet.sol";
import {LibDelayedOrderRoute} from "./LibDelayedOrderRoute.sol";
import {LibEveMarket} from "./LibEveMarket.sol";
import {LibSellExecution} from "./LibSellExecution.sol";

library LibDelayedOrderSell {
    function processMarketSell(
        LibEveMarket.EveMarketStorage storage state,
        uint256 orderId,
        LibEveMarket.DelayedOrder storage order,
        LibEveMarket.Book storage book,
        LibDelayedOrderRoute.PreparedRoute memory prepared
    ) public {
        if (prepared.curveIds.length == 0) {
            cancelSell(orderId, order, book, 0, 0, 0);
            return;
        }

        LibDelayedOrderRoute.SellPreview memory preview =
            LibDelayedOrderRoute.previewSell(state, book, order.remainingAmount, prepared, 0);
        if (preview.quoteOut < order.minOut) {
            cancelSell(orderId, order, book, 0, 0, 0);
            return;
        }

        CurveCLOBTypes.SellBookResult memory sell = executeDelayedSellFill(order, prepared, order.minOut);
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
                sell = executeDelayedSellFill(order, prepared, 0);
            }
        }

        uint128 remainingBase = sell.unfilledBase == 0 && sell.baseSold == 0 ? order.remainingAmount : sell.unfilledBase;
        uint256 restingCurveId = restLimitSellRemainder(state, order, remainingBase);
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

    function executeDelayedSellFill(
        LibEveMarket.DelayedOrder storage order,
        LibDelayedOrderRoute.PreparedRoute memory prepared,
        uint128 minQuoteOut
    ) public returns (CurveCLOBTypes.SellBookResult memory sell) {
        LibDelayedOrder.setActiveProcessor(msg.sender);
        sell = LibSellExecution.sellBookBest(
            CurveCLOBTypes.SellBookParams({
                bookId: order.bookId,
                maxBaseIn: order.remainingAmount,
                minQuoteOut: minQuoteOut,
                curveIds: prepared.curveIds,
                expectedGenerations: prepared.expectedGenerations,
                expectedCommitments: prepared.expectedCommitments,
                receiver: order.owner
            }),
            CurveCLOBTypes.SellExecutionContext({
                source: address(this), seller: order.owner, receiver: order.owner, useEscrowedBase: true
            })
        );
        LibDelayedOrder.setActiveProcessor(address(0));
    }

    function restLimitSellRemainder(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.DelayedOrder storage order,
        uint128 remainingBase
    ) public returns (uint256 restingCurveId) {
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

    function cancelSell(
        uint256 orderId,
        LibEveMarket.DelayedOrder storage order,
        LibEveMarket.Book storage book,
        uint128 filledIn,
        uint128 filledOut,
        uint128 feePaid
    ) public {
        uint128 creditedBase = order.remainingAmount;
        if (creditedBase != 0) {
            LibDelayedOrderFacet.creditBase(order.owner, book, creditedBase);
        }
        order.remainingAmount = 0;
        order.status = LibEveMarket.DelayedOrderStatus.Cancelled;
        LibDelayedOrder.advanceHead(order.bookId);
        LibDelayedOrderFacet.emitProcessed(orderId, order, msg.sender, filledIn, filledOut, 0, creditedBase, 0, feePaid);
    }
}
