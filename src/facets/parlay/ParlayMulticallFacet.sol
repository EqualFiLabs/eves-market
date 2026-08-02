// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

contract ParlayMulticallFacet {
    function multicall(bytes[] calldata calls) external returns (bytes[] memory results) {
        results = new bytes[](calls.length);
        for (uint256 index = 0; index < calls.length; ++index) {
            (bool success, bytes memory result) = address(this).delegatecall(calls[index]);
            if (!success) {
                assembly ("memory-safe") {
                    revert(add(result, 32), mload(result))
                }
            }
            results[index] = result;
        }
    }
}
