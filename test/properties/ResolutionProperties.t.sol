// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IOBRResolutionFacet} from "../../src/interfaces/IOBRResolutionFacet.sol";
import {IResolverJuryFacet} from "../../src/interfaces/IResolverJuryFacet.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {LibMarketCreation} from "../../src/libraries/LibMarketCreation.sol";
import {LibResolverJury} from "../../src/libraries/LibResolverJury.sol";

import {ResolutionFixture, ResolutionHarnessFacet, StateProbeFacet} from "../helpers/DiamondFixtures.sol";

contract ResolutionPropertiesTest is ResolutionFixture {
    // Feature: eve-prediction-market, Property 20: creator settlement mechanics
    function testFuzz_CreatorSettlementMechanics(bytes32 questionSeed, uint64 durationSeed, uint8 outcomeSeed) public {
        string memory question = string.concat("Q-", vm.toString(uint256(questionSeed)));
        uint64 duration = uint64(bound(uint256(durationSeed), 1 hours, 30 days));
        uint8 outcome = uint8(bound(uint256(outcomeSeed), 1, 3));

        (bytes32 marketId,) = _createPendingMarket(question, "creator", duration);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(marketId, outcome);

        (address proposer, uint8 proposedOutcome, uint8 escalationLevel,,, uint64 proposedAt, uint64 disputeDeadline,) =
            StateProbeFacet(address(diamond)).getStoredResolution(marketId);
        (,,,,, uint8 storedOutcome, uint8 state,) = StateProbeFacet(address(diamond)).getStoredMarketStatus(marketId);

        assertEq(proposer, creator);
        assertEq(proposedOutcome, outcome);
        assertEq(escalationLevel, 0);
        assertEq(proposedAt, uint64(vm.getBlockTimestamp()));
        assertEq(disputeDeadline, uint64(vm.getBlockTimestamp() + 2 hours));
        assertEq(storedOutcome, 0);
        assertEq(state, uint8(LibEveMarket.MarketState.Disputed));
    }

    // Feature: eve-prediction-market, Property 21: dispute escalation mechanics
    function testFuzz_DisputeEscalationMechanics(uint8 initialOutcomeSeed, uint8 secondOutcomeSeed) public {
        (bytes32 marketId,) = _createPendingMarket("Escalation", "properties", 8 days);

        uint8 initialOutcome = uint8(bound(uint256(initialOutcomeSeed), 1, 3));
        uint8 firstDisputeOutcome = _differentOutcome(initialOutcome);
        uint8 secondDisputeOutcome = _boundedDifferentOutcome(secondOutcomeSeed, firstDisputeOutcome);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(marketId, initialOutcome);

        vm.prank(challengerOne);
        IOBRResolutionFacet(address(diamond)).disputeResolution(marketId, firstDisputeOutcome);

        vm.prank(challengerTwo);
        IOBRResolutionFacet(address(diamond)).disputeResolution(marketId, secondDisputeOutcome);

        vm.prank(challengerThree);
        IOBRResolutionFacet(address(diamond)).disputeResolution(marketId, _differentOutcome(secondDisputeOutcome));

        (address proposer,, uint8 escalationLevel,, uint128 bondAmount,, uint64 disputeDeadline, uint64 snapshotBlock) =
            StateProbeFacet(address(diamond)).getStoredResolution(marketId);
        (,,,,,, uint8 state,) = StateProbeFacet(address(diamond)).getStoredMarketStatus(marketId);
        bytes32 disputeId = keccak256(abi.encode(keccak256("eve.dispute"), marketId));
        IResolverJuryFacet.DisputeView memory disputeView = IResolverJuryFacet(address(diamond)).disputeView(disputeId);

        assertEq(proposer, challengerThree);
        assertEq(escalationLevel, 2);
        assertEq(bondAmount, 0.5 ether);
        assertEq(state, uint8(LibEveMarket.MarketState.Disputed));
        assertEq(disputeDeadline, uint64(vm.getBlockTimestamp() + 2 hours));
        assertEq(snapshotBlock, 0);
        assertEq(disputeView.marketId, marketId);
        assertEq(disputeView.state, uint8(LibResolverJury.DisputeState.CommitteeSelectionPending));
    }

    // Feature: eve-prediction-market, Property 22: resolution finalization
    function testFuzz_ResolutionFinalization(uint128 feeSeed) public {
        string memory question = "Finalize yes";
        string memory category = "properties";
        (bytes32 marketId,) = _createPendingMarket(question, category, 9 days);
        uint128 escrowedFees = uint128(bound(uint256(feeSeed), 1, 1_000_000e6));

        _seedCreatorFees(marketId, escrowedFees);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(marketId, 1);

        vm.prank(challengerOne);
        IOBRResolutionFacet(address(diamond)).disputeResolution(marketId, 2);

        vm.prank(challengerTwo);
        IOBRResolutionFacet(address(diamond)).disputeResolution(marketId, 1);

        ExpectedMarketData memory expected = _expectedFromStored(marketId);
        (,,,,,, uint64 disputeDeadline,) = StateProbeFacet(address(diamond)).getStoredResolution(marketId);

        vm.warp(disputeDeadline);
        IOBRResolutionFacet(address(diamond)).finalizeResolution(marketId);

        _assertResolvedStatus(marketId, expected.marketId, 1);
        _assertCreatorFeeState(marketId, escrowedFees, true);
        _assertClearedBond(challengerOne);
        _assertClearedBond(challengerTwo);
        _assertPayout(expected.conditionId, 1, 0, 1);
    }

    // Feature: eve-prediction-market, Property 23: bond slashing and creator fee forfeiture
    function testFuzz_BondSlashingAndCreatorFeeForfeiture(uint128 feeSeed) public {
        string memory question = "Creator loses";
        string memory category = "properties";
        (bytes32 marketId,) = _createPendingMarket(question, category, 9 days);
        uint128 escrowedFees = uint128(bound(uint256(feeSeed), 10, 1_000_000e6));

        _seedCreatorFees(marketId, escrowedFees);
        uint256 treasuryUsdcBefore = collateralToken.balanceOf(treasury);
        uint256 challengerUsdcBefore = collateralToken.balanceOf(challengerOne);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(marketId, 1);

        vm.prank(challengerOne);
        IOBRResolutionFacet(address(diamond)).disputeResolution(marketId, 2);

        ExpectedMarketData memory expected = _expectedFromStored(marketId);
        (,,,,,, uint64 disputeDeadline,) = StateProbeFacet(address(diamond)).getStoredResolution(marketId);

        vm.warp(disputeDeadline);
        IOBRResolutionFacet(address(diamond)).finalizeResolution(marketId);

        uint256 challengerReward = escrowedFees / 10;
        _assertResolvedStatus(marketId, expected.marketId, 2);
        _assertCreatorFeeState(marketId, 0, false);
        _assertClearedBond(challengerOne);
        assertEq(collateralToken.balanceOf(challengerOne), challengerUsdcBefore + challengerReward);
        assertEq(collateralToken.balanceOf(treasury), treasuryUsdcBefore + escrowedFees - challengerReward);
        _assertPayout(expected.conditionId, 0, 1, 1);
    }

    // Feature: eve-prediction-market, Property 24: resolution failure modes
    function testFuzz_ResolutionFailureModes(uint128 feeSeed) public {
        string memory question = "Timeout invalid";
        string memory category = "properties";
        (bytes32 marketId, uint64 expiryTime) = _createPendingMarket(question, category, 10 days);
        uint128 escrowedFees = uint128(bound(uint256(feeSeed), 1, 1_000_000e6));

        _seedCreatorFees(marketId, escrowedFees);
        uint256 treasuryUsdcBefore = collateralToken.balanceOf(treasury);
        ExpectedMarketData memory expected = _expectedFromStored(marketId);

        vm.warp(expiryTime + 48 hours);
        IOBRResolutionFacet(address(diamond)).finalizeResolution(marketId);

        _assertResolvedStatus(marketId, expected.marketId, 3);
        _assertCreatorFeeState(marketId, 0, false);
        assertEq(collateralToken.balanceOf(treasury), treasuryUsdcBefore + escrowedFees);
        _assertPayout(expected.conditionId, 1, 1, 2);
    }

    // Feature: eve-prediction-market, Property 37: protocol dispute participation symmetry
    function test_ProtocolDisputeParticipationSymmetry() public {
        (bytes32 marketId, uint64 expiryTime) = _createPendingMarket("Treasury open", "properties", 7 days);
        vm.warp(expiryTime + 24 hours);

        vm.prank(treasury);
        IOBRResolutionFacet(address(diamond)).openResolution(marketId, 2);

        _assertBondedForMarket(marketId, treasury, 0.1 ether);

        (bytes32 secondMarketId, uint64 secondExpiry) = _createPendingMarket("Treasury short", "properties", 8 days);
        vm.warp(secondExpiry + 24 hours);

        vm.prank(outsider);
        vm.expectRevert();
        IOBRResolutionFacet(address(diamond)).openResolution(secondMarketId, 1);
    }

    // Feature: eve-prediction-market, Property 39: CTF payout authorization
    function test_CtfPayoutAuthorization() public {
        string memory question = "Authorized payouts";
        string memory category = "properties";
        (bytes32 marketId,) = _createPendingMarket(question, category, 12 days);
        ExpectedMarketData memory expected = _expectedFromStored(marketId);

        uint256[] memory invalidExternalPayout = new uint256[](2);
        invalidExternalPayout[0] = 1;

        vm.prank(outsider);
        vm.expectRevert();
        conditionalTokens.reportPayouts(expected.resolutionId, invalidExternalPayout);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(marketId, 1);

        (,,,,,, uint64 disputeDeadline,) = StateProbeFacet(address(diamond)).getStoredResolution(marketId);
        vm.warp(disputeDeadline);
        IOBRResolutionFacet(address(diamond)).finalizeResolution(marketId);

        _assertPayout(expected.conditionId, 1, 0, 1);
    }

    function _boundedDifferentOutcome(uint8 seed, uint8 currentOutcome) internal pure returns (uint8) {
        uint8 candidate = uint8((uint256(seed) % 3) + 1);
        if (candidate == currentOutcome) {
            return _differentOutcome(candidate);
        }

        return candidate;
    }

    function _differentOutcome(uint8 outcome) internal pure returns (uint8) {
        if (outcome == 1) {
            return 2;
        }

        if (outcome == 2) {
            return 3;
        }

        return 1;
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

    function _assertCreatorFeeState(bytes32 marketId, uint128 expectedEscrow, bool expectedEligible) internal view {
        (uint128 creatorFeesEscrowed,,, bool creatorFeeEligible) =
            StateProbeFacet(address(diamond)).getStoredMarketFees(marketId);

        assertEq(creatorFeesEscrowed, expectedEscrow);
        assertEq(creatorFeeEligible, expectedEligible);
    }

    function _assertClearedBond(address account) internal view {
        uint256 bonded = StateProbeFacet(address(diamond)).getBondedTotals(account);

        assertEq(bonded, 0);
    }

    function _assertBondedForMarket(bytes32 marketId, address account, uint128 expectedAmount) internal view {
        uint128 bonded = StateProbeFacet(address(diamond)).getBondedForMarket(marketId, account);

        assertEq(bonded, expectedAmount);
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
}
