// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {MLOPredictionTypes} from "../types/MLOPredictionTypes.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibMLOPredictionAdapter} from "../libraries/LibMLOPredictionAdapter.sol";
import {LibReentrancy} from "../libraries/LibReentrancy.sol";

contract MLOPredictionSettlementFacet {
    modifier nonReentrant() {
        LibReentrancy.enter();
        _;
        LibReentrancy.exit();
    }

    function settleMLOInventory(bytes32 bucketId, bytes32 marketId)
        external
        nonReentrant
        returns (MLOPredictionTypes.MLOInventorySettlement memory settlement)
    {
        settlement = LibMLOPredictionAdapter.settleInventory(LibEveMarket.store(), bucketId, marketId);
    }
}
