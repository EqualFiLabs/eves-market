// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IBondManagerFacet {
    function slashBond(bytes32 marketId, uint256 proposalIndex, address recipient) external returns (uint128 amount);

    function returnBond(bytes32 marketId, uint256 proposalIndex) external returns (uint128 amount);

    function routeBond(address recipient, uint128 amount) external;
}
