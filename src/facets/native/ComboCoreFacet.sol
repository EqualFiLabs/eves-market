// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {IComboCoreFacet} from "../../interfaces/IComboCoreFacet.sol";
import {IEvesPositionManager} from "../../interfaces/IEvesPositionManager.sol";
import {Errors} from "../../libraries/Errors.sol";
import {Events} from "../../libraries/Events.sol";
import {LibCombinatorialPosition} from "../../libraries/LibCombinatorialPosition.sol";
import {LibEveMarket} from "../../libraries/LibEveMarket.sol";
import {LibNativePosition} from "../../libraries/LibNativePosition.sol";
import {LibReentrancy} from "../../libraries/LibReentrancy.sol";
import {NativePositionTypes} from "../../types/NativePositionTypes.sol";

contract ComboCoreFacet is IComboCoreFacet {
    using SafeERC20 for IERC20;

    modifier nonReentrant() {
        LibReentrancy.enter();
        _;
        LibReentrancy.exit();
    }

    function prepareComboCondition(uint256[] calldata canonicalLegs)
        external
        returns (bytes32 conditionId, uint256 yesPositionId, uint256 noPositionId)
    {
        (conditionId, yesPositionId, noPositionId) = _prepareComboCondition(LibEveMarket.store(), canonicalLegs);
    }

    function splitCombo(bytes32 conditionId, uint128 amount, address yesReceiver, address noReceiver)
        external
        nonReentrant
        returns (uint256 yesPositionId, uint256 noPositionId)
    {
        if (amount == 0) {
            revert Errors.InvalidAmount(amount);
        }
        if (yesReceiver == address(0) || noReceiver == address(0)) {
            revert Errors.ZeroAddress();
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.ComboCondition storage condition =
            LibCombinatorialPosition.requireComboCondition(state, conditionId);
        address collateralToken = LibCombinatorialPosition.collateralTokenFor(state, conditionId);
        LibCombinatorialPosition.requireLiveConditionAndEarliestExpiry(state, conditionId);

        yesPositionId = LibNativePosition.positionIdFor(
            LibNativePosition.MODULE_COMBINATORIAL, conditionId, LibNativePosition.OUTCOME_YES
        );
        noPositionId = LibNativePosition.positionIdFor(
            LibNativePosition.MODULE_COMBINATORIAL, conditionId, LibNativePosition.OUTCOME_NO
        );

        IERC20(collateralToken).safeTransferFrom(msg.sender, address(this), amount);
        IEvesPositionManager positionManager = IEvesPositionManager(state.config.evesPositionManager);
        positionManager.mint(yesReceiver, yesPositionId, amount);
        positionManager.mint(noReceiver, noPositionId, amount);

        emit Events.ComboSplit(condition.conditionId, msg.sender, amount, yesReceiver, noReceiver);
    }

    function mergeCombo(bytes32 conditionId, uint128 amount, address receiver)
        external
        nonReentrant
        returns (uint128 collateralOut)
    {
        if (amount == 0) {
            revert Errors.InvalidAmount(amount);
        }
        if (receiver == address(0)) {
            revert Errors.ZeroAddress();
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.ComboCondition storage condition =
            LibCombinatorialPosition.requireComboCondition(state, conditionId);
        address collateralToken = LibCombinatorialPosition.collateralTokenFor(state, conditionId);

        uint256 yesPositionId = LibNativePosition.positionIdFor(
            LibNativePosition.MODULE_COMBINATORIAL, conditionId, LibNativePosition.OUTCOME_YES
        );
        uint256 noPositionId = LibNativePosition.positionIdFor(
            LibNativePosition.MODULE_COMBINATORIAL, conditionId, LibNativePosition.OUTCOME_NO
        );

        IEvesPositionManager positionManager = IEvesPositionManager(state.config.evesPositionManager);
        positionManager.burn(msg.sender, yesPositionId, amount);
        positionManager.burn(msg.sender, noPositionId, amount);

        IERC20(collateralToken).safeTransfer(receiver, amount);
        collateralOut = amount;

        emit Events.ComboMerged(condition.conditionId, msg.sender, receiver, amount);
    }

    function wrapCombo(uint256 underlyingPositionId, uint128 amount, address receiver)
        external
        nonReentrant
        returns (uint256 comboPositionId)
    {
        if (amount == 0) {
            revert Errors.InvalidAmount(amount);
        }
        if (receiver == address(0)) {
            revert Errors.ZeroAddress();
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.NativePositionMetadata storage underlying = state.nativePositionMetadata[underlyingPositionId];
        if (!underlying.exists || underlying.moduleId != LibNativePosition.MODULE_BINARY) {
            revert Errors.ComboUnsupportedPosition(underlyingPositionId);
        }

        uint256[] memory legs = new uint256[](1);
        legs[0] = underlyingPositionId;
        (bytes32 conditionId, uint256 yesPositionId, uint256 noPositionId, bool created) =
            LibCombinatorialPosition.storeComboConditionFromMemory(state, legs);
        if (created) {
            LibEveMarket.ComboCondition storage condition = state.comboConditions[conditionId];
            emit Events.ComboConditionPrepared(
                conditionId, condition.legsHash, condition.legCount, yesPositionId, noPositionId, legs
            );
        }
        comboPositionId = LibNativePosition.positionIdFor(
            LibNativePosition.MODULE_COMBINATORIAL, conditionId, LibNativePosition.OUTCOME_YES
        );

        IEvesPositionManager positionManager = IEvesPositionManager(state.config.evesPositionManager);
        positionManager.burn(msg.sender, underlyingPositionId, amount);
        positionManager.mint(receiver, comboPositionId, amount);

        emit Events.ComboWrapped(msg.sender, underlyingPositionId, comboPositionId, amount);
    }

    function unwrapCombo(uint256 comboPositionId, uint128 amount, address receiver)
        external
        nonReentrant
        returns (uint256 underlyingPositionId)
    {
        if (amount == 0) {
            revert Errors.InvalidAmount(amount);
        }
        if (receiver == address(0)) {
            revert Errors.ZeroAddress();
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.NativePositionMetadata storage comboMetadata = state.nativePositionMetadata[comboPositionId];
        if (!comboMetadata.exists || comboMetadata.moduleId != LibNativePosition.MODULE_COMBINATORIAL) {
            revert Errors.ComboUnsupportedPosition(comboPositionId);
        }

        uint256[] storage legs = state.comboConditionLegs[comboMetadata.conditionId];
        if (legs.length != 1) {
            revert Errors.ComboSingleLegRequired(legs.length);
        }

        underlyingPositionId = legs[0];
        if (comboMetadata.outcomeIndex == LibNativePosition.OUTCOME_NO) {
            underlyingPositionId = LibCombinatorialPosition.flipBinaryLeg(state, underlyingPositionId);
        } else if (comboMetadata.outcomeIndex != LibNativePosition.OUTCOME_YES) {
            revert Errors.NativeOutcomeUnsupported(comboMetadata.outcomeIndex);
        }

        IEvesPositionManager positionManager = IEvesPositionManager(state.config.evesPositionManager);
        positionManager.burn(msg.sender, comboPositionId, amount);
        positionManager.mint(receiver, underlyingPositionId, amount);

        emit Events.ComboUnwrapped(msg.sender, comboPositionId, underlyingPositionId, amount);
    }

    function getComboCondition(bytes32 conditionId)
        external
        view
        returns (NativePositionTypes.ComboConditionView memory conditionView)
    {
        LibEveMarket.ComboCondition storage condition =
            LibCombinatorialPosition.requireComboCondition(LibEveMarket.store(), conditionId);
        conditionView = NativePositionTypes.ComboConditionView({
            conditionId: condition.conditionId,
            legsHash: condition.legsHash,
            legCount: condition.legCount,
            preparedAt: condition.preparedAt,
            exists: condition.exists
        });
    }

    function getComboLegs(bytes32 conditionId) external view returns (uint256[] memory legs) {
        LibCombinatorialPosition.requireComboCondition(LibEveMarket.store(), conditionId);
        uint256[] storage storedLegs = LibEveMarket.store().comboConditionLegs[conditionId];
        legs = new uint256[](storedLegs.length);
        for (uint256 index; index < storedLegs.length; ++index) {
            legs[index] = storedLegs[index];
        }
    }

    function _prepareComboCondition(LibEveMarket.EveMarketStorage storage state, uint256[] calldata canonicalLegs)
        internal
        returns (bytes32 conditionId, uint256 yesPositionId, uint256 noPositionId)
    {
        LibCombinatorialPosition.validateCanonicalLiveBinaryLegs(state, canonicalLegs);
        uint256[] memory legs = LibCombinatorialPosition.copyLegs(canonicalLegs);
        bool created;
        (conditionId, yesPositionId, noPositionId, created) =
            LibCombinatorialPosition.storeComboConditionFromMemory(state, legs);
        if (created) {
            LibEveMarket.ComboCondition storage condition = state.comboConditions[conditionId];
            emit Events.ComboConditionPrepared(
                conditionId, condition.legsHash, condition.legCount, yesPositionId, noPositionId, legs
            );
        }
    }
}
