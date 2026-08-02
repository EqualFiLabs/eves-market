// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {CurveCLOBTypes} from "../types/CurveCLOBTypes.sol";

interface ICurveTradeFacet {
    function fillCurve(
        uint256 curveId,
        uint128 collateralIn,
        uint128 minSharesOut,
        uint32 expectedGeneration,
        bytes32 expectedCommitment
    ) external returns (uint128 sharesOut);

    function fillBest(CurveCLOBTypes.FillBestParams calldata params)
        external
        returns (CurveCLOBTypes.FillBestResult memory result);
}
