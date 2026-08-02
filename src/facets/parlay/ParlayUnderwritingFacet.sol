// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {Errors} from "../../libraries/Errors.sol";
import {Events} from "../../libraries/Events.sol";
import {LibParlay} from "../../libraries/LibParlay.sol";
import {LibSafeCast} from "../../libraries/LibSafeCast.sol";
import {ParlayTypes} from "../../types/ParlayTypes.sol";
import {ParlayBase} from "./ParlayBase.sol";

contract ParlayUnderwritingFacet is ParlayBase {
    using SafeERC20 for IERC20;

    struct FillResult {
        uint256 ticketId;
        uint256 premium;
        uint256 fee;
        uint256 escrowLocked;
    }

    function postParlayOffer(
        ParlayTypes.ParlayLeg[] calldata legs,
        ParlayTypes.PayoutTier[] calldata payoutTiers,
        ParlayTypes.InvalidPolicy invalidPolicy,
        string calldata metadataHint,
        uint128 premiumPerUnit,
        uint128 maxPayoutPerUnit,
        uint128 units,
        uint64 fillDeadline
    ) external nonReentrant returns (uint256 offerId) {
        LibParlay.Storage storage state = LibParlay.store();
        uint256 templateId = _createParlayTermsIfMissing(state, legs, payoutTiers, invalidPolicy, metadataHint);
        offerId = _postParlayOffer(
            state, templateId, _defaultParlayCollateral(), premiumPerUnit, maxPayoutPerUnit, units, fillDeadline
        );
    }

    function postParlayOfferWithCollateralProfile(uint8 collateralProfileId, ParlayTypes.QuoteOfferPost calldata post)
        external
        nonReentrant
        returns (uint256 offerId)
    {
        offerId = _postParlayOffer(
            LibParlay.store(),
            _createParlayTermsIfMissing(
                LibParlay.store(), post.legs, post.payoutTiers, post.invalidPolicy, post.metadataHint
            ),
            _parlayCollateralFor(collateralProfileId),
            post.premiumPerUnit,
            post.maxPayoutPerUnit,
            post.units,
            post.fillDeadline
        );
    }

    function fillParlayOffer(uint256 offerId, uint128 units, address receiver)
        external
        nonReentrant
        returns (uint256 ticketId)
    {
        if (receiver == address(0)) {
            revert Errors.ZeroAddress();
        }

        FillResult memory result = _fillParlayOffer(offerId, units, receiver);
        ticketId = result.ticketId;

        emit Events.ParlayOfferFilled(
            offerId,
            result.ticketId,
            msg.sender,
            units,
            LibSafeCast.toUint128(result.premium),
            LibSafeCast.toUint128(result.fee),
            LibSafeCast.toUint128(result.escrowLocked)
        );
    }

    function postParlayRequest(
        ParlayTypes.ParlayLeg[] calldata legs,
        ParlayTypes.PayoutTier[] calldata payoutTiers,
        ParlayTypes.InvalidPolicy invalidPolicy,
        string calldata metadataHint,
        uint128 premiumPerUnit,
        uint128 desiredMaxPayoutPerUnit,
        uint128 units,
        uint64 fillDeadline
    ) external nonReentrant returns (uint256 requestId) {
        LibParlay.Storage storage state = LibParlay.store();
        uint256 templateId = _createParlayTermsIfMissing(state, legs, payoutTiers, invalidPolicy, metadataHint);
        requestId = _postParlayRequest(
            state, templateId, _defaultParlayCollateral(), premiumPerUnit, desiredMaxPayoutPerUnit, units, fillDeadline
        );
    }

    function postParlayRequestWithCollateralProfile(
        uint8 collateralProfileId,
        ParlayTypes.QuoteRequestPost calldata post
    ) external nonReentrant returns (uint256 requestId) {
        requestId = _postParlayRequest(
            LibParlay.store(),
            _createParlayTermsIfMissing(
                LibParlay.store(), post.legs, post.payoutTiers, post.invalidPolicy, post.metadataHint
            ),
            _parlayCollateralFor(collateralProfileId),
            post.premiumPerUnit,
            post.desiredMaxPayoutPerUnit,
            post.units,
            post.fillDeadline
        );
    }

    function fillParlayRequest(uint256 requestId, uint128 units, address ticketReceiver)
        external
        nonReentrant
        returns (uint256 ticketId)
    {
        FillResult memory result = _fillParlayRequest(requestId, units, ticketReceiver);
        ticketId = result.ticketId;

        emit Events.ParlayRequestFilled(
            requestId,
            result.ticketId,
            msg.sender,
            units,
            LibSafeCast.toUint128(result.premium),
            LibSafeCast.toUint128(result.fee),
            LibSafeCast.toUint128(result.escrowLocked)
        );
    }

    function cancelParlayOffer(uint256 offerId) external nonReentrant returns (uint256 escrowReturned) {
        LibParlay.ParlayOffer storage offer = _requireOffer(LibParlay.store(), offerId);
        if (msg.sender != offer.maker) {
            revert Errors.NotMarketCreator(msg.sender, offer.maker);
        }
        _requireActiveOffer(offerId, offer);

        uint128 unitsCancelled = offer.remainingUnits;
        escrowReturned = offer.escrowRemaining;
        offer.remainingUnits = 0;
        offer.escrowRemaining = 0;
        offer.active = false;

        if (escrowReturned != 0) {
            _storedParlayCollateralToken(offer.collateralToken).safeTransfer(offer.maker, escrowReturned);
        }
        emit Events.ParlayOfferCancelled(offerId, msg.sender, unitsCancelled, escrowReturned);
    }

    function cancelParlayRequest(uint256 requestId)
        external
        nonReentrant
        returns (uint256 premiumReturned, uint256 feeReturned)
    {
        LibParlay.ParlayRequest storage request = _requireRequest(LibParlay.store(), requestId);
        if (msg.sender != request.requester) {
            revert Errors.NotMarketCreator(msg.sender, request.requester);
        }
        _requireActiveRequest(requestId, request);

        uint128 unitsCancelled = request.remainingUnits;
        premiumReturned = request.premiumEscrowRemaining;
        feeReturned = request.feeEscrowRemaining;
        request.remainingUnits = 0;
        request.premiumEscrowRemaining = 0;
        request.feeEscrowRemaining = 0;
        request.active = false;

        uint256 refund = premiumReturned + feeReturned;
        if (refund != 0) {
            _storedParlayCollateralToken(request.collateralToken).safeTransfer(request.requester, refund);
        }
        emit Events.ParlayRequestCancelled(requestId, msg.sender, unitsCancelled, premiumReturned, feeReturned);
    }

    function _fillParlayOffer(uint256 offerId, uint128 units, address receiver)
        internal
        returns (FillResult memory result)
    {
        LibParlay.Storage storage state = LibParlay.store();
        LibParlay.ParlayOffer storage offer = _requireOffer(state, offerId);
        _requireActiveOffer(offerId, offer);
        _validateFillableTemplate(offer.templateId, offer.fillDeadline);
        _decreaseRemainingUnits(offerId, units, offer.remainingUnits);

        result.premium = uint256(offer.premiumPerUnit) * units;
        ParlayCollateralContext memory collateralContext = _offerCollateralContext(offer);

        result.fee = uint256(collateralContext.underwritingFee) * units;
        result.escrowLocked = uint256(offer.maxPayoutPerUnit) * units;

        offer.remainingUnits -= units;
        if (offer.budgetId == 0) {
            offer.escrowRemaining -= result.escrowLocked;
        } else {
            LibParlay.SharedBudget storage budget = _requireParlayBudget(state, offer.budgetId);
            _consumeBudget(
                budget,
                offer.budgetId,
                offerId,
                ParlayTypes.SourceType.Offer,
                ParlayTypes.BudgetMode.MakerPayout,
                result.escrowLocked
            );
        }
        if (offer.remainingUnits == 0) {
            offer.active = false;
        }

        IERC20 collateralToken = IERC20(collateralContext.collateralToken);
        collateralToken.safeTransferFrom(msg.sender, address(this), result.premium + result.fee);
        if (result.premium != 0) {
            collateralToken.safeTransfer(offer.maker, result.premium);
        }

        result.ticketId =
            _mintOfferTicket(state, offerId, offer, units, result.escrowLocked, collateralContext, receiver);
        _routeFlatFee(collateralToken, result.ticketId, offerId, uint8(ParlayTypes.SourceType.Offer), result.fee);
    }

    function _fillParlayRequest(uint256 requestId, uint128 units, address ticketReceiver)
        internal
        returns (FillResult memory result)
    {
        LibParlay.Storage storage state = LibParlay.store();
        LibParlay.ParlayRequest storage request = _requireRequest(state, requestId);
        if (ticketReceiver != address(0) && ticketReceiver != request.requester) {
            revert Errors.ParlayReceiverMismatch(request.requester, ticketReceiver);
        }
        _requireActiveRequest(requestId, request);
        _validateFillableTemplate(request.templateId, request.fillDeadline);
        _decreaseRemainingUnits(requestId, units, request.remainingUnits);

        result.premium = uint256(request.premiumPerUnit) * units;
        ParlayCollateralContext memory collateralContext = _requestCollateralContext(request);

        result.fee = uint256(collateralContext.underwritingFee) * units;
        result.escrowLocked = uint256(request.desiredMaxPayoutPerUnit) * units;

        request.remainingUnits -= units;
        if (request.budgetId == 0) {
            request.premiumEscrowRemaining -= result.premium;
            request.feeEscrowRemaining -= result.fee;
        } else {
            LibParlay.SharedBudget storage budget = _requireParlayBudget(state, request.budgetId);
            _consumeBudget(
                budget,
                request.budgetId,
                requestId,
                ParlayTypes.SourceType.Request,
                ParlayTypes.BudgetMode.TakerSpend,
                result.premium + result.fee
            );
        }
        if (request.remainingUnits == 0) {
            request.active = false;
        }

        IERC20 collateralToken = IERC20(collateralContext.collateralToken);
        collateralToken.safeTransferFrom(msg.sender, address(this), result.escrowLocked);
        if (result.premium != 0) {
            collateralToken.safeTransfer(msg.sender, result.premium);
        }

        result.ticketId = _mintRequestTicket(state, requestId, request, units, result.escrowLocked, collateralContext);
        _routeFlatFee(collateralToken, result.ticketId, requestId, uint8(ParlayTypes.SourceType.Request), result.fee);
    }

    function _postParlayOffer(
        LibParlay.Storage storage state,
        uint256 templateId,
        ParlayCollateralContext memory collateralContext,
        uint128 premiumPerUnit,
        uint128 maxPayoutPerUnit,
        uint128 units,
        uint64 fillDeadline
    ) internal returns (uint256 offerId) {
        LibParlay.ParlayTemplate storage template_ = _requireTemplate(state, templateId);
        _requireConfig();
        _validateFillableTemplate(templateId, fillDeadline);
        _validatePostedTerms(template_.maxPayoutPerUnit, maxPayoutPerUnit, units, fillDeadline);

        uint256 escrowRequired = uint256(maxPayoutPerUnit) * units;
        IERC20(collateralContext.collateralToken).safeTransferFrom(msg.sender, address(this), escrowRequired);

        offerId = ++state.nextOfferId;
        state.offers[offerId] = LibParlay.ParlayOffer({
            templateId: templateId,
            maker: msg.sender,
            collateralToken: collateralContext.collateralToken,
            premiumPerUnit: premiumPerUnit,
            maxPayoutPerUnit: maxPayoutPerUnit,
            totalUnits: units,
            remainingUnits: units,
            payoutUnit: collateralContext.payoutUnit,
            underwritingFeePerUnit: collateralContext.underwritingFee,
            escrowRemaining: escrowRequired,
            fillDeadline: fillDeadline,
            collateralProfileId: collateralContext.profileId,
            active: true,
            budgetId: 0
        });

        emit Events.ParlayOfferPosted(
            offerId, templateId, msg.sender, premiumPerUnit, maxPayoutPerUnit, units, fillDeadline
        );
    }

    function _postParlayRequest(
        LibParlay.Storage storage state,
        uint256 templateId,
        ParlayCollateralContext memory collateralContext,
        uint128 premiumPerUnit,
        uint128 desiredMaxPayoutPerUnit,
        uint128 units,
        uint64 fillDeadline
    ) internal returns (uint256 requestId) {
        LibParlay.ParlayTemplate storage template_ = _requireTemplate(state, templateId);
        _validateFillableTemplate(templateId, fillDeadline);
        _validatePostedTerms(template_.maxPayoutPerUnit, desiredMaxPayoutPerUnit, units, fillDeadline);

        uint256 premiumEscrow = uint256(premiumPerUnit) * units;
        uint256 feeEscrow = uint256(collateralContext.underwritingFee) * units;
        IERC20(collateralContext.collateralToken).safeTransferFrom(msg.sender, address(this), premiumEscrow + feeEscrow);

        requestId = ++state.nextRequestId;
        state.requests[requestId] = LibParlay.ParlayRequest({
            templateId: templateId,
            requester: msg.sender,
            collateralToken: collateralContext.collateralToken,
            premiumPerUnit: premiumPerUnit,
            desiredMaxPayoutPerUnit: desiredMaxPayoutPerUnit,
            totalUnits: units,
            remainingUnits: units,
            payoutUnit: collateralContext.payoutUnit,
            underwritingFeePerUnit: collateralContext.underwritingFee,
            premiumEscrowRemaining: premiumEscrow,
            feeEscrowRemaining: feeEscrow,
            fillDeadline: fillDeadline,
            collateralProfileId: collateralContext.profileId,
            active: true,
            budgetId: 0
        });

        emit Events.ParlayRequestPosted(
            requestId, templateId, msg.sender, premiumPerUnit, desiredMaxPayoutPerUnit, units, fillDeadline
        );
    }

    function _offerCollateralContext(LibParlay.ParlayOffer storage offer)
        internal
        view
        returns (ParlayCollateralContext memory collateralContext)
    {
        if (offer.collateralToken == address(0)) {
            return _defaultParlayCollateral();
        }
        collateralContext = ParlayCollateralContext({
            profileId: offer.collateralProfileId,
            collateralToken: offer.collateralToken,
            payoutUnit: offer.payoutUnit,
            underwritingFee: offer.underwritingFeePerUnit
        });
    }

    function _requestCollateralContext(LibParlay.ParlayRequest storage request)
        internal
        view
        returns (ParlayCollateralContext memory collateralContext)
    {
        if (request.collateralToken == address(0)) {
            return _defaultParlayCollateral();
        }
        collateralContext = ParlayCollateralContext({
            profileId: request.collateralProfileId,
            collateralToken: request.collateralToken,
            payoutUnit: request.payoutUnit,
            underwritingFee: request.underwritingFeePerUnit
        });
    }

    function _mintOfferTicket(
        LibParlay.Storage storage state,
        uint256 offerId,
        LibParlay.ParlayOffer storage offer,
        uint128 units,
        uint256 escrowLocked,
        ParlayCollateralContext memory collateralContext,
        address receiver
    ) internal returns (uint256 ticketId) {
        ticketId = _mintIntoBucket(
            state,
            offer.templateId,
            ParlayTypes.SourceType.Offer,
            offerId,
            offer.maker,
            offer.premiumPerUnit,
            offer.maxPayoutPerUnit,
            units,
            escrowLocked,
            collateralContext,
            receiver
        );
    }

    function _mintRequestTicket(
        LibParlay.Storage storage state,
        uint256 requestId,
        LibParlay.ParlayRequest storage request,
        uint128 units,
        uint256 escrowLocked,
        ParlayCollateralContext memory collateralContext
    ) internal returns (uint256 ticketId) {
        ticketId = _mintIntoBucket(
            state,
            request.templateId,
            ParlayTypes.SourceType.Request,
            requestId,
            msg.sender,
            request.premiumPerUnit,
            request.desiredMaxPayoutPerUnit,
            units,
            escrowLocked,
            collateralContext,
            request.requester
        );
    }
}
