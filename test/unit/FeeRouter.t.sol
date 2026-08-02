// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {OwnershipFacet} from "../../src/facets/OwnershipFacet.sol";
import {FeeConfigFacet} from "../../src/facets/FeeConfigFacet.sol";
import {IFeeRouterFacet} from "../../src/interfaces/IFeeRouterFacet.sol";
import {IOBRResolutionFacet} from "../../src/interfaces/IOBRResolutionFacet.sol";
import {ISeniorCapitalFacet} from "../../src/interfaces/ISeniorCapitalFacet.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {Events} from "../../src/libraries/Events.sol";
import {LibCLOBBook} from "../../src/libraries/LibCLOBBook.sol";

import {SettlementFeeFixture, StateProbeFacet} from "../helpers/DiamondFixtures.sol";

contract FeeRouterTest is SettlementFeeFixture {
    function test_RevertWhen_FeeSplitDoesNotTotalDenominator() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidFeeSplit.selector, 9_999));
        FeeConfigFacet(address(diamond)).setOrderbookFeeSplit(0, 0, 9_999, 0, 0);
    }

    uint16 internal constant MAKER_REWARD_RATE_BPS = 1_500;

    function test_RevertWhen_RegularMarketFeesUseBookClaimRoute() public {
        (bytes32 marketId,,) =
            _createFilledMarketWithFee("book-double-claim", "fees", 7 days, 10_000e6, 500_000_000, 500, 4_200e6);
        bytes32 bookId = LibCLOBBook.marketBookId(marketId, true);

        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidAmount.selector, uint256(marketId)));
        IFeeRouterFacet(address(diamond)).claimBookMakerFees(bookId);
    }

    function test_ClaimMakerFeesPaysAccruedAmountAndPreventsDoubleClaim() public {
        (bytes32 marketId,, uint128 fee) =
            _createFilledMarketWithFee("maker-claim", "fees", 7 days, 10_000e6, 500_000_000, 500, 4_200e6);
        uint128 makerShare = _makerShare(fee);

        (uint128 accrued, uint128 claimed, uint128 claimable) =
            IFeeRouterFacet(address(diamond)).previewMakerFees(marketId, maker);
        assertEq(accrued, makerShare);
        assertEq(claimed, 0);
        assertEq(claimable, makerShare);

        uint256 makerBalanceBefore = collateralToken.balanceOf(maker);

        vm.expectEmit(true, true, false, true, address(diamond));
        emit Events.MakerFeesClaimed(marketId, maker, makerShare);

        vm.prank(maker);
        IFeeRouterFacet(address(diamond)).claimMakerFees(marketId);

        assertEq(collateralToken.balanceOf(maker), makerBalanceBefore + makerShare);

        (accrued, claimed, claimable) = IFeeRouterFacet(address(diamond)).previewMakerFees(marketId, maker);
        assertEq(accrued, makerShare);
        assertEq(claimed, makerShare);
        assertEq(claimable, 0);

        vm.expectEmit(true, true, false, true, address(diamond));
        emit Events.MakerFeesClaimed(marketId, maker, 0);

        vm.prank(maker);
        IFeeRouterFacet(address(diamond)).claimMakerFees(marketId);

        assertEq(collateralToken.balanceOf(maker), makerBalanceBefore + makerShare);
    }

    function test_MarketMakerRewardsAccrueOnFillAndClaimImmediately() public {
        (bytes32 marketId,,) = _createTradingMarket("maker-rewards", "fees", 7 days);

        vm.prank(creator);
        IFeeRouterFacet(address(diamond)).configureMarketMakerRewards(marketId, MAKER_REWARD_RATE_BPS);

        uint128 fundedAmount = 2_000e6;
        collateralToken.mint(outsider, fundedAmount);
        vm.startPrank(outsider);
        collateralToken.approve(address(diamond), fundedAmount);

        vm.expectEmit(true, true, true, true, address(diamond));
        emit Events.MarketMakerRewardsFunded(marketId, outsider, address(collateralToken), fundedAmount, fundedAmount);
        IFeeRouterFacet(address(diamond)).fundMarketMakerRewards(marketId, fundedAmount);
        vm.stopPrank();

        _splitFrom(maker, marketId, 10_000e6);
        _approvePositions(maker);
        uint256 curveId = _postCurveFromMaker(marketId, true, 10_000e6, 500_000_000, 500_000_000, 180, 0);
        (, uint128 fee,) = _fillCurveFromTaker(curveId, 4_000e6);
        assertEq(fee, 0);

        uint128 expectedReward = 600e6;
        (address rewardToken, uint16 rewardRateBps, uint128 rewardsRemaining, uint128 claimable) =
            IFeeRouterFacet(address(diamond)).previewMarketMakerRewards(marketId, maker);
        assertEq(rewardToken, address(collateralToken));
        assertEq(rewardRateBps, MAKER_REWARD_RATE_BPS);
        assertEq(rewardsRemaining, fundedAmount - expectedReward);
        assertEq(claimable, expectedReward);

        (uint128 quoteVolume,,) = StateProbeFacet(address(diamond)).getStoredMakerAccounting(marketId, maker);
        assertEq(quoteVolume, 4_000e6);

        uint256 makerBalanceBefore = collateralToken.balanceOf(maker);

        vm.expectEmit(true, true, true, true, address(diamond));
        emit Events.MarketMakerRewardsClaimed(marketId, maker, address(collateralToken), expectedReward);

        vm.prank(maker);
        IFeeRouterFacet(address(diamond)).claimMarketMakerRewards(marketId);

        assertEq(collateralToken.balanceOf(maker), makerBalanceBefore + expectedReward);

        (,,, claimable) = IFeeRouterFacet(address(diamond)).previewMarketMakerRewards(marketId, maker);
        assertEq(claimable, 0);
    }

    function test_MarketMakerRewardsCapAtRemainingPool() public {
        (bytes32 marketId,,) = _createTradingMarket("maker-rewards-cap", "fees", 7 days);

        vm.prank(creator);
        IFeeRouterFacet(address(diamond)).configureMarketMakerRewards(marketId, 5_000);

        uint128 fundedAmount = 100e6;
        collateralToken.mint(outsider, fundedAmount);
        vm.startPrank(outsider);
        collateralToken.approve(address(diamond), fundedAmount);
        IFeeRouterFacet(address(diamond)).fundMarketMakerRewards(marketId, fundedAmount);
        vm.stopPrank();

        _splitFrom(maker, marketId, 10_000e6);
        _approvePositions(maker);
        uint256 curveId = _postCurveFromMaker(marketId, true, 10_000e6, 500_000_000, 500_000_000, 180, 0);
        _fillCurveFromTaker(curveId, 4_000e6);

        (,, uint128 rewardsRemaining, uint128 claimable) =
            IFeeRouterFacet(address(diamond)).previewMarketMakerRewards(marketId, maker);
        assertEq(rewardsRemaining, 0);
        assertEq(claimable, fundedAmount);
    }

    function test_RevertWhen_MarketMakerRewardConfigurationInvalidOrUnauthorized() public {
        (bytes32 marketId,,) = _createTradingMarket("maker-reward-config", "fees", 7 days);

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotMarketCreator.selector, outsider, creator));
        IFeeRouterFacet(address(diamond)).configureMarketMakerRewards(marketId, MAKER_REWARD_RATE_BPS);

        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidAmount.selector, 0));
        IFeeRouterFacet(address(diamond)).configureMarketMakerRewards(marketId, 0);

        vm.prank(owner);
        IFeeRouterFacet(address(diamond)).configureMarketMakerRewards(marketId, MAKER_REWARD_RATE_BPS);

        uint128 fundedAmount = 25e6;
        collateralToken.mint(outsider, fundedAmount);
        vm.startPrank(outsider);
        collateralToken.approve(address(diamond), fundedAmount);
        IFeeRouterFacet(address(diamond)).fundMarketMakerRewards(marketId, fundedAmount);
        vm.stopPrank();

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidAmount.selector, fundedAmount));
        IFeeRouterFacet(address(diamond)).configureMarketMakerRewards(marketId, 2_000);
    }

    function test_RevertWhen_FundingMarketMakerRewardsBeforeConfiguration() public {
        (bytes32 marketId,,) = _createTradingMarket("maker-reward-unconfigured", "fees", 7 days);

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidAmount.selector, 0));
        IFeeRouterFacet(address(diamond)).fundMarketMakerRewards(marketId, 100e6);
    }

    function test_ClaimCreatorFeesPaysEligibleCreatorAndPreventsDoubleClaim() public {
        (bytes32 marketId, uint64 expiryTime, uint128 fee) =
            _createFilledMarketWithFee("creator-claim", "fees", 7 days, 10_000e6, 500_000_000, 500, 4_200e6);
        uint128 creatorShare = _creatorShare(fee);

        _finalizeCreatorResolution(marketId, expiryTime, 1);

        uint256 creatorBalanceBefore = collateralToken.balanceOf(creator);

        vm.expectEmit(true, false, false, true, address(diamond));
        emit Events.CreatorFeesClaimed(marketId, creatorShare);

        vm.prank(creator);
        IFeeRouterFacet(address(diamond)).claimCreatorFees(marketId);

        (uint128 creatorFeesEscrowed,, bool creatorFeesClaimed, bool creatorFeeEligible) =
            StateProbeFacet(address(diamond)).getStoredMarketFees(marketId);

        assertEq(collateralToken.balanceOf(creator), creatorBalanceBefore + creatorShare);
        assertEq(creatorFeesEscrowed, 0);
        assertTrue(creatorFeesClaimed);
        assertTrue(creatorFeeEligible);

        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(Errors.AlreadyClaimed.selector, marketId, creator));
        IFeeRouterFacet(address(diamond)).claimCreatorFees(marketId);
    }

    function test_RevertWhen_CreatorClaimsAfterBeingOverturned() public {
        (bytes32 marketId, uint64 expiryTime,) =
            _createFilledMarketWithFee("creator-overturned", "fees", 7 days, 10_000e6, 500_000_000, 500, 4_200e6);

        _finalizeChallengedResolution(marketId, expiryTime, 1, 2);

        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(Errors.CreatorNotEligible.selector, marketId));
        IFeeRouterFacet(address(diamond)).claimCreatorFees(marketId);
    }

    function test_WhenPermissionlessCreationDisabled_CreatorShareRoutesToTreasury() public {
        creator = owner;

        vm.prank(owner);
        OwnershipFacet(address(diamond)).setPermissionlessCreationEnabled(false);

        uint256 treasuryUsdcBefore = collateralToken.balanceOf(treasury);
        (bytes32 marketId, uint64 expiryTime, uint128 fee) =
            _createFilledMarketWithFee("creator-disabled", "fees", 7 days, 10_000e6, 500_000_000, 500, 4_200e6);
        uint128 makerShare = _makerShare(fee);
        uint128 treasuryShare = fee - makerShare;

        (uint128 creatorFeesEscrowed, uint128 protocolFeesAccrued,, bool creatorFeeEligible) =
            StateProbeFacet(address(diamond)).getStoredMarketFees(marketId);

        assertEq(creatorFeesEscrowed, 0);
        assertEq(protocolFeesAccrued, treasuryShare);
        assertFalse(creatorFeeEligible);
        assertEq(collateralToken.balanceOf(treasury), treasuryUsdcBefore + treasuryShare);

        _finalizeCreatorResolution(marketId, expiryTime, 1);

        (creatorFeesEscrowed, protocolFeesAccrued,, creatorFeeEligible) =
            StateProbeFacet(address(diamond)).getStoredMarketFees(marketId);

        assertEq(creatorFeesEscrowed, 0);
        assertEq(protocolFeesAccrued, treasuryShare);
        assertFalse(creatorFeeEligible);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Errors.CreatorNotEligible.selector, marketId));
        IFeeRouterFacet(address(diamond)).claimCreatorFees(marketId);
    }

    function test_FeeSplitMathUsesStaticEntryBps() public {
        uint128 midFee = _assertFeeSplitExample("mid-price", 500_000_000);
        uint128 lowFee = _assertFeeSplitExample("low-price", 100_000_000);
        uint128 highFee = _assertFeeSplitExample("high-price", 900_000_000);

        assertEq(midFee, 200e6);
        assertEq(lowFee, 200e6);
        assertApproxEqAbs(highFee, 200e6, 1);
    }

    function test_CLOBMarketUsesCreationFeeSnapshotAfterAdminChange() public {
        (bytes32 marketId,,) = _createTradingMarket("snapshot-fees", "fees", 7 days);

        _splitFrom(maker, marketId, 100_000e6);
        _approvePositions(maker);
        uint256 curveId = _postCurveFromMaker(marketId, true, 100_000e6, 500_000_000, 500_000_000, 180, 0);

        vm.prank(owner);
        FeeConfigFacet(address(diamond)).setOrderbookFeeSplit(0, 10_000, 0, 0, 0);

        (, uint128 fee,) = _fillCurveFromTaker(curveId, 4_200e6);
        uint128 makerShare = _makerShare(fee);
        uint128 creatorShare = _creatorShare(fee);
        uint128 protocolShare = fee - makerShare - creatorShare;

        (uint128 storedCreatorFees, uint128 storedProtocolFees,,) =
            StateProbeFacet(address(diamond)).getStoredMarketFees(marketId);
        (, uint128 storedMakerFees,) = StateProbeFacet(address(diamond)).getStoredMakerAccounting(marketId, maker);

        assertEq(storedMakerFees, makerShare);
        assertEq(storedCreatorFees, creatorShare);
        assertEq(storedProtocolFees, protocolShare);
    }

    function test_FortyPercentOrderbookFeeRoutesToSeniorPool() public {
        address depositor = makeAddr("seniorPool-fee-depositor");

        collateralToken.mint(depositor, 1_000e6);
        vm.startPrank(depositor);
        collateralToken.approve(address(diamond), 1_000e6);
        ISeniorCapitalFacet(address(diamond)).depositSeniorCapital(1_000e6);
        vm.warp(block.timestamp + 15 minutes);
        ISeniorCapitalFacet(address(diamond)).activateSeniorCapital();
        vm.stopPrank();

        vm.prank(owner);
        FeeConfigFacet(address(diamond)).setOrderbookFeeSplit(0, 0, 6_000, 4_000, 0);

        uint256 seniorAssetsBefore = ISeniorCapitalFacet(address(diamond)).seniorCapitalState().totalPrincipal;
        (bytes32 marketId,, uint128 fee) =
            _createFilledMarketWithFee("senior-route", "fees", 7 days, 10_000e6, 500_000_000, 500, 4_200e6);

        (uint128 storedCreatorFees, uint128 storedProtocolFees,,) =
            StateProbeFacet(address(diamond)).getStoredMarketFees(marketId);
        (, uint128 storedMakerFees,) = StateProbeFacet(address(diamond)).getStoredMakerAccounting(marketId, maker);

        assertEq(storedMakerFees, 0);
        assertEq(storedCreatorFees, 0);
        assertEq(storedProtocolFees, (uint256(fee) * 6_000) / 10_000);
        ISeniorCapitalFacet.SeniorCapitalState memory senior =
            ISeniorCapitalFacet(address(diamond)).seniorCapitalState();
        assertEq(senior.totalPrincipal, seniorAssetsBefore);
        uint256 expectedSeniorFee = (uint256(fee) * 4_000) / 10_000;
        assertEq(senior.feeReserve, expectedSeniorFee);
        assertEq(ISeniorCapitalFacet(address(diamond)).pendingSeniorCapitalFees(depositor), expectedSeniorFee);
    }

    function test_FinalizeResolutionRoutesForfeitureToChallengerAndTreasury() public {
        (bytes32 marketId, uint64 expiryTime, uint128 fee) =
            _createFilledMarketWithFee("forfeit-challenge", "fees", 7 days, 10_000e6, 500_000_000, 500, 4_200e6);
        uint128 creatorShare = _creatorShare(fee);
        uint128 challengerReward = creatorShare / 10;
        uint256 challengerUsdcBefore = collateralToken.balanceOf(challengerOne);
        uint256 treasuryUsdcBefore = collateralToken.balanceOf(treasury);

        _expireMarket(marketId, expiryTime);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(marketId, 1);

        vm.prank(challengerOne);
        IOBRResolutionFacet(address(diamond)).disputeResolution(marketId, 2);

        (,,,,,, uint64 disputeDeadline,) = StateProbeFacet(address(diamond)).getStoredResolution(marketId);

        vm.expectEmit(true, false, false, true, address(diamond));
        emit Events.CreatorFeesForfeited(marketId, creatorShare);

        vm.warp(disputeDeadline);
        IOBRResolutionFacet(address(diamond)).finalizeResolution(marketId);

        assertEq(collateralToken.balanceOf(challengerOne), challengerUsdcBefore + challengerReward);
        assertEq(collateralToken.balanceOf(treasury), treasuryUsdcBefore + creatorShare - challengerReward);
    }

    function test_FinalizeResolutionRoutesCreatorForfeitureToTreasuryOnAbsence() public {
        (bytes32 marketId, uint64 expiryTime, uint128 fee) =
            _createFilledMarketWithFee("forfeit-absence", "fees", 7 days, 10_000e6, 500_000_000, 500, 4_200e6);
        uint128 creatorShare = _creatorShare(fee);
        uint256 treasuryUsdcBefore = collateralToken.balanceOf(treasury);

        _expireMarket(marketId, expiryTime);

        vm.expectEmit(true, false, false, true, address(diamond));
        emit Events.CreatorFeesForfeited(marketId, creatorShare);

        vm.warp(expiryTime + 48 hours);
        IOBRResolutionFacet(address(diamond)).finalizeResolution(marketId);

        assertEq(collateralToken.balanceOf(treasury), treasuryUsdcBefore + creatorShare);
    }

    function _assertFeeSplitExample(string memory question, uint72 price) internal returns (uint128 fee) {
        uint256 treasuryUsdcBefore = collateralToken.balanceOf(treasury);
        uint128 creationFee = StateProbeFacet(address(diamond)).marketCreationFee();
        (bytes32 marketId,, uint128 quoteFee) =
            _createFilledMarketWithFee(question, "fees", 7 days, 100_000e6, price, 500, 4_200e6);
        uint128 makerShare = _makerShare(quoteFee);
        uint128 creatorShare = _creatorShare(quoteFee);
        uint128 protocolShare = quoteFee - makerShare - creatorShare;
        (uint128 storedCreatorFees, uint128 storedProtocolFees,,) =
            StateProbeFacet(address(diamond)).getStoredMarketFees(marketId);
        (, uint128 storedMakerFees,) = StateProbeFacet(address(diamond)).getStoredMakerAccounting(marketId, maker);

        assertEq(storedMakerFees, makerShare);
        assertEq(storedCreatorFees, creatorShare);
        assertEq(storedProtocolFees, protocolShare);
        assertEq(collateralToken.balanceOf(treasury), treasuryUsdcBefore + creationFee + protocolShare);

        fee = quoteFee;
    }

    function _makerShare(uint128 fee) internal pure returns (uint128) {
        return uint128((uint256(fee) * 8_500) / 10_000);
    }

    function _creatorShare(uint128 fee) internal pure returns (uint128) {
        return uint128((uint256(fee) * 500) / 10_000);
    }
}
