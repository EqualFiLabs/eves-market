// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {MLOPredictionTypes} from "../types/MLOPredictionTypes.sol";
import {LibEveMarket} from "./LibEveMarket.sol";
import {LibMLOPredictionFill} from "./LibMLOPredictionFill.sol";

library LibDelayedOrderMLOAskFill {
    function fillEscrowedMLOAsk(
        address receiver,
        uint256 curveId,
        uint128 collateralIn,
        uint32 expectedGeneration,
        bytes32 expectedCommitment
    ) public returns (MLOPredictionTypes.MLOAskFillResult memory mloFill) {
        mloFill = LibMLOPredictionFill.fillAskCurve(
            LibEveMarket.store(),
            MLOPredictionTypes.MLOAskFillRequest({
                curveId: curveId,
                collateralIn: collateralIn,
                minSharesOut: 0,
                expectedGeneration: expectedGeneration,
                expectedCommitment: expectedCommitment,
                fundingSource: address(this),
                taker: receiver,
                receiver: receiver,
                fundingIsEscrowed: true
            })
        );
    }
}
