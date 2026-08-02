// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IComboViewFacet} from "../../interfaces/IComboViewFacet.sol";
import {Errors} from "../../libraries/Errors.sol";
import {LibCombinatorialPosition} from "../../libraries/LibCombinatorialPosition.sol";
import {LibEveMarket} from "../../libraries/LibEveMarket.sol";
import {NativePositionTypes} from "../../types/NativePositionTypes.sol";

contract ComboViewFacet is IComboViewFacet {
    function getNativePositionMetadata(uint256 positionId)
        external
        view
        returns (LibEveMarket.NativePositionMetadata memory metadata)
    {
        metadata = LibEveMarket.store().nativePositionMetadata[positionId];
        if (!metadata.exists) {
            revert Errors.NativePositionNotFound(positionId);
        }
    }

    function isComboCompressible(uint256 positionId) external view returns (bool compressible) {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.NativePositionMetadata storage metadata =
            LibCombinatorialPosition.requireComboPosition(state, positionId);
        uint256[] storage storedLegs = state.comboConditionLegs[metadata.conditionId];
        for (uint256 index; index < storedLegs.length; ++index) {
            (bool resolved,) = LibCombinatorialPosition.legPayout(state, storedLegs[index]);
            if (resolved) {
                return true;
            }
        }
    }

    function previewComboCompression(uint256 positionId, uint128 amount)
        external
        view
        returns (NativePositionTypes.CompressionResult memory result)
    {
        if (amount == 0) {
            revert Errors.InvalidAmount(amount);
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.NativePositionMetadata storage metadata =
            LibCombinatorialPosition.requireComboPosition(state, positionId);
        result = LibCombinatorialPosition.previewCompressionPlan(state, metadata, amount).result;
    }
}
