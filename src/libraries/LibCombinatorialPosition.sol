// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Math} from "../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

import {Errors} from "./Errors.sol";
import {Events} from "./Events.sol";
import {LibEveMarket} from "./LibEveMarket.sol";
import {LibNativePosition} from "./LibNativePosition.sol";
import {NativePositionTypes} from "../types/NativePositionTypes.sol";
import {IGnosisConditionalTokens} from "../interfaces/IGnosisConditionalTokens.sol";

library LibCombinatorialPosition {
    uint256 internal constant MAX_LEGS = 50;

    struct CompressionPlan {
        NativePositionTypes.CompressionResult result;
        uint256[] remaining;
        uint256 remainingCount;
    }

    struct PayoutScan {
        uint256[] remaining;
        uint256 remainingCount;
        uint256 payoutFactorDown;
        uint256 payoutFactorUp;
        bool resolvedAny;
        bool terminalZero;
    }

    function copyLegs(uint256[] calldata legs) internal pure returns (uint256[] memory copiedLegs) {
        uint256 length = legs.length;
        copiedLegs = new uint256[](length);
        for (uint256 index; index < length; ++index) {
            copiedLegs[index] = legs[index];
        }
    }

    function copyStoredLegs(LibEveMarket.EveMarketStorage storage state, bytes32 conditionId)
        internal
        view
        returns (uint256[] memory copiedLegs)
    {
        uint256[] storage storedLegs = state.comboConditionLegs[conditionId];
        if (storedLegs.length == 0) {
            revert Errors.ComboConditionNotFound(conditionId);
        }
        copiedLegs = new uint256[](storedLegs.length);
        for (uint256 index; index < storedLegs.length; ++index) {
            copiedLegs[index] = storedLegs[index];
        }
    }

    function requireComboCondition(LibEveMarket.EveMarketStorage storage state, bytes32 conditionId)
        internal
        view
        returns (LibEveMarket.ComboCondition storage condition)
    {
        condition = state.comboConditions[conditionId];
        if (!condition.exists) {
            revert Errors.ComboConditionNotFound(conditionId);
        }
    }

    function insertLeg(uint256[] memory baseLegs, uint256 leg) internal pure returns (uint256[] memory result) {
        uint256 length = baseLegs.length;
        result = new uint256[](length + 1);
        uint256 insertIndex = length;

        for (uint256 index; index < length; ++index) {
            if (leg == baseLegs[index]) {
                revert Errors.ComboNonCanonicalLegs(baseLegs[index], leg);
            }
            if (leg < baseLegs[index] && insertIndex == length) {
                insertIndex = index;
            }
        }

        for (uint256 index; index < insertIndex; ++index) {
            result[index] = baseLegs[index];
        }
        result[insertIndex] = leg;
        for (uint256 index = insertIndex; index < length; ++index) {
            result[index + 1] = baseLegs[index];
        }
    }

    function removeLeg(uint256[] memory baseLegs, uint256 index) internal pure returns (uint256[] memory result) {
        uint256 length = baseLegs.length;
        if (index >= length) {
            revert Errors.ComboLegIndexOutOfRange(index, length);
        }
        result = new uint256[](length - 1);
        for (uint256 cursor; cursor < index; ++cursor) {
            result[cursor] = baseLegs[cursor];
        }
        for (uint256 cursor = index + 1; cursor < length; ++cursor) {
            result[cursor - 1] = baseLegs[cursor];
        }
    }

    function flipLeg(LibEveMarket.EveMarketStorage storage state, uint256 leg)
        internal
        view
        returns (uint256 flippedLeg)
    {
        LibEveMarket.NativePositionMetadata storage metadata = state.nativePositionMetadata[leg];
        if (!isSupportedLeg(state, leg, metadata)) {
            revert Errors.ComboUnsupportedPosition(leg);
        }
        flippedLeg = state.ctfPositionMetadata[leg].complementPositionId;
    }

    function storeComboConditionFromMemory(LibEveMarket.EveMarketStorage storage state, uint256[] memory legs)
        internal
        returns (bytes32 conditionId, uint256 yesPositionId, uint256 noPositionId, bool created)
    {
        if (legs.length == 0 || legs.length > MAX_LEGS) {
            revert Errors.ComboLegCountInvalid(legs.length);
        }

        conditionId = LibNativePosition.comboConditionIdFor(legs);
        yesPositionId = LibNativePosition.positionIdFor(
            LibNativePosition.MODULE_COMBINATORIAL, conditionId, LibNativePosition.OUTCOME_YES
        );
        noPositionId = LibNativePosition.positionIdFor(
            LibNativePosition.MODULE_COMBINATORIAL, conditionId, LibNativePosition.OUTCOME_NO
        );

        LibEveMarket.ComboCondition storage condition = state.comboConditions[conditionId];
        if (condition.exists) {
            return (conditionId, yesPositionId, noPositionId, false);
        }

        condition.conditionId = conditionId;
        condition.legsHash = keccak256(abi.encode(legs));
        condition.legCount = uint16(legs.length);
        condition.preparedAt = uint64(block.timestamp);
        condition.exists = true;
        for (uint256 index; index < legs.length; ++index) {
            state.comboConditionLegs[conditionId].push(legs[index]);
        }

        storeComboMetadata(state, conditionId, yesPositionId, LibNativePosition.OUTCOME_YES);
        storeComboMetadata(state, conditionId, noPositionId, LibNativePosition.OUTCOME_NO);
        created = true;
    }

    function storeComboMetadata(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 conditionId,
        uint256 positionId,
        uint8 outcomeIndex
    ) internal {
        state.nativePositionMetadata[positionId] = LibEveMarket.NativePositionMetadata({
            moduleId: LibNativePosition.MODULE_COMBINATORIAL,
            conditionId: conditionId,
            outcomeIndex: outcomeIndex,
            marketId: bytes32(0),
            exists: true
        });
    }

    function requireComboPosition(LibEveMarket.EveMarketStorage storage state, uint256 positionId)
        internal
        view
        returns (LibEveMarket.NativePositionMetadata storage metadata)
    {
        metadata = state.nativePositionMetadata[positionId];
        if (!metadata.exists || metadata.moduleId != LibNativePosition.MODULE_COMBINATORIAL) {
            revert Errors.ComboUnsupportedPosition(positionId);
        }
        if (!LibNativePosition.isBinaryOutcome(metadata.outcomeIndex)) {
            revert Errors.NativeOutcomeUnsupported(metadata.outcomeIndex);
        }
        if (!state.comboConditions[metadata.conditionId].exists) {
            revert Errors.ComboConditionNotFound(metadata.conditionId);
        }
    }

    function positionIdFor(LibEveMarket.NativePositionMetadata storage metadata)
        internal
        view
        returns (uint256 positionId)
    {
        positionId = LibNativePosition.positionIdFor(metadata.moduleId, metadata.conditionId, metadata.outcomeIndex);
    }

    function previewCompressionPlan(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.NativePositionMetadata storage metadata,
        uint128 amount
    ) internal view returns (CompressionPlan memory plan) {
        PayoutScan memory scan = scanPayoutFactors(state, metadata.conditionId);
        plan.remaining = scan.remaining;
        plan.remainingCount = scan.remainingCount;

        if (!scan.resolvedAny) {
            revert Errors.ComboPositionNotCompressible(positionIdFor(metadata));
        }
        if (scan.terminalZero) {
            if (metadata.outcomeIndex == LibNativePosition.OUTCOME_NO) {
                plan.result.collateralOut = amount;
            }
            return plan;
        }

        if (metadata.outcomeIndex == LibNativePosition.OUTCOME_YES) {
            plan.result.positionAmount =
                uint128(Math.mulDiv(amount, scan.payoutFactorDown, LibNativePosition.PAYOUT_FACTOR_DENOMINATOR));
            if (plan.remainingCount == 0) {
                plan.result.collateralOut = plan.result.positionAmount;
                plan.result.positionAmount = 0;
            } else if (plan.result.positionAmount != 0) {
                plan.result.newPositionId =
                    reducedPositionId(plan.remaining, plan.remainingCount, metadata.outcomeIndex);
            }
            return plan;
        }

        uint256 positionAmount =
            Math.mulDiv(amount, scan.payoutFactorUp, LibNativePosition.PAYOUT_FACTOR_DENOMINATOR, Math.Rounding.Ceil);
        plan.result.collateralOut = uint128(uint256(amount) - positionAmount);
        if (plan.remainingCount != 0 && positionAmount != 0) {
            plan.result.positionAmount = uint128(positionAmount);
            plan.result.newPositionId = reducedPositionId(plan.remaining, plan.remainingCount, metadata.outcomeIndex);
        }
    }

    function comboPayout(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.NativePositionMetadata storage metadata,
        uint128 amount
    ) internal view returns (bool redeemable, uint128 collateralOut) {
        PayoutScan memory scan = scanPayoutFactors(state, metadata.conditionId);
        if (scan.terminalZero) {
            return metadata.outcomeIndex == LibNativePosition.OUTCOME_NO ? (true, amount) : (true, 0);
        }
        if (scan.remainingCount != 0) {
            return (false, 0);
        }

        if (metadata.outcomeIndex == LibNativePosition.OUTCOME_YES) {
            return
                (true, uint128(Math.mulDiv(amount, scan.payoutFactorDown, LibNativePosition.PAYOUT_FACTOR_DENOMINATOR)));
        }

        uint256 conjunctionUp =
            Math.mulDiv(amount, scan.payoutFactorUp, LibNativePosition.PAYOUT_FACTOR_DENOMINATOR, Math.Rounding.Ceil);
        return (true, uint128(uint256(amount) - conjunctionUp));
    }

    function scanPayoutFactors(LibEveMarket.EveMarketStorage storage state, bytes32 conditionId)
        internal
        view
        returns (PayoutScan memory scan)
    {
        uint256[] storage storedLegs = state.comboConditionLegs[conditionId];
        scan.remaining = new uint256[](storedLegs.length);
        scan.payoutFactorDown = LibNativePosition.PAYOUT_FACTOR_DENOMINATOR;
        scan.payoutFactorUp = LibNativePosition.PAYOUT_FACTOR_DENOMINATOR;

        for (uint256 index; index < storedLegs.length; ++index) {
            (bool resolved, uint256 numerator) = legPayout(state, storedLegs[index]);
            if (!resolved) {
                scan.remaining[scan.remainingCount++] = storedLegs[index];
                continue;
            }

            scan.resolvedAny = true;
            if (numerator == 0) {
                scan.terminalZero = true;
                return scan;
            }
            if (numerator != LibNativePosition.RESULT_DENOMINATOR) {
                scan.payoutFactorDown =
                    Math.mulDiv(scan.payoutFactorDown, numerator, LibNativePosition.RESULT_DENOMINATOR);
                scan.payoutFactorUp = Math.mulDiv(
                    scan.payoutFactorUp, numerator, LibNativePosition.RESULT_DENOMINATOR, Math.Rounding.Ceil
                );
            }
        }
    }

    function materializeReducedPosition(
        LibEveMarket.EveMarketStorage storage state,
        CompressionPlan memory plan,
        uint8 outcomeIndex
    ) internal returns (NativePositionTypes.CompressionResult memory result) {
        result = plan.result;
        if (result.newPositionId == 0 || result.positionAmount == 0) {
            return result;
        }
        result.newPositionId = storeReducedCombo(state, plan.remaining, plan.remainingCount, outcomeIndex);
    }

    function reducedPositionId(uint256[] memory remaining, uint256 remainingCount, uint8 outcomeIndex)
        internal
        pure
        returns (uint256 positionId)
    {
        uint256[] memory legs = compactRemainingLegs(remaining, remainingCount);
        bytes32 conditionId = LibNativePosition.comboConditionIdFor(legs);
        positionId = LibNativePosition.positionIdFor(LibNativePosition.MODULE_COMBINATORIAL, conditionId, outcomeIndex);
    }

    function storeReducedCombo(
        LibEveMarket.EveMarketStorage storage state,
        uint256[] memory remaining,
        uint256 remainingCount,
        uint8 outcomeIndex
    ) internal returns (uint256 positionId) {
        uint256[] memory legs = compactRemainingLegs(remaining, remainingCount);
        bytes32 conditionId = LibNativePosition.comboConditionIdFor(legs);
        LibEveMarket.ComboCondition storage condition = state.comboConditions[conditionId];
        if (!condition.exists) {
            condition.conditionId = conditionId;
            condition.legsHash = keccak256(abi.encode(legs));
            condition.legCount = uint16(legs.length);
            condition.preparedAt = uint64(block.timestamp);
            condition.exists = true;
            for (uint256 index; index < legs.length; ++index) {
                state.comboConditionLegs[conditionId].push(legs[index]);
            }

            uint256 yesPositionId = LibNativePosition.positionIdFor(
                LibNativePosition.MODULE_COMBINATORIAL, conditionId, LibNativePosition.OUTCOME_YES
            );
            uint256 noPositionId = LibNativePosition.positionIdFor(
                LibNativePosition.MODULE_COMBINATORIAL, conditionId, LibNativePosition.OUTCOME_NO
            );
            storeComboMetadata(state, conditionId, yesPositionId, LibNativePosition.OUTCOME_YES);
            storeComboMetadata(state, conditionId, noPositionId, LibNativePosition.OUTCOME_NO);
            emit Events.ComboConditionPrepared(
                conditionId, condition.legsHash, condition.legCount, yesPositionId, noPositionId, legs
            );
        }

        positionId = LibNativePosition.positionIdFor(LibNativePosition.MODULE_COMBINATORIAL, conditionId, outcomeIndex);
    }

    function compactRemainingLegs(uint256[] memory remaining, uint256 remainingCount)
        internal
        pure
        returns (uint256[] memory legs)
    {
        legs = new uint256[](remainingCount);
        for (uint256 index; index < remainingCount; ++index) {
            legs[index] = remaining[index];
        }
    }

    function validateCanonicalLiveLegs(LibEveMarket.EveMarketStorage storage state, uint256[] calldata legs)
        internal
        view
    {
        uint256 length = legs.length;
        if (length == 0 || length > MAX_LEGS) {
            revert Errors.ComboLegCountInvalid(length);
        }

        address expectedCollateral;
        uint8 expectedCollateralProfileId;
        for (uint256 index; index < length; ++index) {
            uint256 positionId = legs[index];
            LibEveMarket.NativePositionMetadata storage metadata = state.nativePositionMetadata[positionId];
            if (!isSupportedLeg(state, positionId, metadata)) {
                revert Errors.ComboUnsupportedPosition(positionId);
            }
            if (!LibNativePosition.isBinaryOutcome(metadata.outcomeIndex)) {
                revert Errors.NativeOutcomeUnsupported(metadata.outcomeIndex);
            }
            if (index != 0 && positionId <= legs[index - 1]) {
                revert Errors.ComboNonCanonicalLegs(legs[index - 1], positionId);
            }

            LibEveMarket.Market storage market = state.markets[metadata.marketId];
            if (market.marketId != metadata.marketId) {
                revert Errors.MarketNotFound(metadata.marketId);
            }
            if (market.state == LibEveMarket.MarketState.Resolved) {
                revert Errors.ComboLegMarketResolved(metadata.marketId);
            }
            if (
                market.state != LibEveMarket.MarketState.Trading || block.timestamp < market.tradingStartTime
                    || block.timestamp >= market.expiryTime
            ) {
                revert Errors.ComboLegMarketNotStarted(metadata.marketId);
            }
            if (index == 0) {
                expectedCollateral = market.collateralToken;
                expectedCollateralProfileId = market.collateralProfileId;
            } else if (market.collateralToken != expectedCollateral) {
                revert Errors.ComboCollateralMismatch(expectedCollateral, market.collateralToken);
            } else if (market.collateralProfileId != expectedCollateralProfileId) {
                revert Errors.ComboCollateralProfileMismatch(expectedCollateralProfileId, market.collateralProfileId);
            }

            for (uint256 previous; previous < index; ++previous) {
                LibEveMarket.NativePositionMetadata storage previousMetadata =
                    state.nativePositionMetadata[legs[previous]];
                requireCompatiblePair(state, previousMetadata, metadata);
            }
        }
    }

    function validateCanonicalLiveLegsMemory(LibEveMarket.EveMarketStorage storage state, uint256[] memory legs)
        internal
        view
    {
        uint256 length = legs.length;
        if (length == 0 || length > MAX_LEGS) {
            revert Errors.ComboLegCountInvalid(length);
        }

        address expectedCollateral;
        uint8 expectedCollateralProfileId;
        for (uint256 index; index < length; ++index) {
            uint256 positionId = legs[index];
            LibEveMarket.NativePositionMetadata storage metadata = state.nativePositionMetadata[positionId];
            if (!isSupportedLeg(state, positionId, metadata)) {
                revert Errors.ComboUnsupportedPosition(positionId);
            }
            if (!LibNativePosition.isBinaryOutcome(metadata.outcomeIndex)) {
                revert Errors.NativeOutcomeUnsupported(metadata.outcomeIndex);
            }
            if (index != 0 && positionId <= legs[index - 1]) {
                revert Errors.ComboNonCanonicalLegs(legs[index - 1], positionId);
            }

            LibEveMarket.Market storage market = state.markets[metadata.marketId];
            if (market.marketId != metadata.marketId) {
                revert Errors.MarketNotFound(metadata.marketId);
            }
            if (market.state == LibEveMarket.MarketState.Resolved) {
                revert Errors.ComboLegMarketResolved(metadata.marketId);
            }
            if (
                market.state != LibEveMarket.MarketState.Trading || block.timestamp < market.tradingStartTime
                    || block.timestamp >= market.expiryTime
            ) {
                revert Errors.ComboLegMarketNotStarted(metadata.marketId);
            }
            if (index == 0) {
                expectedCollateral = market.collateralToken;
                expectedCollateralProfileId = market.collateralProfileId;
            } else if (market.collateralToken != expectedCollateral) {
                revert Errors.ComboCollateralMismatch(expectedCollateral, market.collateralToken);
            } else if (market.collateralProfileId != expectedCollateralProfileId) {
                revert Errors.ComboCollateralProfileMismatch(expectedCollateralProfileId, market.collateralProfileId);
            }

            for (uint256 previous; previous < index; ++previous) {
                LibEveMarket.NativePositionMetadata storage previousMetadata =
                    state.nativePositionMetadata[legs[previous]];
                requireCompatiblePair(state, previousMetadata, metadata);
            }
        }
    }

    function collateralTokenFor(LibEveMarket.EveMarketStorage storage state, bytes32 conditionId)
        internal
        view
        returns (address collateralToken)
    {
        uint256[] storage legs = state.comboConditionLegs[conditionId];
        if (legs.length == 0) {
            revert Errors.ComboConditionNotFound(conditionId);
        }

        LibEveMarket.NativePositionMetadata storage metadata = state.nativePositionMetadata[legs[0]];
        LibEveMarket.Market storage market = state.markets[metadata.marketId];
        collateralToken = market.collateralToken;
        if (collateralToken == address(0)) {
            revert Errors.ZeroAddress();
        }
    }

    function collateralProfileFor(LibEveMarket.EveMarketStorage storage state, bytes32 conditionId)
        internal
        view
        returns (uint8 collateralProfileId)
    {
        uint256[] storage legs = state.comboConditionLegs[conditionId];
        if (legs.length == 0) {
            revert Errors.ComboConditionNotFound(conditionId);
        }
        collateralProfileId = state.markets[state.nativePositionMetadata[legs[0]].marketId].collateralProfileId;
    }

    function requireLiveConditionAndEarliestExpiry(LibEveMarket.EveMarketStorage storage state, bytes32 conditionId)
        internal
        view
        returns (uint64 earliestExpiryTime)
    {
        uint256[] storage legs = state.comboConditionLegs[conditionId];
        if (legs.length == 0) {
            revert Errors.ComboConditionNotFound(conditionId);
        }

        earliestExpiryTime = type(uint64).max;
        for (uint256 index; index < legs.length; ++index) {
            LibEveMarket.NativePositionMetadata storage metadata = state.nativePositionMetadata[legs[index]];
            if (!isSupportedLeg(state, legs[index], metadata)) {
                revert Errors.ComboUnsupportedPosition(legs[index]);
            }

            LibEveMarket.Market storage market = state.markets[metadata.marketId];
            if (market.marketId != metadata.marketId) {
                revert Errors.MarketNotFound(metadata.marketId);
            }
            if (market.state == LibEveMarket.MarketState.Resolved) {
                revert Errors.ComboLegMarketResolved(metadata.marketId);
            }
            if (
                market.state != LibEveMarket.MarketState.Trading || block.timestamp < market.tradingStartTime
                    || block.timestamp >= market.expiryTime
            ) {
                revert Errors.ComboLegMarketNotStarted(metadata.marketId);
            }
            if (market.expiryTime < earliestExpiryTime) {
                earliestExpiryTime = market.expiryTime;
            }
        }
    }

    function legPayout(LibEveMarket.EveMarketStorage storage state, uint256 leg)
        internal
        view
        returns (bool resolved, uint256 payoutNumerator)
    {
        LibEveMarket.NativePositionMetadata storage metadata = state.nativePositionMetadata[leg];
        if (!isSupportedLeg(state, leg, metadata)) {
            revert Errors.ComboUnsupportedPosition(leg);
        }
        LibEveMarket.CTFPositionMetadata storage ctfMetadata = state.ctfPositionMetadata[leg];
        IGnosisConditionalTokens ctf = IGnosisConditionalTokens(ctfMetadata.positionToken);
        uint256 denominator = ctf.payoutDenominator(ctfMetadata.conditionId);
        if (denominator == 0) return (false, 0);
        uint256 numerator = ctf.payoutNumerators(ctfMetadata.conditionId, metadata.outcomeIndex);
        return (true, Math.mulDiv(numerator, LibNativePosition.RESULT_DENOMINATOR, denominator));
    }

    function isSupportedLeg(
        LibEveMarket.EveMarketStorage storage state,
        uint256 positionId,
        LibEveMarket.NativePositionMetadata storage metadata
    ) internal view returns (bool supported) {
        supported = state.ctfPositionMetadata[positionId].exists && metadata.exists
            && (metadata.moduleId == LibNativePosition.MODULE_BINARY
                || metadata.moduleId == LibNativePosition.MODULE_NEGRISK)
            && LibNativePosition.isBinaryOutcome(metadata.outcomeIndex);
    }

    function requireCompatiblePair(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.NativePositionMetadata storage first,
        LibEveMarket.NativePositionMetadata storage second
    ) internal view {
        if (first.conditionId == second.conditionId) {
            revert Errors.ComboDuplicateCondition(second.conditionId);
        }
        if (
            first.moduleId != LibNativePosition.MODULE_NEGRISK || second.moduleId != LibNativePosition.MODULE_NEGRISK
                || first.marketId != second.marketId
        ) return;

        LibEveMarket.MultiOutcomeMarket storage multi = state.multiOutcomeMarkets[first.marketId];
        if (
            multi.outcomeCount == 2
                || (first.outcomeIndex == LibNativePosition.OUTCOME_YES
                    && second.outcomeIndex == LibNativePosition.OUTCOME_YES)
        ) {
            revert Errors.ComboConflictingConditions(first.conditionId, second.conditionId);
        }
    }
}
