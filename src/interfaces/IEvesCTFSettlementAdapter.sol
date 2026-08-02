// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IEvesCTFSettlementAdapter {
    function conditionalTokens() external view returns (address);
    function collateralToken() external view returns (address);
    function splitPosition(bytes32 conditionId, uint256 amount) external;
    function mergePositions(bytes32 conditionId, uint256 amount, address receiver) external;
    function redeemPositions(bytes32 conditionId, uint256[] calldata amounts, address receiver)
        external
        returns (uint256 payout);
}
