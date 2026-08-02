// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {CurveCLOBTypes} from "../types/CurveCLOBTypes.sol";
import {Errors} from "../libraries/Errors.sol";
import {LibReentrancy} from "../libraries/LibReentrancy.sol";
import {LibSellExecution} from "../libraries/LibSellExecution.sol";

contract BookSellFacet is CurveCLOBTypes {
    modifier nonReentrant() {
        LibReentrancy.enter();
        _;
        LibReentrancy.exit();
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
        if (msg.sender != address(this)) {
            revert Errors.InternalCallOnly(msg.sender);
        }
        SellBookParams memory requestParams = params;
        result = LibSellExecution.sellBookBest(requestParams, context);
    }
}
