// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IGnosisConditionalTokens} from "../interfaces/IGnosisConditionalTokens.sol";
import {Errors} from "./Errors.sol";

library LibCTF {
    uint256 internal constant BINARY_OUTCOME_SLOT_COUNT = 2;
    uint256 internal constant YES_INDEX_SET = 1;
    uint256 internal constant NO_INDEX_SET = 2;

    function prepareMarketCondition(address conditionalTokens, bytes32 questionId)
        internal
        returns (bytes32 conditionId)
    {
        IGnosisConditionalTokens ctf = IGnosisConditionalTokens(conditionalTokens);
        conditionId = ctf.getConditionId(address(this), questionId, BINARY_OUTCOME_SLOT_COUNT);

        try ctf.prepareCondition(address(this), questionId, BINARY_OUTCOME_SLOT_COUNT) {}
        catch {
            if (!_isExpectedPreparedCondition(ctf, conditionId)) {
                revert Errors.CTFConditionPreparationFailed(questionId);
            }
        }
    }

    function conditionIdFor(address conditionalTokens, bytes32 questionId) internal view returns (bytes32 conditionId) {
        conditionId = IGnosisConditionalTokens(conditionalTokens)
            .getConditionId(address(this), questionId, BINARY_OUTCOME_SLOT_COUNT);
    }

    function derivePositionIds(address conditionalTokens, address collateralToken, bytes32 conditionId)
        internal
        view
        returns (uint256 yesPositionId, uint256 noPositionId)
    {
        IGnosisConditionalTokens ctf = IGnosisConditionalTokens(conditionalTokens);
        bytes32 yesCollectionId = ctf.getCollectionId(bytes32(0), conditionId, YES_INDEX_SET);
        bytes32 noCollectionId = ctf.getCollectionId(bytes32(0), conditionId, NO_INDEX_SET);

        yesPositionId = ctf.getPositionId(IERC20(collateralToken), yesCollectionId);
        noPositionId = ctf.getPositionId(IERC20(collateralToken), noCollectionId);
    }

    function splitCollateral(address conditionalTokens, address collateralToken, bytes32 conditionId, uint256 amount)
        internal
    {
        IGnosisConditionalTokens(conditionalTokens)
            .splitPosition(IERC20(collateralToken), bytes32(0), conditionId, binaryPartition(), amount);
    }

    function mergeCollateral(address conditionalTokens, address collateralToken, bytes32 conditionId, uint256 amount)
        internal
    {
        IGnosisConditionalTokens(conditionalTokens)
            .mergePositions(IERC20(collateralToken), bytes32(0), conditionId, binaryPartition(), amount);
    }

    function reportOutcome(address conditionalTokens, bytes32 questionId, uint256[] memory payouts) internal {
        IGnosisConditionalTokens(conditionalTokens).reportPayouts(questionId, payouts);
    }

    function _isExpectedPreparedCondition(IGnosisConditionalTokens ctf, bytes32 conditionId)
        private
        view
        returns (bool)
    {
        try ctf.getOutcomeSlotCount(conditionId) returns (uint256 outcomeSlotCount) {
            return outcomeSlotCount == BINARY_OUTCOME_SLOT_COUNT;
        } catch {
            return false;
        }
    }

    function binaryPartition() internal pure returns (uint256[] memory partition) {
        partition = new uint256[](2);
        partition[0] = YES_INDEX_SET;
        partition[1] = NO_INDEX_SET;
    }
}
