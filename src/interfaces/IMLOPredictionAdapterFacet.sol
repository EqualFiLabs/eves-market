// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {MLOPredictionTypes} from "../types/MLOPredictionTypes.sol";

interface IMLOPredictionAdapterFacet {
    error SeniorCapitalPoolNotSet();
    error InvalidSeniorCapitalPool(address pool);
    error MLOAdapterCurveNotFound(uint256 curveId);
    error MLOEnvelopeAlreadyBound(uint256 envelopeId, uint256 curveId);
    error MLOUnsupportedCurveSide(uint8 side);
    error MLOUnsupportedBook(bytes32 bookId);
    error MLOEnvelopeGenerationMismatch(uint32 expected, uint32 actual);
    error MLOInsufficientSeniorReservation(uint256 required, uint256 available);
    error MLOInventoryNotFound(bytes32 bucketId, bytes32 marketId);
    error MLOInventoryMarketUnresolved(bytes32 marketId);
    error MLOSeniorPoolMismatch(address expected, address actual);

    event SeniorCapitalPoolSet(address indexed previousPool, address indexed newPool);
    event MLOAskCurveCreated(uint256 indexed curveId, uint256 indexed envelopeId, bytes32 indexed bucketId);
    event MLOAskCurveUpdated(uint256 indexed curveId, uint256 indexed envelopeId, uint32 curveGeneration);
    event MLOAskCurveCancelled(
        uint256 indexed curveId, uint256 indexed envelopeId, uint256 seniorReleased, uint256 riskReleased
    );
    event MLOAskCurveFilled(
        uint256 indexed curveId,
        uint256 indexed envelopeId,
        bytes32 indexed bucketId,
        address receiver,
        uint128 collateralUsed,
        uint128 sharesOut,
        uint128 feePaid,
        uint256 retainedInventory
    );
    event MLOInventoryVaultCreated(bytes32 indexed bucketId, bytes32 indexed marketId, address vault);
    event MLOInventorySettled(
        bytes32 indexed bucketId,
        bytes32 indexed marketId,
        address indexed vault,
        uint256 collateralOut,
        uint256 seniorRepaid,
        uint256 marginUsed,
        uint256 seniorLoss,
        uint256 bucketProfit
    );

    function setSeniorCapitalPool(address pool) external;

    function seniorCapitalPool() external view returns (address pool);

    function createMLOAskCurve(MLOPredictionTypes.CreateMLOAskCurveParams calldata params)
        external
        returns (uint256 curveId);

    function updateMLOAskCurve(MLOPredictionTypes.UpdateMLOAskCurveParams calldata params)
        external
        returns (uint32 curveGeneration);

    function cancelMLOAskCurve(uint256 curveId) external;

    function fillMLOAskCurve(MLOPredictionTypes.FillMLOAskCurveParams calldata params)
        external
        returns (MLOPredictionTypes.FillResult memory result);

    function getMLOAskCurve(uint256 curveId) external view returns (MLOPredictionTypes.MLOAskCurveView memory curve);

    function getMLOInventory(bytes32 bucketId, bytes32 marketId)
        external
        view
        returns (MLOPredictionTypes.MLOInventoryView memory inventory);

    function settleMLOInventory(bytes32 bucketId, bytes32 marketId)
        external
        returns (MLOPredictionTypes.MLOInventorySettlement memory settlement);
}
