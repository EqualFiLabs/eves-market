// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {PlainGnosisCTFMock} from "./PlainGnosisCTFMock.sol";

contract MockConditionalTokens is PlainGnosisCTFMock {
    struct ConditionDetails {
        address oracle;
        bytes32 questionId;
        uint256 outcomeSlotCount;
        bool prepared;
        bool reported;
    }

    mapping(bytes32 conditionId => ConditionDetails) internal _details;

    function prepareCondition(address oracle, bytes32 questionId, uint256 outcomeSlotCount) public override {
        super.prepareCondition(oracle, questionId, outcomeSlotCount);

        bytes32 conditionId = getConditionId(oracle, questionId, outcomeSlotCount);
        _details[conditionId] = ConditionDetails({
            oracle: oracle,
            questionId: questionId,
            outcomeSlotCount: outcomeSlotCount,
            prepared: true,
            reported: false
        });
    }

    function reportPayouts(bytes32 questionId, uint256[] calldata payouts) public override {
        super.reportPayouts(questionId, payouts);

        bytes32 conditionId = getConditionId(msg.sender, questionId, payouts.length);
        _details[conditionId].reported = true;
    }

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
        )
    {
        ConditionDetails storage details = _details[conditionId];
        return (
            details.oracle,
            details.questionId,
            details.outcomeSlotCount,
            details.prepared,
            details.reported,
            payoutDenominator[conditionId]
        );
    }

    function collateralBalance(IERC20 collateralToken) external view returns (uint256) {
        return collateralToken.balanceOf(address(this));
    }

    function getPayoutNumerators(bytes32 conditionId) external view returns (uint256[] memory numerators) {
        uint256 outcomeSlotCount = _details[conditionId].outcomeSlotCount;
        if (outcomeSlotCount == 0) {
            outcomeSlotCount = _outcomeSlotCounts[conditionId];
        }

        numerators = new uint256[](outcomeSlotCount);
        for (uint256 index; index < outcomeSlotCount; ++index) {
            numerators[index] = payoutNumerators[conditionId][index];
        }
    }

    function mintPosition(address account, uint256 positionId, uint256 amount) external {
        _mint(account, positionId, amount, "");
    }

    function burnPosition(address account, uint256 positionId, uint256 amount) external {
        _burn(account, positionId, amount);
    }
}
