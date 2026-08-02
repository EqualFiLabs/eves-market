// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {CurveCLOBTypes} from "../types/CurveCLOBTypes.sol";
import {LibDelayedOrder} from "./LibDelayedOrder.sol";
import {LibDelayedOrderRoute} from "./LibDelayedOrderRoute.sol";
import {LibEveMarket} from "./LibEveMarket.sol";
import {LibSellExecution} from "./LibSellExecution.sol";

library LibDelayedOrderSellFill {
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
}
