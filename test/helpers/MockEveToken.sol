// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Votes} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {EIP712} from "../../lib/openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";

contract MockEveToken is ERC20Votes {
    constructor() ERC20("Mock EVE", "mEVE") EIP712("Mock EVE", "1") {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function mintAndDelegate(address account, uint256 amount) external {
        _mint(account, amount);
        _delegate(account, account);
    }
}
