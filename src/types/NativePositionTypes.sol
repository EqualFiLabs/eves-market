// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

abstract contract NativePositionTypes {
    struct ComboConditionView {
        bytes32 conditionId;
        bytes32 legsHash;
        uint16 legCount;
        uint64 preparedAt;
        bool exists;
    }

    struct ComboPositionIds {
        bytes32 conditionId;
        uint256 yesPositionId;
        uint256 noPositionId;
    }

    struct ComboMarketView {
        bytes32 marketId;
        bytes32 conditionId;
        address positionToken;
        uint256 yesPositionId;
        uint256 noPositionId;
        bytes32 yesBookId;
        bytes32 noBookId;
        address creator;
        address collateralToken;
        uint64 createdAt;
        uint64 expiryTime;
        bool exists;
    }

    struct CompressionResult {
        uint256 newPositionId;
        uint128 positionAmount;
        uint128 collateralOut;
    }
}
