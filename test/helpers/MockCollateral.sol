// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract MockCollateral is ERC20, ERC20Permit {
    bytes32 internal constant STATICS_DOLLAR_KIND = keccak256("STATICS_DOLLAR_TOKEN_V1");
    uint256 internal transferFeeBps;

    constructor() ERC20("Mock Collateral", "mCOL") ERC20Permit("Mock Collateral") {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function coreTokenKind() external pure returns (bytes32) {
        return STATICS_DOLLAR_KIND;
    }

    function pool() external view returns (address) {
        return address(this);
    }

    function staticsDollar() external view returns (address) {
        return address(this);
    }

    function setTransferFeeBps(uint256 feeBps) external {
        require(feeBps <= 10_000, "invalid fee");
        transferFeeBps = feeBps;
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from == address(0) || to == address(0) || transferFeeBps == 0) {
            super._update(from, to, value);
            return;
        }
        uint256 fee = (value * transferFeeBps) / 10_000;
        super._update(from, to, value - fee);
        if (fee != 0) super._update(from, address(0), fee);
    }
}
