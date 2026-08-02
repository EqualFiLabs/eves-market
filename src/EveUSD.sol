// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import {IEveUSD} from "./interfaces/IEveUSD.sol";

contract EveUSD is ERC20, IEveUSD {
    address public immutable override pool;

    constructor(address pool_) ERC20("eveUSD", "eveUSD") {
        if (pool_ == address(0)) {
            revert ZeroAddress();
        }

        pool = pool_;
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    function mint(address to, uint256 amount) external {
        if (msg.sender != pool) {
            revert NotMinter(msg.sender);
        }

        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        if (msg.sender != pool) {
            revert NotBurner(msg.sender);
        }

        _burn(from, amount);
    }
}
