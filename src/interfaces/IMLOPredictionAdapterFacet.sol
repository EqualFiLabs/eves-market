// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {MLOPredictionTypes} from "../types/MLOPredictionTypes.sol";

interface IMLOPredictionAdapterFacet {
    error MLOAdapterCurveNotFound(uint256 curveId);
    error MLOEnvelopeAlreadyBound(uint256 envelopeId, uint256 curveId);
    error MLOUnsupportedCurveSide(uint8 side);
    error MLOUnsupportedBook(bytes32 bookId);
    error MLOInvalidOutcomeIndex(uint8 outcomeIndex, uint8 outcomeCount);
    error MLOEnvelopeGenerationMismatch(uint32 expected, uint32 actual);
    error MLOInsufficientCurveBacking(uint256 required, uint256 available);
    error MLOInventoryNotFound(bytes32 bucketId, bytes32 marketId);
    error MLOInventoryMarketUnresolved(bytes32 marketId);
    error MLOInventoryMarketResolved(bytes32 marketId);
    error MLOInventoryReserved(bytes32 bucketId, bytes32 marketId, uint8 outcomeIndex, uint256 reserved);
    error MLOInsufficientCurveInventory(bytes32 bucketId, bytes32 marketId, uint256 required, uint256 available);
    error MLOInsufficientUnreservedInventory(bytes32 bucketId, bytes32 marketId, uint256 required, uint256 available);
    error MLOMergeCollateralMismatch(uint256 expected, uint256 actual);
    error MLOCollateralNonExactTransfer(uint256 expected, uint256 actual);
    error MLOInternalOnly(address caller);
    error InvalidMLOInsuranceFund(address fund);
    error InvalidMLOCollateral(address asset);
    error InvalidMLOFundingSplit(uint256 seniorFundingBps);
    error MLORecoveryNotEligible(bytes32 bucketId, uint8 healthStatus);
    error MLORecoveryCurveMismatch(uint256 curveId, bytes32 expectedBucketId, bytes32 actualBucketId);
    error MLOCurveCleanupNotAllowed(uint256 curveId, bytes32 bucketId);
    error MLOCleanupBatchTooLarge(uint256 supplied, uint256 maximum);
    error MLOEmptyBatch();

    event MLOCurveCreated(
        uint256 indexed curveId, uint256 indexed envelopeId, bytes32 indexed bucketId, uint8 side, uint8 outcomeIndex
    );
    event MLOCurveUpdated(uint256 indexed curveId, uint256 indexed envelopeId, uint32 curveGeneration);
    event MLOCurveReservationResized(
        uint256 indexed curveId,
        uint256 indexed envelopeId,
        uint256 previousRiskVolume,
        uint256 newRiskVolume,
        uint256 inventoryReserved,
        uint256 seniorReserved
    );
    event MLOCurveCancelled(
        uint256 indexed curveId,
        uint256 indexed envelopeId,
        uint256 inventoryReleased,
        uint256 seniorReleased,
        uint256 riskReleased
    );
    event MLOAskCurveFilled(
        uint256 indexed curveId,
        uint256 indexed envelopeId,
        bytes32 indexed bucketId,
        address receiver,
        uint128 collateralUsed,
        uint128 sharesOut,
        uint128 feePaid,
        uint256 inventoryUsed,
        uint256 seniorDeployed,
        uint256 seniorReleased,
        uint256 seniorRepaid,
        uint256 retainedInventory,
        uint256 makerProfit
    );
    event MLOAskCurveRebalanced(
        uint256 indexed curveId, bytes32 indexed bucketId, uint256 inventoryReserved, uint256 seniorReserved
    );
    event MLOBidCurveFilled(
        uint256 indexed curveId,
        uint256 indexed envelopeId,
        bytes32 indexed bucketId,
        address seller,
        address receiver,
        uint128 sharesIn,
        uint128 collateralOut,
        uint128 feePaid,
        uint256 seniorDeployed,
        uint256 seniorReleased,
        uint256 inventoryReceived
    );
    event MLOInventoryVaultCreated(bytes32 indexed bucketId, bytes32 indexed marketId, address vault);
    event MLOInventorySettled(
        bytes32 indexed bucketId,
        bytes32 indexed marketId,
        address indexed vault,
        uint256 collateralOut,
        uint256 seniorRepaid,
        uint256 marginUsed,
        uint256 fundingMarginUsed,
        uint256 seniorLoss,
        uint256 bucketProfit,
        uint256 fundingPaid
    );
    event MLOCompleteSetMerged(
        bytes32 indexed bucketId,
        bytes32 indexed marketId,
        address indexed vault,
        uint256 amount,
        uint256 collateralOut,
        uint256 seniorRepaid,
        uint256 bucketProfit,
        uint256 fundingPaid
    );
    event MLOFundingPaid(
        bytes32 indexed bucketId,
        address indexed insuranceFund,
        uint256 assets,
        uint256 seniorAmount,
        uint256 insuranceAmount,
        bool fromMargin
    );
    event MLORecoveryConfigSet(address indexed insuranceFund, uint16 seniorFundingBps, uint16 maxCleanupBatch);
    event MLOBucketStateSynchronized(bytes32 indexed bucketId, uint8 previousState, uint8 newState, uint8 healthStatus);
    event MLOCurveCleanupBatch(
        bytes32 indexed bucketId,
        address indexed caller,
        uint256 cleaned,
        uint256 inventoryReleased,
        uint256 seniorReleased,
        uint256 riskReleased
    );
    event MLOFundingWrittenOff(bytes32 indexed bucketId, uint256 assets);
    event MLOBucketClosed(
        bytes32 indexed bucketId, uint256 insuranceDraw, uint256 seniorLoss, uint256 fundingWrittenOff
    );

