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

    event TradeExecutedWithEveUSDC(
        address indexed buyer,
        bytes32 indexed marketId,
        bool isYesSide,
        uint128 collateralUsed,
        uint128 sharesOut,
        uint128 feePaid,
        uint128 unfilledCollateral
    );

    event TradeExecutedWithUSDC(
        address indexed buyer,
        bytes32 indexed marketId,
        bool isYesSide,
        uint128 usdcSpent,
        uint128 usdcRefunded,
        uint128 sharesOut,
        uint128 feePaid
    );

    event PositionSoldForEveUSDC(
        address indexed seller,
        bytes32 indexed marketId,
        bool isYesSide,
        uint128 sharesSold,
        uint128 collateralOut,
        uint128 feePaid,
        uint128 unfilledShares
    );

    event PositionSoldForUSDC(
        address indexed seller,
        bytes32 indexed marketId,
        bool isYesSide,
        uint128 sharesSold,
        uint128 usdcOut,
        uint128 feePaid,
        uint128 unfilledShares
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

    event InventorySplitWithUSDC(
        address indexed splitter,
        bytes32 indexed marketId,
        address indexed receiver,
        uint128 usdcAmount,
        uint128 sharesMinted
    );

    function buyWithEveUSDC(CurveCLOBTypes.FillBestParams calldata params)
        external
        returns (CurveCLOBTypes.FillBestResult memory result);

    function buyWithUSDC(CurveCLOBTypes.FillBestParams calldata params)
        external
        returns (CurveCLOBTypes.FillBestResult memory result);

    function buyWithCollateral(CurveCLOBTypes.FillBestParams calldata params)
        external
        returns (CurveCLOBTypes.FillBestResult memory result);

    function sellWithEveUSDC(SellBestParams calldata params) external returns (SellBestResult memory result);

    function sellWithUSDC(SellBestParams calldata params) external returns (SellBestResult memory result);

    function sellWithCollateral(SellBestParams calldata params) external returns (SellBestResult memory result);

    function previewSellBest(SellBestParams calldata params) external view returns (SellBestResult memory result);

    function splitWithUSDC(bytes32 marketId, uint128 usdcAmount, address receiver)
        external
        returns (uint128 sharesMinted);
}
