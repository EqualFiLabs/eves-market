// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {LibBuyExecution} from "./LibBuyExecution.sol";
import {LibEveMarket} from "./LibEveMarket.sol";

library LibDelayedOrderEscrowAskFill {
    function fillEscrowedAsk(
        uint256 curveId,
        uint32 expectedGeneration,
        bytes32 expectedCommitment,
        LibBuyExecution.RouteRequest memory request,
        LibBuyExecution.RouteTotals memory totals
    ) public returns (LibBuyExecution.RouteTotals memory updatedTotals) {
        updatedTotals = LibBuyExecution.routeSingleCurve(
            LibEveMarket.store(), curveId, expectedGeneration, expectedCommitment, request, totals
        );
    }
}
