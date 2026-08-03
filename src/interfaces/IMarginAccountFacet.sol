// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {MarginTypes} from "../types/MarginTypes.sol";
import {MarkOracleTypes} from "../types/MarkOracleTypes.sol";
import {MLOProfitShareTypes} from "../types/MLOProfitShareTypes.sol";

interface IMarginAccountFacet {
    error ZeroAmount();
    error ZeroAddress();
    error ContractHasNoCode(address account);
    error MarginAssetNotSet();
    error MarginAssetInUse(uint256 liabilities);
    error NonExactMarginTransfer(uint256 expected, uint256 actual);
    error InvalidRiskDomain(bytes32 riskDomainId);
    error MarginBucketNotFound(bytes32 bucketId);
    error NotMarginBucketOperator(address caller, address operator);
    error InsufficientFreeMargin(address operator, uint256 required, uint256 available);
    error InsufficientBucketMargin(bytes32 bucketId, uint256 required, uint256 available);
    error InsufficientReservedRisk(bytes32 bucketId, uint256 required, uint256 available);
    error InsufficientActiveRisk(bytes32 bucketId, uint256 required, uint256 available);
    error InsufficientOpenOrderRisk(bytes32 bucketId, uint256 required, uint256 available);
    error InsufficientPositionRisk(bytes32 bucketId, uint256 required, uint256 available);
    error InsufficientDebt(bytes32 bucketId, uint256 required, uint256 available);
    error InsufficientFundingLiability(bytes32 bucketId, uint256 required, uint256 available);
    error BucketMarginLocked(bytes32 bucketId, uint256 requested, uint256 locked);
    error BucketCannotIncreaseRisk(bytes32 bucketId, MarginTypes.BucketState state);
    error InvalidMarginRiskParams(uint256 initialMarginBps, uint256 maintenanceMarginBps);
    error MLOInitialMarginMustBeFull(uint256 initialMarginBps);
    error InvalidRiskMarkConfig(uint256 lookbackSeconds, uint256 assetHaircutBps, uint256 liabilityPremiumBps);
    error InvalidFundingConfig(MarginTypes.FundingMode mode, uint256 ratePerSecondWad);
    error BucketBelowInitialMargin(bytes32 bucketId, uint256 equity, uint256 required);
    error RiskDomainOracleBlocked(
        bytes32 riskDomainId, bytes32 oracleKey, MarginTypes.RiskDomainOracleKind kind, uint8 oracleState
    );
    error ScenarioManagedBucket(bytes32 bucketId);
    error BucketMarginFrozen(bytes32 bucketId, MarginTypes.BucketState state);
    error ClosedBucketHasObligations(bytes32 bucketId, uint256 lockedAssets);

    event MarginAssetSet(address indexed previousAsset, address indexed newAsset);
    event WarningRiskIncreaseAllowedSet(bool allowed);
    event MarginDeposited(address indexed caller, address indexed receiver, uint256 assets);
    event MarginWithdrawn(address indexed caller, address indexed receiver, uint256 assets);
    event MarginBucketCreated(address indexed operator, bytes32 indexed riskDomainId, bytes32 indexed bucketId);
    event MarginBucketKindSet(bytes32 indexed bucketId, MarginTypes.BucketKind kind);
    event BucketMarginAllocated(address indexed operator, bytes32 indexed bucketId, uint256 assets);
    event BucketMarginReleased(address indexed operator, bytes32 indexed bucketId, uint256 assets);
    event BucketRiskReserved(bytes32 indexed bucketId, uint256 assets);
    event BucketReservedRiskReleased(bytes32 indexed bucketId, uint256 assets);
    event BucketRiskActivated(bytes32 indexed bucketId, uint256 assets);
    event BucketActiveRiskReleased(bytes32 indexed bucketId, uint256 assets);
    event BucketOpenOrderRiskIncreased(bytes32 indexed bucketId, uint256 assets);
    event BucketOpenOrderRiskReleased(bytes32 indexed bucketId, uint256 assets);
    event BucketOpenOrderRiskMovedToPosition(bytes32 indexed bucketId, uint256 assets);
    event BucketPositionRiskReleased(bytes32 indexed bucketId, uint256 assets);
    event BucketDebtRecorded(bytes32 indexed bucketId, uint256 assets);
    event BucketDebtRepaid(bytes32 indexed bucketId, uint256 assets);
    event BucketFundingAccrued(bytes32 indexed bucketId, uint256 assets);
    event BucketFundingSettled(bytes32 indexed bucketId, uint256 assets);
    event BucketFundingWrittenOff(bytes32 indexed bucketId, uint256 assets);
    event BucketUnrealizedPnlRecorded(bytes32 indexed bucketId, uint256 profits, uint256 losses);
    event BucketRecoveryPnlRecorded(bytes32 indexed bucketId, uint256 profits, uint256 losses);
    event BucketBadDebtRecorded(bytes32 indexed bucketId, uint256 assets);
    event BucketProfitRecorded(bytes32 indexed bucketId, uint256 assets);
    event BucketLossRecorded(bytes32 indexed bucketId, uint256 assets);
    event BucketStateSet(
        bytes32 indexed bucketId, MarginTypes.BucketState previousState, MarginTypes.BucketState newState
    );
    event ScenarioExposureInitialized(bytes32 indexed bucketId, bytes32 indexed marketId, uint8 outcomeCount);
    event ScenarioExposureUpdated(
        bytes32 indexed bucketId, bytes32 indexed marketId, uint8 outcomeCount, int256 maximumRawLoss
    );
    event DefaultRiskParamsSet(
        MarginTypes.BucketKind indexed kind, uint16 initialMarginBps, uint16 maintenanceMarginBps
    );
    event RiskDomainRiskParamsSet(
        bytes32 indexed riskDomainId,
        MarginTypes.BucketKind indexed kind,
        uint16 initialMarginBps,
        uint16 maintenanceMarginBps
    );
    event RiskDomainRiskParamsCleared(bytes32 indexed riskDomainId, MarginTypes.BucketKind indexed kind);
    event RiskDomainOracleConfigured(
        bytes32 indexed riskDomainId, MarginTypes.RiskDomainOracleKind kind, bytes32 indexed oracleKey
    );
    event RiskDomainMarkConfigSet(
        bytes32 indexed riskDomainId, uint32 lookbackSeconds, uint16 assetHaircutBps, uint16 liabilityPremiumBps
    );
    event RiskDomainFundingConfigSet(
        bytes32 indexed riskDomainId, MarginTypes.FundingMode mode, uint128 ratePerSecondWad
    );
    event DefaultFundingConfigSet(
        MarginTypes.BucketKind indexed kind, MarginTypes.FundingMode mode, uint128 ratePerSecondWad
    );

