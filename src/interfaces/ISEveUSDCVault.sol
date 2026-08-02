// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC4626} from "../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

/// @notice Deprecated experimental staking vault interface retained for transition to the senior margin pool.
interface ISEveUSDCVault is IERC4626 {
    error ZeroAmount();
    error ZeroShares();
    error InsufficientShares(address owner, uint256 required, uint256 available);
    error InsufficientAllowance(address caller, address owner, uint256 required, uint256 available);
    error UnauthorizedRevenueNotifier(address caller);
    error NotOwner(address caller);
    error ZeroAddress();
    error ContractHasNoCode(address account);
    error VaultUninitialized();
    error VaultUninitializedWithAssets(uint256 assets);
    error RewardTokenAlreadyRegistered(address token);
    error RewardTokenNotActive(address token);
    error RewardTokenDisabled(address token);
    error AssetRewardMustUseAssetRevenue(address token);
    error NoRewardsClaimable(address account, address token);

    event RevenueNotified(address indexed caller, uint256 assets);
    event RewardRevenueNotified(address indexed caller, address indexed token, uint256 amount);
    event AssetRevenueSponsored(address indexed sponsor, uint256 assets);
    event RewardSponsored(address indexed sponsor, address indexed token, uint256 amount);
    event RewardTokenRegistered(address indexed token, address indexed registrant, uint256 fee);
    event RewardTokenStatusDisabled(address indexed token);
    event RewardTokenRegistrationFeeSet(uint256 previousFee, uint256 newFee);
    event RewardsClaimed(address indexed account, address indexed receiver, address indexed token, uint256 amount);
    event AumFeeBpsSet(uint16 previousFeeBps, uint16 newFeeBps);
    event FeeRecipientSet(address indexed previousFeeRecipient, address indexed newFeeRecipient);
    event PreBootstrapAssetsRecovered(address indexed receiver, uint256 assets);
    enum RewardTokenStatus {
        NONE,
        ACTIVE,
        DISABLED
    }

    function accrueAum() external returns (uint256 feeAssets);

    function previewAccruedAum() external view returns (uint256 feeAssets, uint256 epochs);

    function notifyRevenue(uint256 assets) external;

    function notifyRevenue(address token, uint256 amount) external;

    function sponsorAssetRevenue(uint256 assets) external;

    function sponsorReward(address token, uint256 amount) external returns (uint256 received);

    function registerRewardToken(address token) external;

    function disableRewardToken(address token) external;

    function setRewardTokenRegistrationFee(uint256 newFee) external;

    function claimRewards(address[] calldata tokens, address receiver) external returns (uint256[] memory amounts);

    function previewRewards(address account, address token) external view returns (uint256 amount);

    function rewardTokenStatus(address token) external view returns (RewardTokenStatus status);

    function isRewardTokenActive(address token) external view returns (bool active);

    function rewardTokenRegistrationFee() external view returns (uint256);

    function setAumFeeBps(uint16 newFeeBps) external;

    function setFeeRecipient(address newRecipient) external;

    function recoverPreBootstrapAssets(address receiver) external returns (uint256 assets);

    function aumFeeBps() external view returns (uint16);

    function feeRecipient() external view returns (address);

    function epochLength() external view returns (uint64);

    function lastAccrualTimestamp() external view returns (uint64);

    function feeRemainderWad() external view returns (uint256);

    function unpaidAumFees() external view returns (uint256);
}
