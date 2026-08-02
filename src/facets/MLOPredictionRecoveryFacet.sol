// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {LibDiamond} from "../libraries/LibDiamond.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibMLORecovery} from "../libraries/LibMLORecovery.sol";
import {LibReentrancy} from "../libraries/LibReentrancy.sol";
import {MLOPredictionTypes} from "../types/MLOPredictionTypes.sol";

contract MLOPredictionRecoveryFacet {
    modifier nonReentrant() {
        LibReentrancy.enter();
        _;
        LibReentrancy.exit();
    }

    function mloRecoveryConfig() external view returns (MLOPredictionTypes.MLORecoveryConfig memory config) {
        config = LibMLORecovery.config(LibEveMarket.store());
    }

    function setMLORecoveryConfig(address insuranceFund, uint16 seniorFundingBps, uint16 maxCleanupBatch) external {
        LibDiamond.enforceIsContractOwner();
        LibMLORecovery.setConfig(LibEveMarket.store(), insuranceFund, seniorFundingBps, maxCleanupBatch);
    }

    function synchronizeMLOBucketState(bytes32 bucketId) external returns (uint8 newState) {
        newState = uint8(LibMLORecovery.synchronizeState(LibEveMarket.store(), bucketId));
    }

    function cleanupMLOCurves(bytes32 bucketId, uint256[] calldata curveIds)
        external
        nonReentrant
        returns (MLOPredictionTypes.MLOCurveCleanupResult memory result)
    {
        result = LibMLORecovery.cleanupCurves(LibEveMarket.store(), bucketId, curveIds);
    }
}
