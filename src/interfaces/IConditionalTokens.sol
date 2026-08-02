// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IGnosisConditionalTokens} from "./IGnosisConditionalTokens.sol";

interface IConditionalTokens is IGnosisConditionalTokens {
    error BinaryMarketsOnly(uint256 outcomeSlotCount);
    error ConditionAlreadyPrepared(bytes32 conditionId);
    error AmountMustBePositive();
    error ConditionAlreadyResolved(bytes32 conditionId);
    error InsufficientCollateral(address collateralToken, uint256 required, uint256 available);
    error PayoutsNotReported(bytes32 conditionId);
    error BinaryPayoutsRequired(uint256 payoutCount);
    error PayoutsAlreadyReported(bytes32 conditionId);
    error ZeroPayoutDenominator();
    error ConditionNotPrepared(bytes32 conditionId);
    error NestedCollectionsUnsupported(bytes32 parentCollectionId);
    error BinaryPartitionRequired(uint256 partitionLength);
    error InvalidBinaryPartition(uint256 firstIndexSet, uint256 secondIndexSet);
    error EmptyRedemptionSets();
    error DuplicateRedemptionSet(uint256 indexSet);
    error InvalidRedemptionIndex(uint256 indexSet);

    function getConditionDetails(bytes32 conditionId)
        external
        view
        returns (
            address oracle,
            bytes32 questionId,
            uint256 outcomeSlotCount,
            bool prepared,
            bool reported,
            uint256 reportedPayoutDenominator
        );
}
