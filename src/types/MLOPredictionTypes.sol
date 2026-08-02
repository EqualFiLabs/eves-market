// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {CurveCLOBTypes} from "./CurveCLOBTypes.sol";
import {QuoteEnvelopeTypes} from "./QuoteEnvelopeTypes.sol";

library MLOPredictionTypes {
    struct CreateMLOAskCurveParams {
        uint256 envelopeId;
        uint24 durationMinutes;
    }

    struct UpdateMLOAskCurveParams {
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

    struct MLOFillRequest {
        uint256 curveId;
        uint128 collateralIn;
        uint128 minSharesOut;
        uint32 expectedGeneration;
        bytes32 expectedCommitment;
        address payer;
        address receiver;
        bool payerIsEscrowed;
    }

    struct MLOAskCurveView {
        uint256 curveId;
        uint256 envelopeId;
        bytes32 bucketId;
        bytes32 bookId;
        bytes32 marketId;
        bool isYesSide;
        address operator;
        address seniorPool;
        uint128 remainingVolume;
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
        uint256 yesInventory;
        uint256 noInventory;
        uint256 seniorDebt;
        uint256 positionRisk;
    }

    struct MLOInventorySettlement {
        bytes32 bucketId;
        bytes32 marketId;
        uint256 collateralOut;
        uint256 seniorRepaid;
        uint256 marginUsed;
        uint256 seniorLoss;
        uint256 bucketProfit;
    }

    struct FillResult {
        CurveCLOBTypes.FillBestResult fill;
        uint256 envelopeId;
        bytes32 bucketId;
        uint256 seniorDeployed;
        uint256 seniorRepaid;
        uint256 retainedInventory;
    }
}
