// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IGnosisConditionalTokens} from "../interfaces/IGnosisConditionalTokens.sol";
import {IEveUSDC} from "../interfaces/IEveUSDC.sol";
import {ITradeRouter} from "../interfaces/ITradeRouter.sol";
import {CurveCLOBTypes} from "../types/CurveCLOBTypes.sol";
import {LibCTF} from "../libraries/LibCTF.sol";
import {LibBuyExecution} from "../libraries/LibBuyExecution.sol";
import {LibEveUSDCUnits} from "../libraries/LibEveUSDCUnits.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibMarketAccess} from "../libraries/LibMarketAccess.sol";
import {LibRouter} from "../libraries/LibRouter.sol";
import {LibSafeCast} from "../libraries/LibSafeCast.sol";
import {LibTradeRouter} from "../libraries/LibTradeRouter.sol";

contract TradeRouterFacet {
    using SafeERC20 for IERC20;

    uint256 internal constant RESERVED_OFFSET = 172;

    struct BuyUSDCCache {
        address eveUSDC;
        address usdc;
        uint256 usdcBalanceBefore;
        uint256 eveUsdcBalanceBefore;
        uint128 retainedFeeBalance;
        uint128 refundedUsdc;
        uint128 usdcSpent;
    }

    modifier nonReentrant() {
        LibRouter.enter();
        _;
        LibRouter.exit();
    }

    function buyWithEveUSDC(CurveCLOBTypes.FillBestParams calldata params)
        external
        nonReentrant
        returns (CurveCLOBTypes.FillBestResult memory result)
    {
        LibTradeRouter.validateOrderParams(params);

        address eveUSDC = LibTradeRouter.eveUSDC();
        uint256 eveUsdcBalanceBefore = IERC20(eveUSDC).balanceOf(address(this));
        LibEveMarket.Market storage market = LibTradeRouter.requireMarket(params.marketId);
        LibTradeRouter.requireMarketCollateral(market, eveUSDC);
        uint128 retainedFeeBalance = LibTradeRouter.previewRetainedBuyFeeBalance(LibTradeRouter.routerParams(params));

        IERC20(eveUSDC).safeTransferFrom(msg.sender, address(this), params.maxCollateralIn);
        result = LibBuyExecution.fillBest(LibTradeRouter.routerParams(params), LibBuyExecution.FillMode.RouteOrder);

        if (result.unfilledCollateral != 0) {
            IERC20(eveUSDC).safeTransfer(msg.sender, result.unfilledCollateral);
        }

        LibRouter.assertBalanceRestored(eveUSDC, eveUsdcBalanceBefore + retainedFeeBalance);

        emit ITradeRouter.TradeExecutedWithEveUSDC(
            msg.sender,
            params.marketId,
            params.isYesSide,
            result.collateralUsed,
            result.sharesOut,
            result.feePaid,
            result.unfilledCollateral
        );
    }

    function buyWithUSDC(CurveCLOBTypes.FillBestParams calldata params)
        external
        nonReentrant
        returns (CurveCLOBTypes.FillBestResult memory result)
    {
        LibTradeRouter.validateOrderParams(params);

        BuyUSDCCache memory cache;
        cache.eveUSDC = LibTradeRouter.eveUSDC();
        cache.usdc = IEveUSDC(cache.eveUSDC).usdc();
        cache.usdcBalanceBefore = IERC20(cache.usdc).balanceOf(address(this));
        cache.eveUsdcBalanceBefore = IERC20(cache.eveUSDC).balanceOf(address(this));
        LibTradeRouter.requireMarketCollateral(LibTradeRouter.requireMarket(params.marketId), cache.eveUSDC);

        uint128 wrappedMaxCollateralIn = LibSafeCast.toUint128(LibEveUSDCUnits.toEveUSDC(params.maxCollateralIn));
        cache.retainedFeeBalance =
            LibTradeRouter.previewRetainedBuyFeeBalance(LibTradeRouter.routerParams(params, wrappedMaxCollateralIn));

        IERC20(cache.usdc).safeTransferFrom(msg.sender, address(this), params.maxCollateralIn);
        IERC20(cache.usdc).forceApprove(cache.eveUSDC, params.maxCollateralIn);
        uint256 wrapped = IEveUSDC(cache.eveUSDC).wrap(params.maxCollateralIn, address(this));
        IERC20(cache.usdc).forceApprove(cache.eveUSDC, 0);

        CurveCLOBTypes.FillBestResult memory rawResult = LibBuyExecution.fillBest(
            LibTradeRouter.routerParams(params, LibSafeCast.toUint128(wrapped)), LibBuyExecution.FillMode.RouteOrder
        );

        if (rawResult.unfilledCollateral != 0) {
            cache.refundedUsdc = LibSafeCast.toUint128(
                LibRouter.unwrapConvertibleEveUSDC(cache.eveUSDC, rawResult.unfilledCollateral, msg.sender)
            );
        }
        cache.usdcSpent = params.maxCollateralIn - cache.refundedUsdc;

        LibRouter.assertBalanceRestored(cache.usdc, cache.usdcBalanceBefore);
        LibRouter.assertBalanceRestored(cache.eveUSDC, cache.eveUsdcBalanceBefore + cache.retainedFeeBalance);

        result = rawResult;
        result.collateralUsed = cache.usdcSpent;
        result.feePaid = LibSafeCast.toUint128(LibTradeRouter.usdcFloor(rawResult.feePaid));
        result.unfilledCollateral = cache.refundedUsdc;

        emit ITradeRouter.TradeExecutedWithUSDC(
            msg.sender,
            params.marketId,
            params.isYesSide,
            cache.usdcSpent,
            cache.refundedUsdc,
            result.sharesOut,
            result.feePaid
        );
    }

    function buyWithCollateral(CurveCLOBTypes.FillBestParams calldata params)
        external
        nonReentrant
        returns (CurveCLOBTypes.FillBestResult memory result)
    {
        LibTradeRouter.validateOrderParams(params);

        LibEveMarket.Market storage market = LibTradeRouter.requireMarket(params.marketId);
        address collateralToken = market.collateralToken;
        uint256 balanceBefore = IERC20(collateralToken).balanceOf(address(this));
        uint128 retainedFeeBalance = LibTradeRouter.previewRetainedBuyFeeBalance(LibTradeRouter.routerParams(params));

        IERC20(collateralToken).safeTransferFrom(msg.sender, address(this), params.maxCollateralIn);
        result = LibBuyExecution.fillBest(LibTradeRouter.routerParams(params), LibBuyExecution.FillMode.RouteOrder);

        if (result.unfilledCollateral != 0) {
            IERC20(collateralToken).safeTransfer(msg.sender, result.unfilledCollateral);
        }

        LibRouter.assertBalanceRestored(collateralToken, balanceBefore + retainedFeeBalance);

        emit ITradeRouter.TradeExecutedWithCollateral(
            msg.sender,
            params.marketId,
            collateralToken,
            params.isYesSide,
            result.collateralUsed,
            result.sharesOut,
            result.feePaid,
            result.unfilledCollateral
        );
    }

    function splitWithUSDC(bytes32 marketId, uint128 usdcAmount, address receiver)
        external
        nonReentrant
        returns (uint128 sharesMinted)
    {
        if (usdcAmount == 0) {
            revert ITradeRouter.ZeroAmount();
        }
        LibRouter.requireReceiver(receiver);

        LibEveMarket.Market storage market = LibTradeRouter.requireCTFPositionMarket(marketId);
        LibMarketAccess.validatePositionIds(market);

        address eveUSDC = LibTradeRouter.eveUSDC();
        LibTradeRouter.requireMarketCollateral(market, eveUSDC);
        address usdc = IEveUSDC(eveUSDC).usdc();
        uint256 usdcBalanceBefore = IERC20(usdc).balanceOf(address(this));
        IGnosisConditionalTokens ctf = IGnosisConditionalTokens(market.positionToken);

        LibCTF.prepareMarketCondition(market.positionToken, market.resolutionId);
        IERC20(usdc).safeTransferFrom(msg.sender, address(this), usdcAmount);
        IERC20(usdc).forceApprove(eveUSDC, usdcAmount);
        sharesMinted = LibSafeCast.toUint128(IEveUSDC(eveUSDC).wrap(usdcAmount, address(this)));
        IERC20(usdc).forceApprove(eveUSDC, 0);

        IERC20(eveUSDC).forceApprove(market.positionToken, sharesMinted);
        LibCTF.splitCollateral(market.positionToken, market.collateralToken, market.conditionId, sharesMinted);
        IERC20(eveUSDC).forceApprove(market.positionToken, 0);

        ctf.safeTransferFrom(address(this), receiver, market.yesPositionId, sharesMinted, "");
        ctf.safeTransferFrom(address(this), receiver, market.noPositionId, sharesMinted, "");

        LibRouter.assertBalanceRestored(usdc, usdcBalanceBefore);

        emit ITradeRouter.InventorySplitWithUSDC(msg.sender, marketId, receiver, usdcAmount, sharesMinted);
    }
}
