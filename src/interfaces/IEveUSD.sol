// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IEveUSD is IERC20 {
    error NotMinter(address caller);
    error NotBurner(address caller);
    error ZeroAddress();

    function pool() external view returns (address);

    function mint(address to, uint256 amount) external;

    function burn(address from, uint256 amount) external;
}
