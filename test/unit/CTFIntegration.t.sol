// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {OwnershipFacet} from "../../src/facets/OwnershipFacet.sol";
import {FeeConfigFacet} from "../../src/facets/FeeConfigFacet.sol";
import {IBookAdminFacet} from "../../src/interfaces/IBookAdminFacet.sol";
import {IBookOrderFacet} from "../../src/interfaces/IBookOrderFacet.sol";
import {IBookTradeFacet} from "../../src/interfaces/IBookTradeFacet.sol";
import {IBookViewFacet} from "../../src/interfaces/IBookViewFacet.sol";
import {ICurveInventoryFacet} from "../../src/interfaces/ICurveInventoryFacet.sol";
import {ICurveLifecycleFacet} from "../../src/interfaces/ICurveLifecycleFacet.sol";
import {ICurveTradeFacet} from "../../src/interfaces/ICurveTradeFacet.sol";
import {ICurveViewFacet} from "../../src/interfaces/ICurveViewFacet.sol";
import {CurveCLOBTypes} from "../../src/types/CurveCLOBTypes.sol";
import {IMarketFactoryFacet} from "../../src/interfaces/IMarketFactoryFacet.sol";
import {IMarketSettlementFacet} from "../../src/interfaces/IMarketSettlementFacet.sol";
import {LibCTF} from "../../src/libraries/LibCTF.sol";

import {SettlementFeeFixture} from "../helpers/DiamondFixtures.sol";

contract LibCTFProbe {
    function derivePositionIds(address conditionalTokens, address collateralToken, bytes32 conditionId)
        external
        view
        returns (uint256 yesPositionId, uint256 noPositionId)
    {
        return LibCTF.derivePositionIds(conditionalTokens, collateralToken, conditionId);
    }
}

