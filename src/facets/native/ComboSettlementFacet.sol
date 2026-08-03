// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC1155} from "../../../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";

import {IComboSettlementFacet} from "../../interfaces/IComboSettlementFacet.sol";
import {IEvesCTFSettlementAdapter} from "../../interfaces/IEvesCTFSettlementAdapter.sol";
import {IEvesNegRiskAdapter} from "../../interfaces/IEvesNegRiskAdapter.sol";
import {IEvesPositionManager} from "../../interfaces/IEvesPositionManager.sol";
import {Errors} from "../../libraries/Errors.sol";
import {Events} from "../../libraries/Events.sol";
import {LibCombinatorialPosition} from "../../libraries/LibCombinatorialPosition.sol";
import {LibEveMarket} from "../../libraries/LibEveMarket.sol";
import {LibNativePosition} from "../../libraries/LibNativePosition.sol";
import {LibNativeCollateral} from "../../libraries/LibNativeCollateral.sol";
import {LibReentrancy} from "../../libraries/LibReentrancy.sol";

contract ComboSettlementFacet is IComboSettlementFacet {
    using SafeERC20 for IERC20;

    modifier nonReentrant() {
        LibReentrancy.enter();
        _;
        LibReentrancy.exit();
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
        (redeemable, collateralOut) = LibCombinatorialPosition.comboPayout(state, metadata, amount);
        if (!redeemable) {
            revert Errors.ComboPositionNotRedeemable(positionId);
        }

        IEvesPositionManager(state.config.evesPositionManager).burn(msg.sender, positionId, amount);
        if (state.comboConditions[metadata.conditionId].legCount == 1) {
            collateralOut = _redeemSingleCTF(state, metadata, amount, receiver);
        } else if (collateralOut != 0) {
            LibNativeCollateral.releaseBacking(state, collateralToken, receiver, collateralOut);
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
        return LibCombinatorialPosition.comboPayout(state, metadata, amount);
    }

    function _redeemSingleCTF(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.NativePositionMetadata storage comboMetadata,
        uint128 amount,
        address receiver
    ) internal returns (uint128 payout) {
        uint256 underlyingPositionId = state.comboConditionLegs[comboMetadata.conditionId][0];
        if (comboMetadata.outcomeIndex == LibNativePosition.OUTCOME_NO) {
            underlyingPositionId = LibCombinatorialPosition.flipLeg(state, underlyingPositionId);
        }

        uint256 escrowed = state.ctfComboEscrow[underlyingPositionId];
        if (escrowed < amount) {
            revert Errors.ComboCTFEscrowInsufficient(underlyingPositionId, escrowed, amount);
        }
        state.ctfComboEscrow[underlyingPositionId] = escrowed - amount;

        LibEveMarket.CTFPositionMetadata storage ctfMetadata = state.ctfPositionMetadata[underlyingPositionId];
        uint256[] memory amounts = new uint256[](2);
        if (underlyingPositionId == state.ctfConditionYesPositionId[ctfMetadata.conditionId]) {
            amounts[0] = amount;
        } else {
            amounts[1] = amount;
        }

        IERC1155(ctfMetadata.positionToken).setApprovalForAll(ctfMetadata.settlementAdapter, true);
        uint256 actualPayout;
        // Historical positions keep their adapter, so classification cannot use the current global pointer.
        if (state.nativePositionMetadata[underlyingPositionId].moduleId == LibNativePosition.MODULE_NEGRISK) {
            actualPayout = IEvesNegRiskAdapter(ctfMetadata.settlementAdapter)
                .redeemPositions(ctfMetadata.conditionId, amounts, receiver);
        } else {
            actualPayout = IEvesCTFSettlementAdapter(ctfMetadata.settlementAdapter)
                .redeemPositions(ctfMetadata.conditionId, amounts, receiver);
        }
        IERC1155(ctfMetadata.positionToken).setApprovalForAll(ctfMetadata.settlementAdapter, false);
        if (actualPayout > type(uint128).max) revert Errors.InvalidAmount(actualPayout);
        payout = uint128(actualPayout);
    }
}
