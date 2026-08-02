// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

library ProductAdapterTypes {
    enum CurveBackingKind {
        Escrow,
        Adapter
    }

    enum ProductAdapterKind {
        None,
        MLOPrediction,
        PredictionTrader,
        Perp
    }

    enum AdapterAction {
        Preview,
        Activate,
        Settle,
        ReduceOnly,
        Recover
    }

    struct AdapterCurveMetadata {
        CurveBackingKind backingKind;
        ProductAdapterKind adapterKind;
        bytes32 bucketId;
        bytes32 riskDomainId;
        bytes32 adapterDataKey;
        bool active;
    }

    struct RiskPreview {
        bytes32 bucketId;
        bytes32 riskDomainId;
        uint256 openOrderRisk;
        uint256 pendingFillRisk;
        uint256 positionRisk;
        uint256 vaultDebt;
        uint256 fundingLiability;
    }

    struct RiskDelta {
        uint256 openOrderRiskReleased;
        uint256 pendingFillRiskAdded;
        uint256 positionRiskAdded;
        uint256 vaultDebtAdded;
        uint256 fundingLiabilityAdded;
    }

    struct SettlementResult {
        uint128 baseAmount;
        uint128 quoteAmount;
        uint128 feeAmount;
        int256 realizedPnl;
        bytes32 inventoryKey;
    }

    struct InventoryReport {
        bytes32 bucketId;
        bytes32 inventoryKey;
        uint256 assetValue;
        uint256 liabilityValue;
    }

    struct FundingReport {
        bytes32 bucketId;
        uint256 fundingLiability;
        uint64 updatedAt;
    }

    struct RecoveryResult {
        bytes32 bucketId;
        uint256 marginSlashed;
        uint256 insuranceDraw;
        uint256 seniorLoss;
        int256 realizedPnl;
    }
}
