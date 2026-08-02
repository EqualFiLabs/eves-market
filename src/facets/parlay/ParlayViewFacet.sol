// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Base64} from "../../../lib/openzeppelin-contracts/contracts/utils/Base64.sol";
import {Strings} from "../../../lib/openzeppelin-contracts/contracts/utils/Strings.sol";

import {LibParlay} from "../../libraries/LibParlay.sol";
import {ParlayTypes} from "../../types/ParlayTypes.sol";
import {Errors} from "../../libraries/Errors.sol";
import {ParlayBase} from "./ParlayBase.sol";

contract ParlayViewFacet is ParlayBase {
    string internal constant JSON_PREFIX = "data:application/json;base64,";

    function computeParlayTemplateId(
        ParlayTypes.ParlayLeg[] calldata legs,
        ParlayTypes.PayoutTier[] calldata payoutTiers,
        ParlayTypes.InvalidPolicy invalidPolicy
    ) external view returns (uint256 templateId) {
        templateId = LibParlay.templateIdFor(legs, payoutTiers, invalidPolicy);
    }

    function computeParlayTicketId(
        uint256 templateId,
        ParlayTypes.SourceType sourceType,
        uint256 sourceId,
        address underwriter,
        uint128 maxPayoutPerUnit
    ) external pure returns (uint256 ticketId) {
        ticketId = LibParlay.ticketIdFor(templateId, sourceType, sourceId, underwriter, maxPayoutPerUnit);
    }

    function getParlayTemplate(uint256 templateId)
        external
        view
        returns (ParlayTypes.ParlayTemplateView memory templateView)
    {
        LibParlay.Storage storage state = LibParlay.store();
        LibParlay.ParlayTemplate storage template_ = _requireTemplate(state, templateId);
        templateView = ParlayTypes.ParlayTemplateView({
            templateId: templateId,
            creator: template_.creator,
            maxPayoutPerUnit: template_.maxPayoutPerUnit,
            invalidPolicy: template_.invalidPolicy,
            legCount: template_.legCount,
            tierCount: template_.tierCount,
            exists: template_.exists,
            metadataHint: state.templateMetadataHints[templateId]
        });
    }

    function getParlayTemplateLeg(uint256 templateId, uint256 index)
        external
        view
        returns (ParlayTypes.ParlayLeg memory leg)
    {
        LibParlay.ParlayTemplate storage template_ = _requireTemplate(LibParlay.store(), templateId);
        if (index >= template_.legCount) {
            revert Errors.InvalidAmount(index);
        }
        leg = LibParlay.store().templateLegs[templateId][index];
    }

    function getParlayTemplatePayoutTier(uint256 templateId, uint256 index)
        external
        view
        returns (ParlayTypes.PayoutTier memory tier)
    {
        LibParlay.ParlayTemplate storage template_ = _requireTemplate(LibParlay.store(), templateId);
        if (index >= template_.tierCount) {
            revert Errors.InvalidAmount(index);
        }
        tier = LibParlay.store().templatePayoutTiers[templateId][index];
    }

    function getParlayOffer(uint256 offerId) external view returns (ParlayTypes.ParlayOfferView memory offerView) {
        LibParlay.ParlayOffer storage offer = _requireOffer(LibParlay.store(), offerId);
        offerView = ParlayTypes.ParlayOfferView({
            offerId: offerId,
            templateId: offer.templateId,
            maker: offer.maker,
            collateralToken: offer.collateralToken,
            premiumPerUnit: offer.premiumPerUnit,
            maxPayoutPerUnit: offer.maxPayoutPerUnit,
            totalUnits: offer.totalUnits,
            remainingUnits: offer.remainingUnits,
            payoutUnit: offer.payoutUnit,
            underwritingFeePerUnit: offer.underwritingFeePerUnit,
            escrowRemaining: offer.escrowRemaining,
            fillDeadline: offer.fillDeadline,
            collateralProfileId: offer.collateralProfileId,
            active: offer.active,
            budgetId: offer.budgetId
        });
    }

    function getParlayRequest(uint256 requestId)
        external
        view
        returns (ParlayTypes.ParlayRequestView memory requestView)
    {
        LibParlay.ParlayRequest storage request = _requireRequest(LibParlay.store(), requestId);
        requestView = ParlayTypes.ParlayRequestView({
            requestId: requestId,
            templateId: request.templateId,
            requester: request.requester,
            collateralToken: request.collateralToken,
            premiumPerUnit: request.premiumPerUnit,
            desiredMaxPayoutPerUnit: request.desiredMaxPayoutPerUnit,
            totalUnits: request.totalUnits,
            remainingUnits: request.remainingUnits,
            payoutUnit: request.payoutUnit,
            underwritingFeePerUnit: request.underwritingFeePerUnit,
            premiumEscrowRemaining: request.premiumEscrowRemaining,
            feeEscrowRemaining: request.feeEscrowRemaining,
            fillDeadline: request.fillDeadline,
            collateralProfileId: request.collateralProfileId,
            active: request.active,
            budgetId: request.budgetId
        });
    }

    function getParlayTicketBucket(uint256 ticketId)
        external
        view
        returns (ParlayTypes.ParlayTicketBucketView memory bucketView)
    {
        LibParlay.ParlayTicketBucket storage bucket = _requireBucket(LibParlay.store(), ticketId);
        bucketView = ParlayTypes.ParlayTicketBucketView({
            ticketId: ticketId,
            templateId: bucket.templateId,
            sourceId: bucket.sourceId,
            underwriter: bucket.underwriter,
            collateralToken: bucket.collateralToken,
            premiumPerUnit: bucket.premiumPerUnit,
            maxPayoutPerUnit: bucket.maxPayoutPerUnit,
            unitsMinted: bucket.unitsMinted,
            unitsClaimed: bucket.unitsClaimed,
            payoutPerUnit: bucket.payoutPerUnit,
            payoutUnit: bucket.payoutUnit,
            escrowRemaining: bucket.escrowRemaining,
            sourceType: bucket.sourceType,
            collateralProfileId: bucket.collateralProfileId,
            finalized: bucket.finalized
        });
    }

    function parlayTicketURI(address ticketToken, uint256 ticketId) external view returns (string memory uri) {
        LibParlay.Config storage config = _requireConfig();
        if (ticketToken != config.ticketToken) {
            return "";
        }

        LibParlay.Storage storage state = LibParlay.store();
        LibParlay.ParlayTicketBucket storage bucket = _requireBucket(state, ticketId);
        LibParlay.ParlayTemplate storage template_ = _requireTemplate(state, bucket.templateId);

        string memory json = string.concat(
            '{"name":"Eves Parlay Ticket #',
            Strings.toString(ticketId),
            '",',
            '"description":"Peer-to-peer underwritten compound event ticket.",',
            '"ticket_id":"',
            Strings.toString(ticketId),
            '",',
            '"template_id":"',
            Strings.toString(bucket.templateId),
            '",',
            '"creator":"',
            Strings.toHexString(template_.creator),
            '",',
            '"underwriter":"',
            Strings.toHexString(bucket.underwriter),
            '",',
            '"premium_per_unit":"',
            Strings.toString(bucket.premiumPerUnit),
            '",',
            '"max_payout_per_unit":"',
            Strings.toString(bucket.maxPayoutPerUnit),
            '",',
            '"payout_per_unit":"',
            Strings.toString(bucket.payoutPerUnit),
            '",',
            '"invalid_policy":"',
            _invalidPolicyLabel(template_.invalidPolicy),
            '",',
            '"legs":',
            _legsJson(state, bucket.templateId, template_.legCount),
            ",",
            '"payout_tiers":',
            _tiersJson(state, bucket.templateId, template_.tierCount),
            "}"
        );
        uri = string.concat(JSON_PREFIX, Base64.encode(bytes(json)));
    }
}
