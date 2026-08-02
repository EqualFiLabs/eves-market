// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC1155} from "../../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";

import {OwnershipFacet} from "../../src/facets/OwnershipFacet.sol";
import {ParlayAdminFacet} from "../../src/facets/parlay/ParlayAdminFacet.sol";
import {ParlayBudgetFacet} from "../../src/facets/parlay/ParlayBudgetFacet.sol";
import {ParlaySettlementFacet} from "../../src/facets/parlay/ParlaySettlementFacet.sol";
import {ParlayUnderwritingFacet} from "../../src/facets/parlay/ParlayUnderwritingFacet.sol";
import {ParlayViewFacet} from "../../src/facets/parlay/ParlayViewFacet.sol";
import {ComboMarketFacet} from "../../src/facets/native/ComboMarketFacet.sol";
import {MultiOutcomeOrderbookFacet} from "../../src/facets/MultiOutcomeOrderbookFacet.sol";
import {MultiOutcomeOrderbookViewFacet} from "../../src/facets/MultiOutcomeOrderbookViewFacet.sol";
import {IComboMarketFacet} from "../../src/interfaces/IComboMarketFacet.sol";
import {IMarketFactoryFacet} from "../../src/interfaces/IMarketFactoryFacet.sol";
import {IMultiOutcomeOrderbookFacet} from "../../src/interfaces/IMultiOutcomeOrderbookFacet.sol";
import {IParlayFacet} from "../../src/interfaces/IParlayFacet.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {LibMultiOutcome} from "../../src/libraries/LibMultiOutcome.sol";
import {ParlayTypes} from "../../src/types/ParlayTypes.sol";
import {EvesPositionManager} from "../../src/tokens/EvesPositionManager.sol";
import {ParlayTicketToken} from "../../src/tokens/ParlayTicketToken.sol";

import {SettlementFeeFixture} from "../helpers/DiamondFixtures.sol";
import {MockEveToken as ProfileCollateral} from "../helpers/MockEveToken.sol";
import {MarketFactoryTypes} from "../../src/types/MarketFactoryTypes.sol";

