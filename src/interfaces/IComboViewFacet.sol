// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {NativePositionTypes} from "../types/NativePositionTypes.sol";

interface IComboViewFacet {
    function getComboPositionMetadata(uint256 positionId)
        external
        view
        returns (LibEveMarket.NativePositionMetadata memory metadata);

    function getComboPositionPayout(uint256 positionId, uint128 amount)
        external
        view
        returns (NativePositionTypes.NativePositionPayoutView memory payout);

    function getComboCollateralStatus(address collateralToken)
        external
        view
        returns (NativePositionTypes.NativeCollateralStatus memory status);
}
