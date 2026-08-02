// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Errors} from "./Errors.sol";

library LibGovernanceDelay {
    bytes32 internal constant STORAGE_SLOT = keccak256("eve.prediction.governance.delay.storage.v1");

    struct Storage {
        bool finalized;
        uint64 delay;
        mapping(bytes32 operationId => uint256 readyAt) readyAt;
    }

    function s() internal pure returns (Storage storage state) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            state.slot := slot
        }
    }

    function operationId(bytes memory callData) internal view returns (bytes32) {
        return keccak256(abi.encode(block.chainid, address(this), callData));
    }

    function schedule(bytes32 id) internal returns (uint256 readyAt) {
        Storage storage state = s();
        if (!state.finalized) revert Errors.GovernanceDelayNotFinalized();
        uint256 existing = state.readyAt[id];
        if (existing != 0) revert Errors.GovernanceOperationAlreadyScheduled(id, existing);
        readyAt = block.timestamp + state.delay;
        state.readyAt[id] = readyAt;
    }

    function cancel(bytes32 id) internal returns (uint256 readyAt) {
        Storage storage state = s();
        readyAt = state.readyAt[id];
        if (readyAt == 0) revert Errors.GovernanceOperationNotScheduled(id);
        delete state.readyAt[id];
    }

    function consume(bytes32 id) internal {
        Storage storage state = s();
        uint256 readyAt = state.readyAt[id];
        if (readyAt == 0) revert Errors.GovernanceOperationNotScheduled(id);
        if (block.timestamp < readyAt) revert Errors.GovernanceOperationTimelocked(id, readyAt);
        delete state.readyAt[id];
    }
}
