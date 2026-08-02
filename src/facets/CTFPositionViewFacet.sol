// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ICTFPositionViewFacet} from "../interfaces/ICTFPositionViewFacet.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";

contract CTFPositionViewFacet is ICTFPositionViewFacet {
    function getCTFPositionMetadata(uint256 positionId)
        external
        view
        returns (
            address positionToken,
            address collateralToken,
            address settlementAdapter,
            bytes32 conditionId,
            uint256 complementPositionId,
            uint128 payoutUnit,
            bool exists
        )
    {
        LibEveMarket.CTFPositionMetadata storage metadata = LibEveMarket.store().ctfPositionMetadata[positionId];
        return (
            metadata.positionToken,
            metadata.collateralToken,
            metadata.settlementAdapter,
            metadata.conditionId,
            metadata.complementPositionId,
            metadata.payoutUnit,
            metadata.exists
        );
    }

    function getCTFComboEscrow(uint256 positionId) external view returns (uint256 amount) {
        return LibEveMarket.store().ctfComboEscrow[positionId];
    }

    function getCTFConditionPositions(bytes32 conditionId)
        external
        view
        returns (uint256 yesPositionId, uint256 noPositionId)
    {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        return (state.ctfConditionYesPositionId[conditionId], state.ctfConditionNoPositionId[conditionId]);
    }
}
