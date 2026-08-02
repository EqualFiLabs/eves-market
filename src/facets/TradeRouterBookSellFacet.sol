// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ITradeRouter} from "../interfaces/ITradeRouter.sol";
import {ITradeRouterBook} from "../interfaces/ITradeRouterBook.sol";
import {CurveCLOBTypes} from "../types/CurveCLOBTypes.sol";
import {LibBookAccess} from "../libraries/LibBookAccess.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibRouter} from "../libraries/LibRouter.sol";
import {LibSellExecution} from "../libraries/LibSellExecution.sol";

contract TradeRouterBookSellFacet {
    modifier nonReentrant() {
        LibRouter.enter();
        _;
        LibRouter.exit();
    }

    function sellBookWithCollateral(CurveCLOBTypes.SellBookParams calldata params)
        external
        nonReentrant
        returns (CurveCLOBTypes.SellBookResult memory result)
    {
        address quoteToken = LibBookAccess.requireExecutableBook(LibEveMarket.store(), params.bookId).quoteToken;
        if (params.maxBaseIn == 0 || params.receiver == address(0)) revert ITradeRouter.ZeroAmount();

        CurveCLOBTypes.SellBookParams memory request = params;
        result = LibSellExecution.sellBookBest(
            request,
            LibSellExecution.immediateContext(msg.sender, address(this)),
            LibSellExecution.DirectBidSettlement.RetainInDiamond
        );
        if (result.quoteOut != 0) LibRouter.transferExact(quoteToken, params.receiver, result.quoteOut);

        emit ITradeRouterBook.BookPositionSold(
            msg.sender, params.bookId, quoteToken, result.baseSold, result.quoteOut, result.feePaid, result.unfilledBase
        );
    }
}
