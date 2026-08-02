// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface ICTFPositionViewFacet {
    function getCTFPositionMetadata(uint256 positionId)
        external
        view
        returns (
            address positionToken,
            address collateralToken,
            address settlementAdapter,
            bytes32 conditionId,
            uint256 complementPositionId,
            uint128 payoutUnit,
            bool exists
        );

    function getCTFComboEscrow(uint256 positionId) external view returns (uint256 amount);
    function getCTFConditionPositions(bytes32 conditionId)
        external
        view
        returns (uint256 yesPositionId, uint256 noPositionId);
}
