// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {CurveCLOBTypes} from "./CurveCLOBTypes.sol";
import {QuoteEnvelopeTypes} from "./QuoteEnvelopeTypes.sol";

library MLOPredictionTypes {
    struct CreateMLOCurveParams {
        uint256 envelopeId;
        uint24 durationMinutes;
    }

    struct PostMLOCurveParams {
        QuoteEnvelopeTypes.CreateQuoteEnvelopeParams envelope;
        uint24 durationMinutes;
    }

    struct MLOCurveIds {
        uint256 envelopeId;
        uint256 curveId;
    }

    struct UpdateMLOCurveParams {
        uint256 curveId;
        QuoteEnvelopeTypes.QuoteEnvelopeUpdate envelopeUpdate;
        uint32 expectedCurveGeneration;
        uint32 expectedEnvelopeGeneration;
    }

    struct FillMLOAskCurveParams {
        uint256 curveId;
        uint128 collateralIn;
        uint128 minSharesOut;
        uint32 expectedGeneration;
        bytes32 expectedCommitment;
        address receiver;
    }

    struct MLOAskFillRequest {
        uint256 curveId;
        uint128 collateralIn;
        uint128 minSharesOut;
        uint32 expectedGeneration;
        bytes32 expectedCommitment;
        address fundingSource;
        address taker;
        address receiver;
        bool fundingIsEscrowed;
    }

    struct FillMLOBidCurveParams {
        uint256 curveId;
        uint128 sharesIn;
        uint128 minCollateralOut;
        uint32 expectedGeneration;
        bytes32 expectedCommitment;
        address receiver;
    }

    struct MLOBidFillRequest {
        uint256 curveId;
        uint128 sharesIn;
        uint128 minCollateralOut;
        uint32 expectedGeneration;
        bytes32 expectedCommitment;
        address source;
        address seller;
        address receiver;
    }

    struct MLOCurveView {
        uint256 curveId;
        uint256 envelopeId;
        bytes32 bucketId;
        bytes32 bookId;
        bytes32 marketId;
        uint8 side;
        uint8 outcomeIndex;
        uint8 outcomeCount;
        address operator;
        uint128 remainingVolume;
        uint256 inventoryReserved;
        uint256 seniorReserved;
        bool active;
        bool envelopeActive;
        uint32 curveGeneration;
        uint32 envelopeGeneration;
    }

    struct MLOInventoryView {
        bytes32 bucketId;
        bytes32 marketId;
        address vault;
        uint8 outcomeCount;
        uint256[] inventory;
        uint256[] reserved;
        uint256[] available;
        uint256 seniorDebt;
        uint256 seniorReserved;
        uint256 positionRisk;
    }

    struct MLOInventorySettlement {
        bytes32 bucketId;
        bytes32 marketId;
        uint256 collateralOut;
        uint256 seniorRepaid;
        uint256 marginUsed;
        uint256 fundingMarginUsed;
        uint256 seniorLoss;
        uint256 bucketProfit;
        uint256 fundingPaid;
        uint256 insuranceDraw;
        uint256 fundingWrittenOff;
    }

    struct MLOAskFillResult {
        CurveCLOBTypes.FillBestResult fill;
        uint256 envelopeId;
        bytes32 bucketId;
        uint256 seniorDeployed;
        uint256 seniorReleased;
        uint256 seniorRepaid;
        uint256 inventoryUsed;
        uint256 retainedInventory;
        uint256 makerProfit;
    }

    struct MLOAskBacking {
        uint128 inventoryUsed;
        uint128 manufacturedShares;
        uint128 seniorDeployed;
        uint128 seniorReleased;
        uint128 seniorRepaid;
        uint128 fundingPaid;
        uint128 bucketProfit;
    }

    struct MLOAskFillStateParams {
        uint256 curveId;
        uint128 sharesOut;
        uint128 price;
        uint128 collateralUsed;
        uint128 feePaid;
        MLOAskBacking backing;
    }

    struct MLOBidFillResult {
        CurveCLOBTypes.SellBookResult fill;
        uint256 envelopeId;
        bytes32 bucketId;
        uint256 seniorDeployed;
        uint256 seniorReleased;
        uint256 inventoryReceived;
    }

    struct MLOCompleteSetMerge {
        bytes32 bucketId;
        bytes32 marketId;
        uint256 amount;
        uint256 collateralOut;
        uint256 seniorRepaid;
        uint256 bucketProfit;
        uint256 fundingPaid;
    }

    struct MLOAskAssetSettlementParams {
        address collateralToken;
        address positionToken;
        address inventoryVault;
        address receiver;
        bytes32 bucketId;
        bytes32 bookId;
        bytes32 conditionId;
        bytes32 resolutionId;
        uint256 soldPositionId;
        uint256[] retainedPositionIds;
        uint8 positionTokenType;
        uint128 inventoryUsed;
        uint128 manufacturedShares;
        uint128 seniorDeployed;
        uint128 seniorReleased;
        uint128 seniorRepaid;
        uint128 fundingPaid;
        uint128 feePaid;
    }

    struct MLOFundingView {
        uint256 ratePerSecondWad;
        uint256 cumulativeIndexWad;
        uint256 accrued;
        uint256 paid;
        uint256 liability;
        uint256 pending;
        uint256 remainderWad;
    }

    struct MLORecoveryConfig {
        address insuranceFund;
        uint16 seniorFundingBps;
        uint16 maxCleanupBatch;
    }

    struct MLOCurveCleanupResult {
        uint256 cleaned;
        uint256 inventoryReleased;
        uint256 seniorReleased;
        uint256 riskReleased;
    }

    struct MLOBidAssetSettlementParams {
        address collateralToken;
        address positionToken;
        address inventoryVault;
        address source;
        address receiver;
        bytes32 bucketId;
        bytes32 bookId;
        uint256 positionId;
        uint128 sharesIn;
        uint128 grossPayment;
        uint128 collateralOut;
        uint128 feePaid;
        uint128 seniorReleased;
    }

    struct MLOScenarioExposureView {
        bytes32 bucketId;
        bytes32 marketId;
        uint8 outcomeCount;
        bool initialized;
        int256[] openLosses;
        int256[] filledPositionLosses;
        int256[] aggregateLosses;
        int256[] effectiveLosses;
        int256 maximumSignedLoss;
        int256 maximumRawLoss;
        int256 maximumEffectiveLoss;
        uint256 funding;
        uint256 initialRequirement;
        uint256 maintenanceRequirement;
    }
}
