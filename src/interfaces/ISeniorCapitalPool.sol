// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface ISeniorCapitalPool is IERC20 {
    error ZeroAmount();
    error ZeroShares();
    error ZeroAssets();
    error ZeroAddress();
    error ContractHasNoCode(address account);
    error NotOwner(address caller);
    error NotRiskManager(address caller);
    error PoolUninitialized();
    error OutstandingPoolAccounting();
    error PreBootstrapAssetsPresent(uint256 assets);
    error InvalidRevenueAsset(address token);
    error InsufficientAllowance(address caller, address owner, uint256 required, uint256 available);
    error InsufficientAvailableCapital(uint256 required, uint256 available);
    error InsufficientReservedCapital(uint256 required, uint256 available);
    error InsufficientActiveExposure(uint256 required, uint256 available);
    error InsufficientRecoveryAllocation(uint256 required, uint256 available);
    error InsufficientInsuranceAllocation(uint256 required, uint256 available);

    struct PoolBucketAccounting {
        uint256 reservedCapital;
        uint256 activeExposure;
        uint256 recoveryAllocation;
        uint256 insuranceAllocation;
        uint256 realizedLosses;
    }

    event Deposit(address indexed caller, address indexed receiver, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );
    event RevenueNotified(address indexed caller, uint256 assets);
    event AssetRevenueSponsored(address indexed sponsor, uint256 assets);
    event RiskManagerSet(address indexed previousRiskManager, address indexed newRiskManager);
    event CapitalReserved(address indexed caller, uint256 assets);
    event ReservedCapitalReleased(address indexed caller, uint256 assets);
    event ActiveExposureIncreased(address indexed caller, uint256 assets);
    event ActiveExposureReleased(address indexed caller, uint256 assets);
    event RealizedLossRecorded(address indexed caller, uint256 assets);
    event RecoveryAllocated(address indexed caller, uint256 assets);
    event RecoveryAllocationReleased(address indexed caller, uint256 assets);
    event InsuranceAllocated(address indexed caller, uint256 assets);
    event InsuranceAllocationReleased(address indexed caller, uint256 assets);
    event PreBootstrapAssetsRecovered(address indexed receiver, uint256 assets);
    event BucketCapitalReserved(bytes32 indexed bucketId, address indexed caller, uint256 assets);
    event BucketReservedCapitalReleased(bytes32 indexed bucketId, address indexed caller, uint256 assets);
    event BucketCapitalDeployed(
        bytes32 indexed bucketId, address indexed caller, address indexed receiver, uint256 assets
    );
    event BucketActiveExposureRepaid(bytes32 indexed bucketId, address indexed caller, uint256 assets);
    event BucketRealizedLossRecorded(bytes32 indexed bucketId, address indexed caller, uint256 assets);

    function asset() external view returns (address);

    function owner() external view returns (address);

    function riskManager() external view returns (address);

    function totalAssets() external view returns (uint256 assets);

    function availableCapital() external view returns (uint256 assets);

    function reservedCapital() external view returns (uint256 assets);

    function activeExposure() external view returns (uint256 assets);

    function recoveryAllocation() external view returns (uint256 assets);

    function insuranceAllocation() external view returns (uint256 assets);

    function realizedLosses() external view returns (uint256 assets);

    function bucketAccounting(bytes32 bucketId) external view returns (PoolBucketAccounting memory accounting);

    function maxDeposit(address receiver) external view returns (uint256 assets);

    function maxMint(address receiver) external view returns (uint256 shares);

    function maxWithdraw(address owner_) external view returns (uint256 assets);

    function maxRedeem(address owner_) external view returns (uint256 shares);

    function convertToShares(uint256 assets) external view returns (uint256 shares);

    function convertToAssets(uint256 shares) external view returns (uint256 assets);

    function previewDeposit(uint256 assets) external view returns (uint256 shares);

    function previewMint(uint256 shares) external view returns (uint256 assets);

    function previewWithdraw(uint256 assets) external view returns (uint256 shares);

    function previewRedeem(uint256 shares) external view returns (uint256 assets);

    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    function mint(uint256 shares, address receiver) external returns (uint256 assets);

    function withdraw(uint256 assets, address receiver, address owner_) external returns (uint256 shares);

    function redeem(uint256 shares, address receiver, address owner_) external returns (uint256 assets);

    function notifyRevenue(uint256 assets) external;

    function notifyRevenue(address token, uint256 amount) external;

    function sponsorAssetRevenue(uint256 assets) external;

    function setRiskManager(address newRiskManager) external;

    function reserveCapital(uint256 assets) external;

    function releaseReservedCapital(uint256 assets) external;

    function increaseActiveExposure(uint256 assets) external;

    function releaseActiveExposure(uint256 assets) external;

    function recordRealizedLoss(uint256 assets) external;

    function allocateRecovery(uint256 assets) external;

    function releaseRecoveryAllocation(uint256 assets) external;

    function allocateInsurance(uint256 assets) external;

    function releaseInsuranceAllocation(uint256 assets) external;

    function reserveCapitalForBucket(bytes32 bucketId, uint256 assets) external;

    function releaseReservedCapitalForBucket(bytes32 bucketId, uint256 assets) external;

    function deployReservedCapitalForBucket(bytes32 bucketId, address receiver, uint256 assets) external;

    function repayActiveExposureForBucket(bytes32 bucketId, uint256 assets) external;

    function recordRealizedLossForBucket(bytes32 bucketId, uint256 assets) external;

    function recoverPreBootstrapAssets(address receiver) external returns (uint256 assets);
}
