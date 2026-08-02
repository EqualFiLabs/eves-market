// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {MLOPredictionTypes} from "../types/MLOPredictionTypes.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibMLOPredictionAdapter} from "../libraries/LibMLOPredictionAdapter.sol";
import {LibReentrancy} from "../libraries/LibReentrancy.sol";

contract MLOPredictionPostFacet {
    modifier nonReentrant() {
        LibReentrancy.enter();
        _;
        LibReentrancy.exit();
    }

    function postMLOCurve(MLOPredictionTypes.PostMLOCurveParams calldata params)
        external
        nonReentrant
        returns (uint256 envelopeId, uint256 curveId)
    {
        return LibMLOPredictionAdapter.postCurve(LibEveMarket.store(), params);
    }

    function postMLOCurvesBatch(MLOPredictionTypes.PostMLOCurveParams[] calldata params)
        external
        nonReentrant
        returns (MLOPredictionTypes.MLOCurveIds[] memory ids)
    {
        ids = LibMLOPredictionAdapter.postCurvesBatch(LibEveMarket.store(), params);
    }
}
