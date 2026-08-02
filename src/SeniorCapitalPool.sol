// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import {ISeniorCapitalPool} from "./interfaces/ISeniorCapitalPool.sol";

/// @notice Senior eveUSDC capital pool for the margin-layer replacement path.
/// @dev Phase 1 keeps this standalone: no lending hooks, reward indexes, AUM fee, or deploy-script cutover.
contract SeniorCapitalPool is ERC20, ReentrancyGuard, ISeniorCapitalPool {
    using SafeERC20 for IERC20;

    uint256 internal constant VIRTUAL_ASSETS = 1;
    uint256 internal constant VIRTUAL_SHARES = 1;

    address internal immutable _asset;

    address public immutable override owner;
    address public override riskManager;

    uint256 public override reservedCapital;
    uint256 public override activeExposure;
    uint256 public override recoveryAllocation;
    uint256 public override insuranceAllocation;
    uint256 public override realizedLosses;

    mapping(bytes32 => PoolBucketAccounting) internal _bucketAccounting;

    constructor(address asset_, address owner_, address riskManager_) ERC20("Senior eveUSDC Pool", "seveUSDC") {
        if (asset_ == address(0) || owner_ == address(0) || riskManager_ == address(0)) {
            revert ZeroAddress();
        }
        if (asset_.code.length == 0 || riskManager_.code.length == 0) {
            revert ContractHasNoCode(asset_.code.length == 0 ? asset_ : riskManager_);
        }

        _asset = asset_;
        owner = owner_;
        riskManager = riskManager_;
    }

    function decimals() public view override returns (uint8) {
        return IERC20Metadata(_asset).decimals();
    }

    function asset() external view override returns (address) {
        return _asset;
    }

    function totalAssets() public view override returns (uint256 assets) {
        uint256 liabilities = recoveryAllocation + insuranceAllocation;
        uint256 grossAssets = IERC20(_asset).balanceOf(address(this)) + activeExposure;

        assets = grossAssets > liabilities ? grossAssets - liabilities : 0;
    }

    function availableCapital() public view override returns (uint256 assets) {
        uint256 encumbered = reservedCapital + recoveryAllocation + insuranceAllocation;
        uint256 liquidAssets = IERC20(_asset).balanceOf(address(this));

        assets = liquidAssets > encumbered ? liquidAssets - encumbered : 0;
    }

    function bucketAccounting(bytes32 bucketId)
        external
        view
        override
        returns (PoolBucketAccounting memory accounting)
    {
        accounting = _bucketAccounting[bucketId];
    }

    function maxDeposit(address) external pure override returns (uint256 assets) {
        assets = type(uint256).max;
    }

    function maxMint(address) external pure override returns (uint256 shares) {
        shares = type(uint256).max;
    }

    function maxWithdraw(address owner_) public view override returns (uint256 assets) {
        uint256 ownerAssets = _convertToAssets(balanceOf(owner_), totalSupply(), totalAssets(), Math.Rounding.Floor);
        uint256 liquidAssets = availableCapital();

        assets = ownerAssets < liquidAssets ? ownerAssets : liquidAssets;
    }

    function maxRedeem(address owner_) public view override returns (uint256 shares) {
        uint256 liquidShares = _convertToShares(availableCapital(), totalSupply(), totalAssets(), Math.Rounding.Floor);
        uint256 ownerShares = balanceOf(owner_);

        shares = ownerShares < liquidShares ? ownerShares : liquidShares;
    }

    function convertToShares(uint256 assets) external view override returns (uint256 shares) {
        shares = _convertToShares(assets, totalSupply(), totalAssets(), Math.Rounding.Floor);
    }

    function convertToAssets(uint256 shares) external view override returns (uint256 assets) {
        assets = _convertToAssets(shares, totalSupply(), totalAssets(), Math.Rounding.Floor);
    }

    function previewDeposit(uint256 assets) public view override returns (uint256 shares) {
        shares = _convertToShares(assets, totalSupply(), totalAssets(), Math.Rounding.Floor);
    }

    function previewMint(uint256 shares) external view override returns (uint256 assets) {
        assets = _convertToAssets(shares, totalSupply(), totalAssets(), Math.Rounding.Ceil);
    }

    function previewWithdraw(uint256 assets) public view override returns (uint256 shares) {
        shares = _convertToShares(assets, totalSupply(), totalAssets(), Math.Rounding.Ceil);
    }

    function previewRedeem(uint256 shares) public view override returns (uint256 assets) {
        assets = _convertToAssets(shares, totalSupply(), totalAssets(), Math.Rounding.Floor);
    }

    function deposit(uint256 assets, address receiver) external override nonReentrant returns (uint256 shares) {
        if (assets == 0) {
            revert ZeroAmount();
        }
        if (receiver == address(0)) {
            revert ZeroAddress();
        }

        _enforceInitializedOrEmpty();

        shares = previewDeposit(assets);
        if (shares == 0) {
            revert ZeroShares();
        }

        IERC20(_asset).safeTransferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function mint(uint256 shares, address receiver) external override nonReentrant returns (uint256 assets) {
        if (shares == 0) {
            revert ZeroAmount();
        }
        if (receiver == address(0)) {
            revert ZeroAddress();
        }

        _enforceInitializedOrEmpty();

        assets = _convertToAssets(shares, totalSupply(), totalAssets(), Math.Rounding.Ceil);
        if (assets == 0) {
            revert ZeroAssets();
        }

        IERC20(_asset).safeTransferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function withdraw(uint256 assets, address receiver, address owner_)
        external
        override
        nonReentrant
        returns (uint256 shares)
    {
        if (assets == 0) {
            revert ZeroAmount();
        }
        if (receiver == address(0) || owner_ == address(0)) {
            revert ZeroAddress();
        }

        uint256 available = availableCapital();
        if (assets > available) {
            revert InsufficientAvailableCapital(assets, available);
        }

        shares = previewWithdraw(assets);
        _consumeShareAllowance(owner_, msg.sender, shares);
        _burn(owner_, shares);
        IERC20(_asset).safeTransfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, owner_, assets, shares);
    }

    function redeem(uint256 shares, address receiver, address owner_)
        external
        override
        nonReentrant
        returns (uint256 assets)
    {
        if (shares == 0) {
            revert ZeroAmount();
        }
        if (receiver == address(0) || owner_ == address(0)) {
            revert ZeroAddress();
        }

        assets = previewRedeem(shares);
        if (assets == 0) {
            revert ZeroAssets();
        }

        uint256 available = availableCapital();
        if (assets > available) {
            revert InsufficientAvailableCapital(assets, available);
        }

        _consumeShareAllowance(owner_, msg.sender, shares);
        _burn(owner_, shares);
        IERC20(_asset).safeTransfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, owner_, assets, shares);
    }

    function notifyRevenue(uint256 assets) public override nonReentrant {
        _receiveAssetRevenue(assets);
        emit RevenueNotified(msg.sender, assets);
    }

    function notifyRevenue(address token, uint256 amount) external override nonReentrant {
        if (token != _asset) {
            revert InvalidRevenueAsset(token);
        }

        _receiveAssetRevenue(amount);
        emit RevenueNotified(msg.sender, amount);
    }

    function sponsorAssetRevenue(uint256 assets) external override nonReentrant {
        _receiveAssetRevenue(assets);
        emit AssetRevenueSponsored(msg.sender, assets);
    }

    function setRiskManager(address newRiskManager) external override {
        _enforceOwner();
        if (newRiskManager == address(0)) {
            revert ZeroAddress();
        }
        if (newRiskManager.code.length == 0) {
            revert ContractHasNoCode(newRiskManager);
        }

        address previousRiskManager = riskManager;
        riskManager = newRiskManager;

        emit RiskManagerSet(previousRiskManager, newRiskManager);
    }

    function reserveCapital(uint256 assets) external override {
        _enforceRiskManager();
        _reserveCapital(bytes32(0), assets);
        emit CapitalReserved(msg.sender, assets);
    }

    function releaseReservedCapital(uint256 assets) external override {
        _enforceRiskManager();
        _releaseReservedCapital(bytes32(0), assets);
        emit ReservedCapitalReleased(msg.sender, assets);
    }

    function increaseActiveExposure(uint256 assets) external override nonReentrant {
        _enforceRiskManager();
        _requireAmount(assets);
        uint256 available = availableCapital();
        if (assets > available) {
            revert InsufficientAvailableCapital(assets, available);
        }
        activeExposure += assets;
        _bucketAccounting[bytes32(0)].activeExposure += assets;
        IERC20(_asset).safeTransfer(msg.sender, assets);
        emit ActiveExposureIncreased(msg.sender, assets);
    }

    function releaseActiveExposure(uint256 assets) external override nonReentrant {
        _enforceRiskManager();
        _repayActiveExposure(bytes32(0), assets);
        emit ActiveExposureReleased(msg.sender, assets);
    }

    function recordRealizedLoss(uint256 assets) external override {
        _enforceRiskManager();
        _recordRealizedLoss(bytes32(0), assets);
        emit RealizedLossRecorded(msg.sender, assets);
    }

    function allocateRecovery(uint256 assets) external override {
        _enforceRiskManager();
        if (assets == 0) {
            revert ZeroAmount();
        }

        uint256 available = availableCapital();
        if (assets > available) {
            revert InsufficientAvailableCapital(assets, available);
        }

        recoveryAllocation += assets;
        emit RecoveryAllocated(msg.sender, assets);
    }

    function releaseRecoveryAllocation(uint256 assets) external override {
        _enforceRiskManager();
        if (assets == 0) {
            revert ZeroAmount();
        }

        uint256 allocated = recoveryAllocation;
        if (assets > allocated) {
            revert InsufficientRecoveryAllocation(assets, allocated);
        }

        recoveryAllocation = allocated - assets;
        emit RecoveryAllocationReleased(msg.sender, assets);
    }

    function allocateInsurance(uint256 assets) external override {
        _enforceRiskManager();
        if (assets == 0) {
            revert ZeroAmount();
        }

        uint256 available = availableCapital();
        if (assets > available) {
            revert InsufficientAvailableCapital(assets, available);
        }

        insuranceAllocation += assets;
        emit InsuranceAllocated(msg.sender, assets);
    }

    function releaseInsuranceAllocation(uint256 assets) external override {
        _enforceRiskManager();
        if (assets == 0) {
            revert ZeroAmount();
        }

        uint256 allocated = insuranceAllocation;
        if (assets > allocated) {
            revert InsufficientInsuranceAllocation(assets, allocated);
        }

        insuranceAllocation = allocated - assets;
        emit InsuranceAllocationReleased(msg.sender, assets);
    }

    function reserveCapitalForBucket(bytes32 bucketId, uint256 assets) external override {
        _enforceRiskManager();
        _reserveCapital(bucketId, assets);
        emit BucketCapitalReserved(bucketId, msg.sender, assets);
    }

    function releaseReservedCapitalForBucket(bytes32 bucketId, uint256 assets) external override {
        _enforceRiskManager();
        _releaseReservedCapital(bucketId, assets);
        emit BucketReservedCapitalReleased(bucketId, msg.sender, assets);
    }

    function deployReservedCapitalForBucket(bytes32 bucketId, address receiver, uint256 assets)
        external
        override
        nonReentrant
    {
        _enforceRiskManager();
        if (receiver == address(0)) {
            revert ZeroAddress();
        }
        _deployReservedCapital(bucketId, receiver, assets);
        emit BucketCapitalDeployed(bucketId, msg.sender, receiver, assets);
    }

    function repayActiveExposureForBucket(bytes32 bucketId, uint256 assets) external override nonReentrant {
        _enforceRiskManager();
        _repayActiveExposure(bucketId, assets);
        emit BucketActiveExposureRepaid(bucketId, msg.sender, assets);
    }

    function recordRealizedLossForBucket(bytes32 bucketId, uint256 assets) external override {
        _enforceRiskManager();
        _recordRealizedLoss(bucketId, assets);
        emit BucketRealizedLossRecorded(bucketId, msg.sender, assets);
    }

    function recoverPreBootstrapAssets(address receiver) external override nonReentrant returns (uint256 assets) {
        _enforceOwner();
        if (receiver == address(0)) {
            revert ZeroAddress();
        }
        if (totalSupply() != 0) {
            revert PoolUninitialized();
        }
        if (
            reservedCapital != 0 || activeExposure != 0 || recoveryAllocation != 0 || insuranceAllocation != 0
                || realizedLosses != 0
        ) {
            revert OutstandingPoolAccounting();
        }

        assets = IERC20(_asset).balanceOf(address(this));
        if (assets == 0) {
            revert ZeroAmount();
        }

        IERC20(_asset).safeTransfer(receiver, assets);
        emit PreBootstrapAssetsRecovered(receiver, assets);
    }

    function _receiveAssetRevenue(uint256 assets) internal {
        if (assets == 0) {
            revert ZeroAmount();
        }
        if (totalSupply() == 0) {
            revert PoolUninitialized();
        }

        IERC20(_asset).safeTransferFrom(msg.sender, address(this), assets);
    }

    function _reserveCapital(bytes32 bucketId, uint256 assets) internal {
        _requireAmount(assets);
        uint256 available = availableCapital();
        if (assets > available) {
            revert InsufficientAvailableCapital(assets, available);
        }

        reservedCapital += assets;
        _bucketAccounting[bucketId].reservedCapital += assets;
    }

    function _releaseReservedCapital(bytes32 bucketId, uint256 assets) internal {
        _requireAmount(assets);
        PoolBucketAccounting storage bucket = _bucketAccounting[bucketId];
        if (assets > bucket.reservedCapital) {
            revert InsufficientReservedCapital(assets, bucket.reservedCapital);
        }

        bucket.reservedCapital -= assets;
        reservedCapital -= assets;
    }

    function _deployReservedCapital(bytes32 bucketId, address receiver, uint256 assets) internal {
        _requireAmount(assets);
        PoolBucketAccounting storage bucket = _bucketAccounting[bucketId];
        if (assets > bucket.reservedCapital) {
            revert InsufficientReservedCapital(assets, bucket.reservedCapital);
        }

        bucket.reservedCapital -= assets;
        bucket.activeExposure += assets;
        reservedCapital -= assets;
        activeExposure += assets;
        IERC20(_asset).safeTransfer(receiver, assets);
    }

    function _repayActiveExposure(bytes32 bucketId, uint256 assets) internal {
        _requireAmount(assets);
        PoolBucketAccounting storage bucket = _bucketAccounting[bucketId];
        if (assets > bucket.activeExposure) {
            revert InsufficientActiveExposure(assets, bucket.activeExposure);
        }

        IERC20(_asset).safeTransferFrom(msg.sender, address(this), assets);
        bucket.activeExposure -= assets;
        activeExposure -= assets;
    }

    function _recordRealizedLoss(bytes32 bucketId, uint256 assets) internal {
        _requireAmount(assets);
        PoolBucketAccounting storage bucket = _bucketAccounting[bucketId];
        if (assets > bucket.activeExposure) {
            revert InsufficientActiveExposure(assets, bucket.activeExposure);
        }

        bucket.activeExposure -= assets;
        bucket.realizedLosses += assets;
        activeExposure -= assets;
        realizedLosses += assets;
    }

    function _requireAmount(uint256 assets) internal pure {
        if (assets == 0) {
            revert ZeroAmount();
        }
    }

    function _convertToShares(uint256 assets, uint256 supply, uint256 managedAssets, Math.Rounding rounding)
        internal
        pure
        returns (uint256 shares)
    {
        if (assets == 0) {
            return 0;
        }
        if (supply == 0) {
            return assets;
        }

        shares = Math.mulDiv(assets, supply + VIRTUAL_SHARES, managedAssets + VIRTUAL_ASSETS, rounding);
    }

    function _convertToAssets(uint256 shares, uint256 supply, uint256 managedAssets, Math.Rounding rounding)
        internal
        pure
        returns (uint256 assets)
    {
        if (shares == 0) {
            return 0;
        }
        if (supply == 0) {
            return shares;
        }

        assets = Math.mulDiv(shares, managedAssets + VIRTUAL_ASSETS, supply + VIRTUAL_SHARES, rounding);
    }

    function _consumeShareAllowance(address owner_, address caller, uint256 shares) internal {
        if (caller == owner_) {
            return;
        }

        uint256 currentAllowance = allowance(owner_, caller);
        if (currentAllowance < shares) {
            revert InsufficientAllowance(caller, owner_, shares, currentAllowance);
        }

        if (currentAllowance != type(uint256).max) {
            _approve(owner_, caller, currentAllowance - shares);
        }
    }

    function _enforceInitializedOrEmpty() internal view {
        if (totalSupply() == 0) {
            uint256 assets = IERC20(_asset).balanceOf(address(this));
            if (assets != 0) {
                revert PreBootstrapAssetsPresent(assets);
            }
        }
    }

    function _enforceOwner() internal view {
        if (msg.sender != owner) {
            revert NotOwner(msg.sender);
        }
    }

    function _enforceRiskManager() internal view {
        if (msg.sender != riskManager) {
            revert NotRiskManager(msg.sender);
        }
    }
}
