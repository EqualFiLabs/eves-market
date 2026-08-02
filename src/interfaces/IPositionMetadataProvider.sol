// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IPositionMetadataProvider {
    function positionTokenURI(address positionToken, uint256 positionId) external view returns (string memory uri);
}
