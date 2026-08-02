// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IEveUSDPool {
    enum SeriesStatus {
        None,
        Active,
        RecoveryPending,
        RecoveryFinalized,
        Liquidatable,
        Retired
    }

    enum RecoveryClaimMode {
        WETHDifference,
        MorePairs
    }

    struct RiskSeries {
        uint256 eveUSDSupply;
        uint256 sharesSupply;
        uint256 returnedSharesSupply;
        uint256 accountedCollateral;
        uint256 startPriceWad;
        uint256 wethPerPairWad;
        uint256 collateralRatioBps;
        uint256 recoveryTriggerBps;
        uint256 startedAt;
        uint256 recoveryStartedAt;
        uint256 recoveryEndsAt;
        uint256 finalizedAt;
        uint256 nextSeriesId;
        SeriesStatus status;
    }

    struct DepositPreview {
        uint256 seriesId;
        uint256 collateralIn;
        uint256 eveUSDMinted;
        uint256 sharesMinted;
        uint256 feeAmount;
        uint256 priceWad;
        uint256 wethPerPairWad;
        uint256 collateralRatioBpsAfter;
    }

    struct RedemptionPreview {
        uint256 seriesId;
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
        uint256 oldClaimWeth;
        uint256 baseNewClaimWeth;
        uint256 surplusWeth;
        uint256 collateralMoved;
        uint256 sharesMinted;
        uint256 eveUSDMinted;
        uint256 wethOut;
        RecoveryClaimMode mode;
    }

    error ZeroAddress();
    error ZeroAmount();
    error ContractExpected(address account);
    error InvalidTokenPool(address token, address expectedPool, address actualPool);
    error InvalidCollateralRatio(uint256 collateralRatioBps);
    error InvalidRecoveryTrigger(uint256 recoveryTriggerBps);
    error InvalidFeeBps(uint256 feeBps);
    error InvalidRecoveryTimelock(uint256 duration);
    error Unauthorized(address caller);
    error ConfigLocked();
    error DepositTooSmall();
    error RedemptionTooSmall();
    error InvalidShareAmount(uint256 provided, uint256 required);
    error EmptyPool();
    error InvalidSeries(uint256 seriesId);
    error SeriesNotActive(uint256 seriesId);
    error RecoveryNotEligible(uint256 currentPriceWad, uint256 triggerPriceWad);
    error RecoveryNotPending(uint256 seriesId);
    error RecoveryTimelockActive(uint256 endsAt);
    error RecoveryRestored(uint256 currentPriceWad, uint256 triggerPriceWad);
    error RecoveryNotFinalized(uint256 seriesId);
    error NoReturnedShares(uint256 seriesId, address account);
    error RecoveryClaimValueInsufficient(uint256 oldClaimWeth, uint256 baseNewClaimWeth);

    event Deposited(
        address indexed caller,
        address indexed eveUSDReceiver,
        address indexed shareReceiver,
        uint256 seriesId,
        uint256 wethAmount,
        uint256 eveUSDMinted,
        uint256 sharesMinted,
        uint256 priceWad,
        uint256 wethPerPairWad
    );

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event ConfigLockedForever(address indexed owner);
    event OracleSet(address indexed oracle);
    event NextSeriesConfigSet(uint256 collateralRatioBps, uint256 recoveryTriggerBps);
    event RecoveryTimelockSet(uint256 recoveryTimelock);
    event FeeRecipientSet(address indexed feeRecipient);
    event FeeBpsSet(uint256 mintFeeBps, uint256 recombinationFeeBps);
    event FeeCollected(address indexed payer, address indexed recipient, uint256 amount);

    event Recombined(
        address indexed caller,
        address indexed receiver,
        uint256 indexed seriesId,
        uint256 eveUSDBurned,
        uint256 sharesBurned,
        uint256 wethOut,
        uint256 collateralRatioBpsAfter
    );

    event RecoveryStarted(uint256 indexed seriesId, uint256 recoveryEndsAt, uint256 priceWad);
    event RiskSharesReturned(address indexed account, uint256 indexed seriesId, uint256 shares);
    event ReturnedRiskSharesReclaimed(address indexed account, uint256 indexed seriesId, uint256 shares);
    event RecoveryCancelled(uint256 indexed seriesId);
    event RecoveryFinalized(uint256 indexed oldSeriesId, uint256 indexed newSeriesId, uint256 priceWad);
    event RecoveredRiskSharesClaimed(
        address indexed account,
        uint256 indexed oldSeriesId,
        uint256 indexed newSeriesId,
        RecoveryClaimMode mode,
        uint256 returnedShares,
        uint256 sharesMinted,
        uint256 eveUSDMinted,
        uint256 wethOut
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

    function depositWETH(uint256 wethAmount, address eveUSDReceiver, address shareReceiver)
        external
        returns (uint256 seriesId, uint256 eveUSDMinted, uint256 sharesMinted);

    function transferOwnership(address newOwner) external;

    function lockConfig() external;

    function setOracle(address newOracle) external;

    function setNextSeriesConfig(uint256 newCollateralRatioBps, uint256 newRecoveryTriggerBps) external;

    function setRecoveryTimelock(uint256 newRecoveryTimelock) external;

    function setFeeRecipient(address newFeeRecipient) external;

    function setFeeBps(uint256 newMintFeeBps, uint256 newRecombinationFeeBps) external;

    function recombine(uint256 seriesId, uint256 eveUSDAmount, uint256 shareAmount, address receiver)
        external
        returns (uint256 wethOut);

    function startRecovery(uint256 seriesId) external;

    function returnRiskShares(uint256 seriesId, uint256 shares) external;

    function reclaimReturnedRiskShares(uint256 seriesId, address receiver) external returns (uint256 shares);

    function cancelRecovery(uint256 seriesId) external;

    function finalizeRecovery(uint256 seriesId) external returns (uint256 newSeriesId);

    function claimRecoveredRiskShares(uint256 oldSeriesId, address receiver, RecoveryClaimMode mode)
        external
        returns (uint256 sharesMinted, uint256 eveUSDMinted, uint256 wethOut);

    function recoverExpiredRisk(address holder, uint256 oldSeriesId, uint256 shares)
        external
        returns (uint256 newSeriesId, uint256 sharesMinted, uint256 eveUSDMinted);

    function previewDeposit(uint256 wethAmount) external view returns (DepositPreview memory preview);

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

    function riskSeries(uint256 seriesId) external view returns (RiskSeries memory series);

    function returnedShares(uint256 seriesId, address account) external view returns (uint256 shares);

    function totalCollateral() external view returns (uint256 wethAmount);

    function seniorLiabilities() external view returns (uint256 eveUSDAmount);

    function collateralValueWad() external view returns (uint256 usdValueWad);

    function collateralRatioBps() external view returns (uint256 ratioBps);

    function weth() external view returns (address);

    function eveUSD() external view returns (address);

    function evRisk() external view returns (address);

    function currentRiskSeriesId() external view returns (uint256 seriesId);
}
