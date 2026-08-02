// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {MLOPredictionTypes} from "../types/MLOPredictionTypes.sol";
import {IMLOPredictionAdapterFacet} from "../interfaces/IMLOPredictionAdapterFacet.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibMLOPredictionBidFill} from "../libraries/LibMLOPredictionBidFill.sol";
import {LibReentrancy} from "../libraries/LibReentrancy.sol";

contract MLOPredictionBidTradeFacet {
    modifier nonReentrant() {
        LibReentrancy.enter();
        _;
        LibReentrancy.exit();
    }

    function fillMLOBidCurve(MLOPredictionTypes.FillMLOBidCurveParams calldata params)
        external
        nonReentrant
        returns (MLOPredictionTypes.MLOBidFillResult memory result)
    {
        address receiver = params.receiver == address(0) ? msg.sender : params.receiver;
        result = LibMLOPredictionBidFill.fillBidCurve(
            LibEveMarket.store(),
            MLOPredictionTypes.MLOBidFillRequest({
                curveId: params.curveId,
                sharesIn: params.sharesIn,
                minCollateralOut: params.minCollateralOut,
                expectedGeneration: params.expectedGeneration,
                expectedCommitment: params.expectedCommitment,
                source: msg.sender,
                seller: msg.sender,
                receiver: receiver
            })
        );
    }

    function executeMLOBidFromRoute(MLOPredictionTypes.MLOBidFillRequest calldata request)
        external
        returns (MLOPredictionTypes.MLOBidFillResult memory result)
    {
        if (msg.sender != address(this)) revert IMLOPredictionAdapterFacet.MLOInternalOnly(msg.sender);
        result = LibMLOPredictionBidFill.fillBidCurve(LibEveMarket.store(), request);
    }
}
