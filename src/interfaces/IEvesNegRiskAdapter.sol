// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IEvesNegRiskAdapter {
    struct EventView {
        uint16 outcomeCount;
        uint16 resolvedConditionCount;
        uint16 winningOutcome;
        bool prepared;
        bool resolved;
        bool invalid;
    }

    function conditionalTokens() external view returns (address);
    function collateralToken() external view returns (address);
    function wrappedCollateral() external view returns (address);
    function oracle() external view returns (address);

    function prepareEvent(bytes32 eventKey, uint256 outcomeCount) external returns (bytes32 eventId);
    function resolveEvent(bytes32 eventId, uint256 outcome) external;

    function splitEvent(bytes32 eventId, uint256 amount, address receiver) external;
    function mergeEvent(bytes32 eventId, uint256 amount, address receiver) external;
    function convertPositions(bytes32 eventId, uint256 indexSet, uint256 amount, address receiver) external;

    function splitPosition(bytes32 conditionId, uint256 amount) external;
    function mergePositions(bytes32 conditionId, uint256 amount) external;
    function redeemPositions(bytes32 conditionId, uint256[] calldata amounts, address receiver)
        external
        returns (uint256 payout);

    function getEvent(bytes32 eventId) external view returns (EventView memory eventView);
    function questionIdFor(bytes32 eventId, uint256 outcome) external pure returns (bytes32 questionId);
    function conditionIdFor(bytes32 eventId, uint256 outcome) external view returns (bytes32 conditionId);
    function positionIdFor(bytes32 eventId, uint256 outcome, bool yes) external view returns (uint256 positionId);
}
