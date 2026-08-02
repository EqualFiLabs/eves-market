// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IEvesPositionManager {
    error NotDiamond(address caller);

    function diamond() external view returns (address);

    function mint(address to, uint256 id, uint256 amount) external;

    function burn(address from, uint256 id, uint256 amount) external;

    function batchMint(address to, uint256[] calldata ids, uint256[] calldata amounts) external;

    function batchBurn(address from, uint256[] calldata ids, uint256[] calldata amounts) external;
}
