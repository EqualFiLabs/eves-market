// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ParlayTypes} from "../types/ParlayTypes.sol";

library LibParlay {
    bytes32 internal constant STORAGE_SLOT = bytes32(uint256(keccak256("eve.prediction.parlay.storage")) - 1);
    bytes32 internal constant PARLAY_TEMPLATE_DOMAIN = keccak256("eve.parlay.template.v1");
    bytes32 internal constant PARLAY_TICKET_DOMAIN = keccak256("eve.parlay.ticket.v1");
    uint8 internal constant MIN_LEGS = 1;
    uint8 internal constant MAX_LEGS = 8;
    uint16 internal constant BPS_DENOMINATOR = 10_000;

    struct Config {
        address ticketToken;
        address feeRecipient;
        uint128 underwritingFee;
        uint16 vaultFeeBps;
        uint16 feeRecipientBps;
    }

    struct ParlayTemplate {
        address creator;
        uint128 maxPayoutPerUnit;
        uint8 invalidPolicy;
        uint8 legCount;
        uint8 tierCount;
        bool exists;
    }

    struct ParlayOffer {
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

    struct ParlayRequest {
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

    struct SharedBudget {
        address owner;
        uint8 mode;
        uint256 deposited;
        uint256 consumed;
        bool active;
        address collateralToken;
        uint128 payoutUnit;
        uint8 collateralProfileId;
    }

    struct ParlayTicketBucket {
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

    struct Storage {
        Config config;
        uint256 nextOfferId;
        uint256 nextRequestId;
        uint256 nextBudgetId;
        mapping(uint256 templateId => ParlayTemplate template_) templates;
        mapping(uint256 templateId => mapping(uint256 index => ParlayTypes.ParlayLeg leg)) templateLegs;
        mapping(uint256 templateId => mapping(uint256 index => ParlayTypes.PayoutTier tier)) templatePayoutTiers;
        mapping(uint256 templateId => string metadataHint) templateMetadataHints;
        mapping(uint256 offerId => ParlayOffer offer) offers;
        mapping(uint256 requestId => ParlayRequest request) requests;
        mapping(uint256 budgetId => SharedBudget budget) budgets;
        mapping(uint256 ticketId => ParlayTicketBucket bucket) ticketBuckets;
    }

    function store() internal pure returns (Storage storage storage_) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            storage_.slot := slot
        }
    }

    function templateIdFor(
        ParlayTypes.ParlayLeg[] calldata legs,
        ParlayTypes.PayoutTier[] calldata payoutTiers,
        ParlayTypes.InvalidPolicy invalidPolicy
    ) internal view returns (uint256 templateId) {
        templateId = uint256(
            keccak256(
                abi.encode(PARLAY_TEMPLATE_DOMAIN, block.chainid, address(this), legs, payoutTiers, invalidPolicy)
            )
        );
    }

    function ticketIdFor(
        uint256 templateId,
        ParlayTypes.SourceType sourceType,
        uint256 sourceId,
        address underwriter,
        uint128 maxPayoutPerUnit
    ) internal pure returns (uint256 ticketId) {
        ticketId = uint256(
            keccak256(abi.encode(PARLAY_TICKET_DOMAIN, templateId, sourceType, sourceId, underwriter, maxPayoutPerUnit))
        );
    }
}
