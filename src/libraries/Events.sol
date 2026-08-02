// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ParlayTypes} from "../types/ParlayTypes.sol";

library Events {
    event MarketCreated(
        bytes32 indexed marketId,
        uint8 indexed marketType,
        address indexed creator,
        uint8 positionTokenType,
        address positionToken,
        address collateralToken,
        bytes32 resolutionId,
        bytes32 conditionId,
        uint256 yesPositionId,
        uint256 noPositionId,
        string question,
        uint64 expiryTime
    );
    event MarketCollateralProfile(
        bytes32 indexed marketId,
        uint8 indexed collateralProfileId,
        address indexed collateralToken,
        uint128 payoutUnit,
        uint128 marketCreationFee
    );
    event MarketDisplayMetadataSet(
        bytes32 indexed marketId,
        string slug,
        string title,
        string subtitle,
        string rules,
        string imageUrl,
        string iconUrl,
        string metadataURI,
        string tagsJson,
        bytes32 metadataHash,
        bytes32 rulesHash
    );
    event MarketExternalReferenceSet(
        bytes32 indexed marketId,
        uint8 indexed source,
        bytes32 indexed sourceEventIdHash,
        string sourceEventId,
        string sourceMarketId,
        string sourceSlug,
        string sourceConditionId,
        bytes32 snapshotHash
    );
    event MarketGroupCreated(
        bytes32 indexed groupId, address indexed creator, bytes32 indexed titleHash, string title, uint256 marketCount
    );
    event MarketGroupDisplaySet(
        bytes32 indexed groupId, string slug, string title, uint8 archetype, string metadataURI
    );
    event MarketGroupMarketAdded(bytes32 indexed groupId, bytes32 indexed marketId, uint256 indexed index);
    event GroupMarketDisplaySet(
        bytes32 indexed groupId,
        bytes32 indexed marketId,
        uint16 indexed sortOrder,
        uint8 groupType,
        int32 lineValueBps,
        string displayLabel,
        string lineLabel
    );
    event CreationBondLocked(bytes32 indexed marketId, address indexed creator, uint128 amount);
    event CreationBondReleased(bytes32 indexed marketId, address indexed creator, uint128 amount);
    event CreationBondSlashed(
        bytes32 indexed marketId, address indexed creator, address indexed rewardRecipient, uint128 amount
    );
    event ParimutuelMarketCreated(
        bytes32 indexed marketId,
        address indexed creator,
        address indexed positionToken,
        uint256 yesPositionId,
        uint256 noPositionId,
        uint64 expiryTime,
        uint64 epochWindow
    );
    event ParimutuelCreationSeeded(bytes32 indexed marketId, address indexed creator, uint128 amount);
    event MultiOutcomeMarketCreated(
        bytes32 indexed marketId,
        bytes32 indexed conditionId,
        address indexed creator,
        uint8 outcomeCount,
        bytes32 outcomesHash
    );
    event MultiOutcomeDisplaySet(
        bytes32 indexed marketId,
        uint8 indexed outcome,
        string slug,
        string displayLabel,
        string abbreviation,
        string iconUrl,
        string externalOutcomeId,
        bytes32 externalRefHash
    );
    event OutcomePositionPrepared(bytes32 indexed marketId, uint8 indexed outcome, uint256 indexed positionId);
    event OutcomeBookPrepared(bytes32 indexed marketId, uint8 indexed outcome, bytes32 indexed bookId);
    event OutcomeSetSplit(bytes32 indexed marketId, address indexed account, uint128 amount);
    event OutcomeSetMerged(bytes32 indexed marketId, address indexed account, uint128 amount);
    event MultiOutcomeResolved(
        bytes32 indexed marketId, uint8 indexed outcome, bool invalid, uint256 payoutDenominator
    );
    event OutcomeRedeemed(
        bytes32 indexed marketId,
        address indexed account,
        uint8 indexed outcome,
        uint128 amountIn,
        uint128 collateralOut
    );

    event MarketExpired(bytes32 indexed marketId);
    event MarketResolved(bytes32 indexed marketId, uint8 outcome);
    event MarketSettled(bytes32 indexed marketId);

    event BookCreated(
        bytes32 indexed bookId,
        bytes32 indexed marketId,
        address indexed creator,
        uint8 assetType,
        address baseToken,
        uint256 baseTokenId,
        address quoteToken,
        bool isYesSide
    );
    event SpotBookCreationFeePaid(
        bytes32 indexed bookId, address indexed creator, address indexed treasury, uint128 amount
    );
    event BookDecommissionRequested(
        bytes32 indexed bookId, address indexed caller, uint64 requestedAt, uint64 availableAt
    );
    event BookDecommissioned(bytes32 indexed bookId, address indexed caller);
    event CurvePosted(bytes32 indexed marketId, uint256 curveId, address maker, bool isYesSide, uint256 packed);
    event BookCurvePosted(
        bytes32 indexed bookId,
        bytes32 indexed marketId,
        uint256 indexed curveId,
        address maker,
        bool isYesSide,
        uint8 curveSide,
        uint256 packed
    );
    event CurveUpdated(uint256 indexed curveId, uint256 newPacked, uint32 generation);
    event CurveUpdatedFromNow(uint256 indexed curveId, uint256 newPacked, uint32 generation, uint64 createdAt);
    event CurveReactivated(
        bytes32 indexed bookId,
        uint256 indexed curveId,
        address indexed maker,
        uint128 remainingVolume,
        uint128 quoteEscrowRemaining,
        uint32 generation,
        uint64 expiresAt,
        uint256 packed
    );
    event CurveToppedUp(
        bytes32 indexed marketId,
        uint256 indexed curveId,
        address indexed maker,
        uint128 addedVolume,
        uint128 newRemainingVolume
    );
    event CurveFilled(
        uint256 indexed curveId,
        address indexed maker,
        address taker,
        uint128 collateralIn,
        uint128 sharesOut,
        uint128 fee
    );
    event TradeRouted(
        bytes32 indexed marketId,
        address indexed taker,
        bool isYesSide,
        uint128 totalCollateralIn,
        uint128 totalSharesOut,
        uint128 averagePrice,
        uint256 curveCount
    );
    event CurveCancelled(uint256 indexed curveId);
    event CurveExpired(uint256 indexed curveId);
    event UserCreditChanged(
        address indexed owner, uint8 indexed creditAssetType, address indexed token, uint256 tokenId, int256 delta
    );
    event DelayedOrderSubmitted(
        uint256 indexed orderId,
        bytes32 indexed bookId,
        address indexed owner,
        uint8 kind,
        uint128 amountIn,
        uint128 limitPrice,
        uint64 sequence,
        bytes32 routeHash,
        uint256[] curveIds,
        uint32[] expectedGenerations,
        bytes32[] expectedCommitments
    );
    event DelayedOrderProcessed(
        uint256 indexed orderId,
        bytes32 indexed bookId,
        address indexed owner,
        address processor,
        uint8 status,
        uint128 filledIn,
        uint128 filledOut,
        uint128 creditedQuote,
        uint128 creditedBase,
        uint128 processorReward,
        uint256 restingCurveId
    );
    event DelayedOrderExpired(
        uint256 indexed orderId,
        bytes32 indexed bookId,
        address indexed owner,
        uint128 creditedQuote,
        uint128 creditedBase
    );
    event ParimutuelSharesBought(
        bytes32 indexed marketId,
        address indexed buyer,
        address indexed receiver,
        bool isYes,
        uint128 amountIn,
        uint128 sharesMinted,
        uint128 feePaid
    );
    event ParimutuelPayoutClaimed(
        bytes32 indexed marketId,
        address indexed claimer,
        uint256 indexed positionId,
        uint128 sharesBurned,
        uint128 payout
    );
    event ParimutuelFinalized(
        bytes32 indexed marketId,
        uint8 rawOutcome,
        uint8 effectiveOutcome,
        uint128 payoutPool,
        uint128 totalClaimableShares
    );
    event ParimutuelDustSwept(bytes32 indexed marketId, address indexed recipient, uint128 amount);
    event ParimutuelEpochMultipliersUpdated(uint16[8] multipliersBps);

    event CreatorSettled(bytes32 indexed marketId, uint8 outcome);
    event EarlyCreatorSettled(bytes32 indexed marketId, uint8 outcome);
    event OpenResolutionStarted(bytes32 indexed marketId, address indexed proposer, uint8 outcome);
    event ResolutionDisputed(bytes32 indexed marketId, address disputer, uint8 counterOutcome, uint8 escalationLevel);
    event ResolutionFinalized(bytes32 indexed marketId, uint8 outcome);
    event CreatorSettlementEvaluated(
        bytes32 indexed marketId,
        address indexed creator,
        uint8 creatorOutcome,
        uint8 finalOutcome,
        bool settledHonestly
    );
    event CreatorFeeEligibilitySet(
        bytes32 indexed marketId, address indexed creator, bool eligible, uint128 escrowedFees
    );
    event CreationBondReturnabilitySet(
        bytes32 indexed marketId, address indexed creator, bool returnable, uint128 amount
    );
    event BondSlashed(bytes32 indexed marketId, address slashedAddress, uint128 amount);
    event CreatorFeesForfeited(bytes32 indexed marketId, uint128 amount);
    event MakerFeesClaimed(bytes32 indexed marketId, address indexed maker, uint128 amount);
    event CreatorFeesClaimed(bytes32 indexed marketId, uint128 amount);
    event MarketMakerRewardsConfigured(bytes32 indexed marketId, address indexed rewardToken, uint16 rewardRateBps);
    event MarketMakerRewardsFunded(
        bytes32 indexed marketId,
        address indexed funder,
        address indexed rewardToken,
        uint128 amount,
        uint128 rewardsRemaining
    );
    event MarketMakerRewardAccrued(
        bytes32 indexed marketId,
        address indexed maker,
        uint128 quoteVolume,
        uint128 rewardAmount,
        uint128 rewardsRemaining
    );
    event MarketMakerRewardsClaimed(
        bytes32 indexed marketId, address indexed maker, address indexed rewardToken, uint128 amount
    );
    event BookMakerFeesClaimed(bytes32 indexed bookId, address indexed maker, uint128 amount);
    event BookCreatorFeesClaimed(bytes32 indexed bookId, address indexed creator, uint128 amount);
    event PayoutReported(bytes32 indexed marketId, uint8 outcome, bytes32 payoutVectorHash);
    event IdentityMinted(uint256 indexed identityId, address indexed owner);
    event IdentityRolesUpdated(uint256 indexed identityId, bool creatorRole, bool resolverRole);
    event CreatorReputationUpdated(
        uint256 indexed identityId,
        uint64 marketsCreated,
        uint64 marketsResolved,
        uint64 disputesRaised,
        uint64 outcomesUpheld,
        uint64 outcomesOverturned
    );
    event ResolverReputationUpdated(
        uint256 indexed identityId,
        uint64 totalSelections,
        uint64 commitCount,
        uint64 revealCount,
        uint64 finalAgreementCount,
        uint64 slashCount
    );
    event ResolverActivationRequested(uint256 indexed identityId, uint64 activationTimestamp);
    event ResolverBecameEligible(uint256 indexed identityId, uint64 eligibleAt);
    event ResolverExitRequested(uint256 indexed identityId, uint64 exitTimestamp);
    event ResolverStakeDeposited(uint256 indexed identityId, address indexed owner, uint128 amount, uint128 newStake);
    event ResolverStakeWithdrawn(uint256 indexed identityId, address indexed owner, uint128 amount);
    event ResolverPoolCapacityUpdated(uint16 priorValue, uint16 newValue);
    event ResolverJuryInitiated(bytes32 indexed disputeId, bytes32 indexed marketId, uint8 round);
    event RandomnessCommitted(bytes32 indexed disputeId, uint8 indexed round, uint256 indexed identityId);
    event RandomnessRevealed(bytes32 indexed disputeId, uint8 indexed round, uint256 indexed identityId);
    event RandomnessFailure(bytes32 indexed disputeId, uint8 indexed round, uint8 mode, uint256 validRevealCount);
    event CommitteeSelected(
        bytes32 indexed disputeId, uint8 indexed round, uint16 committeeSize, bytes32 seed, uint256[] identityIds
    );
    event VoteCommitted(bytes32 indexed disputeId, uint8 indexed round, uint256 indexed identityId);
    event VoteRevealed(bytes32 indexed disputeId, uint8 indexed round, uint256 indexed identityId, uint8 outcome);
    event AppealOpened(bytes32 indexed disputeId, uint8 indexed round, address indexed appellant, uint128 bondAmount);
    event RewardDistributed(
        bytes32 indexed disputeId, uint256 indexed identityId, address indexed recipient, address token, uint256 amount
    );
    event ResolverSlashed(bytes32 indexed disputeId, uint8 indexed round, uint256 indexed identityId, uint128 amount);
    event DisputeFinalized(bytes32 indexed disputeId, bytes32 indexed marketId, uint8 finalResult);
    event ConfigUpdated(bytes32 paramName, uint256 priorValue, uint256 newValue);

    event ParlayConfigSet(
        address indexed ticketToken,
        address indexed feeRecipient,
        uint128 underwritingFee,
        uint16 vaultFeeBps,
        uint16 feeRecipientBps
    );
    event ParlayTemplateCreated(
        uint256 indexed templateId,
        address indexed creator,
        ParlayTypes.ParlayLeg[] legs,
        ParlayTypes.PayoutTier[] payoutTiers,
        uint8 invalidPolicy,
        string metadataHint
    );
    event ParlayOfferPosted(
        uint256 indexed offerId,
        uint256 indexed templateId,
        address indexed maker,
        uint128 premiumPerUnit,
        uint128 maxPayoutPerUnit,
        uint128 units,
        uint64 fillDeadline
    );
    event ParlayOfferFilled(
        uint256 indexed offerId,
        uint256 indexed ticketId,
        address indexed buyer,
        uint128 units,
        uint128 premiumPaid,
        uint128 flatFeePaid,
        uint128 escrowLocked
    );
    event ParlayRequestPosted(
        uint256 indexed requestId,
        uint256 indexed templateId,
        address indexed requester,
        uint128 premiumPerUnit,
        uint128 desiredMaxPayoutPerUnit,
        uint128 units,
        uint64 fillDeadline
    );
    event ParlayRequestFilled(
        uint256 indexed requestId,
        uint256 indexed ticketId,
        address indexed underwriter,
        uint128 units,
        uint128 premiumPaid,
        uint128 flatFeePaid,
        uint128 escrowLocked
    );
    event ParlayFlatFeeRouted(
        uint256 indexed ticketId,
        uint256 indexed sourceId,
        uint8 indexed sourceType,
        uint256 feeAmount,
        uint256 vaultAmount,
        uint256 feeRecipientAmount
    );
    event ParlayOfferCancelled(
        uint256 indexed offerId, address indexed maker, uint128 unitsCancelled, uint256 escrowReturned
    );
    event ParlayRequestCancelled(
        uint256 indexed requestId,
        address indexed requester,
        uint128 unitsCancelled,
        uint256 premiumReturned,
        uint256 feeReturned
    );
    event ParlayBudgetCreated(uint256 indexed budgetId, address indexed owner, uint8 indexed mode, uint256 deposited);
    event ParlayBudgetFunded(uint256 indexed budgetId, address indexed owner, uint256 amount, uint256 deposited);
    event ParlayBudgetConsumed(
        uint256 indexed budgetId,
        uint256 indexed sourceId,
        uint8 indexed sourceType,
        uint256 amount,
        uint256 consumed,
        uint256 available
    );
    event ParlayBudgetCancelled(uint256 indexed budgetId, address indexed owner, uint256 refunded);
    event ParlayBudgetOfferPosted(
        uint256 indexed offerId,
        uint256 indexed budgetId,
        uint256 indexed templateId,
        address maker,
        uint128 premiumPerUnit,
        uint128 maxPayoutPerUnit,
        uint128 units,
        uint64 fillDeadline
    );
    event ParlayBudgetRequestPosted(
        uint256 indexed requestId,
        uint256 indexed budgetId,
        uint256 indexed templateId,
        address requester,
        uint128 premiumPerUnit,
        uint128 desiredMaxPayoutPerUnit,
        uint128 units,
        uint64 fillDeadline
    );
    event ParlayTicketBucketFinalized(
        uint256 indexed ticketId,
        address indexed underwriter,
        uint8 hits,
        uint8 misses,
        uint8 invalids,
        uint128 payoutPerUnit,
        uint128 unitsOutstanding,
        uint256 claimReserve,
        uint256 escrowReturned
    );
    event ParlayTicketClaimed(
        uint256 indexed ticketId,
        address indexed holder,
        address indexed receiver,
        uint128 units,
        uint128 payoutPerUnit,
        uint256 payout
    );
    event StrategyCreated(
        bytes32 indexed strategyId,
        address indexed creator,
        bytes32[] directMarketIds,
        uint8[] directOutcomes,
        uint256[] parlayTemplateIds,
        string metadataHint
    );

    event NativeBinaryConditionPrepared(
        bytes32 indexed marketId, bytes32 indexed conditionId, uint256 yesPositionId, uint256 noPositionId
    );
    event NativeBinarySplit(
        bytes32 indexed marketId, address indexed account, address indexed receiver, uint128 amount
    );
    event NativeBinaryMerged(
        bytes32 indexed marketId, address indexed account, address indexed receiver, uint128 amount
    );
    event NativeBinaryRedeemed(
        bytes32 indexed marketId,
        address indexed account,
        uint8 indexed outcomeIndex,
        uint128 amountIn,
        uint128 collateralOut
    );
    event ComboConditionPrepared(
        bytes32 indexed conditionId,
        bytes32 indexed legsHash,
        uint16 legCount,
        uint256 yesPositionId,
        uint256 noPositionId,
        uint256[] legs
    );
    event ComboSplit(
        bytes32 indexed conditionId, address indexed account, uint128 amount, address yesReceiver, address noReceiver
    );
    event ComboMerged(bytes32 indexed conditionId, address indexed account, address indexed receiver, uint128 amount);
    event ComboWrapped(
        address indexed account, uint256 indexed underlyingPositionId, uint256 indexed comboPositionId, uint128 amount
    );
    event ComboUnwrapped(
        address indexed account, uint256 indexed comboPositionId, uint256 indexed underlyingPositionId, uint128 amount
    );
    event ComboCompressed(
        address indexed account,
        uint256 indexed oldPositionId,
        uint256 indexed newPositionId,
        uint128 amountIn,
        uint128 positionAmountOut,
        uint128 collateralOut
    );
    event ComboRedeemed(address indexed account, uint256 indexed positionId, uint128 amountIn, uint128 collateralOut);
    event ComboSplitOnCondition(
        address indexed account,
        uint256 indexed parentYesPositionId,
        bytes32 indexed binaryConditionId,
        uint256 childYesPositionId,
        uint256 childNoPositionId,
        uint128 amount
    );
    event ComboMergedOnCondition(
        address indexed account,
        uint256 indexed parentYesPositionId,
        bytes32 indexed binaryConditionId,
        uint256 childYesPositionId,
        uint256 childNoPositionId,
        uint128 amount
    );
    event ComboNoLegExtracted(
        address indexed account,
        uint256 indexed fullNoPositionId,
        uint256 indexed extractedLeg,
        uint256 reducedNoPositionId,
        uint256 residualYesPositionId,
        uint128 amount
    );
    event ComboNoLegInjected(
        address indexed account,
        uint256 indexed fullNoPositionId,
        uint256 indexed injectedLeg,
        uint256 reducedNoPositionId,
        uint256 residualYesPositionId,
        uint128 amount
    );
    event ComboNoConvertedToYesBasket(
        address indexed account, uint256 indexed fullNoPositionId, uint128 amount, uint256[] basketPositionIds
    );
    event ComboNoMergedFromYesBasket(
        address indexed account, uint256 indexed fullNoPositionId, address indexed receiver, uint128 amount
    );
    event ComboMarketCreated(
        bytes32 indexed marketId,
        bytes32 indexed conditionId,
        address creator,
        address positionToken,
        uint256 yesPositionId,
        uint256 noPositionId,
        bytes32 yesBookId,
        bytes32 noBookId,
        address quoteToken,
        uint64 expiryTime
    );
    event ComboMarketCreationFeePaid(
        bytes32 indexed marketId, address indexed creator, address indexed treasury, uint128 amount
    );
}
