// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {LibEveMarket} from "../libraries/LibEveMarket.sol";

abstract contract DelayedOrderTypes {
    struct SubmitDelayedOrderParams {
        bytes32 bookId;
        LibEveMarket.DelayedOrderKind kind;
        uint128 amountIn;
        uint128 limitPrice;
        uint128 minOut;
        uint128 maxAveragePrice;
        uint256[] curveIds;
        uint32[] expectedGenerations;
        bytes32[] expectedCommitments;
    }

    struct DelayedOrderRoute {
        uint256[] curveIds;
        uint32[] expectedGenerations;
        bytes32[] expectedCommitments;
    }

    struct ProcessDelayedOrderResult {
        uint256 processedCount;
        uint256 stoppedOrderId;
    }

    struct DelayedOrderView {
        uint256 orderId;
        address owner;
        bytes32 bookId;
        bytes32 marketId;
        LibEveMarket.DelayedOrderKind kind;
        LibEveMarket.DelayedOrderStatus status;
        uint128 amountIn;
        uint128 remainingAmount;
        uint128 limitPrice;
        uint128 minOut;
        uint128 maxAveragePrice;
        uint64 submitBlock;
        uint64 executableBlock;
        uint64 expiryBlock;
        uint64 sequence;
        bytes32 routeHash;
        uint256 restingCurveId;
        bool executable;
        bool expired;
    }

    struct BookQueueView {
        bytes32 bookId;
        uint64 head;
        uint64 tail;
        uint256 headOrderId;
        uint256 pendingCount;
    }

    struct CreditBalanceView {
        address owner;
        uint8 assetType;
        address token;
        uint256 tokenId;
        uint256 withdrawable;
        uint256 locked;
        uint256 available;
    }
}
