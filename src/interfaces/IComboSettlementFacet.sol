// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IComboSettlementFacet {
    function redeemCombo(uint256 positionId, uint128 amount, address receiver) external returns (uint128 collateralOut);

    function getComboPayout(uint256 positionId, uint128 amount)
        external
        view
        returns (bool redeemable, uint128 collateralOut);
}
