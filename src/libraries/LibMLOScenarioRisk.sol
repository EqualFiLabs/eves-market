// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IMarginAccountFacet} from "../interfaces/IMarginAccountFacet.sol";
import {MLOPredictionTypes} from "../types/MLOPredictionTypes.sol";
import {MarginTypes} from "../types/MarginTypes.sol";
import {LibEveMarket} from "./LibEveMarket.sol";
import {LibMLOScenarioMath} from "./LibMLOScenarioMath.sol";

library LibMLOScenarioRisk {
    error ScenarioMarketMismatch(bytes32 bucketId, bytes32 expectedMarketId, bytes32 actualMarketId);
    error ScenarioOutcomeCountMismatch(bytes32 bucketId, uint256 expected, uint256 actual);
    error ScenarioContextUnavailable(bytes32 bookId);
    error ScenarioOpenLossUnderflow(bytes32 bucketId, uint256 index);
    error ScenarioFundingOverflow(uint256 funding);
    error ScenarioEffectiveLossOverflow(uint256 index);
    error ScenarioValueOverflow(uint256 value);

    function contextForBook(LibEveMarket.EveMarketStorage storage state, bytes32 bookId)
        internal
        view
        returns (bytes32 marketId, uint8 outcomeIndex, uint8 outcomeCount)
    {
        LibEveMarket.Book storage book = state.books[bookId];
        marketId = book.marketId;
        if (marketId == bytes32(0)) {
            revert ScenarioContextUnavailable(bookId);
        }

        LibEveMarket.MultiOutcomeMarket storage multi = state.multiOutcomeMarkets[marketId];
        if (multi.exists) {
            LibMLOScenarioMath.validateOutcomeCount(multi.outcomeCount);
            for (uint8 index; index < multi.outcomeCount; ++index) {
                if (
                    state.multiOutcomeBookIds[marketId][index] == bookId
                        || state.multiOutcomePositionIds[marketId][index] == book.baseTokenId
                ) {
                    return (marketId, index, multi.outcomeCount);
                }
            }
            revert ScenarioContextUnavailable(bookId);
        }

        if (book.isYesSide && book.baseTokenId == state.markets[marketId].yesPositionId) {
            return (marketId, 0, 2);
        }
        if (!book.isYesSide && book.baseTokenId == state.markets[marketId].noPositionId) {
            return (marketId, 1, 2);
        }
        revert ScenarioContextUnavailable(bookId);
    }

    function initialize(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bucketId,
        bytes32 marketId,
        uint8 outcomeCount
    ) internal {
        LibMLOScenarioMath.validateOutcomeCount(outcomeCount);
        LibEveMarket.MLOScenarioExposure storage exposure = state.mloScenarioExposures[bucketId];
        if (exposure.initialized) {
            if (exposure.marketId != marketId) {
                revert ScenarioMarketMismatch(bucketId, exposure.marketId, marketId);
            }
            if (exposure.outcomeCount != outcomeCount) {
                revert ScenarioOutcomeCountMismatch(bucketId, exposure.outcomeCount, outcomeCount);
            }
            return;
        }

        exposure.marketId = marketId;
        exposure.outcomeCount = outcomeCount;
        exposure.initialized = true;
        emit IMarginAccountFacet.ScenarioExposureInitialized(bucketId, marketId, outcomeCount);
    }

    function addOpenReservation(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bucketId,
        bytes32 marketId,
        uint8 outcomeIndex,
        uint8 outcomeCount,
        LibMLOScenarioMath.Side side,
        uint256 riskVolume,
        uint256 price,
        uint256 denominator
    ) internal {
        initialize(state, bucketId, marketId, outcomeCount);
        int256[] memory losses =
            LibMLOScenarioMath.reservedLossVector(side, riskVolume, price, denominator, outcomeIndex, outcomeCount);
        LibEveMarket.MLOScenarioExposure storage exposure = state.mloScenarioExposures[bucketId];
        for (uint256 index; index < losses.length; ++index) {
            if (losses[index] > 0) {
                exposure.openLosses[index] += losses[index];
            }
        }
        syncCompatibility(state, bucketId);
        emit IMarginAccountFacet.ScenarioExposureUpdated(
            bucketId, marketId, outcomeCount, maximumRawLoss(state, bucketId)
        );
    }

    function reservationRisk(
        LibMLOScenarioMath.Side side,
        uint256 riskVolume,
        uint256 price,
        uint256 denominator,
        uint256 outcomeIndex,
        uint256 outcomeCount
    ) internal pure returns (uint256 maximum) {
        int256[] memory losses = LibMLOScenarioMath.reservedLossVector(
            side, riskVolume, price, denominator, outcomeIndex, outcomeCount
        );
        for (uint256 index; index < losses.length; ++index) {
            if (losses[index] > int256(maximum)) maximum = uint256(losses[index]);
        }
    }

    function removeOpenReservation(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bucketId,
        bytes32 marketId,
        uint8 outcomeIndex,
        uint8 outcomeCount,
        LibMLOScenarioMath.Side side,
        uint256 riskVolume,
        uint256 price,
        uint256 denominator
    ) internal {
        LibEveMarket.MLOScenarioExposure storage exposure = requireExposure(state, bucketId, marketId, outcomeCount);
        int256[] memory losses =
            LibMLOScenarioMath.reservedLossVector(side, riskVolume, price, denominator, outcomeIndex, outcomeCount);
        for (uint256 index; index < losses.length; ++index) {
            if (losses[index] > 0) {
                if (exposure.openLosses[index] < losses[index]) {
                    revert ScenarioOpenLossUnderflow(bucketId, index);
                }
                exposure.openLosses[index] -= losses[index];
            }
        }
        syncCompatibility(state, bucketId);
        emit IMarginAccountFacet.ScenarioExposureUpdated(
            bucketId, marketId, outcomeCount, maximumRawLoss(state, bucketId)
        );
    }

    function replaceReservationAndAddPosition(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bucketId,
        bytes32 marketId,
        uint8 outcomeIndex,
        uint8 outcomeCount,
        LibMLOScenarioMath.Side side,
        uint256 oldRiskVolume,
        uint256 newRiskVolume,
        uint256 boundPrice,
        uint256 denominator,
        uint256 actualCash,
        uint256 shares
    ) internal {
        LibEveMarket.MLOScenarioExposure storage exposure = requireExposure(state, bucketId, marketId, outcomeCount);
        int256[] memory oldLosses = LibMLOScenarioMath.reservedLossVector(
            side, oldRiskVolume, boundPrice, denominator, outcomeIndex, outcomeCount
        );
        _removeOpenVector(exposure, oldLosses, bucketId);
        if (newRiskVolume != 0) {
            int256[] memory newLosses = LibMLOScenarioMath.reservedLossVector(
                side, newRiskVolume, boundPrice, denominator, outcomeIndex, outcomeCount
            );
            _addOpenVector(exposure, newLosses);
        }
        int256[] memory positionLosses =
            LibMLOScenarioMath.lossVector(side, shares, actualCash, outcomeIndex, outcomeCount);
        for (uint256 index; index < positionLosses.length; ++index) {
            exposure.filledPositionLosses[index] += positionLosses[index];
        }
        syncCompatibility(state, bucketId);
        emit IMarginAccountFacet.ScenarioExposureUpdated(
            bucketId, marketId, outcomeCount, maximumRawLoss(state, bucketId)
        );
    }

    function replaceOpenReservation(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bucketId,
        bytes32 marketId,
        uint8 outcomeIndex,
        uint8 outcomeCount,
        LibMLOScenarioMath.Side side,
        uint256 oldRiskVolume,
        uint256 newRiskVolume,
        uint256 boundPrice,
        uint256 denominator
    ) internal {
        LibEveMarket.MLOScenarioExposure storage exposure = requireExposure(state, bucketId, marketId, outcomeCount);
        if (oldRiskVolume != 0) {
            int256[] memory oldLosses = LibMLOScenarioMath.reservedLossVector(
                side, oldRiskVolume, boundPrice, denominator, outcomeIndex, outcomeCount
            );
            _removeOpenVector(exposure, oldLosses, bucketId);
        }
        if (newRiskVolume != 0) {
            int256[] memory newLosses = LibMLOScenarioMath.reservedLossVector(
                side, newRiskVolume, boundPrice, denominator, outcomeIndex, outcomeCount
            );
            _addOpenVector(exposure, newLosses);
        }
        syncCompatibility(state, bucketId);
        emit IMarginAccountFacet.ScenarioExposureUpdated(
            bucketId, marketId, outcomeCount, maximumRawLoss(state, bucketId)
        );
    }

    function reconcilePosition(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bucketId,
        bytes32 marketId,
        uint256 seniorDebt,
        uint8 outcomeCount
    ) internal {
        LibEveMarket.MLOScenarioExposure storage exposure = requireExposure(state, bucketId, marketId, outcomeCount);
        uint256 invalidPayout;
        for (uint8 outcome; outcome < outcomeCount; ++outcome) {
            uint256 inventory = state.mloBucketOutcomeInventory[bucketId][marketId][outcome];
            exposure.filledPositionLosses[outcome] = _signedDifference(seniorDebt, inventory);
            invalidPayout += inventory / outcomeCount;
        }
        exposure.filledPositionLosses[outcomeCount] = _signedDifference(seniorDebt, invalidPayout);
        syncCompatibility(state, bucketId);
        emit IMarginAccountFacet.ScenarioExposureUpdated(
            bucketId, marketId, outcomeCount, maximumRawLoss(state, bucketId)
        );
    }

    function clearFilledPosition(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId) internal {
        LibEveMarket.MLOScenarioExposure storage exposure = state.mloScenarioExposures[bucketId];
        if (!exposure.initialized) {
            return;
        }
        for (uint256 index; index <= exposure.outcomeCount; ++index) {
            exposure.filledPositionLosses[index] = 0;
        }
        syncCompatibility(state, bucketId);
        emit IMarginAccountFacet.ScenarioExposureUpdated(
            bucketId, exposure.marketId, exposure.outcomeCount, maximumRawLoss(state, bucketId)
        );
    }

    function maximumSignedLoss(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId)
        internal
        view
        returns (int256 maximum)
    {
        LibEveMarket.MLOScenarioExposure storage exposure = requireExposure(state, bucketId);
        maximum = type(int256).min;
        for (uint256 index; index <= exposure.outcomeCount; ++index) {
            int256 value = exposure.filledPositionLosses[index];
            if (value > maximum) maximum = value;
        }
    }

    function maximumRawLoss(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId)
        internal
        view
        returns (int256 maximum)
    {
        LibEveMarket.MLOScenarioExposure storage exposure = requireExposure(state, bucketId);
        maximum = type(int256).min;
        for (uint256 index; index <= exposure.outcomeCount; ++index) {
            int256 value = exposure.openLosses[index] + exposure.filledPositionLosses[index];
            if (value > maximum) maximum = value;
        }
    }

    function maximumEffectiveLoss(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId, uint256 funding)
        internal
        view
        returns (int256 maximum)
    {
        LibEveMarket.MLOScenarioExposure storage exposure = requireExposure(state, bucketId);
        maximum = type(int256).min;
        int256 fundingSigned = _fundingAsSigned(funding);
        for (uint256 index; index <= exposure.outcomeCount; ++index) {
            int256 aggregate = exposure.openLosses[index] + exposure.filledPositionLosses[index];
            int256 value = _effectiveLoss(aggregate, fundingSigned, index);
            if (value > maximum) maximum = value;
        }
    }

    function requiredMargin(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bucketId,
        uint256 funding,
        uint256 marginBps
    ) internal view returns (uint256) {
        LibEveMarket.MLOScenarioExposure storage exposure = requireExposure(state, bucketId);
        int256[] memory effective = new int256[](exposure.outcomeCount + 1);
        int256 fundingSigned = _fundingAsSigned(funding);
        for (uint256 index; index < effective.length; ++index) {
            int256 aggregate = exposure.openLosses[index] + exposure.filledPositionLosses[index];
            effective[index] = _effectiveLoss(aggregate, fundingSigned, index);
        }
        return LibMLOScenarioMath.requiredMargin(effective, marginBps);
    }

    function syncCompatibility(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId) internal {
        LibEveMarket.MLOScenarioExposure storage exposure = requireExposure(state, bucketId);
        uint256 maximumOpen;
        int256 maximumFilled = type(int256).min;
        int256 maximumRaw = type(int256).min;
        for (uint256 index; index <= exposure.outcomeCount; ++index) {
            if (exposure.openLosses[index] > int256(maximumOpen)) maximumOpen = uint256(exposure.openLosses[index]);
            if (exposure.filledPositionLosses[index] > maximumFilled) {
                maximumFilled = exposure.filledPositionLosses[index];
            }
            int256 raw = exposure.openLosses[index] + exposure.filledPositionLosses[index];
            if (raw > maximumRaw) maximumRaw = raw;
        }

        MarginTypes.MarginBucket storage bucket = state.marginBuckets[bucketId];
        bucket.openOrderRisk = maximumOpen;
        bucket.reservedRisk = maximumOpen;
        bucket.positionRisk = maximumFilled > 0 ? uint256(maximumFilled) : 0;
        bucket.activeRisk = maximumRaw > 0 ? uint256(maximumRaw) : 0;
        state.mloBucketMarketPositionRisk[bucketId][exposure.marketId] = bucket.positionRisk;
    }

    function viewExposure(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bucketId,
        uint256 funding,
        uint16 initialMarginBps,
        uint16 maintenanceMarginBps
    ) internal view returns (MLOPredictionTypes.MLOScenarioExposureView memory view_) {
        LibEveMarket.MLOScenarioExposure storage exposure = state.mloScenarioExposures[bucketId];
        view_.bucketId = bucketId;
        view_.marketId = exposure.marketId;
        view_.outcomeCount = exposure.outcomeCount;
        view_.initialized = exposure.initialized;
        if (!exposure.initialized) return view_;

        uint256 length = exposure.outcomeCount + 1;
        view_.openLosses = new int256[](length);
        view_.filledPositionLosses = new int256[](length);
        view_.aggregateLosses = new int256[](length);
        view_.effectiveLosses = new int256[](length);
        int256 fundingSigned = _fundingAsSigned(funding);
        view_.funding = funding;
        view_.maximumSignedLoss = type(int256).min;
        view_.maximumRawLoss = type(int256).min;
        view_.maximumEffectiveLoss = type(int256).min;
        for (uint256 index; index < length; ++index) {
            view_.openLosses[index] = exposure.openLosses[index];
            view_.filledPositionLosses[index] = exposure.filledPositionLosses[index];
            view_.aggregateLosses[index] = exposure.openLosses[index] + exposure.filledPositionLosses[index];
            view_.effectiveLosses[index] = _effectiveLoss(view_.aggregateLosses[index], fundingSigned, index);
            if (view_.filledPositionLosses[index] > view_.maximumSignedLoss) {
                view_.maximumSignedLoss = view_.filledPositionLosses[index];
            }
            if (view_.aggregateLosses[index] > view_.maximumRawLoss) {
                view_.maximumRawLoss = view_.aggregateLosses[index];
            }
            if (view_.effectiveLosses[index] > view_.maximumEffectiveLoss) {
                view_.maximumEffectiveLoss = view_.effectiveLosses[index];
            }
        }
        view_.initialRequirement = requiredMargin(state, bucketId, funding, initialMarginBps);
        view_.maintenanceRequirement = requiredMargin(state, bucketId, funding, maintenanceMarginBps);
    }

    function requireExposure(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId)
        internal
        view
        returns (LibEveMarket.MLOScenarioExposure storage exposure)
    {
        exposure = state.mloScenarioExposures[bucketId];
        if (!exposure.initialized) revert IMarginAccountFacet.ScenarioManagedBucket(bucketId);
    }

    function requireExposure(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bucketId,
        bytes32 marketId,
        uint8 outcomeCount
    ) internal view returns (LibEveMarket.MLOScenarioExposure storage exposure) {
        exposure = requireExposure(state, bucketId);
        if (exposure.marketId != marketId) revert ScenarioMarketMismatch(bucketId, exposure.marketId, marketId);
        if (exposure.outcomeCount != outcomeCount) {
            revert ScenarioOutcomeCountMismatch(bucketId, exposure.outcomeCount, outcomeCount);
        }
    }

    function _addOpenVector(LibEveMarket.MLOScenarioExposure storage exposure, int256[] memory losses) private {
        for (uint256 index; index < losses.length; ++index) {
            if (losses[index] > 0) exposure.openLosses[index] += losses[index];
        }
    }

    function _removeOpenVector(
        LibEveMarket.MLOScenarioExposure storage exposure,
        int256[] memory losses,
        bytes32 bucketId
    ) private {
        for (uint256 index; index < losses.length; ++index) {
            if (losses[index] > 0) {
                if (exposure.openLosses[index] < losses[index]) {
                    revert ScenarioOpenLossUnderflow(bucketId, index);
                }
                exposure.openLosses[index] -= losses[index];
            }
        }
    }

    function _fundingAsSigned(uint256 funding) private pure returns (int256 fundingSigned) {
        if (funding > uint256(type(int256).max)) revert ScenarioFundingOverflow(funding);
        fundingSigned = int256(funding);
    }

    function _effectiveLoss(int256 aggregate, int256 funding, uint256 index) private pure returns (int256 value) {
        if (aggregate > type(int256).max - funding) revert ScenarioEffectiveLossOverflow(index);
        value = aggregate + funding;
    }

    function _signedDifference(uint256 left, uint256 right) private pure returns (int256 difference) {
        uint256 magnitude = left >= right ? left - right : right - left;
        if (magnitude > uint256(type(int256).max)) revert ScenarioValueOverflow(magnitude);
        difference = left >= right ? int256(magnitude) : -int256(magnitude);
    }
}
