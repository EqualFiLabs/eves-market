// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IBookViewFacet {
    function previewBookExecution(bytes32 bookId, uint128 quoteIn, uint256[] calldata curveIds)
        external
        view
        returns (uint128 baseOut, uint128 fee, uint128 averagePrice, uint128 unfilledQuote);

    function getBookTopOfBook(bytes32 bookId)
        external
        view
        returns (uint128 bestAskPrice, uint128 bestBidPrice, uint128 midpointPrice, uint128 lastTradePrice);
}
