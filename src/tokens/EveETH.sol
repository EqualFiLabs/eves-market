// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract EveETH is ERC20 {
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error ZeroAmount();

    address public immutable weth;

    event Wrapped(address indexed caller, address indexed receiver, uint256 amount);
    event Unwrapped(address indexed caller, address indexed receiver, uint256 amount);

    constructor(address weth_) ERC20("eveETH", "eveETH") {
        if (weth_ == address(0)) {
            revert ZeroAddress();
        }

        weth = weth_;
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    function wrap(uint256 amount, address to) external returns (uint256 eveETHMinted) {
        if (amount == 0) {
            revert ZeroAmount();
        }
        if (to == address(0)) {
            revert ZeroAddress();
        }

        IERC20(weth).safeTransferFrom(msg.sender, address(this), amount);
        _mint(to, amount);

        emit Wrapped(msg.sender, to, amount);

        return amount;
    }

    function unwrap(uint256 amount, address to) external returns (uint256 wethOut) {
        if (amount == 0) {
            revert ZeroAmount();
        }
        if (to == address(0)) {
            revert ZeroAddress();
        }

        _burn(msg.sender, amount);
        IERC20(weth).safeTransfer(to, amount);

        emit Unwrapped(msg.sender, to, amount);

        return amount;
    }
}
