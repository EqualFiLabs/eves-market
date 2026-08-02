// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Errors} from "./Errors.sol";
import {LibCLOBBook} from "./LibCLOBBook.sol";
import {LibCurvePacking} from "./LibCurvePacking.sol";
import {LibEveMarket} from "./LibEveMarket.sol";

library LibBookPricing {
    struct TickConfig {
        uint8 tickPresetId;
        uint128 tickSize;
        uint128 priceDenominator;
        uint128 minTick;
        uint128 maxTick;
    }

    function effectiveTickConfig(LibEveMarket.Book storage book, uint256 packed)
        internal
        view
        returns (TickConfig memory config)
    {
        uint8 tickPresetId = LibCurvePacking.extractTickPresetId(packed);
        if (book.pricingMode == LibEveMarket.BookPricingMode.GENERIC) {
            LibCLOBBook.SpotTickConfig memory spotConfig = LibCLOBBook.spotTickConfig(tickPresetId);
            config = TickConfig({
                tickPresetId: spotConfig.tickPresetId,
                tickSize: spotConfig.tickSize,
                priceDenominator: book.priceDenominator,
                minTick: spotConfig.minTick,
                maxTick: spotConfig.maxTick
            });
            return config;
        }

        if (tickPresetId != 0) {
            revert Errors.InvalidTickPreset(tickPresetId);
        }
        config = TickConfig({
            tickPresetId: book.tickPresetId,
            tickSize: book.tickSize,
            priceDenominator: book.priceDenominator,
            minTick: book.minTick,
            maxTick: book.maxTick
        });
    }

    function resolveCurveTickPreset(LibEveMarket.Book storage book, uint8 requestedTickPresetId)
        internal
        view
        returns (uint8 tickPresetId)
    {
        if (book.pricingMode != LibEveMarket.BookPricingMode.GENERIC) {
            if (requestedTickPresetId != 0 && requestedTickPresetId != LibCurvePacking.DEFAULT_TICK_PRESET_SENTINEL) {
                revert Errors.InvalidTickPreset(requestedTickPresetId);
            }
            return 0;
        }

        tickPresetId = requestedTickPresetId == LibCurvePacking.DEFAULT_TICK_PRESET_SENTINEL
            ? book.tickPresetId
            : requestedTickPresetId;
        LibCLOBBook.spotTickConfig(tickPresetId);
    }

    function validateTick(LibEveMarket.Book storage book, uint256 packed, uint128 tick) internal view {
        validateTick(effectiveTickConfig(book, packed), tick);
    }

    function validateTick(TickConfig memory config, uint128 tick) internal pure {
        if (config.tickSize == 0 || config.priceDenominator == 0) {
            revert Errors.InvalidAmount(0);
        }
        if (tick < config.minTick || tick > config.maxTick) {
            revert LibCurvePacking.CurvePriceOutOfRange();
        }
    }

    function validateTick(LibEveMarket.Book storage book, uint128 tick) internal view {
        if (book.tickSize == 0 || book.priceDenominator == 0) {
            revert Errors.InvalidAmount(0);
        }
        if (tick < book.minTick || tick > book.maxTick) {
            revert LibCurvePacking.CurvePriceOutOfRange();
        }
    }

    function priceFromTick(LibEveMarket.Book storage book, uint256 packed, uint128 tick)
        internal
        view
        returns (uint128 price)
    {
        TickConfig memory config = effectiveTickConfig(book, packed);
        price = priceFromTick(config, tick);
    }

    function priceFromTick(TickConfig memory config, uint128 tick) internal pure returns (uint128 price) {
        validateTick(config, tick);

        uint256 priceNumerator = uint256(tick) * uint256(config.tickSize);
        if (priceNumerator > type(uint128).max) {
            revert Errors.InvalidAmount(priceNumerator);
        }
        price = uint128(priceNumerator);
    }

    function priceFromTick(LibEveMarket.Book storage book, uint128 tick) internal view returns (uint128 price) {
        validateTick(book, tick);

        uint256 priceNumerator = uint256(tick) * uint256(book.tickSize);
        if (priceNumerator > type(uint128).max) {
            revert Errors.InvalidAmount(priceNumerator);
        }
        price = uint128(priceNumerator);
    }

    function grossCostFor(LibEveMarket.Book storage book, uint128 baseAmount, uint128 priceNumerator)
        internal
        view
        returns (uint128 grossCost)
    {
        uint256 rawCost = (uint256(baseAmount) * uint256(priceNumerator)) / uint256(book.priceDenominator);
        if (rawCost > type(uint128).max) {
            revert Errors.InvalidAmount(rawCost);
        }
        grossCost = uint128(rawCost);
    }

    function baseForQuote(LibEveMarket.Book storage book, uint128 quoteAmount, uint128 priceNumerator)
        internal
        view
        returns (uint128 baseAmount)
    {
        if (priceNumerator == 0) {
            return type(uint128).max;
        }

        uint256 rawBase = (uint256(quoteAmount) * uint256(book.priceDenominator)) / uint256(priceNumerator);
        if (rawBase > type(uint128).max) {
            return type(uint128).max;
        }
        baseAmount = uint128(rawBase);
    }

    function averagePrice(LibEveMarket.Book storage book, uint128 totalQuoteUsed, uint128 totalBaseOut)
        internal
        view
        returns (uint128 averagePriceNumerator)
    {
        if (totalBaseOut == 0) {
            return 0;
        }

        uint256 rawAverage = (uint256(totalQuoteUsed) * uint256(book.priceDenominator)) / uint256(totalBaseOut);
        if (rawAverage > type(uint128).max) {
            revert Errors.InvalidAmount(rawAverage);
        }
        averagePriceNumerator = uint128(rawAverage);
    }

    function complementPrice(LibEveMarket.Book storage book, uint128 priceNumerator)
        internal
        view
        returns (uint128 complement)
    {
        if (priceNumerator > book.priceDenominator) {
            revert LibCurvePacking.CurvePriceOutOfRange();
        }
        complement = book.priceDenominator - priceNumerator;
    }
}
