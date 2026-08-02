// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Errors} from "./Errors.sol";
import {Events} from "./Events.sol";
import {LibEveMarket} from "./LibEveMarket.sol";
import {ProductAdapterTypes} from "../types/ProductAdapterTypes.sol";

library LibProductAdapter {
    function curveBackingKind(LibEveMarket.EveMarketStorage storage state, uint256 curveId)
        internal
        view
        returns (ProductAdapterTypes.CurveBackingKind backingKind)
    {
        backingKind = state.adapterCurveMetadata[curveId].backingKind;
    }

    function adapterCurveMetadata(LibEveMarket.EveMarketStorage storage state, uint256 curveId)
        internal
        view
        returns (ProductAdapterTypes.AdapterCurveMetadata memory metadata)
    {
        metadata = state.adapterCurveMetadata[curveId];
    }

    function isEscrowBackedCurve(LibEveMarket.EveMarketStorage storage state, uint256 curveId)
        internal
        view
        returns (bool)
    {
        return curveBackingKind(state, curveId) == ProductAdapterTypes.CurveBackingKind.Escrow;
    }

    function requireEscrowBackedCurve(LibEveMarket.EveMarketStorage storage state, uint256 curveId) internal view {
        ProductAdapterTypes.CurveBackingKind backingKind_ = curveBackingKind(state, curveId);
        if (backingKind_ != ProductAdapterTypes.CurveBackingKind.Escrow) {
            revert Errors.CurveBackingMismatch(
                curveId, uint8(ProductAdapterTypes.CurveBackingKind.Escrow), uint8(backingKind_)
            );
        }
    }

    function requireActiveAdapterCurve(LibEveMarket.EveMarketStorage storage state, uint256 curveId)
        internal
        view
        returns (ProductAdapterTypes.AdapterCurveMetadata memory metadata)
    {
        metadata = state.adapterCurveMetadata[curveId];
        if (metadata.backingKind != ProductAdapterTypes.CurveBackingKind.Adapter) {
            revert Errors.AdapterCurveMetadataMissing(curveId);
        }
        if (!metadata.active) {
            revert Errors.AdapterCurveInactive(curveId);
        }
    }

    function setAdapterCurveMetadata(
        LibEveMarket.EveMarketStorage storage state,
        uint256 curveId,
        ProductAdapterTypes.ProductAdapterKind adapterKind,
        bytes32 bucketId,
        bytes32 riskDomainId,
        bytes32 adapterDataKey
    ) internal {
        if (state.curves[curveId].bookId == bytes32(0) || !state.curves[curveId].active) {
            revert Errors.CurveNotActive(curveId);
        }
        if (adapterKind == ProductAdapterTypes.ProductAdapterKind.None) {
            revert Errors.InvalidProductAdapter(uint8(adapterKind));
        }
        if (bucketId == bytes32(0) || riskDomainId == bytes32(0)) {
            revert Errors.InvalidAmount(0);
        }

        state.adapterCurveMetadata[curveId] = ProductAdapterTypes.AdapterCurveMetadata({
            backingKind: ProductAdapterTypes.CurveBackingKind.Adapter,
            adapterKind: adapterKind,
            bucketId: bucketId,
            riskDomainId: riskDomainId,
            adapterDataKey: adapterDataKey,
            active: true
        });

        emit Events.AdapterCurveMetadataSet(curveId, bucketId, riskDomainId, uint8(adapterKind), adapterDataKey, true);
    }

    function disableAdapterCurveMetadata(LibEveMarket.EveMarketStorage storage state, uint256 curveId) internal {
        ProductAdapterTypes.AdapterCurveMetadata storage metadata = state.adapterCurveMetadata[curveId];
        if (metadata.backingKind != ProductAdapterTypes.CurveBackingKind.Adapter) {
            revert Errors.AdapterCurveMetadataMissing(curveId);
        }
        metadata.active = false;

        emit Events.AdapterCurveMetadataSet(
            curveId,
            metadata.bucketId,
            metadata.riskDomainId,
            uint8(metadata.adapterKind),
            metadata.adapterDataKey,
            false
        );
    }
}
