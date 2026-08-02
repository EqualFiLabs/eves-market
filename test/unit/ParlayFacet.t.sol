// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC1155} from "../../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";

import {ParlayAdminFacet} from "../../src/facets/parlay/ParlayAdminFacet.sol";
import {ParlayBookFacet} from "../../src/facets/parlay/ParlayBookFacet.sol";
import {ParlayBudgetFacet} from "../../src/facets/parlay/ParlayBudgetFacet.sol";
import {ParlayMulticallFacet} from "../../src/facets/parlay/ParlayMulticallFacet.sol";
import {ParlaySettlementFacet} from "../../src/facets/parlay/ParlaySettlementFacet.sol";
import {ParlayUnderwritingFacet} from "../../src/facets/parlay/ParlayUnderwritingFacet.sol";
import {ParlayViewFacet} from "../../src/facets/parlay/ParlayViewFacet.sol";
import {MarginAccountFacet} from "../../src/facets/MarginAccountFacet.sol";
import {SeniorCapitalFacet} from "../../src/facets/SeniorCapitalFacet.sol";
import {SeniorCapitalViewFacet} from "../../src/facets/SeniorCapitalViewFacet.sol";
import {IMarginAccountFacet} from "../../src/interfaces/IMarginAccountFacet.sol";
import {IParlayFacet} from "../../src/interfaces/IParlayFacet.sol";
import {ISeniorCapitalFacet} from "../../src/interfaces/ISeniorCapitalFacet.sol";
import {BookFacet} from "../../src/facets/BookFacet.sol";
import {ParlayTicketToken} from "../../src/tokens/ParlayTicketToken.sol";
import {CurveCLOBTypes} from "../../src/types/CurveCLOBTypes.sol";
import {ParlayTypes} from "../../src/types/ParlayTypes.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";

import {TestBase} from "../helpers/TestBase.sol";

