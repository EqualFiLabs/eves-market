// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISeniorCapitalFacet} from "../../src/interfaces/ISeniorCapitalFacet.sol";
import {IMLOProfitShareFacet} from "../../src/interfaces/IMLOProfitShareFacet.sol";
import {IMarginAccountFacet as IProductionMarginAccountFacet} from "../../src/interfaces/IMarginAccountFacet.sol";
import {MarginTypes} from "../../src/types/MarginTypes.sol";
import {MLOProfitShareTypes} from "../../src/types/MLOProfitShareTypes.sol";
import {CurveCLOBTypes} from "../../src/types/CurveCLOBTypes.sol";
import {ITradeRouter} from "../../src/interfaces/ITradeRouter.sol";
import {ITradeRouterBook} from "../../src/interfaces/ITradeRouterBook.sol";
import {CurveViewFacet} from "../../src/facets/CurveViewFacet.sol";
import {LibCLOBBook} from "../../src/libraries/LibCLOBBook.sol";
import {SeniorCapitalFacetTest} from "../unit/SeniorCapitalFacet.t.sol";
import {MLOProfitShareTest} from "../unit/MLOProfitShare.t.sol";
import {MLOPredictionAdapterTest} from "../unit/MLOPredictionAdapter.t.sol";
import {IMarginTestFacet as IMarginAccountFacet} from "../helpers/MarginAccountingHarnessFacet.sol";
import {ITestStateFacet} from "../helpers/TestBase.sol";

contract MLOSeniorRewardSecurityRegression is SeniorCapitalFacetTest {
    function test_RepeatActivationCannotClaimHistoricalFees() public {
        _deposit(alice, 100e18);
        _deposit(bob, 100e18);
        vm.warp(90_001);
        vm.prank(alice);
        senior.activateSeniorCapital();
        vm.prank(bob);
        senior.activateSeniorCapital();

        _deposit(alice, 100e18);
        vm.warp(180_001);
        _mintAndApprove(donor, 200e18);
        vm.prank(donor);
        senior.donateSeniorCapitalFees(200e18);

        vm.prank(alice);
        senior.activateSeniorCapital();

        assertEq(senior.pendingSeniorCapitalFees(alice), 100e18);
        assertEq(senior.pendingSeniorCapitalFees(bob), 100e18);
        assertEq(senior.seniorCapitalState().feeReserve, 200e18);

        vm.prank(alice);
        uint256 aliceClaim = senior.claimSeniorCapitalFees(alice);
        vm.prank(bob);
        uint256 bobClaim = senior.claimSeniorCapitalFees(bob);
        assertEq(aliceClaim + bobClaim, 200e18);
        assertEq(senior.seniorCapitalState().feeReserve, 0);
    }

    function test_FullExitCancellationCannotClaimQueuedFeesTwice() public {
        _deposit(alice, 100e18);
        _deposit(bob, 100e18);
        vm.warp(block.timestamp + 24 hours);
        vm.prank(alice);
        senior.activateSeniorCapital();
        vm.prank(bob);
        senior.activateSeniorCapital();

        vm.prank(alice);
        (uint256 exitId,,) = senior.requestSeniorCapitalExit(100e18, alice);
        _mintAndApprove(donor, 20e18);
        vm.prank(donor);
        senior.donateSeniorCapitalFees(20e18);
        vm.prank(alice);
        senior.cancelSeniorCapitalExit(exitId);

        assertEq(senior.pendingSeniorCapitalFees(alice), 10e18);
        assertEq(senior.pendingSeniorCapitalFees(bob), 10e18);
        assertEq(senior.seniorCapitalState().feeReserve, 20e18);

        vm.prank(alice);
        uint256 aliceClaim = senior.claimSeniorCapitalFees(alice);
        vm.prank(bob);
        uint256 bobClaim = senior.claimSeniorCapitalFees(bob);
        assertEq(aliceClaim + bobClaim, 20e18);
        assertEq(senior.seniorCapitalState().feeReserve, 0);
    }
}

