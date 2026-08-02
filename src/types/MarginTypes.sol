// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

library MarginTypes {
    enum BucketKind {
        MLO,
        PredictionTrader,
        Perp
    }

    enum BucketState {
        Healthy,
        Warning,
        ReduceOnly,
        Liquidatable,
        Recovering,
        Closed
    }

    enum RiskDomainOracleKind {
        None,
        BookMark
    }

    enum FundingMode {
        None,
        BorrowRate
    }

    struct MarginConfig {
        address marginAsset;
        bool warningRiskIncreaseAllowed;
    }

    struct RiskDomainOracleConfig {
        RiskDomainOracleKind kind;
        bytes32 oracleKey;
    }

    struct RiskParams {
        uint16 initialMarginBps;
        uint16 maintenanceMarginBps;
    }

    struct FundingConfig {
        FundingMode mode;
        bool initialized;
        uint64 lastUpdatedAt;
        uint128 ratePerSecondWad;
        uint256 cumulativeIndexWad;
    }

    enum BucketHealthStatus {
        Healthy,
        BelowInitial,
        BelowMaintenance
    }

    struct MarginAccount {
        uint256 depositedMargin;
        uint256 withdrawnMargin;
        uint256 freeMargin;
        uint256 allocatedMargin;
        uint256 realizedProfits;
        uint256 realizedLosses;
        uint256 fundingPaid;
        uint256 fundingBadDebt;
    }

    struct MarginBucket {
        address operator;
        bytes32 riskDomainId;
        BucketKind kind;
        uint256 marginAllocated;
        uint256 openOrderRisk;
        uint256 pendingFillRisk;
        uint256 positionRisk;
        uint256 vaultDebt;
        uint256 fundingLiability;
        uint256 fundingAccrued;
        uint256 fundingPaid;
        uint256 fundingBadDebt;
        uint256 fundingIndexWad;
        uint256 fundingRemainderWad;
        uint256 reservedRisk;
        uint256 activeRisk;
        uint256 realizedProfits;
        uint256 realizedLosses;
        uint256 unrealizedProfits;
        uint256 unrealizedLosses;
        uint256 recoveryProfits;
        uint256 recoveryLosses;
        uint256 badDebt;
        BucketState state;
        bool exists;
    }

    struct BucketRisk {
        uint256 openOrderRisk;
        uint256 pendingFillRisk;
        uint256 positionRisk;
        uint256 vaultDebt;
        uint256 fundingLiability;
        uint256 fundingBadDebt;
        uint256 realizedProfits;
        uint256 realizedLosses;
        uint256 unrealizedProfits;
        uint256 unrealizedLosses;
        uint256 recoveryProfits;
        uint256 recoveryLosses;
        uint256 badDebt;
        uint256 lockedRisk;
    }

    struct BucketHealth {
        uint256 marginEquity;
        uint256 exposure;
        uint256 initialRequirement;
        uint256 maintenanceRequirement;
        uint256 excessInitial;
        uint256 excessMaintenance;
        BucketHealthStatus status;
    }
}