contract CTFIntegrationTest is SettlementFeeFixture {
    LibCTFProbe internal ctfProbe;

    function setUp() public override {
        super.setUp();
        ctfProbe = new LibCTFProbe();
    }

    function test_EndToEndLifecycleReportsPayoutsAndRedeemsWinningShares() public {
        vm.prank(owner);
        FeeConfigFacet(address(diamond)).setOrderbookEntryFeeBps(0);

        (bytes32 marketId, ExpectedMarketData memory expected, uint64 expiryTime) =
            _createTradingMarket("ctf-e2e", "integration", 7 days);

        _splitFrom(maker, marketId, 5_000);
        _assertPreparedCondition(expected.conditionId, expected.resolutionId);
        _approvePositions(maker);

        uint256 curveId = _postCurveFromMaker(marketId, true, 5_000, 500_000_000, 500_000_000, 240, 0);
        uint256 takerCollateralBefore = collateralToken.balanceOf(taker);
        (uint128 sharesOut,,) = _fillCurveFromTaker(curveId, 500);

        assertEq(conditionalTokens.balanceOf(taker, expected.yesPositionId), sharesOut);
        assertEq(conditionalTokens.balanceOf(taker, expected.noPositionId), 0);
        assertEq(takerCollateralBefore - collateralToken.balanceOf(taker), 500);

        _finalizeCreatorResolution(marketId, expiryTime, 1);
        _assertReportedPayout(expected.conditionId, 1, 0, 1);

        assertEq(_redeemCTFPositionsDirect(marketId, taker), uint256(sharesOut));
        assertEq(conditionalTokens.balanceOf(taker, expected.yesPositionId), 0);
        assertEq(conditionalTokens.balanceOf(taker, expected.noPositionId), 0);
    }

    function test_CrossMarketIsolationKeepsConditionIdsAndPositionsDistinct() public {
        vm.prank(owner);
        FeeConfigFacet(address(diamond)).setOrderbookEntryFeeBps(0);

        (bytes32 marketIdA, ExpectedMarketData memory expectedA, uint64 expiryTimeA) =
            _createTradingMarket("isolation-a", "integration", 7 days);
        (bytes32 marketIdB, ExpectedMarketData memory expectedB, uint64 expiryTimeB) =
            _createTradingMarket("isolation-b", "integration", 8 days);

        assertTrue(expectedA.conditionId != expectedB.conditionId);
        assertTrue(expectedA.yesPositionId != expectedB.yesPositionId);
        assertTrue(expectedA.noPositionId != expectedB.noPositionId);

        _splitFrom(maker, marketIdA, 2_000);
        _approvePositions(maker);

        uint256 curveIdA = _postCurveFromMaker(marketIdA, true, 2_000, 500_000_000, 500_000_000, 180, 0);
        (uint128 sharesOutA,,) = _fillCurveFromTaker(curveIdA, 500);

        _finalizeCreatorResolution(marketIdB, expiryTimeB, 1);

        assertEq(_redeemCTFPositionsDirect(marketIdB, taker), 0);
        assertEq(conditionalTokens.balanceOf(taker, expectedA.yesPositionId), sharesOutA);

        _finalizeCreatorResolution(marketIdA, expiryTimeA, 1);

        assertEq(_redeemCTFPositionsDirect(marketIdA, taker), uint256(sharesOutA));
        assertEq(conditionalTokens.balanceOf(taker, expectedA.yesPositionId), 0);
    }

    function test_DirectRedemptionDoesNotBurnDiamondEscrowedCurveInventory() public {
        vm.prank(owner);
        FeeConfigFacet(address(diamond)).setOrderbookEntryFeeBps(0);

        (bytes32 marketId, ExpectedMarketData memory expected, uint64 expiryTime) =
            _createTradingMarket("ctf-direct-escrow-safe", "integration", 7 days);

        _splitFrom(maker, marketId, 5_000);
        _approvePositions(maker);

        uint256 curveId = _postCurveFromMaker(marketId, true, 5_000, 500_000_000, 500_000_000, 240, 0);
        (uint128 sharesOut,,) = _fillCurveFromTaker(curveId, 500);
        uint256 escrowedYesBefore = conditionalTokens.balanceOf(address(diamond), expected.yesPositionId);

        _finalizeCreatorResolution(marketId, expiryTime, 1);

        assertEq(_redeemCTFPositionsDirect(marketId, taker), uint256(sharesOut));
        assertEq(conditionalTokens.balanceOf(address(diamond), expected.yesPositionId), escrowedYesBefore);

        vm.prank(maker);
        ICurveLifecycleFacet(address(diamond)).cancelCurve(curveId);

        assertEq(conditionalTokens.balanceOf(address(diamond), expected.yesPositionId), 0);
        assertEq(conditionalTokens.balanceOf(maker, expected.yesPositionId), escrowedYesBefore);
    }

    function test_PositionIdsMatchLibCtfHelperOutputs() public {
        (bytes32 marketId, ExpectedMarketData memory expected,) =
            _createTradingMarket("ctf-derive", "integration", 7 days);
        (bytes32 conditionId, address collateralTokenAddress, uint256 yesPositionId, uint256 noPositionId) =
            IMarketFactoryFacet(address(diamond)).getMarketPositions(marketId);
        (uint256 derivedYesPositionId, uint256 derivedNoPositionId) =
            ctfProbe.derivePositionIds(address(conditionalTokens), collateralTokenAddress, conditionId);

        assertEq(conditionId, expected.conditionId);
        assertEq(yesPositionId, expected.yesPositionId);
        assertEq(noPositionId, expected.noPositionId);
        assertEq(derivedYesPositionId, yesPositionId);
        assertEq(derivedNoPositionId, noPositionId);
    }

    function test_DiamondAcceptsSafeTransferForCtfPositions() public {
        (bytes32 marketId, ExpectedMarketData memory expected,) =
            _createTradingMarket("ctf-receiver", "integration", 7 days);

        _splitFrom(maker, marketId, 1_000);

        vm.prank(maker);
        conditionalTokens.safeTransferFrom(maker, address(diamond), expected.yesPositionId, 250, "");

        assertEq(conditionalTokens.balanceOf(address(diamond), expected.yesPositionId), 250);
        assertEq(conditionalTokens.balanceOf(maker, expected.yesPositionId), 750);
    }

    function _assertPreparedCondition(bytes32 conditionId, bytes32 expectedQuestionId) internal view {
        (address oracle, bytes32 storedQuestionId,, bool prepared, bool reported,) =
            conditionalTokens.getConditionDetails(conditionId);

        assertEq(oracle, address(diamond));
        assertEq(storedQuestionId, expectedQuestionId);
        assertTrue(prepared);
        assertFalse(reported);
    }

    function _assertReportedPayout(
        bytes32 conditionId,
        uint256 expectedYes,
        uint256 expectedNo,
        uint256 expectedDenominator
    ) internal view {
        (,,,, bool reported, uint256 payoutDenominator) = conditionalTokens.getConditionDetails(conditionId);
        uint256[] memory payouts = conditionalTokens.getPayoutNumerators(conditionId);

        assertTrue(reported);
        assertEq(payoutDenominator, expectedDenominator);
        assertEq(payouts.length, 2);
        assertEq(payouts[0], expectedYes);
        assertEq(payouts[1], expectedNo);
    }

    function _redeemCTFPositionsDirect(bytes32 marketId, address redeemer) internal returns (uint256 collateralOut) {
        uint256 collateralBefore = collateralToken.balanceOf(redeemer);
        (address collateralTokenAddress, bytes32 conditionId, uint256[] memory indexSets) =
            IMarketSettlementFacet(address(diamond)).getCTFRedemptionParams(marketId);

        vm.prank(redeemer);
        conditionalTokens.redeemPositions(IERC20(collateralTokenAddress), bytes32(0), conditionId, indexSets);

        collateralOut = collateralToken.balanceOf(redeemer) - collateralBefore;
    }
}
