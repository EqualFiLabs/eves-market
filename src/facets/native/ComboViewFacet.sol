// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IComboViewFacet} from "../../interfaces/IComboViewFacet.sol";
import {Errors} from "../../libraries/Errors.sol";
import {LibCombinatorialPosition} from "../../libraries/LibCombinatorialPosition.sol";
import {LibEveMarket} from "../../libraries/LibEveMarket.sol";
import {LibNativePosition} from "../../libraries/LibNativePosition.sol";
import {NativePositionTypes} from "../../types/NativePositionTypes.sol";

contract ComboViewFacet is IComboViewFacet {
    function getComboPositionMetadata(uint256 positionId)
        external
        view
        returns (LibEveMarket.NativePositionMetadata memory metadata)
    {
        metadata = LibEveMarket.store().nativePositionMetadata[positionId];
        if (!metadata.exists) {
            revert Errors.NativePositionNotFound(positionId);
        }
    }

    function getComboPositionPayout(uint256 positionId, uint128 amount)
        external
        view
        returns (NativePositionTypes.NativePositionPayoutView memory payout)
    {
        if (amount == 0) revert Errors.InvalidAmount(amount);

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.NativePositionMetadata storage metadata = state.nativePositionMetadata[positionId];
        if (!metadata.exists) revert Errors.NativePositionNotFound(positionId);

        bool finalPayout;
        uint128 collateralOut;
        address collateralToken;
        uint8 collateralProfileId;
        if (metadata.moduleId == LibNativePosition.MODULE_COMBINATORIAL) {
            LibCombinatorialPosition.requireComboPosition(state, positionId);
            (finalPayout, collateralOut) = LibCombinatorialPosition.comboPayout(state, metadata, amount);
            collateralToken = LibCombinatorialPosition.collateralTokenFor(state, metadata.conditionId);
            collateralProfileId = LibCombinatorialPosition.collateralProfileFor(state, metadata.conditionId);
        } else {
            (finalPayout, collateralOut) = LibNativePosition.positionPayout(state, positionId, amount);
            LibEveMarket.Market storage market = state.markets[metadata.marketId];
            collateralToken = market.collateralToken;
            collateralProfileId = market.collateralProfileId;
        }

        payout = NativePositionTypes.NativePositionPayoutView({
            positionId: positionId,
            moduleId: metadata.moduleId,
            conditionId: metadata.conditionId,
            outcomeIndex: metadata.outcomeIndex,
            marketId: metadata.marketId,
            collateralToken: collateralToken,
            collateralProfileId: collateralProfileId,
            isFinal: finalPayout,
            collateralOut: collateralOut
        });
    }

    function getComboCollateralStatus(address collateralToken)
        external
        view
        returns (NativePositionTypes.NativeCollateralStatus memory status)
    {
        if (collateralToken == address(0)) revert Errors.ZeroAddress();
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        uint256 held = IERC20(collateralToken).balanceOf(address(this));
        uint256 liability = state.nativePositionCollateralLiability[collateralToken];
        status = NativePositionTypes.NativeCollateralStatus({
            collateralToken: collateralToken,
            held: held,
            liability: liability,
            balanceAboveNativeLiability: held > liability ? held - liability : 0,
            solvent: held >= liability
        });
    }
}
