// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MockUSDG is ERC20, ERC20Permit, Ownable {
    bool public paused;
    mapping(address account => bool blocked) internal _blacklisted;

    error TokenPaused();
    error AccountBlacklisted(address account);

    constructor() ERC20("Mock USDG", "mUSDG") ERC20Permit("Mock USDG") Ownable(msg.sender) {}

    function mint(address account, uint256 amount) external onlyOwner {
        _mint(account, amount);
    }

    function setPaused(bool value) external onlyOwner {
        paused = value;
    }

    function setBlacklisted(address account, bool value) external onlyOwner {
        _blacklisted[account] = value;
    }

    function isBlacklisted(address account) external view returns (bool) {
        return _blacklisted[account];
    }

    function _update(address from, address to, uint256 value) internal override {
        if (paused) revert TokenPaused();
        if (from != address(0) && _blacklisted[from]) revert AccountBlacklisted(from);
        if (to != address(0) && _blacklisted[to]) revert AccountBlacklisted(to);
        super._update(from, to, value);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}
