// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Adapter-controlled collateral wrapper used by CTF NegRisk positions.
/// @dev Adapted from Polymarket's MIT-licensed WrappedCollateral at commit
///      f78b35b0863b4308a431ca307d06f49b2ea65e78.
contract EvesNegRiskWrappedCollateral is ERC20 {
    using SafeERC20 for IERC20;

    error OnlyOwner();
    error ZeroAddress();
    error NonExactTransfer(uint256 expected, uint256 actual);

    address public immutable owner;
    IERC20 public immutable underlying;
    uint8 private immutable underlyingDecimals;

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    constructor(address underlying_, uint8 decimals_) ERC20("Eves NegRisk Wrapped Collateral", "enrCOL") {
        if (underlying_ == address(0)) revert ZeroAddress();
        owner = msg.sender;
        underlying = IERC20(underlying_);
        underlyingDecimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return underlyingDecimals;
    }

    function wrap(address receiver, uint256 amount) external onlyOwner {
        uint256 balanceBefore = underlying.balanceOf(address(this));
        underlying.safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = underlying.balanceOf(address(this)) - balanceBefore;
        if (received != amount) revert NonExactTransfer(amount, received);
        _mint(receiver, amount);
    }

    function unwrap(address receiver, uint256 amount) external {
        _burn(msg.sender, amount);
        _transferUnderlyingExact(receiver, amount);
    }

    function mint(uint256 amount) external onlyOwner {
        _mint(msg.sender, amount);
    }

    function release(address receiver, uint256 amount) external onlyOwner {
        _transferUnderlyingExact(receiver, amount);
    }

    function _transferUnderlyingExact(address receiver, uint256 amount) private {
        uint256 receiverBefore = underlying.balanceOf(receiver);
        underlying.safeTransfer(receiver, amount);
        uint256 receiverAfter = underlying.balanceOf(receiver);
        uint256 received = receiverAfter >= receiverBefore ? receiverAfter - receiverBefore : 0;
        if (received != amount) revert NonExactTransfer(amount, received);
    }
}
