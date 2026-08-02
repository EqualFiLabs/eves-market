// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {CurveCLOBTypes} from "../types/CurveCLOBTypes.sol";
import {LibCLOBView} from "../libraries/LibCLOBView.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";

contract CurveViewFacet is CurveCLOBTypes {
    function getCurveInfo(uint256 curveId) external view returns (CurveInfo memory curveInfo) {
        return LibCLOBView.curveInfo(LibEveMarket.store(), curveId);
    }

    function getCurveCommitment(uint256 curveId) external view returns (uint32 generation, bytes32 commitment) {
        return LibCLOBView.curveCommitment(LibEveMarket.store(), curveId);
    }

    function previewCurveQuote(uint256 curveId, uint128 collateralIn)
        external
        view
        returns (uint128 sharesOut, uint128 fee, uint128 price, uint128 makerTopUp)
    {
        return LibCLOBView.previewCurveQuote(LibEveMarket.store(), curveId, collateralIn);
    }

    function previewBestExecution(bytes32 marketId, bool isYesSide, uint128 collateralIn, uint256[] calldata curveIds)
        external
        view
        returns (uint128 sharesOut, uint128 fee, uint128 averagePrice, uint128 unfilledCollateral)
    {
        return LibCLOBView.previewMarketExecution(LibEveMarket.store(), marketId, isYesSide, collateralIn, curveIds);
    }
}
