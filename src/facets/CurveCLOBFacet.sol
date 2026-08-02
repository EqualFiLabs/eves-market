// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {CurveCLOBTypes} from "../types/CurveCLOBTypes.sol";
import {LibBuyExecution} from "../libraries/LibBuyExecution.sol";
import {Errors} from "../libraries/Errors.sol";
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

    function fillBestFor(FillBestParams calldata params) external returns (FillBestResult memory result) {
        _enforceSelfCall();

        FillBestParams memory requestParams = params;
        result = LibBuyExecution.fillBest(requestParams, LibBuyExecution.FillMode.RouteOrder);
    }

    function _enforceSelfCall() internal view {
        if (msg.sender != address(this)) {
            revert Errors.InternalCallOnly(msg.sender);
        }
    }
}
