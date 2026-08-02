// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IOBRResolutionFacet} from "../../src/interfaces/IOBRResolutionFacet.sol";
import {Events} from "../../src/libraries/Events.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {LibMarketCreation} from "../../src/libraries/LibMarketCreation.sol";

import {ResolutionFixture, ResolutionHarnessFacet, StateProbeFacet} from "../helpers/DiamondFixtures.sol";

contract OBRParimutuelTest is ResolutionFixture {
    // Synthetic storage setup is limited to market typing and pool totals so this file can isolate finalization.

    function test_CLOBFinalizationReportsCtfPayouts() public {
        string memory question = "focused clob payout report";
        string memory category = "obr-parimutuel";
        (bytes32 marketId,) = _createPendingMarket(question, category, 7 days);
        ExpectedMarketData memory expected = _expectedFromStored(marketId);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(marketId, 2);

        (,,,,,, uint64 disputeDeadline,) = StateProbeFacet(address(diamond)).getStoredResolution(marketId);

        vm.expectEmit(true, false, false, true, address(diamond));
        emit Events.PayoutReported(marketId, 2, keccak256(abi.encode(uint256(0), uint256(1))));

        vm.warp(disputeDeadline);
        IOBRResolutionFacet(address(diamond)).finalizeResolution(marketId);

        _assertResolvedStatus(marketId, expected.marketId, 2);
        _assertPayout(expected.conditionId, 0, 1, 1);
    }

    function test_ParimutuelFinalizationSkipsCtfPayoutReporting() public {
        string memory question = "focused parimutuel skips ctf";
        string memory category = "obr-parimutuel";
        (bytes32 marketId,) = _createPendingMarket(question, category, 7 days);
        ExpectedMarketData memory expected = _expectedFromStored(marketId);

        _markParimutuelMarket(marketId);
        _setParimutuelPool(marketId, 500e6, 700e6, 1_200e6);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(marketId, 2);

        (,,,,,, uint64 disputeDeadline,) = StateProbeFacet(address(diamond)).getStoredResolution(marketId);

        vm.expectEmit(true, false, false, true, address(diamond));
        emit Events.ParimutuelFinalized(marketId, 2, 2, 1_200e6, 700e6);

        vm.warp(disputeDeadline);
        IOBRResolutionFacet(address(diamond)).finalizeResolution(marketId);

        _assertResolvedStatus(marketId, expected.marketId, 2);
        _assertConditionUnreported(expected.conditionId);
        _assertParimutuelPool(marketId, 500e6, 700e6, 1_200e6);
        _assertParimutuelFinalization(marketId, 2, 2, 1_200e6, 700e6);
    }

    function test_ParimutuelZeroWinningSideStoresResolvedOutcome() public {
        string memory question = "focused parimutuel zero winner";
        string memory category = "obr-parimutuel";
        (bytes32 marketId,) = _createPendingMarket(question, category, 7 days);
        ExpectedMarketData memory expected = _expectedFromStored(marketId);

        _markParimutuelMarket(marketId);
        _setParimutuelPool(marketId, 0, 900e6, 900e6);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(marketId, 1);

        (,,,,,, uint64 disputeDeadline,) = StateProbeFacet(address(diamond)).getStoredResolution(marketId);

        vm.expectEmit(true, false, false, true, address(diamond));
        emit Events.ParimutuelFinalized(marketId, 1, 3, 900e6, 900e6);

        vm.warp(disputeDeadline);
        IOBRResolutionFacet(address(diamond)).finalizeResolution(marketId);

        _assertResolvedStatus(marketId, expected.marketId, 1);
        _assertConditionUnreported(expected.conditionId);
        _assertParimutuelPool(marketId, 0, 900e6, 900e6);
        _assertParimutuelFinalization(marketId, 1, 3, 900e6, 900e6);
    }

    function _markParimutuelMarket(bytes32 marketId) internal {
        ResolutionHarnessFacet(address(diamond))
            .setMarketTypeAndPositionToken(
                marketId, uint256(uint8(LibEveMarket.MarketType.PARIMUTUEL)), address(0x1155)
            );
    }

    function _setParimutuelPool(bytes32 marketId, uint128 totalYesShares, uint128 totalNoShares, uint128 payoutPool)
        internal
    {
        ResolutionHarnessFacet(address(diamond))
            .setParimutuelPool(marketId, totalYesShares, totalNoShares, payoutPool, 0, 0, false);
    }

    function _assertResolvedStatus(bytes32 marketId, bytes32 expectedMarketId, uint8 expectedOutcome) internal view {
        (bytes32 storedMarketId,,,,, uint8 outcome, uint8 state,) =
            StateProbeFacet(address(diamond)).getStoredMarketStatus(marketId);

        assertEq(storedMarketId, expectedMarketId);
        assertEq(outcome, expectedOutcome);
        assertEq(state, uint8(LibEveMarket.MarketState.Resolved));
    }

    function _expectedFromStored(bytes32 marketId) internal view returns (ExpectedMarketData memory expected) {
        (,, bytes32 questionId, bytes32 conditionId, uint256 yesPositionId, uint256 noPositionId) =
            StateProbeFacet(address(diamond)).getStoredMarketCore(marketId);

        expected.marketId = marketId;
        expected.questionId = questionId;
        expected.resolutionId = LibMarketCreation.resolutionIdFor(marketId);
        expected.conditionId = conditionId;
        expected.yesPositionId = yesPositionId;
        expected.noPositionId = noPositionId;
    }

    function _assertPayout(bytes32 conditionId, uint256 expectedYes, uint256 expectedNo, uint256 expectedDenominator)
        internal
        view
    {
        (,,, bool prepared, bool reported, uint256 payoutDenominator) =
            conditionalTokens.getConditionDetails(conditionId);
        uint256[] memory payouts = conditionalTokens.getPayoutNumerators(conditionId);

        assertTrue(prepared);
        assertTrue(reported);
        assertEq(payoutDenominator, expectedDenominator);
        assertEq(payouts[0], expectedYes);
        assertEq(payouts[1], expectedNo);
    }

    function _assertConditionUnreported(bytes32 conditionId) internal view {
        (,,, bool prepared, bool reported, uint256 payoutDenominator) =
            conditionalTokens.getConditionDetails(conditionId);
        uint256[] memory payouts = conditionalTokens.getPayoutNumerators(conditionId);

        prepared;
        assertFalse(reported);
        assertEq(payoutDenominator, 0);
        assertEq(payouts.length, 0);
    }

    function _assertParimutuelPool(
        bytes32 marketId,
        uint128 expectedYesShares,
        uint128 expectedNoShares,
        uint128 expectedPayoutPool
    ) internal view {
        (
            uint128 totalYesShares,
            uint128 totalNoShares,
            uint128 payoutPool,
            uint128 claimedPayout,
            uint128 claimedClaimableShares,
            bool dustSwept
        ) = StateProbeFacet(address(diamond)).getStoredParimutuelPool(marketId);

        assertEq(totalYesShares, expectedYesShares);
        assertEq(totalNoShares, expectedNoShares);
        assertEq(payoutPool, expectedPayoutPool);
        assertEq(claimedPayout, 0);
        assertEq(claimedClaimableShares, 0);
        assertFalse(dustSwept);
    }

    function _assertParimutuelFinalization(
        bytes32 marketId,
        uint8 expectedRawOutcome,
        uint8 expectedEffectiveOutcome,
        uint128 expectedPayoutPoolAtResolution,
        uint128 expectedTotalClaimableSharesAtResolution
    ) internal view {
        (
            uint8 rawResolvedOutcome,
            uint8 effectivePayoutOutcome,
            uint128 payoutPoolAtResolution,
            uint128 totalClaimableSharesAtResolution,
            bool finalized
        ) = StateProbeFacet(address(diamond)).getStoredParimutuelFinalization(marketId);

        assertTrue(finalized);
        assertEq(rawResolvedOutcome, expectedRawOutcome);
        assertEq(effectivePayoutOutcome, expectedEffectiveOutcome);
        assertEq(payoutPoolAtResolution, expectedPayoutPoolAtResolution);
        assertEq(totalClaimableSharesAtResolution, expectedTotalClaimableSharesAtResolution);
    }
}
