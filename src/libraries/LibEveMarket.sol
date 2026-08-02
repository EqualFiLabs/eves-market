// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {MarkOracleTypes} from "../types/MarkOracleTypes.sol";
import {MarginTypes} from "../types/MarginTypes.sol";
import {ProductAdapterTypes} from "../types/ProductAdapterTypes.sol";
import {QuoteEnvelopeTypes} from "../types/QuoteEnvelopeTypes.sol";

library LibEveMarket {
    bytes32 internal constant STORAGE_SLOT = bytes32(uint256(keccak256("eve.prediction.market.storage")) - 1);

    enum MarketType {
        CLOB,
        PARIMUTUEL,
        MULTI_OUTCOME_ORDERBOOK
    }

    enum PositionTokenType {
        CTF,
        PARIMUTUEL,
        EVES_POSITION
    }

    enum CurveSide {
        ASK,
        BID
    }

    enum BookAssetType {
        ERC1155,
        ERC20
    }

    enum BaseTransferMode {
        EXACT,
        BALANCE_DELTA
    }

    enum BookPricingMode {
        PREDICTION_PAYOUT,
        GENERIC
    }

    enum BookLifecycle {
        ACTIVE,
        DECOMMISSION_PENDING,
        DECOMMISSIONED
    }

    enum DelayedOrderKind {
        MarketBuy,
        LimitBuy,
        MarketSell,
        LimitSell
    }

    enum DelayedOrderStatus {
        Pending,
        Filled,
        PartiallyFilled,
        Resting,
        Cancelled,
        Expired,
        Refunded
    }

    enum ProcessingMode {
        ProtocolOnly,
        Permissionless,
        Paused
    }

    enum LowQuorumMode {
        Redraw,
        Escalate,
        FinalizeInvalid
    }

    enum TieBreakMode {
        Escalate,
        ResolveInvalid
    }

    enum RandomnessFailureMode {
        Retry,
        AllEligible
    }

    enum MarketState {
        Inactive,
        Scheduled,
        Trading,
        Pending,
        Resolved,
        Disputed
    }

    enum MarketOutcome {
        Unresolved,
        Yes,
        No,
        Invalid
    }

    struct BookFeeConfig {
        uint16 entryFeeBps;
        uint16 makerFeeBps;
        uint16 creatorFeeBps;
        uint16 protocolFeeBps;
        uint16 vaultFeeBps;
    }

    struct ParimutuelFeeConfig {
        uint16 entryFeeBps;
        uint16 creatorFeeBps;
        uint16 protocolFeeBps;
        uint16 vaultFeeBps;
    }

    struct SpotFeeConfig {
        uint16 tradeFeeBps;
        uint16 makerFeeBps;
        uint16 protocolFeeBps;
        uint16 vaultFeeBps;
    }

    struct ComboFeeConfig {
        uint16 tradeFeeBps;
        uint16 makerFeeBps;
        uint16 creatorFeeBps;
        uint16 protocolFeeBps;
        uint16 vaultFeeBps;
    }

    struct ResolverJuryConfig {
        uint128 identityMintFee;
        address identityMintFeeToken;
        uint128 resolverStakeRequirement;
        uint128 resolverStakeCap;
        uint16 resolverPoolCap;
        uint64 activationDelay;
        uint64 exitCooldown;
        uint16 participationThresholdBps;
        uint16 concurrencyLimit;
        uint32 participationGraceCount;
        uint256 conflictPositionThreshold;
        uint16[] committeeSizesByRound;
        uint8 maxAppealRounds;
        uint16 appealBondMultiplierBps;
        uint64 randomnessCommitDuration;
        uint64 randomnessRevealDuration;
        uint64 commitDuration;
        uint64 revealDuration;
        uint64 appealWindow;
        uint64 randomnessTimeout;
        uint32 quorum;
        uint16 redrawLimit;
        LowQuorumMode lowQuorumMode;
        TieBreakMode tieBreakMode;
        RandomnessFailureMode randomnessFailureMode;
        uint8 minRandomnessReveals;
        uint16 allEligibleFallbackCap;
        uint16 missedCommitSlashBps;
        uint16 missedRevealSlashBps;
        uint16 invalidRevealSlashBps;
        uint64 slashCooldown;
        uint16 protocolFeeAllocationBps;
        uint16[4] appealSuccessRoutingBps;
        uint16[3] appealFailureRoutingBps;
        uint128 incentiveSelectCommittee;
        uint128 incentiveCloseCommit;
        uint128 incentiveCloseReveal;
        uint128 incentiveOpenAppeal;
        uint128 incentiveFinalize;
        uint128 incentiveRandomness;
    }

    struct CollateralProfile {
        address collateralToken;
        address wrapperToken;
        uint128 payoutUnit;
        uint128 marketCreationFee;
        bool enabled;
    }

    struct MarketConfig {
        address defaultConditionalTokens;
        address evesPositionManager;
        address parimutuelShareToken;
        address collateralToken;
        address eveToken;
        address eveTreasury;
        address stakingVault;
        address secondaryStakingVault;
        address seniorCapitalPool;
        BookFeeConfig orderbookFeeConfig;
        SpotFeeConfig spotFeeConfig;
        ParimutuelFeeConfig parimutuelFeeConfig;
        uint128 parimutuelMinEntry;
        uint128 marketCreationFee;
        uint128 spotBookCreationFee;
        uint128 marketCreationBond;
        uint128 reservedConfigSlot0;
        uint128 reservedConfigSlot1;
        uint128 reservedConfigSlot2;
        uint128 reservedConfigSlot3;
        uint64 minMarketDuration;
        uint64 maxMarketDuration;
        uint64 disputeWindow;
        uint64 creatorSettleGrace;
        uint64 openResolutionTimeout;
        uint64 parimutuelEpochWindowCap;
        uint16[8] parimutuelEpochMultipliersBps;
        uint16 marketCreationBatchCap;
        uint8 maxEscalation;
        bool permissionlessCreationEnabled;
        uint128 parimutuelCreationSeedAmount;
        ComboFeeConfig comboFeeConfig;
        uint128 comboMarketCreationFee;
        ResolverJuryConfig resolverJuryConfig;
        address bondToken;
        uint128 resolutionBondL1;
        uint128 resolutionBondL2;
        uint64 delayedOrderProtectionDelayBlocks;
        uint64 delayedOrderExecutionGraceBlocks;
        uint24 delayedOrderRestingDurationMinutes;
        uint16 delayedOrderProcessorFeeShareBps;
        ProcessingMode delayedOrderProcessingMode;
    }

    struct Market {
        bytes32 marketId;
        MarketType marketType;
        PositionTokenType positionTokenType;
        address positionToken;
        address collateralToken;
        address creator;
        bytes32 questionId;
        bytes32 resolutionId;
        bytes32 conditionId;
        uint256 yesPositionId;
        uint256 noPositionId;
        bytes32 yesBookId;
        bytes32 noBookId;
        uint64 createdAt;
        uint64 tradingStartTime;
        uint64 expiryTime;
        uint64 parimutuelEpochWindow;
        uint64 resolutionTime;
        uint64 disputeDeadline;
        uint96 lastTradePrice;
        BookFeeConfig orderbookFeeConfig;
        ParimutuelFeeConfig parimutuelFeeConfig;
        uint128 creationFeePaid;
        uint128 creationBond;
        uint128 totalFeePool;
        uint128 totalQuoteVolume;
        uint128 creatorFeesEscrowed;
        uint128 protocolFeesAccrued;
        bool creatorFeesClaimed;
        bool creatorSettledHonestly;
        bool creatorFeeEligible;
        bool creationBondReturnable;
        bool creationBondReleased;
        MarketOutcome outcome;
        MarketState state;
        uint256 curveCount;
        bool delayedExecutionEnabled;
        mapping(address => uint128) makerQuoteVolume;
        mapping(address => uint128) makerFeesAccrued;
        mapping(address => uint128) makerFeesClaimed;
        uint16 makerRewardRateBps;
        uint128 makerRewardsRemaining;
        mapping(address => uint128) makerRewardsClaimable;
        uint8 collateralProfileId;
        uint128 payoutUnit;
    }

    struct MarketMetadata {
        bytes32 marketId;
        string question;
        string category;
        string resolutionSource;
        address creator;
        uint64 tradingStartTime;
        uint64 expiryTime;
        MarketType marketType;
        PositionTokenType positionTokenType;
        address collateralToken;
        address positionToken;
        bytes32 resolutionId;
        bytes32 conditionId;
        uint256 yesPositionId;
        uint256 noPositionId;
        bool exists;
        uint8 collateralProfileId;
        uint128 payoutUnit;
    }

    struct MarketDisplayMetadata {
        bytes32 marketId;
        string slug;
        string title;
        string metadataURI;
        bytes32 metadataHash;
        bytes32 rulesHash;
        bytes32 externalRefHash;
        bool exists;
    }

    struct ExternalMarketReference {
        bytes32 marketId;
        uint8 source;
        bytes32 sourceEventIdHash;
        bytes32 sourceMarketIdHash;
        bytes32 sourceSlugHash;
        bytes32 sourceConditionIdHash;
        bytes32 snapshotHash;
        bool exists;
    }

    struct MarketGroupMetadata {
        bytes32 groupId;
        address creator;
        string slug;
        string title;
        string metadataURI;
        uint8 archetype;
        uint64 createdAt;
        bool exists;
    }

    struct GroupMarketDisplay {
        bytes32 groupId;
        bytes32 marketId;
        uint16 sortOrder;
        uint8 groupType;
        int32 lineValueBps;
        string displayLabel;
        string lineLabel;
        bool exists;
    }

    struct MultiOutcomeDisplay {
        string slug;
        string displayLabel;
        string abbreviation;
        string iconUrl;
        bytes32 externalRefHash;
        bool exists;
    }

    struct MultiOutcomeMarket {
        bytes32 marketId;
        bytes32 conditionId;
        bytes32 outcomesHash;
        uint8 outcomeCount;
        uint8 resolvedOutcome;
        uint256 payoutDenominator;
        bool invalid;
        bool resolved;
        bool exists;
    }

    struct PositionMetadata {
        bytes32 marketId;
        uint8 outcome;
        bool exists;
    }

    struct NativePositionMetadata {
        uint8 moduleId;
        bytes32 conditionId;
        uint8 outcomeIndex;
        bytes32 marketId;
        bool exists;
    }

    struct NativeBinaryCondition {
        bytes32 marketId;
        bytes32 conditionId;
        uint256 yesPositionId;
        uint256 noPositionId;
        bool exists;
    }

    struct ComboCondition {
        bytes32 conditionId;
        bytes32 legsHash;
        uint16 legCount;
        uint64 preparedAt;
        bool exists;
    }

    struct ComboMarket {
        bytes32 marketId;
        bytes32 conditionId;
        address positionToken;
        uint256 yesPositionId;
        uint256 noPositionId;
        bytes32 yesBookId;
        bytes32 noBookId;
        address creator;
        address collateralToken;
        uint64 createdAt;
        uint64 expiryTime;
        bool exists;
    }

    struct StoredCurve {
        uint256 packed;
        uint128 remainingVolume;
        uint64 createdAt;
        uint32 generation;
        bool active;
        bool isYesSide;
        CurveSide curveSide;
        address maker;
        bytes32 bookId;
        uint128 quoteEscrowRemaining;
    }

    struct DelayedOrder {
        address owner;
        bytes32 bookId;
        bytes32 marketId;
        DelayedOrderKind kind;
        DelayedOrderStatus status;
        uint128 amountIn;
        uint128 remainingAmount;
        uint128 limitPrice;
        uint128 minOut;
        uint128 maxAveragePrice;
        uint64 submitBlock;
        uint64 executableBlock;
        uint64 expiryBlock;
        uint64 sequence;
        bytes32 routeHash;
        uint256 restingCurveId;
    }

    struct DelayedOrderQueue {
        uint64 head;
        uint64 tail;
    }

    struct DelayedOrderStorage {
        uint256 nextOrderId;
        mapping(uint256 => DelayedOrder) orders;
        mapping(bytes32 => DelayedOrderQueue) queues;
        mapping(bytes32 => mapping(uint64 => uint256)) orderBySequence;
        mapping(address => mapping(address => uint128)) quoteCredit;
        mapping(address => mapping(address => uint128)) baseERC20Credit;
        mapping(address => mapping(address => mapping(uint256 => uint128))) baseERC1155Credit;
        mapping(address => bool) protocolProcessors;
        address activeProcessor;
    }

    struct Book {
        bytes32 bookId;
        bytes32 marketId;
        bool isYesSide;
        BookAssetType assetType;
        BaseTransferMode baseTransferMode;
        address baseToken;
        uint256 baseTokenId;
        address quoteToken;
        address creator;
        uint64 createdAt;
        uint64 expiryTime;
        bool active;
        BookFeeConfig feeConfig;
        uint96 lastTradePrice;
        uint256 curveCount;
        uint128 totalFeePool;
        uint128 totalQuoteVolume;
        uint128 creatorFeesEscrowed;
        uint128 protocolFeesAccrued;
        bool creatorFeesClaimed;
        BookPricingMode pricingMode;
        BookLifecycle lifecycle;
        uint8 tickPresetId;
        uint64 decommissionRequestedAt;
        uint64 decommissionAvailableAt;
        uint128 tickSize;
        uint128 priceDenominator;
        uint128 minTick;
        uint128 maxTick;
        bool delayedExecutionEnabled;
        mapping(address => uint128) makerQuoteVolume;
        mapping(address => uint128) makerFeesAccrued;
        mapping(address => uint128) makerFeesClaimed;
    }

    struct Resolution {
        bytes32 marketId;
        address proposer;
        uint8 proposedOutcome;
        uint8 escalationLevel;
        bool disputed;
        uint128 bondAmount;
        uint128 reservedBondAmount;
        uint64 proposedAt;
        uint64 disputeDeadline;
        uint64 snapshotBlock;
    }

    struct EveMarketStorage {
        MarketConfig config;
        uint256 nextCurveId;
        mapping(bytes32 => Market) markets;
        mapping(bytes32 => Book) books;
        mapping(bytes32 => MarketMetadata) marketMetadata;
        mapping(bytes32 => MarketDisplayMetadata) marketDisplayMetadata;
        mapping(bytes32 => ExternalMarketReference) marketExternalRefs;
        mapping(bytes32 => MarketGroupMetadata) marketGroups;
        mapping(bytes32 => bytes32[]) marketGroupMarketIds;
        mapping(bytes32 => mapping(bytes32 => GroupMarketDisplay)) groupMarketDisplays;
        mapping(bytes32 => MultiOutcomeMarket) multiOutcomeMarkets;
        mapping(bytes32 => string[]) multiOutcomeLabels;
        mapping(bytes32 => mapping(uint8 => MultiOutcomeDisplay)) multiOutcomeDisplays;
        mapping(bytes32 => mapping(uint8 => uint256)) multiOutcomePositionIds;
        mapping(bytes32 => mapping(uint8 => bytes32)) multiOutcomeBookIds;
        mapping(address => mapping(uint256 => PositionMetadata)) positionMetadata;
        mapping(uint256 => NativePositionMetadata) nativePositionMetadata;
        mapping(bytes32 => NativeBinaryCondition) nativeBinaryConditions;
        mapping(bytes32 => ComboCondition) comboConditions;
        mapping(bytes32 => uint256[]) comboConditionLegs;
        mapping(bytes32 => ComboMarket) comboMarkets;
        mapping(bytes32 => bytes32) comboBookByPositionKey;
        mapping(uint256 => StoredCurve) curves;
        mapping(bytes32 => uint256[]) bookCurveIds;
        mapping(bytes32 => Resolution) resolutions;
        mapping(bytes32 => Resolution[]) resolutionHistory;
        mapping(uint8 => address) curveProfiles;
        mapping(address => uint256) reservedAccountMap0;
        mapping(address => uint256) reservedAccountMap1;
        mapping(address => uint256) reservedAccountMap2;
        mapping(bytes32 => mapping(address => uint128)) reservedMarketAccountMap0;
        mapping(bytes32 => mapping(address => uint128)) reservedMarketAccountMap1;
        mapping(address => uint256) resolutionBonded;
        mapping(bytes32 => mapping(address => uint128)) bondedByMarket;
        address contractOwner;
        mapping(bytes4 => address) selectorToFacet;
        mapping(address => bytes4[]) facetFunctionSelectors;
        address[] facetAddresses;
        mapping(bytes4 => bool) frozenSelectors;
        mapping(uint8 => CollateralProfile) collateralProfiles;
        // Product-specific profile config is kept in dedicated mappings to avoid changing
        // the existing CollateralProfile struct layout.
        mapping(uint8 => uint128) parimutuelProfileCreationSeedAmount;
        mapping(uint8 => uint128) parimutuelProfileMinEntry;
        mapping(uint8 => uint128) parlayUnderwritingFeeByProfile;
        DelayedOrderStorage delayedOrders;
        mapping(bytes32 => MarkOracleTypes.BookOracle) markOracles;
        uint32 markOracleCautionThreshold;
        uint32 markOracleStaleThreshold;
        address marginAsset;
        address marginRiskManager;
        bool marginWarningRiskIncreaseAllowed;
        uint256 totalMarginLiabilities;
        mapping(address => MarginTypes.MarginAccount) marginAccounts;
        mapping(bytes32 => MarginTypes.MarginBucket) marginBuckets;
        mapping(address => mapping(bytes32 => bytes32)) marginBucketIds;
        mapping(bytes32 => MarginTypes.RiskDomainOracleConfig) marginRiskDomainOracles;
        mapping(uint8 => MarginTypes.RiskParams) marginDefaultRiskParams;
        mapping(bytes32 => MarginTypes.RiskParams) marginRiskDomainParams;
        mapping(bytes32 => MarkOracleTypes.RiskMarkConfig) marginRiskDomainMarkConfigs;
        mapping(bytes32 => MarginTypes.FundingConfig) marginRiskDomainFundingConfigs;
        uint256 nextQuoteEnvelopeId;
        mapping(uint256 => QuoteEnvelopeTypes.StoredQuoteEnvelope) quoteEnvelopes;
        mapping(address => uint256[]) operatorQuoteEnvelopeIds;
        mapping(bytes32 => uint256[]) bookQuoteEnvelopeIds;
        mapping(uint256 => ProductAdapterTypes.AdapterCurveMetadata) adapterCurveMetadata;
        mapping(uint256 => uint256) mloCurveEnvelopeIds;
        mapping(uint256 => uint256) mloEnvelopeCurveIds;
        mapping(uint256 => uint256) mloCurveSeniorReserved;
        mapping(uint256 => address) mloCurveSeniorPools;
        mapping(bytes32 => mapping(bytes32 => address)) mloInventoryVaults;
        mapping(bytes32 => mapping(bytes32 => uint256)) mloBucketYesInventory;
        mapping(bytes32 => mapping(bytes32 => uint256)) mloBucketNoInventory;
        mapping(bytes32 => mapping(bytes32 => uint256)) mloBucketMarketSeniorDebt;
        mapping(bytes32 => mapping(bytes32 => uint256)) mloBucketMarketPositionRisk;
        mapping(bytes32 => mapping(bytes32 => address)) mloBucketMarketSeniorPools;
    }

    function store() internal pure returns (EveMarketStorage storage storage_) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            storage_.slot := slot
        }
    }
}
