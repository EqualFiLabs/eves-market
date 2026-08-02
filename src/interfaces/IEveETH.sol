// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IEveETH {
    function weth() external view returns (address);
    function wrap(uint256 amount, address to) external returns (uint256 eveETHMinted);
}
