// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IEveUSDPool {
    enum SeriesStatus {
        None,
        Active,
        RecoveryPending,
        RecoveryFinalized,
        OperatorRecoverable,
        Retired
    }

    enum RecoveryClaimMode {
        CollateralDifference,
        MorePairs
    }

    struct StableCollateralProfile {
        address collateralToken;
        address oracle;
        uint8 decimals;
        uint16 collateralRatioBps;
        uint16 recoveryTriggerBps;
        uint16 mintFeeBps;
        uint16 recombinationFeeBps;
        uint16 insuranceTargetBps;
        uint16 insuranceFeeBps;
        bool enabled;
        uint256 activeSeriesId;
        uint256 accountedCollateral;
        uint256 insuranceReserve;
        uint256 seniorOutstanding;
    }

    struct RiskSeries {
        uint256 profileId;
        address collateralToken;
        uint256 seniorOutstanding;
        uint256 riskSharesOutstanding;
        uint256 returnedSharesSupply;
        uint256 accountedCollateral;
        uint256 startPriceWad;
        uint256 collateralPerPairWad;
        uint256 collateralRatioBps;
        uint256 recoveryTriggerBps;
        uint256 startedAt;
        uint256 recoveryStartedAt;
        uint256 recoveryEndsAt;
        uint256 finalizedAt;
        uint256 successorSeriesId;
        SeriesStatus status;
    }

    struct DepositPreview {
        uint256 profileId;
        uint256 seriesId;
        uint256 collateralIn;
        uint256 eveUSDMinted;
        uint256 sharesMinted;
        uint256 feeAmount;
        uint256 insuranceContribution;
        uint256 priceWad;
        uint256 collateralPerPairWad;
        uint256 collateralRatioBpsAfter;
    }

    struct RedemptionPreview {
        uint256 profileId;
        uint256 seriesId;
        address collateralToken;
        uint256 eveUSDBurned;
        uint256 sharesBurned;
        uint256 collateralOut;
        uint256 feeAmount;
        uint256 priceWad;
        uint256 collateralRatioBpsAfter;
    }

    struct OperatorRecoveryPreview {
        uint256 oldSeriesId;
        uint256 newSeriesId;
        uint256 sharesBurned;
        uint256 sharesMinted;
        uint256 collateralMoved;
        uint256 eveUSDMinted;
    }

    struct RecoveredRiskClaimPreview {
        uint256 oldSeriesId;
        uint256 newSeriesId;
        uint256 returnedShares;
        uint256 oldClaimCollateral;
        uint256 baseNewClaimCollateral;
        uint256 seniorReserveCollateral;
        uint256 juniorResidualCollateral;
        uint256 seniorShortfallCollateral;
        uint256 surplusCollateral;
        uint256 collateralMoved;
        uint256 sharesMinted;
        uint256 eveUSDMinted;
        uint256 collateralOut;
        RecoveryClaimMode mode;
    }

    error ZeroAddress();
    error ZeroAmount();
    error ContractExpected(address account);
    error InvalidTokenPool(address token, address expectedPool, address actualPool);
    error InvalidCollateralRatio(uint256 collateralRatioBps);
    error InvalidRecoveryTrigger(uint256 recoveryTriggerBps);
    error InvalidFeeBps(uint256 feeBps);
    error InvalidInsuranceBps(uint256 bps);
    error InvalidRecoveryTimelock(uint256 duration);
    error InvalidProfile(uint256 profileId);
    error ProfileDisabled(uint256 profileId);
    error InvalidCollateralDecimals(uint8 decimals);
    error InvalidCollateralAmount(uint256 expectedAmount, uint256 actualAmount);
    error Unauthorized(address caller);
    error ConfigLocked();
    error DepositTooSmall();
    error RedemptionTooSmall();
    error InvalidShareAmount(uint256 provided, uint256 required);
    error EmptyPool();
    error InvalidSeries(uint256 seriesId);
    error SeriesNotActive(uint256 seriesId);
    error RecoveryRequired(uint256 profileId, uint256 seriesId, uint256 currentPriceWad, uint256 triggerPriceWad);
    error RecoveryNotEligible(uint256 currentPriceWad, uint256 triggerPriceWad);
    error RecoveryNotPending(uint256 seriesId);
    error RecoveryTimelockActive(uint256 endsAt);
    error RecoveryRestored(uint256 currentPriceWad, uint256 triggerPriceWad);
    error RecoveryNotFinalized(uint256 seriesId);
    error NoReturnedShares(uint256 seriesId, address account);
    error InsuranceInsufficient(uint256 profileId, uint256 requiredAmount, uint256 availableAmount);

    event CollateralProfileCreated(
        uint256 indexed profileId,
        address indexed collateralToken,
        address indexed oracle,
        uint8 decimals,
        uint256 activeSeriesId
    );
    event CollateralProfileConfigured(
        uint256 indexed profileId, uint256 collateralRatioBps, uint256 recoveryTriggerBps, bool enabled
    );
    event CollateralProfileOracleSet(uint256 indexed profileId, address indexed oracle);
    event CollateralProfileFeeBpsSet(uint256 indexed profileId, uint256 mintFeeBps, uint256 recombinationFeeBps);
    event CollateralProfileInsuranceBpsSet(uint256 indexed profileId, uint256 targetBps, uint256 feeBps);

    event Deposited(
        address indexed caller,
        address indexed eveUSDReceiver,
        address indexed shareReceiver,
        uint256 profileId,
        uint256 seriesId,
        uint256 collateralAmount,
        uint256 eveUSDMinted,
        uint256 sharesMinted,
        uint256 priceWad,
        uint256 collateralPerPairWad
    );

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event ConfigLockedForever(address indexed owner);
    event RecoveryTimelockSet(uint256 recoveryTimelock);
    event FeeRecipientSet(address indexed feeRecipient);
    event FeeCollected(
        address indexed payer, address indexed recipient, address indexed collateralToken, uint256 amount
    );
    event InsuranceContributed(
        address indexed payer, uint256 indexed profileId, address indexed collateralToken, uint256 amount
    );
    event InsuranceToppedUp(
        address indexed payer, uint256 indexed profileId, address indexed collateralToken, uint256 amount
    );
    event InsuranceDrawn(
        uint256 indexed profileId, uint256 indexed seriesId, address indexed collateralToken, uint256 amount
    );

    event Recombined(
        address indexed caller,
        address indexed receiver,
        uint256 indexed seriesId,
        uint256 eveUSDBurned,
        uint256 sharesBurned,
        address collateralToken,
        uint256 collateralOut,
        uint256 collateralRatioBpsAfter
    );

    event RecoveryStarted(
        uint256 indexed profileId, uint256 indexed seriesId, uint256 recoveryEndsAt, uint256 priceWad
    );
    event RiskSharesReturned(address indexed account, uint256 indexed seriesId, uint256 shares);
    event ReturnedRiskSharesReclaimed(address indexed account, uint256 indexed seriesId, uint256 shares);
    event RecoveryCancelled(uint256 indexed profileId, uint256 indexed seriesId);
    event RecoveryFinalized(
        uint256 indexed profileId, uint256 indexed oldSeriesId, uint256 indexed newSeriesId, uint256 priceWad
    );
    event RecoveredRiskSharesClaimed(
        address indexed account,
        uint256 indexed oldSeriesId,
        uint256 indexed newSeriesId,
        RecoveryClaimMode mode,
        uint256 returnedShares,
        uint256 sharesMinted,
        uint256 eveUSDMinted,
        uint256 collateralOut
    );
    event ExpiredRiskRecovered(
        address indexed operator,
        address indexed holder,
        uint256 indexed oldSeriesId,
        uint256 newSeriesId,
        uint256 sharesBurned,
        uint256 sharesMinted,
        uint256 eveUSDMinted
    );

    function depositCollateral(
        uint256 profileId,
        uint256 collateralAmount,
        address eveUSDReceiver,
        address shareReceiver
    ) external returns (uint256 seriesId, uint256 eveUSDMinted, uint256 sharesMinted);

    function transferOwnership(address newOwner) external;

    function lockConfig() external;

    function createCollateralProfile(
        address collateralToken,
        address oracle,
        uint256 collateralRatioBps,
        uint256 recoveryTriggerBps,
        uint256 mintFeeBps,
        uint256 recombinationFeeBps,
        bool enabled
    ) external returns (uint256 profileId, uint256 seriesId);

    function setCollateralProfileOracle(uint256 profileId, address newOracle) external;

    function setCollateralProfileConfig(
        uint256 profileId,
        uint256 newCollateralRatioBps,
        uint256 newRecoveryTriggerBps,
        bool enabled
    ) external;

    function setCollateralProfileFeeBps(uint256 profileId, uint256 newMintFeeBps, uint256 newRecombinationFeeBps)
        external;

    function setCollateralProfileInsuranceBps(
        uint256 profileId,
        uint256 newInsuranceTargetBps,
        uint256 newInsuranceFeeBps
    ) external;

    function setRecoveryTimelock(uint256 newRecoveryTimelock) external;

    function setFeeRecipient(address newFeeRecipient) external;

    function topUpInsurance(uint256 profileId, uint256 amount) external;

    function recombine(uint256 seriesId, uint256 eveUSDAmount, uint256 shareAmount, address receiver)
        external
        returns (uint256 collateralOut);

    function startRecovery(uint256 seriesId) external;

    function returnRiskShares(uint256 seriesId, uint256 shares) external;

    function reclaimReturnedRiskShares(uint256 seriesId, address receiver) external returns (uint256 shares);

    function cancelRecovery(uint256 seriesId) external;

    function finalizeRecovery(uint256 seriesId) external returns (uint256 newSeriesId);

    function claimRecoveredRiskShares(uint256 oldSeriesId, address receiver, RecoveryClaimMode mode)
        external
        returns (uint256 sharesMinted, uint256 eveUSDMinted, uint256 collateralOut);

    function recoverExpiredRisk(address holder, uint256 oldSeriesId, uint256 shares)
        external
        returns (uint256 newSeriesId, uint256 sharesMinted, uint256 eveUSDMinted);

    function previewDeposit(uint256 profileId, uint256 collateralAmount)
        external
        view
        returns (DepositPreview memory preview);

    function previewRecombine(uint256 seriesId, uint256 eveUSDAmount)
        external
        view
        returns (RedemptionPreview memory preview);

    function requiredSharesForRecombine(uint256 seriesId, uint256 eveUSDAmount) external pure returns (uint256 shares);

    function previewOperatorRecovery(address holder, uint256 oldSeriesId, uint256 shares)
        external
        view
        returns (OperatorRecoveryPreview memory preview);

    function previewRecoveredRiskClaim(address account, uint256 oldSeriesId, RecoveryClaimMode mode)
        external
        view
        returns (RecoveredRiskClaimPreview memory preview);

    function collateralProfile(uint256 profileId) external view returns (StableCollateralProfile memory profile);

    function riskSeries(uint256 seriesId) external view returns (RiskSeries memory series);

    function returnedShares(uint256 seriesId, address account) external view returns (uint256 shares);

    function totalCollateral(address collateralToken) external view returns (uint256 amount);

    function seriesCollateralValueWad(uint256 seriesId) external view returns (uint256 usdValueWad);

    function seriesCollateralRatioBps(uint256 seriesId) external view returns (uint256 ratioBps);

    function collateralUsdPriceWad(uint256 profileId) external view returns (uint256 priceWad);

    function seniorLiabilities() external view returns (uint256 eveUSDAmount);

    function insuranceReserve(uint256 profileId) external view returns (uint256 amount);

    function insuranceTarget(uint256 profileId) external view returns (uint256 amount);

    function insuranceDeficit(uint256 profileId) external view returns (uint256 amount);

    function profileSeniorLiabilities(uint256 profileId) external view returns (uint256 eveUSDAmount);

    function eveUSD() external view returns (address);

    function evRisk() external view returns (address);

    function firstCollateralProfileId() external view returns (uint256 profileId);
}
