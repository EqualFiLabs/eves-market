// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Math} from "../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

import {IMarkOracleFacet} from "../interfaces/IMarkOracleFacet.sol";
import {MarkOracleTypes} from "../types/MarkOracleTypes.sol";
import {Events} from "./Events.sol";
import {LibEveMarket} from "./LibEveMarket.sol";

library LibMarkOracle {
    uint8 internal constant OBSERVATION_CARDINALITY = 32;
    uint32 internal constant DEFAULT_CAUTION_THRESHOLD = 5 minutes;
    uint32 internal constant DEFAULT_STALE_THRESHOLD = 30 minutes;
    uint16 internal constant MAX_BPS = 10_000;

    function recordFill(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.Book storage book,
        uint128 price,
        uint128 baseVolume,
        uint128 quoteNotional
    ) internal {
        if (price == 0 || baseVolume == 0 || quoteNotional == 0) {
            return;
        }

        MarkOracleTypes.BookOracle storage oracle = state.markOracles[book.bookId];
        uint64 timestamp = uint64(block.timestamp);
        uint64 blockNumber = uint64(block.number);

        if (oracle.lastUpdatedAt != 0) {
            uint256 elapsed = timestamp - oracle.lastUpdatedAt;
            if (elapsed != 0) {
                oracle.priceCumulative += uint256(oracle.lastPrice) * elapsed;
            }
        }

        oracle.volumeCumulative += baseVolume;
        oracle.notionalCumulative += quoteNotional;
        oracle.lastPrice = price;
        oracle.lastUpdatedAt = timestamp;
        oracle.lastUpdatedBlock = blockNumber;

        _writeObservation(oracle, timestamp, blockNumber, price);
        _emitObservation(book, price, baseVolume, quoteNotional, timestamp, blockNumber);
    }

    function snapshot(LibEveMarket.EveMarketStorage storage state, bytes32 bookId)
        internal
        view
        returns (MarkOracleTypes.OracleSnapshot memory snapshot_)
    {
        LibEveMarket.Book storage book = state.books[bookId];
        if (book.bookId != bookId) {
            revert IMarkOracleFacet.MarkOracleBookNotFound(bookId);
        }

        MarkOracleTypes.BookOracle storage oracle = state.markOracles[bookId];
        snapshot_ = MarkOracleTypes.OracleSnapshot({
            bookId: bookId,
            marketId: book.marketId,
            isYesSide: book.isYesSide,
            state: stateFor(state, bookId),
            manualState: oracle.manualState,
            manualOverride: oracle.manualOverride,
            lastPrice: oracle.lastPrice,
            priceDenominator: book.priceDenominator,
            lastUpdatedAt: oracle.lastUpdatedAt,
            lastUpdatedBlock: oracle.lastUpdatedBlock,
            observationCount: _boundedCount(oracle),
            priceCumulative: _currentPriceCumulative(oracle),
            volumeCumulative: oracle.volumeCumulative,
            notionalCumulative: oracle.notionalCumulative
        });
    }

    function observation(LibEveMarket.EveMarketStorage storage state, bytes32 bookId, uint256 index)
        internal
        view
        returns (MarkOracleTypes.Observation memory observation_)
    {
        _requireBook(state, bookId);
        MarkOracleTypes.BookOracle storage oracle = state.markOracles[bookId];
        uint32 count = _boundedCount(oracle);
        if (index >= count) {
            revert IMarkOracleFacet.MarkOracleObservationNotFound(bookId, index);
        }

        observation_ = oracle.observations[_physicalIndex(oracle, index)];
    }

    function consultTwap(LibEveMarket.EveMarketStorage storage state, bytes32 bookId, uint32 lookbackSeconds)
        internal
        view
        returns (uint128 twapPrice, uint32 elapsedSeconds)
    {
        if (lookbackSeconds == 0) {
            revert IMarkOracleFacet.InvalidOracleLookback();
        }

        _requireBook(state, bookId);
        MarkOracleTypes.BookOracle storage oracle = state.markOracles[bookId];
        if (oracle.observationCount == 0) {
            return (0, 0);
        }

        MarkOracleTypes.Observation memory start = _windowStartObservation(oracle, lookbackSeconds);
        uint64 nowTimestamp = uint64(block.timestamp);
        if (nowTimestamp <= start.timestamp) {
            return (oracle.lastPrice, 0);
        }

        elapsedSeconds = uint32(nowTimestamp - start.timestamp);
        uint256 cumulativeDelta = _currentPriceCumulative(oracle) - start.priceCumulative;
        twapPrice = uint128(cumulativeDelta / elapsedSeconds);
    }

    function consultVwap(LibEveMarket.EveMarketStorage storage state, bytes32 bookId, uint32 lookbackSeconds)
        internal
        view
        returns (uint128 vwapPrice, uint256 volume)
    {
        if (lookbackSeconds == 0) {
            revert IMarkOracleFacet.InvalidOracleLookback();
        }

        LibEveMarket.Book storage book = _requireBook(state, bookId);
        MarkOracleTypes.BookOracle storage oracle = state.markOracles[bookId];
        if (oracle.observationCount == 0) {
            return (0, 0);
        }

        MarkOracleTypes.Observation memory start = _windowStartObservation(oracle, lookbackSeconds);
        volume = oracle.volumeCumulative - start.volumeCumulative;
        if (volume == 0) {
            return (0, 0);
        }

        uint256 notional = oracle.notionalCumulative - start.notionalCumulative;
        vwapPrice = uint128(Math.mulDiv(notional, book.priceDenominator, volume));
    }

    function riskMarkForBook(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bookId,
        MarkOracleTypes.RiskMarkConfig memory config_
    ) internal view returns (MarkOracleTypes.RiskMark memory mark) {
        validateRiskMarkConfig(config_);

        LibEveMarket.Book storage book = _requireBook(state, bookId);
        MarkOracleTypes.BookOracle storage oracle = state.markOracles[bookId];
        MarkOracleTypes.OracleState oracleState = stateFor(state, bookId);

        uint128 displayPrice = oracle.lastPrice;
        if (config_.lookbackSeconds != 0) {
            (displayPrice,) = consultTwap(state, bookId, config_.lookbackSeconds);
        }

        uint128 denominator = uint128(book.priceDenominator);
        uint128 assetRiskPrice = uint128(Math.mulDiv(displayPrice, MAX_BPS - config_.assetHaircutBps, MAX_BPS));
        uint256 liabilityPrice =
            Math.mulDiv(displayPrice, MAX_BPS + uint256(config_.liabilityPremiumBps), MAX_BPS, Math.Rounding.Ceil);
        if (book.assetType != LibEveMarket.BookAssetType.ERC20 && liabilityPrice > denominator) {
            liabilityPrice = denominator;
        }

        mark = MarkOracleTypes.RiskMark({
            oracleKey: bookId,
            state: oracleState,
            displayPrice: displayPrice,
            assetRiskPrice: assetRiskPrice,
            liabilityRiskPrice: uint128(liabilityPrice),
            priceDenominator: denominator,
            updatedAt: oracle.lastUpdatedAt
        });
    }

    function stateFor(LibEveMarket.EveMarketStorage storage state, bytes32 bookId)
        internal
        view
        returns (MarkOracleTypes.OracleState oracleState)
    {
        MarkOracleTypes.BookOracle storage oracle = state.markOracles[bookId];
        if (oracle.manualOverride) {
            return oracle.manualState;
        }
        if (oracle.observationCount == 0) {
            return MarkOracleTypes.OracleState.Uninitialized;
        }

        uint256 elapsed = block.timestamp - oracle.lastUpdatedAt;
        if (elapsed > staleThreshold(state)) {
            return MarkOracleTypes.OracleState.Stale;
        }
        if (elapsed > cautionThreshold(state)) {
            return MarkOracleTypes.OracleState.Caution;
        }

        return MarkOracleTypes.OracleState.Normal;
    }

    function config(LibEveMarket.EveMarketStorage storage state)
        internal
        view
        returns (MarkOracleTypes.OracleConfig memory config_)
    {
        config_ = MarkOracleTypes.OracleConfig({
            cautionThreshold: cautionThreshold(state), staleThreshold: staleThreshold(state)
        });
    }

    function setThresholds(
        LibEveMarket.EveMarketStorage storage state,
        uint32 cautionThreshold_,
        uint32 staleThreshold_
    ) internal {
        if (cautionThreshold_ == 0 || staleThreshold_ == 0 || cautionThreshold_ >= staleThreshold_) {
            revert IMarkOracleFacet.InvalidOracleThresholds(cautionThreshold_, staleThreshold_);
        }

        uint32 previousCautionThreshold = cautionThreshold(state);
        uint32 previousStaleThreshold = staleThreshold(state);
        state.markOracleCautionThreshold = cautionThreshold_;
        state.markOracleStaleThreshold = staleThreshold_;

        emit IMarkOracleFacet.MarkOracleThresholdsSet(
            previousCautionThreshold, cautionThreshold_, previousStaleThreshold, staleThreshold_
        );
    }

    function setManualState(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bookId,
        MarkOracleTypes.OracleState oracleState
    ) internal {
        _requireBook(state, bookId);
        if (
            oracleState != MarkOracleTypes.OracleState.Paused
                && oracleState != MarkOracleTypes.OracleState.ResolutionOnly
        ) {
            revert IMarkOracleFacet.InvalidOracleManualState(uint8(oracleState));
        }

        MarkOracleTypes.BookOracle storage oracle = state.markOracles[bookId];
        oracle.manualOverride = true;
        oracle.manualState = oracleState;

        emit IMarkOracleFacet.MarkOracleManualStateSet(bookId, true, oracleState);
    }

    function clearManualState(LibEveMarket.EveMarketStorage storage state, bytes32 bookId) internal {
        _requireBook(state, bookId);
        MarkOracleTypes.BookOracle storage oracle = state.markOracles[bookId];
        oracle.manualOverride = false;
        oracle.manualState = MarkOracleTypes.OracleState.Uninitialized;

        emit IMarkOracleFacet.MarkOracleManualStateSet(bookId, false, MarkOracleTypes.OracleState.Uninitialized);
    }

    function validateRiskMarkConfig(MarkOracleTypes.RiskMarkConfig memory config_) internal pure {
        if (config_.assetHaircutBps > MAX_BPS || config_.liabilityPremiumBps > MAX_BPS) {
            revert IMarkOracleFacet.InvalidRiskMarkConfig(
                config_.lookbackSeconds, config_.assetHaircutBps, config_.liabilityPremiumBps
            );
        }
    }

    function cautionThreshold(LibEveMarket.EveMarketStorage storage state) internal view returns (uint32 threshold) {
        threshold = state.markOracleCautionThreshold;
        if (threshold == 0) {
            threshold = DEFAULT_CAUTION_THRESHOLD;
        }
    }

    function staleThreshold(LibEveMarket.EveMarketStorage storage state) internal view returns (uint32 threshold) {
        threshold = state.markOracleStaleThreshold;
        if (threshold == 0) {
            threshold = DEFAULT_STALE_THRESHOLD;
        }
    }

    function _writeObservation(
        MarkOracleTypes.BookOracle storage oracle,
        uint64 timestamp,
        uint64 blockNumber,
        uint128 price
    ) internal {
        uint8 index = oracle.ringIndex;
        if (oracle.observationCount == 0) {
            oracle.observationCount = 1;
        } else if (oracle.observations[index].blockNumber != blockNumber) {
            index = oracle.observationCount < OBSERVATION_CARDINALITY
                ? uint8(oracle.observationCount)
                : uint8((uint256(index) + 1) % OBSERVATION_CARDINALITY);
            oracle.ringIndex = index;
            oracle.observationCount += 1;
        }

        oracle.observations[index] = MarkOracleTypes.Observation({
            timestamp: timestamp,
            blockNumber: blockNumber,
            price: price,
            priceCumulative: oracle.priceCumulative,
            volumeCumulative: oracle.volumeCumulative,
            notionalCumulative: oracle.notionalCumulative
        });
    }

    function _emitObservation(
        LibEveMarket.Book storage book,
        uint128 price,
        uint128 baseVolume,
        uint128 quoteNotional,
        uint64 timestamp,
        uint64 blockNumber
    ) internal {
        emit Events.MarkOracleObservationRecorded(
            book.bookId, book.marketId, book.isYesSide, price, baseVolume, quoteNotional, timestamp, blockNumber
        );
    }

    function _windowStartObservation(MarkOracleTypes.BookOracle storage oracle, uint32 lookbackSeconds)
        internal
        view
        returns (MarkOracleTypes.Observation memory start)
    {
        uint64 target = block.timestamp > lookbackSeconds ? uint64(block.timestamp - lookbackSeconds) : 0;
        uint32 count = _boundedCount(oracle);
        start = oracle.observations[_physicalIndex(oracle, 0)];

        if (target <= start.timestamp && oracle.observationCount <= OBSERVATION_CARDINALITY) {
            start.volumeCumulative = 0;
            start.notionalCumulative = 0;
            return start;
        }

        for (uint256 index = 1; index < count; ++index) {
            MarkOracleTypes.Observation memory candidate = oracle.observations[_physicalIndex(oracle, index)];
            if (candidate.timestamp > target) {
                break;
            }
            start = candidate;
        }
    }

    function _currentPriceCumulative(MarkOracleTypes.BookOracle storage oracle)
        internal
        view
        returns (uint256 cumulative)
    {
        cumulative = oracle.priceCumulative;
        if (oracle.lastUpdatedAt == 0) {
            return cumulative;
        }

        uint256 elapsed = block.timestamp - oracle.lastUpdatedAt;
        if (elapsed != 0) {
            cumulative += uint256(oracle.lastPrice) * elapsed;
        }
    }

    function _boundedCount(MarkOracleTypes.BookOracle storage oracle) internal view returns (uint32 count) {
        uint32 observations = oracle.observationCount;
        count = observations < OBSERVATION_CARDINALITY ? observations : OBSERVATION_CARDINALITY;
    }

    function _physicalIndex(MarkOracleTypes.BookOracle storage oracle, uint256 logicalIndex)
        internal
        view
        returns (uint256 index)
    {
        if (oracle.observationCount < OBSERVATION_CARDINALITY) {
            return logicalIndex;
        }

        uint256 oldestIndex = (uint256(oracle.ringIndex) + 1) % OBSERVATION_CARDINALITY;
        index = (oldestIndex + logicalIndex) % OBSERVATION_CARDINALITY;
    }

    function _requireBook(LibEveMarket.EveMarketStorage storage state, bytes32 bookId)
        internal
        view
        returns (LibEveMarket.Book storage book)
    {
        book = state.books[bookId];
        if (book.bookId != bookId) {
            revert IMarkOracleFacet.MarkOracleBookNotFound(bookId);
        }
    }
}
