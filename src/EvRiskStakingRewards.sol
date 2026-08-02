// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC1155Holder} from "../lib/openzeppelin-contracts/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IERC1155} from "../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";
import {Math} from "../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import {IEvRiskStakingRewards} from "./interfaces/IEvRiskStakingRewards.sol";
import {IEveUSDPool} from "./interfaces/IEveUSDPool.sol";

contract EvRiskStakingRewards is IEvRiskStakingRewards, ERC1155Holder, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 internal constant REWARD_PRECISION = 1e30;

    address public immutable evRisk;
    address public immutable eveUSDPool;
    uint256 public immutable primaryProfileId;

    address public owner;
    address public treasury;

    mapping(uint256 seriesId => uint256 amount) public override totalStaked;
    mapping(address account => mapping(uint256 seriesId => uint256 amount)) public override stakedBalance;
    mapping(uint256 seriesId => mapping(address token => uint256 accRewardPerShare)) public accRewardPerShare;
    mapping(uint256 seriesId => address[] tokens) internal _rewardTokens;
    mapping(uint256 seriesId => mapping(address token => bool known)) internal _knownRewardToken;
    mapping(address account => mapping(uint256 seriesId => mapping(address token => uint256 debt))) public rewardDebt;
    mapping(address account => mapping(uint256 seriesId => mapping(address token => uint256 amount))) public
        accruedRewards;

    constructor(address evRisk_, address eveUSDPool_, uint256 primaryProfileId_, address treasury_, address owner_) {
        _requireContract(evRisk_);
        _requireContract(eveUSDPool_);
        if (primaryProfileId_ == 0 || treasury_ == address(0) || owner_ == address(0)) {
            revert ZeroAddress();
        }

        IEveUSDPool(eveUSDPool_).collateralProfile(primaryProfileId_);

        evRisk = evRisk_;
        eveUSDPool = eveUSDPool_;
        primaryProfileId = primaryProfileId_;
        treasury = treasury_;
        owner = owner_;

        emit OwnershipTransferred(address(0), owner_);
        emit TreasurySet(address(0), treasury_);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized(msg.sender);
        _;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        address previousOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(previousOwner, newOwner);
    }

    function setTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) revert ZeroAddress();
        address previousTreasury = treasury;
        treasury = newTreasury;
        emit TreasurySet(previousTreasury, newTreasury);
    }

    function notifyReward(address token, uint256 amount) external override nonReentrant {
        if (token == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        uint256 seriesId = activeSeriesId();
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        IEveUSDPool.RiskSeries memory series = IEveUSDPool(eveUSDPool).riskSeries(seriesId);
        if (series.status != IEveUSDPool.SeriesStatus.Active) {
            IERC20(token).safeTransfer(treasury, amount);
            emit RewardRoutedToTreasury(msg.sender, seriesId, token, amount);
            return;
        }

        uint256 supply = totalStaked[seriesId];
        if (supply == 0) {
            IERC20(token).safeTransfer(treasury, amount);
            emit RewardRoutedToTreasury(msg.sender, seriesId, token, amount);
            return;
        }

        _ensureRewardToken(seriesId, token);
        uint256 increment = Math.mulDiv(amount, REWARD_PRECISION, supply);
        if (increment == 0) {
            IERC20(token).safeTransfer(treasury, amount);
            emit RewardRoutedToTreasury(msg.sender, seriesId, token, amount);
            return;
        }

        uint256 distributed = Math.mulDiv(increment, supply, REWARD_PRECISION);
        accRewardPerShare[seriesId][token] += increment;

        uint256 remainder = amount - distributed;
        if (remainder != 0) {
            IERC20(token).safeTransfer(treasury, remainder);
        }
        emit RewardNotified(msg.sender, seriesId, token, distributed);
    }

    function stake(uint256 amount) external override nonReentrant returns (uint256 seriesId) {
        if (amount == 0) revert ZeroAmount();
        seriesId = _activeStakeableSeriesId();

        _checkpoint(msg.sender, seriesId);
        IERC1155(evRisk).safeTransferFrom(msg.sender, address(this), seriesId, amount, "");
        stakedBalance[msg.sender][seriesId] += amount;
        totalStaked[seriesId] += amount;
        _syncDebt(msg.sender, seriesId);

        emit Staked(msg.sender, seriesId, amount);
    }

    function unstake(uint256 seriesId, uint256 amount) external override nonReentrant {
        if (amount == 0) revert ZeroAmount();

        uint256 currentStake = stakedBalance[msg.sender][seriesId];
        if (amount > currentStake) revert InvalidSeries(seriesId);

        _checkpoint(msg.sender, seriesId);
        stakedBalance[msg.sender][seriesId] = currentStake - amount;
        totalStaked[seriesId] -= amount;
        _syncDebt(msg.sender, seriesId);
        IERC1155(evRisk).safeTransferFrom(address(this), msg.sender, seriesId, amount, "");

        emit Unstaked(msg.sender, seriesId, amount);
    }

    function claim(uint256 seriesId, address token) public override nonReentrant returns (uint256 amount) {
        if (token == address(0)) revert ZeroAddress();
        _checkpointToken(msg.sender, seriesId, token);

        amount = accruedRewards[msg.sender][seriesId][token];
        if (amount == 0) revert NoRewards(msg.sender, seriesId, token);

        accruedRewards[msg.sender][seriesId][token] = 0;
        IERC20(token).safeTransfer(msg.sender, amount);
        emit RewardClaimed(msg.sender, seriesId, token, amount);
    }

    function exit(uint256 seriesId, address token) external override nonReentrant returns (uint256 amount) {
        if (token == address(0)) revert ZeroAddress();

        uint256 currentStake = stakedBalance[msg.sender][seriesId];
        _checkpointToken(msg.sender, seriesId, token);

        amount = accruedRewards[msg.sender][seriesId][token];
        if (amount != 0) {
            accruedRewards[msg.sender][seriesId][token] = 0;
            IERC20(token).safeTransfer(msg.sender, amount);
            emit RewardClaimed(msg.sender, seriesId, token, amount);
        }

        if (currentStake != 0) {
            _checkpoint(msg.sender, seriesId);
            stakedBalance[msg.sender][seriesId] = 0;
            totalStaked[seriesId] -= currentStake;
            _syncDebt(msg.sender, seriesId);
            IERC1155(evRisk).safeTransferFrom(address(this), msg.sender, seriesId, currentStake, "");
            emit Unstaked(msg.sender, seriesId, currentStake);
        }
    }

    function previewClaim(address account, uint256 seriesId, address token)
        external
        view
        override
        returns (uint256 amount)
    {
        uint256 stakeAmount = stakedBalance[account][seriesId];
        uint256 accumulated = Math.mulDiv(stakeAmount, accRewardPerShare[seriesId][token], REWARD_PRECISION);
        amount = accruedRewards[account][seriesId][token];
        uint256 debt = rewardDebt[account][seriesId][token];
        if (accumulated > debt) {
            amount += accumulated - debt;
        }
    }

    function activeSeriesId() public view override returns (uint256 seriesId) {
        IEveUSDPool.StableCollateralProfile memory profile = IEveUSDPool(eveUSDPool).collateralProfile(primaryProfileId);
        seriesId = profile.activeSeriesId;
    }

    function rewardTokens(uint256 seriesId) external view returns (address[] memory tokens) {
        tokens = _rewardTokens[seriesId];
    }

    function _activeStakeableSeriesId() internal view returns (uint256 seriesId) {
        seriesId = activeSeriesId();
        IEveUSDPool.RiskSeries memory series = IEveUSDPool(eveUSDPool).riskSeries(seriesId);
        if (series.status != IEveUSDPool.SeriesStatus.Active) revert InvalidSeries(seriesId);
    }

    function _checkpoint(address account, uint256 seriesId) internal {
        address[] storage tokens = _rewardTokens[seriesId];
        uint256 length = tokens.length;
        for (uint256 index; index < length; ++index) {
            _checkpointToken(account, seriesId, tokens[index]);
        }
    }

    function _checkpointToken(address account, uint256 seriesId, address token) internal {
        uint256 stakeAmount = stakedBalance[account][seriesId];
        uint256 accumulated = Math.mulDiv(stakeAmount, accRewardPerShare[seriesId][token], REWARD_PRECISION);
        uint256 debt = rewardDebt[account][seriesId][token];
        if (accumulated > debt) {
            accruedRewards[account][seriesId][token] += accumulated - debt;
        }
        rewardDebt[account][seriesId][token] = accumulated;
    }

    function _syncDebt(address account, uint256 seriesId) internal {
        uint256 stakeAmount = stakedBalance[account][seriesId];
        address[] storage tokens = _rewardTokens[seriesId];
        uint256 length = tokens.length;
        for (uint256 index; index < length; ++index) {
            address token = tokens[index];
            rewardDebt[account][seriesId][token] =
                Math.mulDiv(stakeAmount, accRewardPerShare[seriesId][token], REWARD_PRECISION);
        }
    }

    function _ensureRewardToken(uint256 seriesId, address token) internal {
        if (_knownRewardToken[seriesId][token]) {
            return;
        }
        _knownRewardToken[seriesId][token] = true;
        _rewardTokens[seriesId].push(token);
    }

    function _requireContract(address account) internal view {
        if (account == address(0)) revert ZeroAddress();
        if (account.code.length == 0) revert ContractExpected(account);
    }
}
