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

    function createMLOCurve(MLOPredictionTypes.CreateMLOCurveParams calldata params)
        external
        nonReentrant
        returns (uint256 curveId)
    {
        curveId = LibMLOPredictionAdapter.createCurve(LibEveMarket.store(), params);
    }

    function cancelMLOCurve(uint256 curveId) external nonReentrant {
        LibMLOPredictionAdapter.cancelCurve(LibEveMarket.store(), curveId);
    }

    function rebalanceMLOAskCurve(uint256 curveId)
        external
        nonReentrant
        returns (uint256 inventoryReserved, uint256 seniorReserved)
    {
        return LibMLOPredictionAdapter.rebalanceAskCurve(LibEveMarket.store(), curveId);
    }
}
