// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {CurveCLOBTypes} from "../types/CurveCLOBTypes.sol";
import {Errors} from "./Errors.sol";
import {Events} from "./Events.sol";
import {LibCurvePacking} from "./LibCurvePacking.sol";
import {LibDiamond} from "./LibDiamond.sol";
import {LibEveMarket} from "./LibEveMarket.sol";

library LibCLOBBook {
    using SafeERC20 for IERC20;

    bytes32 internal constant MARKET_BOOK_DOMAIN = keccak256("eve.clob.market.book");
    bytes32 internal constant MULTI_OUTCOME_BOOK_DOMAIN = keccak256("eve.clob.multi.outcome.book");
    bytes32 internal constant STANDALONE_BOOK_DOMAIN = keccak256("eve.clob.standalone.book");
    uint128 internal constant SPOT_PRICE_DENOMINATOR = 1e18;

    struct BookRegistration {
        bytes32 bookId;
        bytes32 marketId;
        bool isYesSide;
        LibEveMarket.BookAssetType assetType;
        LibEveMarket.BaseTransferMode baseTransferMode;
        address baseToken;
        uint256 baseTokenId;
        address quoteToken;
        address creator;
        uint64 createdAt;
        uint64 expiryTime;
        LibEveMarket.BookFeeConfig feeConfig;
        LibEveMarket.BookPricingMode pricingMode;
        uint8 tickPresetId;
        uint128 tickSize;
        uint128 priceDenominator;
        uint128 minTick;
        uint128 maxTick;
    }

    struct SpotTickConfig {
        uint8 tickPresetId;
        uint128 tickSize;
        uint128 priceDenominator;
        uint128 minTick;
        uint128 maxTick;
    }

    function marketBookId(bytes32 marketId, bool isYesSide) internal pure returns (bytes32 bookId) {
        bookId = keccak256(abi.encode(MARKET_BOOK_DOMAIN, marketId, isYesSide));
    }

    function multiOutcomeBookId(bytes32 marketId, uint8 outcome) internal pure returns (bytes32 bookId) {
        bookId = keccak256(abi.encode(MULTI_OUTCOME_BOOK_DOMAIN, marketId, outcome));
    }

    function standaloneBookId(
        address creator,
        LibEveMarket.BookAssetType assetType,
        LibEveMarket.BaseTransferMode baseTransferMode,
        address baseToken,
        uint256 baseTokenId,
        address quoteToken,
        uint8 tickPresetId,
        bytes32 salt
    ) internal pure returns (bytes32 bookId) {
        if (assetType == LibEveMarket.BookAssetType.ERC20) {
            return keccak256(abi.encode(STANDALONE_BOOK_DOMAIN, assetType, baseToken, quoteToken));
        }

        bookId = keccak256(
            abi.encode(
                STANDALONE_BOOK_DOMAIN,
                creator,
                assetType,
                baseTransferMode,
                baseToken,
                baseTokenId,
                quoteToken,
                tickPresetId,
                salt
            )
        );
    }

    function spotTickConfig(uint8 tickPresetId) internal pure returns (SpotTickConfig memory config) {
        uint128 tickSize = _spotTickSizeForPreset(tickPresetId);
        config = SpotTickConfig({
            tickPresetId: tickPresetId,
            tickSize: tickSize,
            priceDenominator: SPOT_PRICE_DENOMINATOR,
            minTick: 1,
            maxTick: type(uint128).max / tickSize
        });
    }

    function setMarketBookIds(LibEveMarket.Market storage market) internal {
        market.yesBookId = marketBookId(market.marketId, true);
        market.noBookId = marketBookId(market.marketId, false);
    }

    function ensureMarketSideBook(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.Market storage market,
        bool isYesSide
    ) internal returns (LibEveMarket.Book storage book) {
        setMarketBookIds(market);

        bytes32 bookId = isYesSide ? market.yesBookId : market.noBookId;
        book = state.books[bookId];
        if (book.bookId == bookId) {
            return book;
        }

        _registerBook(
            book,
            BookRegistration({
                bookId: bookId,
                marketId: market.marketId,
                isYesSide: isYesSide,
                assetType: LibEveMarket.BookAssetType.ERC1155,
                baseTransferMode: LibEveMarket.BaseTransferMode.EXACT,
                baseToken: market.positionToken,
                baseTokenId: isYesSide ? market.yesPositionId : market.noPositionId,
                quoteToken: market.collateralToken,
                creator: market.creator,
                createdAt: market.createdAt,
                expiryTime: market.expiryTime,
                feeConfig: market.orderbookFeeConfig,
                pricingMode: LibEveMarket.BookPricingMode.PREDICTION_PAYOUT,
                tickPresetId: 0,
                tickSize: 1,
                priceDenominator: uint128(LibCurvePacking.PRICE_SCALE),
                minTick: 1,
                maxTick: uint128(LibCurvePacking.PRICE_SCALE)
            })
        );
    }

    function registerStandaloneBook(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bookId,
        LibEveMarket.BookAssetType assetType,
        LibEveMarket.BaseTransferMode baseTransferMode,
        address baseToken,
        uint256 baseTokenId,
        address quoteToken,
        uint8 tickPresetId,
        LibEveMarket.BookFeeConfig memory feeConfig,
        address creator
    ) internal {
        SpotTickConfig memory tickConfig = spotTickConfig(tickPresetId);
        _registerBook(
            state.books[bookId],
            BookRegistration({
                bookId: bookId,
                marketId: bytes32(0),
                isYesSide: false,
                assetType: assetType,
                baseTransferMode: baseTransferMode,
                baseToken: baseToken,
                baseTokenId: baseTokenId,
                quoteToken: quoteToken,
                creator: creator,
                createdAt: uint64(block.timestamp),
                expiryTime: type(uint64).max,
                feeConfig: feeConfig,
                pricingMode: LibEveMarket.BookPricingMode.GENERIC,
                tickPresetId: tickConfig.tickPresetId,
                tickSize: tickConfig.tickSize,
                priceDenominator: tickConfig.priceDenominator,
                minTick: tickConfig.minTick,
                maxTick: tickConfig.maxTick
            })
        );
    }

    function registerComboMarketBook(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bookId,
        bytes32 marketId,
        bool isYesSide,
        address positionToken,
        uint256 positionId,
        address collateralToken,
        uint64 expiryTime,
        address creator
    ) internal {
        _registerBook(
            state.books[bookId],
            BookRegistration({
                bookId: bookId,
                marketId: marketId,
                isYesSide: isYesSide,
                assetType: LibEveMarket.BookAssetType.ERC1155,
                baseTransferMode: LibEveMarket.BaseTransferMode.EXACT,
                baseToken: positionToken,
                baseTokenId: positionId,
                quoteToken: collateralToken,
                creator: creator,
                createdAt: uint64(block.timestamp),
                expiryTime: expiryTime,
                feeConfig: comboMarketFeeConfig(state.config.comboFeeConfig),
                pricingMode: LibEveMarket.BookPricingMode.PREDICTION_PAYOUT,
                tickPresetId: 0,
                tickSize: 1,
                priceDenominator: uint128(LibCurvePacking.PRICE_SCALE),
                minTick: 1,
                maxTick: uint128(LibCurvePacking.PRICE_SCALE)
            })
        );
    }

    function comboMarketFeeConfig(LibEveMarket.ComboFeeConfig storage feeConfig)
        internal
        view
        returns (LibEveMarket.BookFeeConfig memory bookFeeConfig)
    {
        bookFeeConfig = LibEveMarket.BookFeeConfig({
            entryFeeBps: feeConfig.tradeFeeBps,
            makerFeeBps: feeConfig.makerFeeBps,
            creatorFeeBps: feeConfig.creatorFeeBps,
            protocolFeeBps: feeConfig.protocolFeeBps,
            seniorPoolFeeBps: feeConfig.seniorPoolFeeBps,
            resolverFeeBps: feeConfig.resolverFeeBps
        });
    }

    function spotBookFeeConfig(LibEveMarket.SpotFeeConfig storage feeConfig)
        internal
        view
        returns (LibEveMarket.BookFeeConfig memory bookFeeConfig)
    {
        bookFeeConfig = LibEveMarket.BookFeeConfig({
            entryFeeBps: feeConfig.tradeFeeBps,
            makerFeeBps: feeConfig.makerFeeBps,
            creatorFeeBps: 0,
            protocolFeeBps: feeConfig.protocolFeeBps,
            seniorPoolFeeBps: feeConfig.seniorPoolFeeBps,
            resolverFeeBps: feeConfig.resolverFeeBps
        });
    }

    function bookInfo(LibEveMarket.Book storage book) internal view returns (CurveCLOBTypes.BookInfo memory info) {
        info = CurveCLOBTypes.BookInfo({
            bookId: book.bookId,
            marketId: book.marketId,
            isYesSide: book.isYesSide,
            assetType: book.assetType,
            baseTransferMode: book.baseTransferMode,
            baseToken: book.baseToken,
            baseTokenId: book.baseTokenId,
            quoteToken: book.quoteToken,
            creator: book.creator,
            active: book.active,
            createdAt: book.createdAt,
            expiryTime: book.expiryTime,
            lastTradePrice: uint128(book.lastTradePrice),
            totalCurveCount: book.curveCount,
            totalFeePool: book.totalFeePool,
            totalQuoteVolume: book.totalQuoteVolume,
            creatorFeesEscrowed: book.creatorFeesEscrowed,
            protocolFeesAccrued: book.protocolFeesAccrued,
            entryFeeBps: book.feeConfig.entryFeeBps,
            makerFeeBps: book.feeConfig.makerFeeBps,
            creatorFeeBps: book.feeConfig.creatorFeeBps,
            protocolFeeBps: book.feeConfig.protocolFeeBps,
            seniorPoolFeeBps: book.feeConfig.seniorPoolFeeBps,
            resolverFeeBps: book.feeConfig.resolverFeeBps,
            pricingMode: uint8(book.pricingMode),
            lifecycle: uint8(book.lifecycle),
            tickPresetId: book.tickPresetId,
            decommissionRequestedAt: book.decommissionRequestedAt,
            decommissionAvailableAt: book.decommissionAvailableAt,
            tickSize: book.tickSize,
            priceDenominator: book.priceDenominator,
            minTick: book.minTick,
            maxTick: book.maxTick,
            delayedExecutionEnabled: book.delayedExecutionEnabled
        });
    }

    function collectSpotBookCreationFee(LibEveMarket.EveMarketStorage storage state, bytes32 bookId, address creator)
        internal
    {
        uint128 fee = state.config.spotBookCreationFee;
        if (fee == 0 || creator == LibDiamond.contractOwner()) {
            return;
        }
        if (state.config.collateralToken == address(0) || state.config.eveTreasury == address(0)) {
            revert Errors.ZeroAddress();
        }

        IERC20(state.config.collateralToken).safeTransferFrom(creator, state.config.eveTreasury, fee);
        emit Events.SpotBookCreationFeePaid(bookId, creator, state.config.eveTreasury, fee);
    }

    function registerOutcomeBook(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bookId,
        bytes32 marketId,
        address positionToken,
        uint256 positionId,
        address collateralToken,
        uint64 createdAt,
        uint64 expiryTime,
        LibEveMarket.BookFeeConfig memory feeConfig,
        address creator
    ) internal {
        _registerBook(
            state.books[bookId],
            BookRegistration({
                bookId: bookId,
                marketId: marketId,
                isYesSide: false,
                assetType: LibEveMarket.BookAssetType.ERC1155,
                baseTransferMode: LibEveMarket.BaseTransferMode.EXACT,
                baseToken: positionToken,
                baseTokenId: positionId,
                quoteToken: collateralToken,
                creator: creator,
                createdAt: createdAt,
                expiryTime: expiryTime,
                feeConfig: feeConfig,
                pricingMode: LibEveMarket.BookPricingMode.PREDICTION_PAYOUT,
                tickPresetId: 0,
                tickSize: 1,
                priceDenominator: uint128(LibCurvePacking.PRICE_SCALE),
                minTick: 1,
                maxTick: uint128(LibCurvePacking.PRICE_SCALE)
            })
        );
    }

    function _spotTickSizeForPreset(uint8 tickPresetId) private pure returns (uint128 tickSize) {
        if (tickPresetId > 29) {
            revert Errors.InvalidTickPreset(tickPresetId);
        }

        uint8 decade = tickPresetId / 3;
        uint8 mantissaIndex = tickPresetId % 3;
        uint128 mantissa = mantissaIndex == 0 ? 1 : mantissaIndex == 1 ? 2 : 5;
        tickSize = mantissa * uint128(10 ** decade);
    }

    function _registerBook(LibEveMarket.Book storage book, BookRegistration memory input) private {
        if (book.bookId != bytes32(0)) {
            revert Errors.BookAlreadyExists(input.bookId);
        }
        if (input.baseToken == address(0) || input.quoteToken == address(0) || input.creator == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (input.assetType == LibEveMarket.BookAssetType.ERC20 && input.baseTokenId != 0) {
            revert Errors.InvalidAmount(input.baseTokenId);
        }
        if (
            input.baseTransferMode == LibEveMarket.BaseTransferMode.BALANCE_DELTA
                && input.assetType != LibEveMarket.BookAssetType.ERC20
        ) {
            revert Errors.UnsupportedBaseTransferMode(uint8(input.assetType), uint8(input.baseTransferMode));
        }

        book.bookId = input.bookId;
        book.marketId = input.marketId;
        book.isYesSide = input.isYesSide;
        book.assetType = input.assetType;
        book.baseTransferMode = input.baseTransferMode;
        book.baseToken = input.baseToken;
        book.baseTokenId = input.baseTokenId;
        book.quoteToken = input.quoteToken;
        book.creator = input.creator;
        book.createdAt = input.createdAt;
        book.expiryTime = input.expiryTime;
        book.active = true;
        book.feeConfig = input.feeConfig;
        book.pricingMode = input.pricingMode;
        book.lifecycle = LibEveMarket.BookLifecycle.ACTIVE;
        book.tickPresetId = input.tickPresetId;
        book.decommissionRequestedAt = 0;
        book.decommissionAvailableAt = 0;
        book.tickSize = input.tickSize;
        book.priceDenominator = input.priceDenominator;
        book.minTick = input.minTick;
        book.maxTick = input.maxTick;

        emit Events.BookCreated(
            input.bookId,
            input.marketId,
            input.creator,
            uint8(input.assetType),
            input.baseToken,
            input.baseTokenId,
            input.quoteToken,
            input.isYesSide
        );
    }

    function requireBook(LibEveMarket.EveMarketStorage storage state, bytes32 bookId)
        internal
        view
        returns (LibEveMarket.Book storage book)
    {
        book = state.books[bookId];
        if (book.bookId != bookId) {
            revert Errors.BookNotFound(bookId);
        }
    }

    function canExecuteMarketBook(LibEveMarket.Market storage market) internal view returns (bool) {
        if (market.marketId == bytes32(0) || block.timestamp < market.tradingStartTime) {
            return false;
        }

        if (market.state == LibEveMarket.MarketState.Scheduled) {
            return block.timestamp < market.expiryTime;
        }

        return market.state == LibEveMarket.MarketState.Trading;
    }

    function canPostToMarketBook(LibEveMarket.Market storage market) internal view returns (bool) {
        if (market.marketId == bytes32(0)) {
            return false;
        }

        if (market.state == LibEveMarket.MarketState.Scheduled) {
            return block.timestamp < market.expiryTime;
        }

        return market.state == LibEveMarket.MarketState.Trading;
    }

    function canExecute(LibEveMarket.Book storage book) internal view returns (bool) {
        if (!book.active || book.lifecycle != LibEveMarket.BookLifecycle.ACTIVE) {
            return false;
        }

        if (book.marketId == bytes32(0)) {
            return block.timestamp < book.expiryTime;
        }

        LibEveMarket.Market storage market = LibEveMarket.store().markets[book.marketId];
        if (market.marketId == bytes32(0)) {
            LibEveMarket.ComboMarket storage comboMarket = LibEveMarket.store().comboMarkets[book.marketId];
            return comboMarket.exists && block.timestamp < comboMarket.expiryTime;
        }
        return canExecuteMarketBook(market);
    }
}
