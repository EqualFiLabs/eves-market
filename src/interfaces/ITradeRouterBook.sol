// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {CurveCLOBTypes} from "../types/CurveCLOBTypes.sol";

interface ITradeRouterBook {
    event BookPositionBought(
        address indexed account,
        bytes32 indexed bookId,
        address indexed quoteToken,
        uint128 quoteUsed,
        uint128 baseOut,
        uint128 feePaid,
        uint128 unfilledQuote
    );
    event BookPositionSold(
        address indexed account,
        bytes32 indexed bookId,
        address indexed quoteToken,
        uint128 baseSold,
        uint128 quoteOut,
        uint128 feePaid,
        uint128 unfilledBase
    );

    function buyBookWithCollateral(CurveCLOBTypes.FillBookParams calldata params)
        external
        returns (CurveCLOBTypes.FillBestResult memory result);

    function sellBookWithCollateral(CurveCLOBTypes.SellBookParams calldata params)
        external
        returns (CurveCLOBTypes.SellBookResult memory result);
}
