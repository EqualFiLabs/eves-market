// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IMarginAccountFacet} from "../interfaces/IMarginAccountFacet.sol";
import {Math} from "../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {LibEveMarket} from "./LibEveMarket.sol";
import {LibMarkOracle} from "./LibMarkOracle.sol";
import {MarginTypes} from "../types/MarginTypes.sol";
import {MarkOracleTypes} from "../types/MarkOracleTypes.sol";

library LibRiskEngine {
    uint16 internal constant MAX_BPS = 10_000;
    uint16 internal constant DEFAULT_MARGIN_BPS = 10_000;
    uint256 internal constant WAD = 1e18;

    function bucketRisk(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId)
        internal
        view
        returns (MarginTypes.BucketRisk memory risk)
    {
        MarginTypes.MarginBucket storage bucket = requireBucket(state, bucketId);
        risk = MarginTypes.BucketRisk({
            openOrderRisk: bucket.openOrderRisk,
            pendingFillRisk: bucket.pendingFillRisk,
            positionRisk: bucket.positionRisk,
            vaultDebt: bucket.vaultDebt,
            fundingLiability: bucket.fundingLiability,
            realizedProfits: bucket.realizedProfits,
            realizedLosses: bucket.realizedLosses,
            unrealizedProfits: bucket.unrealizedProfits,
            unrealizedLosses: bucket.unrealizedLosses,
            recoveryProfits: bucket.recoveryProfits,
            recoveryLosses: bucket.recoveryLosses,
            badDebt: bucket.badDebt,
            lockedRisk: lockedRisk(bucket)
        });
    }

    function lockedRisk(MarginTypes.MarginBucket storage bucket) internal view returns (uint256 locked) {
        locked = bucket.openOrderRisk + bucket.pendingFillRisk + bucket.positionRisk + bucket.vaultDebt
            + bucket.fundingLiability + bucket.unrealizedLosses + bucket.recoveryLosses + bucket.badDebt;
    }

    function exposure(MarginTypes.MarginBucket storage bucket) internal view returns (uint256 exposure_) {
        exposure_ = bucket.openOrderRisk + bucket.pendingFillRisk + bucket.positionRisk + bucket.vaultDebt;
    }

    function liabilityDrag(MarginTypes.MarginBucket storage bucket) internal view returns (uint256 liabilities) {
        liabilities = bucket.fundingLiability + bucket.unrealizedLosses + bucket.recoveryLosses + bucket.badDebt;
    }

    function marginEquity(MarginTypes.MarginBucket storage bucket) internal view returns (uint256 equity) {
        uint256 liabilities = liabilityDrag(bucket);
        equity = bucket.marginAllocated > liabilities ? bucket.marginAllocated - liabilities : 0;
    }

    function marginEquityWithPendingFunding(
        LibEveMarket.EveMarketStorage storage state,
        MarginTypes.MarginBucket storage bucket
    ) internal view returns (uint256 equity) {
        uint256 liabilities =
            liabilityDrag(bucket) + pendingConfiguredFunding(state, bucket);
        equity = bucket.marginAllocated > liabilities ? bucket.marginAllocated - liabilities : 0;
    }

    function bucketHealth(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId)
        internal
        view
        returns (MarginTypes.BucketHealth memory health)
    {
        MarginTypes.MarginBucket storage bucket = requireBucket(state, bucketId);
        health = healthForBucket(state, bucket);
    }

    function healthForBucket(LibEveMarket.EveMarketStorage storage state, MarginTypes.MarginBucket storage bucket)
        internal
        view
        returns (MarginTypes.BucketHealth memory health)
    {
        uint256 equity = marginEquityWithPendingFunding(state, bucket);
        uint256 exposure_ = exposure(bucket);
        MarginTypes.RiskParams memory params = riskParamsForBucket(state, bucket);
        uint256 initialRequirement = _requirement(exposure_, params.initialMarginBps);
        uint256 maintenanceRequirement = _requirement(exposure_, params.maintenanceMarginBps);

        MarginTypes.BucketHealthStatus status = MarginTypes.BucketHealthStatus.Healthy;
        if (equity < maintenanceRequirement) {
            status = MarginTypes.BucketHealthStatus.BelowMaintenance;
        } else if (equity < initialRequirement) {
            status = MarginTypes.BucketHealthStatus.BelowInitial;
        }

        health = MarginTypes.BucketHealth({
            marginEquity: equity,
            exposure: exposure_,
            initialRequirement: initialRequirement,
            maintenanceRequirement: maintenanceRequirement,
            excessInitial: equity > initialRequirement ? equity - initialRequirement : 0,
            excessMaintenance: equity > maintenanceRequirement ? equity - maintenanceRequirement : 0,
            status: status
        });
    }

    function riskParamsForBucket(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId)
        internal
        view
        returns (MarginTypes.RiskParams memory params)
    {
        MarginTypes.MarginBucket storage bucket = requireBucket(state, bucketId);
        params = riskParamsForBucket(state, bucket);
    }

    function riskParamsForBucket(LibEveMarket.EveMarketStorage storage state, MarginTypes.MarginBucket storage bucket)
        internal
        view
        returns (MarginTypes.RiskParams memory params)
    {
        params = state.marginRiskDomainParams[bucket.riskDomainId];
        if (params.initialMarginBps != 0 || params.maintenanceMarginBps != 0) {
            return params;
        }

        params = state.marginDefaultRiskParams[uint8(bucket.kind)];
        if (params.initialMarginBps == 0 && params.maintenanceMarginBps == 0) {
            params = MarginTypes.RiskParams({
                initialMarginBps: DEFAULT_MARGIN_BPS, maintenanceMarginBps: DEFAULT_MARGIN_BPS
            });
        }
    }

    function riskMarkForDomain(LibEveMarket.EveMarketStorage storage state, bytes32 riskDomainId)
        internal
        view
        returns (MarkOracleTypes.RiskMark memory mark)
    {
        requireRiskDomain(riskDomainId);
        MarginTypes.RiskDomainOracleConfig memory oracleConfig = state.marginRiskDomainOracles[riskDomainId];
        if (oracleConfig.kind != MarginTypes.RiskDomainOracleKind.BookMark) {
            revert IMarginAccountFacet.InvalidRiskDomain(riskDomainId);
        }

        mark = LibMarkOracle.riskMarkForBook(
            state, oracleConfig.oracleKey, state.marginRiskDomainMarkConfigs[riskDomainId]
        );
    }

    function canIncreaseRisk(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId)
        internal
        view
        returns (bool)
    {
        MarginTypes.MarginBucket storage bucket = state.marginBuckets[bucketId];
        if (!bucket.exists) {
            return false;
        }

        bool stateAllows = bucket.state == MarginTypes.BucketState.Healthy
            || (bucket.state == MarginTypes.BucketState.Warning && state.marginWarningRiskIncreaseAllowed);
        if (!stateAllows) {
            return false;
        }

        return healthForBucket(state, bucket).status == MarginTypes.BucketHealthStatus.Healthy;
    }

    function canIncreaseRiskForBook(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId, bytes32 bookId)
        internal
        view
        returns (bool)
    {
        MarginTypes.MarginBucket storage bucket = state.marginBuckets[bucketId];
        if (!canIncreaseRisk(state, bucketId)) {
            return false;
        }

        MarginTypes.RiskDomainOracleConfig memory config = state.marginRiskDomainOracles[bucket.riskDomainId];
        if (config.kind == MarginTypes.RiskDomainOracleKind.None) {
            return true;
        }
        if (config.kind == MarginTypes.RiskDomainOracleKind.BookMark && config.oracleKey == bookId) {
            return _oracleAllowsRiskIncrease(state, bucket.riskDomainId, config);
        }

        return true;
    }

    function configureRiskDomainOracle(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 riskDomainId,
        MarginTypes.RiskDomainOracleKind kind,
        bytes32 oracleKey
    ) internal {
        requireRiskDomain(riskDomainId);
        if (kind != MarginTypes.RiskDomainOracleKind.None && oracleKey == bytes32(0)) {
            revert IMarginAccountFacet.InvalidRiskDomain(oracleKey);
        }

        state.marginRiskDomainOracles[riskDomainId] =
            MarginTypes.RiskDomainOracleConfig({kind: kind, oracleKey: oracleKey});

        emit IMarginAccountFacet.RiskDomainOracleConfigured(riskDomainId, kind, oracleKey);
    }

    function configureRiskDomainMark(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 riskDomainId,
        uint32 lookbackSeconds,
        uint16 assetHaircutBps,
        uint16 liabilityPremiumBps
    ) internal {
        requireRiskDomain(riskDomainId);
        validateRiskMarkParams(lookbackSeconds, assetHaircutBps, liabilityPremiumBps);

        state.marginRiskDomainMarkConfigs[riskDomainId] = MarkOracleTypes.RiskMarkConfig({
            lookbackSeconds: lookbackSeconds, assetHaircutBps: assetHaircutBps, liabilityPremiumBps: liabilityPremiumBps
        });

        emit IMarginAccountFacet.RiskDomainMarkConfigSet(
            riskDomainId, lookbackSeconds, assetHaircutBps, liabilityPremiumBps
        );
    }

    function configureRiskDomainFunding(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 riskDomainId,
        MarginTypes.FundingMode mode,
        uint128 ratePerSecondWad
    ) internal {
        requireRiskDomain(riskDomainId);
        validateFundingConfig(mode, ratePerSecondWad);

        state.marginRiskDomainFundingConfigs[riskDomainId] = MarginTypes.FundingConfig({
            mode: mode, lastConfiguredAt: uint64(block.timestamp), ratePerSecondWad: ratePerSecondWad
        });

        emit IMarginAccountFacet.RiskDomainFundingConfigSet(riskDomainId, mode, ratePerSecondWad);
    }

    function configureDefaultRiskParams(
        LibEveMarket.EveMarketStorage storage state,
        MarginTypes.BucketKind kind,
        uint16 initialMarginBps,
        uint16 maintenanceMarginBps
    ) internal {
        validateRiskParams(initialMarginBps, maintenanceMarginBps);
        state.marginDefaultRiskParams[uint8(kind)] =
            MarginTypes.RiskParams({initialMarginBps: initialMarginBps, maintenanceMarginBps: maintenanceMarginBps});

        emit IMarginAccountFacet.DefaultRiskParamsSet(kind, initialMarginBps, maintenanceMarginBps);
    }

    function configureRiskDomainRiskParams(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 riskDomainId,
        uint16 initialMarginBps,
        uint16 maintenanceMarginBps
    ) internal {
        requireRiskDomain(riskDomainId);
        validateRiskParams(initialMarginBps, maintenanceMarginBps);
        state.marginRiskDomainParams[riskDomainId] =
            MarginTypes.RiskParams({initialMarginBps: initialMarginBps, maintenanceMarginBps: maintenanceMarginBps});

        emit IMarginAccountFacet.RiskDomainRiskParamsSet(riskDomainId, initialMarginBps, maintenanceMarginBps);
    }

    function clearRiskDomainRiskParams(LibEveMarket.EveMarketStorage storage state, bytes32 riskDomainId) internal {
        requireRiskDomain(riskDomainId);
        delete state.marginRiskDomainParams[riskDomainId];

        emit IMarginAccountFacet.RiskDomainRiskParamsCleared(riskDomainId);
    }

    function increaseOpenOrderRisk(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId, uint256 assets)
        internal
    {
        requireAmount(assets);
        MarginTypes.MarginBucket storage bucket = requireBucket(state, bucketId);
        accrueConfiguredFunding(state, bucketId, bucket);
        enforceCanIncreaseRisk(state, bucketId, bucket);
        enforceInitialMarginAfter(state, bucketId, bucket, assets, 0);

        bucket.openOrderRisk += assets;
        bucket.reservedRisk = bucket.openOrderRisk;

        emit IMarginAccountFacet.BucketOpenOrderRiskIncreased(bucketId, assets);
    }

    function increaseOpenOrderRiskForBook(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bucketId,
        bytes32 bookId,
        uint256 assets
    ) internal {
        requireAmount(assets);
        MarginTypes.MarginBucket storage bucket = requireBucket(state, bucketId);
        accrueConfiguredFunding(state, bucketId, bucket);
        enforceCanIncreaseRiskForBook(state, bucketId, bucket, bookId);
        enforceInitialMarginAfter(state, bucketId, bucket, assets, 0);

        bucket.openOrderRisk += assets;
        bucket.reservedRisk = bucket.openOrderRisk;

        emit IMarginAccountFacet.BucketOpenOrderRiskIncreased(bucketId, assets);
    }

    function releaseOpenOrderRisk(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId, uint256 assets)
        internal
    {
        requireAmount(assets);
        MarginTypes.MarginBucket storage bucket = requireBucket(state, bucketId);
        if (assets > bucket.openOrderRisk) {
            revert IMarginAccountFacet.InsufficientOpenOrderRisk(bucketId, assets, bucket.openOrderRisk);
        }

        bucket.openOrderRisk -= assets;
        bucket.reservedRisk = bucket.openOrderRisk;

        emit IMarginAccountFacet.BucketOpenOrderRiskReleased(bucketId, assets);
    }

    function moveOpenOrderToPositionRisk(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId, uint256 assets)
        internal
    {
        requireAmount(assets);
        MarginTypes.MarginBucket storage bucket = requireBucket(state, bucketId);
        if (assets > bucket.openOrderRisk) {
            revert IMarginAccountFacet.InsufficientOpenOrderRisk(bucketId, assets, bucket.openOrderRisk);
        }

        bucket.openOrderRisk -= assets;
        bucket.positionRisk += assets;
        bucket.reservedRisk = bucket.openOrderRisk;
        bucket.activeRisk = bucket.positionRisk;

        emit IMarginAccountFacet.BucketOpenOrderRiskMovedToPosition(bucketId, assets);
    }

    function releasePositionRisk(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId, uint256 assets)
        internal
    {
        requireAmount(assets);
        MarginTypes.MarginBucket storage bucket = requireBucket(state, bucketId);
        if (assets > bucket.positionRisk) {
            revert IMarginAccountFacet.InsufficientPositionRisk(bucketId, assets, bucket.positionRisk);
        }

        bucket.positionRisk -= assets;
        bucket.activeRisk = bucket.positionRisk;

        emit IMarginAccountFacet.BucketPositionRiskReleased(bucketId, assets);
    }

    function recordDebt(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId, uint256 assets) internal {
        requireAmount(assets);
        MarginTypes.MarginBucket storage bucket = requireBucket(state, bucketId);
        accrueConfiguredFunding(state, bucketId, bucket);
        enforceCanIncreaseRisk(state, bucketId, bucket);
        enforceInitialMarginAfter(state, bucketId, bucket, assets, 0);

        bucket.vaultDebt += assets;

        emit IMarginAccountFacet.BucketDebtRecorded(bucketId, assets);
    }

    function recordDebtTrusted(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId, uint256 assets) internal {
        requireAmount(assets);
        MarginTypes.MarginBucket storage bucket = requireBucket(state, bucketId);
        accrueConfiguredFunding(state, bucketId, bucket);
        bucket.vaultDebt += assets;

        emit IMarginAccountFacet.BucketDebtRecorded(bucketId, assets);
    }

    function repayDebt(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId, uint256 assets) internal {
        requireAmount(assets);
        MarginTypes.MarginBucket storage bucket = requireBucket(state, bucketId);
        accrueConfiguredFunding(state, bucketId, bucket);
        if (assets > bucket.vaultDebt) {
            revert IMarginAccountFacet.InsufficientDebt(bucketId, assets, bucket.vaultDebt);
        }

        bucket.vaultDebt -= assets;

        emit IMarginAccountFacet.BucketDebtRepaid(bucketId, assets);
    }

    function accrueFunding(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId, uint256 assets) internal {
        requireAmount(assets);
        MarginTypes.MarginBucket storage bucket = requireBucket(state, bucketId);
        accrueConfiguredFunding(state, bucketId, bucket);
        bucket.fundingLiability += assets;

        emit IMarginAccountFacet.BucketFundingAccrued(bucketId, assets);
    }

    function settleFunding(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId, uint256 assets) internal {
        requireAmount(assets);
        MarginTypes.MarginBucket storage bucket = requireBucket(state, bucketId);
        accrueConfiguredFunding(state, bucketId, bucket);
        if (assets > bucket.fundingLiability) {
            revert IMarginAccountFacet.InsufficientFundingLiability(bucketId, assets, bucket.fundingLiability);
        }

        bucket.fundingLiability -= assets;

        emit IMarginAccountFacet.BucketFundingSettled(bucketId, assets);
    }

    function accrueConfiguredFunding(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId)
        internal
        returns (uint256 accrued)
    {
        MarginTypes.MarginBucket storage bucket = requireBucket(state, bucketId);
        accrued = accrueConfiguredFunding(state, bucketId, bucket);
    }

    function accrueConfiguredFunding(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bucketId,
        MarginTypes.MarginBucket storage bucket
    ) internal returns (uint256 accrued) {
        accrued = pendingConfiguredFunding(state, bucket);
        MarginTypes.FundingConfig memory config = state.marginRiskDomainFundingConfigs[bucket.riskDomainId];
        if (config.mode == MarginTypes.FundingMode.None) {
            bucket.lastFundingAccruedAt = uint64(block.timestamp);
            return 0;
        }

        bucket.lastFundingAccruedAt = uint64(block.timestamp);
        if (accrued == 0) {
            return 0;
        }

        bucket.fundingLiability += accrued;
        emit IMarginAccountFacet.BucketFundingAccrued(bucketId, accrued);
    }

    function pendingConfiguredFunding(
        LibEveMarket.EveMarketStorage storage state,
        MarginTypes.MarginBucket storage bucket
    ) internal view returns (uint256 pending) {
        MarginTypes.FundingConfig memory config = state.marginRiskDomainFundingConfigs[bucket.riskDomainId];
        if (config.mode == MarginTypes.FundingMode.None || bucket.vaultDebt == 0) {
            return 0;
        }

        uint256 accrualStart = bucket.lastFundingAccruedAt;
        if (accrualStart < config.lastConfiguredAt) {
            accrualStart = config.lastConfiguredAt;
        }

        if (block.timestamp <= accrualStart) {
            return 0;
        }

        uint256 elapsed = block.timestamp - accrualStart;
        pending = Math.mulDiv(bucket.vaultDebt, uint256(config.ratePerSecondWad) * elapsed, WAD, Math.Rounding.Ceil);
    }

    function recordUnrealizedPnl(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bucketId,
        uint256 profits,
        uint256 losses
    ) internal {
        MarginTypes.MarginBucket storage bucket = requireBucket(state, bucketId);
        bucket.unrealizedProfits = profits;
        bucket.unrealizedLosses = losses;

        emit IMarginAccountFacet.BucketUnrealizedPnlRecorded(bucketId, profits, losses);
    }

    function recordRecoveryPnl(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bucketId,
        uint256 profits,
        uint256 losses
    ) internal {
        MarginTypes.MarginBucket storage bucket = requireBucket(state, bucketId);
        bucket.recoveryProfits = profits;
        bucket.recoveryLosses = losses;

        emit IMarginAccountFacet.BucketRecoveryPnlRecorded(bucketId, profits, losses);
    }

    function recordBadDebt(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId, uint256 assets) internal {
        requireAmount(assets);
        MarginTypes.MarginBucket storage bucket = requireBucket(state, bucketId);
        bucket.badDebt += assets;

        emit IMarginAccountFacet.BucketBadDebtRecorded(bucketId, assets);
    }

    function enforceCanIncreaseRisk(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bucketId,
        MarginTypes.MarginBucket storage bucket
    ) internal view {
        if (!canIncreaseRisk(state, bucketId)) {
            revert IMarginAccountFacet.BucketCannotIncreaseRisk(bucketId, bucket.state);
        }
    }

    function enforceCanIncreaseRiskForBook(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bucketId,
        MarginTypes.MarginBucket storage bucket,
        bytes32 bookId
    ) internal view {
        enforceCanIncreaseRisk(state, bucketId, bucket);

        MarginTypes.RiskDomainOracleConfig memory config = state.marginRiskDomainOracles[bucket.riskDomainId];
        if (config.kind == MarginTypes.RiskDomainOracleKind.None) {
            return;
        }
        if (config.kind == MarginTypes.RiskDomainOracleKind.BookMark && config.oracleKey == bookId) {
            MarkOracleTypes.RiskMark memory mark = LibMarkOracle.riskMarkForBook(
                state, config.oracleKey, state.marginRiskDomainMarkConfigs[bucket.riskDomainId]
            );
            if (!_oracleStateAllowsRiskIncrease(state, mark.state)) {
                revert IMarginAccountFacet.RiskDomainOracleBlocked(
                    bucket.riskDomainId, config.oracleKey, config.kind, uint8(mark.state)
                );
            }
        }
    }

    function enforceInitialMarginAfter(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bucketId,
        MarginTypes.MarginBucket storage bucket,
        uint256 exposureIncrease,
        uint256 marginDecrease
    ) internal view {
        uint256 liabilities = liabilityDrag(bucket);
        uint256 equityBefore = bucket.marginAllocated > liabilities ? bucket.marginAllocated - liabilities : 0;
        uint256 equityAfter = equityBefore > marginDecrease ? equityBefore - marginDecrease : 0;
        uint256 exposureAfter = exposure(bucket) + exposureIncrease;
        uint256 required = _requirement(exposureAfter, riskParamsForBucket(state, bucket).initialMarginBps);

        if (equityAfter < required) {
            revert IMarginAccountFacet.BucketBelowInitialMargin(bucketId, equityAfter, required);
        }
    }

    function validateRiskParams(uint16 initialMarginBps, uint16 maintenanceMarginBps) internal pure {
        if (maintenanceMarginBps == 0 || initialMarginBps < maintenanceMarginBps || initialMarginBps > MAX_BPS) {
            revert IMarginAccountFacet.InvalidMarginRiskParams(initialMarginBps, maintenanceMarginBps);
        }
    }

    function validateRiskMarkParams(uint32 lookbackSeconds, uint16 assetHaircutBps, uint16 liabilityPremiumBps)
        internal
        pure
    {
        if (assetHaircutBps > MAX_BPS || liabilityPremiumBps > MAX_BPS) {
            revert IMarginAccountFacet.InvalidRiskMarkConfig(lookbackSeconds, assetHaircutBps, liabilityPremiumBps);
        }
    }

    function validateFundingConfig(MarginTypes.FundingMode mode, uint128 ratePerSecondWad) internal pure {
        if (
            (mode == MarginTypes.FundingMode.None && ratePerSecondWad != 0)
                || (mode == MarginTypes.FundingMode.BorrowRate && ratePerSecondWad == 0)
        ) {
            revert IMarginAccountFacet.InvalidFundingConfig(mode, ratePerSecondWad);
        }
    }

    function requireBucket(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId)
        internal
        view
        returns (MarginTypes.MarginBucket storage bucket)
    {
        bucket = state.marginBuckets[bucketId];
        if (!bucket.exists) {
            revert IMarginAccountFacet.MarginBucketNotFound(bucketId);
        }
    }

    function requireRiskDomain(bytes32 riskDomainId) internal pure {
        if (riskDomainId == bytes32(0)) {
            revert IMarginAccountFacet.InvalidRiskDomain(riskDomainId);
        }
    }

    function requireAmount(uint256 assets) internal pure {
        if (assets == 0) {
            revert IMarginAccountFacet.ZeroAmount();
        }
    }

    function _requirement(uint256 exposure_, uint16 marginBps) private pure returns (uint256 requirement) {
        requirement = Math.mulDiv(exposure_, marginBps, MAX_BPS, Math.Rounding.Ceil);
    }

    function _oracleAllowsRiskIncrease(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 riskDomainId,
        MarginTypes.RiskDomainOracleConfig memory config
    ) private view returns (bool) {
        MarkOracleTypes.RiskMark memory mark = LibMarkOracle.riskMarkForBook(
            state, config.oracleKey, state.marginRiskDomainMarkConfigs[riskDomainId]
        );
        return _oracleStateAllowsRiskIncrease(state, mark.state);
    }

    function _oracleStateAllowsRiskIncrease(
        LibEveMarket.EveMarketStorage storage state,
        MarkOracleTypes.OracleState oracleState
    ) private view returns (bool) {
        if (oracleState == MarkOracleTypes.OracleState.Normal) {
            return true;
        }
        if (oracleState == MarkOracleTypes.OracleState.Caution) {
            return state.marginWarningRiskIncreaseAllowed;
        }
        return false;
    }
}