contract MLOProfitShareSecurityRegression is MLOProfitShareTest {
    function test_MakerCannotRecaptureHistoricalShareWithOneAtomOfSeniorPrincipal() public {
        bytes32 bucketId = _depositAndAllocate(100e18, keccak256("maker-reward-capture"));
        _recordProfit(bucketId, 20e18);

        seniorDepositor = maker;
        _activateSenior(1);

        vm.prank(maker);
        IMarginAccountFacet(address(diamond)).releaseBucketMargin(bucketId, 115e18);
        assertEq(IMLOProfitShareFacet(address(diamond)).mloBucketProfitReward(bucketId, maker).accountClaimable, 0);

        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSelector(IMLOProfitShareFacet.NoMLOBucketProfitReward.selector, bucketId, maker));
        IMLOProfitShareFacet(address(diamond)).claimMLOBucketProfitReward(bucketId, maker);
        assertEq(insurance.totalProfitShare(), 5e18);

        MarginTypes.MarginAccount memory margin =
            IProductionMarginAccountFacet(address(diamond)).getMarginAccount(maker);
        assertEq(margin.freeMargin, 115e18);
    }

    function test_IndependentRecipientRoundingCannotStrandFinalProfitAtom() public {
        _activateSenior(100e18);
        bytes32 bucketId = _depositAndAllocate(100e18, keccak256("recipient-rounding"));
        for (uint256 index; index < 20; ++index) {
            _recordProfit(bucketId, 1);
        }

        vm.prank(maker);
        MLOProfitShareTypes.ProfitRelease memory finalRelease =
            IMarginAccountFacet(address(diamond)).releaseBucketMargin(bucketId, 100e18 + 15);

        MarginTypes.MarginBucket memory bucket =
            IProductionMarginAccountFacet(address(diamond)).getMarginBucket(bucketId);
        assertEq(finalRelease.grossAssets, 100e18 + 15);
        assertEq(finalRelease.seniorShare, 0);
        assertEq(finalRelease.insuranceShare, 0);
        assertEq(finalRelease.makerCredit, 100e18 + 15);
        assertEq(bucket.marginAllocated, 0);
        assertEq(
            IMLOProfitShareFacet(address(diamond)).mloBucketProfitReward(bucketId, seniorDepositor).accountClaimable, 4
        );
        assertEq(insurance.totalProfitShare(), 1);
    }
}

contract MLOSeniorRouterSecurityRegression is MLOPredictionAdapterTest {
    function test_RetainedSeniorFeePreservesBookBuyRouterBalanceRestoration() public {
        vm.prank(owner);
        ITestStateFacet(address(diamond)).setOrderbookFeeConfigFixture(100, 0, 0, 0, 10_000);
        (marketId,) = _createMarketFixture("Does an internal Senior fee preserve router balance?", marketExpiry);
        ITestStateFacet(address(diamond)).materializeMarketSideBookFixture(marketId, true);
        ITestStateFacet(address(diamond)).materializeMarketSideBookFixture(marketId, false);
        yesBookId = LibCLOBBook.marketBookId(marketId, true);
        noBookId = LibCLOBBook.marketBookId(marketId, false);
        _depositAndAllocate(maker, 100e18);

        uint256 curveId = _createMLOCurve(_createEnvelope());
        (uint32 generation, bytes32 commitment) = CurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        vm.startPrank(taker);
        collateral.approve(address(diamond), 25e18);
        CurveCLOBTypes.FillBestResult memory result = ITradeRouterBook(address(diamond))
            .buyBookWithCollateral(
                CurveCLOBTypes.FillBookParams({
                    bookId: yesBookId,
                    maxQuoteIn: 25e18,
                    minBaseOut: 1,
                    maxAveragePrice: PRICE_DENOMINATOR,
                    curveIds: _singleUint(curveId),
                    expectedGenerations: _singleUint32(generation),
                    expectedCommitments: _singleBytes32(commitment),
                    payer: address(0),
                    receiver: taker
                })
            );
        vm.stopPrank();

        assertGt(result.feePaid, 0);
        assertEq(ISeniorCapitalFacet(address(diamond)).seniorCapitalState().feeReserve, result.feePaid);
    }
}