    function marginConfig() external view returns (MarginTypes.MarginConfig memory config);

    function depositMargin(uint256 assets, address receiver) external returns (uint256 credited);

    function withdrawMargin(uint256 assets, address receiver) external returns (uint256 withdrawn);

    function allocateBucketMargin(bytes32 riskDomainId, uint256 assets, uint256 expectedSplitVersion)
        external
        returns (bytes32 bucketId);

    function allocateBucketMarginWithKind(
        bytes32 riskDomainId,
        uint256 assets,
        MarginTypes.BucketKind kind,
        uint256 expectedSplitVersion
    ) external returns (bytes32 bucketId);

    function releaseBucketMargin(bytes32 bucketId, uint256 assets)
        external
        returns (MLOProfitShareTypes.ProfitRelease memory release);

    function getMarginAccount(address operator) external view returns (MarginTypes.MarginAccount memory account);

    function getMarginBucket(bytes32 bucketId) external view returns (MarginTypes.MarginBucket memory bucket);

    function getBucketRisk(bytes32 bucketId) external view returns (MarginTypes.BucketRisk memory risk);

    function bucketHealth(bytes32 bucketId) external view returns (MarginTypes.BucketHealth memory health);

    function riskParamsForBucket(bytes32 bucketId) external view returns (MarginTypes.RiskParams memory params);

    function defaultRiskParams(MarginTypes.BucketKind kind) external view returns (MarginTypes.RiskParams memory params);

    function riskDomainRiskParams(bytes32 riskDomainId, MarginTypes.BucketKind kind)
        external
        view
        returns (MarginTypes.RiskParams memory params);

    function bucketLockedRisk(bytes32 bucketId) external view returns (uint256 locked);

    function bucketIdFor(address operator, bytes32 riskDomainId) external pure returns (bytes32 bucketId);

    function riskDomainForBook(bytes32 bookId) external pure returns (bytes32 riskDomainId);

    function riskDomainForMarket(bytes32 marketId) external pure returns (bytes32 riskDomainId);

    function canBucketIncreaseRisk(bytes32 bucketId) external view returns (bool canIncrease);

    function canBucketIncreaseRiskForBook(bytes32 bucketId, bytes32 bookId) external view returns (bool canIncrease);

    function riskDomainOracleConfig(bytes32 riskDomainId)
        external
        view
        returns (MarginTypes.RiskDomainOracleConfig memory config);

    function riskDomainMarkConfig(bytes32 riskDomainId)
        external
        view
        returns (MarkOracleTypes.RiskMarkConfig memory config);

    function riskDomainRiskMark(bytes32 riskDomainId) external view returns (MarkOracleTypes.RiskMark memory mark);

    function riskDomainFundingConfig(bytes32 riskDomainId)
        external
        view
        returns (MarginTypes.FundingConfig memory config);

    function defaultFundingConfig(MarginTypes.BucketKind kind)
        external
        view
        returns (MarginTypes.FundingConfig memory config);

    function setMarginAsset(address asset) external;

    function setWarningRiskIncreaseAllowed(bool allowed) external;

    function setRiskDomainOracleConfig(bytes32 riskDomainId, MarginTypes.RiskDomainOracleKind kind, bytes32 oracleKey)
        external;

    function setRiskDomainMarkConfig(
        bytes32 riskDomainId,
        uint32 lookbackSeconds,
        uint16 assetHaircutBps,
        uint16 liabilityPremiumBps
    ) external;

    function setRiskDomainFundingConfig(bytes32 riskDomainId, MarginTypes.FundingMode mode, uint128 ratePerSecondWad)
        external;

    function setDefaultFundingConfig(
        MarginTypes.BucketKind kind,
        MarginTypes.FundingMode mode,
        uint128 ratePerSecondWad
    ) external;

    function setDefaultRiskParams(MarginTypes.BucketKind kind, uint16 initialMarginBps, uint16 maintenanceMarginBps)
        external;

    function setRiskDomainRiskParams(
        bytes32 riskDomainId,
        MarginTypes.BucketKind kind,
        uint16 initialMarginBps,
        uint16 maintenanceMarginBps
    ) external;

    function clearRiskDomainRiskParams(bytes32 riskDomainId, MarginTypes.BucketKind kind) external;

    function accrueBucketFundingNow(bytes32 bucketId) external returns (uint256 accrued);
}
