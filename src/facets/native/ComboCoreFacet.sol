// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC1155} from "../../../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";

import {IComboCoreFacet} from "../../interfaces/IComboCoreFacet.sol";
import {IEvesNegRiskAdapter} from "../../interfaces/IEvesNegRiskAdapter.sol";
import {IEvesCTFSettlementAdapter} from "../../interfaces/IEvesCTFSettlementAdapter.sol";
import {IEvesPositionManager} from "../../interfaces/IEvesPositionManager.sol";
import {IGnosisConditionalTokens} from "../../interfaces/IGnosisConditionalTokens.sol";
import {Errors} from "../../libraries/Errors.sol";
import {Events} from "../../libraries/Events.sol";
import {LibCombinatorialPosition} from "../../libraries/LibCombinatorialPosition.sol";
import {LibEveMarket} from "../../libraries/LibEveMarket.sol";
import {LibNativePosition} from "../../libraries/LibNativePosition.sol";
import {LibNativeCollateral} from "../../libraries/LibNativeCollateral.sol";
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

        if (condition.legCount == 1) {
            _splitSingleCTFLeg(state, conditionId, amount);
        } else {
            LibNativeCollateral.collectBacking(state, collateralToken, msg.sender, amount);
        }
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

        if (condition.legCount == 1) {
            _mergeSingleCTFLeg(state, conditionId, amount, receiver);
        } else {
            LibNativeCollateral.releaseBacking(state, collateralToken, receiver, amount);
        }
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
        if (!LibCombinatorialPosition.isSupportedLeg(state, underlyingPositionId, underlying)) {
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

        LibEveMarket.CTFPositionMetadata storage ctfMetadata = state.ctfPositionMetadata[underlyingPositionId];
        IERC1155(ctfMetadata.positionToken)
            .safeTransferFrom(msg.sender, address(this), underlyingPositionId, amount, "");
        state.ctfComboEscrow[underlyingPositionId] += amount;
        IEvesPositionManager positionManager = IEvesPositionManager(state.config.evesPositionManager);
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
            underlyingPositionId = LibCombinatorialPosition.flipLeg(state, underlyingPositionId);
        } else if (comboMetadata.outcomeIndex != LibNativePosition.OUTCOME_YES) {
            revert Errors.NativeOutcomeUnsupported(comboMetadata.outcomeIndex);
        }

        uint256 escrowed = state.ctfComboEscrow[underlyingPositionId];
        if (escrowed < amount) {
            revert Errors.ComboCTFEscrowInsufficient(underlyingPositionId, escrowed, amount);
        }
        LibEveMarket.CTFPositionMetadata storage ctfMetadata = state.ctfPositionMetadata[underlyingPositionId];
        IEvesPositionManager positionManager = IEvesPositionManager(state.config.evesPositionManager);
        positionManager.burn(msg.sender, comboPositionId, amount);
        state.ctfComboEscrow[underlyingPositionId] = escrowed - amount;
        IERC1155(ctfMetadata.positionToken).safeTransferFrom(address(this), receiver, underlyingPositionId, amount, "");

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
        LibCombinatorialPosition.validateCanonicalLiveLegs(state, canonicalLegs);
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

    function _splitSingleCTFLeg(LibEveMarket.EveMarketStorage storage state, bytes32 conditionId, uint128 amount)
        internal
    {
        uint256 leg = state.comboConditionLegs[conditionId][0];
        LibEveMarket.CTFPositionMetadata storage metadata = state.ctfPositionMetadata[leg];
        uint256 complement = metadata.complementPositionId;
        IERC20 collateral = IERC20(metadata.collateralToken);
        collateral.safeTransferFrom(msg.sender, address(this), amount);

        if (metadata.settlementAdapter == address(0)) {
            collateral.forceApprove(metadata.positionToken, amount);
            IGnosisConditionalTokens(metadata.positionToken)
                .splitPosition(collateral, bytes32(0), metadata.conditionId, _binaryPartition(), amount);
            collateral.forceApprove(metadata.positionToken, 0);
        } else if (metadata.settlementAdapter == state.negRiskAdapter) {
            collateral.forceApprove(metadata.settlementAdapter, amount);
            IEvesNegRiskAdapter(metadata.settlementAdapter).splitPosition(metadata.conditionId, amount);
            collateral.forceApprove(metadata.settlementAdapter, 0);
        } else {
            collateral.forceApprove(metadata.settlementAdapter, amount);
            IEvesCTFSettlementAdapter(metadata.settlementAdapter).splitPosition(metadata.conditionId, amount);
            collateral.forceApprove(metadata.settlementAdapter, 0);
        }

        state.ctfComboEscrow[leg] += amount;
        state.ctfComboEscrow[complement] += amount;
    }

    function _mergeSingleCTFLeg(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 conditionId,
        uint128 amount,
        address receiver
    ) internal {
        uint256 leg = state.comboConditionLegs[conditionId][0];
        LibEveMarket.CTFPositionMetadata storage metadata = state.ctfPositionMetadata[leg];
        uint256 complement = metadata.complementPositionId;
        uint256 legEscrow = state.ctfComboEscrow[leg];
        uint256 complementEscrow = state.ctfComboEscrow[complement];
        if (legEscrow < amount) revert Errors.ComboCTFEscrowInsufficient(leg, legEscrow, amount);
        if (complementEscrow < amount) {
            revert Errors.ComboCTFEscrowInsufficient(complement, complementEscrow, amount);
        }
        state.ctfComboEscrow[leg] = legEscrow - amount;
        state.ctfComboEscrow[complement] = complementEscrow - amount;

        if (metadata.settlementAdapter == address(0)) {
            IGnosisConditionalTokens(metadata.positionToken)
                .mergePositions(
                    IERC20(metadata.collateralToken), bytes32(0), metadata.conditionId, _binaryPartition(), amount
                );
        } else if (metadata.settlementAdapter == state.negRiskAdapter) {
            IERC1155(metadata.positionToken).setApprovalForAll(metadata.settlementAdapter, true);
            IEvesNegRiskAdapter(metadata.settlementAdapter).mergePositions(metadata.conditionId, amount);
            IERC1155(metadata.positionToken).setApprovalForAll(metadata.settlementAdapter, false);
        } else {
            IERC1155(metadata.positionToken).setApprovalForAll(metadata.settlementAdapter, true);
            IEvesCTFSettlementAdapter(metadata.settlementAdapter)
                .mergePositions(metadata.conditionId, amount, address(this));
            IERC1155(metadata.positionToken).setApprovalForAll(metadata.settlementAdapter, false);
        }
        IERC20(metadata.collateralToken).safeTransfer(receiver, amount);
    }

    function _binaryPartition() internal pure returns (uint256[] memory partition) {
        partition = new uint256[](2);
        partition[0] = 1;
        partition[1] = 2;
    }
}
