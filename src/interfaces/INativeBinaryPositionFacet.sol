// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface INativeBinaryPositionFacet {
    struct BinaryPositionIds {
        bytes32 marketId;
        bytes32 conditionId;
        uint256 yesPositionId;
        uint256 noPositionId;
    }

    function prepareNativeBinaryCondition(bytes32 marketId) external returns (BinaryPositionIds memory ids);

    function getNativeBinaryCondition(bytes32 marketId) external view returns (BinaryPositionIds memory ids);

    function splitNativeBinary(bytes32 marketId, uint128 amount, address receiver)
        external
        returns (uint256 yesPositionId, uint256 noPositionId);

    function mergeNativeBinary(bytes32 marketId, uint128 amount, address receiver)
        external
        returns (uint128 collateralOut);

    function redeemNativeBinary(bytes32 marketId, uint8 outcomeIndex, uint128 amount, address receiver)
        external
        returns (uint128 collateralOut);

    function getNativeBinaryPayout(bytes32 conditionId, uint8 outcomeIndex)
        external
        view
        returns (bool resolved, uint256 payoutNumerator);
}
