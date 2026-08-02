// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IComboBranchFacet} from "../../interfaces/IComboBranchFacet.sol";
import {IEvesPositionManager} from "../../interfaces/IEvesPositionManager.sol";
import {Errors} from "../../libraries/Errors.sol";
import {Events} from "../../libraries/Events.sol";
import {LibCombinatorialPosition} from "../../libraries/LibCombinatorialPosition.sol";
import {LibEveMarket} from "../../libraries/LibEveMarket.sol";
import {LibNativePosition} from "../../libraries/LibNativePosition.sol";
import {LibReentrancy} from "../../libraries/LibReentrancy.sol";

contract ComboBranchFacet is IComboBranchFacet {
    struct ChildBranchPositions {
        uint256 yesPositionId;
        uint256 noPositionId;
    }

    struct NoExtractionPositions {
        uint256 reducedNoPositionId;
        uint256 residualYesPositionId;
        uint256 extractedLeg;
    }

    modifier nonReentrant() {
        LibReentrancy.enter();
        _;
        LibReentrancy.exit();
    }

    function splitComboOnCondition(
        uint256 parentYesPositionId,
        bytes32 binaryConditionId,
        uint128 amount,
        address yesReceiver,
        address noReceiver
    ) external nonReentrant returns (uint256 childYesPositionId, uint256 childNoPositionId) {
        if (amount == 0) {
            revert Errors.InvalidAmount(amount);
        }
        if (yesReceiver == address(0) || noReceiver == address(0)) {
            revert Errors.ZeroAddress();
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.NativePositionMetadata storage parentMetadata =
            _requireParentYesPosition(state, parentYesPositionId);
        ChildBranchPositions memory children =
            _childBranchPositions(state, parentMetadata.conditionId, binaryConditionId, true);

        IEvesPositionManager positionManager = IEvesPositionManager(state.config.evesPositionManager);
        positionManager.burn(msg.sender, parentYesPositionId, amount);
        positionManager.mint(yesReceiver, children.yesPositionId, amount);
        positionManager.mint(noReceiver, children.noPositionId, amount);

        emit Events.ComboSplitOnCondition(
            msg.sender, parentYesPositionId, binaryConditionId, children.yesPositionId, children.noPositionId, amount
        );
        return (children.yesPositionId, children.noPositionId);
    }

    function mergeComboOnCondition(
        uint256 parentYesPositionId,
        bytes32 binaryConditionId,
        uint128 amount,
        address receiver
    ) external nonReentrant returns (uint256 parentPositionId) {
        if (amount == 0) {
            revert Errors.InvalidAmount(amount);
        }
        if (receiver == address(0)) {
            revert Errors.ZeroAddress();
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.NativePositionMetadata storage parentMetadata =
            _requireParentYesPosition(state, parentYesPositionId);
        ChildBranchPositions memory children =
            _childBranchPositions(state, parentMetadata.conditionId, binaryConditionId, false);

        IEvesPositionManager positionManager = IEvesPositionManager(state.config.evesPositionManager);
        positionManager.burn(msg.sender, children.yesPositionId, amount);
        positionManager.burn(msg.sender, children.noPositionId, amount);
        positionManager.mint(receiver, parentYesPositionId, amount);
        parentPositionId = parentYesPositionId;

        emit Events.ComboMergedOnCondition(
            msg.sender, parentYesPositionId, binaryConditionId, children.yesPositionId, children.noPositionId, amount
        );
    }

    function extractComboNoLeg(
        uint256 fullNoPositionId,
        uint256 legIndex,
        uint128 amount,
        address reducedNoReceiver,
        address residualYesReceiver
    ) external nonReentrant returns (uint256 reducedNoPositionId, uint256 residualYesPositionId) {
        if (amount == 0) {
            revert Errors.InvalidAmount(amount);
        }
        if (reducedNoReceiver == address(0) || residualYesReceiver == address(0)) {
            revert Errors.ZeroAddress();
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.NativePositionMetadata storage fullNoMetadata = _requireNoPosition(state, fullNoPositionId);
        NoExtractionPositions memory positions = _noExtractionPositions(state, fullNoMetadata.conditionId, legIndex);

        IEvesPositionManager positionManager = IEvesPositionManager(state.config.evesPositionManager);
        positionManager.burn(msg.sender, fullNoPositionId, amount);
        positionManager.mint(reducedNoReceiver, positions.reducedNoPositionId, amount);
        positionManager.mint(residualYesReceiver, positions.residualYesPositionId, amount);

        emit Events.ComboNoLegExtracted(
            msg.sender,
            fullNoPositionId,
            positions.extractedLeg,
            positions.reducedNoPositionId,
            positions.residualYesPositionId,
            amount
        );
        return (positions.reducedNoPositionId, positions.residualYesPositionId);
    }

    function injectComboNoLeg(uint256 fullNoPositionId, uint256 legIndex, uint128 amount, address receiver)
        external
        nonReentrant
        returns (uint256 fullNoPositionIdOut)
    {
        if (amount == 0) {
            revert Errors.InvalidAmount(amount);
        }
        if (receiver == address(0)) {
            revert Errors.ZeroAddress();
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.NativePositionMetadata storage fullNoMetadata = _requireNoPosition(state, fullNoPositionId);
        NoExtractionPositions memory positions = _noExtractionPositions(state, fullNoMetadata.conditionId, legIndex);

        IEvesPositionManager positionManager = IEvesPositionManager(state.config.evesPositionManager);
        positionManager.burn(msg.sender, positions.reducedNoPositionId, amount);
        positionManager.burn(msg.sender, positions.residualYesPositionId, amount);
        positionManager.mint(receiver, fullNoPositionId, amount);
        fullNoPositionIdOut = fullNoPositionId;

        emit Events.ComboNoLegInjected(
            msg.sender,
            fullNoPositionId,
            positions.extractedLeg,
            positions.reducedNoPositionId,
            positions.residualYesPositionId,
            amount
        );
    }

    function convertComboNoToYesBasket(uint256 fullNoPositionId, uint128 amount, address[] calldata receivers)
        external
        nonReentrant
        returns (uint256[] memory basketPositionIds)
    {
        if (amount == 0) {
            revert Errors.InvalidAmount(amount);
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.NativePositionMetadata storage fullNoMetadata = _requireNoPosition(state, fullNoPositionId);
        uint256[] memory fullLegs = LibCombinatorialPosition.copyStoredLegs(state, fullNoMetadata.conditionId);
        if (receivers.length != fullLegs.length) {
            revert Errors.ArrayLengthMismatch(fullLegs.length, receivers.length);
        }

        basketPositionIds = _yesBasketPositions(state, fullLegs);

        IEvesPositionManager positionManager = IEvesPositionManager(state.config.evesPositionManager);
        positionManager.burn(msg.sender, fullNoPositionId, amount);
        for (uint256 index; index < basketPositionIds.length; ++index) {
            if (receivers[index] == address(0)) {
                revert Errors.ZeroAddress();
            }
            positionManager.mint(receivers[index], basketPositionIds[index], amount);
        }

        emit Events.ComboNoConvertedToYesBasket(msg.sender, fullNoPositionId, amount, basketPositionIds);
    }

    function mergeComboNoFromYesBasket(uint256 fullNoPositionId, uint128 amount, address receiver)
        external
        nonReentrant
        returns (uint256 fullNoPositionIdOut)
    {
        if (amount == 0) {
            revert Errors.InvalidAmount(amount);
        }
        if (receiver == address(0)) {
            revert Errors.ZeroAddress();
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.NativePositionMetadata storage fullNoMetadata = _requireNoPosition(state, fullNoPositionId);
        uint256[] memory fullLegs = LibCombinatorialPosition.copyStoredLegs(state, fullNoMetadata.conditionId);
        uint256[] memory basketPositionIds = _yesBasketPositions(state, fullLegs);

        IEvesPositionManager positionManager = IEvesPositionManager(state.config.evesPositionManager);
        for (uint256 index; index < basketPositionIds.length; ++index) {
            positionManager.burn(msg.sender, basketPositionIds[index], amount);
        }
        positionManager.mint(receiver, fullNoPositionId, amount);
        fullNoPositionIdOut = fullNoPositionId;

        emit Events.ComboNoMergedFromYesBasket(msg.sender, fullNoPositionId, receiver, amount);
    }

    function _childBranchPositions(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 parentConditionId,
        bytes32 binaryConditionId,
        bool requireLiveBinary
    ) internal returns (ChildBranchPositions memory children) {
        uint256[] memory parentLegs = LibCombinatorialPosition.copyStoredLegs(state, parentConditionId);
        _requireConditionNotPresent(state, parentLegs, binaryConditionId);
        _requireCompatibleBinaryCondition(state, parentLegs, binaryConditionId, requireLiveBinary);

        uint256[] memory childYesLegs = LibCombinatorialPosition.insertLeg(
            parentLegs,
            LibNativePosition.positionIdFor(
                LibNativePosition.MODULE_BINARY, binaryConditionId, LibNativePosition.OUTCOME_YES
            )
        );
        uint256[] memory childNoLegs = LibCombinatorialPosition.insertLeg(
            parentLegs,
            LibNativePosition.positionIdFor(
                LibNativePosition.MODULE_BINARY, binaryConditionId, LibNativePosition.OUTCOME_NO
            )
        );

        (bytes32 childYesConditionId,,,) = _storeAndEmitCondition(state, childYesLegs);
        (bytes32 childNoConditionId,,,) = _storeAndEmitCondition(state, childNoLegs);
        children.yesPositionId = LibNativePosition.positionIdFor(
            LibNativePosition.MODULE_COMBINATORIAL, childYesConditionId, LibNativePosition.OUTCOME_YES
        );
        children.noPositionId = LibNativePosition.positionIdFor(
            LibNativePosition.MODULE_COMBINATORIAL, childNoConditionId, LibNativePosition.OUTCOME_YES
        );
    }

    function _requireParentYesPosition(LibEveMarket.EveMarketStorage storage state, uint256 parentYesPositionId)
        internal
        view
        returns (LibEveMarket.NativePositionMetadata storage metadata)
    {
        metadata = state.nativePositionMetadata[parentYesPositionId];
        if (!metadata.exists || metadata.moduleId != LibNativePosition.MODULE_COMBINATORIAL) {
            revert Errors.ComboUnsupportedPosition(parentYesPositionId);
        }
        if (metadata.outcomeIndex != LibNativePosition.OUTCOME_YES) {
            revert Errors.ComboParentYesRequired(parentYesPositionId);
        }
        if (!state.comboConditions[metadata.conditionId].exists) {
            revert Errors.ComboConditionNotFound(metadata.conditionId);
        }
    }

    function _requireNoPosition(LibEveMarket.EveMarketStorage storage state, uint256 fullNoPositionId)
        internal
        view
        returns (LibEveMarket.NativePositionMetadata storage metadata)
    {
        metadata = state.nativePositionMetadata[fullNoPositionId];
        if (!metadata.exists || metadata.moduleId != LibNativePosition.MODULE_COMBINATORIAL) {
            revert Errors.ComboUnsupportedPosition(fullNoPositionId);
        }
        if (metadata.outcomeIndex != LibNativePosition.OUTCOME_NO) {
            revert Errors.ComboNoPositionRequired(fullNoPositionId);
        }
        if (!state.comboConditions[metadata.conditionId].exists) {
            revert Errors.ComboConditionNotFound(metadata.conditionId);
        }
    }

    function _noExtractionPositions(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 fullConditionId,
        uint256 legIndex
    ) internal returns (NoExtractionPositions memory positions) {
        uint256[] memory fullLegs = LibCombinatorialPosition.copyStoredLegs(state, fullConditionId);
        if (fullLegs.length < 2) {
            revert Errors.ComboLegCountInvalid(fullLegs.length);
        }
        if (legIndex >= fullLegs.length) {
            revert Errors.ComboLegIndexOutOfRange(legIndex, fullLegs.length);
        }

        positions.extractedLeg = fullLegs[legIndex];
        uint256[] memory reducedLegs = LibCombinatorialPosition.removeLeg(fullLegs, legIndex);
        uint256[] memory residualLegs = LibCombinatorialPosition.insertLeg(
            reducedLegs, LibCombinatorialPosition.flipBinaryLeg(state, positions.extractedLeg)
        );

        (bytes32 reducedConditionId,,,) = _storeAndEmitCondition(state, reducedLegs);
        (bytes32 residualConditionId,,,) = _storeAndEmitCondition(state, residualLegs);
        positions.reducedNoPositionId = LibNativePosition.positionIdFor(
            LibNativePosition.MODULE_COMBINATORIAL, reducedConditionId, LibNativePosition.OUTCOME_NO
        );
        positions.residualYesPositionId = LibNativePosition.positionIdFor(
            LibNativePosition.MODULE_COMBINATORIAL, residualConditionId, LibNativePosition.OUTCOME_YES
        );
    }

    function _yesBasketPositions(LibEveMarket.EveMarketStorage storage state, uint256[] memory fullLegs)
        internal
        returns (uint256[] memory basketPositionIds)
    {
        basketPositionIds = new uint256[](fullLegs.length);
        for (uint256 terminalIndex; terminalIndex < fullLegs.length; ++terminalIndex) {
            uint256[] memory basketLegs = new uint256[](0);
            for (uint256 legIndex; legIndex <= terminalIndex; ++legIndex) {
                uint256 leg = fullLegs[legIndex];
                if (legIndex == terminalIndex) {
                    leg = LibCombinatorialPosition.flipBinaryLeg(state, leg);
                }
                basketLegs = LibCombinatorialPosition.insertLeg(basketLegs, leg);
            }

            (bytes32 basketConditionId,,,) = _storeAndEmitCondition(state, basketLegs);
            basketPositionIds[terminalIndex] = LibNativePosition.positionIdFor(
                LibNativePosition.MODULE_COMBINATORIAL, basketConditionId, LibNativePosition.OUTCOME_YES
            );
        }
    }

    function _requireConditionNotPresent(
        LibEveMarket.EveMarketStorage storage state,
        uint256[] memory legs,
        bytes32 binaryConditionId
    ) internal view {
        for (uint256 index; index < legs.length; ++index) {
            LibEveMarket.NativePositionMetadata storage legMetadata = state.nativePositionMetadata[legs[index]];
            if (legMetadata.conditionId == binaryConditionId) {
                revert Errors.ComboConditionAlreadyPresent(binaryConditionId);
            }
        }
    }

    function _requireCompatibleBinaryCondition(
        LibEveMarket.EveMarketStorage storage state,
        uint256[] memory parentLegs,
        bytes32 binaryConditionId,
        bool requireLiveBinary
    ) internal view {
        uint256 yesPositionId = LibNativePosition.positionIdFor(
            LibNativePosition.MODULE_BINARY, binaryConditionId, LibNativePosition.OUTCOME_YES
        );
        uint256 noPositionId = LibNativePosition.positionIdFor(
            LibNativePosition.MODULE_BINARY, binaryConditionId, LibNativePosition.OUTCOME_NO
        );

        LibEveMarket.NativePositionMetadata storage yesMetadata = state.nativePositionMetadata[yesPositionId];
        LibEveMarket.NativePositionMetadata storage noMetadata = state.nativePositionMetadata[noPositionId];
        if (
            !yesMetadata.exists || !noMetadata.exists || yesMetadata.moduleId != LibNativePosition.MODULE_BINARY
                || noMetadata.moduleId != LibNativePosition.MODULE_BINARY
        ) {
            revert Errors.NativeConditionNotFound(binaryConditionId);
        }

        LibEveMarket.Market storage market = state.markets[yesMetadata.marketId];
        if (market.marketId != yesMetadata.marketId) {
            revert Errors.MarketNotFound(yesMetadata.marketId);
        }

        LibEveMarket.NativePositionMetadata storage parentMetadata = state.nativePositionMetadata[parentLegs[0]];
        LibEveMarket.Market storage parentMarket = state.markets[parentMetadata.marketId];
        if (market.collateralToken != parentMarket.collateralToken) {
            revert Errors.ComboCollateralMismatch(parentMarket.collateralToken, market.collateralToken);
        }

        if (!requireLiveBinary) {
            return;
        }
        if (market.state == LibEveMarket.MarketState.Resolved) {
            revert Errors.ComboLegMarketResolved(yesMetadata.marketId);
        }
        if (
            market.state != LibEveMarket.MarketState.Trading || block.timestamp < market.tradingStartTime
                || block.timestamp >= market.expiryTime
        ) {
            revert Errors.ComboLegMarketNotStarted(yesMetadata.marketId);
        }
    }

    function _storeAndEmitCondition(LibEveMarket.EveMarketStorage storage state, uint256[] memory legs)
        internal
        returns (bytes32 conditionId, uint256 yesPositionId, uint256 noPositionId, bool created)
    {
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
