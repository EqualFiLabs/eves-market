// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Math} from "../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

import {IEveRiskShares} from "./interfaces/IEveRiskShares.sol";
import {IEveUSD} from "./interfaces/IEveUSD.sol";
import {IEveUSDPool} from "./interfaces/IEveUSDPool.sol";
import {IUsdOracle} from "./interfaces/IUsdOracle.sol";

contract EveUSDPool is IEveUSDPool, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct InsuranceCalc {
        uint256 seniorOutstanding;
        uint256 reserveWad;
        uint256 netCollateralWad;
        uint256 targetPerPairWad;
        uint256 collateralPerPairWad;
    }

    uint256 public constant WAD = 1e18;
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant MAX_FEE_BPS = 1_000;
    uint256 public constant MAX_INSURANCE_BPS = 10_000;
    uint256 public constant MIN_COLLATERAL_RATIO_BPS = 10_001;
    uint256 public constant MAX_COLLATERAL_RATIO_BPS = 30_000;
    uint256 public constant MIN_RECOVERY_TRIGGER_BPS = 1;
    uint256 public constant MAX_RECOVERY_TRIGGER_BPS = 9_999;
    uint256 public constant MIN_RECOVERY_TIMELOCK = 1 days;
    uint256 public constant MAX_RECOVERY_TIMELOCK = 30 days;

    address public immutable eveUSD;
    address public immutable evRisk;
    uint256 public immutable firstCollateralProfileId;

    address public owner;
    address public feeRecipient;
    uint256 public recoveryTimelock;
    uint256 public nextProfileId;
    uint256 public nextSeriesId;
    uint256 public totalSeniorOutstanding;
    bool public configLocked;

    mapping(uint256 profileId => StableCollateralProfile profile) internal _collateralProfiles;
    mapping(address collateralToken => uint256 amount) internal _accountedCollateralByToken;
    mapping(uint256 seriesId => RiskSeries series) internal _riskSeries;
    mapping(uint256 seriesId => mapping(address account => uint256 shares)) internal _returnedShares;

    constructor(
        address initialCollateralToken,
        address eveUSD_,
        address evRisk_,
        address oracle_,
        address owner_,
        uint256 collateralRatioBps_,
        uint256 recoveryTriggerBps_
    ) {
        _requireContract(eveUSD_);
        _requireContract(evRisk_);
        if (owner_ == address(0)) revert ZeroAddress();
        _requireEveUSDPool(eveUSD_);
        _requireEvRiskPool(evRisk_);

        eveUSD = eveUSD_;
        evRisk = evRisk_;
        owner = owner_;
        feeRecipient = owner_;
        recoveryTimelock = 7 days;
        firstCollateralProfileId = 1;
        nextProfileId = 2;
        nextSeriesId = 2;

        uint256 seriesId = _createCollateralProfile(
            1, initialCollateralToken, oracle_, collateralRatioBps_, recoveryTriggerBps_, 0, 0, true
        );

        emit OwnershipTransferred(address(0), owner_);
        emit FeeRecipientSet(owner_);
        emit RecoveryTimelockSet(recoveryTimelock);
        emit CollateralProfileCreated(1, initialCollateralToken, oracle_, _collateralProfiles[1].decimals, seriesId);
        emit CollateralProfileConfigured(1, collateralRatioBps_, recoveryTriggerBps_, true);
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

    function createCollateralProfile(
        address collateralToken,
        address oracle,
        uint256 collateralRatioBps,
        uint256 recoveryTriggerBps,
        uint256 mintFeeBps,
        uint256 recombinationFeeBps,
        bool enabled
    ) external onlyOwner whenConfigUnlocked returns (uint256 profileId, uint256 seriesId) {
        profileId = nextProfileId++;
        seriesId = _createCollateralProfile(
            profileId,
            collateralToken,
            oracle,
            collateralRatioBps,
            recoveryTriggerBps,
            mintFeeBps,
            recombinationFeeBps,
            enabled
        );
        StableCollateralProfile memory profile = _collateralProfiles[profileId];
        emit CollateralProfileCreated(profileId, collateralToken, oracle, profile.decimals, seriesId);
        emit CollateralProfileConfigured(profileId, collateralRatioBps, recoveryTriggerBps, enabled);
    }

    function setCollateralProfileOracle(uint256 profileId, address newOracle) external onlyOwner whenConfigUnlocked {
        StableCollateralProfile storage profile = _requireProfile(profileId);
        _requireContract(newOracle);
        profile.oracle = newOracle;
        emit CollateralProfileOracleSet(profileId, newOracle);
    }

    function setCollateralProfileConfig(
        uint256 profileId,
        uint256 newCollateralRatioBps,
        uint256 newRecoveryTriggerBps,
        bool enabled
    ) external onlyOwner whenConfigUnlocked {
        StableCollateralProfile storage profile = _requireProfile(profileId);
        _validateCollateralRatio(newCollateralRatioBps);
        _validateRecoveryTrigger(newRecoveryTriggerBps);
        profile.collateralRatioBps = uint16(newCollateralRatioBps);
        profile.recoveryTriggerBps = uint16(newRecoveryTriggerBps);
        profile.enabled = enabled;
        emit CollateralProfileConfigured(profileId, newCollateralRatioBps, newRecoveryTriggerBps, enabled);
    }

    function setCollateralProfileFeeBps(uint256 profileId, uint256 newMintFeeBps, uint256 newRecombinationFeeBps)
        external
        onlyOwner
        whenConfigUnlocked
    {
        StableCollateralProfile storage profile = _requireProfile(profileId);
        _validateFeeBps(newMintFeeBps);
        _validateFeeBps(newRecombinationFeeBps);
        profile.mintFeeBps = uint16(newMintFeeBps);
        profile.recombinationFeeBps = uint16(newRecombinationFeeBps);
        emit CollateralProfileFeeBpsSet(profileId, newMintFeeBps, newRecombinationFeeBps);
    }

    function setCollateralProfileInsuranceBps(
        uint256 profileId,
        uint256 newInsuranceTargetBps,
        uint256 newInsuranceFeeBps
    ) external onlyOwner whenConfigUnlocked {
        StableCollateralProfile storage profile = _requireProfile(profileId);
        _validateInsuranceBps(newInsuranceTargetBps);
        _validateInsuranceBps(newInsuranceFeeBps);
        profile.insuranceTargetBps = uint16(newInsuranceTargetBps);
        profile.insuranceFeeBps = uint16(newInsuranceFeeBps);
        emit CollateralProfileInsuranceBpsSet(profileId, newInsuranceTargetBps, newInsuranceFeeBps);
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

    function topUpInsurance(uint256 profileId, uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        StableCollateralProfile storage profile = _requireProfile(profileId);
        _pullExact(profile.collateralToken, msg.sender, amount);

        profile.insuranceReserve += amount;
        _accountedCollateralByToken[profile.collateralToken] += amount;

        emit InsuranceToppedUp(msg.sender, profileId, profile.collateralToken, amount);
    }

    function depositCollateral(
        uint256 profileId,
        uint256 collateralAmount,
        address eveUSDReceiver,
        address shareReceiver
    ) external nonReentrant returns (uint256 seriesId, uint256 eveUSDMinted, uint256 sharesMinted) {
        if (eveUSDReceiver == address(0) || shareReceiver == address(0)) revert ZeroAddress();
        DepositPreview memory preview = previewDeposit(profileId, collateralAmount);
        StableCollateralProfile storage profile = _collateralProfiles[profileId];

        _pullExact(profile.collateralToken, msg.sender, collateralAmount);
        _applyDepositAccounting(profileId, preview);
        _collectFee(msg.sender, profile.collateralToken, preview.feeAmount);
        if (preview.insuranceContribution != 0) {
            emit InsuranceContributed(msg.sender, profileId, profile.collateralToken, preview.insuranceContribution);
        }
        IEveUSD(eveUSD).mint(eveUSDReceiver, preview.eveUSDMinted);
        IEveRiskShares(evRisk).mint(shareReceiver, preview.seriesId, preview.sharesMinted);

        _emitDeposited(msg.sender, eveUSDReceiver, shareReceiver, preview);

        return (preview.seriesId, preview.eveUSDMinted, preview.sharesMinted);
    }

    function _applyDepositAccounting(uint256 profileId, DepositPreview memory preview) internal {
        StableCollateralProfile storage profile = _collateralProfiles[profileId];
        RiskSeries storage series = _riskSeries[preview.seriesId];
        uint256 netCollateral = preview.collateralIn - preview.feeAmount;
        uint256 pairCollateral = netCollateral - preview.insuranceContribution;
        profile.accountedCollateral += pairCollateral;
        profile.insuranceReserve += preview.insuranceContribution;
        _accountedCollateralByToken[profile.collateralToken] += netCollateral;
        series.accountedCollateral += pairCollateral;
        series.seniorOutstanding += preview.eveUSDMinted;
        series.riskSharesOutstanding += preview.sharesMinted;
        profile.seniorOutstanding += preview.eveUSDMinted;
        totalSeniorOutstanding += preview.eveUSDMinted;
    }

    function _emitDeposited(
        address caller,
        address eveUSDReceiver,
        address shareReceiver,
        DepositPreview memory preview
    ) internal {
        emit Deposited(
            caller,
            eveUSDReceiver,
            shareReceiver,
            preview.profileId,
            preview.seriesId,
            preview.collateralIn,
            preview.eveUSDMinted,
            preview.sharesMinted,
            preview.priceWad,
            preview.collateralPerPairWad
        );
    }

    function recombine(uint256 seriesId, uint256 eveUSDAmount, uint256 shareAmount, address receiver)
        external
        nonReentrant
        returns (uint256 collateralOut)
    {
        if (receiver == address(0)) revert ZeroAddress();
        RedemptionPreview memory preview = previewRecombine(seriesId, eveUSDAmount);
        if (shareAmount != preview.sharesBurned) revert InvalidShareAmount(shareAmount, preview.sharesBurned);

        uint256 grossCollateralOut = preview.collateralOut + preview.feeAmount;
        RiskSeries storage series = _riskSeries[seriesId];
        StableCollateralProfile storage profile = _collateralProfiles[series.profileId];

        series.seniorOutstanding -= eveUSDAmount;
        series.riskSharesOutstanding -= shareAmount;
        series.accountedCollateral -= grossCollateralOut;
        profile.accountedCollateral -= grossCollateralOut;
        profile.seniorOutstanding -= eveUSDAmount;
        _accountedCollateralByToken[series.collateralToken] -= grossCollateralOut;
        totalSeniorOutstanding -= eveUSDAmount;

        IEveUSD(eveUSD).burn(msg.sender, eveUSDAmount);
        IEveRiskShares(evRisk).burn(msg.sender, seriesId, shareAmount);
        _collectFee(msg.sender, series.collateralToken, preview.feeAmount);
        IERC20(series.collateralToken).safeTransfer(receiver, preview.collateralOut);

        emit Recombined(
            msg.sender,
            receiver,
            seriesId,
            eveUSDAmount,
            shareAmount,
            series.collateralToken,
            preview.collateralOut,
            preview.collateralRatioBpsAfter
        );

        return preview.collateralOut;
    }

    function startRecovery(uint256 seriesId) external nonReentrant {
        RiskSeries storage series = _riskSeries[seriesId];
        _requireSeriesStatus(seriesId, SeriesStatus.Active);

        uint256 priceWad = _priceWad(_collateralProfiles[series.profileId]);
        uint256 triggerPrice = _triggerPrice(series);
        if (priceWad > triggerPrice) revert RecoveryNotEligible(priceWad, triggerPrice);

        series.status = SeriesStatus.RecoveryPending;
        series.recoveryStartedAt = block.timestamp;
        series.recoveryEndsAt = block.timestamp + recoveryTimelock;

        emit RecoveryStarted(series.profileId, seriesId, series.recoveryEndsAt, priceWad);
    }

    function returnRiskShares(uint256 seriesId, uint256 shares) external nonReentrant {
        if (shares == 0) revert ZeroAmount();
        RiskSeries storage series = _riskSeries[seriesId];
        _requireSeriesStatus(seriesId, SeriesStatus.RecoveryPending);

        IEveRiskShares(evRisk).burn(msg.sender, seriesId, shares);
        series.riskSharesOutstanding -= shares;
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
        series.riskSharesOutstanding += shares;
        IEveRiskShares(evRisk).mint(receiver, seriesId, shares);

        emit ReturnedRiskSharesReclaimed(msg.sender, seriesId, shares);
    }

    function cancelRecovery(uint256 seriesId) external nonReentrant {
        RiskSeries storage series = _riskSeries[seriesId];
        _requireSeriesStatus(seriesId, SeriesStatus.RecoveryPending);

        uint256 priceWad = _priceWad(_collateralProfiles[series.profileId]);
        uint256 triggerPrice = _triggerPrice(series);
        if (priceWad <= triggerPrice) revert RecoveryNotEligible(priceWad, triggerPrice);

        series.status = SeriesStatus.Active;
        series.recoveryStartedAt = 0;
        series.recoveryEndsAt = 0;

        emit RecoveryCancelled(series.profileId, seriesId);
    }

    function finalizeRecovery(uint256 seriesId) external nonReentrant returns (uint256 newSeriesId) {
        RiskSeries storage series = _riskSeries[seriesId];
        _requireSeriesStatus(seriesId, SeriesStatus.RecoveryPending);
        if (block.timestamp < series.recoveryEndsAt) revert RecoveryTimelockActive(series.recoveryEndsAt);

        StableCollateralProfile storage profile = _collateralProfiles[series.profileId];
        uint256 priceWad = _priceWad(profile);
        uint256 triggerPrice = _triggerPrice(series);
        if (priceWad > triggerPrice) revert RecoveryRestored(priceWad, triggerPrice);

        _drawInsuranceForSeniorShortfall(seriesId, series, profile, priceWad);

        newSeriesId = nextSeriesId++;

        series.status = SeriesStatus.OperatorRecoverable;
        series.finalizedAt = block.timestamp;
        series.successorSeriesId = newSeriesId;
        _createSeries(newSeriesId, series.profileId, priceWad, profile.collateralRatioBps, profile.recoveryTriggerBps);
        profile.activeSeriesId = newSeriesId;

        emit RecoveryFinalized(series.profileId, seriesId, newSeriesId, priceWad);
    }

    function claimRecoveredRiskShares(uint256 oldSeriesId, address receiver, RecoveryClaimMode mode)
        external
        nonReentrant
        returns (uint256 sharesMinted, uint256 eveUSDMinted, uint256 collateralOut)
    {
        if (receiver == address(0)) revert ZeroAddress();
        _requireSeriesStatus(oldSeriesId, SeriesStatus.OperatorRecoverable);

        RecoveredRiskClaimPreview memory preview = previewRecoveredRiskClaim(msg.sender, oldSeriesId, mode);

        _returnedShares[oldSeriesId][msg.sender] = 0;
        _riskSeries[oldSeriesId].returnedSharesSupply -= preview.returnedShares;
        _moveRecoveredClaimAccounting(preview);
        _mintRecoveredClaim(receiver, preview);
        if (preview.collateralOut != 0) {
            IERC20(_riskSeries[oldSeriesId].collateralToken).safeTransfer(receiver, preview.collateralOut);
        }

        emit RecoveredRiskSharesClaimed(
            msg.sender,
            oldSeriesId,
            preview.newSeriesId,
            mode,
            preview.returnedShares,
            preview.sharesMinted,
            preview.eveUSDMinted,
            preview.collateralOut
        );

        return (preview.sharesMinted, preview.eveUSDMinted, preview.collateralOut);
    }

    function recoverExpiredRisk(address holder, uint256 oldSeriesId, uint256 shares)
        external
        nonReentrant
        returns (uint256 newSeriesId, uint256 sharesMinted, uint256 eveUSDMinted)
    {
        if (holder == address(0)) revert ZeroAddress();
        if (shares == 0) revert ZeroAmount();
        _requireSeriesStatus(oldSeriesId, SeriesStatus.OperatorRecoverable);
        if (shares > IEveRiskShares(evRisk).balanceOf(holder, oldSeriesId)) revert EmptyPool();

        newSeriesId = _riskSeries[oldSeriesId].successorSeriesId;
        RecoveredRiskClaimPreview memory preview =
            _previewRecoveredRiskClaim(oldSeriesId, newSeriesId, shares, RecoveryClaimMode.MorePairs);
        IEveRiskShares(evRisk).burn(holder, oldSeriesId, shares);
        _riskSeries[oldSeriesId].riskSharesOutstanding -= shares;
        _moveRecoveredClaimAccounting(preview);
        _mintRecoveredClaim(msg.sender, preview);

        emit ExpiredRiskRecovered(
            msg.sender, holder, oldSeriesId, newSeriesId, shares, preview.sharesMinted, preview.eveUSDMinted
        );

        return (newSeriesId, preview.sharesMinted, preview.eveUSDMinted);
    }

    function previewDeposit(uint256 profileId, uint256 collateralAmount)
        public
        view
        returns (DepositPreview memory preview)
    {
        if (collateralAmount == 0) revert ZeroAmount();
        StableCollateralProfile memory profile = _requireProfileView(profileId);
        if (!profile.enabled) revert ProfileDisabled(profileId);
        uint256 seriesId = profile.activeSeriesId;
        RiskSeries memory series = _riskSeries[seriesId];
        if (series.status != SeriesStatus.Active) revert SeriesNotActive(seriesId);

        uint256 priceWad = _priceWad(profile);
        uint256 triggerPrice = _triggerPrice(series);
        if (priceWad <= triggerPrice) revert RecoveryRequired(profileId, seriesId, priceWad, triggerPrice);

        preview.profileId = profileId;
        preview.seriesId = seriesId;
        preview.collateralIn = collateralAmount;
        preview.feeAmount = _feeAmount(collateralAmount, profile.mintFeeBps);
        preview.priceWad = priceWad;
        preview.collateralPerPairWad = series.collateralPerPairWad;

        uint256 netCollateral = collateralAmount - preview.feeAmount;
        preview.insuranceContribution =
            _depositInsuranceContribution(profile, netCollateral, priceWad, series.collateralPerPairWad);
        if (preview.insuranceContribution > netCollateral) revert DepositTooSmall();
        uint256 pairCollateral = netCollateral - preview.insuranceContribution;
        uint256 netCollateralWad = _toWad(pairCollateral, profile.decimals);
        preview.eveUSDMinted = Math.mulDiv(netCollateralWad, WAD, series.collateralPerPairWad);
        if (preview.eveUSDMinted == 0) revert DepositTooSmall();
        preview.sharesMinted = preview.eveUSDMinted;

        preview.collateralRatioBpsAfter = _collateralRatioBps(
            profile.decimals,
            series.accountedCollateral + pairCollateral,
            series.seniorOutstanding + preview.eveUSDMinted,
            priceWad
        );
    }

    function previewRecombine(uint256 seriesId, uint256 eveUSDAmount)
        public
        view
        returns (RedemptionPreview memory preview)
    {
        if (eveUSDAmount == 0) revert ZeroAmount();
        _requireRecombinableSeries(seriesId);

        RiskSeries memory series = _riskSeries[seriesId];
        StableCollateralProfile memory profile = _collateralProfiles[series.profileId];
        if (
            series.seniorOutstanding == 0 || series.riskSharesOutstanding == 0 || series.accountedCollateral == 0
                || eveUSDAmount > series.seniorOutstanding || eveUSDAmount > series.riskSharesOutstanding
        ) {
            revert EmptyPool();
        }

        uint256 grossCollateralOut = Math.mulDiv(series.accountedCollateral, eveUSDAmount, series.seniorOutstanding);
        uint256 feeAmount = _feeAmount(grossCollateralOut, profile.recombinationFeeBps);
        uint256 collateralOut = grossCollateralOut - feeAmount;
        if (grossCollateralOut == 0 || collateralOut == 0) revert RedemptionTooSmall();

        uint256 priceWad = _priceWad(profile);
        uint256 collateralRatioBpsAfter = _collateralRatioBps(
            profile.decimals,
            series.accountedCollateral - grossCollateralOut,
            series.seniorOutstanding - eveUSDAmount,
            priceWad
        );

        return RedemptionPreview({
            profileId: series.profileId,
            seriesId: seriesId,
            collateralToken: series.collateralToken,
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
        if (oldSeries.status != SeriesStatus.OperatorRecoverable) revert RecoveryNotFinalized(oldSeriesId);
        if (shares > IEveRiskShares(evRisk).balanceOf(holder, oldSeriesId)) revert EmptyPool();

        RecoveredRiskClaimPreview memory conversion =
            _previewRecoveredRiskClaim(oldSeriesId, oldSeries.successorSeriesId, shares, RecoveryClaimMode.MorePairs);

        return OperatorRecoveryPreview({
            oldSeriesId: oldSeriesId,
            newSeriesId: oldSeries.successorSeriesId,
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
        if (oldSeries.status != SeriesStatus.OperatorRecoverable) revert RecoveryNotFinalized(oldSeriesId);
        uint256 shares = _returnedShares[oldSeriesId][account];
        if (shares == 0) revert NoReturnedShares(oldSeriesId, account);

        return _previewRecoveredRiskClaim(oldSeriesId, oldSeries.successorSeriesId, shares, mode);
    }

    function collateralProfile(uint256 profileId) external view returns (StableCollateralProfile memory profile) {
        return _requireProfileView(profileId);
    }

    function riskSeries(uint256 seriesId) external view returns (RiskSeries memory series) {
        return _riskSeries[seriesId];
    }

    function returnedShares(uint256 seriesId, address account) external view returns (uint256 shares) {
        return _returnedShares[seriesId][account];
    }

    function totalCollateral(address collateralToken) public view returns (uint256 amount) {
        return _accountedCollateralByToken[collateralToken];
    }

    function seriesCollateralValueWad(uint256 seriesId) public view returns (uint256 usdValueWad) {
        RiskSeries memory series = _requireSeriesView(seriesId);
        StableCollateralProfile memory profile = _collateralProfiles[series.profileId];
        return _collateralValueWad(profile.decimals, series.accountedCollateral, _priceWad(profile));
    }

    function seriesCollateralRatioBps(uint256 seriesId) external view returns (uint256 ratioBps) {
        RiskSeries memory series = _requireSeriesView(seriesId);
        StableCollateralProfile memory profile = _collateralProfiles[series.profileId];
        return
            _collateralRatioBps(
                profile.decimals, series.accountedCollateral, series.seniorOutstanding, _priceWad(profile)
            );
    }

    function collateralUsdPriceWad(uint256 profileId) external view returns (uint256 priceWad) {
        return _priceWad(_requireProfileView(profileId));
    }

    function seniorLiabilities() public view returns (uint256 eveUSDAmount) {
        return IERC20(eveUSD).totalSupply();
    }

    function insuranceReserve(uint256 profileId) external view returns (uint256 amount) {
        return _requireProfileView(profileId).insuranceReserve;
    }

    function insuranceTarget(uint256 profileId) public view returns (uint256 amount) {
        StableCollateralProfile memory profile = _requireProfileView(profileId);
        return _insuranceTarget(profile, _priceWad(profile));
    }

    function insuranceDeficit(uint256 profileId) external view returns (uint256 amount) {
        StableCollateralProfile memory profile = _requireProfileView(profileId);
        uint256 target = _insuranceTarget(profile, _priceWad(profile));
        if (target > profile.insuranceReserve) return target - profile.insuranceReserve;
        return 0;
    }

    function profileSeniorLiabilities(uint256 profileId) external view returns (uint256 eveUSDAmount) {
        return _requireProfileView(profileId).seniorOutstanding;
    }

    function _createCollateralProfile(
        uint256 profileId,
        address collateralToken,
        address oracle,
        uint256 collateralRatioBps,
        uint256 recoveryTriggerBps,
        uint256 mintFeeBps,
        uint256 recombinationFeeBps,
        bool enabled
    ) internal returns (uint256 seriesId) {
        _requireContract(collateralToken);
        _requireContract(oracle);
        _validateCollateralRatio(collateralRatioBps);
        _validateRecoveryTrigger(recoveryTriggerBps);
        _validateFeeBps(mintFeeBps);
        _validateFeeBps(recombinationFeeBps);

        uint8 decimals = IERC20Metadata(collateralToken).decimals();
        if (decimals > 18) revert InvalidCollateralDecimals(decimals);

        seriesId = profileId == firstCollateralProfileId ? 1 : nextSeriesId++;
        uint256 priceWad = IUsdOracle(oracle).priceWad();

        _collateralProfiles[profileId] = StableCollateralProfile({
            collateralToken: collateralToken,
            oracle: oracle,
            decimals: decimals,
            collateralRatioBps: uint16(collateralRatioBps),
            recoveryTriggerBps: uint16(recoveryTriggerBps),
            mintFeeBps: uint16(mintFeeBps),
            recombinationFeeBps: uint16(recombinationFeeBps),
            insuranceTargetBps: 0,
            insuranceFeeBps: 0,
            enabled: enabled,
            activeSeriesId: seriesId,
            accountedCollateral: 0,
            insuranceReserve: 0,
            seniorOutstanding: 0
        });
        _createSeries(seriesId, profileId, priceWad, collateralRatioBps, recoveryTriggerBps);
    }

    function _createSeries(
        uint256 seriesId,
        uint256 profileId,
        uint256 priceWad,
        uint256 collateralRatioBps_,
        uint256 recoveryTriggerBps_
    ) internal {
        StableCollateralProfile memory profile = _collateralProfiles[profileId];
        uint256 collateralPerPairWad = _collateralPerPairWad(priceWad, collateralRatioBps_);
        if (collateralPerPairWad == 0) revert DepositTooSmall();

        _riskSeries[seriesId] = RiskSeries({
            profileId: profileId,
            collateralToken: profile.collateralToken,
            seniorOutstanding: 0,
            riskSharesOutstanding: 0,
            returnedSharesSupply: 0,
            accountedCollateral: 0,
            startPriceWad: priceWad,
            collateralPerPairWad: collateralPerPairWad,
            collateralRatioBps: collateralRatioBps_,
            recoveryTriggerBps: recoveryTriggerBps_,
            startedAt: block.timestamp,
            recoveryStartedAt: 0,
            recoveryEndsAt: 0,
            finalizedAt: 0,
            successorSeriesId: 0,
            status: SeriesStatus.Active
        });
    }

    function _moveRecoveredClaimAccounting(RecoveredRiskClaimPreview memory preview) internal {
        RiskSeries storage oldSeries = _riskSeries[preview.oldSeriesId];
        RiskSeries storage newSeries = _riskSeries[preview.newSeriesId];
        StableCollateralProfile storage profile = _collateralProfiles[oldSeries.profileId];

        uint256 collateralRemoved = preview.collateralMoved + preview.collateralOut;
        oldSeries.accountedCollateral -= collateralRemoved;
        newSeries.seniorOutstanding += preview.eveUSDMinted;
        newSeries.riskSharesOutstanding += preview.sharesMinted;
        newSeries.accountedCollateral += preview.collateralMoved;
        profile.seniorOutstanding += preview.eveUSDMinted;
        totalSeniorOutstanding += preview.eveUSDMinted;

        if (preview.collateralOut != 0) {
            profile.accountedCollateral -= preview.collateralOut;
            _accountedCollateralByToken[oldSeries.collateralToken] -= preview.collateralOut;
        }
    }

    function _mintRecoveredClaim(address receiver, RecoveredRiskClaimPreview memory preview) internal {
        if (preview.eveUSDMinted != 0) {
            IEveUSD(eveUSD).mint(receiver, preview.eveUSDMinted);
        }
        if (preview.sharesMinted != 0) {
            IEveRiskShares(evRisk).mint(receiver, preview.newSeriesId, preview.sharesMinted);
        }
    }

    function _previewRecoveredRiskClaim(
        uint256 oldSeriesId,
        uint256 newSeriesId,
        uint256 shares,
        RecoveryClaimMode mode
    ) internal view returns (RecoveredRiskClaimPreview memory preview) {
        RiskSeries memory oldSeries = _riskSeries[oldSeriesId];
        RiskSeries memory newSeries = _riskSeries[newSeriesId];
        if (newSeries.status != SeriesStatus.Active || newSeries.profileId != oldSeries.profileId) {
            revert InvalidSeries(newSeriesId);
        }
        StableCollateralProfile memory profile = _collateralProfiles[oldSeries.profileId];

        preview.oldSeriesId = oldSeriesId;
        preview.newSeriesId = newSeriesId;
        preview.returnedShares = shares;
        preview.mode = mode;
        uint256 remainingRecoverableShares = _remainingRecoverableShares(oldSeries);
        if (shares > remainingRecoverableShares) revert EmptyPool();
        preview.oldClaimCollateral = Math.mulDiv(oldSeries.accountedCollateral, shares, remainingRecoverableShares);
        uint256 baseNewClaimWad = Math.mulDiv(shares, newSeries.collateralPerPairWad, WAD, Math.Rounding.Ceil);
        preview.baseNewClaimCollateral = _fromWadCeil(baseNewClaimWad, profile.decimals);
        preview.seniorReserveCollateral =
            _seniorReserveCollateral(oldSeries.seniorOutstanding, newSeries.startPriceWad, profile.decimals);
        if (preview.seniorReserveCollateral > oldSeries.accountedCollateral) {
            preview.seniorShortfallCollateral = preview.seniorReserveCollateral - oldSeries.accountedCollateral;
        }
        uint256 totalJuniorResidual = oldSeries.accountedCollateral > preview.seniorReserveCollateral
            ? oldSeries.accountedCollateral - preview.seniorReserveCollateral
            : 0;
        preview.juniorResidualCollateral = Math.mulDiv(totalJuniorResidual, shares, remainingRecoverableShares);

        if (mode == RecoveryClaimMode.CollateralDifference) {
            if (preview.juniorResidualCollateral >= preview.baseNewClaimCollateral) {
                preview.collateralMoved = preview.baseNewClaimCollateral;
                preview.sharesMinted = shares;
                preview.eveUSDMinted = shares;
                preview.surplusCollateral = preview.juniorResidualCollateral - preview.baseNewClaimCollateral;
                preview.collateralOut = preview.surplusCollateral;
            } else {
                preview.collateralMoved = preview.juniorResidualCollateral;
                preview.sharesMinted = _sharesForCollateral(
                    preview.juniorResidualCollateral, profile.decimals, newSeries.collateralPerPairWad
                );
                preview.eveUSDMinted = preview.sharesMinted;
            }
        } else {
            preview.collateralMoved = preview.juniorResidualCollateral;
            preview.sharesMinted = _sharesForCollateral(
                preview.juniorResidualCollateral, profile.decimals, newSeries.collateralPerPairWad
            );
            preview.eveUSDMinted = preview.sharesMinted;
        }
    }

    function _remainingRecoverableShares(RiskSeries memory series) internal pure returns (uint256) {
        uint256 remaining = series.riskSharesOutstanding + series.returnedSharesSupply;
        if (remaining == 0) revert EmptyPool();
        return remaining;
    }

    function _sharesForCollateral(uint256 rawCollateral, uint8 decimals, uint256 collateralPerPairWad)
        internal
        pure
        returns (uint256)
    {
        if (rawCollateral == 0) return 0;
        return Math.mulDiv(_toWad(rawCollateral, decimals), WAD, collateralPerPairWad);
    }

    function _collateralPerPairWad(uint256 priceWad, uint256 collateralRatioBps_) internal pure returns (uint256) {
        return Math.mulDiv(Math.mulDiv(WAD, collateralRatioBps_, BPS_DENOMINATOR), WAD, priceWad);
    }

    function _triggerPrice(RiskSeries memory series) internal pure returns (uint256) {
        return Math.mulDiv(series.startPriceWad, series.recoveryTriggerBps, BPS_DENOMINATOR);
    }

    function _depositInsuranceContribution(
        StableCollateralProfile memory profile,
        uint256 netCollateral,
        uint256 priceWad,
        uint256 collateralPerPairWad
    ) internal pure returns (uint256) {
        if (profile.insuranceTargetBps == 0 || profile.insuranceFeeBps == 0) return 0;

        InsuranceCalc memory calc = InsuranceCalc({
            seniorOutstanding: profile.seniorOutstanding,
            reserveWad: _toWad(profile.insuranceReserve, profile.decimals),
            netCollateralWad: _toWad(netCollateral, profile.decimals),
            targetPerPairWad: _collateralPerPairWad(priceWad, profile.insuranceTargetBps),
            collateralPerPairWad: collateralPerPairWad
        });
        uint256 feePerPairWad = _collateralPerPairWad(priceWad, profile.insuranceFeeBps);
        if (calc.targetPerPairWad == 0 || feePerPairWad == 0) return 0;

        uint256 mintedWithoutInsurance = Math.mulDiv(calc.netCollateralWad, WAD, calc.collateralPerPairWad);
        uint256 targetWithoutInsurance =
            Math.mulDiv(calc.seniorOutstanding + mintedWithoutInsurance, calc.targetPerPairWad, WAD);
        if (calc.reserveWad >= targetWithoutInsurance) return 0;

        uint256 mintedWithFullFee = Math.mulDiv(calc.netCollateralWad, WAD, calc.collateralPerPairWad + feePerPairWad);
        uint256 fullFeeWad = Math.mulDiv(mintedWithFullFee, feePerPairWad, WAD, Math.Rounding.Ceil);
        uint256 targetWithFullFee = Math.mulDiv(calc.seniorOutstanding + mintedWithFullFee, calc.targetPerPairWad, WAD);
        if (calc.reserveWad + fullFeeWad <= targetWithFullFee) return _fromWadCeil(fullFeeWad, profile.decimals);

        uint256 dueWad = _cappedInsuranceDueWad(calc);
        if (dueWad > fullFeeWad) dueWad = fullFeeWad;
        return _fromWadCeil(dueWad, profile.decimals);
    }

    function _cappedInsuranceDueWad(InsuranceCalc memory calc) internal pure returns (uint256 dueWad) {
        uint256 currentTarget = Math.mulDiv(calc.seniorOutstanding, calc.targetPerPairWad, WAD);
        uint256 denominator = calc.collateralPerPairWad + calc.targetPerPairWad;
        if (calc.reserveWad >= currentTarget) {
            uint256 surplus = calc.reserveWad - currentTarget;
            uint256 surplusRequiredToSkip =
                Math.mulDiv(calc.netCollateralWad, calc.targetPerPairWad, calc.collateralPerPairWad);
            if (surplus >= surplusRequiredToSkip) return 0;
            return
                Math.mulDiv(surplusRequiredToSkip - surplus, calc.collateralPerPairWad, denominator, Math.Rounding.Ceil);
        }

        uint256 deficit = currentTarget - calc.reserveWad;
        return Math.mulDiv(deficit, calc.collateralPerPairWad, denominator, Math.Rounding.Ceil)
            + Math.mulDiv(calc.netCollateralWad, calc.targetPerPairWad, denominator, Math.Rounding.Ceil);
    }

    function _drawInsuranceForSeniorShortfall(
        uint256 seriesId,
        RiskSeries storage series,
        StableCollateralProfile storage profile,
        uint256 priceWad
    ) internal {
        uint256 seniorReserve = _seniorReserveCollateral(series.seniorOutstanding, priceWad, profile.decimals);
        if (series.accountedCollateral >= seniorReserve) return;

        uint256 shortfall = seniorReserve - series.accountedCollateral;
        if (profile.insuranceReserve < shortfall) {
            revert InsuranceInsufficient(series.profileId, shortfall, profile.insuranceReserve);
        }

        profile.insuranceReserve -= shortfall;
        profile.accountedCollateral += shortfall;
        series.accountedCollateral += shortfall;
        emit InsuranceDrawn(series.profileId, seriesId, series.collateralToken, shortfall);
    }

    function _seniorReserveCollateral(uint256 eveUSDAmount, uint256 priceWad, uint8 decimals)
        internal
        pure
        returns (uint256)
    {
        if (eveUSDAmount == 0) return 0;
        uint256 collateralWad = Math.mulDiv(eveUSDAmount, WAD, priceWad, Math.Rounding.Ceil);
        return _fromWadCeil(collateralWad, decimals);
    }

    function _insuranceTarget(StableCollateralProfile memory profile, uint256 priceWad)
        internal
        pure
        returns (uint256)
    {
        if (profile.insuranceTargetBps == 0 || profile.seniorOutstanding == 0) return 0;
        uint256 targetValueWad = Math.mulDiv(profile.seniorOutstanding, profile.insuranceTargetBps, BPS_DENOMINATOR);
        uint256 targetCollateralWad = Math.mulDiv(targetValueWad, WAD, priceWad, Math.Rounding.Ceil);
        return _fromWadCeil(targetCollateralWad, profile.decimals);
    }

    function _collateralValueWad(uint8 decimals, uint256 rawAmount, uint256 priceWad) internal pure returns (uint256) {
        return Math.mulDiv(_toWad(rawAmount, decimals), priceWad, WAD);
    }

    function _collateralRatioBps(uint8 decimals, uint256 rawAmount, uint256 liabilities, uint256 priceWad)
        internal
        pure
        returns (uint256)
    {
        if (liabilities == 0) return type(uint256).max;
        return Math.mulDiv(_collateralValueWad(decimals, rawAmount, priceWad), BPS_DENOMINATOR, liabilities);
    }

    function _toWad(uint256 rawAmount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return rawAmount;
        return rawAmount * 10 ** (18 - decimals);
    }

    function _fromWadCeil(uint256 wadAmount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return wadAmount;
        return Math.mulDiv(wadAmount, 1, 10 ** (18 - decimals), Math.Rounding.Ceil);
    }

    function _feeAmount(uint256 amount, uint256 feeBps) internal pure returns (uint256) {
        if (feeBps == 0) return 0;
        return Math.mulDiv(amount, feeBps, BPS_DENOMINATOR);
    }

    function _collectFee(address payer, address collateralToken, uint256 amount) internal {
        if (amount == 0) return;
        IERC20(collateralToken).safeTransfer(feeRecipient, amount);
        emit FeeCollected(payer, feeRecipient, collateralToken, amount);
    }

    function _pullExact(address collateralToken, address payer, uint256 amount) internal {
        uint256 beforeBalance = IERC20(collateralToken).balanceOf(address(this));
        IERC20(collateralToken).safeTransferFrom(payer, address(this), amount);
        uint256 received = IERC20(collateralToken).balanceOf(address(this)) - beforeBalance;
        if (received != amount) revert InvalidCollateralAmount(amount, received);
    }

    function _priceWad(StableCollateralProfile memory profile) internal view returns (uint256) {
        return IUsdOracle(profile.oracle).priceWad();
    }

    function _requireRecombinableSeries(uint256 seriesId) internal view {
        SeriesStatus status = _riskSeries[seriesId].status;
        if (
            status != SeriesStatus.Active && status != SeriesStatus.RecoveryPending
                && status != SeriesStatus.OperatorRecoverable
        ) {
            revert SeriesNotActive(seriesId);
        }
    }

    function _requireSeriesStatus(uint256 seriesId, SeriesStatus expected) internal view {
        if (_riskSeries[seriesId].status == SeriesStatus.None) revert InvalidSeries(seriesId);
        if (_riskSeries[seriesId].status != expected) {
            if (expected == SeriesStatus.Active) revert SeriesNotActive(seriesId);
            if (expected == SeriesStatus.RecoveryPending) revert RecoveryNotPending(seriesId);
            if (expected == SeriesStatus.OperatorRecoverable) revert RecoveryNotFinalized(seriesId);
            revert InvalidSeries(seriesId);
        }
    }

    function _requireProfile(uint256 profileId) internal view returns (StableCollateralProfile storage profile) {
        profile = _collateralProfiles[profileId];
        if (profile.collateralToken == address(0)) revert InvalidProfile(profileId);
    }

    function _requireProfileView(uint256 profileId) internal view returns (StableCollateralProfile memory profile) {
        profile = _collateralProfiles[profileId];
        if (profile.collateralToken == address(0)) revert InvalidProfile(profileId);
    }

    function _requireSeriesView(uint256 seriesId) internal view returns (RiskSeries memory series) {
        series = _riskSeries[seriesId];
        if (series.status == SeriesStatus.None) revert InvalidSeries(seriesId);
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

    function _validateInsuranceBps(uint256 bps) internal pure {
        if (bps > MAX_INSURANCE_BPS) revert InvalidInsuranceBps(bps);
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
