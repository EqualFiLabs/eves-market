// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {CurveCLOBTypes} from "../types/CurveCLOBTypes.sol";

interface ITradeRouter {
    error ZeroAddress();
    error ZeroAmount();
    error InvalidReceiver(address receiver);
    error ResidualRouterBalance(address token, uint256 expectedBalance, uint256 actualBalance);
    error SellProceedsInsufficient(uint128 collateralValue, uint128 collateralUsed);
    error MarketCollateralMismatch(address marketCollateral, address routerCollateral);
    error MaxUsdcExceeded(uint256 required, uint256 maximum);
    error StaticsDollarRailUnavailable();
    error ExactFillRequired(uint128 unfilledCollateral);
    error NonExactRouterTransfer();
    error RouterExecutionUnauthorized(address caller);

    struct BuyWithUSDCParams {
        CurveCLOBTypes.FillBestParams order;
        uint256 maxUsdcIn;
    }

    struct PermitSignature {
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct SellBestParams {
        bytes32 marketId;
        bool isYesSide;
        uint128 maxSharesIn;
        uint128 minCollateralOut;
        uint256[] curveIds;
        uint32[] expectedGenerations;
        bytes32[] expectedCommitments;
        address receiver;
    }

    struct SellBestResult {
        uint128 sharesSold;
        uint128 collateralOut;
        uint128 feePaid;
        uint128 averagePrice;
        uint128 unfilledShares;
    }

    event StaticsDollarMintedAndBoughtWithUSDC(
        address indexed buyer,
        bytes32 indexed marketId,
        uint256 staticsDollarMinted,
        uint256 usdcPrincipal,
        uint256 usdcFee,
        uint128 sharesOut,
        uint128 unfilledCollateral
    );

    event TradeExecutedWithCollateral(
        address indexed buyer,
        bytes32 indexed marketId,
        address indexed collateralToken,
        bool isYesSide,
        uint128 collateralUsed,
        uint128 sharesOut,
        uint128 feePaid,
        uint128 unfilledCollateral
    );

    event PositionSoldForCollateral(
        address indexed seller,
        bytes32 indexed marketId,
        address indexed collateralToken,
        bool isYesSide,
        uint128 sharesSold,
        uint128 collateralOut,
        uint128 feePaid,
        uint128 unfilledShares
    );

    function mintAndBuyWithUSDC(BuyWithUSDCParams calldata params)
        external
        returns (CurveCLOBTypes.FillBestResult memory result);

    function mintAndBuyWithUSDCPermit(BuyWithUSDCParams calldata params, PermitSignature calldata permitSignature)
        external
        returns (CurveCLOBTypes.FillBestResult memory result);

    function buyWithCollateral(CurveCLOBTypes.FillBestParams calldata params)
        external
        returns (CurveCLOBTypes.FillBestResult memory result);

    function buyWithCollateralWithPermit(
        CurveCLOBTypes.FillBestParams calldata params,
        PermitSignature calldata permitSignature
    ) external returns (CurveCLOBTypes.FillBestResult memory result);

    function buyWithCollateralExact(CurveCLOBTypes.FillBestParams calldata params)
        external
        returns (CurveCLOBTypes.FillBestResult memory result);

    function sellWithCollateral(SellBestParams calldata params) external returns (SellBestResult memory result);

    function previewSellBest(SellBestParams calldata params) external view returns (SellBestResult memory result);

    function executeExactRouterTransfer(address token, address receiver, uint256 amount) external;
}
