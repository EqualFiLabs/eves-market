// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Errors} from "./Errors.sol";
import {LibCurveMath} from "./LibCurveMath.sol";
import {LibEveMarket} from "./LibEveMarket.sol";
import {ProductAdapterTypes} from "../types/ProductAdapterTypes.sol";

/// @notice Maintains the bounded-per-call execution index and resolver ASK exposure.
library LibCurveIndex {
    uint256 internal constant MAX_PAGE_SIZE = 128;
    uint256 internal constant MAX_PRUNE_BATCH = 64;

    function registerCreatedCurve(LibEveMarket.EveMarketStorage storage state, uint256 curveId) internal {
        LibEveMarket.StoredCurve storage curve = state.curves[curveId];
        if (!curve.active || curve.remainingVolume == 0) return;
        _insert(state, curveId, curve.bookId);
        if (curve.curveSide == LibEveMarket.CurveSide.ASK) {
            state.bookMakerAskExposure[curve.bookId][curve.maker] += curve.remainingVolume;
        }
    }

    function decreaseRemaining(LibEveMarket.EveMarketStorage storage state, uint256 curveId, uint128 amount) internal {
        LibEveMarket.StoredCurve storage curve = state.curves[curveId];
        if (curve.curveSide == LibEveMarket.CurveSide.ASK) {
            state.bookMakerAskExposure[curve.bookId][curve.maker] -= amount;
        }
        curve.remainingVolume -= amount;
        if (curve.remainingVolume == 0) _remove(state, curveId, curve.bookId);
    }

    function decreaseAskRemaining(LibEveMarket.EveMarketStorage storage state, uint256 curveId, uint128 amount)
        internal
    {
        LibEveMarket.StoredCurve storage curve = state.curves[curveId];
        state.bookMakerAskExposure[curve.bookId][curve.maker] -= amount;
        curve.remainingVolume -= amount;
        if (curve.remainingVolume == 0) _remove(state, curveId, curve.bookId);
    }

    function decreaseBidRemaining(LibEveMarket.EveMarketStorage storage state, uint256 curveId, uint128 amount)
        internal
    {
        LibEveMarket.StoredCurve storage curve = state.curves[curveId];
        curve.remainingVolume -= amount;
        if (curve.remainingVolume == 0) _remove(state, curveId, curve.bookId);
    }

    function increaseRemaining(LibEveMarket.EveMarketStorage storage state, uint256 curveId, uint128 amount) internal {
        LibEveMarket.StoredCurve storage curve = state.curves[curveId];
        bool wasEmpty = curve.remainingVolume == 0;
        curve.remainingVolume += amount;
        if (curve.curveSide == LibEveMarket.CurveSide.ASK && curve.active) {
            state.bookMakerAskExposure[curve.bookId][curve.maker] += amount;
        }
        if (wasEmpty && curve.active) _insert(state, curveId, curve.bookId);
    }

    function setRemaining(LibEveMarket.EveMarketStorage storage state, uint256 curveId, uint128 newRemaining) internal {
        LibEveMarket.StoredCurve storage curve = state.curves[curveId];
        uint128 oldRemaining = curve.remainingVolume;
        if (curve.curveSide == LibEveMarket.CurveSide.ASK && curve.active) {
            uint256 exposure = state.bookMakerAskExposure[curve.bookId][curve.maker];
            if (newRemaining >= oldRemaining) exposure += newRemaining - oldRemaining;
            else exposure -= oldRemaining - newRemaining;
            state.bookMakerAskExposure[curve.bookId][curve.maker] = exposure;
        }
        curve.remainingVolume = newRemaining;
        if (!curve.active || newRemaining == 0) _remove(state, curveId, curve.bookId);
        else _insert(state, curveId, curve.bookId);
    }

    function deactivate(LibEveMarket.EveMarketStorage storage state, uint256 curveId) internal {
        LibEveMarket.StoredCurve storage curve = state.curves[curveId];
        if (curve.active && curve.curveSide == LibEveMarket.CurveSide.ASK && curve.remainingVolume != 0) {
            state.bookMakerAskExposure[curve.bookId][curve.maker] -= curve.remainingVolume;
        }
        curve.active = false;
        curve.remainingVolume = 0;
        _remove(state, curveId, curve.bookId);
    }

    function reactivateWithRemaining(LibEveMarket.EveMarketStorage storage state, uint256 curveId, uint128 newRemaining)
        internal
    {
        LibEveMarket.StoredCurve storage curve = state.curves[curveId];
        uint128 oldRemaining = curve.remainingVolume;
        bool wasActive = curve.active;
        if (curve.curveSide == LibEveMarket.CurveSide.ASK) {
            uint256 exposure = state.bookMakerAskExposure[curve.bookId][curve.maker];
            if (wasActive) exposure -= oldRemaining;
            exposure += newRemaining;
            state.bookMakerAskExposure[curve.bookId][curve.maker] = exposure;
        }
        curve.active = true;
        curve.remainingVolume = newRemaining;
        _insert(state, curveId, curve.bookId);
    }

    function prune(LibEveMarket.EveMarketStorage storage state, bytes32 bookId, uint256[] calldata curveIds)
        internal
        returns (uint256 pruned)
    {
        uint256 length = curveIds.length;
        if (length > MAX_PRUNE_BATCH) revert Errors.CurvePruneBatchTooLarge(length, MAX_PRUNE_BATCH);
        for (uint256 i; i < length; ++i) {
            uint256 curveId = curveIds[i];
            LibEveMarket.StoredCurve storage curve = state.curves[curveId];
            if (curve.bookId != bookId) revert Errors.CurveBookMismatch(bookId, curve.bookId);
            if (_isExecutableCandidate(state, curveId, curve)) continue;
            if (state.activeBookCurveIndexPlusOne[curveId] != 0) {
                _remove(state, curveId, bookId);
                ++pruned;
            }
        }
    }

    function isExecutableCandidate(
        LibEveMarket.EveMarketStorage storage state,
        uint256 curveId,
        LibEveMarket.StoredCurve storage curve
    ) internal view returns (bool) {
        return _isExecutableCandidate(state, curveId, curve);
    }

    function validatePage(uint256 cursor, uint256 limit, uint256 length) internal pure returns (uint256 end) {
        if (limit == 0 || limit > MAX_PAGE_SIZE) revert Errors.InvalidPageSize(limit, MAX_PAGE_SIZE);
        if (cursor > length) revert Errors.InvalidAmount(cursor);
        if (cursor >= length) return length;
        end = cursor + limit;
        if (end > length) end = length;
    }

    function _isExecutableCandidate(
        LibEveMarket.EveMarketStorage storage state,
        uint256 curveId,
        LibEveMarket.StoredCurve storage curve
    ) private view returns (bool) {
        if (!curve.active || curve.remainingVolume == 0 || LibCurveMath.isExpired(state, curve)) {
            return false;
        }
        ProductAdapterTypes.CurveBackingKind backing = state.adapterCurveMetadata[curveId].backingKind;
        return backing != ProductAdapterTypes.CurveBackingKind.Adapter || state.adapterCurveMetadata[curveId].active;
    }

    function _insert(LibEveMarket.EveMarketStorage storage state, uint256 curveId, bytes32 bookId) private {
        if (state.activeBookCurveIndexPlusOne[curveId] != 0) return;
        state.activeBookCurveIds[bookId].push(curveId);
        state.activeBookCurveIndexPlusOne[curveId] = state.activeBookCurveIds[bookId].length;
    }

    function _remove(LibEveMarket.EveMarketStorage storage state, uint256 curveId, bytes32 bookId) private {
        uint256 indexPlusOne = state.activeBookCurveIndexPlusOne[curveId];
        if (indexPlusOne == 0) return;
        uint256[] storage ids = state.activeBookCurveIds[bookId];
        uint256 index = indexPlusOne - 1;
        uint256 lastIndex = ids.length - 1;
        if (index != lastIndex) {
            uint256 movedCurveId = ids[lastIndex];
            ids[index] = movedCurveId;
            state.activeBookCurveIndexPlusOne[movedCurveId] = index + 1;
        }
        ids.pop();
        delete state.activeBookCurveIndexPlusOne[curveId];
    }
}
