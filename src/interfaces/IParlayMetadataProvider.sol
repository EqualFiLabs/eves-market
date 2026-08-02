// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IParlayMetadataProvider {
    function parlayTicketURI(address ticketToken, uint256 ticketId) external view returns (string memory uri);
}
