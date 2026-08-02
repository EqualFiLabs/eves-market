// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {MLOPredictionTypes} from "../types/MLOPredictionTypes.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibMLOPredictionAdapter} from "../libraries/LibMLOPredictionAdapter.sol";

contract MLOPredictionAdapterFacet {
    function setSeniorCapitalPool(address pool) external {
        LibDiamond.enforceIsContractOwner();
        LibMLOPredictionAdapter.setSeniorCapitalPool(LibEveMarket.store(), pool);
    }

    function seniorCapitalPool() external view returns (address pool) {
        pool = LibEveMarket.store().config.seniorCapitalPool;
    }

    function getMLOAskCurve(uint256 curveId) external view returns (MLOPredictionTypes.MLOAskCurveView memory curve) {
        curve = LibMLOPredictionAdapter.viewAskCurve(LibEveMarket.store(), curveId);
    }

    function getMLOInventory(bytes32 bucketId, bytes32 marketId)
        external
        view
        returns (MLOPredictionTypes.MLOInventoryView memory inventory)
    {
        inventory = LibMLOPredictionAdapter.viewInventory(LibEveMarket.store(), bucketId, marketId);
    }
}
