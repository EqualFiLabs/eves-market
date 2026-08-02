// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {CurveCLOBTypes} from "../types/CurveCLOBTypes.sol";
import {LibCLOBView} from "../libraries/LibCLOBView.sol";
import {LibCLOBBook} from "../libraries/LibCLOBBook.sol";
import {LibCurveIndex} from "../libraries/LibCurveIndex.sol";
import {LibCurveMath} from "../libraries/LibCurveMath.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";

contract BookViewFacet is CurveCLOBTypes {
    function previewBookExecution(bytes32 bookId, uint128 quoteIn, uint256[] calldata curveIds)
        external
        view
        returns (uint128 baseOut, uint128 fee, uint128 averagePrice, uint128 unfilledQuote)
    {
        return LibCLOBView.previewBookExecution(
            LibEveMarket.store(), bookId, quoteIn, curveIds, LibCLOBView.PreviewRouteMode.BestAsk
        );
    }

    function getBookCurveIdsPage(bytes32 bookId, uint256 cursor, uint256 limit)
        external
        view
        returns (uint256[] memory curveIds, uint256 nextCursor, uint256 total)
    {
        uint256[] storage stored = LibEveMarket.store().bookCurveIds[bookId];
        total = stored.length;
        nextCursor = LibCurveIndex.validatePage(cursor, limit, total);
        curveIds = new uint256[](nextCursor - cursor);
        for (uint256 i; i < curveIds.length; ++i) {
            curveIds[i] = stored[cursor + i];
        }
    }

    function getActiveBookCurveIdsPage(bytes32 bookId, uint256 cursor, uint256 limit)
        external
        view
        returns (uint256[] memory curveIds, uint256 nextCursor, uint256 total)
    {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        uint256[] storage stored = state.activeBookCurveIds[bookId];
        total = stored.length;
        nextCursor = LibCurveIndex.validatePage(cursor, limit, total);
        curveIds = new uint256[](nextCursor - cursor);
        bool bookExecutable = LibCLOBBook.canExecute(state.books[bookId]);
        uint256 count;
        for (uint256 i = cursor; i < nextCursor; ++i) {
            uint256 curveId = stored[i];
            if (!bookExecutable || !LibCurveIndex.isExecutableCandidate(state, curveId, state.curves[curveId])) {
                continue;
            }
            curveIds[count++] = curveId;
        }
        assembly ("memory-safe") {
            mstore(curveIds, count)
        }
    }

    function getBookTopOfBookPage(bytes32 bookId, uint256 cursor, uint256 limit)
        external
        view
        returns (
            uint128 bestAskPrice,
            bool hasAsk,
            uint128 bestBidPrice,
            bool hasBid,
            uint128 lastTradePrice,
            uint256 nextCursor,
            uint256 total
        )
    {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Book storage book = state.books[bookId];
        uint256[] storage stored = state.activeBookCurveIds[bookId];
        total = stored.length;
        nextCursor = LibCurveIndex.validatePage(cursor, limit, total);
        lastTradePrice = uint128(book.lastTradePrice);
        if (!LibCLOBBook.canExecute(book)) return (0, false, 0, false, lastTradePrice, nextCursor, total);
        for (uint256 i = cursor; i < nextCursor; ++i) {
            uint256 curveId = stored[i];
            LibEveMarket.StoredCurve storage curve = state.curves[curveId];
            if (!LibCurveIndex.isExecutableCandidate(state, curveId, curve)) continue;
            uint128 price = LibCurveMath.currentPrice(state, curve);
            if (curve.curveSide == LibEveMarket.CurveSide.ASK) {
                if (!hasAsk || price < bestAskPrice) {
                    hasAsk = true;
                    bestAskPrice = price;
                }
            } else if (!hasBid || price > bestBidPrice) {
                hasBid = true;
                bestBidPrice = price;
            }
        }
    }
}
