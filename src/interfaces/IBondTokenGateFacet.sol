// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IBondTokenGateFacet {
    function lockResolutionBond(address bonder, uint8 escalationLevel) external;

    function unlockResolutionBond(address bonder, uint128 amount) external;
}
