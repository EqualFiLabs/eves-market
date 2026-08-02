// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {CurveCLOBTypes} from "../types/CurveCLOBTypes.sol";

interface ICurveViewFacet {
    function getCurveInfo(uint256 curveId) external view returns (CurveCLOBTypes.CurveInfo memory curveInfo);
    function getCurveCommitment(uint256 curveId) external view returns (uint32 generation, bytes32 commitment);

    function previewCurveQuote(uint256 curveId, uint128 collateralIn)
        external
        view
        returns (uint128 sharesOut, uint128 fee, uint128 price, uint128 makerTopUp);

    function previewBestExecution(bytes32 marketId, bool isYesSide, uint128 collateralIn, uint256[] calldata curveIds)
        external
        view
        returns (uint128 sharesOut, uint128 fee, uint128 averagePrice, uint128 unfilledCollateral);
}