contract ParlayFacetTest is TestBase {
    uint128 internal constant FLAT_FEE = 3e6;
    address internal feeRecipient;
    ParlayAdminFacet internal parlayAdminFacet;
    ParlayUnderwritingFacet internal parlayUnderwritingFacet;
    ParlayBudgetFacet internal parlayBudgetFacet;
    ParlaySettlementFacet internal parlaySettlementFacet;
    ParlayBookFacet internal parlayBookFacet;
    ParlayViewFacet internal parlayViewFacet;
    ParlayMulticallFacet internal parlayMulticallFacet;
    BookFacet internal bookFacet;
    ParlayTicketToken internal ticketToken;

    function setUp() public override {
        super.setUp();

        feeRecipient = makeAddr("parlay-fee-recipient");
        parlayAdminFacet = new ParlayAdminFacet();
        parlayUnderwritingFacet = new ParlayUnderwritingFacet();
        parlayBudgetFacet = new ParlayBudgetFacet();
        parlaySettlementFacet = new ParlaySettlementFacet();
        parlayBookFacet = new ParlayBookFacet();
        parlayViewFacet = new ParlayViewFacet();
        parlayMulticallFacet = new ParlayMulticallFacet();
        bookFacet = new BookFacet();
        ticketToken = new ParlayTicketToken(address(diamond), "uri://parlay/{id}");

        vm.startPrank(owner);
        diamond.registerFacet(address(parlayAdminFacet), _parlayAdminSelectors());
        diamond.registerFacet(address(parlayUnderwritingFacet), _parlayUnderwritingSelectors());
        diamond.registerFacet(address(parlayBudgetFacet), _parlayBudgetSelectors());
        diamond.registerFacet(address(parlaySettlementFacet), _parlaySettlementSelectors());
        diamond.registerFacet(address(parlayBookFacet), _parlayBookSelectors());
        diamond.registerFacet(address(parlayViewFacet), _parlayViewSelectors());
        diamond.registerFacet(address(parlayMulticallFacet), _parlayMulticallSelectors());
        diamond.registerFacet(address(bookFacet), _bookSelectors());
        diamond.registerFacet(address(new MarginAccountFacet()), _marginAssetSelectors());
        diamond.registerFacet(address(new SeniorCapitalFacet()), _seniorCapitalSelectors());
        diamond.registerFacet(address(new SeniorCapitalViewFacet()), _seniorCapitalViewSelectors());
        IMarginAccountFacet(address(diamond)).setMarginAsset(address(usdc));
        IParlayFacet(address(diamond)).setParlayConfig(address(ticketToken), feeRecipient, FLAT_FEE, 0, 10_000);
        vm.stopPrank();
    }

    function test_ParlayFeeAccruesToInternalSeniorIndex() public {
        vm.prank(owner);
        IParlayFacet(address(diamond)).setParlayConfig(address(ticketToken), feeRecipient, FLAT_FEE, 10_000, 0);
        vm.startPrank(creator);
        usdc.approve(address(diamond), 100e6);
        ISeniorCapitalFacet(address(diamond)).depositSeniorCapital(100e6);
        vm.warp(block.timestamp + 24 hours);
        ISeniorCapitalFacet(address(diamond)).activateSeniorCapital();
        vm.stopPrank();

        bytes32[] memory marketIds = _createMarkets(2);
        ParlayTypes.ParlayLeg[] memory legs = _buildSortedLegs(marketIds, _yesYesOutcomes());
        ParlayTypes.PayoutTier[] memory tiers = _allOrNothingTiers(2, 100e6);
        vm.startPrank(maker);
        usdc.approve(address(diamond), 100e6);
        uint256 offerId = IParlayFacet(address(diamond))
            .postParlayOffer(
                legs, tiers, ParlayTypes.InvalidPolicy.VoidInvalidLegs, "ipfs://senior-fee", 10e6, 100e6, 1, _deadline()
            );
        vm.stopPrank();
        vm.startPrank(taker);
        usdc.approve(address(diamond), 13e6);
        IParlayFacet(address(diamond)).fillParlayOffer(offerId, 1, taker);
        vm.stopPrank();

        assertEq(ISeniorCapitalFacet(address(diamond)).seniorCapitalState().feeReserve, FLAT_FEE);
        assertEq(ISeniorCapitalFacet(address(diamond)).pendingSeniorCapitalFees(creator), FLAT_FEE);
        assertEq(usdc.balanceOf(feeRecipient), 0);
    }

    function test_MakerPostedOfferEscrowsMintsFinalizesAndClaims() public {
        bytes32[] memory marketIds = _createMarkets(2);
        uint8[] memory outcomes = _yesYesOutcomes();
        ParlayTypes.PayoutTier[] memory tiers = _allOrNothingTiers(2, 100e6);
        ParlayTypes.ParlayLeg[] memory legs = _buildSortedLegs(marketIds, outcomes);

        vm.startPrank(maker);
        usdc.approve(address(diamond), 300e6);
        uint256 offerId = IParlayFacet(address(diamond))
            .postParlayOffer(
                legs, tiers, ParlayTypes.InvalidPolicy.VoidInvalidLegs, "ipfs://offer", 10e6, 100e6, 3, _deadline()
            );
        vm.stopPrank();

        uint256 makerAfterPost = usdc.balanceOf(maker);

        vm.startPrank(taker);
        usdc.approve(address(diamond), 26e6);
        uint256 ticketId = IParlayFacet(address(diamond)).fillParlayOffer(offerId, 2, taker);
        vm.stopPrank();

        assertEq(IERC1155(address(ticketToken)).balanceOf(taker, ticketId), 2);
        assertEq(usdc.balanceOf(maker), makerAfterPost + 20e6);
        assertEq(usdc.balanceOf(feeRecipient), 6e6);

        ParlayTypes.ParlayOfferView memory offer = IParlayFacet(address(diamond)).getParlayOffer(offerId);
        assertEq(offer.remainingUnits, 1);
        assertEq(offer.escrowRemaining, 100e6);

        _resolveMarketFixture(marketIds[0], 1);
        _resolveMarketFixture(marketIds[1], 1);

        uint256 takerBeforeClaim = usdc.balanceOf(taker);
        uint128 payoutPerUnit = IParlayFacet(address(diamond)).finalizeParlayTicketBucket(ticketId);
        assertEq(payoutPerUnit, 100e6);

        vm.prank(taker);
        uint256 payout = IParlayFacet(address(diamond)).claimParlayTicket(ticketId, 2, taker);

        assertEq(payout, 200e6);
        assertEq(usdc.balanceOf(taker) - takerBeforeClaim, 200e6);
        assertEq(IERC1155(address(ticketToken)).balanceOf(taker, ticketId), 0);

        ParlayTypes.ParlayTicketBucketView memory bucket =
            IParlayFacet(address(diamond)).getParlayTicketBucket(ticketId);
        assertEq(bucket.unitsClaimed, 2);
        assertEq(bucket.escrowRemaining, 0);
    }

    function test_BuyerPostedRequestPaysUnderwriterAndMintsToRequester() public {
        bytes32[] memory marketIds = _createMarkets(2);
        uint8[] memory outcomes = _yesYesOutcomes();
        ParlayTypes.PayoutTier[] memory tiers = _allOrNothingTiers(2, 100e6);
        ParlayTypes.ParlayLeg[] memory legs = _buildSortedLegs(marketIds, outcomes);

        vm.startPrank(taker);
        usdc.approve(address(diamond), 26e6);
        uint256 requestId = IParlayFacet(address(diamond))
            .postParlayRequest(
                legs, tiers, ParlayTypes.InvalidPolicy.VoidInvalidLegs, "ipfs://request", 10e6, 100e6, 2, _deadline()
            );
        vm.stopPrank();

        uint256 makerBeforeFill = usdc.balanceOf(maker);
        vm.startPrank(maker);
        usdc.approve(address(diamond), 100e6);
        uint256 ticketId = IParlayFacet(address(diamond)).fillParlayRequest(requestId, 1, taker);
        vm.stopPrank();

        assertEq(usdc.balanceOf(maker), makerBeforeFill - 90e6);
        assertEq(usdc.balanceOf(feeRecipient), 3e6);
        assertEq(IERC1155(address(ticketToken)).balanceOf(taker, ticketId), 1);

        ParlayTypes.ParlayRequestView memory request = IParlayFacet(address(diamond)).getParlayRequest(requestId);
        assertEq(request.remainingUnits, 1);
        assertEq(request.premiumEscrowRemaining, 10e6);
        assertEq(request.feeEscrowRemaining, 3e6);

        uint256 takerBeforeCancel = usdc.balanceOf(taker);
        vm.prank(taker);
        (uint256 premiumReturned, uint256 feeReturned) = IParlayFacet(address(diamond)).cancelParlayRequest(requestId);
        assertEq(premiumReturned, 10e6);
        assertEq(feeReturned, 3e6);
        assertEq(usdc.balanceOf(taker) - takerBeforeCancel, 13e6);
    }

    function test_PostOfferCreatesReusableTermsAndEscrowsPayout() public {
        bytes32[] memory marketIds = _createMarkets(2);
        uint8[] memory outcomes = _yesYesOutcomes();
        ParlayTypes.PayoutTier[] memory tiers = _allOrNothingTiers(2, 100e6);
        ParlayTypes.ParlayLeg[] memory legs = _buildSortedLegs(marketIds, outcomes);
        uint256 templateId = IParlayFacet(address(diamond))
            .computeParlayTemplateId(legs, tiers, ParlayTypes.InvalidPolicy.VoidInvalidLegs);

        vm.startPrank(maker);
        usdc.approve(address(diamond), 300e6);
        uint256 offerId = IParlayFacet(address(diamond))
            .postParlayOffer(
                legs,
                tiers,
                ParlayTypes.InvalidPolicy.VoidInvalidLegs,
                "ipfs://atomic-offer",
                10e6,
                100e6,
                3,
                _deadline()
            );
        vm.stopPrank();

        ParlayTypes.ParlayTemplateView memory template_ = IParlayFacet(address(diamond)).getParlayTemplate(templateId);
        assertEq(template_.creator, maker);
        assertEq(template_.metadataHint, "ipfs://atomic-offer");

        ParlayTypes.ParlayOfferView memory offer = IParlayFacet(address(diamond)).getParlayOffer(offerId);
        assertEq(offer.templateId, templateId);
        assertEq(offer.maker, maker);
        assertEq(offer.remainingUnits, 3);
        assertEq(offer.escrowRemaining, 300e6);
    }

    function test_PostRequestReusesExistingTerms() public {
        bytes32[] memory marketIds = _createMarkets(2);
        uint8[] memory outcomes = _yesYesOutcomes();
        ParlayTypes.PayoutTier[] memory tiers = _allOrNothingTiers(2, 100e6);
        ParlayTypes.ParlayLeg[] memory legs = _buildSortedLegs(marketIds, outcomes);
        uint256 templateId = IParlayFacet(address(diamond))
            .computeParlayTemplateId(legs, tiers, ParlayTypes.InvalidPolicy.VoidInvalidLegs);

        vm.startPrank(taker);
        usdc.approve(address(diamond), 26e6);
        uint256 firstRequestId = IParlayFacet(address(diamond))
            .postParlayRequest(
                legs,
                tiers,
                ParlayTypes.InvalidPolicy.VoidInvalidLegs,
                "ipfs://atomic-request",
                10e6,
                100e6,
                1,
                _deadline()
            );
        uint256 secondRequestId = IParlayFacet(address(diamond))
            .postParlayRequest(
                legs, tiers, ParlayTypes.InvalidPolicy.VoidInvalidLegs, "ipfs://ignored", 10e6, 100e6, 1, _deadline()
            );
        vm.stopPrank();

        assertGt(secondRequestId, firstRequestId);

        ParlayTypes.ParlayTemplateView memory template_ = IParlayFacet(address(diamond)).getParlayTemplate(templateId);
        assertEq(template_.metadataHint, "ipfs://atomic-request");

        ParlayTypes.ParlayRequestView memory request = IParlayFacet(address(diamond)).getParlayRequest(secondRequestId);
        assertEq(request.templateId, templateId);
        assertEq(request.requester, taker);
        assertEq(request.premiumEscrowRemaining, 10e6);
        assertEq(request.feeEscrowRemaining, 3e6);
    }

    function test_MakerBudgetBacksOverPostedOffersAndCancelsAvailable() public {
        bytes32[] memory marketIds = _createMarkets(2);
        uint8[] memory outcomes = _yesYesOutcomes();
        ParlayTypes.PayoutTier[] memory tiers = _allOrNothingTiers(2, 100e6);
        ParlayTypes.ParlayLeg[] memory legs = _buildSortedLegs(marketIds, outcomes);

        vm.startPrank(maker);
        usdc.approve(address(diamond), 250e6);
        uint256 budgetId = IParlayFacet(address(diamond)).createParlayBudget(ParlayTypes.BudgetMode.MakerPayout, 200e6);
        IParlayFacet(address(diamond)).fundParlayBudget(budgetId, 50e6);
        IParlayFacet(address(diamond))
            .postParlayOfferFromBudget(budgetId, _budgetOfferPost(legs, tiers, "ipfs://budget-offer", 10e6, 100e6, 3));
        uint256 secondOfferId = IParlayFacet(address(diamond))
            .postParlayOfferFromBudget(budgetId, _budgetOfferPost(legs, tiers, "ipfs://budget-offer", 10e6, 100e6, 3));
        vm.stopPrank();

        ParlayTypes.ParlayOfferView memory offer = IParlayFacet(address(diamond)).getParlayOffer(secondOfferId);
        assertEq(offer.budgetId, budgetId);
        assertEq(offer.escrowRemaining, 0);

        vm.startPrank(taker);
        usdc.approve(address(diamond), 26e6);
        uint256 ticketId = IParlayFacet(address(diamond)).fillParlayOffer(secondOfferId, 2, taker);
        vm.stopPrank();

        ParlayTypes.SharedBudgetView memory budget = IParlayFacet(address(diamond)).getParlayBudget(budgetId);
        assertEq(budget.consumed, 200e6);
        assertEq(budget.available, 50e6);
        assertEq(IERC1155(address(ticketToken)).balanceOf(taker, ticketId), 2);

        vm.startPrank(taker);
        usdc.approve(address(diamond), 13e6);
        vm.expectRevert(abi.encodeWithSelector(Errors.ParlayBudgetInsufficient.selector, 100e6, 50e6));
        IParlayFacet(address(diamond)).fillParlayOffer(secondOfferId, 1, taker);
        vm.stopPrank();

        uint256 makerBeforeCancel = usdc.balanceOf(maker);
        vm.prank(maker);
        uint256 refunded = IParlayFacet(address(diamond)).cancelParlayBudget(budgetId);
        assertEq(refunded, 50e6);
        assertEq(usdc.balanceOf(maker) - makerBeforeCancel, 50e6);

        budget = IParlayFacet(address(diamond)).getParlayBudget(budgetId);
        assertFalse(budget.active);
        assertEq(budget.available, 0);
    }

    function test_TakerBudgetPaysPremiumAndFeeFromSharedSpend() public {
        bytes32[] memory marketIds = _createMarkets(2);
        uint8[] memory outcomes = _yesYesOutcomes();
        ParlayTypes.PayoutTier[] memory tiers = _allOrNothingTiers(2, 100e6);
        ParlayTypes.ParlayLeg[] memory legs = _buildSortedLegs(marketIds, outcomes);

        vm.startPrank(taker);
        usdc.approve(address(diamond), 39e6);
        uint256 budgetId = IParlayFacet(address(diamond)).createParlayBudget(ParlayTypes.BudgetMode.TakerSpend, 39e6);
        uint256 requestId = IParlayFacet(address(diamond))
            .postParlayRequestFromBudget(
                budgetId, _budgetRequestPost(legs, tiers, "ipfs://budget-request", 10e6, 100e6, 4)
            );
        vm.stopPrank();

        ParlayTypes.ParlayRequestView memory request = IParlayFacet(address(diamond)).getParlayRequest(requestId);
        assertEq(request.budgetId, budgetId);
        assertEq(request.premiumEscrowRemaining, 0);
        assertEq(request.feeEscrowRemaining, 0);

        uint256 makerBeforeFill = usdc.balanceOf(maker);
        vm.startPrank(maker);
        usdc.approve(address(diamond), 200e6);
        uint256 ticketId = IParlayFacet(address(diamond)).fillParlayRequest(requestId, 2, taker);
        vm.stopPrank();

        assertEq(usdc.balanceOf(maker), makerBeforeFill - 180e6);
        assertEq(usdc.balanceOf(feeRecipient), 6e6);
        assertEq(IERC1155(address(ticketToken)).balanceOf(taker, ticketId), 2);

        ParlayTypes.SharedBudgetView memory budget = IParlayFacet(address(diamond)).getParlayBudget(budgetId);
        assertEq(budget.consumed, 26e6);
        assertEq(budget.available, 13e6);

        vm.startPrank(maker);
        usdc.approve(address(diamond), 200e6);
        vm.expectRevert(abi.encodeWithSelector(Errors.ParlayBudgetInsufficient.selector, 26e6, 13e6));
        IParlayFacet(address(diamond)).fillParlayRequest(requestId, 2, taker);
        vm.stopPrank();
    }

    function test_BatchPostsMakerBudgetOffers() public {
        bytes32[] memory marketIds = _createMarkets(3);
        ParlayTypes.ParlayLeg[] memory legsA = _buildSortedLegs(_selectMarkets(marketIds, 0, 1), _yesYesOutcomes());
        ParlayTypes.ParlayLeg[] memory legsB = _buildSortedLegs(_selectMarkets(marketIds, 1, 2), _yesYesOutcomes());
        ParlayTypes.PayoutTier[] memory tiersA = _allOrNothingTiers(2, 80e6);
        ParlayTypes.PayoutTier[] memory tiersB = _allOrNothingTiers(2, 120e6);
        uint256 templateIdA = IParlayFacet(address(diamond))
            .computeParlayTemplateId(legsA, tiersA, ParlayTypes.InvalidPolicy.VoidInvalidLegs);
        uint256 templateIdB = IParlayFacet(address(diamond))
            .computeParlayTemplateId(legsB, tiersB, ParlayTypes.InvalidPolicy.VoidInvalidLegs);

        ParlayTypes.BudgetOfferPost[] memory posts = new ParlayTypes.BudgetOfferPost[](2);
        posts[0] = ParlayTypes.BudgetOfferPost({
            legs: legsA,
            payoutTiers: tiersA,
            invalidPolicy: ParlayTypes.InvalidPolicy.VoidInvalidLegs,
            metadataHint: "ipfs://budget-offer-a",
            premiumPerUnit: 8e6,
            maxPayoutPerUnit: 80e6,
            units: 5,
            fillDeadline: _deadline()
        });
        posts[1] = ParlayTypes.BudgetOfferPost({
            legs: legsB,
            payoutTiers: tiersB,
            invalidPolicy: ParlayTypes.InvalidPolicy.VoidInvalidLegs,
            metadataHint: "ipfs://budget-offer-b",
            premiumPerUnit: 12e6,
            maxPayoutPerUnit: 120e6,
            units: 2,
            fillDeadline: _deadline()
        });

        vm.startPrank(maker);
        usdc.approve(address(diamond), 100e6);
        uint256 budgetId = IParlayFacet(address(diamond)).createParlayBudget(ParlayTypes.BudgetMode.MakerPayout, 100e6);
        uint256[] memory offerIds = IParlayFacet(address(diamond)).postParlayOffersFromBudgetBatch(budgetId, posts);
        vm.stopPrank();

        assertEq(offerIds.length, 2);
        ParlayTypes.ParlayOfferView memory offerA = IParlayFacet(address(diamond)).getParlayOffer(offerIds[0]);
        ParlayTypes.ParlayOfferView memory offerB = IParlayFacet(address(diamond)).getParlayOffer(offerIds[1]);
        assertEq(offerA.budgetId, budgetId);
        assertEq(offerA.templateId, templateIdA);
        assertEq(offerA.totalUnits, 5);
        assertEq(offerA.escrowRemaining, 0);
        assertEq(offerB.budgetId, budgetId);
        assertEq(offerB.templateId, templateIdB);
        assertEq(offerB.totalUnits, 2);
        assertEq(offerB.escrowRemaining, 0);
    }

    function test_BatchPostsTakerBudgetRequests() public {
        bytes32[] memory marketIds = _createMarkets(3);
        ParlayTypes.ParlayLeg[] memory legsA = _buildSortedLegs(_selectMarkets(marketIds, 0, 1), _yesYesOutcomes());
        ParlayTypes.ParlayLeg[] memory legsB = _buildSortedLegs(_selectMarkets(marketIds, 1, 2), _yesYesOutcomes());
        ParlayTypes.PayoutTier[] memory tiersA = _allOrNothingTiers(2, 80e6);
        ParlayTypes.PayoutTier[] memory tiersB = _allOrNothingTiers(2, 120e6);
        uint256 templateIdA = IParlayFacet(address(diamond))
            .computeParlayTemplateId(legsA, tiersA, ParlayTypes.InvalidPolicy.VoidInvalidLegs);
        uint256 templateIdB = IParlayFacet(address(diamond))
            .computeParlayTemplateId(legsB, tiersB, ParlayTypes.InvalidPolicy.VoidInvalidLegs);

        ParlayTypes.BudgetRequestPost[] memory posts = new ParlayTypes.BudgetRequestPost[](2);
        posts[0] = ParlayTypes.BudgetRequestPost({
            legs: legsA,
            payoutTiers: tiersA,
            invalidPolicy: ParlayTypes.InvalidPolicy.VoidInvalidLegs,
            metadataHint: "ipfs://budget-request-a",
            premiumPerUnit: 8e6,
            desiredMaxPayoutPerUnit: 80e6,
            units: 5,
            fillDeadline: _deadline()
        });
        posts[1] = ParlayTypes.BudgetRequestPost({
            legs: legsB,
            payoutTiers: tiersB,
            invalidPolicy: ParlayTypes.InvalidPolicy.VoidInvalidLegs,
            metadataHint: "ipfs://budget-request-b",
            premiumPerUnit: 12e6,
            desiredMaxPayoutPerUnit: 120e6,
            units: 2,
            fillDeadline: _deadline()
        });

        vm.startPrank(taker);
        usdc.approve(address(diamond), 100e6);
        uint256 budgetId = IParlayFacet(address(diamond)).createParlayBudget(ParlayTypes.BudgetMode.TakerSpend, 100e6);
        uint256[] memory requestIds = IParlayFacet(address(diamond)).postParlayRequestsFromBudgetBatch(budgetId, posts);
        vm.stopPrank();

        assertEq(requestIds.length, 2);
        ParlayTypes.ParlayRequestView memory requestA = IParlayFacet(address(diamond)).getParlayRequest(requestIds[0]);
        ParlayTypes.ParlayRequestView memory requestB = IParlayFacet(address(diamond)).getParlayRequest(requestIds[1]);
        assertEq(requestA.budgetId, budgetId);
        assertEq(requestA.templateId, templateIdA);
        assertEq(requestA.totalUnits, 5);
        assertEq(requestA.premiumEscrowRemaining, 0);
        assertEq(requestA.feeEscrowRemaining, 0);
        assertEq(requestB.budgetId, budgetId);
        assertEq(requestB.templateId, templateIdB);
        assertEq(requestB.totalUnits, 2);
        assertEq(requestB.premiumEscrowRemaining, 0);
        assertEq(requestB.feeEscrowRemaining, 0);
    }

    function test_CancelledBudgetBlocksLinkedFillsWithoutTouchingTicket() public {
        bytes32[] memory marketIds = _createMarkets(2);
        uint8[] memory outcomes = _yesYesOutcomes();
        ParlayTypes.PayoutTier[] memory tiers = _allOrNothingTiers(2, 100e6);
        ParlayTypes.ParlayLeg[] memory legs = _buildSortedLegs(marketIds, outcomes);

        vm.startPrank(maker);
        usdc.approve(address(diamond), 250e6);
        uint256 budgetId = IParlayFacet(address(diamond)).createParlayBudget(ParlayTypes.BudgetMode.MakerPayout, 250e6);
        uint256 offerId = IParlayFacet(address(diamond))
            .postParlayOfferFromBudget(budgetId, _budgetOfferPost(legs, tiers, "ipfs://budget-offer", 10e6, 100e6, 3));
        vm.stopPrank();

        vm.startPrank(taker);
        usdc.approve(address(diamond), 13e6);
        uint256 ticketId = IParlayFacet(address(diamond)).fillParlayOffer(offerId, 1, taker);
        vm.stopPrank();

        vm.prank(maker);
        assertEq(IParlayFacet(address(diamond)).cancelParlayBudget(budgetId), 150e6);

        vm.startPrank(taker);
        usdc.approve(address(diamond), 13e6);
        vm.expectRevert(abi.encodeWithSelector(Errors.ParlayBudgetInactive.selector, budgetId));
        IParlayFacet(address(diamond)).fillParlayOffer(offerId, 1, taker);
        vm.stopPrank();

        _resolveMarketFixture(marketIds[0], 1);
        _resolveMarketFixture(marketIds[1], 1);

        assertEq(IParlayFacet(address(diamond)).finalizeParlayTicketBucket(ticketId), 100e6);
        vm.prank(taker);
        assertEq(IParlayFacet(address(diamond)).claimParlayTicket(ticketId, 1, taker), 100e6);
    }

    function test_CancelOfferReturnsOnlyUnfilledEscrow() public {
        bytes32[] memory marketIds = _createMarkets(2);
        uint8[] memory outcomes = _yesYesOutcomes();
        ParlayTypes.PayoutTier[] memory tiers = _allOrNothingTiers(2, 100e6);
        ParlayTypes.ParlayLeg[] memory legs = _buildSortedLegs(marketIds, outcomes);

        vm.startPrank(maker);
        usdc.approve(address(diamond), 300e6);
        uint256 offerId = IParlayFacet(address(diamond))
            .postParlayOffer(
                legs, tiers, ParlayTypes.InvalidPolicy.VoidInvalidLegs, "ipfs://offer", 10e6, 100e6, 3, _deadline()
            );
        vm.stopPrank();

        vm.startPrank(taker);
        usdc.approve(address(diamond), 13e6);
        IParlayFacet(address(diamond)).fillParlayOffer(offerId, 1, taker);
        vm.stopPrank();

        uint256 makerBeforeCancel = usdc.balanceOf(maker);
        vm.prank(maker);
        uint256 returned = IParlayFacet(address(diamond)).cancelParlayOffer(offerId);

        assertEq(returned, 200e6);
        assertEq(usdc.balanceOf(maker) - makerBeforeCancel, 200e6);

        ParlayTypes.ParlayOfferView memory offer = IParlayFacet(address(diamond)).getParlayOffer(offerId);
        assertEq(offer.remainingUnits, 0);
        assertEq(offer.escrowRemaining, 0);
        assertFalse(offer.active);
    }

    function test_VoidInvalidLegsUsesRemainingHitCount() public {
        bytes32[] memory marketIds = _createMarkets(3);
        uint8[] memory outcomes = new uint8[](3);
        outcomes[0] = 1;
        outcomes[1] = 1;
        outcomes[2] = 1;

        ParlayTypes.PayoutTier[] memory tiers = new ParlayTypes.PayoutTier[](2);
        tiers[0] = ParlayTypes.PayoutTier({minHits: 3, payout: 90e6});
        tiers[1] = ParlayTypes.PayoutTier({minHits: 2, payout: 30e6});

        uint256 ticketId =
            _postAndFillOneUnit(marketIds, outcomes, tiers, ParlayTypes.InvalidPolicy.VoidInvalidLegs, 90e6);

        _resolveMarketFixture(marketIds[0], 1);
        _resolveMarketFixture(marketIds[1], 1);
        _resolveMarketFixture(marketIds[2], 3);

        uint256 makerBeforeFinalize = usdc.balanceOf(maker);
        uint128 payoutPerUnit = IParlayFacet(address(diamond)).finalizeParlayTicketBucket(ticketId);
        assertEq(payoutPerUnit, 30e6);
        assertEq(usdc.balanceOf(maker) - makerBeforeFinalize, 60e6);

        vm.prank(taker);
        uint256 payout = IParlayFacet(address(diamond)).claimParlayTicket(ticketId, 1, taker);
        assertEq(payout, 30e6);
    }

    function test_InvalidCountsAsMissKeepsInvalidLegInMissCount() public {
        bytes32[] memory marketIds = _createMarkets(3);
        uint8[] memory outcomes = new uint8[](3);
        outcomes[0] = 1;
        outcomes[1] = 1;
        outcomes[2] = 1;

        ParlayTypes.PayoutTier[] memory tiers = new ParlayTypes.PayoutTier[](1);
        tiers[0] = ParlayTypes.PayoutTier({minHits: 3, payout: 90e6});

        uint256 ticketId =
            _postAndFillOneUnit(marketIds, outcomes, tiers, ParlayTypes.InvalidPolicy.InvalidCountsAsMiss, 90e6);

        _resolveMarketFixture(marketIds[0], 1);
        _resolveMarketFixture(marketIds[1], 1);
        _resolveMarketFixture(marketIds[2], 3);

        uint256 makerBeforeFinalize = usdc.balanceOf(maker);
        uint128 payoutPerUnit = IParlayFacet(address(diamond)).finalizeParlayTicketBucket(ticketId);

        assertEq(payoutPerUnit, 0);
        assertEq(usdc.balanceOf(maker) - makerBeforeFinalize, 90e6);
    }

    function test_SingleLegSpecialBetPaysWhenOutcomeHits() public {
        bytes32[] memory marketIds = _createMarkets(1);
        uint8[] memory outcomes = _singleOutcome(1);
        ParlayTypes.PayoutTier[] memory tiers = _allOrNothingTiers(1, 170e6);
        uint256 ticketId =
            _postAndFillOneUnit(marketIds, outcomes, tiers, ParlayTypes.InvalidPolicy.VoidInvalidLegs, 170e6);

        _resolveMarketFixture(marketIds[0], 1);

        uint256 takerBeforeClaim = usdc.balanceOf(taker);
        uint128 payoutPerUnit = IParlayFacet(address(diamond)).finalizeParlayTicketBucket(ticketId);
        assertEq(payoutPerUnit, 170e6);

        vm.prank(taker);
        uint256 payout = IParlayFacet(address(diamond)).claimParlayTicket(ticketId, 1, taker);
        assertEq(payout, 170e6);
        assertEq(usdc.balanceOf(taker) - takerBeforeClaim, 170e6);
    }

    function test_SingleLegSpecialBetLosesWhenOutcomeMisses() public {
        bytes32[] memory marketIds = _createMarkets(1);
        uint8[] memory outcomes = _singleOutcome(1);
        ParlayTypes.PayoutTier[] memory tiers = _allOrNothingTiers(1, 170e6);
        uint256 ticketId =
            _postAndFillOneUnit(marketIds, outcomes, tiers, ParlayTypes.InvalidPolicy.VoidInvalidLegs, 170e6);

        _resolveMarketFixture(marketIds[0], 2);

        uint256 makerBeforeFinalize = usdc.balanceOf(maker);
        uint128 payoutPerUnit = IParlayFacet(address(diamond)).finalizeParlayTicketBucket(ticketId);
        assertEq(payoutPerUnit, 0);
        assertEq(usdc.balanceOf(maker) - makerBeforeFinalize, 170e6);

        vm.prank(taker);
        uint256 payout = IParlayFacet(address(diamond)).claimParlayTicket(ticketId, 1, taker);
        assertEq(payout, 0);
        assertEq(IERC1155(address(ticketToken)).balanceOf(taker, ticketId), 0);
    }

    function test_SingleLegSpecialBetLosesWhenOutcomeInvalid() public {
        bytes32[] memory marketIds = _createMarkets(1);
        uint8[] memory outcomes = _singleOutcome(1);
        ParlayTypes.PayoutTier[] memory tiers = _allOrNothingTiers(1, 170e6);
        uint256 ticketId =
            _postAndFillOneUnit(marketIds, outcomes, tiers, ParlayTypes.InvalidPolicy.VoidInvalidLegs, 170e6);

        _resolveMarketFixture(marketIds[0], 3);

        uint256 makerBeforeFinalize = usdc.balanceOf(maker);
        uint128 payoutPerUnit = IParlayFacet(address(diamond)).finalizeParlayTicketBucket(ticketId);
        assertEq(payoutPerUnit, 0);
        assertEq(usdc.balanceOf(maker) - makerBeforeFinalize, 170e6);
    }

    function test_RevertWhen_QuoteHasNoLegs() public {
        ParlayTypes.ParlayLeg[] memory legs = new ParlayTypes.ParlayLeg[](0);

        vm.expectRevert(abi.encodeWithSelector(Errors.ParlayLegCountInvalid.selector, 0));
        IParlayFacet(address(diamond))
            .postParlayOffer(
                legs,
                _allOrNothingTiers(1, 100e6),
                ParlayTypes.InvalidPolicy.VoidInvalidLegs,
                "ipfs://terms",
                10e6,
                100e6,
                1,
                _deadline()
            );
    }

    function test_RevertWhen_QuoteLegsAreNotCanonical() public {
        bytes32[] memory marketIds = _createMarkets(2);
        ParlayTypes.ParlayLeg[] memory legs = new ParlayTypes.ParlayLeg[](2);
        legs[0] = ParlayTypes.ParlayLeg({marketId: marketIds[0], requiredOutcome: 1});
        legs[1] = ParlayTypes.ParlayLeg({marketId: marketIds[1], requiredOutcome: 1});
        if (uint256(legs[0].marketId) < uint256(legs[1].marketId)) {
            (legs[0], legs[1]) = (legs[1], legs[0]);
        }

        vm.expectRevert(
            abi.encodeWithSelector(Errors.ParlayNonCanonicalLegs.selector, legs[0].marketId, legs[1].marketId)
        );
        IParlayFacet(address(diamond))
            .postParlayOffer(
                legs,
                _allOrNothingTiers(2, 100e6),
                ParlayTypes.InvalidPolicy.VoidInvalidLegs,
                "ipfs://terms",
                10e6,
                100e6,
                1,
                _deadline()
            );
    }

    function test_ParimutuelMarketCanBeAParlayLeg() public {
        uint64 expiryTime = uint64(block.timestamp + 7 days);
        (bytes32 orderbookMarketId,) = _createMarketFixture("Will A resolve yes?", expiryTime);
        (bytes32 pariMarketId,,,) = _createParimutuelMarketFixture("Will B resolve no?", expiryTime);

        bytes32[] memory marketIds = new bytes32[](2);
        marketIds[0] = orderbookMarketId;
        marketIds[1] = pariMarketId;

        uint8[] memory outcomes = new uint8[](2);
        outcomes[0] = 1;
        outcomes[1] = 2;

        ParlayTypes.PayoutTier[] memory tiers = _allOrNothingTiers(2, 50e6);
        uint256 ticketId =
            _postAndFillOneUnit(marketIds, outcomes, tiers, ParlayTypes.InvalidPolicy.VoidInvalidLegs, 50e6);

        _resolveMarketFixture(orderbookMarketId, 1);
        _resolveParimutuelMarketFixture(pariMarketId, 2);

        assertEq(IParlayFacet(address(diamond)).finalizeParlayTicketBucket(ticketId), 50e6);
    }

    function test_CreateParlayTicketBookRegistersGenericErc1155Book() public {
        bytes32[] memory marketIds = _createMarkets(2);
        uint8[] memory outcomes = _yesYesOutcomes();
        ParlayTypes.PayoutTier[] memory tiers = _allOrNothingTiers(2, 100e6);
        uint256 ticketId =
            _postAndFillOneUnit(marketIds, outcomes, tiers, ParlayTypes.InvalidPolicy.VoidInvalidLegs, 100e6);

        bytes32 salt = keccak256("ticket book");
        bytes32 bookId = IParlayFacet(address(diamond)).createParlayTicketBook(ticketId, 2, salt);
        CurveCLOBTypes.BookInfo memory info = BookFacet(address(diamond)).getBookInfo(bookId);

        assertEq(info.bookId, bookId);
        assertEq(uint8(info.assetType), uint8(LibEveMarket.BookAssetType.ERC1155));
        assertEq(info.baseToken, address(ticketToken));
        assertEq(info.baseTokenId, ticketId);
        assertEq(info.quoteToken, address(usdc));
        assertEq(info.pricingMode, uint8(LibEveMarket.BookPricingMode.GENERIC));
    }

    function test_MulticallCanPostRequestAndEmitStrategy() public {
        bytes32[] memory marketIds = _createMarkets(2);
        uint8[] memory outcomes = _yesYesOutcomes();
        ParlayTypes.PayoutTier[] memory tiers = _allOrNothingTiers(2, 100e6);
        ParlayTypes.ParlayLeg[] memory legs = _buildSortedLegs(marketIds, outcomes);
        uint256 templateId = IParlayFacet(address(diamond))
            .computeParlayTemplateId(legs, tiers, ParlayTypes.InvalidPolicy.VoidInvalidLegs);
        bytes32[] memory directMarketIds = new bytes32[](1);
        directMarketIds[0] = marketIds[0];
        uint8[] memory directOutcomes = new uint8[](1);
        directOutcomes[0] = 1;
        uint256[] memory templateIds = new uint256[](1);
        templateIds[0] = templateId;

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(
            IParlayFacet.postParlayRequest,
            (
                legs,
                tiers,
                ParlayTypes.InvalidPolicy.VoidInvalidLegs,
                "ipfs://multicall-request",
                uint128(10e6),
                uint128(100e6),
                uint128(1),
                _deadline()
            )
        );
        calls[1] = abi.encodeCall(
            IParlayFacet.emitStrategyCreated,
            (keccak256("hedge strategy"), directMarketIds, directOutcomes, templateIds, "ipfs://strategy")
        );

        vm.startPrank(taker);
        usdc.approve(address(diamond), 13e6);
        bytes[] memory results = IParlayFacet(address(diamond)).multicall(calls);
        vm.stopPrank();

        assertEq(results.length, 2);
        assertEq(abi.decode(results[0], (uint256)), 1);
        ParlayTypes.ParlayRequestView memory request = IParlayFacet(address(diamond)).getParlayRequest(1);
        assertEq(request.requester, taker);
        assertEq(request.premiumEscrowRemaining, 10e6);
        assertEq(request.feeEscrowRemaining, 3e6);
    }

    function _postAndFillOneUnit(
        bytes32[] memory marketIds,
        uint8[] memory outcomes,
        ParlayTypes.PayoutTier[] memory tiers,
        ParlayTypes.InvalidPolicy invalidPolicy,
        uint128 maxPayoutPerUnit
    ) internal returns (uint256 ticketId) {
        ParlayTypes.ParlayLeg[] memory legs = _buildSortedLegs(marketIds, outcomes);

        vm.startPrank(maker);
        usdc.approve(address(diamond), maxPayoutPerUnit);
        uint256 offerId = IParlayFacet(address(diamond))
            .postParlayOffer(legs, tiers, invalidPolicy, "ipfs://terms", 10e6, maxPayoutPerUnit, 1, _deadline());
        vm.stopPrank();

        vm.startPrank(taker);
        usdc.approve(address(diamond), 13e6);
        ticketId = IParlayFacet(address(diamond)).fillParlayOffer(offerId, 1, taker);
        vm.stopPrank();
    }

    function _createMarkets(uint256 count) internal returns (bytes32[] memory marketIds) {
        marketIds = new bytes32[](count);
        uint64 expiryTime = uint64(block.timestamp + 7 days);
        for (uint256 index = 0; index < count; ++index) {
            (marketIds[index],) =
                _createMarketFixture(string.concat("Will leg ", vm.toString(index), " resolve?"), expiryTime);
        }
    }

    function _selectMarkets(bytes32[] memory marketIds, uint256 firstIndex, uint256 secondIndex)
        internal
        pure
        returns (bytes32[] memory selectedMarketIds)
    {
        selectedMarketIds = new bytes32[](2);
        selectedMarketIds[0] = marketIds[firstIndex];
        selectedMarketIds[1] = marketIds[secondIndex];
    }

    function _budgetOfferPost(
        ParlayTypes.ParlayLeg[] memory legs,
        ParlayTypes.PayoutTier[] memory tiers,
        string memory metadataHint,
        uint128 premiumPerUnit,
        uint128 maxPayoutPerUnit,
        uint128 units
    ) internal view returns (ParlayTypes.BudgetOfferPost memory post) {
        post = ParlayTypes.BudgetOfferPost({
            legs: legs,
            payoutTiers: tiers,
            invalidPolicy: ParlayTypes.InvalidPolicy.VoidInvalidLegs,
            metadataHint: metadataHint,
            premiumPerUnit: premiumPerUnit,
            maxPayoutPerUnit: maxPayoutPerUnit,
            units: units,
            fillDeadline: _deadline()
        });
    }

    function _budgetRequestPost(
        ParlayTypes.ParlayLeg[] memory legs,
        ParlayTypes.PayoutTier[] memory tiers,
        string memory metadataHint,
        uint128 premiumPerUnit,
        uint128 desiredMaxPayoutPerUnit,
        uint128 units
    ) internal view returns (ParlayTypes.BudgetRequestPost memory post) {
        post = ParlayTypes.BudgetRequestPost({
            legs: legs,
            payoutTiers: tiers,
            invalidPolicy: ParlayTypes.InvalidPolicy.VoidInvalidLegs,
            metadataHint: metadataHint,
            premiumPerUnit: premiumPerUnit,
            desiredMaxPayoutPerUnit: desiredMaxPayoutPerUnit,
            units: units,
            fillDeadline: _deadline()
        });
    }

    function _buildSortedLegs(bytes32[] memory marketIds, uint8[] memory outcomes)
        internal
        pure
        returns (ParlayTypes.ParlayLeg[] memory legs)
    {
        _sortLegInputs(marketIds, outcomes);
        legs = new ParlayTypes.ParlayLeg[](marketIds.length);
        for (uint256 index = 0; index < marketIds.length; ++index) {
            legs[index] = ParlayTypes.ParlayLeg({marketId: marketIds[index], requiredOutcome: outcomes[index]});
        }
    }

    function _sortLegInputs(bytes32[] memory marketIds, uint8[] memory outcomes) internal pure {
        for (uint256 i = 0; i < marketIds.length; ++i) {
            for (uint256 j = i + 1; j < marketIds.length; ++j) {
                if (uint256(marketIds[j]) < uint256(marketIds[i])) {
                    (marketIds[i], marketIds[j]) = (marketIds[j], marketIds[i]);
                    (outcomes[i], outcomes[j]) = (outcomes[j], outcomes[i]);
                }
            }
        }
    }

    function _yesYesOutcomes() internal pure returns (uint8[] memory outcomes) {
        outcomes = new uint8[](2);
        outcomes[0] = 1;
        outcomes[1] = 1;
    }

    function _singleOutcome(uint8 outcome) internal pure returns (uint8[] memory outcomes) {
        outcomes = new uint8[](1);
        outcomes[0] = outcome;
    }

    function _allOrNothingTiers(uint8 hits, uint128 payout)
        internal
        pure
        returns (ParlayTypes.PayoutTier[] memory tiers)
    {
        tiers = new ParlayTypes.PayoutTier[](1);
        tiers[0] = ParlayTypes.PayoutTier({minHits: hits, payout: payout});
    }

    function _deadline() internal view returns (uint64) {
        return uint64(block.timestamp + 1 days);
    }

    function _parlayAdminSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = ParlayAdminFacet.setParlayConfig.selector;
        selectors[1] = ParlayAdminFacet.getParlayConfig.selector;
        selectors[2] = ParlayAdminFacet.emitStrategyCreated.selector;
    }

    function _marginAssetSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = IMarginAccountFacet.setMarginAsset.selector;
    }

    function _seniorCapitalSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](9);
        selectors[0] = ISeniorCapitalFacet.depositSeniorCapital.selector;
        selectors[1] = ISeniorCapitalFacet.withdrawPendingSeniorCapital.selector;
        selectors[2] = ISeniorCapitalFacet.activateSeniorCapital.selector;
        selectors[3] = ISeniorCapitalFacet.requestSeniorCapitalExit.selector;
        selectors[4] = ISeniorCapitalFacet.cancelSeniorCapitalExit.selector;
        selectors[5] = ISeniorCapitalFacet.processSeniorCapitalExits.selector;
        selectors[6] = ISeniorCapitalFacet.claimSeniorCapitalFees.selector;
        selectors[7] = ISeniorCapitalFacet.donateSeniorCapitalFees.selector;
        selectors[8] = ISeniorCapitalFacet.claimSeniorCapitalExit.selector;
    }

    function _seniorCapitalViewSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](6);
        selectors[0] = ISeniorCapitalFacet.seniorCapitalState.selector;
        selectors[1] = ISeniorCapitalFacet.seniorCapitalAccount.selector;
        selectors[2] = ISeniorCapitalFacet.seniorCapitalExit.selector;
        selectors[3] = ISeniorCapitalFacet.seniorCapitalBucket.selector;
        selectors[4] = ISeniorCapitalFacet.pendingSeniorCapitalFees.selector;
        selectors[5] = ISeniorCapitalFacet.claimableSeniorCapitalExit.selector;
    }

    function _parlayUnderwritingSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](8);
        selectors[0] = ParlayUnderwritingFacet.postParlayOffer.selector;
        selectors[1] = ParlayUnderwritingFacet.fillParlayOffer.selector;
        selectors[2] = ParlayUnderwritingFacet.postParlayRequest.selector;
        selectors[3] = ParlayUnderwritingFacet.fillParlayRequest.selector;
        selectors[4] = ParlayUnderwritingFacet.cancelParlayOffer.selector;
        selectors[5] = ParlayUnderwritingFacet.cancelParlayRequest.selector;
        selectors[6] = ParlayUnderwritingFacet.postParlayOfferWithCollateralProfile.selector;
        selectors[7] = ParlayUnderwritingFacet.postParlayRequestWithCollateralProfile.selector;
    }

    function _parlayBudgetSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](13);
        selectors[0] = ParlayBudgetFacet.createParlayBudget.selector;
        selectors[1] = ParlayBudgetFacet.fundParlayBudget.selector;
        selectors[2] = ParlayBudgetFacet.cancelParlayBudget.selector;
        selectors[3] = ParlayBudgetFacet.getParlayBudget.selector;
        selectors[4] = ParlayBudgetFacet.postParlayOfferFromBudget.selector;
        selectors[5] = ParlayBudgetFacet.postParlayRequestFromBudget.selector;
        selectors[6] = ParlayBudgetFacet.postParlayOffersFromBudgetBatch.selector;
        selectors[7] = ParlayBudgetFacet.postParlayRequestsFromBudgetBatch.selector;
        selectors[8] = ParlayBudgetFacet.createParlayBudgetWithCollateralProfile.selector;
        selectors[9] = ParlayBudgetFacet.postParlayOfferFromBudgetWithCollateralProfile.selector;
        selectors[10] = ParlayBudgetFacet.postParlayRequestFromBudgetWithCollateralProfile.selector;
        selectors[11] = ParlayBudgetFacet.postParlayOffersFromBudgetBatchWithCollateralProfile.selector;
        selectors[12] = ParlayBudgetFacet.postParlayRequestsFromBudgetBatchWithCollateralProfile.selector;
    }

    function _parlaySettlementSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = ParlaySettlementFacet.finalizeParlayTicketBucket.selector;
        selectors[1] = ParlaySettlementFacet.claimParlayTicket.selector;
    }

    function _parlayBookSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = ParlayBookFacet.createParlayTicketBook.selector;
    }

    function _parlayViewSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](9);
        selectors[0] = ParlayViewFacet.computeParlayTemplateId.selector;
        selectors[1] = ParlayViewFacet.computeParlayTicketId.selector;
        selectors[2] = ParlayViewFacet.getParlayTemplate.selector;
        selectors[3] = ParlayViewFacet.getParlayTemplateLeg.selector;
        selectors[4] = ParlayViewFacet.getParlayTemplatePayoutTier.selector;
        selectors[5] = ParlayViewFacet.getParlayOffer.selector;
        selectors[6] = ParlayViewFacet.getParlayRequest.selector;
        selectors[7] = ParlayViewFacet.getParlayTicketBucket.selector;
        selectors[8] = ParlayViewFacet.parlayTicketURI.selector;
    }

    function _parlayMulticallSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = ParlayMulticallFacet.multicall.selector;
    }

    function _bookSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = BookFacet.getBookInfo.selector;
    }
}
