// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

library LibReentrancy {
    bytes32 internal constant STORAGE_SLOT = bytes32(uint256(keccak256("eve.prediction.reentrancy.storage")) - 1);

    uint256 internal constant NOT_ENTERED = 1;
    uint256 internal constant ENTERED = 2;

    error ReentrantCall();

    struct Storage {
        uint256 status;
    }

    function enter() internal {
        Storage storage storage_ = store();
        if (storage_.status == ENTERED) {
            revert ReentrantCall();
        }

        storage_.status = ENTERED;
    }

    function exit() internal {
        store().status = NOT_ENTERED;
    }

    function store() internal pure returns (Storage storage storage_) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            storage_.slot := slot
        }
    }
}
