// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IMLOPredictionAdapterFacet} from "../interfaces/IMLOPredictionAdapterFacet.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibMLOPredictionFill} from "../libraries/LibMLOPredictionFill.sol";
import {MLOPredictionTypes} from "../types/MLOPredictionTypes.sol";

contract MLOPredictionAskRouteFacet {
    function executeMLOAskFromRoute(MLOPredictionTypes.MLOAskFillRequest calldata request)
        external
        returns (MLOPredictionTypes.MLOAskFillResult memory result)
    {
        if (msg.sender != address(this)) revert IMLOPredictionAdapterFacet.MLOInternalOnly(msg.sender);
        result = LibMLOPredictionFill.fillAskCurve(LibEveMarket.store(), request);
    }
}
