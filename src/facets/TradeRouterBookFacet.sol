// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ITradeRouter} from "../interfaces/ITradeRouter.sol";
import {ITradeRouterBook} from "../interfaces/ITradeRouterBook.sol";
import {CurveCLOBTypes} from "../types/CurveCLOBTypes.sol";
import {LibBookAccess} from "../libraries/LibBookAccess.sol";
import {LibBuyExecution} from "../libraries/LibBuyExecution.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibMLOProfitShare} from "../libraries/LibMLOProfitShare.sol";
import {LibRouter} from "../libraries/LibRouter.sol";
import {LibSeniorCapital} from "../libraries/LibSeniorCapital.sol";
import {LibTradeRouter} from "../libraries/LibTradeRouter.sol";

contract TradeRouterBookFacet {
    using SafeERC20 for IERC20;

    modifier nonReentrant() {
        LibRouter.enter();
        _;
        LibRouter.exit();
    }

    function buyBookWithCollateral(CurveCLOBTypes.FillBookParams calldata params)
        external
        nonReentrant
        returns (CurveCLOBTypes.FillBestResult memory result)
    {
        address quoteToken = LibBookAccess.requireExecutableBook(LibEveMarket.store(), params.bookId).quoteToken;
        if (params.maxQuoteIn == 0 || params.receiver == address(0)) revert ITradeRouter.ZeroAmount();

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        uint256 balanceBefore = IERC20(quoteToken).balanceOf(address(this));
        uint256 liabilitiesBefore = state.totalMarginLiabilities;
        uint256 seniorRewardReserveBefore = LibMLOProfitShare.s().totalSeniorRewardReserve;
        uint256 nativeLiabilityBefore = state.nativePositionCollateralLiability[quoteToken];
        uint256 seniorExposureBefore = LibSeniorCapital.s().activeExposure;
        CurveCLOBTypes.FillBookParams memory request = params;
        request.payer = address(this);
        uint128 retainedFee = LibTradeRouter.previewRetainedBookBuyFeeBalance(request);

        IERC20(quoteToken).safeTransferFrom(msg.sender, address(this), params.maxQuoteIn);
        result = LibBuyExecution.fillBookBest(request, LibBuyExecution.FillMode.BestAsk, msg.sender);
        if (result.unfilledCollateral != 0) {
            IERC20(quoteToken).safeTransfer(msg.sender, result.unfilledCollateral);
        }

        uint256 marginProfit = state.totalMarginLiabilities - liabilitiesBefore;
        uint256 seniorReward = LibMLOProfitShare.s().totalSeniorRewardReserve - seniorRewardReserveBefore;
        uint256 nativeCollateral = state.nativePositionCollateralLiability[quoteToken] - nativeLiabilityBefore;
        uint256 expectedBalance = LibRouter.adjustForSeniorExposure(
            balanceBefore + retainedFee + marginProfit + seniorReward + nativeCollateral,
            seniorExposureBefore,
            LibSeniorCapital.s().activeExposure
        );
        LibRouter.assertBalanceRestored(quoteToken, expectedBalance);
        emit ITradeRouterBook.BookPositionBought(
            msg.sender,
            params.bookId,
            quoteToken,
            result.collateralUsed,
            result.sharesOut,
            result.feePaid,
            result.unfilledCollateral
        );
    }
}
