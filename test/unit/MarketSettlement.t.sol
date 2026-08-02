// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IMarketSettlementFacet} from "../../src/interfaces/IMarketSettlementFacet.sol";
import {IOBRResolutionFacet} from "../../src/interfaces/IOBRResolutionFacet.sol";
import {OwnershipFacet} from "../../src/facets/OwnershipFacet.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {Events} from "../../src/libraries/Events.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";

import {ResolutionHarnessFacet, SettlementFeeFixture, StateProbeFacet} from "../helpers/DiamondFixtures.sol";
import {MockConditionalTokens} from "../helpers/MockConditionalTokens.sol";

contract MarketSettlementTest is SettlementFeeFixture {
    function test_GetCTFRedemptionParamsForResolvedYesMarket() public {
        _assertRedemptionParamsForOutcome(1, 1, 0, 1);
    }

    function test_GetCTFRedemptionParamsReturnsResolvedMarketData() public {
        (bytes32 marketId, ExpectedMarketData memory expected, uint64 expiryTime) =
            _createTradingMarket("ctf-redemption-view", "settlement", 7 days);
        _finalizeCreatorResolution(marketId, expiryTime, 1);

        (address collateralTokenAddress, bytes32 conditionId, uint256[] memory indexSets) =
            IMarketSettlementFacet(address(diamond)).getCTFRedemptionParams(marketId);

        assertEq(collateralTokenAddress, address(collateralToken));
        assertEq(conditionId, expected.conditionId);
        assertEq(indexSets.length, 2);
        assertEq(indexSets[0], 1);
        assertEq(indexSets[1], 2);
    }

    function test_GetCTFRedemptionParamsForResolvedNoMarket() public {
        _assertRedemptionParamsForOutcome(2, 0, 1, 1);
    }

    function test_GetCTFRedemptionParamsForResolvedInvalidMarket() public {
        _assertRedemptionParamsForOutcome(3, 1, 1, 2);
    }

    function test_RevertWhen_GetCTFRedemptionParamsBeforeResolution() public {
        (bytes32 marketId,,) = _createTradingMarket("pending-settlement", "settlement", 7 days);

        vm.expectRevert(abi.encodeWithSelector(Errors.MarketNotResolved.selector, marketId));
        IMarketSettlementFacet(address(diamond)).getCTFRedemptionParams(marketId);
    }

    function test_RevertWhen_GetCTFRedemptionParamsForParimutuelMarket() public {
        (bytes32 marketId,, uint64 expiryTime) =
            _createTradingMarket("parimutuel-redemption-params", "settlement", 7 days);

        _markParimutuelMarket(marketId);
        _setParimutuelPool(marketId, 100e6, 200e6, 300e6, 0, 0, false);
        _finalizeCreatorResolution(marketId, expiryTime, 1);

        vm.expectRevert(_positionTokenTypeMismatch(marketId));
        IMarketSettlementFacet(address(diamond)).getCTFRedemptionParams(marketId);
    }

    function test_PreviewRedemptionReturnsParimutuelYesPayout() public {
        (bytes32 marketId,, uint64 expiryTime) = _createTradingMarket("parimutuel-preview-yes", "settlement", 7 days);
        MockConditionalTokens positionToken = _markParimutuelMarket(marketId);
        (uint256 yesPositionId, uint256 noPositionId) = _positionIds(marketId);

        positionToken.mintPosition(maker, yesPositionId, 250e6);
        positionToken.mintPosition(maker, noPositionId, 80e6);
        _setParimutuelPool(marketId, 1_000e6, 2_000e6, 6_000e6, 0, 0, false);
        _finalizeCreatorResolution(marketId, expiryTime, 1);

        (uint256 claimableAmount, uint256 yesBalance, uint256 noBalance, uint8 outcome) =
            IMarketSettlementFacet(address(diamond)).previewRedemption(marketId, maker);

        assertEq(yesBalance, 250e6);
        assertEq(noBalance, 80e6);
        assertEq(outcome, 1);
        assertEq(claimableAmount, 1_500e6);
    }

    function test_PreviewCTFRedemptionRejectsParimutuelAndDedicatedPreviewWorks() public {
        (bytes32 marketId,, uint64 expiryTime) = _createTradingMarket("split-redemption-preview", "settlement", 7 days);
        MockConditionalTokens positionToken = _markParimutuelMarket(marketId);
        (uint256 yesPositionId, uint256 noPositionId) = _positionIds(marketId);

        positionToken.mintPosition(maker, yesPositionId, 250e6);
        positionToken.mintPosition(maker, noPositionId, 80e6);
        _setParimutuelPool(marketId, 1_000e6, 2_000e6, 6_000e6, 0, 0, false);
        _finalizeCreatorResolution(marketId, expiryTime, 1);

        vm.expectRevert(_positionTokenTypeMismatch(marketId));
        IMarketSettlementFacet(address(diamond)).previewCTFRedemption(marketId, maker);

        (uint256 claimableAmount, uint256 yesBalance, uint256 noBalance, uint8 outcome) =
            IMarketSettlementFacet(address(diamond)).previewParimutuelPayout(marketId, maker);

        assertEq(yesBalance, 250e6);
        assertEq(noBalance, 80e6);
        assertEq(outcome, 1);
        assertEq(claimableAmount, 1_500e6);
    }

    function test_PreviewRedemptionReturnsParimutuelNoPayout() public {
        (bytes32 marketId,, uint64 expiryTime) = _createTradingMarket("parimutuel-preview-no", "settlement", 7 days);
        MockConditionalTokens positionToken = _markParimutuelMarket(marketId);
        (uint256 yesPositionId, uint256 noPositionId) = _positionIds(marketId);

        positionToken.mintPosition(maker, yesPositionId, 100e6);
        positionToken.mintPosition(maker, noPositionId, 250e6);
        _setParimutuelPool(marketId, 1_000e6, 2_000e6, 6_000e6, 0, 0, false);
        _finalizeCreatorResolution(marketId, expiryTime, 2);

        (uint256 claimableAmount, uint256 yesBalance, uint256 noBalance, uint8 outcome) =
            IMarketSettlementFacet(address(diamond)).previewRedemption(marketId, maker);

        assertEq(yesBalance, 100e6);
        assertEq(noBalance, 250e6);
        assertEq(outcome, 2);
        assertEq(claimableAmount, 750e6);
    }

    function test_PreviewRedemptionReturnsParimutuelInvalidProRataPayout() public {
        (bytes32 marketId,, uint64 expiryTime) =
            _createTradingMarket("parimutuel-preview-invalid", "settlement", 7 days);
        MockConditionalTokens positionToken = _markParimutuelMarket(marketId);
        (uint256 yesPositionId, uint256 noPositionId) = _positionIds(marketId);

        positionToken.mintPosition(maker, yesPositionId, 300e6);
        positionToken.mintPosition(maker, noPositionId, 200e6);
        _setParimutuelPool(marketId, 1_000e6, 2_000e6, 2_000e6, 0, 0, false);
        _finalizeCreatorResolution(marketId, expiryTime, 3);

        (uint256 claimableAmount, uint256 yesBalance, uint256 noBalance, uint8 outcome) =
            IMarketSettlementFacet(address(diamond)).previewRedemption(marketId, maker);

        assertEq(yesBalance, 300e6);
        assertEq(noBalance, 200e6);
        assertEq(outcome, 3);
        assertEq(claimableAmount, 333_333_333);
    }

    function test_PreviewRedemptionReturnsParimutuelZeroWinnerRefund() public {
        (bytes32 marketId,, uint64 expiryTime) =
            _createTradingMarket("parimutuel-preview-zero-winner", "settlement", 7 days);
        MockConditionalTokens positionToken = _markParimutuelMarket(marketId);
        (, uint256 noPositionId) = _positionIds(marketId);

        positionToken.mintPosition(maker, noPositionId, 120e6);
        _setParimutuelPool(marketId, 0, 900e6, 900e6, 0, 0, false);
        _finalizeCreatorResolution(marketId, expiryTime, 1);

        (uint256 claimableAmount, uint256 yesBalance, uint256 noBalance, uint8 outcome) =
            IMarketSettlementFacet(address(diamond)).previewRedemption(marketId, maker);

        assertEq(yesBalance, 0);
        assertEq(noBalance, 120e6);
        assertEq(outcome, 1);
        assertEq(claimableAmount, 120e6);
    }

    function test_FinalizeResolutionEmitsPayoutReported() public {
        (bytes32 marketId,, uint64 expiryTime) = _createTradingMarket("payout-event", "settlement", 7 days);

        _expireMarket(marketId, expiryTime);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(marketId, 3);

        (,,,,,, uint64 disputeDeadline,) = StateProbeFacet(address(diamond)).getStoredResolution(marketId);

        vm.expectEmit(true, false, false, true, address(diamond));
        emit Events.PayoutReported(marketId, 3, keccak256(abi.encode(uint256(1), uint256(1))));

        vm.warp(disputeDeadline);
        IOBRResolutionFacet(address(diamond)).finalizeResolution(marketId);
    }

    function test_FinalizeResolutionPreparesNeverTradedCondition() public {
        (bytes32 marketId, ExpectedMarketData memory expected, uint64 expiryTime) =
            _createTradingMarket("lazy-condition-settlement", "settlement", 7 days);

        assertEq(conditionalTokens.getOutcomeSlotCount(expected.conditionId), 0);

        _finalizeCreatorResolution(marketId, expiryTime, 2);

        (
            address oracle,
            bytes32 questionId,
            uint256 outcomeSlotCount,
            bool prepared,
            bool reported,
            uint256 denominator
        ) = conditionalTokens.getConditionDetails(expected.conditionId);
        uint256[] memory payouts = conditionalTokens.getPayoutNumerators(expected.conditionId);

        assertEq(oracle, address(diamond));
        assertEq(questionId, expected.resolutionId);
        assertEq(outcomeSlotCount, 2);
        assertTrue(prepared);
        assertTrue(reported);
        assertEq(denominator, 1);
        assertEq(payouts[0], 0);
        assertEq(payouts[1], 1);
    }

    function test_ExistingCLOBMarketSettlementUsesStoredPositionTokenAfterDefaultChange() public {
        (bytes32 marketId, ExpectedMarketData memory expected, uint64 expiryTime) =
            _createTradingMarket("market-scoped-ctf-settlement", "settlement", 7 days);
        MockConditionalTokens replacementDefault = new MockConditionalTokens();

        vm.prank(owner);
        OwnershipFacet(address(diamond)).setDefaultConditionalTokens(address(replacementDefault));

        _finalizeCreatorResolution(marketId, expiryTime, 1);

        (,,, bool prepared, bool reported, uint256 payoutDenominator) =
            conditionalTokens.getConditionDetails(expected.conditionId);
        uint256[] memory payouts = conditionalTokens.getPayoutNumerators(expected.conditionId);

        assertTrue(prepared);
        assertTrue(reported);
        assertEq(payoutDenominator, 1);
        assertEq(payouts[0], 1);
        assertEq(payouts[1], 0);
        assertEq(replacementDefault.payoutDenominator(expected.conditionId), 0);

        (address collateralTokenAddress, bytes32 conditionId, uint256[] memory indexSets) =
            IMarketSettlementFacet(address(diamond)).getCTFRedemptionParams(marketId);

        assertEq(collateralTokenAddress, address(collateralToken));
        assertEq(conditionId, expected.conditionId);
        assertEq(indexSets.length, 2);
    }

    function _assertRedemptionParamsForOutcome(
        uint8 outcome,
        uint256 expectedYes,
        uint256 expectedNo,
        uint256 expectedDenominator
    ) internal {
        (bytes32 marketId, ExpectedMarketData memory expected, uint64 expiryTime) =
            _createTradingMarket("resolved-settlement", "settlement", 7 days);

        _finalizeCreatorResolution(marketId, expiryTime, outcome);

        (address collateralTokenAddress, bytes32 conditionId, uint256[] memory indexSets) =
            IMarketSettlementFacet(address(diamond)).getCTFRedemptionParams(marketId);
        (,,, bool prepared, bool reported, uint256 payoutDenominator) =
            conditionalTokens.getConditionDetails(expected.conditionId);
        uint256[] memory payouts = conditionalTokens.getPayoutNumerators(expected.conditionId);

        assertEq(collateralTokenAddress, address(collateralToken));
        assertEq(conditionId, expected.conditionId);
        assertEq(indexSets.length, 2);
        assertEq(indexSets[0], 1);
        assertEq(indexSets[1], 2);
        assertTrue(prepared);
        assertTrue(reported);
        assertEq(payoutDenominator, expectedDenominator);
        assertEq(payouts[0], expectedYes);
        assertEq(payouts[1], expectedNo);
    }

    function _markParimutuelMarket(bytes32 marketId) internal returns (MockConditionalTokens positionToken) {
        positionToken = new MockConditionalTokens();
        ResolutionHarnessFacet(address(diamond))
            .setMarketTypeAndPositionToken(
                marketId, uint256(uint8(LibEveMarket.MarketType.PARIMUTUEL)), address(positionToken)
            );
    }

    function _positionTokenTypeMismatch(bytes32 marketId) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(
            Errors.PositionTokenTypeMismatch.selector,
            marketId,
            uint8(LibEveMarket.PositionTokenType.CTF),
            uint8(LibEveMarket.PositionTokenType.PARIMUTUEL)
        );
    }

    function _setParimutuelPool(
        bytes32 marketId,
        uint128 totalYesShares,
        uint128 totalNoShares,
        uint128 payoutPool,
        uint128 claimedPayout,
        uint128 claimedClaimableShares,
        bool dustSwept
    ) internal {
        ResolutionHarnessFacet(address(diamond))
            .setParimutuelPool(
                marketId, totalYesShares, totalNoShares, payoutPool, claimedPayout, claimedClaimableShares, dustSwept
            );
    }

    function _positionIds(bytes32 marketId) internal view returns (uint256 yesPositionId, uint256 noPositionId) {
        (,,,, yesPositionId, noPositionId) = StateProbeFacet(address(diamond)).getStoredMarketCore(marketId);
    }
}
