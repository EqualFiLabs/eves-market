// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {LibEveMarket} from "./LibEveMarket.sol";
import {LibMLOInventory} from "./LibMLOInventory.sol";
import {LibMLOMarket} from "./LibMLOMarket.sol";
import {LibMLOPredictionAdapter} from "./LibMLOPredictionAdapter.sol";

library LibMLOAutoMerge {
    function mergeAvailable(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId, bytes32 marketId)
        internal
        returns (uint256 merged)
    {
        if (
            state.mloBucketMarketSeniorDebt[bucketId][marketId] == 0
                || state.mloInventoryVaults[bucketId][marketId] == address(0)
        ) return 0;
        LibEveMarket.Market storage market = state.markets[marketId];
        if (market.marketId != marketId || LibMLOMarket.isResolved(state, market)) return 0;

        uint8 count = LibMLOMarket.outcomeCount(state, marketId);
        merged = type(uint256).max;
        for (uint8 outcome; outcome < count; ++outcome) {
            uint256 available = LibMLOInventory.availableOutcome(state, bucketId, marketId, outcome);
            if (available < merged) merged = available;
        }
        if (merged == 0 || merged == type(uint256).max) return 0;
        LibMLOPredictionAdapter.mergeCompleteSet(state, bucketId, marketId, merged);
    }
}
