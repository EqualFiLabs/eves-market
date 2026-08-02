// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {MLOPredictionTypes} from "../types/MLOPredictionTypes.sol";
import {IMLOPredictionAdapterFacet} from "../interfaces/IMLOPredictionAdapterFacet.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibMLOAskState} from "../libraries/LibMLOAskState.sol";
import {LibMLOPredictionAdapter} from "../libraries/LibMLOPredictionAdapter.sol";

contract MLOPredictionAdapterFacet {
    function getMLOCurve(uint256 curveId) external view returns (MLOPredictionTypes.MLOCurveView memory curve) {
        curve = LibMLOPredictionAdapter.viewCurve(LibEveMarket.store(), curveId);
    }

    function getMLOInventory(bytes32 bucketId, bytes32 marketId)
        external
        view
        returns (MLOPredictionTypes.MLOInventoryView memory inventory)
    {
        inventory = LibMLOPredictionAdapter.viewInventory(LibEveMarket.store(), bucketId, marketId);
    }

    function getMLOScenarioExposure(bytes32 bucketId)
        external
        view
        returns (MLOPredictionTypes.MLOScenarioExposureView memory exposure)
    {
        exposure = LibMLOPredictionAdapter.viewScenarioExposure(LibEveMarket.store(), bucketId);
    }

    function previewMLOFunding(bytes32 bucketId)
        external
        view
        returns (MLOPredictionTypes.MLOFundingView memory funding)
    {
        funding = LibMLOPredictionAdapter.viewFunding(LibEveMarket.store(), bucketId);
    }

    function applyMLOAskFillState(MLOPredictionTypes.MLOAskFillStateParams calldata params) external {
        if (msg.sender != address(this)) revert IMLOPredictionAdapterFacet.MLOInternalOnly(msg.sender);
        LibMLOAskState.applyFill(LibEveMarket.store(), params);
    }
}
