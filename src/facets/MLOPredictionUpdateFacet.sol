// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {MLOPredictionTypes} from "../types/MLOPredictionTypes.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibMLOPredictionAdapter} from "../libraries/LibMLOPredictionAdapter.sol";
import {LibReentrancy} from "../libraries/LibReentrancy.sol";

contract MLOPredictionUpdateFacet {
    modifier nonReentrant() {
        LibReentrancy.enter();
        _;
        LibReentrancy.exit();
    }

    function updateMLOCurve(MLOPredictionTypes.UpdateMLOCurveParams calldata params)
        external
        nonReentrant
        returns (uint32 curveGeneration)
    {
        curveGeneration = LibMLOPredictionAdapter.updateCurve(LibEveMarket.store(), params);
    }

    function updateMLOCurvesBatch(MLOPredictionTypes.UpdateMLOCurveParams[] calldata params)
        external
        nonReentrant
        returns (uint32[] memory curveGenerations)
    {
        curveGenerations = LibMLOPredictionAdapter.updateCurvesBatch(LibEveMarket.store(), params, false);
    }

    function updateMLOCurveFromNow(MLOPredictionTypes.UpdateMLOCurveParams calldata params)
        external
        nonReentrant
        returns (uint32 curveGeneration)
    {
        curveGeneration = LibMLOPredictionAdapter.updateCurveFromNow(LibEveMarket.store(), params);
    }

    function updateMLOCurvesFromNowBatch(MLOPredictionTypes.UpdateMLOCurveParams[] calldata params)
        external
        nonReentrant
        returns (uint32[] memory curveGenerations)
    {
        curveGenerations = LibMLOPredictionAdapter.updateCurvesBatch(LibEveMarket.store(), params, true);
    }
}
