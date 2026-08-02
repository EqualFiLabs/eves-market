// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Errors} from "./Errors.sol";
import {LibCLOBBook} from "./LibCLOBBook.sol";
import {LibCTF} from "./LibCTF.sol";
import {LibEveMarket} from "./LibEveMarket.sol";

library LibBookAccess {
    function marketSideBookId(LibEveMarket.Market storage market, bool isYesSide)
        internal
        view
        returns (bytes32 bookId)
    {
        bookId = isYesSide ? market.yesBookId : market.noBookId;
        if (bookId == bytes32(0)) {
            bookId = LibCLOBBook.marketBookId(market.marketId, isYesSide);
        }
    }

    function requireExecutableBook(LibEveMarket.EveMarketStorage storage state, bytes32 bookId)
        internal
        view
        returns (LibEveMarket.Book storage book)
    {
        book = LibCLOBBook.requireBook(state, bookId);
        if (!book.active) {
            revert Errors.BookNotActive(bookId);
        }
        if (!LibCLOBBook.canExecute(book)) {
            revert Errors.MarketNotTrading(book.marketId);
        }
        if (book.marketId == bytes32(0) && block.timestamp >= book.expiryTime) {
            revert Errors.BookNotActive(bookId);
        }
    }

    function bookAssetIdsMatch(LibEveMarket.Book storage book) internal view returns (bool) {
        if (book.assetType != LibEveMarket.BookAssetType.ERC1155 || book.marketId == bytes32(0)) {
            return true;
        }

        LibEveMarket.Market storage market = LibEveMarket.store().markets[book.marketId];
        if (market.marketId == bytes32(0) || market.positionTokenType != LibEveMarket.PositionTokenType.CTF) {
            return true;
        }

        (uint256 yesPositionId, uint256 noPositionId) =
            LibCTF.derivePositionIds(market.positionToken, market.collateralToken, market.conditionId);
        uint256 expected = book.isYesSide ? yesPositionId : noPositionId;
        return expected == book.baseTokenId;
    }

    function requireCurveOwner(uint256 curveId, LibEveMarket.StoredCurve storage curve, address caller) internal view {
        if (!curve.active) {
            revert Errors.CurveNotActive(curveId);
        }
        if (curve.maker != caller) {
            revert Errors.NotCurveOwner(caller, curve.maker);
        }
    }
}
