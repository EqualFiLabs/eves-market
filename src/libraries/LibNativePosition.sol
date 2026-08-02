// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Errors} from "./Errors.sol";
import {Events} from "./Events.sol";
import {LibEveMarket} from "./LibEveMarket.sol";

library LibNativePosition {
    uint8 internal constant MODULE_BINARY = 1;
    uint8 internal constant MODULE_NEGRISK = 2;
    uint8 internal constant MODULE_COMBINATORIAL = 3;

    uint8 internal constant OUTCOME_YES = 0;
    uint8 internal constant OUTCOME_NO = 1;

    uint256 internal constant RESULT_DENOMINATOR = 1e18;
    uint256 internal constant PAYOUT_FACTOR_DENOMINATOR = 1e36;

    bytes32 internal constant BINARY_CONDITION_DOMAIN = keccak256("EVE_NATIVE_BINARY_CONDITION");
    bytes32 internal constant COMBO_CONDITION_DOMAIN = keccak256("EVE_NATIVE_COMBO_CONDITION");
    bytes32 internal constant POSITION_DOMAIN = keccak256("EVE_NATIVE_POSITION");

    struct BinaryPositionIds {
        bytes32 marketId;
        bytes32 conditionId;
        uint256 yesPositionId;
        uint256 noPositionId;
    }

    function binaryConditionIdFor(bytes32 marketId) internal pure returns (bytes32 conditionId) {
        conditionId = keccak256(abi.encode(BINARY_CONDITION_DOMAIN, marketId));
    }

    function comboConditionIdFor(uint256[] memory canonicalLegs) internal pure returns (bytes32 conditionId) {
        conditionId = keccak256(abi.encode(COMBO_CONDITION_DOMAIN, canonicalLegs));
    }

    function positionIdFor(uint8 moduleId, bytes32 conditionId, uint8 outcomeIndex)
        internal
        pure
        returns (uint256 positionId)
    {
        positionId = uint256(keccak256(abi.encode(POSITION_DOMAIN, moduleId, conditionId, outcomeIndex)));
    }

    function isBinaryOutcome(uint8 outcomeIndex) internal pure returns (bool) {
        return outcomeIndex == OUTCOME_YES || outcomeIndex == OUTCOME_NO;
    }

    function prepareBinaryCondition(LibEveMarket.EveMarketStorage storage state, bytes32 marketId)
        internal
        returns (BinaryPositionIds memory ids)
    {
        LibEveMarket.NativeBinaryCondition storage stored = state.nativeBinaryConditions[marketId];
        if (stored.exists) {
            return BinaryPositionIds({
                marketId: stored.marketId,
                conditionId: stored.conditionId,
                yesPositionId: stored.yesPositionId,
                noPositionId: stored.noPositionId
            });
        }

        requireCLOBMarket(state, marketId);
        if (state.config.evesPositionManager == address(0)) {
            revert Errors.ZeroAddress();
        }

        bytes32 conditionId = binaryConditionIdFor(marketId);
        uint256 yesPositionId = positionIdFor(MODULE_BINARY, conditionId, OUTCOME_YES);
        uint256 noPositionId = positionIdFor(MODULE_BINARY, conditionId, OUTCOME_NO);

        stored.marketId = marketId;
        stored.conditionId = conditionId;
        stored.yesPositionId = yesPositionId;
        stored.noPositionId = noPositionId;
        stored.exists = true;

        state.nativePositionMetadata[yesPositionId] = LibEveMarket.NativePositionMetadata({
            moduleId: MODULE_BINARY,
            conditionId: conditionId,
            outcomeIndex: OUTCOME_YES,
            marketId: marketId,
            exists: true
        });
        state.nativePositionMetadata[noPositionId] = LibEveMarket.NativePositionMetadata({
            moduleId: MODULE_BINARY,
            conditionId: conditionId,
            outcomeIndex: OUTCOME_NO,
            marketId: marketId,
            exists: true
        });

        emit Events.NativeBinaryConditionPrepared(marketId, conditionId, yesPositionId, noPositionId);

        ids = BinaryPositionIds({
            marketId: marketId, conditionId: conditionId, yesPositionId: yesPositionId, noPositionId: noPositionId
        });
    }

    function requireBinaryCondition(LibEveMarket.EveMarketStorage storage state, bytes32 marketId)
        internal
        view
        returns (BinaryPositionIds memory ids)
    {
        LibEveMarket.NativeBinaryCondition storage condition = state.nativeBinaryConditions[marketId];
        if (!condition.exists) {
            revert Errors.NativeBinaryConditionNotFound(marketId);
        }

        ids = BinaryPositionIds({
            marketId: condition.marketId,
            conditionId: condition.conditionId,
            yesPositionId: condition.yesPositionId,
            noPositionId: condition.noPositionId
        });
    }

    function requireCLOBMarket(LibEveMarket.EveMarketStorage storage state, bytes32 marketId)
        internal
        view
        returns (LibEveMarket.Market storage market)
    {
        market = state.markets[marketId];
        if (market.marketId != marketId) {
            revert Errors.MarketNotFound(marketId);
        }
        if (market.marketType != LibEveMarket.MarketType.CLOB) {
            revert Errors.NotCLOBMarket(marketId);
        }
    }
}
