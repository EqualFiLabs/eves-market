// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IMarginAccountFacet} from "../interfaces/IMarginAccountFacet.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibMarginAccount} from "../libraries/LibMarginAccount.sol";
import {LibReentrancy} from "../libraries/LibReentrancy.sol";
import {LibRiskEngine} from "../libraries/LibRiskEngine.sol";
import {MarginTypes} from "../types/MarginTypes.sol";
import {MarkOracleTypes} from "../types/MarkOracleTypes.sol";

contract MarginAccountFacet is IMarginAccountFacet {
    modifier nonReentrant() {
        LibReentrancy.enter();
        _;
        LibReentrancy.exit();
    }

    function marginConfig() external view returns (MarginTypes.MarginConfig memory config) {
        config = LibMarginAccount.marginConfig(LibEveMarket.store());
    }

    function depositMargin(uint256 assets, address receiver) external nonReentrant returns (uint256 credited) {
        credited = LibMarginAccount.deposit(LibEveMarket.store(), assets, receiver);
    }

    function withdrawMargin(uint256 assets, address receiver) external nonReentrant returns (uint256 withdrawn) {
        withdrawn = LibMarginAccount.withdraw(LibEveMarket.store(), assets, receiver);
    }

    function allocateBucketMargin(bytes32 riskDomainId, uint256 assets) external returns (bytes32 bucketId) {
        bucketId = LibMarginAccount.allocateToBucket(LibEveMarket.store(), riskDomainId, assets);
    }

    function allocateBucketMarginWithKind(bytes32 riskDomainId, uint256 assets, MarginTypes.BucketKind kind)
        external
        returns (bytes32 bucketId)
    {
        bucketId = LibMarginAccount.allocateToBucketWithKind(LibEveMarket.store(), riskDomainId, assets, kind);
    }

    function releaseBucketMargin(bytes32 bucketId, uint256 assets) external {
        LibMarginAccount.releaseFromBucket(LibEveMarket.store(), bucketId, assets);
    }

    function getMarginAccount(address operator) external view returns (MarginTypes.MarginAccount memory account) {
        account = LibEveMarket.store().marginAccounts[operator];
    }

    function getMarginBucket(bytes32 bucketId) external view returns (MarginTypes.MarginBucket memory bucket) {
        bucket = LibEveMarket.store().marginBuckets[bucketId];
    }

    function getBucketRisk(bytes32 bucketId) external view returns (MarginTypes.BucketRisk memory risk) {
        risk = LibRiskEngine.bucketRisk(LibEveMarket.store(), bucketId);
    }

    function bucketHealth(bytes32 bucketId) external view returns (MarginTypes.BucketHealth memory health) {
        health = LibRiskEngine.bucketHealth(LibEveMarket.store(), bucketId);
    }

    function riskParamsForBucket(bytes32 bucketId) external view returns (MarginTypes.RiskParams memory params) {
        params = LibRiskEngine.riskParamsForBucket(LibEveMarket.store(), bucketId);
    }

    function defaultRiskParams(MarginTypes.BucketKind kind)
        external
        view
        returns (MarginTypes.RiskParams memory params)
    {
        params = LibEveMarket.store().marginDefaultRiskParams[uint8(kind)];
        if (params.initialMarginBps == 0 && params.maintenanceMarginBps == 0) {
            params = MarginTypes.RiskParams({initialMarginBps: 10_000, maintenanceMarginBps: 10_000});
        }
    }

    function riskDomainRiskParams(bytes32 riskDomainId) external view returns (MarginTypes.RiskParams memory params) {
        params = LibEveMarket.store().marginRiskDomainParams[riskDomainId];
    }

    function bucketLockedRisk(bytes32 bucketId) external view returns (uint256 locked) {
        MarginTypes.MarginBucket storage bucket = LibRiskEngine.requireBucket(LibEveMarket.store(), bucketId);
        locked = LibRiskEngine.lockedRisk(bucket);
    }

    function bucketIdFor(address operator, bytes32 riskDomainId) external pure returns (bytes32 bucketId) {
        bucketId = LibMarginAccount.bucketIdFor(operator, riskDomainId);
    }

    function riskDomainForBook(bytes32 bookId) external pure returns (bytes32 riskDomainId) {
        riskDomainId = LibMarginAccount.riskDomainForBook(bookId);
    }

    function riskDomainForMarketBook(bytes32 marketId, bytes32 bookId) external pure returns (bytes32 riskDomainId) {
        riskDomainId = LibMarginAccount.riskDomainForMarketBook(marketId, bookId);
    }

    function canBucketIncreaseRisk(bytes32 bucketId) external view returns (bool canIncrease) {
        canIncrease = LibMarginAccount.canIncreaseRisk(LibEveMarket.store(), bucketId);
    }

    function canBucketIncreaseRiskForBook(bytes32 bucketId, bytes32 bookId) external view returns (bool canIncrease) {
        canIncrease = LibMarginAccount.canIncreaseRiskForBook(LibEveMarket.store(), bucketId, bookId);
    }

    function riskDomainOracleConfig(bytes32 riskDomainId)
        external
        view
        returns (MarginTypes.RiskDomainOracleConfig memory config)
    {
        config = LibEveMarket.store().marginRiskDomainOracles[riskDomainId];
    }

    function riskDomainMarkConfig(bytes32 riskDomainId)
        external
        view
        returns (MarkOracleTypes.RiskMarkConfig memory config)
    {
        config = LibEveMarket.store().marginRiskDomainMarkConfigs[riskDomainId];
    }

    function riskDomainRiskMark(bytes32 riskDomainId) external view returns (MarkOracleTypes.RiskMark memory mark) {
        mark = LibRiskEngine.riskMarkForDomain(LibEveMarket.store(), riskDomainId);
    }

    function riskDomainFundingConfig(bytes32 riskDomainId)
        external
        view
        returns (MarginTypes.FundingConfig memory config)
    {
        config = LibEveMarket.store().marginRiskDomainFundingConfigs[riskDomainId];
    }

    function setMarginAsset(address asset) external {
        LibDiamond.enforceIsContractOwner();
        LibMarginAccount.setMarginAsset(LibEveMarket.store(), asset);
    }

    function setMarginRiskManager(address riskManager) external {
        LibDiamond.enforceIsContractOwner();
        LibMarginAccount.setRiskManager(LibEveMarket.store(), riskManager);
    }

    function setWarningRiskIncreaseAllowed(bool allowed) external {
        LibDiamond.enforceIsContractOwner();
        LibMarginAccount.setWarningRiskIncreaseAllowed(LibEveMarket.store(), allowed);
    }

    function setRiskDomainOracleConfig(bytes32 riskDomainId, MarginTypes.RiskDomainOracleKind kind, bytes32 oracleKey)
        external
    {
        LibDiamond.enforceIsContractOwner();
        LibRiskEngine.configureRiskDomainOracle(LibEveMarket.store(), riskDomainId, kind, oracleKey);
    }

    function setRiskDomainMarkConfig(
        bytes32 riskDomainId,
        uint32 lookbackSeconds,
        uint16 assetHaircutBps,
        uint16 liabilityPremiumBps
    ) external {
        LibDiamond.enforceIsContractOwner();
        LibRiskEngine.configureRiskDomainMark(
            LibEveMarket.store(), riskDomainId, lookbackSeconds, assetHaircutBps, liabilityPremiumBps
        );
    }

    function setRiskDomainFundingConfig(bytes32 riskDomainId, MarginTypes.FundingMode mode, uint128 ratePerSecondWad)
        external
    {
        LibDiamond.enforceIsContractOwner();
        LibRiskEngine.configureRiskDomainFunding(LibEveMarket.store(), riskDomainId, mode, ratePerSecondWad);
    }

    function setDefaultRiskParams(MarginTypes.BucketKind kind, uint16 initialMarginBps, uint16 maintenanceMarginBps)
        external
    {
        LibDiamond.enforceIsContractOwner();
        LibRiskEngine.configureDefaultRiskParams(LibEveMarket.store(), kind, initialMarginBps, maintenanceMarginBps);
    }

    function setRiskDomainRiskParams(bytes32 riskDomainId, uint16 initialMarginBps, uint16 maintenanceMarginBps)
        external
    {
        LibDiamond.enforceIsContractOwner();
        LibRiskEngine.configureRiskDomainRiskParams(
            LibEveMarket.store(), riskDomainId, initialMarginBps, maintenanceMarginBps
        );
    }

    function clearRiskDomainRiskParams(bytes32 riskDomainId) external {
        LibDiamond.enforceIsContractOwner();
        LibRiskEngine.clearRiskDomainRiskParams(LibEveMarket.store(), riskDomainId);
    }

    function reserveBucketRisk(bytes32 bucketId, uint256 assets) external {
        LibMarginAccount.reserveRisk(LibEveMarket.store(), bucketId, assets);
    }

    function releaseReservedBucketRisk(bytes32 bucketId, uint256 assets) external {
        LibMarginAccount.releaseReservedRisk(LibEveMarket.store(), bucketId, assets);
    }

    function activateReservedBucketRisk(bytes32 bucketId, uint256 assets) external {
        LibMarginAccount.activateReservedRisk(LibEveMarket.store(), bucketId, assets);
    }

    function releaseActiveBucketRisk(bytes32 bucketId, uint256 assets) external {
        LibMarginAccount.releaseActiveRisk(LibEveMarket.store(), bucketId, assets);
    }

    function increaseOpenOrderRisk(bytes32 bucketId, uint256 assets) external {
        LibMarginAccount.enforceRiskManager(LibEveMarket.store());
        LibRiskEngine.increaseOpenOrderRisk(LibEveMarket.store(), bucketId, assets);
    }

    function releaseOpenOrderRisk(bytes32 bucketId, uint256 assets) external {
        LibMarginAccount.enforceRiskManager(LibEveMarket.store());
        LibRiskEngine.releaseOpenOrderRisk(LibEveMarket.store(), bucketId, assets);
    }

    function moveOpenOrderToPositionRisk(bytes32 bucketId, uint256 assets) external {
        LibMarginAccount.enforceRiskManager(LibEveMarket.store());
        LibRiskEngine.moveOpenOrderToPositionRisk(LibEveMarket.store(), bucketId, assets);
    }

    function releasePositionRisk(bytes32 bucketId, uint256 assets) external {
        LibMarginAccount.enforceRiskManager(LibEveMarket.store());
        LibRiskEngine.releasePositionRisk(LibEveMarket.store(), bucketId, assets);
    }

    function recordBucketDebt(bytes32 bucketId, uint256 assets) external {
        LibMarginAccount.enforceRiskManager(LibEveMarket.store());
        LibRiskEngine.recordDebt(LibEveMarket.store(), bucketId, assets);
    }

    function repayBucketDebt(bytes32 bucketId, uint256 assets) external {
        LibMarginAccount.enforceRiskManager(LibEveMarket.store());
        LibRiskEngine.repayDebt(LibEveMarket.store(), bucketId, assets);
    }

    function accrueBucketFunding(bytes32 bucketId, uint256 assets) external {
        LibMarginAccount.enforceRiskManager(LibEveMarket.store());
        LibRiskEngine.accrueFunding(LibEveMarket.store(), bucketId, assets);
    }

    function accrueBucketFundingNow(bytes32 bucketId) external returns (uint256 accrued) {
        accrued = LibRiskEngine.accrueConfiguredFunding(LibEveMarket.store(), bucketId);
    }

    function settleBucketFunding(bytes32 bucketId, uint256 assets) external {
        LibMarginAccount.enforceRiskManager(LibEveMarket.store());
        LibRiskEngine.settleFunding(LibEveMarket.store(), bucketId, assets);
    }

    function recordBucketUnrealizedPnl(bytes32 bucketId, uint256 profits, uint256 losses) external {
        LibMarginAccount.enforceRiskManager(LibEveMarket.store());
        LibRiskEngine.recordUnrealizedPnl(LibEveMarket.store(), bucketId, profits, losses);
    }

    function recordBucketRecoveryPnl(bytes32 bucketId, uint256 profits, uint256 losses) external {
        LibMarginAccount.enforceRiskManager(LibEveMarket.store());
        LibRiskEngine.recordRecoveryPnl(LibEveMarket.store(), bucketId, profits, losses);
    }

    function recordBucketBadDebt(bytes32 bucketId, uint256 assets) external {
        LibMarginAccount.enforceRiskManager(LibEveMarket.store());
        LibRiskEngine.recordBadDebt(LibEveMarket.store(), bucketId, assets);
    }

    function recordBucketProfit(bytes32 bucketId, uint256 assets) external nonReentrant {
        LibMarginAccount.recordProfit(LibEveMarket.store(), bucketId, assets);
    }

    function recordBucketLoss(bytes32 bucketId, uint256 assets) external {
        LibMarginAccount.recordLoss(LibEveMarket.store(), bucketId, assets);
    }

    function setBucketState(bytes32 bucketId, MarginTypes.BucketState state) external {
        LibMarginAccount.setBucketState(LibEveMarket.store(), bucketId, state);
    }
}
