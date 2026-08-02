// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {CurveCLOBTypes} from "../types/CurveCLOBTypes.sol";
import {Errors} from "../libraries/Errors.sol";
import {Events} from "../libraries/Events.sol";
import {LibCLOBBook} from "../libraries/LibCLOBBook.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibMarketAccess} from "../libraries/LibMarketAccess.sol";
import {LibReentrancy} from "../libraries/LibReentrancy.sol";

contract BookFacet is CurveCLOBTypes {
    modifier nonReentrant() {
        LibReentrancy.enter();
        _;
        LibReentrancy.exit();
    }

    function createBook(
        LibEveMarket.BookAssetType assetType,
        LibEveMarket.BaseTransferMode baseTransferMode,
        address baseToken,
        uint256 baseTokenId,
        address quoteToken,
        uint8 tickPresetId,
        bytes32 salt
    ) external nonReentrant returns (bytes32 bookId) {
        bookId = LibCLOBBook.standaloneBookId(
            msg.sender, assetType, baseTransferMode, baseToken, baseTokenId, quoteToken, tickPresetId, salt
        );
        if (assetType != LibEveMarket.BookAssetType.ERC20) {
            revert Errors.BookAssetTypeMismatch(bookId, uint8(LibEveMarket.BookAssetType.ERC20), uint8(assetType));
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        if (state.books[bookId].bookId != bytes32(0)) {
            revert Errors.BookAlreadyExists(bookId);
        }

        LibCLOBBook.collectSpotBookCreationFee(state, bookId, msg.sender);
        LibCLOBBook.registerStandaloneBook(
            state,
            bookId,
            assetType,
            baseTransferMode,
            baseToken,
            baseTokenId,
            quoteToken,
            tickPresetId,
            LibCLOBBook.spotBookFeeConfig(state.config.spotFeeConfig),
            msg.sender
        );
    }

    function computeBookId(
        address creator,
        LibEveMarket.BookAssetType assetType,
        LibEveMarket.BaseTransferMode baseTransferMode,
        address baseToken,
        uint256 baseTokenId,
        address quoteToken,
        uint8 tickPresetId,
        bytes32 salt
    ) external pure returns (bytes32 bookId) {
        bookId = LibCLOBBook.standaloneBookId(
            creator, assetType, baseTransferMode, baseToken, baseTokenId, quoteToken, tickPresetId, salt
        );
    }

    function getBookInfo(bytes32 bookId) external view returns (BookInfo memory bookInfo) {
        LibEveMarket.Book storage book = LibCLOBBook.requireBook(LibEveMarket.store(), bookId);
        bookInfo = LibCLOBBook.bookInfo(book);
    }

    function isBookMaterialized(bytes32 bookId) external view returns (bool materialized) {
        materialized = LibEveMarket.store().books[bookId].bookId == bookId;
    }

    function getMarketSideBook(bytes32 marketId, bool isYesSide) external view returns (bytes32 bookId) {
        LibEveMarket.Market storage market = LibMarketAccess.requireExistingMarket(LibEveMarket.store(), marketId);
        bookId = isYesSide ? market.yesBookId : market.noBookId;
        if (bookId == bytes32(0)) {
            bookId = LibCLOBBook.marketBookId(marketId, isYesSide);
        }
    }

    function requestBookDecommission(bytes32 bookId) external nonReentrant {
        LibEveMarket.Book storage book = LibCLOBBook.requireBook(LibEveMarket.store(), bookId);
        _requireBookController(bookId, book);
        if (book.marketId != bytes32(0)) {
            revert Errors.BookDecommissionUnsupported(bookId);
        }
        if (book.lifecycle != LibEveMarket.BookLifecycle.ACTIVE) {
            revert Errors.BookNotActive(bookId);
        }

        uint64 requestedAt = uint64(block.timestamp);
        book.active = false;
        book.lifecycle = LibEveMarket.BookLifecycle.DECOMMISSION_PENDING;
        book.decommissionRequestedAt = requestedAt;
        book.decommissionAvailableAt = requestedAt;

        emit Events.BookDecommissionRequested(bookId, msg.sender, requestedAt, requestedAt);
    }

    function finalizeBookDecommission(bytes32 bookId) external nonReentrant {
        LibEveMarket.Book storage book = LibCLOBBook.requireBook(LibEveMarket.store(), bookId);
        _requireBookController(bookId, book);
        if (book.lifecycle != LibEveMarket.BookLifecycle.DECOMMISSION_PENDING) {
            revert Errors.BookNotDecommissionPending(bookId);
        }
        if (block.timestamp < book.decommissionAvailableAt) {
            revert Errors.BookDecommissionNotReady(bookId, book.decommissionAvailableAt);
        }

        book.active = false;
        book.lifecycle = LibEveMarket.BookLifecycle.DECOMMISSIONED;

        emit Events.BookDecommissioned(bookId, msg.sender);
    }

    function _requireBookController(bytes32 bookId, LibEveMarket.Book storage book) private view {
        if (msg.sender != book.creator && msg.sender != LibDiamond.contractOwner()) {
            revert Errors.NotBookController(msg.sender, bookId);
        }
    }
}
