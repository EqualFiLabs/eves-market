// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IGnosisConditionalTokens} from "../interfaces/IGnosisConditionalTokens.sol";
import {ICurveTradeFacet} from "../interfaces/ICurveTradeFacet.sol";
import {IEveUSDC} from "../interfaces/IEveUSDC.sol";
import {ITradeRouter} from "../interfaces/ITradeRouter.sol";
import {CurveCLOBTypes} from "../types/CurveCLOBTypes.sol";
import {Errors} from "../libraries/Errors.sol";
import {LibCTF} from "../libraries/LibCTF.sol";
import {LibBookAccounting} from "../libraries/LibBookAccounting.sol";
import {LibCurveMath} from "../libraries/LibCurveMath.sol";
import {LibEveUSDCUnits} from "../libraries/LibEveUSDCUnits.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibMarketAccess} from "../libraries/LibMarketAccess.sol";
import {LibRouter} from "../libraries/LibRouter.sol";
import {LibSafeCast} from "../libraries/LibSafeCast.sol";
import {LibSellExecution} from "../libraries/LibSellExecution.sol";

contract TradeRouterFacet is ITradeRouter {
    using SafeERC20 for IERC20;

    uint256 internal constant RESERVED_OFFSET = 172;

    struct BuyQuote {
        uint128 sharesOut;
        uint128 fee;
        uint128 price;
        uint128 collateralUsed;
    }

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
        override
        nonReentrant
        returns (CurveCLOBTypes.FillBestResult memory result)
    {
        _validateOrderParams(params);

        address eveUSDC = _eveUSDC();
        uint256 eveUsdcBalanceBefore = IERC20(eveUSDC).balanceOf(address(this));
        LibEveMarket.Market storage market = _requireRouterMarket(params.marketId);
        _requireRouterMarketCollateral(market, eveUSDC);
        uint128 retainedFeeBalance = _previewRetainedBuyFeeBalance(_routerParams(params));

        IERC20(eveUSDC).safeTransferFrom(msg.sender, address(this), params.maxCollateralIn);
        result = ICurveTradeFacet(address(this)).fillBestFor(_routerParams(params));

        if (result.unfilledCollateral != 0) {
            IERC20(eveUSDC).safeTransfer(msg.sender, result.unfilledCollateral);
        }

        LibRouter.assertBalanceRestored(eveUSDC, eveUsdcBalanceBefore + retainedFeeBalance);

        emit TradeExecutedWithEveUSDC(
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
        override
        nonReentrant
        returns (CurveCLOBTypes.FillBestResult memory result)
    {
        _validateOrderParams(params);

        BuyUSDCCache memory cache;
        cache.eveUSDC = _eveUSDC();
        cache.usdc = IEveUSDC(cache.eveUSDC).usdc();
        cache.usdcBalanceBefore = IERC20(cache.usdc).balanceOf(address(this));
        cache.eveUsdcBalanceBefore = IERC20(cache.eveUSDC).balanceOf(address(this));
        _requireRouterMarketCollateral(_requireRouterMarket(params.marketId), cache.eveUSDC);

        uint128 wrappedMaxCollateralIn = LibSafeCast.toUint128(LibEveUSDCUnits.toEveUSDC(params.maxCollateralIn));
        cache.retainedFeeBalance = _previewRetainedBuyFeeBalance(_routerParams(params, wrappedMaxCollateralIn));

        IERC20(cache.usdc).safeTransferFrom(msg.sender, address(this), params.maxCollateralIn);
        IERC20(cache.usdc).forceApprove(cache.eveUSDC, params.maxCollateralIn);
        uint256 wrapped = IEveUSDC(cache.eveUSDC).wrap(params.maxCollateralIn, address(this));
        IERC20(cache.usdc).forceApprove(cache.eveUSDC, 0);

        CurveCLOBTypes.FillBestResult memory rawResult =
            ICurveTradeFacet(address(this)).fillBestFor(_routerParams(params, LibSafeCast.toUint128(wrapped)));

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
        result.feePaid = LibSafeCast.toUint128(_usdcFloor(rawResult.feePaid));
        result.unfilledCollateral = cache.refundedUsdc;

        emit TradeExecutedWithUSDC(
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
        override
        nonReentrant
        returns (CurveCLOBTypes.FillBestResult memory result)
    {
        _validateOrderParams(params);

        LibEveMarket.Market storage market = _requireRouterMarket(params.marketId);
        address collateralToken = market.collateralToken;
        uint256 balanceBefore = IERC20(collateralToken).balanceOf(address(this));
        uint128 retainedFeeBalance = _previewRetainedBuyFeeBalance(_routerParams(params));

        IERC20(collateralToken).safeTransferFrom(msg.sender, address(this), params.maxCollateralIn);
        result = ICurveTradeFacet(address(this)).fillBestFor(_routerParams(params));

        if (result.unfilledCollateral != 0) {
            IERC20(collateralToken).safeTransfer(msg.sender, result.unfilledCollateral);
        }

        LibRouter.assertBalanceRestored(collateralToken, balanceBefore + retainedFeeBalance);

        emit TradeExecutedWithCollateral(
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

    function sellWithEveUSDC(SellBestParams calldata params)
        external
        override
        nonReentrant
        returns (SellBestResult memory result)
    {
        _validateSellParams(params);

        address eveUSDC = _eveUSDC();
        LibEveMarket.Market storage market = _requireRouterMarket(params.marketId);
        _requireRouterMarketCollateral(market, eveUSDC);

        SellBestParams memory requestParams = params;
        result =
            LibSellExecution.sellBest(requestParams, LibSellExecution.immediateContext(msg.sender, params.receiver));

        if (result.collateralOut != 0) {
            IERC20(eveUSDC).safeTransfer(params.receiver, result.collateralOut);
        }

        emit PositionSoldForEveUSDC(
            msg.sender,
            params.marketId,
            params.isYesSide,
            result.sharesSold,
            result.collateralOut,
            result.feePaid,
            result.unfilledShares
        );
    }

    function sellWithUSDC(SellBestParams calldata params)
        external
        override
        nonReentrant
        returns (SellBestResult memory result)
    {
        _validateSellParams(params);

        address eveUSDC = _eveUSDC();
        address usdc = IEveUSDC(eveUSDC).usdc();
        uint256 usdcBalanceBefore = IERC20(usdc).balanceOf(address(this));
        LibEveMarket.Market storage market = _requireRouterMarket(params.marketId);
        _requireRouterMarketCollateral(market, eveUSDC);

        SellBestParams memory requestParams = params;
        result =
            LibSellExecution.sellBest(requestParams, LibSellExecution.immediateContext(msg.sender, params.receiver));

        if (result.collateralOut != 0) {
            result.collateralOut =
                LibSafeCast.toUint128(LibRouter.unwrapConvertibleEveUSDC(eveUSDC, result.collateralOut, params.receiver));
        }
        result.feePaid = LibSafeCast.toUint128(_usdcFloor(result.feePaid));

        LibRouter.assertBalanceRestored(usdc, usdcBalanceBefore);

        emit PositionSoldForUSDC(
            msg.sender,
            params.marketId,
            params.isYesSide,
            result.sharesSold,
            result.collateralOut,
            result.feePaid,
            result.unfilledShares
        );
    }

    function sellWithCollateral(SellBestParams calldata params)
        external
        override
        nonReentrant
        returns (SellBestResult memory result)
    {
        _validateSellParams(params);

        LibEveMarket.Market storage market = _requireRouterMarket(params.marketId);
        address collateralToken = market.collateralToken;

        SellBestParams memory requestParams = params;
        result =
            LibSellExecution.sellBest(requestParams, LibSellExecution.immediateContext(msg.sender, params.receiver));

        if (result.collateralOut != 0) {
            IERC20(collateralToken).safeTransfer(params.receiver, result.collateralOut);
        }

        emit PositionSoldForCollateral(
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

    function previewSellBest(SellBestParams calldata params)
        external
        view
        override
        returns (SellBestResult memory result)
    {
        _validateSellRouteParams(params);
        SellBestParams memory requestParams = params;
        result = LibSellExecution.previewSellBest(requestParams);
    }

    function splitWithUSDC(bytes32 marketId, uint128 usdcAmount, address receiver)
        external
        override
        nonReentrant
        returns (uint128 sharesMinted)
    {
        if (usdcAmount == 0) {
            revert ZeroAmount();
        }
        LibRouter.requireReceiver(receiver);

        LibEveMarket.Market storage market = _requireRouterCTFPositionMarket(marketId);
        LibMarketAccess.validatePositionIds(market);

        address eveUSDC = _eveUSDC();
        _requireRouterMarketCollateral(market, eveUSDC);
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

        emit InventorySplitWithUSDC(msg.sender, marketId, receiver, usdcAmount, sharesMinted);
    }

    function _eveUSDC() internal view returns (address) {
        address eveUSDC = LibEveMarket.store().config.collateralToken;
        if (eveUSDC == address(0)) {
            revert ZeroAddress();
        }
        return eveUSDC;
    }

    function _requireRouterMarket(bytes32 marketId) internal view returns (LibEveMarket.Market storage market) {
        market = LibMarketAccess.requireExistingMarket(LibEveMarket.store(), marketId);
    }

    function _requireRouterCTFPositionMarket(bytes32 marketId)
        internal
        view
        returns (LibEveMarket.Market storage market)
    {
        market = _requireRouterMarket(marketId);
        LibMarketAccess.requirePositionTokenType(market, LibEveMarket.PositionTokenType.CTF);
    }

    function _requireRouterMarketCollateral(LibEveMarket.Market storage market, address routerCollateral)
        internal
        view
    {
        if (market.collateralToken != routerCollateral) {
            revert MarketCollateralMismatch(market.collateralToken, routerCollateral);
        }
    }

    function _routerParams(CurveCLOBTypes.FillBestParams calldata params)
        internal
        view
        returns (CurveCLOBTypes.FillBestParams memory rewritten)
    {
        rewritten = CurveCLOBTypes.FillBestParams({
            marketId: params.marketId,
            isYesSide: params.isYesSide,
            maxCollateralIn: params.maxCollateralIn,
            minSharesOut: params.minSharesOut,
            maxAveragePrice: params.maxAveragePrice,
            curveIds: params.curveIds,
            expectedGenerations: params.expectedGenerations,
            expectedCommitments: params.expectedCommitments,
            payer: address(this),
            receiver: params.receiver
        });
    }

    function _routerParams(CurveCLOBTypes.FillBestParams calldata params, uint128 maxCollateralIn)
        internal
        view
        returns (CurveCLOBTypes.FillBestParams memory rewritten)
    {
        rewritten = CurveCLOBTypes.FillBestParams({
            marketId: params.marketId,
            isYesSide: params.isYesSide,
            maxCollateralIn: maxCollateralIn,
            minSharesOut: params.minSharesOut,
            maxAveragePrice: params.maxAveragePrice,
            curveIds: params.curveIds,
            expectedGenerations: params.expectedGenerations,
            expectedCommitments: params.expectedCommitments,
            payer: address(this),
            receiver: params.receiver
        });
    }

    function _previewRetainedBuyFeeBalance(CurveCLOBTypes.FillBestParams memory params)
        internal
        view
        returns (uint128 retainedFeeBalance)
    {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Market storage market = state.markets[params.marketId];
        if (market.marketId != params.marketId || !LibMarketAccess.canExecute(market)) {
            return 0;
        }
        bytes32 bookId = params.isYesSide ? market.yesBookId : market.noBookId;

        uint128 remainingCollateral = params.maxCollateralIn;
        for (uint256 index = 0; index < params.curveIds.length && remainingCollateral != 0; ++index) {
            LibEveMarket.StoredCurve storage curve = state.curves[params.curveIds[index]];
            if (
                curve.bookId != bookId || !curve.active || curve.curveSide != LibEveMarket.CurveSide.ASK
                    || curve.remainingVolume == 0 || LibCurveMath.isExpired(state, curve)
            ) {
                continue;
            }

            BuyQuote memory quote = _quoteBuyCurve(state, curve, remainingCollateral);
            if (quote.sharesOut == 0) {
                continue;
            }

            retainedFeeBalance += LibBookAccounting.retainedBuyFeeBalance(
                state, quote.fee, state.books[bookId].feeConfig
            );
            remainingCollateral -= quote.collateralUsed;
        }
    }

    function _validateOrderParams(CurveCLOBTypes.FillBestParams calldata params) internal pure {
        if (params.maxCollateralIn == 0) {
            revert ZeroAmount();
        }
        LibRouter.requireReceiver(params.receiver);
    }

    function _validateSellParams(SellBestParams calldata params) internal pure {
        _validateSellRouteParams(params);
        LibRouter.requireReceiver(params.receiver);
    }

    function _validateSellRouteParams(SellBestParams calldata params) internal pure {
        if (params.maxSharesIn == 0) {
            revert ZeroAmount();
        }
        if (params.curveIds.length != params.expectedGenerations.length) {
            revert Errors.ArrayLengthMismatch(params.curveIds.length, params.expectedGenerations.length);
        }
        if (params.curveIds.length != params.expectedCommitments.length) {
            revert Errors.ArrayLengthMismatch(params.curveIds.length, params.expectedCommitments.length);
        }
    }

    function _quoteBuyCurve(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.StoredCurve storage curve,
        uint128 collateralIn
    ) internal view returns (BuyQuote memory quote) {
        (quote.sharesOut, quote.fee, quote.price, quote.collateralUsed) =
            LibCurveMath.quoteAsk(state, curve, collateralIn);
    }

    function _usdcFloor(uint256 eveUSDCAmount) internal pure returns (uint256 usdcAmount) {
        usdcAmount = LibEveUSDCUnits.convertibleEveUSDC(eveUSDCAmount) / LibEveUSDCUnits.USDC_TO_EVEUSDC_SCALE;
    }
}
