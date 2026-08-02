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
        uint8 collateralProfileId;
        uint64 createdAt;
        uint64 expiryTime;
        bool exists;
    }

    struct CompressionResult {
        uint256 newPositionId;
        uint128 positionAmount;
        uint128 collateralOut;
    }

    struct NativePositionPayoutView {
        uint256 positionId;
        uint8 moduleId;
        bytes32 conditionId;
        uint8 outcomeIndex;
        bytes32 marketId;
        address collateralToken;
        uint8 collateralProfileId;
        bool isFinal;
        uint128 collateralOut;
    }

    struct NativeCollateralStatus {
        address collateralToken;
        uint256 held;
        uint256 liability;
        uint256 balanceAboveNativeLiability;
        bool solvent;
    }
}
