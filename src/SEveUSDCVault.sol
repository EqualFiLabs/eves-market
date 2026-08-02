// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import {ISEveUSDCVault} from "./interfaces/ISEveUSDCVault.sol";
import {ISEveUSDCVaultLending} from "./interfaces/ISEveUSDCVaultLending.sol";
import {LibFixedPointMath} from "./libraries/LibFixedPointMath.sol";

contract SEveUSDCVault is ERC20, ReentrancyGuard, ISEveUSDCVault, ISEveUSDCVaultLending {
    using SafeERC20 for IERC20;

    uint256 internal constant WAD = 1e18;
    uint256 internal constant YEAR_BPS_DENOMINATOR = 365 * 10_000;
    uint256 internal constant DEFAULT_REWARD_TOKEN_REGISTRATION_FEE = 2_500e18;
    address internal immutable _asset;
    uint256 internal immutable _virtualAssets;
    uint256 internal immutable _virtualShares;

    address public immutable owner;
    address public immutable revenueNotifier;

    address public override feeRecipient;
    address public lendingContract;
    uint16 public override aumFeeBps;
    uint64 public constant override epochLength = 1 days;
    uint64 public override lastAccrualTimestamp;
    uint256 public override feeRemainderWad;
    uint256 public override unpaidAumFees;
    uint256 public override outstandingPrincipal;
    uint256 public override recognizedLosses;
    uint256 public override rewardTokenRegistrationFee;

    address[] internal _rewardTokens;
    mapping(address => RewardTokenStatus) public override rewardTokenStatus;
    mapping(address => uint256) public accRewardPerShare;
    mapping(address => uint256) public rewardRemainder;
    mapping(address => uint256) public rewardLiability;
    mapping(address => mapping(address => uint256)) public accruedRewards;
    mapping(address => mapping(address => uint256)) public rewardDebt;

    constructor(address asset_, address owner_, address feeRecipient_, uint16 aumFeeBps_, address revenueNotifier_)
        ERC20("sEVEUSDC", "sEVEUSDC")
    {
        _asset = asset_;
        _virtualAssets = 1;
        _virtualShares = 1;
        owner = owner_;
        feeRecipient = feeRecipient_;
        aumFeeBps = aumFeeBps_;
        revenueNotifier = revenueNotifier_;
        lastAccrualTimestamp = uint64(block.timestamp);
        rewardTokenRegistrationFee = DEFAULT_REWARD_TOKEN_REGISTRATION_FEE;
        rewardTokenStatus[asset_] = RewardTokenStatus.ACTIVE;
        _rewardTokens.push(asset_);
    }

    function decimals() public view override(ERC20, IERC20Metadata) returns (uint8) {
        return IERC20Metadata(_asset).decimals();
    }

    function asset() public view override returns (address) {
        return _asset;
    }

    function totalAssets() public view override returns (uint256) {
        uint256 grossAssets = IERC20(_asset).balanceOf(address(this)) + outstandingPrincipal;
        uint256 liabilities = recognizedLosses + unpaidAumFees;

        return grossAssets > liabilities ? grossAssets - liabilities : 0;
    }

    function maxDeposit(address) public pure override returns (uint256 maxAssets) {
        maxAssets = type(uint256).max;
    }

    function maxMint(address) public pure override returns (uint256 maxShares) {
        maxShares = type(uint256).max;
    }

    function maxWithdraw(address owner_) public view override returns (uint256 maxAssets) {
        uint256 ownerAssets =
            _convertToRedeemAssets(balanceOf(owner_), totalSupply(), _postAccrualAssets(), Math.Rounding.Floor);
        uint256 liquidAssets = _postAccrualLiquidAssets();
        maxAssets = ownerAssets < liquidAssets ? ownerAssets : liquidAssets;
    }

    function maxRedeem(address owner_) public view override returns (uint256 maxShares) {
        uint256 liquidShares = _convertToRedeemShares(
            _postAccrualLiquidAssets(), totalSupply(), _postAccrualAssets(), Math.Rounding.Floor
        );
        uint256 ownerShares = balanceOf(owner_);
        maxShares = ownerShares < liquidShares ? ownerShares : liquidShares;
    }

    function deposit(uint256 assets, address receiver) external override nonReentrant returns (uint256 shares) {
        if (assets == 0) {
            revert ZeroAmount();
        }

        _accrueAum();
        _enforceInitializedOrEmpty();

        shares = _convertToDepositShares(assets, totalSupply(), totalAssets(), Math.Rounding.Floor);
        if (shares == 0) {
            revert ZeroShares();
        }
        IERC20(_asset).safeTransferFrom(msg.sender, address(this), assets);
        _settlePayableAum();
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function mint(uint256 shares, address receiver) external override nonReentrant returns (uint256 assets) {
        if (shares == 0) {
            revert ZeroAmount();
        }

        _accrueAum();
        _enforceInitializedOrEmpty();

        assets = _convertToDepositAssets(shares, totalSupply(), totalAssets(), Math.Rounding.Ceil);
        IERC20(_asset).safeTransferFrom(msg.sender, address(this), assets);
        _settlePayableAum();
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

        _accrueAum();

        shares = _convertToRedeemShares(assets, totalSupply(), totalAssets(), Math.Rounding.Ceil);
        _consumeShareAllowance(owner_, msg.sender, shares);
        _burnShares(owner_, shares);
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

        _accrueAum();

        assets = _convertToRedeemAssets(shares, totalSupply(), totalAssets(), Math.Rounding.Floor);
        _consumeShareAllowance(owner_, msg.sender, shares);
        _burnShares(owner_, shares);
        IERC20(_asset).safeTransfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, owner_, assets, shares);
    }

    function previewDeposit(uint256 assets) external view override returns (uint256 shares) {
        shares = _convertToDepositShares(assets, totalSupply(), _postAccrualAssets(), Math.Rounding.Floor);
    }

    function previewMint(uint256 shares) external view override returns (uint256 assets) {
        assets = _convertToDepositAssets(shares, totalSupply(), _postAccrualAssets(), Math.Rounding.Ceil);
    }

    function previewWithdraw(uint256 assets) external view override returns (uint256 shares) {
        shares = _convertToRedeemShares(assets, totalSupply(), _postAccrualAssets(), Math.Rounding.Ceil);
    }

    function previewRedeem(uint256 shares) external view override returns (uint256 assets) {
        assets = _convertToRedeemAssets(shares, totalSupply(), _postAccrualAssets(), Math.Rounding.Floor);
    }

    function convertToShares(uint256 assets) external view override returns (uint256 shares) {
        shares = _convertToDepositShares(assets, totalSupply(), _postAccrualAssets(), Math.Rounding.Floor);
    }

    function convertToAssets(uint256 shares) external view override returns (uint256 assets) {
        assets = _convertToRedeemAssets(shares, totalSupply(), _postAccrualAssets(), Math.Rounding.Floor);
    }

    function accrueAum() external override nonReentrant returns (uint256 feeAssets) {
        feeAssets = _accrueAum();
    }

    function previewAccruedAum() public view override returns (uint256 feeAssets, uint256 epochs) {
        (, feeAssets, epochs,) = _previewAccrualState();
    }

    function notifyRevenue(uint256 assets) external override nonReentrant {
        _enforceRevenueNotifier();
        _notifyAssetRevenue(assets);
    }

    function notifyRevenue(address token, uint256 amount) external override nonReentrant {
        _enforceRevenueNotifier();
        if (token == _asset) {
            _notifyAssetRevenue(amount);
            return;
        }
        _notifyRewardRevenue(token, amount);
    }

    function registerRewardToken(address token) external override nonReentrant {
        if (token == address(0)) {
            revert ZeroAddress();
        }
        if (token.code.length == 0) {
            revert ContractHasNoCode(token);
        }
        if (rewardTokenStatus[token] != RewardTokenStatus.NONE) {
            revert RewardTokenAlreadyRegistered(token);
        }

        uint256 fee = rewardTokenRegistrationFee;
        if (fee != 0) {
            IERC20(_asset).safeTransferFrom(msg.sender, feeRecipient, fee);
        }

        rewardTokenStatus[token] = RewardTokenStatus.ACTIVE;
        _rewardTokens.push(token);

        emit RewardTokenRegistered(token, msg.sender, fee);
    }

    function disableRewardToken(address token) external override {
        _enforceOwner();
        if (rewardTokenStatus[token] != RewardTokenStatus.ACTIVE) {
            revert RewardTokenNotActive(token);
        }

        rewardTokenStatus[token] = RewardTokenStatus.DISABLED;
        emit RewardTokenStatusDisabled(token);
    }

    function setRewardTokenRegistrationFee(uint256 newFee) external override {
        _enforceOwner();
        uint256 previousFee = rewardTokenRegistrationFee;
        rewardTokenRegistrationFee = newFee;
        emit RewardTokenRegistrationFeeSet(previousFee, newFee);
    }

    function claimRewards(address[] calldata tokens, address receiver)
        external
        override
        nonReentrant
        returns (uint256[] memory amounts)
    {
        if (receiver == address(0)) {
            revert ZeroAddress();
        }

        uint256 length = tokens.length;
        amounts = new uint256[](length);
        for (uint256 index = 0; index < length; ++index) {
            address token = tokens[index];
            _checkpointReward(msg.sender, token);

            uint256 amount = accruedRewards[msg.sender][token];
            if (amount == 0) {
                revert NoRewardsClaimable(msg.sender, token);
            }

            accruedRewards[msg.sender][token] = 0;
            rewardLiability[token] -= amount;
            amounts[index] = amount;

            IERC20(token).safeTransfer(receiver, amount);
            emit RewardsClaimed(msg.sender, receiver, token, amount);
        }
    }

    function previewRewards(address account, address token) external view override returns (uint256 amount) {
        amount = accruedRewards[account][token];

        uint256 accumulated = Math.mulDiv(balanceOf(account), accRewardPerShare[token], WAD);
        uint256 debt = rewardDebt[account][token];
        if (accumulated > debt) {
            amount += accumulated - debt;
        }
    }

    function isRewardTokenActive(address token) external view override returns (bool active) {
        active = rewardTokenStatus[token] == RewardTokenStatus.ACTIVE;
    }

    function _notifyAssetRevenue(uint256 assets) internal {
        if (assets == 0) {
            revert ZeroAmount();
        }
        if (totalSupply() == 0) {
            revert VaultUninitialized();
        }

        _accrueAum();
        IERC20(_asset).safeTransferFrom(msg.sender, address(this), assets);
        _settlePayableAum();

        emit RevenueNotified(msg.sender, assets);
    }

    function _notifyRewardRevenue(address token, uint256 amount) internal {
        if (amount == 0) {
            revert ZeroAmount();
        }
        if (totalSupply() == 0) {
            revert VaultUninitialized();
        }
        RewardTokenStatus status = rewardTokenStatus[token];
        if (status == RewardTokenStatus.DISABLED) {
            revert RewardTokenDisabled(token);
        }
        if (status != RewardTokenStatus.ACTIVE) {
            revert RewardTokenNotActive(token);
        }

        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = IERC20(token).balanceOf(address(this)) - balanceBefore;
        if (received == 0) {
            revert ZeroAmount();
        }

        uint256 scaledReward = (received * WAD) + rewardRemainder[token];
        accRewardPerShare[token] += scaledReward / totalSupply();
        rewardRemainder[token] = scaledReward % totalSupply();
        rewardLiability[token] += received;

        emit RewardRevenueNotified(msg.sender, token, received);
    }

    function setAumFeeBps(uint16 newFeeBps) external override {
        _enforceOwner();
        _accrueAum();

        uint16 previousFeeBps = aumFeeBps;
        aumFeeBps = newFeeBps;

        emit AumFeeBpsSet(previousFeeBps, newFeeBps);
    }

    function setFeeRecipient(address newRecipient) external override {
        _enforceOwner();
        if (newRecipient == address(0)) {
            revert ZeroAddress();
        }

        address previousFeeRecipient = feeRecipient;
        feeRecipient = newRecipient;

        emit FeeRecipientSet(previousFeeRecipient, newRecipient);
    }

    function reportLoan(uint256 debtPrincipal) external override {
        _enforceLendingContract();
        outstandingPrincipal += debtPrincipal;
    }

    function reportRepayment(uint256 debtPrincipal) external override {
        _enforceLendingContract();
        outstandingPrincipal -= debtPrincipal;
        _settlePayableAum();
    }

    function reportDefault(uint256 debtPrincipal, uint256 recognizedLoss) external override {
        _enforceLendingContract();
        outstandingPrincipal -= debtPrincipal;
        recognizedLosses += recognizedLoss;
    }

    function settleDefault(uint256 debtPrincipal, uint256 collateralShares)
        external
        override
        nonReentrant
        returns (uint256 recoveredAssets, uint256 recognizedLoss)
    {
        _enforceLendingContract();

        _accrueAum();

        recoveredAssets = _convertToRedeemAssets(collateralShares, totalSupply(), totalAssets(), Math.Rounding.Floor);
        _burnShares(msg.sender, collateralShares);

        outstandingPrincipal -= debtPrincipal;
        recognizedLoss = recoveredAssets >= debtPrincipal ? 0 : debtPrincipal - recoveredAssets;
        recognizedLosses += recognizedLoss;
    }

    function disburseLoan(address recipient, uint256 borrowAmount, uint256 feeAmount) external override {
        _enforceLendingContract();

        if (borrowAmount != 0) {
            IERC20(_asset).safeTransfer(recipient, borrowAmount);
        }

        if (feeAmount != 0) {
            IERC20(_asset).safeTransfer(feeRecipient, feeAmount);
        }
    }

    function setLendingContract(address lending) external override {
        _enforceOwner();
        if (lending == address(0)) {
            revert ZeroAddress();
        }
        if (lending.code.length == 0) {
            revert ContractHasNoCode(lending);
        }

        address previousLending = lendingContract;
        lendingContract = lending;

        emit LendingContractSet(previousLending, lending);
    }

    function recoverPreBootstrapAssets(address receiver) external override nonReentrant returns (uint256 assets) {
        _enforceOwner();
        if (receiver == address(0)) {
            revert ZeroAddress();
        }
        if (totalSupply() != 0) {
            revert VaultUninitialized();
        }

        assets = IERC20(_asset).balanceOf(address(this));
        if (assets == 0) {
            revert ZeroAmount();
        }

        IERC20(_asset).safeTransfer(receiver, assets);
        emit PreBootstrapAssetsRecovered(receiver, assets);
    }

    function _accrueAum() internal returns (uint256 feeAssets) {
        uint256 epochs;
        uint256 remainderWad;

        (, feeAssets, epochs, remainderWad) = _previewAccrualState();

        if (epochs != 0) {
            lastAccrualTimestamp += uint64(epochs * epochLength);
            feeRemainderWad = remainderWad;
            unpaidAumFees += feeAssets;
        }

        _settlePayableAum();
    }

    function _previewAccrualState()
        internal
        view
        returns (uint256 assetsAfter, uint256 feeAssets, uint256 epochs, uint256 remainderWad)
    {
        uint256 assetsBefore = totalAssets();
        epochs = (block.timestamp - lastAccrualTimestamp) / epochLength;

        if (epochs == 0) {
            return (assetsBefore, 0, 0, feeRemainderWad);
        }

        if (assetsBefore == 0) {
            return (0, 0, epochs, feeRemainderWad);
        }

        uint256 retentionFactorWad = WAD - _dailyRateWad();
        uint256 retainedFactorPowWad = LibFixedPointMath.rpow(retentionFactorWad, epochs, WAD);
        uint256 preciseFeeWad = Math.mulDiv(assetsBefore, WAD - retainedFactorPowWad, 1) + feeRemainderWad;

        feeAssets = preciseFeeWad / WAD;
        remainderWad = preciseFeeWad % WAD;
        assetsAfter = assetsBefore - feeAssets;
    }

    function _postAccrualAssets() internal view returns (uint256 assetsAfter) {
        (assetsAfter,,,) = _previewAccrualState();
    }

    function _postAccrualLiquidAssets() internal view returns (uint256 liquidAssetsAfter) {
        uint256 idleAssets = IERC20(_asset).balanceOf(address(this));
        (, uint256 feeAssets,,) = _previewAccrualState();
        uint256 payableFees = unpaidAumFees + feeAssets;

        if (payableFees >= idleAssets) {
            return 0;
        }

        liquidAssetsAfter = idleAssets - payableFees;
    }

    function _settlePayableAum() internal returns (uint256 paidAssets) {
        uint256 outstandingFees = unpaidAumFees;
        if (outstandingFees == 0) {
            return 0;
        }

        uint256 idleAssets = IERC20(_asset).balanceOf(address(this));
        paidAssets = outstandingFees < idleAssets ? outstandingFees : idleAssets;
        if (paidAssets == 0) {
            return 0;
        }

        unpaidAumFees = outstandingFees - paidAssets;
        IERC20(_asset).safeTransfer(feeRecipient, paidAssets);
    }

    function _convertToDepositShares(uint256 assets, uint256 supply, uint256 managedAssets, Math.Rounding rounding)
        internal
        view
        returns (uint256 shares)
    {
        if (assets == 0) {
            return 0;
        }
        if (supply == 0) {
            return assets;
        }

        return Math.mulDiv(assets, supply + _virtualShares, managedAssets + _virtualAssets, rounding);
    }

    function _convertToDepositAssets(uint256 shares, uint256 supply, uint256 managedAssets, Math.Rounding rounding)
        internal
        view
        returns (uint256 assets)
    {
        if (shares == 0) {
            return 0;
        }
        if (supply == 0) {
            return shares;
        }

        return Math.mulDiv(shares, managedAssets + _virtualAssets, supply + _virtualShares, rounding);
    }

    function _convertToRedeemShares(uint256 assets, uint256 supply, uint256 managedAssets, Math.Rounding rounding)
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

        return Math.mulDiv(assets, supply, managedAssets, rounding);
    }

    function _convertToRedeemAssets(uint256 shares, uint256 supply, uint256 managedAssets, Math.Rounding rounding)
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

        return Math.mulDiv(shares, managedAssets, supply, rounding);
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

    function _burnShares(address owner_, uint256 shares) internal {
        uint256 available = balanceOf(owner_);
        if (available < shares) {
            revert InsufficientShares(owner_, shares, available);
        }

        _burn(owner_, shares);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0)) {
            _checkpointAllRewards(from);
        }
        if (to != address(0) && to != from) {
            _checkpointAllRewards(to);
        }

        super._update(from, to, value);

        if (from != address(0)) {
            _resetAllRewardDebt(from);
        }
        if (to != address(0) && to != from) {
            _resetAllRewardDebt(to);
        }
    }

    function _checkpointAllRewards(address account) internal {
        uint256 length = _rewardTokens.length;
        for (uint256 index = 0; index < length; ++index) {
            _checkpointReward(account, _rewardTokens[index]);
        }
    }

    function _checkpointReward(address account, address token) internal {
        uint256 accumulated = Math.mulDiv(balanceOf(account), accRewardPerShare[token], WAD);
        uint256 debt = rewardDebt[account][token];
        if (accumulated > debt) {
            accruedRewards[account][token] += accumulated - debt;
        }
        rewardDebt[account][token] = accumulated;
    }

    function _resetAllRewardDebt(address account) internal {
        uint256 balance = balanceOf(account);
        uint256 length = _rewardTokens.length;
        for (uint256 index = 0; index < length; ++index) {
            address token = _rewardTokens[index];
            rewardDebt[account][token] = Math.mulDiv(balance, accRewardPerShare[token], WAD);
        }
    }

    function _dailyRateWad() internal view returns (uint256) {
        return Math.mulDiv(uint256(aumFeeBps), WAD, YEAR_BPS_DENOMINATOR);
    }

    function _enforceOwner() internal view {
        if (msg.sender != owner) {
            revert NotOwner(msg.sender);
        }
    }

    function _enforceRevenueNotifier() internal view {
        if (msg.sender != revenueNotifier) {
            revert UnauthorizedRevenueNotifier(msg.sender);
        }
    }

    function _enforceLendingContract() internal view {
        if (msg.sender != lendingContract) {
            revert NotLendingContract(msg.sender);
        }
    }

    function _enforceInitializedOrEmpty() internal view {
        if (totalSupply() == 0) {
            uint256 managedAssets = totalAssets();
            if (managedAssets != 0) {
                revert VaultUninitializedWithAssets(managedAssets);
            }
        }
    }
}
