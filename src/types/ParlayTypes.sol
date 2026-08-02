// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

library ParlayTypes {
    enum InvalidPolicy {
        VoidInvalidLegs,
        InvalidCountsAsMiss
    }

    enum SourceType {
        Offer,
        Request
    }

    enum BudgetMode {
        MakerPayout,
        TakerSpend
    }

    struct ParlayLeg {
        bytes32 marketId;
        uint8 requiredOutcome;
    }

    struct PayoutTier {
        uint8 minHits;
        uint128 payout;
    }

    struct ParlayTemplateView {
        uint256 templateId;
        address creator;
        uint128 maxPayoutPerUnit;
        uint8 invalidPolicy;
        uint8 legCount;
        uint8 tierCount;
        bool exists;
        string metadataHint;
    }

    struct ParlayOfferView {
        uint256 offerId;
        uint256 templateId;
        address maker;
        address collateralToken;
        uint128 premiumPerUnit;
        uint128 maxPayoutPerUnit;
        uint128 totalUnits;
        uint128 remainingUnits;
        uint128 payoutUnit;
        uint128 underwritingFeePerUnit;
        uint256 escrowRemaining;
        uint64 fillDeadline;
        uint8 collateralProfileId;
        bool active;
        uint256 budgetId;
    }

    struct ParlayRequestView {
        uint256 requestId;
        uint256 templateId;
        address requester;
        address collateralToken;
        uint128 premiumPerUnit;
        uint128 desiredMaxPayoutPerUnit;
        uint128 totalUnits;
        uint128 remainingUnits;
        uint128 payoutUnit;
        uint128 underwritingFeePerUnit;
        uint256 premiumEscrowRemaining;
        uint256 feeEscrowRemaining;
        uint64 fillDeadline;
        uint8 collateralProfileId;
        bool active;
        uint256 budgetId;
    }

    struct ParlayTicketBucketView {
        uint256 ticketId;
        uint256 templateId;
        uint256 sourceId;
        address underwriter;
        address collateralToken;
        uint128 premiumPerUnit;
        uint128 maxPayoutPerUnit;
        uint128 unitsMinted;
        uint128 unitsClaimed;
        uint128 payoutPerUnit;
        uint128 payoutUnit;
        uint256 escrowRemaining;
        uint8 sourceType;
        uint8 collateralProfileId;
        bool finalized;
    }

    struct ParlayConfigView {
        address ticketToken;
        address feeRecipient;
        uint128 underwritingFee;
        uint16 vaultFeeBps;
        uint16 feeRecipientBps;
    }

    struct SharedBudgetView {
        uint256 budgetId;
        address owner;
        address collateralToken;
        uint8 mode;
        uint128 payoutUnit;
        uint256 deposited;
        uint256 consumed;
        uint256 available;
        uint8 collateralProfileId;
        bool active;
    }

    struct QuoteOfferPost {
        ParlayLeg[] legs;
        PayoutTier[] payoutTiers;
        InvalidPolicy invalidPolicy;
        string metadataHint;
        uint128 premiumPerUnit;
        uint128 maxPayoutPerUnit;
        uint128 units;
        uint64 fillDeadline;
    }

    struct QuoteRequestPost {
        ParlayLeg[] legs;
        PayoutTier[] payoutTiers;
        InvalidPolicy invalidPolicy;
        string metadataHint;
        uint128 premiumPerUnit;
        uint128 desiredMaxPayoutPerUnit;
        uint128 units;
        uint64 fillDeadline;
    }

    struct BudgetOfferPost {
        ParlayLeg[] legs;
        PayoutTier[] payoutTiers;
        InvalidPolicy invalidPolicy;
        string metadataHint;
        uint128 premiumPerUnit;
        uint128 maxPayoutPerUnit;
        uint128 units;
        uint64 fillDeadline;
    }

    struct BudgetRequestPost {
        ParlayLeg[] legs;
        PayoutTier[] payoutTiers;
        InvalidPolicy invalidPolicy;
        string metadataHint;
        uint128 premiumPerUnit;
        uint128 desiredMaxPayoutPerUnit;
        uint128 units;
        uint64 fillDeadline;
    }
}
