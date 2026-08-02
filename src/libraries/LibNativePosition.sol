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
    bytes32 internal constant NEGRISK_CONDITION_DOMAIN = keccak256("EVE_NATIVE_NEGRISK_CONDITION");
    bytes32 internal constant COMBO_CONDITION_DOMAIN = keccak256("EVE_NATIVE_COMBO_CONDITION");
    bytes32 internal constant POSITION_DOMAIN = keccak256("EVE_NATIVE_POSITION");

    struct BinaryPositionIds {
        bytes32 marketId;
        bytes32 conditionId;
        uint256 yesPositionId;
        uint256 noPositionId;
    }

    struct NegRiskPositionIds {
        bytes32 marketId;
        bytes32 conditionId;
        uint256 yesPositionId;
        uint256 noPositionId;
        uint8 excludedOutcome;
    }

    function binaryConditionIdFor(bytes32 marketId) internal pure returns (bytes32 conditionId) {
        conditionId = keccak256(abi.encode(BINARY_CONDITION_DOMAIN, marketId));
    }

    function negRiskConditionIdFor(bytes32 marketId, uint8 excludedOutcome)
        internal
        pure
        returns (bytes32 conditionId)
    {
        conditionId = keccak256(abi.encode(NEGRISK_CONDITION_DOMAIN, marketId, excludedOutcome));
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

    function prepareNegRiskCondition(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 marketId,
        uint8 excludedOutcome
    ) internal returns (NegRiskPositionIds memory ids) {
        LibEveMarket.MultiOutcomeMarket storage multi = state.multiOutcomeMarkets[marketId];
        if (!multi.exists) {
            revert Errors.MultiOutcomeMarketNotFound(marketId);
        }
        if (excludedOutcome >= multi.outcomeCount) {
            revert Errors.InvalidOutcome(excludedOutcome);
        }

        bytes32 storedConditionId = state.nativeNegRiskConditionIds[marketId][excludedOutcome];
        if (storedConditionId != bytes32(0)) {
            return negRiskPositionIds(state.nativeNegRiskConditions[storedConditionId]);
        }

        bytes32 conditionId = negRiskConditionIdFor(marketId, excludedOutcome);
        uint256 yesPositionId = state.multiOutcomePositionIds[marketId][excludedOutcome];
        if (yesPositionId == 0) {
            revert Errors.NativePositionNotFound(yesPositionId);
        }
        uint256 noPositionId = positionIdFor(MODULE_NEGRISK, conditionId, OUTCOME_NO);

        LibEveMarket.NativeNegRiskCondition storage condition = state.nativeNegRiskConditions[conditionId];
        condition.marketId = marketId;
        condition.conditionId = conditionId;
        condition.yesPositionId = yesPositionId;
        condition.noPositionId = noPositionId;
        condition.excludedOutcome = excludedOutcome;
        condition.exists = true;
        state.nativeNegRiskConditionIds[marketId][excludedOutcome] = conditionId;

        state.nativePositionMetadata[yesPositionId] = LibEveMarket.NativePositionMetadata({
            moduleId: MODULE_NEGRISK,
            conditionId: conditionId,
            outcomeIndex: OUTCOME_YES,
            marketId: marketId,
            exists: true
        });
        state.nativePositionMetadata[noPositionId] = LibEveMarket.NativePositionMetadata({
            moduleId: MODULE_NEGRISK,
            conditionId: conditionId,
            outcomeIndex: OUTCOME_NO,
            marketId: marketId,
            exists: true
        });

        emit Events.NativeNegRiskConditionPrepared(marketId, conditionId, excludedOutcome, yesPositionId, noPositionId);
        ids = negRiskPositionIds(condition);
    }

    function requireNegRiskCondition(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 marketId,
        uint8 excludedOutcome
    ) internal view returns (NegRiskPositionIds memory ids) {
        bytes32 conditionId = state.nativeNegRiskConditionIds[marketId][excludedOutcome];
        if (conditionId == bytes32(0)) {
            revert Errors.NativeNegRiskConditionNotFound(marketId, excludedOutcome);
        }
        ids = negRiskPositionIds(state.nativeNegRiskConditions[conditionId]);
    }

    function requireNegRiskConditionById(LibEveMarket.EveMarketStorage storage state, bytes32 conditionId)
        internal
        view
        returns (LibEveMarket.NativeNegRiskCondition storage condition)
    {
        condition = state.nativeNegRiskConditions[conditionId];
        if (!condition.exists) {
            revert Errors.NativeConditionNotFound(conditionId);
        }
    }

    function negRiskPositionIds(LibEveMarket.NativeNegRiskCondition storage condition)
        internal
        view
        returns (NegRiskPositionIds memory ids)
    {
        ids = NegRiskPositionIds({
            marketId: condition.marketId,
            conditionId: condition.conditionId,
            yesPositionId: condition.yesPositionId,
            noPositionId: condition.noPositionId,
            excludedOutcome: condition.excludedOutcome
        });
    }

    function flipPosition(LibEveMarket.EveMarketStorage storage state, uint256 positionId)
        internal
        view
        returns (uint256 flippedPositionId)
    {
        LibEveMarket.NativePositionMetadata storage metadata = state.nativePositionMetadata[positionId];
        if (!metadata.exists || !isBinaryOutcome(metadata.outcomeIndex)) {
            revert Errors.NativePositionNotFound(positionId);
        }
        if (metadata.moduleId == MODULE_BINARY) {
            flippedPositionId = positionIdFor(MODULE_BINARY, metadata.conditionId, metadata.outcomeIndex ^ 1);
        } else if (metadata.moduleId == MODULE_NEGRISK) {
            LibEveMarket.NativeNegRiskCondition storage condition =
                requireNegRiskConditionById(state, metadata.conditionId);
            flippedPositionId = metadata.outcomeIndex == OUTCOME_YES ? condition.noPositionId : condition.yesPositionId;
        } else {
            revert Errors.NativeModuleUnsupported(metadata.moduleId);
        }
        if (!state.nativePositionMetadata[flippedPositionId].exists) {
            revert Errors.NativePositionNotFound(flippedPositionId);
        }
    }

    function positionPayoutNumerator(LibEveMarket.EveMarketStorage storage state, uint256 positionId)
        internal
        view
        returns (bool resolved, uint256 payoutNumerator)
    {
        LibEveMarket.NativePositionMetadata storage metadata = state.nativePositionMetadata[positionId];
        if (!metadata.exists) {
            revert Errors.NativePositionNotFound(positionId);
        }
        if (metadata.moduleId == MODULE_BINARY) {
            LibEveMarket.Market storage market = state.markets[metadata.marketId];
            if (market.state != LibEveMarket.MarketState.Resolved) return (false, 0);
            return (true, binaryPayoutNumerator(market.outcome, metadata.outcomeIndex));
        }
        if (metadata.moduleId == MODULE_NEGRISK) {
            LibEveMarket.NativeNegRiskCondition storage condition =
                requireNegRiskConditionById(state, metadata.conditionId);
            LibEveMarket.MultiOutcomeMarket storage multi = state.multiOutcomeMarkets[condition.marketId];
            if (!multi.resolved) return (false, 0);
            if (multi.invalid) {
                uint256 yesNumerator = RESULT_DENOMINATOR / multi.outcomeCount;
                if (metadata.outcomeIndex == OUTCOME_YES) return (true, yesNumerator);
                uint256 yesNumeratorUp = (RESULT_DENOMINATOR + multi.outcomeCount - 1) / multi.outcomeCount;
                return (true, RESULT_DENOMINATOR - yesNumeratorUp);
            }
            bool excludedWon = multi.resolvedOutcome == condition.excludedOutcome;
            if (metadata.outcomeIndex == OUTCOME_YES) {
                return (true, excludedWon ? RESULT_DENOMINATOR : 0);
            }
            return (true, excludedWon ? 0 : RESULT_DENOMINATOR);
        }
        revert Errors.NativeModuleUnsupported(metadata.moduleId);
    }

    function positionPayout(LibEveMarket.EveMarketStorage storage state, uint256 positionId, uint128 amount)
        internal
        view
        returns (bool resolved, uint128 collateralOut)
    {
        LibEveMarket.NativePositionMetadata storage metadata = state.nativePositionMetadata[positionId];
        if (!metadata.exists) {
            revert Errors.NativePositionNotFound(positionId);
        }

        if (metadata.moduleId == MODULE_BINARY) {
            uint256 payoutNumerator;
            (resolved, payoutNumerator) = positionPayoutNumerator(state, positionId);
            if (!resolved) return (false, 0);
            collateralOut = uint128((uint256(amount) * payoutNumerator) / RESULT_DENOMINATOR);
            return (true, collateralOut);
        }

        if (metadata.moduleId == MODULE_NEGRISK) {
            LibEveMarket.NativeNegRiskCondition storage condition =
                requireNegRiskConditionById(state, metadata.conditionId);
            LibEveMarket.MultiOutcomeMarket storage multi = state.multiOutcomeMarkets[condition.marketId];
            if (!multi.resolved) return (false, 0);

            if (multi.invalid) {
                if (metadata.outcomeIndex == OUTCOME_YES) {
                    return (true, uint128(uint256(amount) / multi.outcomeCount));
                }
                uint256 yesPayoutUp = (uint256(amount) + multi.outcomeCount - 1) / multi.outcomeCount;
                return (true, uint128(uint256(amount) - yesPayoutUp));
            }

            bool excludedWon = multi.resolvedOutcome == condition.excludedOutcome;
            if (metadata.outcomeIndex == OUTCOME_YES) return (true, excludedWon ? amount : 0);
            return (true, excludedWon ? 0 : amount);
        }

        revert Errors.NativeModuleUnsupported(metadata.moduleId);
    }

    function binaryPayoutNumerator(LibEveMarket.MarketOutcome outcome, uint8 outcomeIndex)
        internal
        pure
        returns (uint256 payoutNumerator)
    {
        if (outcome == LibEveMarket.MarketOutcome.Yes) {
            return outcomeIndex == OUTCOME_YES ? RESULT_DENOMINATOR : 0;
        }
        if (outcome == LibEveMarket.MarketOutcome.No) {
            return outcomeIndex == OUTCOME_NO ? RESULT_DENOMINATOR : 0;
        }
        if (outcome == LibEveMarket.MarketOutcome.Invalid) {
            return RESULT_DENOMINATOR / 2;
        }
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
