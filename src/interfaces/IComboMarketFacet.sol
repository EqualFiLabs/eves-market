// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {NativePositionTypes} from "../types/NativePositionTypes.sol";

interface IComboMarketFacet {
    struct ComboMarketPreparation {
        bytes32 marketId;
        bytes32 conditionId;
        uint256 yesPositionId;
        uint256 noPositionId;
        bytes32 yesBookId;
        bytes32 noBookId;
    }

    function createComboMarket(bytes32[] calldata marketIds, bool[] calldata yesLegs)
        external
        returns (ComboMarketPreparation memory preparation);

    function createComboMarketFromLegs(uint256[] calldata positionIds)
        external
        returns (ComboMarketPreparation memory preparation);

    function computeComboBookId(bytes32 comboMarketId, bool isYesSide) external pure returns (bytes32 bookId);

    function getComboMarket(bytes32 comboMarketId)
        external
        view
        returns (NativePositionTypes.ComboMarketView memory comboMarket);

    function getComboBook(address positionToken, uint256 positionId) external view returns (bytes32 bookId);
}
