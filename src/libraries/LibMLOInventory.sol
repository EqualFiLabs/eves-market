// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IMLOPredictionAdapterFacet} from "../interfaces/IMLOPredictionAdapterFacet.sol";
import {LibEveMarket} from "./LibEveMarket.sol";

library LibMLOInventory {
    function availableOutcome(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bucketId,
        bytes32 marketId,
        uint8 outcomeIndex
    ) internal view returns (uint256 available) {
        uint256 inventory = state.mloBucketOutcomeInventory[bucketId][marketId][outcomeIndex];
        uint256 reserved = state.mloBucketOutcomeInventoryReserved[bucketId][marketId][outcomeIndex];
        available = inventory > reserved ? inventory - reserved : 0;
    }

    function reserveForCurve(
        LibEveMarket.EveMarketStorage storage state,
        uint256 curveId,
        bytes32 bucketId,
        bytes32 marketId,
        uint8 outcomeIndex,
        uint256 capacity
    ) internal returns (uint256 inventoryReserved) {
        uint256 available = availableOutcome(state, bucketId, marketId, outcomeIndex);
        inventoryReserved = capacity < available ? capacity : available;
        if (inventoryReserved == 0) return 0;

        state.mloCurveInventoryReserved[curveId] += inventoryReserved;
        state.mloBucketOutcomeInventoryReserved[bucketId][marketId][outcomeIndex] += inventoryReserved;
    }

    function rebalanceCurve(
        LibEveMarket.EveMarketStorage storage state,
        uint256 curveId,
        bytes32 bucketId,
        bytes32 marketId,
        uint8 outcomeIndex,
        uint256 capacity
    ) internal returns (uint256 shifted) {
        uint256 available = availableOutcome(state, bucketId, marketId, outcomeIndex);
        shifted = available < capacity ? available : capacity;
        if (shifted == 0) return 0;

        state.mloCurveInventoryReserved[curveId] += shifted;
        state.mloBucketOutcomeInventoryReserved[bucketId][marketId][outcomeIndex] += shifted;
    }

    function consumeCurveInventory(
        LibEveMarket.EveMarketStorage storage state,
        uint256 curveId,
        bytes32 bucketId,
        bytes32 marketId,
        uint8 outcomeIndex,
        uint256 amount
    ) internal {
        uint256 curveReserved = state.mloCurveInventoryReserved[curveId];
        if (amount > curveReserved) {
            revert IMLOPredictionAdapterFacet.MLOInsufficientCurveInventory(bucketId, marketId, amount, curveReserved);
        }
        state.mloCurveInventoryReserved[curveId] = curveReserved - amount;
        state.mloBucketOutcomeInventoryReserved[bucketId][marketId][outcomeIndex] -= amount;
        state.mloBucketOutcomeInventory[bucketId][marketId][outcomeIndex] -= amount;
    }

    function releaseCurveInventory(
        LibEveMarket.EveMarketStorage storage state,
        uint256 curveId,
        bytes32 bucketId,
        bytes32 marketId,
        uint8 outcomeIndex
    ) internal returns (uint256 released) {
        released = state.mloCurveInventoryReserved[curveId];
        if (released == 0) return 0;
        state.mloCurveInventoryReserved[curveId] = 0;
        state.mloBucketOutcomeInventoryReserved[bucketId][marketId][outcomeIndex] -= released;
    }

    function releaseCurveInventoryAmount(
        LibEveMarket.EveMarketStorage storage state,
        uint256 curveId,
        bytes32 bucketId,
        bytes32 marketId,
        uint8 outcomeIndex,
        uint256 amount
    ) internal {
        uint256 curveReserved = state.mloCurveInventoryReserved[curveId];
        if (amount > curveReserved) {
            revert IMLOPredictionAdapterFacet.MLOInsufficientCurveInventory(bucketId, marketId, amount, curveReserved);
        }
        if (amount == 0) return;

        state.mloCurveInventoryReserved[curveId] = curveReserved - amount;
        state.mloBucketOutcomeInventoryReserved[bucketId][marketId][outcomeIndex] -= amount;
    }

    function addOutcome(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bucketId,
        bytes32 marketId,
        uint8 outcomeIndex,
        uint256 amount
    ) internal {
        if (amount != 0) state.mloBucketOutcomeInventory[bucketId][marketId][outcomeIndex] += amount;
    }

    function completeSetAvailable(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bucketId,
        bytes32 marketId,
        uint8 outcomeCount
    ) internal view returns (uint256 available) {
        available = type(uint256).max;
        for (uint8 outcome; outcome < outcomeCount; ++outcome) {
            uint256 outcomeAvailable = availableOutcome(state, bucketId, marketId, outcome);
            if (outcomeAvailable < available) available = outcomeAvailable;
        }
    }

    function removeCompleteSet(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bucketId,
        bytes32 marketId,
        uint8 outcomeCount,
        uint256 amount
    ) internal {
        uint256 available = completeSetAvailable(state, bucketId, marketId, outcomeCount);
        if (amount == 0 || amount > available) {
            revert IMLOPredictionAdapterFacet.MLOInsufficientUnreservedInventory(bucketId, marketId, amount, available);
        }
        for (uint8 outcome; outcome < outcomeCount; ++outcome) {
            state.mloBucketOutcomeInventory[bucketId][marketId][outcome] -= amount;
        }
    }

    function requireNoReservations(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bucketId,
        bytes32 marketId,
        uint8 outcomeCount
    ) internal view {
        for (uint8 outcome; outcome < outcomeCount; ++outcome) {
            uint256 reserved = state.mloBucketOutcomeInventoryReserved[bucketId][marketId][outcome];
            if (reserved != 0) {
                revert IMLOPredictionAdapterFacet.MLOInventoryReserved(bucketId, marketId, outcome, reserved);
            }
        }
    }

    function isEmpty(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bucketId,
        bytes32 marketId,
        uint8 outcomeCount
    ) internal view returns (bool empty) {
        empty = true;
        for (uint8 outcome; outcome < outcomeCount; ++outcome) {
            if (state.mloBucketOutcomeInventory[bucketId][marketId][outcome] != 0) return false;
        }
    }
}
