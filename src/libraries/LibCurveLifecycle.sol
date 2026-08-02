// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC1155} from "../../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";

import {CurveCLOBTypes} from "../types/CurveCLOBTypes.sol";
import {Errors} from "./Errors.sol";
import {Events} from "./Events.sol";
import {LibBookAccess} from "./LibBookAccess.sol";
import {LibBookPricing} from "./LibBookPricing.sol";
import {LibCLOBBook} from "./LibCLOBBook.sol";
import {LibCurveEscrow} from "./LibCurveEscrow.sol";
import {LibCurveMath} from "./LibCurveMath.sol";
import {LibCurvePacking} from "./LibCurvePacking.sol";
import {LibCurveStorage} from "./LibCurveStorage.sol";
import {LibEveMarket} from "./LibEveMarket.sol";
import {LibProductAdapter} from "./LibProductAdapter.sol";
import {LibSafeCast} from "./LibSafeCast.sol";

library LibCurveLifecycle {
    using SafeERC20 for IERC20;

    uint8 internal constant EXPONENTIAL_DECAY_PROFILE_ID = 2;
    uint8 internal constant CUSTOM_PROFILE_ID = 3;

    struct CancelCache {
        bytes32 bookId;
        LibEveMarket.BookAssetType assetType;
        LibEveMarket.BaseTransferMode baseTransferMode;
        address baseToken;
        uint256 baseTokenId;
        address quoteToken;
        bool initialized;
    }

    function postCurve(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bookId,
        LibEveMarket.CurveSide curveSide,
        CurveCLOBTypes.CurveCreationParams memory params,
        address maker
    ) internal returns (uint256 curveId) {
        if (params.volume == 0) {
            revert Errors.InvalidAmount(params.volume);
        }

        LibEveMarket.Book storage book = LibBookAccess.requireExecutableBook(state, bookId);
        uint256 packed = packCurve(
            state,
            book,
            params.startPrice,
            params.endPrice,
            params.durationMinutes,
            params.profileId,
            params.tickPresetId
        );
        validatePackedCurve(state, bookId, packed);

        uint128 quoteEscrow;
        uint128 storedVolume = params.volume;
        if (curveSide == LibEveMarket.CurveSide.ASK) {
            storedVolume = LibCurveEscrow.escrowPostedInventory(book, maker, params.volume);
        } else {
            quoteEscrow = LibCurveMath.quoteEscrowRequiredForPacked(book, params.volume, packed);
            LibCurveEscrow.transferExactERC20From(book.quoteToken, maker, address(this), quoteEscrow);
        }

        curveId = state.nextCurveId++;
        LibCurveStorage.storeCurve(
            state.curves[curveId], bookId, maker, book.isYesSide, curveSide, storedVolume, quoteEscrow, packed, curveId
        );
        LibCurveStorage.incrementCurveCount(state, book);
    }

    function postMarketCurvesBatch(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.Market storage market,
        LibEveMarket.CurveSide curveSide,
        CurveCLOBTypes.CurveCreationParams[] calldata params,
        address maker
    ) internal returns (uint256[] memory curveIds) {
        uint256 length = params.length;
        if (length == 0) {
            revert Errors.InvalidAmount(length);
        }

        (uint256[] memory packedCurves, uint256 totalYesVolume, uint256 totalNoVolume, uint256 totalQuoteEscrow) =
            prepareCurvesBatch(state, market.yesBookId, market.noBookId, params);

        if (curveSide == LibEveMarket.CurveSide.ASK) {
            LibCurveEscrow.escrowPostedInventory(state.books[market.yesBookId], maker, asUint128(totalYesVolume));
            LibCurveEscrow.escrowPostedInventory(state.books[market.noBookId], maker, asUint128(totalNoVolume));
        } else {
            LibCurveEscrow.transferExactERC20From(
                market.collateralToken, maker, address(this), asUint128(totalQuoteEscrow)
            );
        }

        curveIds = new uint256[](length);
        uint256 nextCurveId = state.nextCurveId;
        for (uint256 index = 0; index < length; ++index) {
            curveIds[index] = storeMarketCurveFromBatch(
                state, market, curveSide, maker, params[index], packedCurves[index], nextCurveId
            );

            unchecked {
                ++nextCurveId;
            }
        }
        state.nextCurveId = nextCurveId;
    }

    function postCurvesBatch(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bookId,
        LibEveMarket.CurveSide curveSide,
        CurveCLOBTypes.CurveCreationParams[] calldata params,
        address maker
    ) internal returns (uint256[] memory curveIds) {
        uint256 length = params.length;
        if (length == 0) {
            revert Errors.InvalidAmount(length);
        }

        LibEveMarket.Book storage book = LibBookAccess.requireExecutableBook(state, bookId);
        (uint256[] memory packedCurves, uint256 totalYesVolume, uint256 totalNoVolume, uint256 totalQuoteEscrow) =
            prepareCurvesBatch(state, bookId, bookId, params);

        if (curveSide == LibEveMarket.CurveSide.ASK) {
            uint256 totalVolume = totalYesVolume + totalNoVolume;
            if (book.baseTransferMode == LibEveMarket.BaseTransferMode.BALANCE_DELTA) {
                revert Errors.UnsupportedBaseTransferMode(uint8(book.assetType), uint8(book.baseTransferMode));
            }
            LibCurveEscrow.escrowPostedInventory(book, maker, asUint128(totalVolume));
        } else {
            LibCurveEscrow.transferExactERC20From(book.quoteToken, maker, address(this), asUint128(totalQuoteEscrow));
        }

        curveIds = new uint256[](length);
        state.nextCurveId = storeCurvesBatch(state, bookId, maker, curveSide, params, packedCurves, curveIds);
        LibCurveStorage.incrementCurveCountBy(state, book, length);
    }

    function storeWrappedBidCurve(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bookId,
        address maker,
        uint128 volume,
        uint128 quoteEscrow,
        uint256 packed
    ) internal returns (uint256 curveId) {
        LibEveMarket.Book storage book = state.books[bookId];
        curveId = state.nextCurveId++;
        LibCurveStorage.storeCurve(
            state.curves[curveId],
            bookId,
            maker,
            book.isYesSide,
            LibEveMarket.CurveSide.BID,
            volume,
            quoteEscrow,
            packed,
            curveId
        );
        LibCurveStorage.incrementCurveCount(state, book);
    }

    function packCurve(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.Book storage book,
        uint72 startPrice,
        uint72 endPrice,
        uint24 durationMinutes,
        uint8 profileId,
        uint8 tickPresetId
    ) internal view returns (uint256 packed) {
        validateProfileId(state, profileId);
        uint8 resolvedTickPresetId = LibBookPricing.resolveCurveTickPreset(book, tickPresetId);
        packed =
            LibCurvePacking.pack(startPrice, endPrice, durationMinutes, profileId, resolvedTickPresetId, bytes32(0));
    }

    function prepareCurvesBatch(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 yesBookId,
        bytes32 noBookId,
        CurveCLOBTypes.CurveCreationParams[] calldata params
    )
        internal
        view
        returns (uint256[] memory packedCurves, uint256 totalYesVolume, uint256 totalNoVolume, uint256 totalQuoteEscrow)
    {
        uint256 length = params.length;
        packedCurves = new uint256[](length);

        for (uint256 index = 0; index < length; ++index) {
            CurveCLOBTypes.CurveCreationParams calldata params_ = params[index];
            if (params_.volume == 0) {
                revert Errors.InvalidAmount(params_.volume);
            }

            if (params_.isYesSide) {
                totalYesVolume += params_.volume;
            } else {
                totalNoVolume += params_.volume;
            }
            LibEveMarket.Book storage book = state.books[params_.isYesSide ? yesBookId : noBookId];
            packedCurves[index] = packCurve(
                state,
                book,
                params_.startPrice,
                params_.endPrice,
                params_.durationMinutes,
                params_.profileId,
                params_.tickPresetId
            );
            totalQuoteEscrow += LibCurveMath.quoteEscrowRequiredForPacked(book, params_.volume, packedCurves[index]);
        }
    }

    function prepareCurveTopUpsBatch(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 marketId,
        CurveCLOBTypes.CurveTopUpParams[] calldata params,
        address maker
    ) internal view returns (uint256 totalYesVolume, uint256 totalNoVolume, uint256 totalQuoteEscrow) {
        uint256 length = params.length;

        for (uint256 index = 0; index < length; ++index) {
            CurveCLOBTypes.CurveTopUpParams calldata params_ = params[index];
            if (params_.addedVolume == 0) {
                revert Errors.InvalidAmount(params_.addedVolume);
            }

            LibEveMarket.StoredCurve storage curve = state.curves[params_.curveId];
            requireCurveOwner(params_.curveId, curve, maker);
            LibProductAdapter.requireEscrowBackedCurve(state, params_.curveId);
            LibEveMarket.Book storage book = state.books[curve.bookId];
            if (book.marketId != marketId) {
                revert Errors.CurveMarketMismatch(marketId, book.marketId);
            }
            if (LibCurveMath.isExpired(state, curve)) {
                revert Errors.CurveExpired(params_.curveId);
            }

            if (curve.curveSide == LibEveMarket.CurveSide.BID) {
                totalQuoteEscrow += LibCurveMath.quoteEscrowRequiredForPacked(book, params_.addedVolume, curve.packed);
            } else if (curve.isYesSide) {
                totalYesVolume += params_.addedVolume;
            } else {
                totalNoVolume += params_.addedVolume;
            }
        }
    }

    function prepareBookCurveTopUpsBatch(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bookId,
        CurveCLOBTypes.CurveTopUpParams[] calldata params,
        address maker
    ) internal view returns (uint256 totalBaseVolume, uint256 totalQuoteEscrow) {
        uint256 length = params.length;

        for (uint256 index = 0; index < length; ++index) {
            CurveCLOBTypes.CurveTopUpParams calldata params_ = params[index];
            if (params_.addedVolume == 0) {
                revert Errors.InvalidAmount(params_.addedVolume);
            }

            LibEveMarket.StoredCurve storage curve = state.curves[params_.curveId];
            requireCurveOwner(params_.curveId, curve, maker);
            LibProductAdapter.requireEscrowBackedCurve(state, params_.curveId);
            if (curve.bookId != bookId) {
                revert Errors.CurveBookMismatch(bookId, curve.bookId);
            }
            if (LibCurveMath.isExpired(state, curve)) {
                revert Errors.CurveExpired(params_.curveId);
            }

            if (curve.curveSide == LibEveMarket.CurveSide.BID) {
                totalQuoteEscrow += LibCurveMath.quoteEscrowRequiredForPacked(
                    state.books[curve.bookId], params_.addedVolume, curve.packed
                );
            } else {
                totalBaseVolume += params_.addedVolume;
            }
        }
    }

    function applyCurveTopUpsBatch(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 marketId,
        CurveCLOBTypes.CurveTopUpParams[] calldata params,
        address maker
    ) internal {
        uint256 length = params.length;

        for (uint256 index = 0; index < length; ++index) {
            CurveCLOBTypes.CurveTopUpParams calldata params_ = params[index];
            LibEveMarket.StoredCurve storage curve = state.curves[params_.curveId];

            curve.remainingVolume += params_.addedVolume;
            if (curve.curveSide == LibEveMarket.CurveSide.BID) {
                curve.quoteEscrowRemaining += LibCurveMath.quoteEscrowRequiredForPacked(
                    state.books[curve.bookId], params_.addedVolume, curve.packed
                );
            }
            emit Events.CurveToppedUp(marketId, params_.curveId, maker, params_.addedVolume, curve.remainingVolume);
        }
    }

    function applySingleBaseCurveTopUp(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 marketId,
        uint256 curveId,
        address maker,
        uint128 actualAddedVolume
    ) internal {
        LibEveMarket.StoredCurve storage curve = state.curves[curveId];
        curve.remainingVolume += actualAddedVolume;
        emit Events.CurveToppedUp(marketId, curveId, maker, actualAddedVolume, curve.remainingVolume);
    }

    function updateCurve(
        LibEveMarket.EveMarketStorage storage state,
        uint256 curveId,
        uint256 newPacked,
        uint32 expectedGeneration,
        bytes32 cachedBookId,
        bool hasCachedBook,
        bool resetStartTime,
        address caller
    ) internal returns (bytes32 nextCachedBookId, bool cacheInitialized) {
        LibEveMarket.StoredCurve storage curve = state.curves[curveId];
        requireCurveOwner(curveId, curve, caller);
        LibProductAdapter.requireEscrowBackedCurve(state, curveId);

        if (expectedGeneration != curve.generation) {
            revert Errors.GenerationMismatch(expectedGeneration, curve.generation);
        }

        bytes32 bookId = curve.bookId;
        if (!hasCachedBook || bookId != cachedBookId) {
            if (state.books[bookId].bookId != bookId) {
                revert Errors.BookNotFound(bookId);
            }
            cachedBookId = bookId;
            hasCachedBook = true;
        }

        if (LibCurveMath.isExpired(state, curve)) {
            revert Errors.CurveExpired(curveId);
        }

        LibEveMarket.Book storage book = state.books[curve.bookId];
        validatePackedCurve(state, curve.bookId, newPacked);
        syncBidEscrowForCurveUpdate(book, curve, newPacked, caller);

        uint64 createdAt;
        if (resetStartTime) {
            createdAt = uint64(block.timestamp);
            curve.createdAt = createdAt;
        }

        unchecked {
            curve.generation += 1;
        }
        curve.packed = newPacked;

        emit Events.CurveUpdated(curveId, newPacked, curve.generation);
        if (resetStartTime) {
            emit Events.CurveUpdatedFromNow(curveId, newPacked, curve.generation, createdAt);
        }
        return (cachedBookId, hasCachedBook);
    }

    function cancelCurve(
        LibEveMarket.EveMarketStorage storage state,
        uint256 curveId,
        address maker,
        CancelCache memory cache
    ) internal returns (CancelCache memory nextCache) {
        LibEveMarket.StoredCurve storage curve = state.curves[curveId];
        requireCurveOwner(curveId, curve, maker);
        LibProductAdapter.requireEscrowBackedCurve(state, curveId);

        bytes32 bookId = curve.bookId;
        if (!cache.initialized || bookId != cache.bookId) {
            LibEveMarket.Book storage book = LibCLOBBook.requireBook(state, bookId);
            cache.bookId = bookId;
            cache.assetType = book.assetType;
            cache.baseTransferMode = book.baseTransferMode;
            cache.baseToken = book.baseToken;
            cache.baseTokenId = book.baseTokenId;
            cache.quoteToken = book.quoteToken;
            cache.initialized = true;
        }

        uint128 remainingVolume = curve.remainingVolume;
        uint128 quoteEscrowRemaining = curve.quoteEscrowRemaining;
        bool wasExpired = LibCurveMath.isExpired(state, curve);

        curve.active = false;
        curve.remainingVolume = 0;
        curve.quoteEscrowRemaining = 0;

        if (wasExpired) {
            emit Events.CurveExpired(curveId);
        }

        if (curve.curveSide == LibEveMarket.CurveSide.BID) {
            if (quoteEscrowRemaining != 0) {
                IERC20(cache.quoteToken).safeTransfer(maker, quoteEscrowRemaining);
            }
        } else if (remainingVolume != 0) {
            if (cache.assetType == LibEveMarket.BookAssetType.ERC20) {
                LibCurveEscrow.transferCachedBaseERC20(cache.baseToken, cache.baseTransferMode, maker, remainingVolume);
            } else {
                IERC1155(cache.baseToken).safeTransferFrom(address(this), maker, cache.baseTokenId, remainingVolume, "");
            }
        }

        emit Events.CurveCancelled(curveId);
        return cache;
    }

    function validatePackedCurve(LibEveMarket.EveMarketStorage storage state, bytes32 bookId, uint256 packed)
        internal
        view
    {
        LibCurvePacking.CurveParams memory params = LibCurvePacking.unpack(packed);
        LibEveMarket.Book storage book = state.books[bookId];
        LibBookPricing.validateTick(book, packed, params.startPrice);
        LibBookPricing.validateTick(book, packed, params.endPrice);

        validateProfileId(state, params.profileId);
    }

    function validateProfileId(LibEveMarket.EveMarketStorage storage state, uint8 profileId) internal view {
        if (profileId <= EXPONENTIAL_DECAY_PROFILE_ID) {
            return;
        }
        if (profileId == CUSTOM_PROFILE_ID && state.curveProfiles[profileId] != address(0)) {
            return;
        }

        revert Errors.InvalidProfileId(profileId);
    }

    function storeCurvesBatch(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bookId,
        address maker,
        LibEveMarket.CurveSide curveSide,
        CurveCLOBTypes.CurveCreationParams[] calldata params,
        uint256[] memory packedCurves,
        uint256[] memory curveIds
    ) internal returns (uint256 nextCurveId) {
        uint256 length = params.length;
        nextCurveId = state.nextCurveId;
        bool isYesSide = state.books[bookId].isYesSide;

        for (uint256 index = 0; index < length; ++index) {
            curveIds[index] = storeBookCurveFromBatch(
                state, bookId, maker, isYesSide, curveSide, params[index], packedCurves[index], nextCurveId
            );

            unchecked {
                ++nextCurveId;
            }
        }
    }

    function storeBookCurveFromBatch(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bookId,
        address maker,
        bool isYesSide,
        LibEveMarket.CurveSide curveSide,
        CurveCLOBTypes.CurveCreationParams calldata params_,
        uint256 packed,
        uint256 curveId
    ) internal returns (uint256 storedCurveId) {
        LibEveMarket.Book storage book = state.books[bookId];
        uint128 quoteEscrow = curveSide == LibEveMarket.CurveSide.BID
            ? LibCurveMath.quoteEscrowRequiredForPacked(book, params_.volume, packed)
            : 0;
        validatePackedCurve(state, bookId, packed);

        LibCurveStorage.storeCurve(
            state.curves[curveId], bookId, maker, isYesSide, curveSide, params_.volume, quoteEscrow, packed, curveId
        );
        storedCurveId = curveId;
    }

    function storeMarketCurveFromBatch(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.Market storage market,
        LibEveMarket.CurveSide curveSide,
        address maker,
        CurveCLOBTypes.CurveCreationParams calldata params_,
        uint256 packed,
        uint256 curveId
    ) internal returns (uint256 storedCurveId) {
        bytes32 bookId = LibBookAccess.marketSideBookId(market, params_.isYesSide);
        validatePackedCurve(state, bookId, packed);
        LibEveMarket.Book storage book = state.books[bookId];
        uint128 quoteEscrow = curveSide == LibEveMarket.CurveSide.BID
            ? LibCurveMath.quoteEscrowRequiredForPacked(book, params_.volume, packed)
            : 0;

        LibCurveStorage.storeCurve(
            state.curves[curveId],
            bookId,
            maker,
            params_.isYesSide,
            curveSide,
            params_.volume,
            quoteEscrow,
            packed,
            curveId
        );
        LibCurveStorage.incrementCurveCount(state, state.books[bookId]);
        storedCurveId = curveId;
    }

    function requireCurveOwner(uint256 curveId, LibEveMarket.StoredCurve storage curve, address caller) internal view {
        if (!curve.active) {
            revert Errors.CurveNotActive(curveId);
        }
        if (curve.maker != caller) {
            revert Errors.NotCurveOwner(caller, curve.maker);
        }
    }

    function syncBidEscrowForCurveUpdate(
        LibEveMarket.Book storage book,
        LibEveMarket.StoredCurve storage curve,
        uint256 newPacked,
        address payer
    ) internal {
        if (curve.curveSide != LibEveMarket.CurveSide.BID) {
            return;
        }

        uint128 newRequired = LibCurveMath.quoteEscrowRequiredForPacked(book, curve.remainingVolume, newPacked);
        uint128 currentEscrow = curve.quoteEscrowRemaining;
        if (newRequired > currentEscrow) {
            uint128 delta = newRequired - currentEscrow;
            LibCurveEscrow.transferExactERC20From(book.quoteToken, payer, address(this), delta);
        } else if (newRequired < currentEscrow) {
            IERC20(book.quoteToken).safeTransfer(curve.maker, currentEscrow - newRequired);
        }
        curve.quoteEscrowRemaining = newRequired;
    }

    function asUint128(uint256 amount) internal pure returns (uint128 narrowed) {
        narrowed = LibSafeCast.toUint128(amount);
    }
}
