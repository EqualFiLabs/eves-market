// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {Errors} from "../../libraries/Errors.sol";
import {Events} from "../../libraries/Events.sol";
import {LibParlay} from "../../libraries/LibParlay.sol";
import {ParlayTypes} from "../../types/ParlayTypes.sol";
import {ParlayBase} from "./ParlayBase.sol";

contract ParlayBudgetFacet is ParlayBase {
    using SafeERC20 for IERC20;

    function createParlayBudget(ParlayTypes.BudgetMode mode, uint256 amount)
        external
        nonReentrant
        returns (uint256 budgetId)
    {
        budgetId = _createParlayBudget(_defaultParlayCollateral(), mode, amount);
    }

    function createParlayBudgetWithCollateralProfile(
        uint8 collateralProfileId,
        ParlayTypes.BudgetMode mode,
        uint256 amount
    ) external nonReentrant returns (uint256 budgetId) {
        budgetId = _createParlayBudget(_parlayCollateralFor(collateralProfileId), mode, amount);
    }

    function _createParlayBudget(
        ParlayCollateralContext memory collateralContext,
        ParlayTypes.BudgetMode mode,
        uint256 amount
    ) internal returns (uint256 budgetId) {
        _validateBudgetMode(mode);
        if (amount == 0) {
            revert Errors.InvalidAmount(amount);
        }

        LibParlay.Storage storage state = LibParlay.store();
        budgetId = ++state.nextBudgetId;
        state.budgets[budgetId] = LibParlay.SharedBudget({
            owner: msg.sender,
            mode: uint8(mode),
            deposited: amount,
            consumed: 0,
            active: true,
            collateralToken: collateralContext.collateralToken,
            payoutUnit: collateralContext.payoutUnit,
            collateralProfileId: collateralContext.profileId
        });

        IERC20(collateralContext.collateralToken).safeTransferFrom(msg.sender, address(this), amount);
        emit Events.ParlayBudgetCreated(budgetId, msg.sender, uint8(mode), amount);
    }

    function fundParlayBudget(uint256 budgetId, uint256 amount) external nonReentrant {
        if (amount == 0) {
            revert Errors.InvalidAmount(amount);
        }

        LibParlay.SharedBudget storage budget = _requireParlayBudget(LibParlay.store(), budgetId);
        _requireBudgetOwner(budget);
        _requireActiveBudget(budgetId, budget);

        budget.deposited += amount;
        IERC20(_activeBudgetCollateralContext(budget).collateralToken)
            .safeTransferFrom(msg.sender, address(this), amount);
        emit Events.ParlayBudgetFunded(budgetId, msg.sender, amount, budget.deposited);
    }

    function cancelParlayBudget(uint256 budgetId) external nonReentrant returns (uint256 refunded) {
        LibParlay.SharedBudget storage budget = _requireParlayBudget(LibParlay.store(), budgetId);
        _requireBudgetOwner(budget);
        _requireActiveBudget(budgetId, budget);

        refunded = _availableBudget(budget);
        budget.active = false;
        budget.deposited = budget.consumed;

        if (refunded != 0) {
            IERC20(_budgetCollateralContext(budget).collateralToken).safeTransfer(budget.owner, refunded);
        }
        emit Events.ParlayBudgetCancelled(budgetId, budget.owner, refunded);
    }

    function getParlayBudget(uint256 budgetId) external view returns (ParlayTypes.SharedBudgetView memory budgetView) {
        LibParlay.SharedBudget storage budget = _requireParlayBudget(LibParlay.store(), budgetId);
        ParlayCollateralContext memory collateralContext = _budgetCollateralContext(budget);
        budgetView = ParlayTypes.SharedBudgetView({
            budgetId: budgetId,
            owner: budget.owner,
            collateralToken: collateralContext.collateralToken,
            mode: budget.mode,
            payoutUnit: collateralContext.payoutUnit,
            deposited: budget.deposited,
            consumed: budget.consumed,
            available: _availableBudget(budget),
            collateralProfileId: collateralContext.profileId,
            active: budget.active
        });
    }

    function postParlayOfferFromBudget(uint256 budgetId, ParlayTypes.BudgetOfferPost calldata post)
        external
        nonReentrant
        returns (uint256 offerId)
    {
        LibParlay.Storage storage state = LibParlay.store();
        ParlayCollateralContext memory collateralContext =
            _requireOwnedActiveBudget(state, budgetId, ParlayTypes.BudgetMode.MakerPayout, 0);

        uint256 templateId =
            _createParlayTermsIfMissing(state, post.legs, post.payoutTiers, post.invalidPolicy, post.metadataHint);
        offerId = _postParlayOfferFromBudget(
            state,
            budgetId,
            templateId,
            collateralContext,
            post.premiumPerUnit,
            post.maxPayoutPerUnit,
            post.units,
            post.fillDeadline
        );
    }

    function postParlayOfferFromBudgetWithCollateralProfile(
        uint256 budgetId,
        uint8 collateralProfileId,
        ParlayTypes.BudgetOfferPost calldata post
    ) external nonReentrant returns (uint256 offerId) {
        LibParlay.Storage storage state = LibParlay.store();
        ParlayCollateralContext memory collateralContext =
            _requireOwnedActiveBudget(state, budgetId, ParlayTypes.BudgetMode.MakerPayout, collateralProfileId);

        uint256 templateId =
            _createParlayTermsIfMissing(state, post.legs, post.payoutTiers, post.invalidPolicy, post.metadataHint);
        offerId = _postParlayOfferFromBudget(
            state,
            budgetId,
            templateId,
            collateralContext,
            post.premiumPerUnit,
            post.maxPayoutPerUnit,
            post.units,
            post.fillDeadline
        );
    }

    function postParlayOffersFromBudgetBatch(uint256 budgetId, ParlayTypes.BudgetOfferPost[] calldata posts)
        external
        nonReentrant
        returns (uint256[] memory offerIds)
    {
        if (posts.length == 0) {
            revert Errors.InvalidAmount(0);
        }

        LibParlay.Storage storage state = LibParlay.store();
        ParlayCollateralContext memory collateralContext =
            _requireOwnedActiveBudget(state, budgetId, ParlayTypes.BudgetMode.MakerPayout, 0);

        offerIds = new uint256[](posts.length);
        for (uint256 index = 0; index < posts.length; ++index) {
            ParlayTypes.BudgetOfferPost calldata post = posts[index];
            offerIds[index] = _postParlayOfferFromBudget(
                state,
                budgetId,
                _createParlayTermsIfMissing(state, post.legs, post.payoutTiers, post.invalidPolicy, post.metadataHint),
                collateralContext,
                post.premiumPerUnit,
                post.maxPayoutPerUnit,
                post.units,
                post.fillDeadline
            );
        }
    }

    function postParlayOffersFromBudgetBatchWithCollateralProfile(
        uint256 budgetId,
        uint8 collateralProfileId,
        ParlayTypes.BudgetOfferPost[] calldata posts
    ) external nonReentrant returns (uint256[] memory offerIds) {
        if (posts.length == 0) {
            revert Errors.InvalidAmount(0);
        }

        LibParlay.Storage storage state = LibParlay.store();
        ParlayCollateralContext memory collateralContext =
            _requireOwnedActiveBudget(state, budgetId, ParlayTypes.BudgetMode.MakerPayout, collateralProfileId);

        offerIds = new uint256[](posts.length);
        for (uint256 index = 0; index < posts.length; ++index) {
            ParlayTypes.BudgetOfferPost calldata post = posts[index];
            offerIds[index] = _postParlayOfferFromBudget(
                state,
                budgetId,
                _createParlayTermsIfMissing(state, post.legs, post.payoutTiers, post.invalidPolicy, post.metadataHint),
                collateralContext,
                post.premiumPerUnit,
                post.maxPayoutPerUnit,
                post.units,
                post.fillDeadline
            );
        }
    }

    function postParlayRequestFromBudget(uint256 budgetId, ParlayTypes.BudgetRequestPost calldata post)
        external
        nonReentrant
        returns (uint256 requestId)
    {
        LibParlay.Storage storage state = LibParlay.store();
        ParlayCollateralContext memory collateralContext =
            _requireOwnedActiveBudget(state, budgetId, ParlayTypes.BudgetMode.TakerSpend, 0);

        uint256 templateId =
            _createParlayTermsIfMissing(state, post.legs, post.payoutTiers, post.invalidPolicy, post.metadataHint);
        requestId = _postParlayRequestFromBudget(
            state,
            budgetId,
            templateId,
            collateralContext,
            post.premiumPerUnit,
            post.desiredMaxPayoutPerUnit,
            post.units,
            post.fillDeadline
        );
    }

    function postParlayRequestFromBudgetWithCollateralProfile(
        uint256 budgetId,
        uint8 collateralProfileId,
        ParlayTypes.BudgetRequestPost calldata post
    ) external nonReentrant returns (uint256 requestId) {
        LibParlay.Storage storage state = LibParlay.store();
        ParlayCollateralContext memory collateralContext =
            _requireOwnedActiveBudget(state, budgetId, ParlayTypes.BudgetMode.TakerSpend, collateralProfileId);

        uint256 templateId =
            _createParlayTermsIfMissing(state, post.legs, post.payoutTiers, post.invalidPolicy, post.metadataHint);
        requestId = _postParlayRequestFromBudget(
            state,
            budgetId,
            templateId,
            collateralContext,
            post.premiumPerUnit,
            post.desiredMaxPayoutPerUnit,
            post.units,
            post.fillDeadline
        );
    }

    function postParlayRequestsFromBudgetBatch(uint256 budgetId, ParlayTypes.BudgetRequestPost[] calldata posts)
        external
        nonReentrant
        returns (uint256[] memory requestIds)
    {
        if (posts.length == 0) {
            revert Errors.InvalidAmount(0);
        }

        LibParlay.Storage storage state = LibParlay.store();
        ParlayCollateralContext memory collateralContext =
            _requireOwnedActiveBudget(state, budgetId, ParlayTypes.BudgetMode.TakerSpend, 0);

        requestIds = new uint256[](posts.length);
        for (uint256 index = 0; index < posts.length; ++index) {
            ParlayTypes.BudgetRequestPost calldata post = posts[index];
            requestIds[index] = _postParlayRequestFromBudget(
                state,
                budgetId,
                _createParlayTermsIfMissing(state, post.legs, post.payoutTiers, post.invalidPolicy, post.metadataHint),
                collateralContext,
                post.premiumPerUnit,
                post.desiredMaxPayoutPerUnit,
                post.units,
                post.fillDeadline
            );
        }
    }

    function postParlayRequestsFromBudgetBatchWithCollateralProfile(
        uint256 budgetId,
        uint8 collateralProfileId,
        ParlayTypes.BudgetRequestPost[] calldata posts
    ) external nonReentrant returns (uint256[] memory requestIds) {
        if (posts.length == 0) {
            revert Errors.InvalidAmount(0);
        }

        LibParlay.Storage storage state = LibParlay.store();
        ParlayCollateralContext memory collateralContext =
            _requireOwnedActiveBudget(state, budgetId, ParlayTypes.BudgetMode.TakerSpend, collateralProfileId);

        requestIds = new uint256[](posts.length);
        for (uint256 index = 0; index < posts.length; ++index) {
            ParlayTypes.BudgetRequestPost calldata post = posts[index];
            requestIds[index] = _postParlayRequestFromBudget(
                state,
                budgetId,
                _createParlayTermsIfMissing(state, post.legs, post.payoutTiers, post.invalidPolicy, post.metadataHint),
                collateralContext,
                post.premiumPerUnit,
                post.desiredMaxPayoutPerUnit,
                post.units,
                post.fillDeadline
            );
        }
    }

    function _postParlayOfferFromBudget(
        LibParlay.Storage storage state,
        uint256 budgetId,
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
            escrowRemaining: 0,
            fillDeadline: fillDeadline,
            collateralProfileId: collateralContext.profileId,
            active: true,
            budgetId: budgetId
        });

        emit Events.ParlayOfferPosted(
            offerId, templateId, msg.sender, premiumPerUnit, maxPayoutPerUnit, units, fillDeadline
        );
        emit Events.ParlayBudgetOfferPosted(
            offerId, budgetId, templateId, msg.sender, premiumPerUnit, maxPayoutPerUnit, units, fillDeadline
        );
    }

    function _postParlayRequestFromBudget(
        LibParlay.Storage storage state,
        uint256 budgetId,
        uint256 templateId,
        ParlayCollateralContext memory collateralContext,
        uint128 premiumPerUnit,
        uint128 desiredMaxPayoutPerUnit,
        uint128 units,
        uint64 fillDeadline
    ) internal returns (uint256 requestId) {
        LibParlay.ParlayTemplate storage template_ = _requireTemplate(state, templateId);
        _requireConfig();
        _validateFillableTemplate(templateId, fillDeadline);
        _validatePostedTerms(template_.maxPayoutPerUnit, desiredMaxPayoutPerUnit, units, fillDeadline);

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
            premiumEscrowRemaining: 0,
            feeEscrowRemaining: 0,
            fillDeadline: fillDeadline,
            collateralProfileId: collateralContext.profileId,
            active: true,
            budgetId: budgetId
        });

        emit Events.ParlayRequestPosted(
            requestId, templateId, msg.sender, premiumPerUnit, desiredMaxPayoutPerUnit, units, fillDeadline
        );
        emit Events.ParlayBudgetRequestPosted(
            requestId, budgetId, templateId, msg.sender, premiumPerUnit, desiredMaxPayoutPerUnit, units, fillDeadline
        );
    }

    function _validateBudgetMode(ParlayTypes.BudgetMode mode) internal pure {
        if (uint8(mode) > uint8(ParlayTypes.BudgetMode.TakerSpend)) {
            revert Errors.ParlayBudgetWrongMode(uint8(ParlayTypes.BudgetMode.TakerSpend), uint8(mode));
        }
    }

    function _requireOwnedActiveBudget(
        LibParlay.Storage storage state,
        uint256 budgetId,
        ParlayTypes.BudgetMode expectedMode,
        uint8 collateralProfileId
    ) internal view returns (ParlayCollateralContext memory collateralContext) {
        LibParlay.SharedBudget storage budget = _requireParlayBudget(state, budgetId);
        _requireBudgetOwner(budget);
        _requireActiveBudget(budgetId, budget);
        _requireBudgetMode(budget, expectedMode);
        collateralContext = _requireBudgetCollateralProfile(budget, budgetId, collateralProfileId);
    }
}
