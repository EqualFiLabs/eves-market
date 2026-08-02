// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ProductAdapterTypes} from "../types/ProductAdapterTypes.sol";

interface IProductAdapter {
    function previewRisk(uint256 curveId, bytes calldata adapterData)
        external
        view
        returns (ProductAdapterTypes.RiskPreview memory preview);

    function activateRisk(uint256 curveId, uint128 baseAmount, uint128 quoteAmount, bytes calldata adapterData)
        external
        returns (ProductAdapterTypes.RiskDelta memory delta);

    function settleFill(
        uint256 curveId,
        address taker,
        address receiver,
        uint128 baseAmount,
        uint128 quoteAmount,
        bytes calldata adapterData
    ) external returns (ProductAdapterTypes.SettlementResult memory result);

    function reportInventory(bytes32 bucketId, bytes calldata adapterData)
        external
        view
        returns (ProductAdapterTypes.InventoryReport memory report);

    function reportFunding(bytes32 bucketId, bytes calldata adapterData)
        external
        view
        returns (ProductAdapterTypes.FundingReport memory report);

    function enterReduceOnly(bytes32 bucketId, bytes calldata adapterData) external returns (bool changed);

    function recover(bytes32 bucketId, bytes calldata adapterData)
        external
        returns (ProductAdapterTypes.RecoveryResult memory result);
}
