// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "../../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

import {IComboSettlementFacet} from "../../interfaces/IComboSettlementFacet.sol";
import {IEvesPositionManager} from "../../interfaces/IEvesPositionManager.sol";
import {Errors} from "../../libraries/Errors.sol";
import {Events} from "../../libraries/Events.sol";
import {LibCombinatorialPosition} from "../../libraries/LibCombinatorialPosition.sol";
import {LibEveMarket} from "../../libraries/LibEveMarket.sol";
import {LibNativePosition} from "../../libraries/LibNativePosition.sol";
import {LibReentrancy} from "../../libraries/LibReentrancy.sol";
import {NativePositionTypes} from "../../types/NativePositionTypes.sol";

contract ComboSettlementFacet is IComboSettlementFacet {
    using SafeERC20 for IERC20;

    modifier nonReentrant() {
        LibReentrancy.enter();
        _;
        LibReentrancy.exit();
    }

    function compressCombo(uint256 positionId, uint128 amount, address receiver)
        external
        nonReentrant
        returns (NativePositionTypes.CompressionResult memory result)
    {
        if (amount == 0) {
            revert Errors.InvalidAmount(amount);
        }
        if (receiver == address(0)) {
            revert Errors.ZeroAddress();
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.NativePositionMetadata storage metadata =
            LibCombinatorialPosition.requireComboPosition(state, positionId);
        address collateralToken = LibCombinatorialPosition.collateralTokenFor(state, metadata.conditionId);

        LibCombinatorialPosition.CompressionPlan memory plan =
            LibCombinatorialPosition.previewCompressionPlan(state, metadata, amount);
        result = LibCombinatorialPosition.materializeReducedPosition(state, plan, metadata.outcomeIndex);

        IEvesPositionManager positionManager = IEvesPositionManager(state.config.evesPositionManager);
        positionManager.burn(msg.sender, positionId, amount);
        if (result.newPositionId != 0 && result.positionAmount != 0) {
            positionManager.mint(receiver, result.newPositionId, result.positionAmount);
        }
        if (result.collateralOut != 0) {
            IERC20(collateralToken).safeTransfer(receiver, result.collateralOut);
        }

        emit Events.ComboCompressed(
            msg.sender, positionId, result.newPositionId, amount, result.positionAmount, result.collateralOut
        );
    }

    function redeemCombo(uint256 positionId, uint128 amount, address receiver)
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
        LibEveMarket.NativePositionMetadata storage metadata =
            LibCombinatorialPosition.requireComboPosition(state, positionId);
        address collateralToken = LibCombinatorialPosition.collateralTokenFor(state, metadata.conditionId);

        bool redeemable;
        (redeemable, collateralOut) = _comboPayout(state, metadata, amount);
        if (!redeemable) {
            revert Errors.ComboPositionNotRedeemable(positionId);
        }

        IEvesPositionManager(state.config.evesPositionManager).burn(msg.sender, positionId, amount);
        if (collateralOut != 0) {
            IERC20(collateralToken).safeTransfer(receiver, collateralOut);
        }

        emit Events.ComboRedeemed(msg.sender, positionId, amount, collateralOut);
    }

    function getComboPayout(uint256 positionId, uint128 amount)
        external
        view
        returns (bool redeemable, uint128 collateralOut)
    {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.NativePositionMetadata storage metadata =
            LibCombinatorialPosition.requireComboPosition(state, positionId);
        return _comboPayout(state, metadata, amount);
    }

    function _comboPayout(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.NativePositionMetadata storage metadata,
        uint128 amount
    ) internal view returns (bool redeemable, uint128 collateralOut) {
        uint256[] storage legs = state.comboConditionLegs[metadata.conditionId];
        uint256 payoutFactor = LibNativePosition.PAYOUT_FACTOR_DENOMINATOR;
        bool hasUnresolved;

        for (uint256 index; index < legs.length; ++index) {
            (bool resolved, uint256 numerator) = LibCombinatorialPosition.legPayout(state, legs[index]);
            if (!resolved) {
                hasUnresolved = true;
                continue;
            }
            if (numerator == 0) {
                return metadata.outcomeIndex == LibNativePosition.OUTCOME_NO ? (true, amount) : (true, 0);
            }
            payoutFactor = Math.mulDiv(payoutFactor, numerator, LibNativePosition.RESULT_DENOMINATOR);
        }

        if (hasUnresolved) {
            return (false, 0);
        }

        uint256 yesPayout = Math.mulDiv(amount, payoutFactor, LibNativePosition.PAYOUT_FACTOR_DENOMINATOR);
        if (metadata.outcomeIndex == LibNativePosition.OUTCOME_YES) {
            return (true, uint128(yesPayout));
        }
        return (true, uint128(uint256(amount) - yesPayout));
    }
}
