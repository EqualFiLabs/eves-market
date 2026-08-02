// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {NativePositionTypes} from "../types/NativePositionTypes.sol";

interface IComboCoreFacet {
    function prepareComboCondition(uint256[] calldata canonicalLegs)
        external
        returns (bytes32 conditionId, uint256 yesPositionId, uint256 noPositionId);

    function splitCombo(bytes32 conditionId, uint128 amount, address yesReceiver, address noReceiver)
        external
        returns (uint256 yesPositionId, uint256 noPositionId);

    function mergeCombo(bytes32 conditionId, uint128 amount, address receiver)
        external
        returns (uint128 collateralOut);

    function wrapCombo(uint256 underlyingPositionId, uint128 amount, address receiver)
        external
        returns (uint256 comboPositionId);

    function unwrapCombo(uint256 comboPositionId, uint128 amount, address receiver)
        external
        returns (uint256 underlyingPositionId);

    function getComboCondition(bytes32 conditionId)
        external
        view
        returns (NativePositionTypes.ComboConditionView memory condition);

    function getComboLegs(bytes32 conditionId) external view returns (uint256[] memory legs);
}
