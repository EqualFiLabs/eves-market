// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ITradeRouter} from "../interfaces/ITradeRouter.sol";
import {LibRouter} from "../libraries/LibRouter.sol";
import {LibSellExecution} from "../libraries/LibSellExecution.sol";
import {LibTradeRouter} from "../libraries/LibTradeRouter.sol";

/// @notice Direct ERC-20 collateral exit and quoting for production markets.
contract CollateralTradeRouterSellFacet {
    modifier nonReentrant() {
        LibRouter.enter();
        _;
        LibRouter.exit();
    }

    function sellWithCollateral(ITradeRouter.SellBestParams calldata params)
        external
        nonReentrant
        returns (ITradeRouter.SellBestResult memory result)
    {
        LibTradeRouter.validateSellParams(params);

        address collateralToken = LibTradeRouter.requireMarket(params.marketId).collateralToken;
        result = LibSellExecution.sellBest(params, LibSellExecution.immediateContext(msg.sender, params.receiver));

        ITradeRouter(address(this)).executeExactRouterTransfer(collateralToken, params.receiver, result.collateralOut);

        emit ITradeRouter.PositionSoldForCollateral(
            msg.sender,
            params.marketId,
            collateralToken,
            params.isYesSide,
            result.sharesSold,
            result.collateralOut,
            result.feePaid,
            result.unfilledShares
        );
    }
}
