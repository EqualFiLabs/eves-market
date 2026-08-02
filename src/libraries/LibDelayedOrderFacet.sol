// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {DelayedOrderTypes} from "../types/DelayedOrderTypes.sol";
import {Errors} from "./Errors.sol";
import {Events} from "./Events.sol";
import {LibDelayedOrder} from "./LibDelayedOrder.sol";
import {LibEveMarket} from "./LibEveMarket.sol";

library LibDelayedOrderFacet {
    struct SubmissionSchedule {
        uint64 submitBlock;
        uint64 executableBlock;
        uint64 expiryBlock;
    }

    function tryHeadOrder(bytes32 bookId) public view returns (uint64 sequence, uint256 orderId, bool hasHead) {
        (uint64 head, uint64 tail) = LibDelayedOrder.queueBounds(bookId);
        if (head >= tail) {
            return (head, 0, false);
        }
        sequence = head;
        orderId = LibDelayedOrder.orderIdBySequence(bookId, head);
        hasHead = orderId != 0;
    }

    function emitProcessed(
        uint256 orderId,
        LibEveMarket.DelayedOrder storage order,
        address processor,
        uint128 filledIn,
        uint128 filledOut,
        uint128 creditedQuote,
        uint128 creditedBase,
        uint256 restingCurveId,
        uint128 feePaid
    ) public {
        uint128 processorReward;
        if (feePaid != 0 && LibEveMarket.store().config.delayedOrderProcessorFeeShareBps != 0) {
            processorReward =
                uint128((uint256(feePaid) * LibEveMarket.store().config.delayedOrderProcessorFeeShareBps) / 10_000);
        }
        emit Events.DelayedOrderProcessed(
            orderId,
            order.bookId,
            order.owner,
            processor,
            uint8(order.status),
            filledIn,
            filledOut,
            creditedQuote,
            creditedBase,
            processorReward,
            restingCurveId
        );
    }

    function lockedQuote(address owner, address token) public view returns (uint256 locked) {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        uint256 nextOrderId = state.delayedOrders.nextOrderId;
        for (uint256 orderId = 1; orderId <= nextOrderId; ++orderId) {
            LibEveMarket.DelayedOrder storage order = state.delayedOrders.orders[orderId];
            if (
                order.owner == owner && order.status == LibEveMarket.DelayedOrderStatus.Pending
                    && isBuyOrder(order.kind) && state.books[order.bookId].quoteToken == token
            ) {
                locked += order.remainingAmount;
            }
        }
    }

    function lockedBase(address owner, LibEveMarket.BookAssetType assetType, address token, uint256 tokenId)
        public
        view
        returns (uint256 locked)
    {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        uint256 nextOrderId = state.delayedOrders.nextOrderId;
        for (uint256 orderId = 1; orderId <= nextOrderId; ++orderId) {
            LibEveMarket.DelayedOrder storage order = state.delayedOrders.orders[orderId];
            LibEveMarket.Book storage book = state.books[order.bookId];
            if (
                order.owner == owner && order.status == LibEveMarket.DelayedOrderStatus.Pending
                    && !isBuyOrder(order.kind) && book.assetType == assetType && book.baseToken == token
                    && book.baseTokenId == tokenId
            ) {
                locked += order.remainingAmount;
            }
        }
    }

    function isSupportedDelayedKind(LibEveMarket.DelayedOrderKind kind) public pure returns (bool supported) {
        supported = kind == LibEveMarket.DelayedOrderKind.MarketBuy || kind == LibEveMarket.DelayedOrderKind.LimitBuy
            || kind == LibEveMarket.DelayedOrderKind.MarketSell || kind == LibEveMarket.DelayedOrderKind.LimitSell;
    }

    function isBuyOrder(LibEveMarket.DelayedOrderKind kind) public pure returns (bool buyOrder) {
        buyOrder = kind == LibEveMarket.DelayedOrderKind.MarketBuy || kind == LibEveMarket.DelayedOrderKind.LimitBuy;
    }

    function isLimitOrder(LibEveMarket.DelayedOrderKind kind) public pure returns (bool limitOrder) {
        limitOrder = kind == LibEveMarket.DelayedOrderKind.LimitBuy || kind == LibEveMarket.DelayedOrderKind.LimitSell;
    }

    function recordSubmittedOrder(
        DelayedOrderTypes.SubmitDelayedOrderParams calldata params,
        address owner,
        bytes32 marketId,
        SubmissionSchedule memory schedule,
        bytes32 hash
    ) public returns (uint256 orderId, uint64 sequence) {
        (orderId, sequence) = LibDelayedOrder.recordSubmittedOrder(
            owner,
            params.bookId,
            marketId,
            params.kind,
            params.amountIn,
            params.limitPrice,
            params.minOut,
            params.maxAveragePrice,
            schedule.submitBlock,
            schedule.executableBlock,
            schedule.expiryBlock,
            hash
        );
    }

    function emitSubmitted(
        uint256 orderId,
        uint64 sequence,
        DelayedOrderTypes.SubmitDelayedOrderParams calldata params,
        address owner,
        bytes32 hash
    ) public {
        emit Events.DelayedOrderSubmitted(
            orderId,
            params.bookId,
            owner,
            uint8(params.kind),
            params.amountIn,
            params.limitPrice,
            sequence,
            hash,
            params.curveIds,
            params.expectedGenerations,
            params.expectedCommitments
        );
    }

    function submissionSchedule(LibEveMarket.MarketConfig storage config)
        public
        view
        returns (SubmissionSchedule memory schedule)
    {
        schedule.submitBlock = currentBlock();
        schedule.executableBlock = schedule.submitBlock + config.delayedOrderProtectionDelayBlocks;
        schedule.expiryBlock = schedule.executableBlock + config.delayedOrderExecutionGraceBlocks;
    }

    function currentBlock() public view returns (uint64 currentBlock_) {
        if (block.number > type(uint64).max) {
            revert Errors.InvalidAmount(block.number);
        }
        currentBlock_ = uint64(block.number);
    }

    function creditBase(address owner, LibEveMarket.Book storage book, uint128 amount) public {
        LibDelayedOrder.creditBase(owner, book.assetType, book.baseToken, book.baseTokenId, amount);
    }
}
