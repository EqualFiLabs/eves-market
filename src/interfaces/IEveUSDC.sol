// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IEveUSDC is IERC20 {
    error ZeroAmount();
    error NonConvertibleEveUSDC(uint256 amount);
    error UnauthorizedMinter(address caller);
    error UnauthorizedBurner(address caller);

    event Wrapped(address indexed caller, address indexed to, uint256 amount);
    event Unwrapped(address indexed caller, address indexed to, uint256 amount);

    function wrap(uint256 usdcAmount, address to) external returns (uint256 eveUSDCMinted);

    function unwrap(uint256 eveUSDCAmount, address to) external returns (uint256 usdcOut);

    function mint(address to, uint256 amount) external;

    function burn(address from, uint256 amount) external;

    function usdc() external view returns (address);

    function onramp() external view returns (address);

    function offramp() external view returns (address);
}
