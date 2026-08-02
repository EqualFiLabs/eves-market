// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface MarketFactoryTypes {
    struct MarketInfo {
        bytes32 marketId;
        address creator;
        address collateralToken;
        bytes32 questionId;
        bytes32 resolutionId;
        bytes32 conditionId;
        uint256 yesPositionId;
        uint256 noPositionId;
        uint64 createdAt;
        uint64 tradingStartTime;
        uint64 expiryTime;
        uint64 resolutionTime;
        uint8 state;
        uint8 outcome;
        uint128 creationFeePaid;
        uint128 creationBond;
        bool creationBondReleased;
        uint128 totalQuoteVolume;
        uint128 creatorFeesEscrowed;
        uint128 protocolFeesAccrued;
        uint128 lastTradePrice;
        uint256 totalCurveCount;
        bool creatorSettledHonestly;
        bool creatorFeeEligible;
        bool creationBondReturnable;
        uint8 marketType;
        uint8 positionTokenType;
        address positionToken;
        uint16 orderbookEntryFeeBps;
        uint16 orderbookMakerFeeBps;
        uint16 orderbookCreatorFeeBps;
        uint16 orderbookProtocolFeeBps;
        uint16 orderbookVaultFeeBps;
        uint16 parimutuelEntryFeeBps;
        uint16 parimutuelCreatorFeeBps;
        uint16 parimutuelProtocolFeeBps;
        uint16 parimutuelVaultFeeBps;
        uint8 collateralProfileId;
        uint128 payoutUnit;
        bool delayedExecutionEnabled;
    }

    struct MarketSummary {
        MarketInfo marketInfo;
        uint64 disputeDeadline;
        uint256 yesBalance;
        uint256 noBalance;
    }

    struct MarketMetadataView {
        bytes32 marketId;
        string question;
        string category;
        string resolutionSource;
        address creator;
        uint64 tradingStartTime;
        uint64 expiryTime;
        uint8 marketType;
        uint8 positionTokenType;
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

    struct MarketCreationParams {
        string question;
        string category;
        string resolutionSource;
        uint64 tradingStartTime;
        uint64 expiryTime;
        uint128 initialVolume;
        bool initialDirection;
        MarketDisplayInput display;
        ExternalMarketRefInput externalRef;
    }

    struct MarketDisplayInput {
        string slug;
        string title;
        string subtitle;
        string rules;
        string imageUrl;
        string iconUrl;
        string metadataURI;
        string tagsJson;
    }

    struct ExternalMarketRefInput {
        uint8 source;
        string sourceEventId;
        string sourceMarketId;
        string sourceSlug;
        string sourceConditionId;
        bytes32 snapshotHash;
    }

    struct GroupDisplayInput {
        string slug;
        string title;
        uint8 archetype;
        string metadataURI;
        ExternalMarketRefInput externalRef;
    }

    struct GroupMarketDisplayInput {
        string displayLabel;
        string lineLabel;
        int32 lineValueBps;
        uint8 groupType;
    }

    struct MarketGroupCreationParams {
        GroupDisplayInput display;
        GroupMarketCreationParam[] markets;
    }

    struct GroupMarketCreationParam {
        MarketCreationParams market;
        GroupMarketDisplayInput display;
    }

    struct ExistingMarketGroupCreationParams {
        GroupDisplayInput display;
        ExistingGroupMarketParam[] markets;
    }

    struct ExistingGroupMarketParam {
        bytes32 marketId;
        GroupMarketDisplayInput display;
    }

    struct MarketDisplayView {
        bytes32 marketId;
        string slug;
        string title;
        string metadataURI;
        bytes32 metadataHash;
        bytes32 rulesHash;
        bytes32 externalRefHash;
        bool exists;
    }

    struct MarketExternalRefView {
        bytes32 marketId;
        uint8 source;
        bytes32 sourceEventIdHash;
        bytes32 sourceMarketIdHash;
        bytes32 sourceSlugHash;
        bytes32 sourceConditionIdHash;
        bytes32 snapshotHash;
        bool exists;
    }

    struct MarketGroupView {
        bytes32 groupId;
        address creator;
        string slug;
        string title;
        uint8 archetype;
        uint64 createdAt;
        uint256 marketCount;
        bool exists;
    }

    struct GroupMarketDisplayView {
        bytes32 groupId;
        bytes32 marketId;
        uint16 sortOrder;
        uint8 groupType;
        int32 lineValueBps;
        string displayLabel;
        string lineLabel;
        bool exists;
    }

    struct PositionMetadataView {
        address positionToken;
        uint256 positionId;
        bytes32 marketId;
        uint8 outcome;
        string outcomeLabel;
        bool exists;
    }

    struct MarketTokenInfo {
        uint8 positionTokenType;
        address positionToken;
        address collateralToken;
        bytes32 resolutionId;
        bytes32 conditionId;
        uint256 yesPositionId;
        uint256 noPositionId;
    }

    struct CollateralProfileView {
        address collateralToken;
        address wrapperToken;
        uint128 payoutUnit;
        uint128 marketCreationFee;
        bool enabled;
    }

    struct BookFeeConfigView {
        uint16 entryFeeBps;
        uint16 makerFeeBps;
        uint16 creatorFeeBps;
        uint16 protocolFeeBps;
        uint16 vaultFeeBps;
        uint16 resolverFeeBps;
        uint16 evRiskFeeBps;
    }

    struct ParimutuelFeeConfigView {
        uint16 entryFeeBps;
        uint16 creatorFeeBps;
        uint16 protocolFeeBps;
        uint16 vaultFeeBps;
        uint16 resolverFeeBps;
        uint16 evRiskFeeBps;
    }

    struct SpotFeeConfigView {
        uint16 tradeFeeBps;
        uint16 makerFeeBps;
        uint16 protocolFeeBps;
        uint16 vaultFeeBps;
        uint16 resolverFeeBps;
        uint16 evRiskFeeBps;
    }

    struct ComboFeeConfigView {
        uint16 tradeFeeBps;
        uint16 makerFeeBps;
        uint16 creatorFeeBps;
        uint16 protocolFeeBps;
        uint16 vaultFeeBps;
        uint16 resolverFeeBps;
        uint16 evRiskFeeBps;
    }

    struct MarketConfigView {
        address defaultConditionalTokens;
        address evesPositionManager;
        address collateralToken;
        address eveToken;
        address eveTreasury;
        address seniorCapitalPool;
        address evRiskStakingRewards;
        address parimutuelShareToken;
        BookFeeConfigView orderbookFeeConfig;
        SpotFeeConfigView spotFeeConfig;
        ComboFeeConfigView comboFeeConfig;
        ParimutuelFeeConfigView parimutuelFeeConfig;
        uint128 parimutuelMinEntry;
        uint128 parimutuelCreationSeedAmount;
        uint128 marketCreationFee;
        uint128 spotBookCreationFee;
        uint128 comboMarketCreationFee;
        uint128 marketCreationBond;
        address bondToken;
        uint128 resolutionBondL1;
        uint128 resolutionBondL2;
        uint64 minMarketDuration;
        uint64 maxMarketDuration;
        uint64 disputeWindow;
        uint64 creatorSettleGrace;
        uint64 openResolutionTimeout;
        uint16 marketCreationBatchCap;
        uint8 maxEscalation;
        uint8 resolutionMode;
        bool permissionlessCreationEnabled;
        uint64 delayedOrderProtectionDelayBlocks;
        uint64 delayedOrderExecutionGraceBlocks;
        uint24 delayedOrderRestingDurationMinutes;
        uint16 delayedOrderProcessorFeeShareBps;
        uint8 delayedOrderProcessingMode;
        uint32 maxDelayedOrderRouteLength;
        uint128 minDelayedOrderQuoteWad;
        uint128 minDelayedOrderBaseWad;
    }
}
