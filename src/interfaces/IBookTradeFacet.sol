// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {CurveCLOBTypes} from "../types/CurveCLOBTypes.sol";

interface IBookTradeFacet {
    function fillBookBest(CurveCLOBTypes.FillBookParams calldata params)
        external
        returns (CurveCLOBTypes.FillBestResult memory result);

    function fillBookBestFor(CurveCLOBTypes.FillBookParams calldata params)
        external
        returns (CurveCLOBTypes.FillBestResult memory result);

    function sellBookBest(CurveCLOBTypes.SellBookParams calldata params)
        external
        returns (CurveCLOBTypes.SellBookResult memory result);

    function sellBookBestFor(
        CurveCLOBTypes.SellBookParams calldata params,
        CurveCLOBTypes.SellExecutionContext calldata context
    ) external returns (CurveCLOBTypes.SellBookResult memory result);
}
