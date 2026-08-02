// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ICollateralTradeExecution} from "../interfaces/ICollateralTradeExecution.sol";
import {CurveCLOBTypes} from "../types/CurveCLOBTypes.sol";
import {LibBuyExecution} from "../libraries/LibBuyExecution.sol";

/// @notice Internal execution boundary shared by collateral-funded buy routers.
contract CollateralTradeExecutionFacet {
    function executeCollateralBuy(CurveCLOBTypes.FillBestParams calldata params, address taker)
        external
        returns (CurveCLOBTypes.FillBestResult memory result)
    {
        if (msg.sender != address(this)) {
            revert ICollateralTradeExecution.CollateralTradeExecutionUnauthorized(msg.sender);
        }
        CurveCLOBTypes.FillBestParams memory request = params;
        result = LibBuyExecution.fillBest(request, LibBuyExecution.FillMode.RouteOrder, taker);
    }
}
