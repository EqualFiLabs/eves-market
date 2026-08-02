// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Errors} from "./Errors.sol";

library LibSafeCast {
    function toUint128(uint256 value) internal pure returns (uint128 narrowed) {
        if (value > type(uint128).max) {
            revert Errors.InvalidAmount(value);
        }
        narrowed = uint128(value);
    }
}
