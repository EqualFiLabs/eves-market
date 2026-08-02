// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IVotes {
    function getVotes(address account) external view returns (uint256);

    function getPastVotes(address account, uint256 timepoint) external view returns (uint256);

    function getPastTotalSupply(uint256 timepoint) external view returns (uint256);

    function delegates(address account) external view returns (address);

    function delegate(address delegatee) external;

    function delegateBySig(address delegatee, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s) external;
}