    function createMLOCurve(MLOPredictionTypes.CreateMLOCurveParams calldata params) external returns (uint256 curveId);

    function postMLOCurve(MLOPredictionTypes.PostMLOCurveParams calldata params)
        external
        returns (uint256 envelopeId, uint256 curveId);

    function postMLOCurvesBatch(MLOPredictionTypes.PostMLOCurveParams[] calldata params)
        external
        returns (MLOPredictionTypes.MLOCurveIds[] memory ids);

    function updateMLOCurve(MLOPredictionTypes.UpdateMLOCurveParams calldata params)
        external
        returns (uint32 curveGeneration);

    function updateMLOCurvesBatch(MLOPredictionTypes.UpdateMLOCurveParams[] calldata params)
        external
        returns (uint32[] memory curveGenerations);

    function updateMLOCurveFromNow(MLOPredictionTypes.UpdateMLOCurveParams calldata params)
        external
        returns (uint32 curveGeneration);

    function updateMLOCurvesFromNowBatch(MLOPredictionTypes.UpdateMLOCurveParams[] calldata params)
        external
        returns (uint32[] memory curveGenerations);

    function cancelMLOCurve(uint256 curveId) external;

    function rebalanceMLOAskCurve(uint256 curveId) external returns (uint256 inventoryReserved, uint256 seniorReserved);

    function fillMLOAskCurve(MLOPredictionTypes.FillMLOAskCurveParams calldata params)
        external
        returns (MLOPredictionTypes.MLOAskFillResult memory result);

    function fillMLOBidCurve(MLOPredictionTypes.FillMLOBidCurveParams calldata params)
        external
        returns (MLOPredictionTypes.MLOBidFillResult memory result);

    function getMLOCurve(uint256 curveId) external view returns (MLOPredictionTypes.MLOCurveView memory curve);

    function getMLOInventory(bytes32 bucketId, bytes32 marketId)
        external
        view
        returns (MLOPredictionTypes.MLOInventoryView memory inventory);

    function getMLOScenarioExposure(bytes32 bucketId)
        external
        view
        returns (MLOPredictionTypes.MLOScenarioExposureView memory exposure);

    function settleMLOInventory(bytes32 bucketId, bytes32 marketId)
        external
        returns (MLOPredictionTypes.MLOInventorySettlement memory settlement);

    function mergeMLOCompleteSet(bytes32 bucketId, bytes32 marketId, uint256 amount)
        external
        returns (MLOPredictionTypes.MLOCompleteSetMerge memory result);

    function mergeAvailableMLOCompleteSet(bytes32 bucketId, bytes32 marketId) external returns (uint256 merged);

    function previewMLOFunding(bytes32 bucketId)
        external
        view
        returns (MLOPredictionTypes.MLOFundingView memory funding);

    function mloRecoveryConfig() external view returns (MLOPredictionTypes.MLORecoveryConfig memory config);

    function setMLORecoveryConfig(address insuranceFund, uint16 seniorFundingBps, uint16 maxCleanupBatch) external;

    function synchronizeMLOBucketState(bytes32 bucketId) external returns (uint8 newState);

    function cleanupMLOCurves(bytes32 bucketId, uint256[] calldata curveIds)
        external
        returns (MLOPredictionTypes.MLOCurveCleanupResult memory result);

    function settleMLOFunding(bytes32 bucketId, uint256 maxAssets) external returns (uint256 paid);

    function executeMLOAskAssetSettlement(MLOPredictionTypes.MLOAskAssetSettlementParams calldata params) external;

    function prepareMLOAskBacking(uint256 curveId, uint128 sharesOut, uint128 grossCost, uint128 price)
        external
        returns (MLOPredictionTypes.MLOAskBacking memory backing);

    function applyMLOAskFillState(MLOPredictionTypes.MLOAskFillStateParams calldata params) external;

    function executeMLOBidAssetSettlement(MLOPredictionTypes.MLOBidAssetSettlementParams calldata params) external;

    function executeMLOAskFromRoute(MLOPredictionTypes.MLOAskFillRequest calldata request)
        external
        returns (MLOPredictionTypes.MLOAskFillResult memory result);

    function executeMLOBidFromRoute(MLOPredictionTypes.MLOBidFillRequest calldata request)
        external
        returns (MLOPredictionTypes.MLOBidFillResult memory result);
}
