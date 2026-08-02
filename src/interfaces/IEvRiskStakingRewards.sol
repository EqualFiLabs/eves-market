// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IEvRiskStakingRewards {
    error ZeroAddress();
    error ZeroAmount();
    error Unauthorized(address caller);
    error ContractExpected(address account);
    error InvalidSeries(uint256 seriesId);
    error NoRewards(address account, uint256 seriesId, address token);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event TreasurySet(address indexed previousTreasury, address indexed newTreasury);
    event Staked(address indexed account, uint256 indexed seriesId, uint256 amount);
    event Unstaked(address indexed account, uint256 indexed seriesId, uint256 amount);
    event RewardNotified(address indexed caller, uint256 indexed seriesId, address indexed token, uint256 amount);
    event RewardRoutedToTreasury(
        address indexed caller, uint256 indexed seriesId, address indexed token, uint256 amount
    );
    event RewardClaimed(address indexed account, uint256 indexed seriesId, address indexed token, uint256 amount);

    function notifyReward(address token, uint256 amount) external;

    function stake(uint256 amount) external returns (uint256 seriesId);

    function unstake(uint256 seriesId, uint256 amount) external;

    function claim(uint256 seriesId, address token) external returns (uint256 amount);

    function exit(uint256 seriesId, address token) external returns (uint256 amount);

    function previewClaim(address account, uint256 seriesId, address token) external view returns (uint256 amount);

    function stakedBalance(address account, uint256 seriesId) external view returns (uint256 amount);

    function totalStaked(uint256 seriesId) external view returns (uint256 amount);

    function activeSeriesId() external view returns (uint256 seriesId);
}
