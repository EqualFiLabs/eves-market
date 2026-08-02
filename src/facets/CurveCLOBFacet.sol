// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {CurveCLOBTypes} from "../types/CurveCLOBTypes.sol";
import {LibBuyExecution} from "../libraries/LibBuyExecution.sol";
import {LibReentrancy} from "../libraries/LibReentrancy.sol";

contract CurveCLOBFacet is CurveCLOBTypes {
    modifier nonReentrant() {
        LibReentrancy.enter();
        _;
        LibReentrancy.exit();
    }

    function fillCurve(
        uint256 curveId,
        uint128 collateralIn,
        uint128 minSharesOut,
        uint32 expectedGeneration,
        bytes32 expectedCommitment
    ) external nonReentrant returns (uint128 sharesOut) {
        sharesOut = LibBuyExecution.fillCurve(
            curveId, collateralIn, minSharesOut, expectedGeneration, expectedCommitment, msg.sender, msg.sender
        );
    }

    function fillBest(FillBestParams calldata params) external nonReentrant returns (FillBestResult memory result) {
        FillBestParams memory requestParams = params;
        requestParams.payer = msg.sender;
        result = LibBuyExecution.fillBest(requestParams, LibBuyExecution.FillMode.RouteOrder);
    }
}
