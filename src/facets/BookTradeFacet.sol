// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {CurveCLOBTypes} from "../types/CurveCLOBTypes.sol";
import {Errors} from "../libraries/Errors.sol";
import {LibBuyExecution} from "../libraries/LibBuyExecution.sol";
import {LibReentrancy} from "../libraries/LibReentrancy.sol";
import {LibSellExecution} from "../libraries/LibSellExecution.sol";

contract BookTradeFacet is CurveCLOBTypes {
    modifier nonReentrant() {
        LibReentrancy.enter();
        _;
        LibReentrancy.exit();
    }

    function fillBookBest(FillBookParams calldata params) external nonReentrant returns (FillBestResult memory result) {
        FillBookParams memory requestParams = params;
        requestParams.payer = msg.sender;
        result = LibBuyExecution.fillBookBest(requestParams, LibBuyExecution.FillMode.BestAsk);
    }

    function fillBookBestFor(FillBookParams calldata params) external returns (FillBestResult memory result) {
        _enforceSelfCall();

        FillBookParams memory requestParams = params;
        result = LibBuyExecution.fillBookBest(requestParams, LibBuyExecution.FillMode.BestAsk);
    }

    function sellBookBest(SellBookParams calldata params) external nonReentrant returns (SellBookResult memory result) {
        SellBookParams memory requestParams = params;
        result = LibSellExecution.sellBookBest(
            requestParams, LibSellExecution.immediateContext(msg.sender, params.receiver)
        );
    }

    function sellBookBestFor(SellBookParams calldata params, SellExecutionContext calldata context)
        external
        returns (SellBookResult memory result)
    {
        _enforceSelfCall();
        SellBookParams memory requestParams = params;
        result = LibSellExecution.sellBookBest(requestParams, context);
    }

    function _enforceSelfCall() internal view {
        if (msg.sender != address(this)) {
            revert Errors.InternalCallOnly(msg.sender);
        }
    }
}
