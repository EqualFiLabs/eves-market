// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {NativePositionTypes} from "../types/NativePositionTypes.sol";

interface IComboViewFacet {
    function getNativePositionMetadata(uint256 positionId)
        external
        view
        returns (LibEveMarket.NativePositionMetadata memory metadata);

    function isComboCompressible(uint256 positionId) external view returns (bool compressible);

    function previewComboCompression(uint256 positionId, uint128 amount)
        external
        view
        returns (NativePositionTypes.CompressionResult memory result);
}
