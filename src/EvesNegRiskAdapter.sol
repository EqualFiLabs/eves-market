// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC1155} from "../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";
import {ERC1155Holder} from "../lib/openzeppelin-contracts/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import {IGnosisConditionalTokens} from "./interfaces/IGnosisConditionalTokens.sol";
import {IEvesNegRiskAdapter} from "./interfaces/IEvesNegRiskAdapter.sol";
import {EvesNegRiskWrappedCollateral} from "./tokens/EvesNegRiskWrappedCollateral.sol";

/// @notice CTF adapter for mutually exclusive binary markets.
/// @dev The conversion and wrapped-collateral accounting model is adapted from Polymarket's
///      MIT-licensed neg-risk-ctf-adapter at commit
///      f78b35b0863b4308a431ca307d06f49b2ea65e78. Eves adds atomic event preparation,
///      horizontal split/merge, explicit invalid-event payouts, and a fixed oracle.
contract EvesNegRiskAdapter is IEvesNegRiskAdapter, ERC1155Holder, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant INVALID_OUTCOME = type(uint8).max;
    uint256 public constant MIN_OUTCOME_COUNT = 2;
    uint256 public constant MAX_OUTCOME_COUNT = 16;
    address public constant RETIRED_POSITION_ADDRESS =
        address(bytes20(bytes32(keccak256("EVES_NEGRISK_RETIRED_POSITION"))));

    bytes32 private constant EVENT_DOMAIN = keccak256("EVES_CTF_NEGRISK_EVENT");

    error OnlyOracle();
    error ZeroAddress();
    error ZeroAmount();
    error InvalidOutcomeCount(uint256 count);
    error InvalidOutcome(uint256 outcome);
    error InvalidIndexSet(uint256 indexSet);
    error EventAlreadyPrepared(bytes32 eventId);
    error EventNotPrepared(bytes32 eventId);
    error EventAlreadyResolved(bytes32 eventId);
    error UnknownCondition(bytes32 conditionId);
    error ArrayLengthMismatch(uint256 expected, uint256 actual);
    error NonExactCollateralTransfer(uint256 expected, uint256 actual);

    event NegRiskEventPrepared(bytes32 indexed eventId, bytes32 indexed eventKey, uint256 outcomeCount);
    event NegRiskConditionPrepared(
        bytes32 indexed eventId, uint256 indexed outcome, bytes32 indexed questionId, bytes32 conditionId
    );
    event NegRiskEventResolved(bytes32 indexed eventId, uint256 indexed outcome, bool invalid);
    event NegRiskEventSplit(address indexed account, bytes32 indexed eventId, address indexed receiver, uint256 amount);
    event NegRiskEventMerged(
        address indexed account, bytes32 indexed eventId, address indexed receiver, uint256 amount
    );
    event NegRiskPositionsConverted(
        address indexed account, bytes32 indexed eventId, uint256 indexed indexSet, address receiver, uint256 amount
    );
    event NegRiskPositionSplit(address indexed account, bytes32 indexed conditionId, uint256 amount);
    event NegRiskPositionsMerged(address indexed account, bytes32 indexed conditionId, uint256 amount);
    event NegRiskPositionsRedeemed(
        address indexed account, bytes32 indexed conditionId, address indexed receiver, uint256 payout
    );

    struct EventData {
        uint16 outcomeCount;
        uint16 resolvedConditionCount;
        uint16 winningOutcome;
        bool prepared;
        bool resolved;
        bool invalid;
    }

    IGnosisConditionalTokens public immutable ctf;
    IERC1155 public immutable ctfPositions;
    IERC20 public immutable collateral;
    EvesNegRiskWrappedCollateral public immutable wrapped;
    address public immutable override oracle;

    mapping(bytes32 eventId => EventData) private events;
    mapping(bytes32 conditionId => bytes32 eventId) public eventByCondition;

    modifier onlyOracle() {
        if (msg.sender != oracle) revert OnlyOracle();
        _;
    }

    constructor(address conditionalTokens_, address collateralToken_, address oracle_) {
        if (conditionalTokens_ == address(0) || collateralToken_ == address(0) || oracle_ == address(0)) {
            revert ZeroAddress();
        }
        ctf = IGnosisConditionalTokens(conditionalTokens_);
        ctfPositions = IERC1155(conditionalTokens_);
        collateral = IERC20(collateralToken_);
        oracle = oracle_;
        wrapped = new EvesNegRiskWrappedCollateral(collateralToken_, IERC20Metadata(collateralToken_).decimals());
    }

    function conditionalTokens() external view override returns (address) {
        return address(ctf);
    }

    function collateralToken() external view override returns (address) {
        return address(collateral);
    }

    function wrappedCollateral() external view override returns (address) {
        return address(wrapped);
    }

    function prepareEvent(bytes32 eventKey, uint256 outcomeCount)
        external
        override
        onlyOracle
        returns (bytes32 eventId)
    {
        if (outcomeCount < MIN_OUTCOME_COUNT || outcomeCount > MAX_OUTCOME_COUNT) {
            revert InvalidOutcomeCount(outcomeCount);
        }
        eventId = keccak256(abi.encode(EVENT_DOMAIN, address(this), eventKey, outcomeCount));
        if (events[eventId].prepared) revert EventAlreadyPrepared(eventId);

        events[eventId] = EventData({
            outcomeCount: uint16(outcomeCount),
            resolvedConditionCount: 0,
            winningOutcome: 0,
            prepared: true,
            resolved: false,
            invalid: false
        });

        emit NegRiskEventPrepared(eventId, eventKey, outcomeCount);
        for (uint256 outcome; outcome < outcomeCount; ++outcome) {
            bytes32 questionId = questionIdFor(eventId, outcome);
            bytes32 conditionId = _conditionId(questionId);
            eventByCondition[conditionId] = eventId;
            ctf.prepareCondition(address(this), questionId, 2);
            emit NegRiskConditionPrepared(eventId, outcome, questionId, conditionId);
        }
    }

    function resolveEvent(bytes32 eventId, uint256 outcome) external override onlyOracle {
        EventData storage eventData = _requireOpenEvent(eventId);
        uint256 outcomeCount = eventData.outcomeCount;
        bool invalid = outcome == INVALID_OUTCOME;
        if (!invalid && outcome >= outcomeCount) revert InvalidOutcome(outcome);

        for (uint256 index; index < outcomeCount; ++index) {
            uint256[] memory payouts = new uint256[](2);
            if (invalid) {
                payouts[0] = 1;
                payouts[1] = outcomeCount - 1;
            } else if (index == outcome) {
                payouts[0] = 1;
            } else {
                payouts[1] = 1;
            }
            ctf.reportPayouts(questionIdFor(eventId, index), payouts);
        }

        eventData.resolvedConditionCount = uint16(outcomeCount);
        eventData.winningOutcome = invalid ? 0 : uint16(outcome);
        eventData.resolved = true;
        eventData.invalid = invalid;
        emit NegRiskEventResolved(eventId, outcome, invalid);
    }

    function splitEvent(bytes32 eventId, uint256 amount, address receiver) external override nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();
        EventData storage eventData = _requireOpenEvent(eventId);
        uint256 outcomeCount = eventData.outcomeCount;

        _pullCollateralExact(msg.sender, amount);
        _wrap(amount);
        if (outcomeCount > 1) wrapped.mint((outcomeCount - 1) * amount);

        uint256[] memory yesPositionIds = new uint256[](outcomeCount);
        uint256[] memory noPositionIds = new uint256[](outcomeCount);
        uint256[] memory amounts = _filledArray(outcomeCount, amount);
        for (uint256 outcome; outcome < outcomeCount; ++outcome) {
            bytes32 conditionId = conditionIdFor(eventId, outcome);
            _splitHeldCollateral(conditionId, amount);
            yesPositionIds[outcome] = _positionId(conditionId, true);
            noPositionIds[outcome] = _positionId(conditionId, false);
        }

        ctfPositions.safeBatchTransferFrom(address(this), receiver, yesPositionIds, amounts, "");
        ctfPositions.safeBatchTransferFrom(address(this), RETIRED_POSITION_ADDRESS, noPositionIds, amounts, "");
        emit NegRiskEventSplit(msg.sender, eventId, receiver, amount);
    }

    function mergeEvent(bytes32 eventId, uint256 amount, address receiver) external override nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();
        EventData storage eventData = _requireEvent(eventId);
        uint256 outcomeCount = eventData.outcomeCount;
        uint256[] memory yesPositionIds = new uint256[](outcomeCount);
        for (uint256 outcome; outcome < outcomeCount; ++outcome) {
            yesPositionIds[outcome] = positionIdFor(eventId, outcome, true);
        }
        ctfPositions.safeBatchTransferFrom(
            msg.sender, RETIRED_POSITION_ADDRESS, yesPositionIds, _filledArray(outcomeCount, amount), ""
        );
        wrapped.release(receiver, amount);
        emit NegRiskEventMerged(msg.sender, eventId, receiver, amount);
    }

    function convertPositions(bytes32 eventId, uint256 indexSet, uint256 amount, address receiver)
        external
        override
        nonReentrant
    {
        if (amount == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();
        EventData storage eventData = _requireOpenEvent(eventId);
        uint256 outcomeCount = eventData.outcomeCount;
        if (indexSet == 0 || indexSet >> outcomeCount != 0) revert InvalidIndexSet(indexSet);

        uint256 noCount;
        for (uint256 outcome; outcome < outcomeCount; ++outcome) {
            if (indexSet & (uint256(1) << outcome) != 0) ++noCount;
        }
        uint256 yesCount = outcomeCount - noCount;
        uint256[] memory inputNoIds = new uint256[](noCount);
        uint256[] memory outputYesIds = new uint256[](yesCount);
        uint256[] memory retiredNoIds = new uint256[](yesCount);

        if (yesCount != 0) wrapped.mint(yesCount * amount);
        uint256 noCursor;
        uint256 yesCursor;
        for (uint256 outcome; outcome < outcomeCount; ++outcome) {
            bytes32 conditionId = conditionIdFor(eventId, outcome);
            if (indexSet & (uint256(1) << outcome) != 0) {
                inputNoIds[noCursor++] = _positionId(conditionId, false);
            } else {
                _splitHeldCollateral(conditionId, amount);
                outputYesIds[yesCursor] = _positionId(conditionId, true);
                retiredNoIds[yesCursor] = _positionId(conditionId, false);
                ++yesCursor;
            }
        }

        ctfPositions.safeBatchTransferFrom(
            msg.sender, RETIRED_POSITION_ADDRESS, inputNoIds, _filledArray(noCount, amount), ""
        );
        if (yesCount != 0) {
            ctfPositions.safeBatchTransferFrom(
                address(this), RETIRED_POSITION_ADDRESS, retiredNoIds, _filledArray(yesCount, amount), ""
            );
            ctfPositions.safeBatchTransferFrom(
                address(this), receiver, outputYesIds, _filledArray(yesCount, amount), ""
            );
        }
        if (noCount > 1) wrapped.release(receiver, (noCount - 1) * amount);

        emit NegRiskPositionsConverted(msg.sender, eventId, indexSet, receiver, amount);
    }

    function splitPosition(bytes32 conditionId, uint256 amount) external override nonReentrant {
        if (amount == 0) revert ZeroAmount();
        _requireCondition(conditionId);
        _pullCollateralExact(msg.sender, amount);
        _wrap(amount);
        _splitHeldCollateral(conditionId, amount);
        uint256[] memory positionIds = _positionPair(conditionId);
        ctfPositions.safeBatchTransferFrom(address(this), msg.sender, positionIds, _filledArray(2, amount), "");
        emit NegRiskPositionSplit(msg.sender, conditionId, amount);
    }

    function mergePositions(bytes32 conditionId, uint256 amount) external override nonReentrant {
        if (amount == 0) revert ZeroAmount();
        _requireCondition(conditionId);
        uint256[] memory positionIds = _positionPair(conditionId);
        ctfPositions.safeBatchTransferFrom(msg.sender, address(this), positionIds, _filledArray(2, amount), "");
        ctf.mergePositions(IERC20(address(wrapped)), bytes32(0), conditionId, _binaryPartition(), amount);
        wrapped.unwrap(msg.sender, amount);
        emit NegRiskPositionsMerged(msg.sender, conditionId, amount);
    }

    function redeemPositions(bytes32 conditionId, uint256[] calldata amounts, address receiver)
        external
        override
        nonReentrant
        returns (uint256 payout)
    {
        if (receiver == address(0)) revert ZeroAddress();
        _requireCondition(conditionId);
        if (amounts.length != 2) revert ArrayLengthMismatch(2, amounts.length);
        uint256[] memory positionIds = _positionPair(conditionId);
        ctfPositions.safeBatchTransferFrom(msg.sender, address(this), positionIds, amounts, "");

        uint256 beforeBalance = wrapped.balanceOf(address(this));
        ctf.redeemPositions(IERC20(address(wrapped)), bytes32(0), conditionId, _binaryPartition());
        payout = wrapped.balanceOf(address(this)) - beforeBalance;
        if (payout != 0) wrapped.unwrap(receiver, payout);
        emit NegRiskPositionsRedeemed(msg.sender, conditionId, receiver, payout);
    }

    function getEvent(bytes32 eventId) external view override returns (EventView memory eventView) {
        EventData storage eventData = _requireEvent(eventId);
        eventView = EventView({
            outcomeCount: eventData.outcomeCount,
            resolvedConditionCount: eventData.resolvedConditionCount,
            winningOutcome: eventData.winningOutcome,
            prepared: eventData.prepared,
            resolved: eventData.resolved,
            invalid: eventData.invalid
        });
    }

    function questionIdFor(bytes32 eventId, uint256 outcome) public pure override returns (bytes32 questionId) {
        questionId = keccak256(abi.encode(eventId, outcome));
    }

    function conditionIdFor(bytes32 eventId, uint256 outcome) public view override returns (bytes32 conditionId) {
        EventData storage eventData = _requireEvent(eventId);
        if (outcome >= eventData.outcomeCount) revert InvalidOutcome(outcome);
        conditionId = _conditionId(questionIdFor(eventId, outcome));
    }

    function positionIdFor(bytes32 eventId, uint256 outcome, bool yes)
        public
        view
        override
        returns (uint256 positionId)
    {
        positionId = _positionId(conditionIdFor(eventId, outcome), yes);
    }

    function _conditionId(bytes32 questionId) private view returns (bytes32) {
        return ctf.getConditionId(address(this), questionId, 2);
    }

    function _positionId(bytes32 conditionId, bool yes) private view returns (uint256) {
        bytes32 collectionId = ctf.getCollectionId(bytes32(0), conditionId, yes ? 1 : 2);
        return ctf.getPositionId(IERC20(address(wrapped)), collectionId);
    }

    function _positionPair(bytes32 conditionId) private view returns (uint256[] memory positionIds) {
        positionIds = new uint256[](2);
        positionIds[0] = _positionId(conditionId, true);
        positionIds[1] = _positionId(conditionId, false);
    }

    function _wrap(uint256 amount) private {
        collateral.forceApprove(address(wrapped), amount);
        wrapped.wrap(address(this), amount);
        collateral.forceApprove(address(wrapped), 0);
    }

    function _pullCollateralExact(address from, uint256 amount) private {
        uint256 balanceBefore = collateral.balanceOf(address(this));
        collateral.safeTransferFrom(from, address(this), amount);
        uint256 received = collateral.balanceOf(address(this)) - balanceBefore;
        if (received != amount) revert NonExactCollateralTransfer(amount, received);
    }

    function _splitHeldCollateral(bytes32 conditionId, uint256 amount) private {
        IERC20(address(wrapped)).forceApprove(address(ctf), amount);
        ctf.splitPosition(IERC20(address(wrapped)), bytes32(0), conditionId, _binaryPartition(), amount);
        IERC20(address(wrapped)).forceApprove(address(ctf), 0);
    }

    function _filledArray(uint256 length, uint256 value) private pure returns (uint256[] memory values) {
        values = new uint256[](length);
        for (uint256 index; index < length; ++index) {
            values[index] = value;
        }
    }

    function _binaryPartition() private pure returns (uint256[] memory partition) {
        partition = new uint256[](2);
        partition[0] = 1;
        partition[1] = 2;
    }

    function _requireEvent(bytes32 eventId) private view returns (EventData storage eventData) {
        eventData = events[eventId];
        if (!eventData.prepared) revert EventNotPrepared(eventId);
    }

    function _requireOpenEvent(bytes32 eventId) private view returns (EventData storage eventData) {
        eventData = _requireEvent(eventId);
        if (eventData.resolved) revert EventAlreadyResolved(eventId);
    }

    function _requireCondition(bytes32 conditionId) private view {
        if (!events[eventByCondition[conditionId]].prepared) revert UnknownCondition(conditionId);
    }
}
