// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {CurveCLOBTypes} from "../types/CurveCLOBTypes.sol";

interface ICollateralTradeExecution {
    error CollateralTradeExecutionUnauthorized(address caller);

    /// @notice Executes a collateral-funded CLOB buy after the calling router has acquired the collateral.
    /// @dev This selector is an internal Diamond boundary and only accepts self-calls.
    function executeCollateralBuy(CurveCLOBTypes.FillBestParams calldata params, address taker)
        external
        returns (CurveCLOBTypes.FillBestResult memory result);
}
