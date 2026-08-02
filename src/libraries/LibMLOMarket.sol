// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IMLOPredictionAdapterFacet} from "../interfaces/IMLOPredictionAdapterFacet.sol";
import {LibEveMarket} from "./LibEveMarket.sol";
import {LibMLOScenarioMath} from "./LibMLOScenarioMath.sol";

library LibMLOMarket {
    function outcomeCount(LibEveMarket.EveMarketStorage storage state, bytes32 marketId)
        internal
        view
        returns (uint8 count)
    {
        LibEveMarket.MultiOutcomeMarket storage multi = state.multiOutcomeMarkets[marketId];
        count = multi.exists ? multi.outcomeCount : 2;
        LibMLOScenarioMath.validateOutcomeCount(count);
    }

    function positionId(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.Market storage market,
        uint8 outcomeIndex
    ) internal view returns (uint256 id) {
        uint8 count = outcomeCount(state, market.marketId);
        if (outcomeIndex >= count) {
            revert IMLOPredictionAdapterFacet.MLOInvalidOutcomeIndex(outcomeIndex, count);
        }
        if (state.multiOutcomeMarkets[market.marketId].exists) {
            return state.multiOutcomePositionIds[market.marketId][outcomeIndex];
        }
        id = outcomeIndex == 0 ? market.yesPositionId : market.noPositionId;
    }

    function positionIds(LibEveMarket.EveMarketStorage storage state, LibEveMarket.Market storage market)
        internal
        view
        returns (uint256[] memory ids)
    {
        uint8 count = outcomeCount(state, market.marketId);
        ids = new uint256[](count);
        for (uint8 outcome; outcome < count; ++outcome) {
            ids[outcome] = positionId(state, market, outcome);
        }
    }

    function isResolved(LibEveMarket.EveMarketStorage storage state, LibEveMarket.Market storage market)
        internal
        view
        returns (bool)
    {
        LibEveMarket.MultiOutcomeMarket storage multi = state.multiOutcomeMarkets[market.marketId];
        return multi.exists ? multi.resolved : market.outcome != LibEveMarket.MarketOutcome.Unresolved;
    }

    function resolutionPayout(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bucketId,
        LibEveMarket.Market storage market
    ) internal view returns (uint256 payout) {
        LibEveMarket.MultiOutcomeMarket storage multi = state.multiOutcomeMarkets[market.marketId];
        if (!multi.exists) {
            if (market.outcome == LibEveMarket.MarketOutcome.Yes) {
                return state.mloBucketOutcomeInventory[bucketId][market.marketId][0];
            }
            if (market.outcome == LibEveMarket.MarketOutcome.No) {
                return state.mloBucketOutcomeInventory[bucketId][market.marketId][1];
            }
            return state.mloBucketOutcomeInventory[bucketId][market.marketId][0] / 2
                + state.mloBucketOutcomeInventory[bucketId][market.marketId][1] / 2;
        }
        if (!multi.invalid) {
            return state.mloBucketOutcomeInventory[bucketId][market.marketId][multi.resolvedOutcome];
        }
        for (uint8 outcome; outcome < multi.outcomeCount; ++outcome) {
            payout += state.mloBucketOutcomeInventory[bucketId][market.marketId][outcome] / multi.outcomeCount;
        }
    }
}
