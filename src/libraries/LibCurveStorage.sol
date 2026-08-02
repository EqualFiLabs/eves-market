// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Events} from "./Events.sol";
import {Errors} from "./Errors.sol";
import {LibBookPricing} from "./LibBookPricing.sol";
import {LibCurvePacking} from "./LibCurvePacking.sol";
import {LibCurveIndex} from "./LibCurveIndex.sol";
import {LibEveMarket} from "./LibEveMarket.sol";

library LibCurveStorage {
    uint8 internal constant LINEAR_PROFILE_ID = 0;

    struct FlatCurveFromEscrowParams {
        bytes32 bookId;
        address maker;
        LibEveMarket.CurveSide curveSide;
        uint128 volume;
        uint128 quoteEscrow;
        uint72 price;
        uint24 durationMinutes;
    }

    function createFlatCurveFromEscrow(
        LibEveMarket.EveMarketStorage storage state,
        FlatCurveFromEscrowParams memory params
    ) internal returns (uint256 curveId) {
        if (params.maker == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (params.volume == 0) {
            revert Errors.InvalidAmount(0);
        }

        LibEveMarket.Book storage book = state.books[params.bookId];
        if (book.bookId != params.bookId) {
            revert Errors.BookNotFound(params.bookId);
        }

        if (params.curveSide == LibEveMarket.CurveSide.BID) {
            if (params.quoteEscrow == 0) {
                revert Errors.InvalidAmount(0);
            }
        } else if (params.quoteEscrow != 0) {
            revert Errors.InvalidAmount(params.quoteEscrow);
        }

        uint8 tickPresetId = LibBookPricing.resolveCurveTickPreset(book, LibCurvePacking.DEFAULT_TICK_PRESET_SENTINEL);
        uint256 packed = LibCurvePacking.pack(
            params.price, params.price, params.durationMinutes, LINEAR_PROFILE_ID, tickPresetId, bytes32(0)
        );
        LibBookPricing.validateTick(book, packed, params.price);

        curveId = state.nextCurveId++;
        storeCurve(
            state.curves[curveId],
            params.bookId,
            params.maker,
            book.isYesSide,
            params.curveSide,
            params.volume,
            params.quoteEscrow,
            packed,
            curveId
        );

        incrementCurveCount(state, book);
    }

    function incrementCurveCount(LibEveMarket.EveMarketStorage storage state, LibEveMarket.Book storage book) internal {
        incrementCurveCountBy(state, book, 1);
    }

    function incrementCurveCountBy(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.Book storage book,
        uint256 count
    ) internal {
        book.curveCount += count;
        if (book.marketId != bytes32(0) && state.markets[book.marketId].marketId != bytes32(0)) {
            state.markets[book.marketId].curveCount += count;
        }
    }

    function storeCurve(
        LibEveMarket.StoredCurve storage curve,
        bytes32 bookId,
        address maker,
        bool isYesSide,
        LibEveMarket.CurveSide curveSide,
        uint128 volume,
        uint128 quoteEscrow,
        uint256 packed,
        uint256 curveId
    ) internal {
        _writeCurve(curve, bookId, maker, isYesSide, curveSide, volume, quoteEscrow, packed);

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        state.bookCurveIds[bookId].push(curveId);
        LibCurveIndex.registerCreatedCurve(state, curveId);
        _emitCurvePosted(state, bookId, maker, isYesSide, curveSide, packed, curveId);
    }

    function storeCurveRecord(
        LibEveMarket.StoredCurve storage curve,
        bytes32 bookId,
        address maker,
        bool isYesSide,
        LibEveMarket.CurveSide curveSide,
        uint128 volume,
        uint128 quoteEscrow,
        uint256 packed,
        uint256 curveId
    ) internal {
        _writeCurve(curve, bookId, maker, isYesSide, curveSide, volume, quoteEscrow, packed);
        _emitCurvePosted(LibEveMarket.store(), bookId, maker, isYesSide, curveSide, packed, curveId);
    }

    function _writeCurve(
        LibEveMarket.StoredCurve storage curve,
        bytes32 bookId,
        address maker,
        bool isYesSide,
        LibEveMarket.CurveSide curveSide,
        uint128 volume,
        uint128 quoteEscrow,
        uint256 packed
    ) private {
        curve.packed = packed;
        curve.remainingVolume = volume;
        curve.createdAt = uint64(block.timestamp);
        curve.generation = 1;
        curve.active = true;
        curve.isYesSide = isYesSide;
        curve.curveSide = curveSide;
        curve.maker = maker;
        curve.bookId = bookId;
        curve.quoteEscrowRemaining = quoteEscrow;
    }

    function _emitCurvePosted(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bookId,
        address maker,
        bool isYesSide,
        LibEveMarket.CurveSide curveSide,
        uint256 packed,
        uint256 curveId
    ) private {
        LibEveMarket.Book storage book = state.books[bookId];
        emit Events.CurvePosted(book.marketId, curveId, maker, isYesSide, packed);
        emit Events.BookCurvePosted(bookId, book.marketId, curveId, maker, isYesSide, uint8(curveSide), packed);
    }
}
