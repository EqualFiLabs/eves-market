// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

library MarkOracleTypes {
    enum OracleState {
        Uninitialized,
        Normal,
        Caution,
        Stale,
        Paused,
        ResolutionOnly
    }

    struct Observation {
        uint64 timestamp;
        uint64 blockNumber;
        uint128 price;
        uint256 priceCumulative;
        uint256 volumeCumulative;
        uint256 notionalCumulative;
    }

    struct OracleSnapshot {
        bytes32 bookId;
        bytes32 marketId;
        bool isYesSide;
        OracleState state;
        OracleState manualState;
        bool manualOverride;
        uint128 lastPrice;
        uint128 priceDenominator;
        uint64 lastUpdatedAt;
        uint64 lastUpdatedBlock;
        uint32 observationCount;
        uint256 priceCumulative;
        uint256 volumeCumulative;
        uint256 notionalCumulative;
    }

    struct OracleConfig {
        uint32 cautionThreshold;
        uint32 staleThreshold;
    }

    struct RiskMark {
        bytes32 oracleKey;
        OracleState state;
        uint128 displayPrice;
        uint128 assetRiskPrice;
        uint128 liabilityRiskPrice;
        uint128 priceDenominator;
        uint64 updatedAt;
    }

    struct RiskMarkConfig {
        uint32 lookbackSeconds;
        uint16 assetHaircutBps;
        uint16 liabilityPremiumBps;
    }

    struct BookOracle {
        uint128 lastPrice;
        uint64 lastUpdatedAt;
        uint64 lastUpdatedBlock;
        uint32 observationCount;
        uint8 ringIndex;
        bool manualOverride;
        OracleState manualState;
        uint256 priceCumulative;
        uint256 volumeCumulative;
        uint256 notionalCumulative;
        Observation[32] observations;
    }
}
