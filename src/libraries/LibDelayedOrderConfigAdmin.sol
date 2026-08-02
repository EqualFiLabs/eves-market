// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Errors} from "./Errors.sol";
import {LibAdminConfig} from "./LibAdminConfig.sol";
import {LibDelayedOrder} from "./LibDelayedOrder.sol";
import {LibEveMarket} from "./LibEveMarket.sol";

library LibDelayedOrderConfigAdmin {
    function setConfig(
        LibEveMarket.MarketConfig storage config,
        uint64 protectionDelayBlocks,
        uint64 executionGraceBlocks,
        uint24 restingDurationMinutes
    ) internal {
        LibAdminConfig.emitConfigUpdate(
            "delayedProtectionBlocks", config.delayedOrderProtectionDelayBlocks, protectionDelayBlocks
        );
        LibAdminConfig.emitConfigUpdate(
            "delayedExecutionGraceBlocks", config.delayedOrderExecutionGraceBlocks, executionGraceBlocks
        );
        LibAdminConfig.emitConfigUpdate(
            "delayedRestingMinutes", config.delayedOrderRestingDurationMinutes, restingDurationMinutes
        );

        config.delayedOrderProtectionDelayBlocks = protectionDelayBlocks;
        config.delayedOrderExecutionGraceBlocks = executionGraceBlocks;
        config.delayedOrderRestingDurationMinutes = restingDurationMinutes;
    }

    function setProcessing(LibEveMarket.MarketConfig storage config, uint8 processingMode, uint16 processorFeeShareBps)
        internal
    {
        if (processingMode > uint8(LibEveMarket.ProcessingMode.Paused)) {
            revert Errors.InvalidAmount(processingMode);
        }
        LibAdminConfig.enforceBps(processorFeeShareBps);

        LibAdminConfig.emitConfigUpdate(
            "delayedOrderProcessingMode", uint8(config.delayedOrderProcessingMode), processingMode
        );
        LibAdminConfig.emitConfigUpdate(
            "delayedOrderProcessorFeeShareBps", config.delayedOrderProcessorFeeShareBps, processorFeeShareBps
        );
        config.delayedOrderProcessingMode = LibEveMarket.ProcessingMode(processingMode);
        config.delayedOrderProcessorFeeShareBps = processorFeeShareBps;
    }

    function setGuards(
        LibEveMarket.MarketConfig storage config,
        uint256 maxRouteLength,
        uint256 minQuoteWad,
        uint256 minBaseWad
    ) internal {
        if (maxRouteLength > type(uint32).max) {
            revert Errors.InvalidAmount(maxRouteLength);
        }
        if (minQuoteWad > type(uint128).max) {
            revert Errors.InvalidAmount(minQuoteWad);
        }
        if (minBaseWad > type(uint128).max) {
            revert Errors.InvalidAmount(minBaseWad);
        }

        LibAdminConfig.emitConfigUpdate("maxDelayedOrderRouteLength", config.maxDelayedOrderRouteLength, maxRouteLength);
        LibAdminConfig.emitConfigUpdate("minDelayedOrderQuoteWad", config.minDelayedOrderQuoteWad, minQuoteWad);
        LibAdminConfig.emitConfigUpdate("minDelayedOrderBaseWad", config.minDelayedOrderBaseWad, minBaseWad);

        config.maxDelayedOrderRouteLength = uint32(maxRouteLength);
        config.minDelayedOrderQuoteWad = uint128(minQuoteWad);
        config.minDelayedOrderBaseWad = uint128(minBaseWad);
    }

    function setProtocolProcessor(address processor, bool allowed) internal {
        if (processor == address(0)) {
            revert Errors.ZeroAddress();
        }

        bool previous = LibDelayedOrder.isProtocolProcessor(processor);
        LibDelayedOrder.setProtocolProcessor(processor, allowed);
        LibAdminConfig.emitConfigUpdateAddress(
            "delayedOrderProtocolProcessor", processor, allowed ? processor : address(0)
        );
        LibAdminConfig.emitConfigUpdate("delayedProcessorAllowed", previous ? 1 : 0, allowed ? 1 : 0);
    }

    function setMarketDelayedExecution(bytes32 marketId, bool enabled) internal {
        LibEveMarket.Market storage market = LibEveMarket.store().markets[marketId];
        if (market.marketId != marketId) {
            revert Errors.MarketNotFound(marketId);
        }

        bool previous = market.delayedExecutionEnabled;
        market.delayedExecutionEnabled = enabled;
        LibAdminConfig.emitConfigUpdate("marketDelayedExecutionEnabled", previous ? 1 : 0, enabled ? 1 : 0);
    }

    function setBookDelayedExecution(bytes32 bookId, bool enabled) internal {
        LibEveMarket.Book storage book = LibEveMarket.store().books[bookId];
        if (book.bookId != bookId) {
            revert Errors.BookNotFound(bookId);
        }

        bool previous = book.delayedExecutionEnabled;
        book.delayedExecutionEnabled = enabled;
        LibAdminConfig.emitConfigUpdate("bookDelayedExecutionEnabled", previous ? 1 : 0, enabled ? 1 : 0);
    }
}
