// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IComboBranchFacet {
    function splitComboOnCondition(
        uint256 parentYesPositionId,
        bytes32 binaryConditionId,
        uint128 amount,
        address yesReceiver,
        address noReceiver
    ) external returns (uint256 childYesPositionId, uint256 childNoPositionId);

    function mergeComboOnCondition(
        uint256 parentYesPositionId,
        bytes32 binaryConditionId,
        uint128 amount,
        address receiver
    ) external returns (uint256 parentPositionId);

    function extractComboNoLeg(
        uint256 fullNoPositionId,
        uint256 legIndex,
        uint128 amount,
        address reducedNoReceiver,
        address residualYesReceiver
    ) external returns (uint256 reducedNoPositionId, uint256 residualYesPositionId);

    function injectComboNoLeg(uint256 fullNoPositionId, uint256 legIndex, uint128 amount, address receiver)
        external
        returns (uint256 fullNoPositionIdOut);

    function convertComboNoToYesBasket(uint256 fullNoPositionId, uint128 amount, address[] calldata receivers)
        external
        returns (uint256[] memory basketPositionIds);

    function mergeComboNoFromYesBasket(uint256 fullNoPositionId, uint128 amount, address receiver)
        external
        returns (uint256 fullNoPositionIdOut);
}
