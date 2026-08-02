// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {MLOPredictionTypes} from "../types/MLOPredictionTypes.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibMLOPredictionFill} from "../libraries/LibMLOPredictionFill.sol";
import {LibReentrancy} from "../libraries/LibReentrancy.sol";

contract MLOPredictionTradeFacet {
    modifier nonReentrant() {
        LibReentrancy.enter();
        _;
        LibReentrancy.exit();
    }

    function fillMLOAskCurve(MLOPredictionTypes.FillMLOAskCurveParams calldata params)
        external
        nonReentrant
        returns (MLOPredictionTypes.MLOAskFillResult memory result)
    {
        address receiver = params.receiver == address(0) ? msg.sender : params.receiver;
        result = LibMLOPredictionFill.fillAskCurve(
            LibEveMarket.store(),
            MLOPredictionTypes.MLOAskFillRequest({
                curveId: params.curveId,
                collateralIn: params.collateralIn,
                minSharesOut: params.minSharesOut,
                expectedGeneration: params.expectedGeneration,
                expectedCommitment: params.expectedCommitment,
                fundingSource: msg.sender,
                taker: msg.sender,
                receiver: receiver,
                fundingIsEscrowed: false
            })
        );
    }
}