contract ParlayCollateralTest is SettlementFeeFixture {
    uint8 internal constant ALT_PROFILE_ID = 1;
    uint128 internal constant ALT_PROFILE_PAYOUT_UNIT = 0.0005 ether;
    uint128 internal constant ALT_PROFILE_FLAT_FEE = 0.0002 ether;
    uint128 internal constant PREMIUM_PER_UNIT = 0.0001 ether;
    uint128 internal constant MAX_PAYOUT_PER_UNIT = 0.001 ether;

    address internal feeRecipient;
    ProfileCollateral internal profileCollateral;
    EvesPositionManager internal outcomePositions;
    ParlayTicketToken internal ticketToken;

    function setUp() public override {
        super.setUp();

        feeRecipient = makeAddr("parlay-profile-fee-recipient");
        profileCollateral = new ProfileCollateral();
        outcomePositions = new EvesPositionManager(address(diamond), "");
        ticketToken = new ParlayTicketToken(address(diamond), "uri://parlay-profile/{id}");

        _addFacet(address(ownershipFacet), _evesPositionManagerSelector());
        _addFacet(address(new MultiOutcomeOrderbookFacet()), _multiOutcomeSelectors());
        _addFacet(address(new MultiOutcomeOrderbookViewFacet()), _multiOutcomeViewSelectors());
        _addFacet(address(new ComboMarketFacet()), _comboMarketSelectors());
        _addFacet(address(new ParlayAdminFacet()), _parlayAdminSelectors());
        _addFacet(address(new ParlayBudgetFacet()), _parlayBudgetSelectors());
        _addFacet(address(new ParlayUnderwritingFacet()), _parlayUnderwritingSelectors());
        _addFacet(address(new ParlaySettlementFacet()), _parlaySettlementSelectors());
        _addFacet(address(new ParlayViewFacet()), _parlayViewSelectors());

        vm.startPrank(owner);
        OwnershipFacet(address(diamond)).setEvesPositionManager(address(outcomePositions));
        OwnershipFacet(address(diamond))
            .setCollateralProfile(
                ALT_PROFILE_ID, address(profileCollateral), address(0), ALT_PROFILE_PAYOUT_UNIT, 0, true
            );
        OwnershipFacet(address(diamond)).setCollateralProfileParlayUnderwritingFee(ALT_PROFILE_ID, ALT_PROFILE_FLAT_FEE);
        IParlayFacet(address(diamond)).setParlayConfig(address(ticketToken), feeRecipient, 3e6, 0, 10_000);
        vm.stopPrank();
    }

    function test_ProfileCollateralOfferEscrowsFillsAndClaimsProfileCollateral() public {
        (bytes32 firstMarketId, uint64 firstExpiry) =
            _createProfileCollateralMarket("Will profileCollateral parlay leg one win?");
        (bytes32 secondMarketId, uint64 secondExpiry) =
            _createProfileCollateralMarket("Will profileCollateral parlay leg two win?");
        ParlayTypes.ParlayLeg[] memory legs = _buildSortedLegs(firstMarketId, secondMarketId);
        ParlayTypes.PayoutTier[] memory tiers = _allOrNothingTiers(2, MAX_PAYOUT_PER_UNIT);

        _fundProfileCollateral(maker, MAX_PAYOUT_PER_UNIT);
        _fundProfileCollateral(taker, PREMIUM_PER_UNIT + ALT_PROFILE_FLAT_FEE);

        vm.prank(maker);
        uint256 offerId = IParlayFacet(address(diamond))
            .postParlayOfferWithCollateralProfile(
                ALT_PROFILE_ID, _quoteOfferPost(legs, tiers, "ipfs://profile-collateral-offer", 1)
            );

        ParlayTypes.ParlayOfferView memory offer = IParlayFacet(address(diamond)).getParlayOffer(offerId);
        assertEq(offer.collateralProfileId, ALT_PROFILE_ID);
        assertEq(offer.collateralToken, address(profileCollateral));
        assertEq(offer.payoutUnit, ALT_PROFILE_PAYOUT_UNIT);
        assertEq(offer.underwritingFeePerUnit, ALT_PROFILE_FLAT_FEE);
        assertEq(offer.escrowRemaining, MAX_PAYOUT_PER_UNIT);

        uint256 makerBalanceBeforeFill = profileCollateral.balanceOf(maker);
        vm.prank(taker);
        uint256 ticketId = IParlayFacet(address(diamond)).fillParlayOffer(offerId, 1, taker);

        assertEq(profileCollateral.balanceOf(maker), makerBalanceBeforeFill + PREMIUM_PER_UNIT);
        assertEq(profileCollateral.balanceOf(feeRecipient), ALT_PROFILE_FLAT_FEE);
        assertEq(IERC1155(address(ticketToken)).balanceOf(taker, ticketId), 1);

        ParlayTypes.ParlayTicketBucketView memory bucket =
            IParlayFacet(address(diamond)).getParlayTicketBucket(ticketId);
        assertEq(bucket.collateralProfileId, ALT_PROFILE_ID);
        assertEq(bucket.collateralToken, address(profileCollateral));
        assertEq(bucket.payoutUnit, ALT_PROFILE_PAYOUT_UNIT);
        assertEq(bucket.escrowRemaining, MAX_PAYOUT_PER_UNIT);

        _finalizeCreatorResolution(firstMarketId, firstExpiry, uint8(LibEveMarket.MarketOutcome.Yes));
        _finalizeCreatorResolution(secondMarketId, secondExpiry, uint8(LibEveMarket.MarketOutcome.Yes));

        uint256 takerBalanceBeforeClaim = profileCollateral.balanceOf(taker);
        assertEq(IParlayFacet(address(diamond)).finalizeParlayTicketBucket(ticketId), MAX_PAYOUT_PER_UNIT);

        vm.prank(taker);
        uint256 payout = IParlayFacet(address(diamond)).claimParlayTicket(ticketId, 1, taker);

        assertEq(payout, MAX_PAYOUT_PER_UNIT);
        assertEq(profileCollateral.balanceOf(taker), takerBalanceBeforeClaim + MAX_PAYOUT_PER_UNIT);
    }

    function test_ProfileCollateralOfferCancelRefundsProfileCollateral() public {
        (bytes32 firstMarketId,) = _createProfileCollateralMarket("Will profileCollateral cancel leg one win?");
        (bytes32 secondMarketId,) = _createProfileCollateralMarket("Will profileCollateral cancel leg two win?");

        _fundProfileCollateral(maker, MAX_PAYOUT_PER_UNIT * 2);

        vm.prank(maker);
        uint256 offerId = IParlayFacet(address(diamond))
            .postParlayOfferWithCollateralProfile(
                ALT_PROFILE_ID,
                _quoteOfferPost(
                    _buildSortedLegs(firstMarketId, secondMarketId),
                    _allOrNothingTiers(2, MAX_PAYOUT_PER_UNIT),
                    "ipfs://profile-collateral-cancel",
                    2
                )
            );

        uint256 makerBalanceBeforeCancel = profileCollateral.balanceOf(maker);
        vm.prank(maker);
        uint256 refunded = IParlayFacet(address(diamond)).cancelParlayOffer(offerId);

        assertEq(refunded, MAX_PAYOUT_PER_UNIT * 2);
        assertEq(profileCollateral.balanceOf(maker), makerBalanceBeforeCancel + refunded);
    }

    function test_ProfileCollateralRequestCancelRefundsPremiumAndProfileFee() public {
        (bytes32 firstMarketId,) = _createProfileCollateralMarket("Will profileCollateral request leg one win?");
        (bytes32 secondMarketId,) = _createProfileCollateralMarket("Will profileCollateral request leg two win?");

        _fundProfileCollateral(taker, (PREMIUM_PER_UNIT + ALT_PROFILE_FLAT_FEE) * 2);

        vm.prank(taker);
        uint256 requestId = IParlayFacet(address(diamond))
            .postParlayRequestWithCollateralProfile(
                ALT_PROFILE_ID,
                _quoteRequestPost(
                    _buildSortedLegs(firstMarketId, secondMarketId),
                    _allOrNothingTiers(2, MAX_PAYOUT_PER_UNIT),
                    "ipfs://profile-collateral-request",
                    2
                )
            );

        ParlayTypes.ParlayRequestView memory request = IParlayFacet(address(diamond)).getParlayRequest(requestId);
        assertEq(request.collateralProfileId, ALT_PROFILE_ID);
        assertEq(request.collateralToken, address(profileCollateral));
        assertEq(request.payoutUnit, ALT_PROFILE_PAYOUT_UNIT);
        assertEq(request.underwritingFeePerUnit, ALT_PROFILE_FLAT_FEE);

        uint256 takerBalanceBeforeCancel = profileCollateral.balanceOf(taker);
        vm.prank(taker);
        (uint256 premiumReturned, uint256 feeReturned) = IParlayFacet(address(diamond)).cancelParlayRequest(requestId);

        assertEq(premiumReturned, PREMIUM_PER_UNIT * 2);
        assertEq(feeReturned, ALT_PROFILE_FLAT_FEE * 2);
        assertEq(profileCollateral.balanceOf(taker), takerBalanceBeforeCancel + premiumReturned + feeReturned);
    }

    function test_RevertWhen_ProfileParlayPostingUsesDisabledCollateral() public {
        (bytes32 firstMarketId,) = _createProfileCollateralMarket("Will disabled profile leg one win?");
        (bytes32 secondMarketId,) = _createProfileCollateralMarket("Will disabled profile leg two win?");

        vm.prank(owner);
        OwnershipFacet(address(diamond)).setCollateralProfileEnabled(ALT_PROFILE_ID, false);

        _fundProfileCollateral(maker, MAX_PAYOUT_PER_UNIT);
        uint256 makerBalanceBefore = profileCollateral.balanceOf(maker);

        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSelector(Errors.CollateralProfileDisabled.selector, ALT_PROFILE_ID));
        IParlayFacet(address(diamond))
            .postParlayOfferWithCollateralProfile(
                ALT_PROFILE_ID,
                _quoteOfferPost(
                    _buildSortedLegs(firstMarketId, secondMarketId),
                    _allOrNothingTiers(2, MAX_PAYOUT_PER_UNIT),
                    "ipfs://disabled",
                    1
                )
            );

        assertEq(profileCollateral.balanceOf(maker), makerBalanceBefore);
    }

    function test_ProfileParlayAcceptsMixedCollateralLegs() public {
        (bytes32 defaultMarketId,, uint64 defaultExpiry) =
            _createTradingMarket("Will mixed parlay collateral leg win?", "parlay", 7 days);
        (bytes32 profileCollateralMarketId, uint64 profileCollateralExpiry) =
            _createProfileCollateralMarket("Will mixed parlay profileCollateral leg win?");
        ParlayTypes.ParlayLeg[] memory legs = _buildSortedLegs(defaultMarketId, profileCollateralMarketId);

        _fundProfileCollateral(maker, MAX_PAYOUT_PER_UNIT);
        _fundProfileCollateral(taker, PREMIUM_PER_UNIT + ALT_PROFILE_FLAT_FEE);

        vm.prank(maker);
        uint256 offerId = IParlayFacet(address(diamond))
            .postParlayOfferWithCollateralProfile(
                ALT_PROFILE_ID,
                _quoteOfferPost(legs, _allOrNothingTiers(2, MAX_PAYOUT_PER_UNIT), "ipfs://mixed-collateral", 1)
            );

        vm.prank(taker);
        uint256 ticketId = IParlayFacet(address(diamond)).fillParlayOffer(offerId, 1, taker);

        _finalizeCreatorResolution(defaultMarketId, defaultExpiry, uint8(LibEveMarket.MarketOutcome.Yes));
        _finalizeCreatorResolution(
            profileCollateralMarketId, profileCollateralExpiry, uint8(LibEveMarket.MarketOutcome.Yes)
        );
        assertEq(IParlayFacet(address(diamond)).finalizeParlayTicketBucket(ticketId), MAX_PAYOUT_PER_UNIT);
    }

    function test_ProfileCollateralMakerBudgetConsumesAndRefundsProfileCollateral() public {
        (bytes32 firstMarketId, uint64 firstExpiry) =
            _createProfileCollateralMarket("Will profileCollateral budget leg one win?");
        (bytes32 secondMarketId, uint64 secondExpiry) =
            _createProfileCollateralMarket("Will profileCollateral budget leg two win?");
        ParlayTypes.ParlayLeg[] memory legs = _buildSortedLegs(firstMarketId, secondMarketId);

        _fundProfileCollateral(maker, MAX_PAYOUT_PER_UNIT * 3);
        _fundProfileCollateral(taker, (PREMIUM_PER_UNIT + ALT_PROFILE_FLAT_FEE) * 2);

        vm.startPrank(maker);
        uint256 budgetId = IParlayFacet(address(diamond))
            .createParlayBudgetWithCollateralProfile(
                ALT_PROFILE_ID, ParlayTypes.BudgetMode.MakerPayout, MAX_PAYOUT_PER_UNIT * 2
            );
        IParlayFacet(address(diamond)).fundParlayBudget(budgetId, MAX_PAYOUT_PER_UNIT);
        uint256 offerId = IParlayFacet(address(diamond))
            .postParlayOfferFromBudgetWithCollateralProfile(
                budgetId,
                ALT_PROFILE_ID,
                _budgetOfferPost(
                    legs, _allOrNothingTiers(2, MAX_PAYOUT_PER_UNIT), "ipfs://profile-collateral-maker-budget", 2
                )
            );
        vm.stopPrank();

        ParlayTypes.SharedBudgetView memory budget = IParlayFacet(address(diamond)).getParlayBudget(budgetId);
        assertEq(budget.collateralProfileId, ALT_PROFILE_ID);
        assertEq(budget.collateralToken, address(profileCollateral));
        assertEq(budget.payoutUnit, ALT_PROFILE_PAYOUT_UNIT);
        assertEq(budget.deposited, MAX_PAYOUT_PER_UNIT * 3);
        assertEq(budget.available, MAX_PAYOUT_PER_UNIT * 3);

        ParlayTypes.ParlayOfferView memory offer = IParlayFacet(address(diamond)).getParlayOffer(offerId);
        assertEq(offer.budgetId, budgetId);
        assertEq(offer.collateralProfileId, ALT_PROFILE_ID);
        assertEq(offer.collateralToken, address(profileCollateral));
        assertEq(offer.escrowRemaining, 0);

        vm.prank(taker);
        uint256 ticketId = IParlayFacet(address(diamond)).fillParlayOffer(offerId, 2, taker);

        budget = IParlayFacet(address(diamond)).getParlayBudget(budgetId);
        assertEq(budget.consumed, MAX_PAYOUT_PER_UNIT * 2);
        assertEq(budget.available, MAX_PAYOUT_PER_UNIT);
        assertEq(profileCollateral.balanceOf(feeRecipient), ALT_PROFILE_FLAT_FEE * 2);

        uint256 makerBeforeCancel = profileCollateral.balanceOf(maker);
        vm.prank(maker);
        assertEq(IParlayFacet(address(diamond)).cancelParlayBudget(budgetId), MAX_PAYOUT_PER_UNIT);
        assertEq(profileCollateral.balanceOf(maker), makerBeforeCancel + MAX_PAYOUT_PER_UNIT);

        _finalizeCreatorResolution(firstMarketId, firstExpiry, uint8(LibEveMarket.MarketOutcome.Yes));
        _finalizeCreatorResolution(secondMarketId, secondExpiry, uint8(LibEveMarket.MarketOutcome.Yes));
        assertEq(IParlayFacet(address(diamond)).finalizeParlayTicketBucket(ticketId), MAX_PAYOUT_PER_UNIT);

        uint256 takerBeforeClaim = profileCollateral.balanceOf(taker);
        vm.prank(taker);
        assertEq(IParlayFacet(address(diamond)).claimParlayTicket(ticketId, 2, taker), MAX_PAYOUT_PER_UNIT * 2);
        assertEq(profileCollateral.balanceOf(taker), takerBeforeClaim + MAX_PAYOUT_PER_UNIT * 2);
    }

    function test_ProfileCollateralTakerBudgetConsumesPremiumAndFeeCollateral() public {
        (bytes32 firstMarketId, uint64 firstExpiry) =
            _createProfileCollateralMarket("Will profileCollateral taker budget leg one win?");
        (bytes32 secondMarketId, uint64 secondExpiry) =
            _createProfileCollateralMarket("Will profileCollateral taker budget leg two win?");
        ParlayTypes.ParlayLeg[] memory legs = _buildSortedLegs(firstMarketId, secondMarketId);
        uint256 unitSpend = uint256(PREMIUM_PER_UNIT) + ALT_PROFILE_FLAT_FEE;

        _fundProfileCollateral(taker, unitSpend * 3);
        _fundProfileCollateral(maker, MAX_PAYOUT_PER_UNIT * 2);

        vm.startPrank(taker);
        uint256 budgetId = IParlayFacet(address(diamond))
            .createParlayBudgetWithCollateralProfile(ALT_PROFILE_ID, ParlayTypes.BudgetMode.TakerSpend, unitSpend * 3);
        uint256 requestId = IParlayFacet(address(diamond))
            .postParlayRequestFromBudgetWithCollateralProfile(
                budgetId,
                ALT_PROFILE_ID,
                _budgetRequestPost(
                    legs, _allOrNothingTiers(2, MAX_PAYOUT_PER_UNIT), "ipfs://profile-collateral-taker-budget", 3
                )
            );
        vm.stopPrank();

        ParlayTypes.ParlayRequestView memory request = IParlayFacet(address(diamond)).getParlayRequest(requestId);
        assertEq(request.budgetId, budgetId);
        assertEq(request.collateralProfileId, ALT_PROFILE_ID);
        assertEq(request.collateralToken, address(profileCollateral));
        assertEq(request.premiumEscrowRemaining, 0);
        assertEq(request.feeEscrowRemaining, 0);

        uint256 makerBeforeFill = profileCollateral.balanceOf(maker);
        vm.prank(maker);
        uint256 ticketId = IParlayFacet(address(diamond)).fillParlayRequest(requestId, 2, taker);

        assertEq(profileCollateral.balanceOf(maker), makerBeforeFill - MAX_PAYOUT_PER_UNIT * 2 + PREMIUM_PER_UNIT * 2);
        assertEq(profileCollateral.balanceOf(feeRecipient), ALT_PROFILE_FLAT_FEE * 2);

        ParlayTypes.SharedBudgetView memory budget = IParlayFacet(address(diamond)).getParlayBudget(budgetId);
        assertEq(budget.consumed, unitSpend * 2);
        assertEq(budget.available, unitSpend);

        uint256 takerBeforeCancel = profileCollateral.balanceOf(taker);
        vm.prank(taker);
        assertEq(IParlayFacet(address(diamond)).cancelParlayBudget(budgetId), unitSpend);
        assertEq(profileCollateral.balanceOf(taker), takerBeforeCancel + unitSpend);

        _finalizeCreatorResolution(firstMarketId, firstExpiry, uint8(LibEveMarket.MarketOutcome.Yes));
        _finalizeCreatorResolution(secondMarketId, secondExpiry, uint8(LibEveMarket.MarketOutcome.Yes));
        assertEq(IParlayFacet(address(diamond)).finalizeParlayTicketBucket(ticketId), MAX_PAYOUT_PER_UNIT);
    }

    function test_RevertWhen_BudgetQuoteProfileDiffers() public {
        (bytes32 firstMarketId,) = _createProfileCollateralMarket("Will profile mismatch leg one win?");
        (bytes32 secondMarketId,) = _createProfileCollateralMarket("Will profile mismatch leg two win?");
        ParlayTypes.ParlayLeg[] memory legs = _buildSortedLegs(firstMarketId, secondMarketId);

        vm.startPrank(maker);
        collateralToken.approve(address(diamond), 100e6);
        uint256 defaultBudgetId =
            IParlayFacet(address(diamond)).createParlayBudget(ParlayTypes.BudgetMode.MakerPayout, 100e6);

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.ParlayBudgetCollateralProfileMismatch.selector, defaultBudgetId, uint8(0), ALT_PROFILE_ID
            )
        );
        IParlayFacet(address(diamond))
            .postParlayOfferFromBudgetWithCollateralProfile(
                defaultBudgetId,
                ALT_PROFILE_ID,
                _budgetOfferPost(legs, _allOrNothingTiers(2, MAX_PAYOUT_PER_UNIT), "ipfs://profile-mismatch", 1)
            );
        vm.stopPrank();

        _fundProfileCollateral(maker, MAX_PAYOUT_PER_UNIT);

        vm.startPrank(maker);
        uint256 profileBudgetId = IParlayFacet(address(diamond))
            .createParlayBudgetWithCollateralProfile(
                ALT_PROFILE_ID, ParlayTypes.BudgetMode.MakerPayout, MAX_PAYOUT_PER_UNIT
            );
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.ParlayBudgetCollateralProfileMismatch.selector, profileBudgetId, ALT_PROFILE_ID, uint8(0)
            )
        );
        IParlayFacet(address(diamond))
            .postParlayOfferFromBudget(
                profileBudgetId,
                _budgetOfferPost(legs, _allOrNothingTiers(2, MAX_PAYOUT_PER_UNIT), "ipfs://default-mismatch", 1)
            );
        vm.stopPrank();
    }

    function test_RevertWhen_BudgetCreationUsesDisabledProfileCollateral() public {
        vm.prank(owner);
        OwnershipFacet(address(diamond)).setCollateralProfileEnabled(ALT_PROFILE_ID, false);

        _fundProfileCollateral(maker, MAX_PAYOUT_PER_UNIT);
        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSelector(Errors.CollateralProfileDisabled.selector, ALT_PROFILE_ID));
        IParlayFacet(address(diamond))
            .createParlayBudgetWithCollateralProfile(
                ALT_PROFILE_ID, ParlayTypes.BudgetMode.MakerPayout, MAX_PAYOUT_PER_UNIT
            );
    }

    function test_MultiOutcomeParlayLegPaysOnExactOutcome() public {
        (bytes32 marketId, uint64 expiryTime) = _createDefaultMultiOutcomeMarket("Will exact outcome B win?");
        uint256 ticketId = _postAndFillDefaultParlay(_singleLeg(marketId, 1), _allOrNothingTiers(1, 100e6));

        _finalizeCreatorResolution(marketId, expiryTime, 1);
        assertEq(IParlayFacet(address(diamond)).finalizeParlayTicketBucket(ticketId), 100e6);

        uint256 takerBalanceBefore = collateralToken.balanceOf(taker);
        vm.prank(taker);
        assertEq(IParlayFacet(address(diamond)).claimParlayTicket(ticketId, 1, taker), 100e6);
        assertEq(collateralToken.balanceOf(taker), takerBalanceBefore + 100e6);
    }

    function test_MultiOutcomeParlayLegMissesOnDifferentConcreteOutcome() public {
        (bytes32 marketId, uint64 expiryTime) = _createDefaultMultiOutcomeMarket("Will exact outcome miss?");
        uint256 ticketId = _postAndFillDefaultParlay(_singleLeg(marketId, 1), _allOrNothingTiers(1, 100e6));

        _finalizeCreatorResolution(marketId, expiryTime, 2);
        uint256 makerBalanceBeforeFinalize = collateralToken.balanceOf(maker);

        assertEq(IParlayFacet(address(diamond)).finalizeParlayTicketBucket(ticketId), 0);
        assertEq(collateralToken.balanceOf(maker), makerBalanceBeforeFinalize + 100e6);
    }

    function test_MultiOutcomeParlayLegAppliesInvalidCountsAsMissPolicy() public {
        (bytes32 marketId, uint64 expiryTime) = _createDefaultMultiOutcomeMarket("Will exact outcome invalidate?");
        uint256 ticketId = _postAndFillDefaultParlay(
            _singleLeg(marketId, 1), _allOrNothingTiers(1, 100e6), ParlayTypes.InvalidPolicy.InvalidCountsAsMiss
        );

        _finalizeCreatorResolution(marketId, expiryTime, LibMultiOutcome.OUTCOME_INVALID);
        assertEq(IParlayFacet(address(diamond)).finalizeParlayTicketBucket(ticketId), 0);
    }

    function test_RevertWhen_MultiOutcomeTargetIsOutOfBounds() public {
        (bytes32 marketId,) = _createDefaultMultiOutcomeMarket("Will out of bounds target fail?");

        vm.expectRevert(abi.encodeWithSelector(Errors.ParlayUnsupportedOutcome.selector, uint8(3)));
        IParlayFacet(address(diamond))
            .postParlayOffer(
                _singleLeg(marketId, 3),
                _allOrNothingTiers(1, 100e6),
                ParlayTypes.InvalidPolicy.VoidInvalidLegs,
                "ipfs://bad-target",
                10e6,
                100e6,
                1,
                _deadline()
            );
    }

    function test_RevertWhen_ParlayLegUsesComboMarket() public {
        (bytes32 firstMarketId,,) = _createTradingMarket("Will combo parlay leg one win?", "parlay", 7 days);
        (bytes32 secondMarketId,,) = _createTradingMarket("Will combo parlay leg two win?", "parlay", 8 days);

        vm.prank(creator);
        IComboMarketFacet.ComboMarketPreparation memory preparation = IComboMarketFacet(address(diamond))
            .createComboMarket(_marketPair(firstMarketId, secondMarketId), _yesLegs());

        vm.expectRevert(
            abi.encodeWithSelector(Errors.ParlayUnsupportedMarketType.selector, preparation.marketId, type(uint8).max)
        );
        IParlayFacet(address(diamond))
            .postParlayOffer(
                _singleLeg(preparation.marketId, 1),
                _allOrNothingTiers(1, 100e6),
                ParlayTypes.InvalidPolicy.VoidInvalidLegs,
                "ipfs://combo-leg",
                10e6,
                100e6,
                1,
                _deadline()
            );
    }

    function _createProfileCollateralMarket(string memory question)
        internal
        returns (bytes32 marketId, uint64 expiryTime)
    {
        uint64 tradingStartTime = uint64(block.timestamp);
        expiryTime = tradingStartTime + 7 days;

        vm.prank(creator);
        eveToken.approve(address(diamond), type(uint256).max);

        vm.prank(creator);
        marketId = IMarketFactoryFacet(address(diamond))
            .createMarketWithCollateralProfile(
                ALT_PROFILE_ID, question, "parlay", DEFAULT_RESOLUTION_SOURCE, tradingStartTime, expiryTime, 0, true
            );
    }

    function _createDefaultMultiOutcomeMarket(string memory question)
        internal
        returns (bytes32 marketId, uint64 expiryTime)
    {
        expiryTime = uint64(block.timestamp + 7 days);

        vm.prank(creator);
        collateralToken.approve(address(diamond), type(uint256).max);

        vm.prank(creator);
        eveToken.approve(address(diamond), type(uint256).max);

        vm.prank(creator);
        marketId = IMultiOutcomeOrderbookFacet(address(diamond))
            .createMultiOutcomeMarket(
                IMultiOutcomeOrderbookFacet.CreateMultiOutcomeMarketParams({
                    question: question,
                    category: "parlay",
                    resolutionSource: DEFAULT_RESOLUTION_SOURCE,
                    tradingStartTime: uint64(block.timestamp),
                    expiryTime: expiryTime,
                    outcomes: _outcomes(),
                    display: _emptyMultiOutcomeDisplay(),
                    externalRef: _emptyMultiOutcomeExternalRef(),
                    outcomeDisplay: new IMultiOutcomeOrderbookFacet.OutcomeDisplayInput[](0)
                })
            );
    }

    function _emptyMultiOutcomeDisplay() internal pure returns (MarketFactoryTypes.MarketDisplayInput memory display) {}

    function _emptyMultiOutcomeExternalRef()
        internal
        pure
        returns (MarketFactoryTypes.ExternalMarketRefInput memory externalRef)
    {}

    function _buildSortedLegs(bytes32 firstMarketId, bytes32 secondMarketId)
        internal
        pure
        returns (ParlayTypes.ParlayLeg[] memory legs)
    {
        legs = new ParlayTypes.ParlayLeg[](2);
        if (uint256(firstMarketId) < uint256(secondMarketId)) {
            legs[0] = ParlayTypes.ParlayLeg({marketId: firstMarketId, requiredOutcome: 1});
            legs[1] = ParlayTypes.ParlayLeg({marketId: secondMarketId, requiredOutcome: 1});
        } else {
            legs[0] = ParlayTypes.ParlayLeg({marketId: secondMarketId, requiredOutcome: 1});
            legs[1] = ParlayTypes.ParlayLeg({marketId: firstMarketId, requiredOutcome: 1});
        }
    }

    function _allOrNothingTiers(uint8 hits, uint128 payout)
        internal
        pure
        returns (ParlayTypes.PayoutTier[] memory tiers)
    {
        tiers = new ParlayTypes.PayoutTier[](1);
        tiers[0] = ParlayTypes.PayoutTier({minHits: hits, payout: payout});
    }

    function _postAndFillDefaultParlay(ParlayTypes.ParlayLeg[] memory legs, ParlayTypes.PayoutTier[] memory tiers)
        internal
        returns (uint256 ticketId)
    {
        ticketId = _postAndFillDefaultParlay(legs, tiers, ParlayTypes.InvalidPolicy.VoidInvalidLegs);
    }

    function _postAndFillDefaultParlay(
        ParlayTypes.ParlayLeg[] memory legs,
        ParlayTypes.PayoutTier[] memory tiers,
        ParlayTypes.InvalidPolicy invalidPolicy
    ) internal returns (uint256 ticketId) {
        vm.startPrank(maker);
        collateralToken.approve(address(diamond), 100e6);
        uint256 offerId = IParlayFacet(address(diamond))
            .postParlayOffer(legs, tiers, invalidPolicy, "ipfs://multi-outcome", 10e6, 100e6, 1, _deadline());
        vm.stopPrank();

        vm.startPrank(taker);
        collateralToken.approve(address(diamond), 13e6);
        ticketId = IParlayFacet(address(diamond)).fillParlayOffer(offerId, 1, taker);
        vm.stopPrank();
    }

    function _budgetOfferPost(
        ParlayTypes.ParlayLeg[] memory legs,
        ParlayTypes.PayoutTier[] memory tiers,
        string memory metadataHint,
        uint128 units
    ) internal view returns (ParlayTypes.BudgetOfferPost memory post) {
        post = ParlayTypes.BudgetOfferPost({
            legs: legs,
            payoutTiers: tiers,
            invalidPolicy: ParlayTypes.InvalidPolicy.VoidInvalidLegs,
            metadataHint: metadataHint,
            premiumPerUnit: PREMIUM_PER_UNIT,
            maxPayoutPerUnit: MAX_PAYOUT_PER_UNIT,
            units: units,
            fillDeadline: _deadline()
        });
    }

    function _budgetRequestPost(
        ParlayTypes.ParlayLeg[] memory legs,
        ParlayTypes.PayoutTier[] memory tiers,
        string memory metadataHint,
        uint128 units
    ) internal view returns (ParlayTypes.BudgetRequestPost memory post) {
        post = ParlayTypes.BudgetRequestPost({
            legs: legs,
            payoutTiers: tiers,
            invalidPolicy: ParlayTypes.InvalidPolicy.VoidInvalidLegs,
            metadataHint: metadataHint,
            premiumPerUnit: PREMIUM_PER_UNIT,
            desiredMaxPayoutPerUnit: MAX_PAYOUT_PER_UNIT,
            units: units,
            fillDeadline: _deadline()
        });
    }

    function _singleLeg(bytes32 marketId, uint8 outcome) internal pure returns (ParlayTypes.ParlayLeg[] memory legs) {
        legs = new ParlayTypes.ParlayLeg[](1);
        legs[0] = ParlayTypes.ParlayLeg({marketId: marketId, requiredOutcome: outcome});
    }

    function _marketPair(bytes32 first, bytes32 second) internal pure returns (bytes32[] memory marketIds) {
        marketIds = new bytes32[](2);
        marketIds[0] = first;
        marketIds[1] = second;
    }

    function _yesLegs() internal pure returns (bool[] memory yesLegs) {
        yesLegs = new bool[](2);
        yesLegs[0] = true;
        yesLegs[1] = true;
    }

    function _outcomes() internal pure returns (string[] memory outcomes) {
        outcomes = new string[](3);
        outcomes[0] = "A";
        outcomes[1] = "B";
        outcomes[2] = "C";
    }

    function _quoteOfferPost(
        ParlayTypes.ParlayLeg[] memory legs,
        ParlayTypes.PayoutTier[] memory tiers,
        string memory metadataHint,
        uint128 units
    ) internal view returns (ParlayTypes.QuoteOfferPost memory post) {
        post = ParlayTypes.QuoteOfferPost({
            legs: legs,
            payoutTiers: tiers,
            invalidPolicy: ParlayTypes.InvalidPolicy.VoidInvalidLegs,
            metadataHint: metadataHint,
            premiumPerUnit: PREMIUM_PER_UNIT,
            maxPayoutPerUnit: MAX_PAYOUT_PER_UNIT,
            units: units,
            fillDeadline: _deadline()
        });
    }

    function _quoteRequestPost(
        ParlayTypes.ParlayLeg[] memory legs,
        ParlayTypes.PayoutTier[] memory tiers,
        string memory metadataHint,
        uint128 units
    ) internal view returns (ParlayTypes.QuoteRequestPost memory post) {
        post = ParlayTypes.QuoteRequestPost({
            legs: legs,
            payoutTiers: tiers,
            invalidPolicy: ParlayTypes.InvalidPolicy.VoidInvalidLegs,
            metadataHint: metadataHint,
            premiumPerUnit: PREMIUM_PER_UNIT,
            desiredMaxPayoutPerUnit: MAX_PAYOUT_PER_UNIT,
            units: units,
            fillDeadline: _deadline()
        });
    }

    function _fundProfileCollateral(address account, uint256 amount) internal {
        profileCollateral.mint(account, amount);
        vm.prank(account);
        profileCollateral.approve(address(diamond), type(uint256).max);
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

    function _evesPositionManagerSelector() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = OwnershipFacet.setEvesPositionManager.selector;
    }

    function _multiOutcomeSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](5);
        selectors[0] = IMultiOutcomeOrderbookFacet.createMultiOutcomeMarket.selector;
        selectors[1] = IMultiOutcomeOrderbookFacet.createMultiOutcomeMarketWithCollateralProfile.selector;
        selectors[2] = IMultiOutcomeOrderbookFacet.splitOutcomeSet.selector;
        selectors[3] = IMultiOutcomeOrderbookFacet.mergeOutcomeSet.selector;
        selectors[4] = IMultiOutcomeOrderbookFacet.redeemOutcome.selector;
    }

    function _multiOutcomeViewSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](5);
        selectors[0] = IMultiOutcomeOrderbookFacet.getMultiOutcomeMarket.selector;
        selectors[1] = IMultiOutcomeOrderbookFacet.getMultiOutcomeOutcomes.selector;
        selectors[2] = IMultiOutcomeOrderbookFacet.getOutcomePositionId.selector;
        selectors[3] = IMultiOutcomeOrderbookFacet.getMultiOutcomeBooks.selector;
        selectors[4] = IMultiOutcomeOrderbookFacet.getMultiOutcomeDisplay.selector;
    }

    function _comboMarketSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = IComboMarketFacet.createComboMarket.selector;
        selectors[1] = IComboMarketFacet.computeComboBookId.selector;
        selectors[2] = IComboMarketFacet.getComboMarket.selector;
        selectors[3] = IComboMarketFacet.getComboBook.selector;
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

    function _parlaySettlementSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = ParlaySettlementFacet.finalizeParlayTicketBucket.selector;
        selectors[1] = ParlaySettlementFacet.claimParlayTicket.selector;
    }

    function _parlayViewSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](8);
        selectors[0] = ParlayViewFacet.computeParlayTemplateId.selector;
        selectors[1] = ParlayViewFacet.computeParlayTicketId.selector;
        selectors[2] = ParlayViewFacet.getParlayTemplate.selector;
        selectors[3] = ParlayViewFacet.getParlayTemplateLeg.selector;
        selectors[4] = ParlayViewFacet.getParlayTemplatePayoutTier.selector;
        selectors[5] = ParlayViewFacet.getParlayOffer.selector;
        selectors[6] = ParlayViewFacet.getParlayRequest.selector;
        selectors[7] = ParlayViewFacet.getParlayTicketBucket.selector;
    }
}
