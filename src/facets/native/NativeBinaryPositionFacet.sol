// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {IEvesPositionManager} from "../../interfaces/IEvesPositionManager.sol";
import {INativeBinaryPositionFacet} from "../../interfaces/INativeBinaryPositionFacet.sol";
import {Errors} from "../../libraries/Errors.sol";
import {Events} from "../../libraries/Events.sol";
import {LibCLOBBook} from "../../libraries/LibCLOBBook.sol";
import {LibEveMarket} from "../../libraries/LibEveMarket.sol";
import {LibNativePosition} from "../../libraries/LibNativePosition.sol";
import {LibReentrancy} from "../../libraries/LibReentrancy.sol";

contract NativeBinaryPositionFacet is INativeBinaryPositionFacet {
    using SafeERC20 for IERC20;

    modifier nonReentrant() {
        LibReentrancy.enter();
        _;
        LibReentrancy.exit();
    }

    function prepareNativeBinaryCondition(bytes32 marketId) external returns (BinaryPositionIds memory ids) {
        LibNativePosition.BinaryPositionIds memory prepared =
            LibNativePosition.prepareBinaryCondition(LibEveMarket.store(), marketId);
        ids = BinaryPositionIds({
            marketId: prepared.marketId,
            conditionId: prepared.conditionId,
            yesPositionId: prepared.yesPositionId,
            noPositionId: prepared.noPositionId
        });
    }

    function getNativeBinaryCondition(bytes32 marketId) external view returns (BinaryPositionIds memory ids) {
        LibNativePosition.BinaryPositionIds memory condition =
            LibNativePosition.requireBinaryCondition(LibEveMarket.store(), marketId);
        ids = BinaryPositionIds({
            marketId: condition.marketId,
            conditionId: condition.conditionId,
            yesPositionId: condition.yesPositionId,
            noPositionId: condition.noPositionId
        });
    }

    function splitNativeBinary(bytes32 marketId, uint128 amount, address receiver)
        external
        nonReentrant
        returns (uint256 yesPositionId, uint256 noPositionId)
    {
        if (amount == 0) {
            revert Errors.InvalidAmount(amount);
        }
        if (receiver == address(0)) {
            revert Errors.ZeroAddress();
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibNativePosition.BinaryPositionIds memory ids = LibNativePosition.prepareBinaryCondition(state, marketId);
        LibEveMarket.Market storage market = _requireTradingCLOBMarket(state, marketId);

        IERC20(market.collateralToken).safeTransferFrom(msg.sender, address(this), amount);
        IEvesPositionManager(state.config.evesPositionManager).mint(receiver, ids.yesPositionId, amount);
        IEvesPositionManager(state.config.evesPositionManager).mint(receiver, ids.noPositionId, amount);

        emit Events.NativeBinarySplit(marketId, msg.sender, receiver, amount);
        return (ids.yesPositionId, ids.noPositionId);
    }

    function mergeNativeBinary(bytes32 marketId, uint128 amount, address receiver)
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
        LibNativePosition.BinaryPositionIds memory ids = LibNativePosition.requireBinaryCondition(state, marketId);
        LibEveMarket.Market storage market = LibNativePosition.requireCLOBMarket(state, marketId);

        IEvesPositionManager positionManager = IEvesPositionManager(state.config.evesPositionManager);
        positionManager.burn(msg.sender, ids.yesPositionId, amount);
        positionManager.burn(msg.sender, ids.noPositionId, amount);

        IERC20(market.collateralToken).safeTransfer(receiver, amount);
        collateralOut = amount;

        emit Events.NativeBinaryMerged(marketId, msg.sender, receiver, amount);
    }

    function redeemNativeBinary(bytes32 marketId, uint8 outcomeIndex, uint128 amount, address receiver)
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
        if (!LibNativePosition.isBinaryOutcome(outcomeIndex)) {
            revert Errors.NativeOutcomeUnsupported(outcomeIndex);
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibNativePosition.BinaryPositionIds memory ids = LibNativePosition.requireBinaryCondition(state, marketId);
        LibEveMarket.Market storage market = _requireResolvedCLOBMarket(state, marketId);

        uint256 positionId = outcomeIndex == LibNativePosition.OUTCOME_YES ? ids.yesPositionId : ids.noPositionId;
        IEvesPositionManager(state.config.evesPositionManager).burn(msg.sender, positionId, amount);

        collateralOut = _binaryCollateralOut(market.outcome, outcomeIndex, amount);
        if (collateralOut != 0) {
            IERC20(market.collateralToken).safeTransfer(receiver, collateralOut);
        }

        emit Events.NativeBinaryRedeemed(marketId, msg.sender, outcomeIndex, amount, collateralOut);
    }

    function getNativeBinaryPayout(bytes32 conditionId, uint8 outcomeIndex)
        external
        view
        returns (bool resolved, uint256 payoutNumerator)
    {
        if (!LibNativePosition.isBinaryOutcome(outcomeIndex)) {
            revert Errors.NativeOutcomeUnsupported(outcomeIndex);
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.NativePositionMetadata storage metadata = state.nativePositionMetadata[
            LibNativePosition.positionIdFor(LibNativePosition.MODULE_BINARY, conditionId, outcomeIndex)
        ];
        if (!metadata.exists || metadata.conditionId != conditionId) {
            revert Errors.NativeConditionNotFound(conditionId);
        }

        LibEveMarket.Market storage market = state.markets[metadata.marketId];
        if (market.state != LibEveMarket.MarketState.Resolved) {
            return (false, 0);
        }

        resolved = true;
        payoutNumerator = _binaryPayoutNumerator(market.outcome, outcomeIndex);
    }

    function _requireTradingCLOBMarket(LibEveMarket.EveMarketStorage storage state, bytes32 marketId)
        internal
        view
        returns (LibEveMarket.Market storage market)
    {
        market = LibNativePosition.requireCLOBMarket(state, marketId);
        if (!LibCLOBBook.canExecuteMarketBook(market)) {
            revert Errors.MarketNotTrading(marketId);
        }
    }

    function _requireResolvedCLOBMarket(LibEveMarket.EveMarketStorage storage state, bytes32 marketId)
        internal
        view
        returns (LibEveMarket.Market storage market)
    {
        market = LibNativePosition.requireCLOBMarket(state, marketId);
        if (market.state != LibEveMarket.MarketState.Resolved) {
            revert Errors.MarketNotResolved(marketId);
        }
    }

    function _binaryCollateralOut(LibEveMarket.MarketOutcome outcome, uint8 outcomeIndex, uint128 amount)
        internal
        pure
        returns (uint128 collateralOut)
    {
        uint256 numerator = _binaryPayoutNumerator(outcome, outcomeIndex);
        collateralOut = uint128((uint256(amount) * numerator) / LibNativePosition.RESULT_DENOMINATOR);
    }

    function _binaryPayoutNumerator(LibEveMarket.MarketOutcome outcome, uint8 outcomeIndex)
        internal
        pure
        returns (uint256 payoutNumerator)
    {
        if (outcome == LibEveMarket.MarketOutcome.Yes) {
            return outcomeIndex == LibNativePosition.OUTCOME_YES ? LibNativePosition.RESULT_DENOMINATOR : 0;
        }
        if (outcome == LibEveMarket.MarketOutcome.No) {
            return outcomeIndex == LibNativePosition.OUTCOME_NO ? LibNativePosition.RESULT_DENOMINATOR : 0;
        }
        if (outcome == LibEveMarket.MarketOutcome.Invalid) {
            return LibNativePosition.RESULT_DENOMINATOR / 2;
        }
        return 0;
    }
}
