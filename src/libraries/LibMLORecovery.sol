// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IStaticsDollar} from "@statics/dollar/interfaces/IStaticsDollar.sol";
import {IStaticsDollarCore} from "@statics/dollar/core/interfaces/IStaticsDollarCore.sol";
import {IMLOInsuranceFund} from "../interfaces/IMLOInsuranceFund.sol";
import {IMLOPredictionAdapterFacet} from "../interfaces/IMLOPredictionAdapterFacet.sol";
import {LibEveMarket} from "./LibEveMarket.sol";
import {LibMLOPredictionAdapter} from "./LibMLOPredictionAdapter.sol";
import {LibRiskEngine} from "./LibRiskEngine.sol";
import {MarginTypes} from "../types/MarginTypes.sol";
import {MLOPredictionTypes} from "../types/MLOPredictionTypes.sol";
import {ProductAdapterTypes} from "../types/ProductAdapterTypes.sol";

library LibMLORecovery {
    uint16 private constant MAX_CLEANUP_BATCH = 64;
    bytes32 private constant STATICS_DOLLAR_KIND = keccak256("STATICS_DOLLAR_TOKEN_V1");

    function config(LibEveMarket.EveMarketStorage storage state)
        internal
        view
        returns (MLOPredictionTypes.MLORecoveryConfig memory config_)
    {
        config_ = MLOPredictionTypes.MLORecoveryConfig({
            insuranceFund: state.mloInsuranceFund,
            seniorFundingBps: state.mloFundingSeniorBps,
            maxCleanupBatch: state.mloMaxCleanupBatch
        });
    }

    function setConfig(
        LibEveMarket.EveMarketStorage storage state,
        address insuranceFund,
        uint16 seniorFundingBps,
        uint16 maxCleanupBatch
    ) internal {
        if (insuranceFund == address(0) || insuranceFund.code.length == 0) {
            revert IMLOPredictionAdapterFacet.InvalidMLOInsuranceFund(insuranceFund);
        }
        if (seniorFundingBps > 10_000) {
            revert IMLOPredictionAdapterFacet.InvalidMLOFundingSplit(seniorFundingBps);
        }
        if (maxCleanupBatch == 0 || maxCleanupBatch > MAX_CLEANUP_BATCH) {
            revert IMLOPredictionAdapterFacet.MLOCleanupBatchTooLarge(maxCleanupBatch, MAX_CLEANUP_BATCH);
        }
        _enforceCanonicalStaticsDollar(state);
        IMLOInsuranceFund fund = IMLOInsuranceFund(insuranceFund);
        if (
            fund.asset() != state.marginAsset || fund.governance() != address(this)
                || fund.riskManager() != address(this)
        ) {
            revert IMLOPredictionAdapterFacet.InvalidMLOInsuranceFund(insuranceFund);
        }
        state.mloInsuranceFund = insuranceFund;
        state.mloFundingSeniorBps = seniorFundingBps;
        state.mloMaxCleanupBatch = maxCleanupBatch;
        emit IMLOPredictionAdapterFacet.MLORecoveryConfigSet(insuranceFund, seniorFundingBps, maxCleanupBatch);
    }

    function _enforceCanonicalStaticsDollar(LibEveMarket.EveMarketStorage storage state) private view {
        address asset = state.marginAsset;
        if (asset == address(0) || asset.code.length == 0) {
            revert IMLOPredictionAdapterFacet.InvalidMLOCollateral(asset);
        }

        bytes32 kind;
        address core;
        try IStaticsDollar(asset).coreTokenKind() returns (bytes32 tokenKind) {
            kind = tokenKind;
        } catch {
            revert IMLOPredictionAdapterFacet.InvalidMLOCollateral(asset);
        }
        try IStaticsDollar(asset).pool() returns (address pool_) {
            core = pool_;
        } catch {
            revert IMLOPredictionAdapterFacet.InvalidMLOCollateral(asset);
        }
        if (kind != STATICS_DOLLAR_KIND || core == address(0) || core.code.length == 0) {
            revert IMLOPredictionAdapterFacet.InvalidMLOCollateral(asset);
        }

        address configuredCore = state.config.staticsDollarCore;
        if (configuredCore != address(0)) {
            if (configuredCore != core || IStaticsDollarCore(configuredCore).staticsDollar() != asset) {
                revert IMLOPredictionAdapterFacet.InvalidMLOCollateral(asset);
            }
        }
    }

    function synchronizeState(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId)
        internal
        returns (MarginTypes.BucketState newState)
    {
        newState = LibRiskEngine.synchronizeMLOState(state, bucketId);
    }

    function cleanupCurves(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId, uint256[] calldata curveIds)
        internal
        returns (MLOPredictionTypes.MLOCurveCleanupResult memory result)
    {
        LibRiskEngine.synchronizeMLOState(state, bucketId);
        uint256 maximum = state.mloMaxCleanupBatch;
        if (curveIds.length > maximum) {
            revert IMLOPredictionAdapterFacet.MLOCleanupBatchTooLarge(curveIds.length, maximum);
        }
        for (uint256 index; index < curveIds.length; ++index) {
            (uint256 inventory, uint256 senior, uint256 risk, bool cleaned) =
                LibMLOPredictionAdapter.cleanupCurve(state, bucketId, curveIds[index]);
            if (!cleaned) continue;
            result.cleaned += 1;
            result.inventoryReleased += inventory;
            result.seniorReleased += senior;
            result.riskReleased += risk;
        }
        emit IMLOPredictionAdapterFacet.MLOCurveCleanupBatch(
            bucketId, msg.sender, result.cleaned, result.inventoryReleased, result.seniorReleased, result.riskReleased
        );
    }

    function maintainCurve(LibEveMarket.EveMarketStorage storage state, uint256 curveId)
        internal
        returns (bool cleaned)
    {
        ProductAdapterTypes.AdapterCurveMetadata storage metadata = state.adapterCurveMetadata[curveId];
        if (
            metadata.adapterKind != ProductAdapterTypes.ProductAdapterKind.MLOPrediction
                || metadata.backingKind != ProductAdapterTypes.CurveBackingKind.Adapter || !metadata.active
                || !state.curves[curveId].active
        ) return false;

        LibRiskEngine.synchronizeMLOState(state, metadata.bucketId);
        if (!LibMLOPredictionAdapter.isCurveCleanupAllowed(state, metadata.bucketId, curveId)) return false;
        (,,, cleaned) = LibMLOPredictionAdapter.cleanupCurve(state, metadata.bucketId, curveId);
    }

    function maintainCurves(LibEveMarket.EveMarketStorage storage state, uint256[] memory curveIds) internal {
        for (uint256 index; index < curveIds.length; ++index) {
            maintainCurve(state, curveIds[index]);
        }
    }
}
