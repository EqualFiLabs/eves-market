// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {MLOPredictionTypes} from "../types/MLOPredictionTypes.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibMLOPredictionAdapter} from "../libraries/LibMLOPredictionAdapter.sol";
import {LibReentrancy} from "../libraries/LibReentrancy.sol";

contract MLOPredictionCurveFacet {
    modifier nonReentrant() {
        LibReentrancy.enter();
        _;
        LibReentrancy.exit();
    }

    function createMLOAskCurve(MLOPredictionTypes.CreateMLOAskCurveParams calldata params)
        external
        nonReentrant
        returns (uint256 curveId)
    {
        curveId = LibMLOPredictionAdapter.createAskCurve(LibEveMarket.store(), params);
    }

    function updateMLOAskCurve(MLOPredictionTypes.UpdateMLOAskCurveParams calldata params)
        external
        returns (uint32 curveGeneration)
    {
        curveGeneration = LibMLOPredictionAdapter.updateAskCurve(LibEveMarket.store(), params);
    }

    function cancelMLOAskCurve(uint256 curveId) external {
        LibMLOPredictionAdapter.cancelAskCurve(LibEveMarket.store(), curveId);
    }
}
