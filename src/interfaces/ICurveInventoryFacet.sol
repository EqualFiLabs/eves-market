// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface ICurveInventoryFacet {
    function splitInventory(bytes32 marketId, uint128 collateralAmount) external returns (uint128 sharesMinted);
    function mergeInventory(bytes32 marketId, uint128 shareAmount) external returns (uint128 collateralOut);
}
