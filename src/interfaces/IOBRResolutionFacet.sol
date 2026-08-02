// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IOBRResolutionFacet {
    struct ResolutionInfo {
        address proposer;
        uint8 proposedOutcome;
        uint8 escalationLevel;
        bool disputed;
        uint128 bondAmount;
        uint64 proposedAt;
        uint64 disputeDeadline;
        uint64 snapshotBlock;
    }

    function settleMarket(bytes32 marketId, uint8 outcome) external;

    function settleMarketEarly(bytes32 marketId, uint8 outcome) external;

    function openResolution(bytes32 marketId, uint8 outcome) external;

    function disputeResolution(bytes32 marketId, uint8 counterOutcome) external;

    function getResolutionHistory(bytes32 marketId)
        external
        view
        returns (ResolutionInfo[] memory history, uint8 currentEscalationLevel, uint64 disputeDeadline, bool isActive);

    function finalizeResolution(bytes32 marketId) external;

    function finalizeFromJury(bytes32 marketId, uint8 finalResult) external;

    function getMarketStatus(bytes32 marketId)
        external
        view
        returns (uint8 state, uint8 outcome, uint64 disputeDeadline, uint128 creatorFeesEscrowed);
}
