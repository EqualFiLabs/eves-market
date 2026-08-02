// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ITradeRouter} from "../interfaces/ITradeRouter.sol";
import {LibSellExecution} from "../libraries/LibSellExecution.sol";
import {LibRouter} from "../libraries/LibRouter.sol";
import {LibTradeRouter} from "../libraries/LibTradeRouter.sol";

/// @notice Sell quoting and Diamond-internal exact transfers for production collateral markets.
contract CollateralTradeRouterPreviewFacet {
    function previewSellBest(ITradeRouter.SellBestParams calldata params)
        external
        view
        returns (ITradeRouter.SellBestResult memory result)
    {
        LibTradeRouter.validateSellRouteParams(params);
        ITradeRouter.SellBestParams memory requestParams = params;
        result = LibSellExecution.previewSellBest(requestParams);
    }

    function executeExactRouterTransfer(address token, address receiver, uint256 amount) external {
        if (msg.sender != address(this)) revert ITradeRouter.RouterExecutionUnauthorized(msg.sender);
        LibRouter.transferExact(token, receiver, amount);
    }
}
