// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Math} from "../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

import {IETHUSDOracle} from "./interfaces/IETHUSDOracle.sol";
import {IEveRiskShares} from "./interfaces/IEveRiskShares.sol";
import {IEveUSD} from "./interfaces/IEveUSD.sol";
import {IEveUSDPool} from "./interfaces/IEveUSDPool.sol";

contract EveUSDPool is IEveUSDPool, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant WAD = 1e18;
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant MAX_FEE_BPS = 1_000;
    uint256 public constant MIN_COLLATERAL_RATIO_BPS = 10_001;
    uint256 public constant MAX_COLLATERAL_RATIO_BPS = 30_000;
    uint256 public constant MIN_RECOVERY_TRIGGER_BPS = 1;
    uint256 public constant MAX_RECOVERY_TRIGGER_BPS = 9_999;
    uint256 public constant MIN_RECOVERY_TIMELOCK = 1 days;
    uint256 public constant MAX_RECOVERY_TIMELOCK = 30 days;

    address public immutable weth;
    address public immutable eveUSD;
    address public immutable evRisk;

    address public oracle;
    address public owner;
    address public feeRecipient;
    uint256 public nextSeriesCollateralRatioBps;
    uint256 public nextSeriesRecoveryTriggerBps;
    uint256 public recoveryTimelock;
    uint256 public mintFeeBps;
    uint256 public recombinationFeeBps;
    uint256 public accountedCollateral;
    uint256 public currentRiskSeriesId;
    bool public configLocked;

    mapping(uint256 seriesId => RiskSeries series) internal _riskSeries;
    mapping(uint256 seriesId => mapping(address account => uint256 shares)) internal _returnedShares;

    constructor(
        address weth_,
        address eveUSD_,
        address evRisk_,
        address oracle_,
        address owner_,
        uint256 collateralRatioBps_,
        uint256 recoveryTriggerBps_
    ) {
        _requireContract(weth_);
        _requireContract(eveUSD_);
        _requireContract(evRisk_);
        _requireContract(oracle_);
        if (owner_ == address(0)) revert ZeroAddress();
        _validateCollateralRatio(collateralRatioBps_);
        _validateRecoveryTrigger(recoveryTriggerBps_);
        _requireEveUSDPool(eveUSD_);
        _requireEvRiskPool(evRisk_);

        weth = weth_;
        eveUSD = eveUSD_;
        evRisk = evRisk_;
        oracle = oracle_;
        owner = owner_;
        feeRecipient = owner_;
        nextSeriesCollateralRatioBps = collateralRatioBps_;
        nextSeriesRecoveryTriggerBps = recoveryTriggerBps_;
        recoveryTimelock = 7 days;
        currentRiskSeriesId = 1;

        uint256 priceWad = IETHUSDOracle(oracle_).ethUsdPriceWad();
        _createSeries(1, priceWad, collateralRatioBps_, recoveryTriggerBps_, SeriesStatus.Active);

        emit OwnershipTransferred(address(0), owner_);
        emit FeeRecipientSet(owner_);
        emit OracleSet(oracle_);
        emit NextSeriesConfigSet(collateralRatioBps_, recoveryTriggerBps_);
        emit RecoveryTimelockSet(recoveryTimelock);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized(msg.sender);
        _;
    }

    modifier whenConfigUnlocked() {
        if (configLocked) revert ConfigLocked();
        _;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        address previousOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(previousOwner, newOwner);
    }

    function lockConfig() external onlyOwner {
        configLocked = true;
        emit ConfigLockedForever(msg.sender);
    }

    function setOracle(address newOracle) external onlyOwner whenConfigUnlocked {
        _requireContract(newOracle);
        oracle = newOracle;
        emit OracleSet(newOracle);
    }

    function setNextSeriesConfig(uint256 newCollateralRatioBps, uint256 newRecoveryTriggerBps)
        external
        onlyOwner
        whenConfigUnlocked
    {
        _validateCollateralRatio(newCollateralRatioBps);
        _validateRecoveryTrigger(newRecoveryTriggerBps);
        nextSeriesCollateralRatioBps = newCollateralRatioBps;
        nextSeriesRecoveryTriggerBps = newRecoveryTriggerBps;
        emit NextSeriesConfigSet(newCollateralRatioBps, newRecoveryTriggerBps);
    }

    function setRecoveryTimelock(uint256 newRecoveryTimelock) external onlyOwner whenConfigUnlocked {
        _validateRecoveryTimelock(newRecoveryTimelock);
        recoveryTimelock = newRecoveryTimelock;
        emit RecoveryTimelockSet(newRecoveryTimelock);
    }

    function setFeeRecipient(address newFeeRecipient) external onlyOwner whenConfigUnlocked {
        if (newFeeRecipient == address(0)) revert ZeroAddress();
        feeRecipient = newFeeRecipient;
        emit FeeRecipientSet(newFeeRecipient);
    }

    function setFeeBps(uint256 newMintFeeBps, uint256 newRecombinationFeeBps)
        external
        onlyOwner
        whenConfigUnlocked
    {
        _validateFeeBps(newMintFeeBps);
        _validateFeeBps(newRecombinationFeeBps);
        mintFeeBps = newMintFeeBps;
        recombinationFeeBps = newRecombinationFeeBps;
        emit FeeBpsSet(newMintFeeBps, newRecombinationFeeBps);
    }

    function depositWETH(uint256 wethAmount, address eveUSDReceiver, address shareReceiver)
        external
        nonReentrant
        returns (uint256 seriesId, uint256 eveUSDMinted, uint256 sharesMinted)
    {
        if (eveUSDReceiver == address(0) || shareReceiver == address(0)) revert ZeroAddress();
        DepositPreview memory preview = previewDeposit(wethAmount);

        IERC20(weth).safeTransferFrom(msg.sender, address(this), wethAmount);
        accountedCollateral += wethAmount - preview.feeAmount;
        _riskSeries[preview.seriesId].accountedCollateral += wethAmount - preview.feeAmount;
        _riskSeries[preview.seriesId].eveUSDSupply += preview.eveUSDMinted;
        _riskSeries[preview.seriesId].sharesSupply += preview.sharesMinted;
        _collectFee(msg.sender, preview.feeAmount);
        IEveUSD(eveUSD).mint(eveUSDReceiver, preview.eveUSDMinted);
        IEveRiskShares(evRisk).mint(shareReceiver, preview.seriesId, preview.sharesMinted);

        emit Deposited(
            msg.sender,
            eveUSDReceiver,
            shareReceiver,
            preview.seriesId,
            wethAmount,
            preview.eveUSDMinted,
            preview.sharesMinted,
            preview.priceWad,
            preview.wethPerPairWad
        );

        return (preview.seriesId, preview.eveUSDMinted, preview.sharesMinted);
    }

    function recombine(uint256 seriesId, uint256 eveUSDAmount, uint256 shareAmount, address receiver)
        external
        nonReentrant
        returns (uint256 wethOut)
    {
        if (receiver == address(0)) revert ZeroAddress();
        RedemptionPreview memory preview = previewRecombine(seriesId, eveUSDAmount);
        if (shareAmount != preview.sharesBurned) {
            revert InvalidShareAmount(shareAmount, preview.sharesBurned);
        }

        uint256 grossCollateralOut = preview.collateralOut + preview.feeAmount;
        RiskSeries storage series = _riskSeries[seriesId];
        series.eveUSDSupply -= eveUSDAmount;
        series.sharesSupply -= shareAmount;
        series.accountedCollateral -= grossCollateralOut;
        accountedCollateral -= grossCollateralOut;

        IEveUSD(eveUSD).burn(msg.sender, eveUSDAmount);
        IEveRiskShares(evRisk).burn(msg.sender, seriesId, shareAmount);
        _collectFee(msg.sender, preview.feeAmount);
        IERC20(weth).safeTransfer(receiver, preview.collateralOut);

        emit Recombined(
            msg.sender,
            receiver,
            seriesId,
            eveUSDAmount,
            shareAmount,
            preview.collateralOut,
            preview.collateralRatioBpsAfter
        );

        return preview.collateralOut;
    }

    function startRecovery(uint256 seriesId) external nonReentrant {
        RiskSeries storage series = _riskSeries[seriesId];
        _requireSeriesStatus(seriesId, SeriesStatus.Active);
        uint256 priceWad = IETHUSDOracle(oracle).ethUsdPriceWad();
        uint256 triggerPrice = _triggerPrice(series);
        if (priceWad > triggerPrice) revert RecoveryNotEligible(priceWad, triggerPrice);

        series.status = SeriesStatus.RecoveryPending;
        series.recoveryStartedAt = block.timestamp;
        series.recoveryEndsAt = block.timestamp + recoveryTimelock;

        emit RecoveryStarted(seriesId, series.recoveryEndsAt, priceWad);
    }

    function returnRiskShares(uint256 seriesId, uint256 shares) external nonReentrant {
        if (shares == 0) revert ZeroAmount();
        RiskSeries storage series = _riskSeries[seriesId];
        _requireSeriesStatus(seriesId, SeriesStatus.RecoveryPending);

        IEveRiskShares(evRisk).burn(msg.sender, seriesId, shares);
        series.sharesSupply -= shares;
        series.returnedSharesSupply += shares;
        _returnedShares[seriesId][msg.sender] += shares;

        emit RiskSharesReturned(msg.sender, seriesId, shares);
    }

    function reclaimReturnedRiskShares(uint256 seriesId, address receiver)
        external
        nonReentrant
        returns (uint256 shares)
    {
        if (receiver == address(0)) revert ZeroAddress();
        RiskSeries storage series = _riskSeries[seriesId];
        if (series.status != SeriesStatus.Active && series.status != SeriesStatus.RecoveryPending) {
            revert RecoveryNotPending(seriesId);
        }

        shares = _returnedShares[seriesId][msg.sender];
        if (shares == 0) revert NoReturnedShares(seriesId, msg.sender);

        _returnedShares[seriesId][msg.sender] = 0;
        series.returnedSharesSupply -= shares;
        series.sharesSupply += shares;
        IEveRiskShares(evRisk).mint(receiver, seriesId, shares);

        emit ReturnedRiskSharesReclaimed(msg.sender, seriesId, shares);
    }

    function cancelRecovery(uint256 seriesId) external nonReentrant {
        RiskSeries storage series = _riskSeries[seriesId];
        _requireSeriesStatus(seriesId, SeriesStatus.RecoveryPending);
        uint256 priceWad = IETHUSDOracle(oracle).ethUsdPriceWad();
        uint256 triggerPrice = _triggerPrice(series);
        if (priceWad <= triggerPrice) revert RecoveryNotEligible(priceWad, triggerPrice);

        series.status = SeriesStatus.Active;
        series.recoveryStartedAt = 0;
        series.recoveryEndsAt = 0;

        emit RecoveryCancelled(seriesId);
    }

    function finalizeRecovery(uint256 seriesId) external nonReentrant returns (uint256 newSeriesId) {
        RiskSeries storage series = _riskSeries[seriesId];
        _requireSeriesStatus(seriesId, SeriesStatus.RecoveryPending);
        if (block.timestamp < series.recoveryEndsAt) revert RecoveryTimelockActive(series.recoveryEndsAt);

        uint256 priceWad = IETHUSDOracle(oracle).ethUsdPriceWad();
        uint256 triggerPrice = _triggerPrice(series);
        if (priceWad > triggerPrice) revert RecoveryRestored(priceWad, triggerPrice);

        newSeriesId = seriesId + 1;
        if (_riskSeries[newSeriesId].status != SeriesStatus.None) revert InvalidSeries(newSeriesId);
        uint256 newWethPerPairWad =
            _wethPerPairWad(priceWad, nextSeriesCollateralRatioBps);
        _requireRecoverableSeriesValue(series, newWethPerPairWad);

        series.status = SeriesStatus.Liquidatable;
        series.finalizedAt = block.timestamp;
        series.nextSeriesId = newSeriesId;
        _createSeries(
            newSeriesId,
            priceWad,
            nextSeriesCollateralRatioBps,
            nextSeriesRecoveryTriggerBps,
            SeriesStatus.Active
        );
        currentRiskSeriesId = newSeriesId;

        emit RecoveryFinalized(seriesId, newSeriesId, priceWad);
    }

    function claimRecoveredRiskShares(uint256 oldSeriesId, address receiver, RecoveryClaimMode mode)
        external
        nonReentrant
        returns (uint256 sharesMinted, uint256 eveUSDMinted, uint256 wethOut)
    {
        if (receiver == address(0)) revert ZeroAddress();
        _requireSeriesStatus(oldSeriesId, SeriesStatus.Liquidatable);

        RecoveredRiskClaimPreview memory preview = previewRecoveredRiskClaim(msg.sender, oldSeriesId, mode);

        _returnedShares[oldSeriesId][msg.sender] = 0;
        _riskSeries[oldSeriesId].returnedSharesSupply -= preview.returnedShares;
        _moveRecoveredClaimAccounting(preview, preview.returnedShares);
        _mintRecoveredClaim(receiver, preview);
        if (preview.wethOut != 0) {
            IERC20(weth).safeTransfer(receiver, preview.wethOut);
        }

        emit RecoveredRiskSharesClaimed(
            msg.sender,
            oldSeriesId,
            preview.newSeriesId,
            mode,
            preview.returnedShares,
            preview.sharesMinted,
            preview.eveUSDMinted,
            preview.wethOut
        );

        return (preview.sharesMinted, preview.eveUSDMinted, preview.wethOut);
    }

    function recoverExpiredRisk(address holder, uint256 oldSeriesId, uint256 shares)
        external
        nonReentrant
        returns (uint256 newSeriesId, uint256 sharesMinted, uint256 eveUSDMinted)
    {
        if (holder == address(0)) revert ZeroAddress();
        if (shares == 0) revert ZeroAmount();
        _requireSeriesStatus(oldSeriesId, SeriesStatus.Liquidatable);
        if (shares > IEveRiskShares(evRisk).balanceOf(holder, oldSeriesId)) revert EmptyPool();

        newSeriesId = _riskSeries[oldSeriesId].nextSeriesId;
        RecoveredRiskClaimPreview memory preview =
            _previewRecoveredRiskClaim(oldSeriesId, newSeriesId, shares, RecoveryClaimMode.MorePairs);
        IEveRiskShares(evRisk).burn(holder, oldSeriesId, shares);
        _riskSeries[oldSeriesId].sharesSupply -= shares;
        _moveRecoveredClaimAccounting(preview, shares);
        _mintRecoveredClaim(msg.sender, preview);

        emit ExpiredRiskRecovered(
            msg.sender, holder, oldSeriesId, newSeriesId, shares, preview.sharesMinted, preview.eveUSDMinted
        );

        return (newSeriesId, preview.sharesMinted, preview.eveUSDMinted);
    }

    function previewDeposit(uint256 wethAmount) public view returns (DepositPreview memory preview) {
        if (wethAmount == 0) revert ZeroAmount();
        uint256 seriesId = currentRiskSeriesId;
        RiskSeries memory series = _riskSeries[seriesId];
        if (series.status != SeriesStatus.Active) revert SeriesNotActive(seriesId);

        uint256 priceWad = IETHUSDOracle(oracle).ethUsdPriceWad();
        uint256 feeAmount = _feeAmount(wethAmount, mintFeeBps);
        uint256 netWethAmount = wethAmount - feeAmount;
        uint256 minted = Math.mulDiv(netWethAmount, WAD, series.wethPerPairWad);
        if (minted == 0) revert DepositTooSmall();

        uint256 collateralRatioBpsAfter =
            _collateralRatioBps(accountedCollateral + netWethAmount, seniorLiabilities() + minted, priceWad);

        return DepositPreview({
            seriesId: seriesId,
            collateralIn: wethAmount,
            eveUSDMinted: minted,
            sharesMinted: minted,
            feeAmount: feeAmount,
            priceWad: priceWad,
            wethPerPairWad: series.wethPerPairWad,
            collateralRatioBpsAfter: collateralRatioBpsAfter
        });
    }

    function previewRecombine(uint256 seriesId, uint256 eveUSDAmount)
        public
        view
        returns (RedemptionPreview memory preview)
    {
        if (eveUSDAmount == 0) revert ZeroAmount();
        _requireRecombinableSeries(seriesId);

        RiskSeries memory series = _riskSeries[seriesId];
        if (
            series.eveUSDSupply == 0 || series.sharesSupply == 0 || series.accountedCollateral == 0
                || eveUSDAmount > series.eveUSDSupply || eveUSDAmount > series.sharesSupply
        ) {
            revert EmptyPool();
        }

        uint256 grossCollateralOut = Math.mulDiv(series.accountedCollateral, eveUSDAmount, series.eveUSDSupply);
        uint256 feeAmount = _feeAmount(grossCollateralOut, recombinationFeeBps);
        uint256 collateralOut = grossCollateralOut - feeAmount;
        if (grossCollateralOut == 0 || collateralOut == 0) revert RedemptionTooSmall();

        uint256 priceWad = IETHUSDOracle(oracle).ethUsdPriceWad();
        uint256 collateralRatioBpsAfter = _collateralRatioBps(
            accountedCollateral - grossCollateralOut, seniorLiabilities() - eveUSDAmount, priceWad
        );

        return RedemptionPreview({
            seriesId: seriesId,
            eveUSDBurned: eveUSDAmount,
            sharesBurned: eveUSDAmount,
            collateralOut: collateralOut,
            feeAmount: feeAmount,
            priceWad: priceWad,
            collateralRatioBpsAfter: collateralRatioBpsAfter
        });
    }

    function requiredSharesForRecombine(uint256, uint256 eveUSDAmount) external pure returns (uint256 shares) {
        if (eveUSDAmount == 0) revert ZeroAmount();
        return eveUSDAmount;
    }

    function previewOperatorRecovery(address holder, uint256 oldSeriesId, uint256 shares)
        external
        view
        returns (OperatorRecoveryPreview memory preview)
    {
        if (holder == address(0)) revert ZeroAddress();
        if (shares == 0) revert ZeroAmount();
        RiskSeries memory oldSeries = _riskSeries[oldSeriesId];
        if (oldSeries.status != SeriesStatus.Liquidatable) revert RecoveryNotFinalized(oldSeriesId);
        if (shares > IEveRiskShares(evRisk).balanceOf(holder, oldSeriesId)) revert EmptyPool();

        RecoveredRiskClaimPreview memory conversion =
            _previewRecoveredRiskClaim(oldSeriesId, oldSeries.nextSeriesId, shares, RecoveryClaimMode.MorePairs);

        return OperatorRecoveryPreview({
            oldSeriesId: oldSeriesId,
            newSeriesId: oldSeries.nextSeriesId,
            sharesBurned: shares,
            sharesMinted: conversion.sharesMinted,
            collateralMoved: conversion.collateralMoved,
            eveUSDMinted: conversion.eveUSDMinted
        });
    }

    function previewRecoveredRiskClaim(address account, uint256 oldSeriesId, RecoveryClaimMode mode)
        public
        view
        returns (RecoveredRiskClaimPreview memory preview)
    {
        if (account == address(0)) revert ZeroAddress();
        RiskSeries memory oldSeries = _riskSeries[oldSeriesId];
        if (oldSeries.status != SeriesStatus.Liquidatable) revert RecoveryNotFinalized(oldSeriesId);
        uint256 shares = _returnedShares[oldSeriesId][account];
        if (shares == 0) revert NoReturnedShares(oldSeriesId, account);

        return _previewRecoveredRiskClaim(oldSeriesId, oldSeries.nextSeriesId, shares, mode);
    }

    function riskSeries(uint256 seriesId) external view returns (RiskSeries memory series) {
        return _riskSeries[seriesId];
    }

    function returnedShares(uint256 seriesId, address account) external view returns (uint256 shares) {
        return _returnedShares[seriesId][account];
    }

    function totalCollateral() public view returns (uint256 wethAmount) {
        return accountedCollateral;
    }

    function seniorLiabilities() public view returns (uint256 eveUSDAmount) {
        return IERC20(eveUSD).totalSupply();
    }

    function collateralValueWad() public view returns (uint256 usdValueWad) {
        return _collateralValueWad(accountedCollateral, IETHUSDOracle(oracle).ethUsdPriceWad());
    }

    function collateralRatioBps() external view returns (uint256 ratioBps) {
        return _collateralRatioBps(accountedCollateral, seniorLiabilities(), IETHUSDOracle(oracle).ethUsdPriceWad());
    }

    function _moveRecoveredClaimAccounting(RecoveredRiskClaimPreview memory preview, uint256 oldSharesBurned)
        internal
    {
        RiskSeries storage oldSeries = _riskSeries[preview.oldSeriesId];
        RiskSeries storage newSeries = _riskSeries[preview.newSeriesId];

        oldSeries.eveUSDSupply -= oldSharesBurned;
        oldSeries.accountedCollateral -= preview.oldClaimWeth;
        newSeries.eveUSDSupply += preview.sharesMinted;
        newSeries.sharesSupply += preview.sharesMinted;
        newSeries.accountedCollateral += preview.collateralMoved;
        accountedCollateral -= preview.wethOut;
    }

    function _mintRecoveredClaim(address receiver, RecoveredRiskClaimPreview memory preview) internal {
        if (preview.eveUSDMinted != 0) {
            IEveUSD(eveUSD).mint(receiver, preview.eveUSDMinted);
        }
        IEveRiskShares(evRisk).mint(receiver, preview.newSeriesId, preview.sharesMinted);
    }

    function _previewRecoveredRiskClaim(
        uint256 oldSeriesId,
        uint256 newSeriesId,
        uint256 shares,
        RecoveryClaimMode mode
    ) internal view returns (RecoveredRiskClaimPreview memory preview) {
        RiskSeries memory oldSeries = _riskSeries[oldSeriesId];
        RiskSeries memory newSeries = _riskSeries[newSeriesId];
        if (newSeries.status != SeriesStatus.Active) revert InvalidSeries(newSeriesId);

        uint256 oldClaimWeth = _collateralForShares(oldSeries, shares);
        if (oldClaimWeth == 0) revert RedemptionTooSmall();
        uint256 baseNewClaimWeth = Math.mulDiv(shares, newSeries.wethPerPairWad, WAD, Math.Rounding.Ceil);
        if (baseNewClaimWeth > oldClaimWeth) {
            revert RecoveryClaimValueInsufficient(oldClaimWeth, baseNewClaimWeth);
        }

        uint256 collateralMoved;
        uint256 sharesMinted;
        uint256 eveUSDMinted;
        uint256 wethOut;
        if (mode == RecoveryClaimMode.WETHDifference) {
            collateralMoved = baseNewClaimWeth;
            sharesMinted = shares;
            wethOut = oldClaimWeth - baseNewClaimWeth;
        } else {
            collateralMoved = oldClaimWeth;
            sharesMinted = Math.mulDiv(oldClaimWeth, WAD, newSeries.wethPerPairWad);
            if (sharesMinted < shares) {
                revert RecoveryClaimValueInsufficient(oldClaimWeth, baseNewClaimWeth);
            }
            eveUSDMinted = sharesMinted - shares;
        }

        return RecoveredRiskClaimPreview({
            oldSeriesId: oldSeriesId,
            newSeriesId: newSeriesId,
            returnedShares: shares,
            oldClaimWeth: oldClaimWeth,
            baseNewClaimWeth: baseNewClaimWeth,
            surplusWeth: oldClaimWeth - baseNewClaimWeth,
            collateralMoved: collateralMoved,
            sharesMinted: sharesMinted,
            eveUSDMinted: eveUSDMinted,
            wethOut: wethOut,
            mode: mode
        });
    }

    function _createSeries(
        uint256 seriesId,
        uint256 priceWad,
        uint256 collateralRatioBps_,
        uint256 recoveryTriggerBps_,
        SeriesStatus status
    ) internal {
        uint256 wethPerPairWad = _wethPerPairWad(priceWad, collateralRatioBps_);
        if (wethPerPairWad == 0) revert DepositTooSmall();

        _riskSeries[seriesId] = RiskSeries({
            eveUSDSupply: 0,
            sharesSupply: 0,
            returnedSharesSupply: 0,
            accountedCollateral: 0,
            startPriceWad: priceWad,
            wethPerPairWad: wethPerPairWad,
            collateralRatioBps: collateralRatioBps_,
            recoveryTriggerBps: recoveryTriggerBps_,
            startedAt: block.timestamp,
            recoveryStartedAt: 0,
            recoveryEndsAt: 0,
            finalizedAt: 0,
            nextSeriesId: 0,
            status: status
        });
    }

    function _collateralForShares(RiskSeries memory series, uint256 shares) internal pure returns (uint256) {
        if (shares > series.eveUSDSupply) revert EmptyPool();
        return Math.mulDiv(series.accountedCollateral, shares, series.eveUSDSupply);
    }

    function _wethPerPairWad(uint256 priceWad, uint256 collateralRatioBps_) internal pure returns (uint256) {
        return Math.mulDiv(Math.mulDiv(WAD, collateralRatioBps_, BPS_DENOMINATOR), WAD, priceWad);
    }

    function _requireRecoverableSeriesValue(RiskSeries memory oldSeries, uint256 newWethPerPairWad)
        internal
        pure
    {
        if (oldSeries.eveUSDSupply == 0) return;
        uint256 oldClaimWethPerPair = Math.mulDiv(oldSeries.accountedCollateral, WAD, oldSeries.eveUSDSupply);
        if (newWethPerPairWad > oldClaimWethPerPair) {
            revert RecoveryClaimValueInsufficient(oldClaimWethPerPair, newWethPerPairWad);
        }
    }

    function _triggerPrice(RiskSeries memory series) internal pure returns (uint256) {
        return Math.mulDiv(series.startPriceWad, series.recoveryTriggerBps, BPS_DENOMINATOR);
    }

    function _collateralValueWad(uint256 wethAmount, uint256 priceWad) internal pure returns (uint256) {
        return Math.mulDiv(wethAmount, priceWad, WAD);
    }

    function _collateralRatioBps(uint256 wethAmount, uint256 liabilities, uint256 priceWad)
        internal
        pure
        returns (uint256)
    {
        if (liabilities == 0) return type(uint256).max;
        return Math.mulDiv(_collateralValueWad(wethAmount, priceWad), BPS_DENOMINATOR, liabilities);
    }

    function _feeAmount(uint256 amount, uint256 feeBps) internal pure returns (uint256) {
        if (feeBps == 0) return 0;
        return Math.mulDiv(amount, feeBps, BPS_DENOMINATOR);
    }

    function _collectFee(address payer, uint256 amount) internal {
        if (amount == 0) return;
        IERC20(weth).safeTransfer(feeRecipient, amount);
        emit FeeCollected(payer, feeRecipient, amount);
    }

    function _requireRecombinableSeries(uint256 seriesId) internal view {
        SeriesStatus status = _riskSeries[seriesId].status;
        if (
            status != SeriesStatus.Active && status != SeriesStatus.RecoveryPending
                && status != SeriesStatus.Liquidatable
        ) {
            revert SeriesNotActive(seriesId);
        }
    }

    function _requireSeriesStatus(uint256 seriesId, SeriesStatus expected) internal view {
        if (_riskSeries[seriesId].status == SeriesStatus.None) revert InvalidSeries(seriesId);
        if (_riskSeries[seriesId].status != expected) {
            if (expected == SeriesStatus.Active) revert SeriesNotActive(seriesId);
            if (expected == SeriesStatus.RecoveryPending) revert RecoveryNotPending(seriesId);
            if (expected == SeriesStatus.Liquidatable) revert RecoveryNotFinalized(seriesId);
            revert InvalidSeries(seriesId);
        }
    }

    function _validateCollateralRatio(uint256 collateralRatioBps_) internal pure {
        if (collateralRatioBps_ < MIN_COLLATERAL_RATIO_BPS || collateralRatioBps_ > MAX_COLLATERAL_RATIO_BPS) {
            revert InvalidCollateralRatio(collateralRatioBps_);
        }
    }

    function _validateRecoveryTrigger(uint256 recoveryTriggerBps_) internal pure {
        if (recoveryTriggerBps_ < MIN_RECOVERY_TRIGGER_BPS || recoveryTriggerBps_ > MAX_RECOVERY_TRIGGER_BPS) {
            revert InvalidRecoveryTrigger(recoveryTriggerBps_);
        }
    }

    function _validateRecoveryTimelock(uint256 recoveryTimelock_) internal pure {
        if (recoveryTimelock_ < MIN_RECOVERY_TIMELOCK || recoveryTimelock_ > MAX_RECOVERY_TIMELOCK) {
            revert InvalidRecoveryTimelock(recoveryTimelock_);
        }
    }

    function _validateFeeBps(uint256 feeBps) internal pure {
        if (feeBps > MAX_FEE_BPS) revert InvalidFeeBps(feeBps);
    }

    function _requireContract(address account) internal view {
        if (account == address(0)) revert ZeroAddress();
        if (account.code.length == 0) revert ContractExpected(account);
    }

    function _requireEveUSDPool(address token) internal view {
        address configuredPool = IEveUSD(token).pool();
        if (configuredPool != address(this)) revert InvalidTokenPool(token, address(this), configuredPool);
    }

    function _requireEvRiskPool(address token) internal view {
        address configuredPool = IEveRiskShares(token).pool();
        if (configuredPool != address(this)) revert InvalidTokenPool(token, address(this), configuredPool);
    }
}
