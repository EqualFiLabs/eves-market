// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ICollateralTradeExecution} from "../interfaces/ICollateralTradeExecution.sol";
import {ITradeRouter} from "../interfaces/ITradeRouter.sol";
import {CurveCLOBTypes} from "../types/CurveCLOBTypes.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibMLOProfitShare} from "../libraries/LibMLOProfitShare.sol";
import {LibRouter} from "../libraries/LibRouter.sol";
import {LibSeniorCapital} from "../libraries/LibSeniorCapital.sol";
import {LibTradeRouter} from "../libraries/LibTradeRouter.sol";

/// @notice Direct ERC-20 collateral entry for production markets.
contract CollateralTradeRouterFacet {
    using SafeERC20 for IERC20;

    modifier nonReentrant() {
        LibRouter.enter();
        _;
        LibRouter.exit();
    }

    function buyWithCollateral(CurveCLOBTypes.FillBestParams calldata params)
        external
        nonReentrant
        returns (CurveCLOBTypes.FillBestResult memory result)
    {
        ITradeRouter.PermitSignature memory permitSignature;
        result = _buyWithCollateral(params, permitSignature, false);
    }

    function buyWithCollateralWithPermit(
        CurveCLOBTypes.FillBestParams calldata params,
        ITradeRouter.PermitSignature calldata permitSignature
    ) external nonReentrant returns (CurveCLOBTypes.FillBestResult memory result) {
        result = _buyWithCollateral(params, permitSignature, true);
    }

    function _buyWithCollateral(
        CurveCLOBTypes.FillBestParams calldata params,
        ITradeRouter.PermitSignature memory permitSignature,
        bool usePermit
    ) private returns (CurveCLOBTypes.FillBestResult memory result) {
        LibTradeRouter.validateOrderParams(params);

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Market storage market = LibTradeRouter.requireMarket(params.marketId);
        address collateralToken = market.collateralToken;
        uint256 balanceBefore = IERC20(collateralToken).balanceOf(address(this));
        uint256 marginLiabilitiesBefore = state.totalMarginLiabilities;
        uint256 seniorRewardReserveBefore = LibMLOProfitShare.s().totalSeniorRewardReserve;
        uint256 nativeLiabilityBefore = state.nativePositionCollateralLiability[collateralToken];
        uint256 seniorExposureBefore = LibSeniorCapital.s().activeExposure;
        uint128 retainedFeeBalance = LibTradeRouter.previewRetainedBuyFeeBalance(LibTradeRouter.routerParams(params));

        if (usePermit) {
            IERC20Permit(collateralToken).permit(
                msg.sender,
                address(this),
                params.maxCollateralIn,
                permitSignature.deadline,
                permitSignature.v,
                permitSignature.r,
                permitSignature.s
            );
        }
        IERC20(collateralToken).safeTransferFrom(msg.sender, address(this), params.maxCollateralIn);
        result = ICollateralTradeExecution(address(this))
            .executeCollateralBuy(LibTradeRouter.routerParams(params), msg.sender);

        if (result.unfilledCollateral != 0) {
            IERC20(collateralToken).safeTransfer(msg.sender, result.unfilledCollateral);
        }

        uint256 marginProfit = state.totalMarginLiabilities - marginLiabilitiesBefore;
        uint256 seniorReward = LibMLOProfitShare.s().totalSeniorRewardReserve - seniorRewardReserveBefore;
        uint256 nativeCollateral = state.nativePositionCollateralLiability[collateralToken] - nativeLiabilityBefore;
        uint256 expectedBalance = LibRouter.adjustForSeniorExposure(
            balanceBefore + retainedFeeBalance + marginProfit + seniorReward + nativeCollateral,
            seniorExposureBefore,
            LibSeniorCapital.s().activeExposure
        );
        LibRouter.assertBalanceRestored(collateralToken, expectedBalance);

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
}
