// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {CurveCLOBTypes} from "../types/CurveCLOBTypes.sol";
import {Errors} from "../libraries/Errors.sol";
import {Events} from "../libraries/Events.sol";
import {LibBookAccess} from "../libraries/LibBookAccess.sol";
import {LibCurveMath} from "../libraries/LibCurveMath.sol";
import {LibCurveLifecycle} from "../libraries/LibCurveLifecycle.sol";
import {LibCurveIndex} from "../libraries/LibCurveIndex.sol";
import {LibCurveEscrow} from "../libraries/LibCurveEscrow.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibSafeCast} from "../libraries/LibSafeCast.sol";
import {LibReentrancy} from "../libraries/LibReentrancy.sol";

contract BookOrderFacet is CurveCLOBTypes {
    using SafeERC20 for IERC20;

    modifier nonReentrant() {
        LibReentrancy.enter();
        _;
        LibReentrancy.exit();
    }

    function postBookCurve(
        bytes32 bookId,
        LibEveMarket.CurveSide curveSide,
        uint128 volume,
        uint72 startPrice,
        uint72 endPrice,
        uint24 durationMinutes,
        uint8 profileId,
        uint8 tickPresetId
    ) external nonReentrant returns (uint256 curveId) {
        curveId = LibCurveLifecycle.postCurve(
            LibEveMarket.store(),
            bookId,
            curveSide,
            CurveCreationParams({
                isYesSide: false,
                volume: volume,
                startPrice: startPrice,
                endPrice: endPrice,
                durationMinutes: durationMinutes,
                profileId: profileId,
                tickPresetId: tickPresetId
            }),
            msg.sender
        );
    }

    function postBookCurvesBatch(
        bytes32 bookId,
        LibEveMarket.CurveSide curveSide,
        CurveCreationParams[] calldata params
    ) external nonReentrant returns (uint256[] memory curveIds) {
        curveIds = LibCurveLifecycle.postCurvesBatch(LibEveMarket.store(), bookId, curveSide, params, msg.sender);
    }

    function topUpBookCurvesBatch(bytes32 bookId, CurveTopUpParams[] calldata params) external nonReentrant {
        uint256 length = params.length;
        if (length == 0) {
            revert Errors.InvalidAmount(length);
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Book storage book = LibBookAccess.requireExecutableBook(state, bookId);

        (uint256 totalBaseVolume, uint256 totalQuoteEscrow) =
            LibCurveLifecycle.prepareBookCurveTopUpsBatch(state, bookId, params, msg.sender);

        uint128 actualBaseTopUp;
        if (totalBaseVolume != 0) {
            if (book.baseTransferMode == LibEveMarket.BaseTransferMode.BALANCE_DELTA) {
                if (length != 1 || totalQuoteEscrow != 0) {
                    revert Errors.UnsupportedBaseTransferMode(uint8(book.assetType), uint8(book.baseTransferMode));
                }
                actualBaseTopUp =
                    LibCurveEscrow.escrowPostedInventory(book, msg.sender, LibSafeCast.toUint128(totalBaseVolume));
            } else {
                actualBaseTopUp =
                    LibCurveEscrow.escrowPostedInventory(book, msg.sender, LibSafeCast.toUint128(totalBaseVolume));
            }
        }
        if (totalQuoteEscrow != 0) {
            LibCurveEscrow.transferExactERC20From(
                book.quoteToken, msg.sender, address(this), LibSafeCast.toUint128(totalQuoteEscrow)
            );
        }

        if (actualBaseTopUp != 0 && book.baseTransferMode == LibEveMarket.BaseTransferMode.BALANCE_DELTA) {
            LibCurveLifecycle.applySingleBaseCurveTopUp(
                state, book.marketId, params[0].curveId, msg.sender, actualBaseTopUp
            );
        } else {
            LibCurveLifecycle.applyCurveTopUpsBatch(state, book.marketId, params, msg.sender);
        }
    }

    function reactivateBookCurve(
        bytes32 bookId,
        uint256 curveId,
        uint128 newVolume,
        uint256 newPacked,
        uint32 expectedGeneration
    ) external nonReentrant {
        if (newVolume == 0) {
            revert Errors.InvalidAmount(newVolume);
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Book storage book = LibBookAccess.requireExecutableBook(state, bookId);
        LibEveMarket.StoredCurve storage curve = state.curves[curveId];
        LibBookAccess.requireCurveOwner(curveId, curve, msg.sender);

        if (curve.bookId != bookId) {
            revert Errors.CurveBookMismatch(bookId, curve.bookId);
        }
        if (expectedGeneration != curve.generation) {
            revert Errors.GenerationMismatch(expectedGeneration, curve.generation);
        }

        if (!LibCurveMath.isExpired(state, curve) && curve.remainingVolume != 0) {
            revert Errors.CurveNotReusable(curveId, curve.remainingVolume, LibCurveMath.expiresAt(state, curve));
        }

        LibCurveLifecycle.validatePackedCurve(state, bookId, newPacked);

        uint128 storedVolume;
        if (curve.curveSide == LibEveMarket.CurveSide.BID) {
            curve.quoteEscrowRemaining = _settleBidReactivationEscrow(book, curve, newVolume, newPacked);
            storedVolume = newVolume;
        } else {
            curve.quoteEscrowRemaining = 0;
            storedVolume = _settleAskReactivationEscrow(book, curve.remainingVolume, newVolume);
        }

        curve.packed = newPacked;
        curve.createdAt = uint64(block.timestamp);
        unchecked {
            curve.generation += 1;
        }
        LibCurveIndex.reactivateWithRemaining(state, curveId, storedVolume);

        emit Events.CurveReactivated(
            bookId,
            curveId,
            msg.sender,
            curve.remainingVolume,
            curve.quoteEscrowRemaining,
            curve.generation,
            LibCurveMath.expiresAt(state, curve),
            newPacked
        );
    }

    function pruneBookCurves(bytes32 bookId, uint256[] calldata curveIds) external returns (uint256 pruned) {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        if (state.books[bookId].bookId != bookId) revert Errors.BookNotFound(bookId);
        pruned = LibCurveIndex.prune(state, bookId, curveIds);
        emit Events.BookCurvesPruned(bookId, msg.sender, pruned);
    }

    function _settleBidReactivationEscrow(
        LibEveMarket.Book storage book,
        LibEveMarket.StoredCurve storage curve,
        uint128 newVolume,
        uint256 newPacked
    ) internal returns (uint128 quoteEscrow) {
        quoteEscrow = LibCurveMath.quoteEscrowRequiredForPacked(book, newVolume, newPacked);
        uint128 currentEscrow = curve.quoteEscrowRemaining;

        if (currentEscrow > quoteEscrow) {
            IERC20(book.quoteToken).safeTransfer(curve.maker, currentEscrow - quoteEscrow);
        } else if (quoteEscrow > currentEscrow) {
            LibCurveEscrow.transferExactERC20From(
                book.quoteToken, curve.maker, address(this), quoteEscrow - currentEscrow
            );
        }
    }

    function _settleAskReactivationEscrow(LibEveMarket.Book storage book, uint128 currentVolume, uint128 newVolume)
        internal
        returns (uint128 storedVolume)
    {
        storedVolume = newVolume;

        if (currentVolume > newVolume) {
            LibCurveEscrow.transferBaseFromEscrow(book, msg.sender, currentVolume - newVolume);
        } else if (newVolume > currentVolume) {
            uint128 actualAddedVolume =
                LibCurveEscrow.escrowPostedInventory(book, msg.sender, newVolume - currentVolume);
            storedVolume = currentVolume + actualAddedVolume;
        }
    }
}
