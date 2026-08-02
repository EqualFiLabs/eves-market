// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {CurveCLOBTypes} from "../types/CurveCLOBTypes.sol";

interface IBookAdminFacet {
    function createBook(
        LibEveMarket.BookAssetType assetType,
        LibEveMarket.BaseTransferMode baseTransferMode,
        address baseToken,
        uint256 baseTokenId,
        address quoteToken,
        uint8 tickPresetId,
        bytes32 salt
    ) external returns (bytes32 bookId);

    function computeBookId(
        address creator,
        LibEveMarket.BookAssetType assetType,
        LibEveMarket.BaseTransferMode baseTransferMode,
        address baseToken,
        uint256 baseTokenId,
        address quoteToken,
        uint8 tickPresetId,
        bytes32 salt
    ) external pure returns (bytes32 bookId);

    function getBookInfo(bytes32 bookId) external view returns (CurveCLOBTypes.BookInfo memory bookInfo);
    function isBookMaterialized(bytes32 bookId) external view returns (bool materialized);
    function getMarketSideBook(bytes32 marketId, bool isYesSide) external view returns (bytes32 bookId);
    function requestBookDecommission(bytes32 bookId) external;
    function finalizeBookDecommission(bytes32 bookId) external;
}
