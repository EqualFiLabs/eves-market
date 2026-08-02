// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IStaticsDollarCore} from "@statics/dollar/core/interfaces/IStaticsDollarCore.sol";
import {IStaticsDollarCoreTypes} from "@statics/dollar/interfaces/IStaticsDollarCoreTypes.sol";
import {IStaticsDollarGateway} from "@statics/dollar/interfaces/IStaticsDollarGateway.sol";
import {ICollateralTradeExecution} from "../interfaces/ICollateralTradeExecution.sol";
import {ITradeRouter} from "../interfaces/ITradeRouter.sol";
import {CurveCLOBTypes} from "../types/CurveCLOBTypes.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibMLOProfitShare} from "../libraries/LibMLOProfitShare.sol";
import {LibRouter} from "../libraries/LibRouter.sol";
import {LibSeniorCapital} from "../libraries/LibSeniorCapital.sol";
import {LibTradeRouter} from "../libraries/LibTradeRouter.sol";

/// @notice Atomic USDC entry rail for Statics Dollar-denominated markets.
contract StaticsDollarTradeRouterFacet {
    using SafeERC20 for IERC20;

    modifier nonReentrant() {
        LibRouter.enter();
        _;
        LibRouter.exit();
    }

    function mintAndBuyWithUSDC(ITradeRouter.BuyWithUSDCParams calldata params)
        external
        nonReentrant
        returns (CurveCLOBTypes.FillBestResult memory result)
    {
        ITradeRouter.PermitSignature memory permitSignature;
        result = _mintAndBuyWithUSDC(params, permitSignature, false);
    }

    function mintAndBuyWithUSDCPermit(
        ITradeRouter.BuyWithUSDCParams calldata params,
        ITradeRouter.PermitSignature calldata permitSignature
    ) external nonReentrant returns (CurveCLOBTypes.FillBestResult memory result) {
        result = _mintAndBuyWithUSDC(params, permitSignature, true);
    }

    function _mintAndBuyWithUSDC(
        ITradeRouter.BuyWithUSDCParams calldata params,
        ITradeRouter.PermitSignature memory permitSignature,
        bool usePermit
    ) private returns (CurveCLOBTypes.FillBestResult memory result) {
        LibTradeRouter.validateOrderParams(params.order);

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.MarketConfig storage config = state.config;
        if (
            config.staticsDollarCore == address(0) || config.staticsDiamond == address(0)
                || config.usdcToken == address(0) || config.peggedProfileId == 0
        ) {
            revert ITradeRouter.StaticsDollarRailUnavailable();
        }

        IStaticsDollarCore core = IStaticsDollarCore(config.staticsDollarCore);
        IStaticsDollarGateway gateway = IStaticsDollarGateway(config.staticsDiamond);
        address staticsDollar = core.staticsDollar();
        LibTradeRouter.requireMarketCollateral(LibTradeRouter.requireMarket(params.order.marketId), staticsDollar);

        IStaticsDollarCoreTypes.PeggedMintPreview memory mintPreview =
            gateway.previewPeggedMint(config.peggedProfileId, params.order.maxCollateralIn);
        if (mintPreview.totalCollateralIn > params.maxUsdcIn) {
            revert ITradeRouter.MaxUsdcExceeded(mintPreview.totalCollateralIn, params.maxUsdcIn);
        }

        uint256 usdcBalanceBefore = IERC20(config.usdcToken).balanceOf(address(this));
        uint256 staticsDollarBalanceBefore = IERC20(staticsDollar).balanceOf(address(this));
        uint256 marginLiabilitiesBefore = state.totalMarginLiabilities;
        uint256 seniorRewardReserveBefore = LibMLOProfitShare.s().totalSeniorRewardReserve;
        uint256 nativeLiabilityBefore = state.nativePositionCollateralLiability[staticsDollar];
        uint256 seniorExposureBefore = LibSeniorCapital.s().activeExposure;
        CurveCLOBTypes.FillBestParams memory routedOrder = LibTradeRouter.routerParams(params.order);
        uint128 retainedFeeBalance = LibTradeRouter.previewRetainedBuyFeeBalance(routedOrder);

        if (usePermit) {
            IERC20Permit(config.usdcToken)
                .permit(
                    msg.sender,
                    address(this),
                    mintPreview.totalCollateralIn,
                    permitSignature.deadline,
                    permitSignature.v,
                    permitSignature.r,
                    permitSignature.s
                );
        }
        IERC20(config.usdcToken).safeTransferFrom(msg.sender, address(this), mintPreview.totalCollateralIn);
        IERC20(config.usdcToken).forceApprove(config.staticsDiamond, mintPreview.totalCollateralIn);
        gateway.mintPegged(
            config.peggedProfileId, params.order.maxCollateralIn, mintPreview.totalCollateralIn, address(this)
        );
        IERC20(config.usdcToken).forceApprove(config.staticsDiamond, 0);

        result = ICollateralTradeExecution(address(this)).executeCollateralBuy(routedOrder, msg.sender);
        if (result.unfilledCollateral != 0) {
            IERC20(staticsDollar).safeTransfer(msg.sender, result.unfilledCollateral);
        }

        LibRouter.assertBalanceRestored(config.usdcToken, usdcBalanceBefore);
        uint256 marginProfit = state.totalMarginLiabilities - marginLiabilitiesBefore;
        uint256 seniorReward = LibMLOProfitShare.s().totalSeniorRewardReserve - seniorRewardReserveBefore;
        uint256 nativeCollateral = state.nativePositionCollateralLiability[staticsDollar] - nativeLiabilityBefore;
        uint256 expectedStaticsDollarBalance = LibRouter.adjustForSeniorExposure(
            staticsDollarBalanceBefore + retainedFeeBalance + marginProfit + seniorReward + nativeCollateral,
            seniorExposureBefore,
            LibSeniorCapital.s().activeExposure
        );
        LibRouter.assertBalanceRestored(staticsDollar, expectedStaticsDollarBalance);

        emit ITradeRouter.StaticsDollarMintedAndBoughtWithUSDC(
            msg.sender,
            params.order.marketId,
            params.order.maxCollateralIn,
            mintPreview.principalCollateral,
            mintPreview.feeAmount,
            result.sharesOut,
            result.unfilledCollateral
        );
    }
}
