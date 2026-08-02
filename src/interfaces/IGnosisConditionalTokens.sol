// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IGnosisConditionalTokens {
    function prepareCondition(address oracle, bytes32 questionId, uint256 outcomeSlotCount) external;

    function splitPosition(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata partition,
        uint256 amount
    ) external;

    function mergePositions(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata partition,
        uint256 amount
    ) external;

    function redeemPositions(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata indexSets
    ) external;

    function reportPayouts(bytes32 questionId, uint256[] calldata payouts) external;

    function payoutDenominator(bytes32 conditionId) external view returns (uint256 denominator);

    function payoutNumerators(bytes32 conditionId, uint256 slot) external view returns (uint256 numerator);

    function getOutcomeSlotCount(bytes32 conditionId) external view returns (uint256 outcomeSlotCount);

    function getPositionId(IERC20 collateralToken, bytes32 collectionId) external pure returns (uint256 positionId);

    function getCollectionId(bytes32 parentCollectionId, bytes32 conditionId, uint256 indexSet)
        external
        view
        returns (bytes32 collectionId);

    function getConditionId(address oracle, bytes32 questionId, uint256 outcomeSlotCount)
        external
        pure
        returns (bytes32 conditionId);

    function balanceOf(address account, uint256 positionId) external view returns (uint256 balance);

    function setApprovalForAll(address operator, bool approved) external;

    function isApprovedForAll(address account, address operator) external view returns (bool approved);

    function safeTransferFrom(address from, address to, uint256 positionId, uint256 amount, bytes calldata data)
        external;
}
