// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IEveUSDC} from "../interfaces/IEveUSDC.sol";
import {ITradeRouter} from "../interfaces/ITradeRouter.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibRouter} from "../libraries/LibRouter.sol";
import {LibSafeCast} from "../libraries/LibSafeCast.sol";
import {LibSellExecution} from "../libraries/LibSellExecution.sol";
import {LibTradeRouter} from "../libraries/LibTradeRouter.sol";

contract TradeRouterSellFacet {
    using SafeERC20 for IERC20;

    modifier nonReentrant() {
        LibRouter.enter();
        _;
        LibRouter.exit();
    }

    function sellWithEveUSDC(ITradeRouter.SellBestParams calldata params)
        external
        nonReentrant
        returns (ITradeRouter.SellBestResult memory result)
    {
        LibTradeRouter.validateSellParams(params);

        address eveUSDC = LibTradeRouter.eveUSDC();
        LibEveMarket.Market storage market = LibTradeRouter.requireMarket(params.marketId);
        LibTradeRouter.requireMarketCollateral(market, eveUSDC);

        ITradeRouter.SellBestParams memory requestParams = params;
        result =
            LibSellExecution.sellBest(requestParams, LibSellExecution.immediateContext(msg.sender, params.receiver));

        if (result.collateralOut != 0) {
            IERC20(eveUSDC).safeTransfer(params.receiver, result.collateralOut);
        }

        emit ITradeRouter.PositionSoldForEveUSDC(
            msg.sender,
            params.marketId,
            params.isYesSide,
            result.sharesSold,
            result.collateralOut,
            result.feePaid,
            result.unfilledShares
        );
    }

    function sellWithUSDC(ITradeRouter.SellBestParams calldata params)
        external
        nonReentrant
        returns (ITradeRouter.SellBestResult memory result)
    {
        LibTradeRouter.validateSellParams(params);

        address eveUSDC = LibTradeRouter.eveUSDC();
        address usdc = IEveUSDC(eveUSDC).usdc();
        uint256 usdcBalanceBefore = IERC20(usdc).balanceOf(address(this));
        LibEveMarket.Market storage market = LibTradeRouter.requireMarket(params.marketId);
        LibTradeRouter.requireMarketCollateral(market, eveUSDC);

        ITradeRouter.SellBestParams memory requestParams = params;
        result =
            LibSellExecution.sellBest(requestParams, LibSellExecution.immediateContext(msg.sender, params.receiver));

        if (result.collateralOut != 0) {
            result.collateralOut = LibSafeCast.toUint128(
                LibRouter.unwrapConvertibleEveUSDC(eveUSDC, result.collateralOut, params.receiver)
            );
        }
        result.feePaid = LibSafeCast.toUint128(LibTradeRouter.usdcFloor(result.feePaid));

        LibRouter.assertBalanceRestored(usdc, usdcBalanceBefore);

        emit ITradeRouter.PositionSoldForUSDC(
            msg.sender,
            params.marketId,
            params.isYesSide,
            result.sharesSold,
            result.collateralOut,
            result.feePaid,
            result.unfilledShares
        );
    }

    function sellWithCollateral(ITradeRouter.SellBestParams calldata params)
        external
        nonReentrant
        returns (ITradeRouter.SellBestResult memory result)
    {
        LibTradeRouter.validateSellParams(params);

        LibEveMarket.Market storage market = LibTradeRouter.requireMarket(params.marketId);
        address collateralToken = market.collateralToken;

        ITradeRouter.SellBestParams memory requestParams = params;
        result =
            LibSellExecution.sellBest(requestParams, LibSellExecution.immediateContext(msg.sender, params.receiver));

        if (result.collateralOut != 0) {
            IERC20(collateralToken).safeTransfer(params.receiver, result.collateralOut);
        }

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

    function previewSellBest(ITradeRouter.SellBestParams calldata params)
        external
        view
        returns (ITradeRouter.SellBestResult memory result)
    {
        LibTradeRouter.validateSellRouteParams(params);
        ITradeRouter.SellBestParams memory requestParams = params;
        result = LibSellExecution.previewSellBest(requestParams);
    }
}
