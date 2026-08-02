// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IBookViewFacet {
    function previewBookExecution(bytes32 bookId, uint128 quoteIn, uint256[] calldata curveIds)
        external
        view
        returns (uint128 baseOut, uint128 fee, uint128 averagePrice, uint128 unfilledQuote);

    function getBookCurveIdsPage(bytes32 bookId, uint256 cursor, uint256 limit)
        external
        view
        returns (uint256[] memory curveIds, uint256 nextCursor, uint256 total);

    function getActiveBookCurveIdsPage(bytes32 bookId, uint256 cursor, uint256 limit)
        external
        view
        returns (uint256[] memory curveIds, uint256 nextCursor, uint256 total);

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
        );
}
