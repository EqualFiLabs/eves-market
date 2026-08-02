// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ERC1155} from "../../lib/openzeppelin-contracts/contracts/token/ERC1155/ERC1155.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {IGnosisConditionalTokens} from "../../src/interfaces/IGnosisConditionalTokens.sol";

contract PlainGnosisCTFMock is ERC1155, IGnosisConditionalTokens {
    using SafeERC20 for IERC20;

    struct PreparedPartition {
        uint256 fullIndexSet;
        uint256 freeIndexSet;
        uint256[] positionIds;
        uint256[] amounts;
    }

    mapping(bytes32 conditionId => uint256 outcomeSlotCount) internal _outcomeSlotCounts;
    mapping(bytes32 conditionId => uint256 denominator) public override payoutDenominator;
    mapping(bytes32 conditionId => mapping(uint256 slot => uint256 numerator)) public override payoutNumerators;

    constructor() ERC1155("") {}

    function prepareCondition(address oracle, bytes32 questionId, uint256 outcomeSlotCount) public virtual {
        require(outcomeSlotCount > 1, "there should be more than one outcome slot");
        bytes32 conditionId = getConditionId(oracle, questionId, outcomeSlotCount);
        require(_outcomeSlotCounts[conditionId] == 0, "condition already prepared");
        _outcomeSlotCounts[conditionId] = outcomeSlotCount;
    }

    function splitPosition(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata partition,
        uint256 amount
    ) external {
        PreparedPartition memory prepared =
            _preparePartition(collateralToken, parentCollectionId, conditionId, partition, amount);

        if (prepared.freeIndexSet == 0) {
            if (parentCollectionId == bytes32(0)) {
                collateralToken.safeTransferFrom(msg.sender, address(this), amount);
            } else {
                _burn(msg.sender, getPositionId(collateralToken, parentCollectionId), amount);
            }
        } else {
            _burn(
                msg.sender,
                getPositionId(
                    collateralToken,
                    getCollectionId(parentCollectionId, conditionId, prepared.fullIndexSet ^ prepared.freeIndexSet)
                ),
                amount
            );
        }

        _mintBatch(msg.sender, prepared.positionIds, prepared.amounts, "");
    }

    function mergePositions(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata partition,
        uint256 amount
    ) external {
        PreparedPartition memory prepared =
            _preparePartition(collateralToken, parentCollectionId, conditionId, partition, amount);

        _burnBatch(msg.sender, prepared.positionIds, prepared.amounts);

        if (prepared.freeIndexSet == 0) {
            if (parentCollectionId == bytes32(0)) {
                collateralToken.safeTransfer(msg.sender, amount);
            } else {
                _mint(msg.sender, getPositionId(collateralToken, parentCollectionId), amount, "");
            }
        } else {
            _mint(
                msg.sender,
                getPositionId(
                    collateralToken,
                    getCollectionId(parentCollectionId, conditionId, prepared.fullIndexSet ^ prepared.freeIndexSet)
                ),
                amount,
                ""
            );
        }
    }

    function redeemPositions(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata indexSets
    ) external {
        uint256 denominator = payoutDenominator[conditionId];
        require(denominator != 0, "result for condition not received yet");
        uint256 outcomeSlotCount = _outcomeSlotCounts[conditionId];
        require(outcomeSlotCount != 0, "condition not prepared yet");
        uint256 fullIndexSet = (uint256(1) << outcomeSlotCount) - 1;

        uint256 totalPayout;
        for (uint256 index; index < indexSets.length; ++index) {
            uint256 indexSet = indexSets[index];
            require(indexSet > 0 && indexSet < fullIndexSet, "got invalid index set");
            uint256 positionId = getPositionId(collateralToken, getCollectionId(parentCollectionId, conditionId, indexSet));
            uint256 balance = super.balanceOf(msg.sender, positionId);
            if (balance == 0) {
                continue;
            }
            _burn(msg.sender, positionId, balance);
            totalPayout += (balance * _payoutNumeratorForIndexSet(conditionId, outcomeSlotCount, indexSet)) / denominator;
        }

        if (totalPayout != 0) {
            if (parentCollectionId == bytes32(0)) {
                collateralToken.safeTransfer(msg.sender, totalPayout);
            } else {
                _mint(msg.sender, getPositionId(collateralToken, parentCollectionId), totalPayout, "");
            }
        }
    }

    function reportPayouts(bytes32 questionId, uint256[] calldata payouts) public virtual {
        uint256 outcomeSlotCount = payouts.length;
        bytes32 conditionId = getConditionId(msg.sender, questionId, outcomeSlotCount);
        require(_outcomeSlotCounts[conditionId] == outcomeSlotCount, "condition not prepared or found");
        require(payoutDenominator[conditionId] == 0, "payout denominator already set");

        uint256 denominator;
        for (uint256 index; index < outcomeSlotCount; ++index) {
            payoutNumerators[conditionId][index] = payouts[index];
            denominator += payouts[index];
        }
        require(denominator != 0, "payout is all zeroes");
        payoutDenominator[conditionId] = denominator;
    }

    function getOutcomeSlotCount(bytes32 conditionId) external view returns (uint256 outcomeSlotCount) {
        return _outcomeSlotCounts[conditionId];
    }

    function getPositionId(IERC20 collateralToken, bytes32 collectionId) public pure returns (uint256 positionId) {
        return uint256(keccak256(abi.encodePacked(collateralToken, collectionId)));
    }

    function getCollectionId(bytes32 parentCollectionId, bytes32 conditionId, uint256 indexSet)
        public
        pure
        returns (bytes32 collectionId)
    {
        return keccak256(abi.encodePacked(parentCollectionId, conditionId, indexSet));
    }

    function getConditionId(address oracle, bytes32 questionId, uint256 outcomeSlotCount)
        public
        pure
        returns (bytes32 conditionId)
    {
        return keccak256(abi.encodePacked(oracle, questionId, outcomeSlotCount));
    }

    function balanceOf(address account, uint256 positionId)
        public
        view
        override(ERC1155, IGnosisConditionalTokens)
        returns (uint256)
    {
        return super.balanceOf(account, positionId);
    }

    function setApprovalForAll(address operator, bool approved) public override(ERC1155, IGnosisConditionalTokens) {
        super.setApprovalForAll(operator, approved);
    }

    function isApprovedForAll(address account, address operator)
        public
        view
        override(ERC1155, IGnosisConditionalTokens)
        returns (bool approved)
    {
        return super.isApprovedForAll(account, operator);
    }

    function safeTransferFrom(address from, address to, uint256 positionId, uint256 amount, bytes memory data)
        public
        override(ERC1155, IGnosisConditionalTokens)
    {
        super.safeTransferFrom(from, to, positionId, amount, data);
    }

    function _preparePartition(
        IERC20 collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata partition,
        uint256 amount
    )
        internal
        view
        returns (PreparedPartition memory prepared)
    {
        require(partition.length > 1, "got empty or singleton partition");
        uint256 outcomeSlotCount = _outcomeSlotCounts[conditionId];
        require(outcomeSlotCount != 0, "condition not prepared yet");

        prepared.fullIndexSet = (uint256(1) << outcomeSlotCount) - 1;
        prepared.freeIndexSet = prepared.fullIndexSet;
        prepared.positionIds = new uint256[](partition.length);
        prepared.amounts = new uint256[](partition.length);
        for (uint256 index; index < partition.length; ++index) {
            uint256 indexSet = partition[index];
            require(indexSet > 0 && indexSet < prepared.fullIndexSet, "got invalid index set");
            require((indexSet & prepared.freeIndexSet) == indexSet, "partition not disjoint");
            prepared.freeIndexSet ^= indexSet;
            prepared.positionIds[index] =
                getPositionId(collateralToken, getCollectionId(parentCollectionId, conditionId, indexSet));
            prepared.amounts[index] = amount;
        }
    }

    function _payoutNumeratorForIndexSet(bytes32 conditionId, uint256 outcomeSlotCount, uint256 indexSet)
        internal
        view
        returns (uint256 numerator)
    {
        for (uint256 slot; slot < outcomeSlotCount; ++slot) {
            if ((indexSet & (uint256(1) << slot)) != 0) {
                numerator += payoutNumerators[conditionId][slot];
            }
        }
    }
}
