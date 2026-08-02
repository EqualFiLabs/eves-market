// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

/// @notice Multi-token testnet faucet for distributing funded ERC20 test assets.
contract Faucet is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant CLAIM_INTERVAL = 1 days;

    struct TokenConfig {
        uint256 amount;
        bool enabled;
        bool exists;
    }

    mapping(address token => TokenConfig config) private tokenConfig;
    address[] private tokens;
    mapping(address user => uint64 timestamp) public lastClaimAt;

    error FaucetClaimTooSoon(uint256 nextAllowed);
    error FaucetInvalidToken(address token);
    error FaucetTokenNotConfigured(address token);
    error FaucetInsufficientBalance(address token, uint256 required, uint256 balance);
    error FaucetNoEnabledTokens();

    event TokenConfigured(address indexed token, uint256 amount, bool enabled);
    event Claimed(address indexed user, uint256 timestamp);
    event TokenClaimed(address indexed user, address indexed token, uint256 amount);
    event Withdrawn(address indexed token, address indexed to, uint256 amount);

    constructor(address owner_) Ownable(owner_) {}

    function setToken(address token, uint256 amount, bool enabled) external onlyOwner {
        if (token == address(0)) revert FaucetInvalidToken(token);

        TokenConfig storage config = tokenConfig[token];
        if (!config.exists) {
            config.exists = true;
            tokens.push(token);
        }

        config.amount = amount;
        config.enabled = enabled;

        emit TokenConfigured(token, amount, enabled);
    }

    function setTokenAmount(address token, uint256 amount) external onlyOwner {
        TokenConfig storage config = tokenConfig[token];
        if (!config.exists) revert FaucetTokenNotConfigured(token);

        config.amount = amount;

        emit TokenConfigured(token, amount, config.enabled);
    }

    function setTokenEnabled(address token, bool enabled) external onlyOwner {
        TokenConfig storage config = tokenConfig[token];
        if (!config.exists) revert FaucetTokenNotConfigured(token);

        config.enabled = enabled;

        emit TokenConfigured(token, config.amount, enabled);
    }

    function claim() external nonReentrant {
        uint64 last = lastClaimAt[msg.sender];
        uint64 nowTs = uint64(block.timestamp);
        if (last != 0 && nowTs < last + CLAIM_INTERVAL) {
            revert FaucetClaimTooSoon(last + CLAIM_INTERVAL);
        }

        uint256 enabledCount;
        uint256 length = tokens.length;
        for (uint256 index = 0; index < length; ++index) {
            address token = tokens[index];
            TokenConfig memory config = tokenConfig[token];
            if (!config.enabled || config.amount == 0) continue;

            ++enabledCount;
            uint256 balance = IERC20(token).balanceOf(address(this));
            if (balance < config.amount) {
                revert FaucetInsufficientBalance(token, config.amount, balance);
            }
        }
        if (enabledCount == 0) revert FaucetNoEnabledTokens();

        lastClaimAt[msg.sender] = nowTs;

        for (uint256 index = 0; index < length; ++index) {
            address token = tokens[index];
            TokenConfig memory config = tokenConfig[token];
            if (!config.enabled || config.amount == 0) continue;

            IERC20(token).safeTransfer(msg.sender, config.amount);
            emit TokenClaimed(msg.sender, token, config.amount);
        }

        emit Claimed(msg.sender, block.timestamp);
    }

    function withdraw(address token, address to, uint256 amount) external onlyOwner {
        if (token == address(0) || to == address(0)) revert FaucetInvalidToken(token);

        IERC20(token).safeTransfer(to, amount);

        emit Withdrawn(token, to, amount);
    }

    function getTokens() external view returns (address[] memory) {
        return tokens;
    }

    function getTokenConfig(address token) external view returns (uint256 amount, bool enabled, bool exists) {
        TokenConfig memory config = tokenConfig[token];
        return (config.amount, config.enabled, config.exists);
    }

    function nextClaimAt(address user) external view returns (uint256) {
        uint64 last = lastClaimAt[user];
        if (last == 0) return 0;

        return uint256(last + CLAIM_INTERVAL);
    }
}
