// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {CurveCLOBTypes} from "../../src/types/CurveCLOBTypes.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {Events} from "../../src/libraries/Events.sol";
import {LibBookAccess} from "../../src/libraries/LibBookAccess.sol";
import {LibBookPricing} from "../../src/libraries/LibBookPricing.sol";
import {LibCurvePacking} from "../../src/libraries/LibCurvePacking.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {LibProductAdapter} from "../../src/libraries/LibProductAdapter.sol";
import {LibSafeCast} from "../../src/libraries/LibSafeCast.sol";
import {ProductAdapterTypes} from "../../src/types/ProductAdapterTypes.sol";

contract ProductAdapterHarnessFacet {
    struct AdapterCurveFixtureParams {
        bytes32 bookId;
        address maker;
        uint256 curveSide;
        uint256 volume;
        uint256 quoteEscrow;
        uint256 price;
        uint256 durationMinutes;
        bytes32 bucketId;
        bytes32 riskDomainId;
        bytes32 adapterDataKey;
    }

    struct NarrowedCurveParams {
        LibEveMarket.CurveSide curveSide;
        uint128 volume;
        uint128 quoteEscrow;
        uint72 price;
        uint24 durationMinutes;
    }

    function postAdapterCurveFixture(AdapterCurveFixtureParams calldata params) external returns (uint256 curveId) {
        NarrowedCurveParams memory narrowed = _narrow(params);

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Book storage book = LibBookAccess.requireExecutableBook(state, params.bookId);
        uint256 packed = _pack(book, narrowed.price, narrowed.durationMinutes);

        curveId = state.nextCurveId++;
        _writeCurve(state, book, curveId, params, narrowed, packed);

        LibProductAdapter.setAdapterCurveMetadata(
            state,
            curveId,
            ProductAdapterTypes.ProductAdapterKind.MLOPrediction,
            params.bucketId,
            params.riskDomainId,
            params.adapterDataKey
        );
    }

    function disableAdapterCurveFixture(uint256 curveId) external {
        LibProductAdapter.disableAdapterCurveMetadata(LibEveMarket.store(), curveId);
    }

    function requireActiveAdapterCurveFixture(uint256 curveId)
        external
        view
        returns (ProductAdapterTypes.AdapterCurveMetadata memory metadata)
    {
        metadata = LibProductAdapter.requireActiveAdapterCurve(LibEveMarket.store(), curveId);
    }

    function _narrow(AdapterCurveFixtureParams calldata params)
        private
        pure
        returns (NarrowedCurveParams memory narrowed)
    {
        if (params.curveSide > uint256(type(uint8).max) || params.durationMinutes > uint256(type(uint24).max)) {
            revert Errors.InvalidAmount(params.curveSide > uint256(type(uint8).max)
                    ? params.curveSide
                    : params.durationMinutes);
        }
        if (params.price > uint256(type(uint72).max)) {
            revert Errors.InvalidAmount(params.price);
        }
        LibEveMarket.CurveSide narrowedSide = LibEveMarket.CurveSide(uint8(params.curveSide));
        if (uint8(narrowedSide) > uint8(LibEveMarket.CurveSide.BID)) {
            revert Errors.InvalidAmount(params.curveSide);
        }
        narrowed = NarrowedCurveParams({
            curveSide: narrowedSide,
            volume: LibSafeCast.toUint128(params.volume),
            quoteEscrow: LibSafeCast.toUint128(params.quoteEscrow),
            price: uint72(params.price),
            durationMinutes: uint24(params.durationMinutes)
        });
    }

    function _pack(LibEveMarket.Book storage book, uint72 price, uint24 durationMinutes)
        private
        view
        returns (uint256 packed)
    {
        uint8 tickPresetId = LibBookPricing.resolveCurveTickPreset(book, LibCurvePacking.DEFAULT_TICK_PRESET_SENTINEL);
        packed = LibCurvePacking.pack(price, price, durationMinutes, 0, tickPresetId, bytes32(0));
        LibBookPricing.validateTick(book, packed, uint128(price));
    }

    function _writeCurve(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.Book storage book,
        uint256 curveId,
        AdapterCurveFixtureParams calldata params,
        NarrowedCurveParams memory narrowed,
        uint256 packed
    ) private {
        LibEveMarket.StoredCurve storage curve = state.curves[curveId];
        curve.packed = packed;
        curve.remainingVolume = narrowed.volume;
        curve.createdAt = uint64(block.timestamp);
        curve.generation = 1;
        curve.active = true;
        curve.isYesSide = book.isYesSide;
        curve.curveSide = narrowed.curveSide;
        curve.maker = params.maker;
        curve.bookId = params.bookId;
        curve.quoteEscrowRemaining = narrowed.quoteEscrow;
        state.bookCurveIds[params.bookId].push(curveId);
        book.curveCount += 1;
        if (book.marketId != bytes32(0) && state.markets[book.marketId].marketId != bytes32(0)) {
            state.markets[book.marketId].curveCount += 1;
        }

        emit Events.CurvePosted(book.marketId, curveId, params.maker, book.isYesSide, packed);
        emit Events.BookCurvePosted(
            params.bookId, book.marketId, curveId, params.maker, book.isYesSide, uint8(narrowed.curveSide), packed
        );
    }
}
