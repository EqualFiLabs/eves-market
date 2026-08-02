// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IOBRResolutionFacet} from "../../src/interfaces/IOBRResolutionFacet.sol";
import {IMarketFactoryFacet} from "../../src/interfaces/IMarketFactoryFacet.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {Events} from "../../src/libraries/Events.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {LibMarketCreation} from "../../src/libraries/LibMarketCreation.sol";
import {LibMultiOutcome} from "../../src/libraries/LibMultiOutcome.sol";
import {OwnershipFacet} from "../../src/facets/OwnershipFacet.sol";

import {ResolutionFixture, ResolutionHarnessFacet, StateProbeFacet} from "../helpers/DiamondFixtures.sol";

contract OBRResolutionTest is ResolutionFixture {
    // Synthetic harness use is limited to narrow storage setup for otherwise unreachable resolution edges.

    function test_BootstrapModeAllowsCreatorSettlementButRejectsPublicResolution() public {
        ResolutionHarnessFacet(address(diamond))
            .setResolutionMode(uint8(LibEveMarket.ResolutionMode.CreatorAdminBootstrap));
        (bytes32 settledMarketId,) = _createPendingMarket("Bootstrap creator settle", "resolution", 7 days);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(settledMarketId, 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.ResolutionModeDisabled.selector, uint8(LibEveMarket.ResolutionMode.CreatorAdminBootstrap)
            )
        );
        vm.prank(challengerOne);
        IOBRResolutionFacet(address(diamond)).disputeResolution(settledMarketId, 2);

        (bytes32 openMarketId, uint64 expiryTime) = _createPendingMarket("Bootstrap open blocked", "resolution", 7 days);
        vm.warp(expiryTime + 24 hours);

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.ResolutionModeDisabled.selector, uint8(LibEveMarket.ResolutionMode.CreatorAdminBootstrap)
            )
        );
        vm.prank(challengerOne);
        IOBRResolutionFacet(address(diamond)).openResolution(openMarketId, 2);
    }

    function test_BootstrapModeOwnerCanFinalizeUnresolvedMarket() public {
        ResolutionHarnessFacet(address(diamond))
            .setResolutionMode(uint8(LibEveMarket.ResolutionMode.CreatorAdminBootstrap));
        (bytes32 marketId,) = _createPendingMarket("Bootstrap admin final", "resolution", 7 days);

        vm.prank(owner);
        IOBRResolutionFacet(address(diamond)).adminFinalizeResolution(marketId, 2);

        _assertResolvedStatus(marketId, marketId, 2);
    }

    function test_RevertWhen_NonOwnerAdminFinalizesBootstrapMarket() public {
        ResolutionHarnessFacet(address(diamond))
            .setResolutionMode(uint8(LibEveMarket.ResolutionMode.CreatorAdminBootstrap));
        (bytes32 marketId,) = _createPendingMarket("Bootstrap admin owner", "resolution", 7 days);

        vm.expectRevert(abi.encodeWithSelector(Errors.NotContractOwner.selector, challengerOne));
        vm.prank(challengerOne);
        IOBRResolutionFacet(address(diamond)).adminFinalizeResolution(marketId, 2);
    }

    function test_RevertWhen_AdminFinalizationOverridesResolvedMarket() public {
        ResolutionHarnessFacet(address(diamond))
            .setResolutionMode(uint8(LibEveMarket.ResolutionMode.CreatorAdminBootstrap));
        (bytes32 marketId,) = _createPendingMarket("Bootstrap no override", "resolution", 7 days);

        vm.prank(owner);
        IOBRResolutionFacet(address(diamond)).adminFinalizeResolution(marketId, 2);

        vm.expectRevert(abi.encodeWithSelector(Errors.MarketAlreadyResolved.selector, marketId));
        vm.prank(owner);
        IOBRResolutionFacet(address(diamond)).adminFinalizeResolution(marketId, 1);
    }

    function test_RevertWhen_EnablingObrJuryBeforeFullResolverSet() public {
        ResolutionHarnessFacet(address(diamond))
            .setResolutionMode(uint8(LibEveMarket.ResolutionMode.CreatorAdminBootstrap));

        vm.expectRevert(abi.encodeWithSelector(Errors.ResolverSetNotReady.selector, 0, 0));
        vm.prank(owner);
        OwnershipFacet(address(diamond)).setResolutionMode(uint8(LibEveMarket.ResolutionMode.ObrJury));
    }

    function test_SettleMarketRecordsCreatorProposalAndStartsDisputeWindow() public {
        (bytes32 marketId,) = _createPendingMarket("Creator settle", "resolution", 7 days);

        vm.expectEmit(true, false, false, true, address(diamond));
        emit Events.CreatorSettled(marketId, 1);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(marketId, 1);

        (,,,,,, uint8 state,) = StateProbeFacet(address(diamond)).getStoredMarketStatus(marketId);
        (
            address proposer,
            uint8 proposedOutcome,
            uint8 escalationLevel,
            bool disputed,,
            uint64 proposedAt,
            uint64 disputeDeadline,
        ) = StateProbeFacet(address(diamond)).getStoredResolution(marketId);

        assertEq(state, uint8(LibEveMarket.MarketState.Disputed));
        assertEq(proposer, creator);
        assertEq(proposedOutcome, 1);
        assertEq(escalationLevel, 0);
        assertFalse(disputed);
        assertEq(proposedAt, uint64(block.timestamp));
        assertEq(disputeDeadline, uint64(block.timestamp + 2 hours));
        assertEq(StateProbeFacet(address(diamond)).getResolutionHistoryLength(marketId), 1);
    }

    function test_SettleMarketSyncsExpiredTradingMarket() public {
        (bytes32 marketId,, uint64 expiryTime) =
            _createUnsyncedTradingMarket("Creator settle direct", "resolution", 7 days);

        vm.warp(expiryTime);

        vm.expectEmit(true, false, false, true, address(diamond));
        emit Events.MarketExpired(marketId);
        vm.expectEmit(true, false, false, true, address(diamond));
        emit Events.CreatorSettled(marketId, 1);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(marketId, 1);

        (,,,,,, uint8 state,) = StateProbeFacet(address(diamond)).getStoredMarketStatus(marketId);
        assertEq(state, uint8(LibEveMarket.MarketState.Disputed));
    }

    function test_SettleMarketEarlyRecordsCreatorProposalAndStartsDisputeWindow() public {
        (bytes32 marketId,, uint64 expiryTime) =
            _createUnsyncedTradingMarket("Creator early settle", "resolution", 7 days);
        assertLt(block.timestamp, expiryTime);

        vm.expectEmit(true, false, false, true, address(diamond));
        emit Events.CreatorSettled(marketId, 1);
        vm.expectEmit(true, false, false, true, address(diamond));
        emit Events.EarlyCreatorSettled(marketId, 1);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarketEarly(marketId, 1);

        (,, uint64 storedExpiry,,,, uint8 state,) = StateProbeFacet(address(diamond)).getStoredMarketStatus(marketId);
        (
            address proposer,
            uint8 proposedOutcome,
            uint8 escalationLevel,
            bool disputed,,
            uint64 proposedAt,
            uint64 disputeDeadline,
        ) = StateProbeFacet(address(diamond)).getStoredResolution(marketId);

        assertEq(storedExpiry, expiryTime);
        assertEq(state, uint8(LibEveMarket.MarketState.Disputed));
        assertEq(proposer, creator);
        assertEq(proposedOutcome, 1);
        assertEq(escalationLevel, 0);
        assertFalse(disputed);
        assertEq(proposedAt, uint64(block.timestamp));
        assertEq(disputeDeadline, uint64(block.timestamp + 2 hours));
        assertEq(StateProbeFacet(address(diamond)).getResolutionHistoryLength(marketId), 1);
    }

    function test_SettleMarketEarlyFinalizesThroughNormalDisputeWindow() public {
        (bytes32 marketId, ExpectedMarketData memory expected,) =
            _createUnsyncedTradingMarket("Early settle finalization", "resolution", 7 days);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarketEarly(marketId, 2);

        (,,,,,, uint64 disputeDeadline,) = StateProbeFacet(address(diamond)).getStoredResolution(marketId);
        vm.expectRevert(abi.encodeWithSelector(Errors.ResolutionNotReady.selector, marketId));
        IOBRResolutionFacet(address(diamond)).finalizeResolution(marketId);

        vm.warp(disputeDeadline);
        IOBRResolutionFacet(address(diamond)).finalizeResolution(marketId);

        _assertResolvedStatus(marketId, expected.marketId, 2);
        _assertPayout(expected.conditionId, 0, 1, 1);
    }

    function test_RevertWhen_NonCreatorSettlesMarketEarly() public {
        (bytes32 marketId,,) = _createUnsyncedTradingMarket("Early creator restriction", "resolution", 7 days);

        vm.prank(challengerOne);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotMarketCreator.selector, challengerOne, creator));
        IOBRResolutionFacet(address(diamond)).settleMarketEarly(marketId, 1);
    }

    function test_RevertWhen_EarlySettlementTargetsNonTradingMarket() public {
        (bytes32 marketId,) = _createPendingMarket("Early pending restriction", "resolution", 7 days);

        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(Errors.MarketNotTrading.selector, marketId));
        IOBRResolutionFacet(address(diamond)).settleMarketEarly(marketId, 1);
    }

    function test_OpenResolutionAfterGraceLocksBondsAndStartsProposal() public {
        (bytes32 marketId, uint64 expiryTime) = _createPendingMarket("Open resolution", "resolution", 7 days);
        vm.warp(expiryTime + 24 hours);

        uint256 userEveBefore = eveToken.balanceOf(challengerOne);

        vm.expectEmit(true, true, false, true, address(diamond));
        emit Events.OpenResolutionStarted(marketId, challengerOne, 2);

        vm.prank(challengerOne);
        IOBRResolutionFacet(address(diamond)).openResolution(marketId, 2);

        (
            address proposer,
            uint8 proposedOutcome,
            uint8 escalationLevel,,
            uint128 bondAmount,,
            uint64 disputeDeadline,
        ) = StateProbeFacet(address(diamond)).getStoredResolution(marketId);
        uint256 bonded = StateProbeFacet(address(diamond)).getBondedTotals(challengerOne);
        uint128 marketBonded = StateProbeFacet(address(diamond)).getBondedForMarket(marketId, challengerOne);

        assertEq(proposer, challengerOne);
        assertEq(proposedOutcome, 2);
        assertEq(escalationLevel, 1);
        assertEq(bondAmount, 0.1 ether);
        assertEq(disputeDeadline, uint64(block.timestamp + 2 hours));
        assertEq(bonded, 0.1 ether);
        assertEq(marketBonded, 0.1 ether);
        assertEq(eveToken.balanceOf(challengerOne), userEveBefore - 0.1 ether);
    }

    function test_OpenResolutionSyncsExpiredTradingMarket() public {
        (bytes32 marketId,, uint64 expiryTime) = _createUnsyncedTradingMarket("Open direct", "resolution", 7 days);

        vm.warp(expiryTime + 24 hours);

        vm.expectEmit(true, false, false, true, address(diamond));
        emit Events.MarketExpired(marketId);
        vm.expectEmit(true, true, false, true, address(diamond));
        emit Events.OpenResolutionStarted(marketId, challengerOne, 2);

        vm.prank(challengerOne);
        IOBRResolutionFacet(address(diamond)).openResolution(marketId, 2);

        (,,,,,, uint8 state,) = StateProbeFacet(address(diamond)).getStoredMarketStatus(marketId);
        assertEq(state, uint8(LibEveMarket.MarketState.Disputed));
    }

    function test_DisputeEscalatesToResolverJuryAtMaxReDispute() public {
        (bytes32 marketId,) = _createPendingMarket("Vote escalation", "resolution", 8 days);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(marketId, 1);

        vm.prank(challengerOne);
        IOBRResolutionFacet(address(diamond)).disputeResolution(marketId, 2);

        vm.prank(challengerTwo);
        IOBRResolutionFacet(address(diamond)).disputeResolution(marketId, 3);

        vm.prank(challengerThree);
        IOBRResolutionFacet(address(diamond)).disputeResolution(marketId, 1);

        (,,,,,, uint8 state,) = StateProbeFacet(address(diamond)).getStoredMarketStatus(marketId);
        (
            address proposer,
            uint8 proposedOutcome,
            uint8 escalationLevel,,
            uint128 bondAmount,,
            uint64 disputeDeadline,
            uint64 snapshotBlock
        ) = StateProbeFacet(address(diamond)).getStoredResolution(marketId);

        assertEq(state, uint8(LibEveMarket.MarketState.Disputed));
        assertEq(proposer, challengerThree);
        assertEq(proposedOutcome, 1);
        assertEq(escalationLevel, 2);
        assertEq(bondAmount, 0.5 ether);
        assertEq(snapshotBlock, 0);
        assertEq(disputeDeadline, uint64(block.timestamp + 2 hours));
        assertEq(StateProbeFacet(address(diamond)).getResolutionHistoryLength(marketId), 4);
    }

    function test_FinalizeResolutionKeepsCreatorFeesClaimableWhenCreatorOutcomeWins() public {
        string memory question = "Honest creator";
        string memory category = "resolution";
        (bytes32 marketId,) = _createPendingMarket(question, category, 9 days);
        uint128 creationBond = StateProbeFacet(address(diamond)).marketCreationBond();

        _seedCreatorFees(marketId, 200e6);

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
        _assertCreatorFeeState(marketId, 200e6, true);
        _assertCreationBondState(marketId, creationBond, true);
        _assertClearedBond(challengerOne);
        _assertClearedBond(challengerTwo);
        assertEq(eveToken.balanceOf(creator), 20_000e18);
        assertEq(challengerTwo.balance, 10 ether);
        assertEq(eveToken.balanceOf(challengerTwo), 20_000e18);
        assertEq(treasury.balance, 10 ether);
        assertEq(eveToken.balanceOf(treasury), 20_000e18 + 0.1 ether);
        _assertPayout(expected.conditionId, 1, 0, 1);
    }

    function test_FinalizeResolutionReturnsCreationBondWhenCreatorHonestWithoutFees() public {
        string memory question = "Honest no volume";
        string memory category = "resolution";
        (bytes32 marketId,) = _createPendingMarket(question, category, 9 days);
        uint128 creationBond = StateProbeFacet(address(diamond)).marketCreationBond();

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(marketId, 1);

        ExpectedMarketData memory expected = _expectedFromStored(marketId);
        (,,,,,, uint64 disputeDeadline,) = StateProbeFacet(address(diamond)).getStoredResolution(marketId);

        vm.warp(disputeDeadline);
        IOBRResolutionFacet(address(diamond)).finalizeResolution(marketId);

        _assertResolvedStatus(marketId, expected.marketId, 1);
        _assertCreatorFeeState(marketId, 0, false);
        _assertCreatorStatus(marketId, true, false, true);
        _assertCreationBondState(marketId, creationBond, true);
        assertEq(eveToken.balanceOf(creator), 20_000e18);
        _assertPayout(expected.conditionId, 1, 0, 1);
    }

    function test_FinalizeResolutionReturnsCreationBondWhenCreatorHonestlySettlesInvalid() public {
        string memory question = "Honest invalid";
        string memory category = "resolution";
        (bytes32 marketId,) = _createPendingMarket(question, category, 9 days);
        uint128 creationBond = StateProbeFacet(address(diamond)).marketCreationBond();

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(marketId, 3);

        ExpectedMarketData memory expected = _expectedFromStored(marketId);
        (,,,,,, uint64 disputeDeadline,) = StateProbeFacet(address(diamond)).getStoredResolution(marketId);

        vm.warp(disputeDeadline);
        IOBRResolutionFacet(address(diamond)).finalizeResolution(marketId);

        _assertResolvedStatus(marketId, expected.marketId, 3);
        _assertCreatorFeeState(marketId, 0, false);
        _assertCreatorStatus(marketId, true, false, true);
        _assertCreationBondState(marketId, creationBond, true);
        assertEq(eveToken.balanceOf(creator), 20_000e18);
        _assertPayout(expected.conditionId, 1, 1, 2);
    }

    function test_FinalizeResolutionForfeitsCreatorFeesWhenHonestOutcomeIsInvalid() public {
        string memory question = "Honest invalid fees";
        string memory category = "resolution";
        (bytes32 marketId,) = _createPendingMarket(question, category, 9 days);
        uint128 creationBond = StateProbeFacet(address(diamond)).marketCreationBond();

        _seedCreatorFees(marketId, 75e6);

        uint256 treasuryUsdcBefore = collateralToken.balanceOf(treasury);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(marketId, 3);

        ExpectedMarketData memory expected = _expectedFromStored(marketId);
        (,,,,,, uint64 disputeDeadline,) = StateProbeFacet(address(diamond)).getStoredResolution(marketId);

        vm.warp(disputeDeadline);
        IOBRResolutionFacet(address(diamond)).finalizeResolution(marketId);

        _assertResolvedStatus(marketId, expected.marketId, 3);
        _assertCreatorFeeState(marketId, 0, false);
        _assertCreatorStatus(marketId, true, false, true);
        _assertCreationBondState(marketId, creationBond, true);
        assertEq(collateralToken.balanceOf(treasury), treasuryUsdcBefore + 75e6);
        assertEq(eveToken.balanceOf(creator), 20_000e18);
        _assertPayout(expected.conditionId, 1, 1, 2);
    }

    function test_FinalizeMultiOutcomeKeepsCreatorFeesWhenOutcomeZeroWins() public {
        string memory question = "Multi outcome zero honest";
        string memory category = "resolution";
        (bytes32 marketId,) = _createPendingMarket(question, category, 9 days);
        _markMultiOutcomeMarket(marketId, 3);
        _seedCreatorFees(marketId, 80e6);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(marketId, 0);

        (,,,,,, uint64 disputeDeadline,) = StateProbeFacet(address(diamond)).getStoredResolution(marketId);

        vm.warp(disputeDeadline);
        IOBRResolutionFacet(address(diamond)).finalizeResolution(marketId);

        _assertCreatorFeeState(marketId, 80e6, true);
        _assertCreatorStatus(marketId, true, true, true);
    }

    function test_FinalizeMultiOutcomeInvalidForfeitsCreatorFees() public {
        string memory question = "Multi outcome invalid fees";
        string memory category = "resolution";
        (bytes32 marketId,) = _createPendingMarket(question, category, 9 days);
        _markMultiOutcomeMarket(marketId, 3);
        _seedCreatorFees(marketId, 60e6);

        uint256 treasuryUsdcBefore = collateralToken.balanceOf(treasury);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(marketId, LibMultiOutcome.OUTCOME_INVALID);

        (,,,,,, uint64 disputeDeadline,) = StateProbeFacet(address(diamond)).getStoredResolution(marketId);

        vm.warp(disputeDeadline);
        IOBRResolutionFacet(address(diamond)).finalizeResolution(marketId);

        _assertResolvedStatus(marketId, marketId, uint8(LibEveMarket.MarketOutcome.Invalid));
        _assertCreatorFeeState(marketId, 0, false);
        _assertCreatorStatus(marketId, true, false, true);
        assertEq(collateralToken.balanceOf(treasury), treasuryUsdcBefore + 60e6);
    }

    function test_FinalizeMultiOutcomeOverturnsOutcomeZeroAndRewardsChallenger() public {
        string memory question = "Multi outcome zero overturned";
        string memory category = "resolution";
        (bytes32 marketId,) = _createPendingMarket(question, category, 9 days);
        _markMultiOutcomeMarket(marketId, 3);
        _seedCreatorFees(marketId, 100e6);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(marketId, 0);

        uint256 challengerUsdcBefore = collateralToken.balanceOf(challengerOne);
        uint256 treasuryUsdcBefore = collateralToken.balanceOf(treasury);

        vm.prank(challengerOne);
        IOBRResolutionFacet(address(diamond)).disputeResolution(marketId, 1);

        (,,,,,, uint64 disputeDeadline,) = StateProbeFacet(address(diamond)).getStoredResolution(marketId);

        vm.warp(disputeDeadline);
        IOBRResolutionFacet(address(diamond)).finalizeResolution(marketId);

        _assertCreatorFeeState(marketId, 0, false);
        _assertCreatorStatus(marketId, false, false, false);
        assertEq(collateralToken.balanceOf(challengerOne), challengerUsdcBefore + 10e6);
        assertEq(collateralToken.balanceOf(treasury), treasuryUsdcBefore + 90e6);
    }

    function test_FinalizeResolutionForfeitsCreatorFeesWhenCreatorIsOverturned() public {
        string memory question = "Creator overturned";
        string memory category = "resolution";
        (bytes32 marketId,) = _createPendingMarket(question, category, 9 days);
        uint128 creationBond = StateProbeFacet(address(diamond)).marketCreationBond();

        _seedCreatorFees(marketId, 100e6);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(marketId, 1);

        uint256 challengerEthBefore = challengerOne.balance;
        uint256 challengerEveBefore = eveToken.balanceOf(challengerOne);
        uint256 challengerUsdcBefore = collateralToken.balanceOf(challengerOne);
        uint256 treasuryUsdcBefore = collateralToken.balanceOf(treasury);
        uint256 treasuryEveBefore = eveToken.balanceOf(treasury);

        vm.prank(challengerOne);
        IOBRResolutionFacet(address(diamond)).disputeResolution(marketId, 2);

        ExpectedMarketData memory expected = _expectedFromStored(marketId);
        (,,,,,, uint64 disputeDeadline,) = StateProbeFacet(address(diamond)).getStoredResolution(marketId);

        vm.warp(disputeDeadline);
        IOBRResolutionFacet(address(diamond)).finalizeResolution(marketId);

        _assertCreatorFeeState(marketId, 0, false);
        _assertCreationBondState(marketId, creationBond, true);
        assertEq(challengerOne.balance, challengerEthBefore);
        assertEq(eveToken.balanceOf(challengerOne), challengerEveBefore + (creationBond / 10));
        assertEq(collateralToken.balanceOf(challengerOne), challengerUsdcBefore + 10e6);
        assertEq(collateralToken.balanceOf(treasury), treasuryUsdcBefore + 90e6);
        assertEq(eveToken.balanceOf(treasury), treasuryEveBefore + creationBond - (creationBond / 10));
        assertEq(eveToken.balanceOf(creator), 20_000e18 - creationBond);
        _assertPayout(expected.conditionId, 0, 1, 1);
    }

    function test_FinalizeResolutionAfterTimeoutWithoutProposalResolvesInvalid() public {
        string memory question = "Timeout invalid";
        string memory category = "resolution";
        (bytes32 marketId, uint64 expiryTime) = _createPendingMarket(question, category, 10 days);
        uint128 creationBond = StateProbeFacet(address(diamond)).marketCreationBond();

        _seedCreatorFees(marketId, 50e6);
        vm.warp(expiryTime + 48 hours);

        uint256 treasuryUsdcBefore = collateralToken.balanceOf(treasury);
        uint256 treasuryEveBefore = eveToken.balanceOf(treasury);
        ExpectedMarketData memory expected = _expectedFromStored(marketId);

        IOBRResolutionFacet(address(diamond)).finalizeResolution(marketId);

        _assertResolvedStatus(marketId, expected.marketId, 3);
        _assertCreatorFeeState(marketId, 0, false);
        _assertCreationBondState(marketId, creationBond, true);
        assertEq(collateralToken.balanceOf(treasury), treasuryUsdcBefore + 50e6);
        assertEq(eveToken.balanceOf(treasury), treasuryEveBefore + creationBond);
        assertEq(eveToken.balanceOf(creator), 20_000e18 - creationBond);
        _assertPayout(expected.conditionId, 1, 1, 2);
    }

    function test_FinalizeResolutionSyncsExpiredTradingMarketForTimeout() public {
        string memory question = "No proposal direct";
        string memory category = "resolution";
        (bytes32 marketId, ExpectedMarketData memory expected, uint64 expiryTime) =
            _createUnsyncedTradingMarket(question, category, 10 days);

        vm.warp(expiryTime + 3 days);

        vm.expectEmit(true, false, false, true, address(diamond));
        emit Events.MarketExpired(marketId);

        IOBRResolutionFacet(address(diamond)).finalizeResolution(marketId);

        _assertResolvedStatus(marketId, expected.marketId, 3);
        _assertPayout(expected.conditionId, 1, 1, 2);
    }

    function test_CLOBFinalizationReportsCtfPayouts() public {
        string memory question = "CLOB CTF report";
        string memory category = "resolution";
        (bytes32 marketId,) = _createPendingMarket(question, category, 9 days);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(marketId, 2);

        ExpectedMarketData memory expected = _expectedFromStored(marketId);
        (,,,,,, uint64 disputeDeadline,) = StateProbeFacet(address(diamond)).getStoredResolution(marketId);

        vm.warp(disputeDeadline);
        IOBRResolutionFacet(address(diamond)).finalizeResolution(marketId);

        _assertResolvedStatus(marketId, expected.marketId, 2);
        _assertPayout(expected.conditionId, 0, 1, 1);
    }

    function test_ParimutuelFinalizationSkipsCtfPayoutReporting() public {
        string memory question = "Parimutuel no CTF report";
        string memory category = "resolution";
        (bytes32 marketId,) = _createPendingMarket(question, category, 9 days);
        ExpectedMarketData memory expected = _expectedFromStored(marketId);

        _markParimutuelMarket(marketId);
        _setParimutuelPool(marketId, 500e6, 700e6, 1_200e6, 0, 0, false);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(marketId, 2);

        (,,,,,, uint64 disputeDeadline,) = StateProbeFacet(address(diamond)).getStoredResolution(marketId);

        vm.expectEmit(true, false, false, true, address(diamond));
        emit Events.ParimutuelFinalized(marketId, 2, 2, 1_200e6, 700e6);

        vm.warp(disputeDeadline);
        IOBRResolutionFacet(address(diamond)).finalizeResolution(marketId);

        _assertResolvedStatus(marketId, expected.marketId, 2);
        _assertConditionUnreported(expected.conditionId);
        _assertParimutuelPool(marketId, 500e6, 700e6, 1_200e6, 0, 0, false);
        _assertParimutuelFinalization(marketId, 2, 2, 1_200e6, 700e6);
    }

    function test_ParimutuelZeroWinningSideStoresResolvedOutcome() public {
        string memory question = "Parimutuel zero winner";
        string memory category = "resolution";
        (bytes32 marketId,) = _createPendingMarket(question, category, 9 days);
        ExpectedMarketData memory expected = _expectedFromStored(marketId);

        _markParimutuelMarket(marketId);
        _setParimutuelPool(marketId, 0, 900e6, 900e6, 0, 0, false);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(marketId, 1);

        (,,,,,, uint64 disputeDeadline,) = StateProbeFacet(address(diamond)).getStoredResolution(marketId);

        vm.expectEmit(true, false, false, true, address(diamond));
        emit Events.ParimutuelFinalized(marketId, 1, 3, 900e6, 900e6);

        vm.warp(disputeDeadline);
        IOBRResolutionFacet(address(diamond)).finalizeResolution(marketId);

        _assertResolvedStatus(marketId, expected.marketId, 1);
        _assertConditionUnreported(expected.conditionId);
        _assertParimutuelPool(marketId, 0, 900e6, 900e6, 0, 0, false);
        _assertParimutuelFinalization(marketId, 1, 3, 900e6, 900e6);
    }

    function test_RevertWhen_NonCreatorSettlesDuringGrace() public {
        (bytes32 marketId,) = _createPendingMarket("Grace restriction", "resolution", 7 days);

        vm.prank(challengerOne);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotMarketCreator.selector, challengerOne, creator));
        IOBRResolutionFacet(address(diamond)).settleMarket(marketId, 1);
    }

    function test_RevertWhen_ResolutionStartsBeforeExpiry() public {
        (bytes32 marketId,,) = _createUnsyncedTradingMarket("Too early resolution", "resolution", 7 days);

        vm.expectRevert(abi.encodeWithSelector(Errors.MarketNotExpired.selector, marketId));
        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(marketId, 1);

        vm.expectRevert(abi.encodeWithSelector(Errors.MarketNotExpired.selector, marketId));
        vm.prank(challengerOne);
        IOBRResolutionFacet(address(diamond)).openResolution(marketId, 2);

        vm.expectRevert(abi.encodeWithSelector(Errors.MarketNotExpired.selector, marketId));
        IOBRResolutionFacet(address(diamond)).finalizeResolution(marketId);
    }

    function test_RevertWhen_ResolutionActionTargetsResolvedMarket() public {
        (bytes32 marketId,) = _createPendingMarket("Already resolved", "resolution", 7 days);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(marketId, 1);

        (,,,,,, uint64 disputeDeadline,) = StateProbeFacet(address(diamond)).getStoredResolution(marketId);
        vm.warp(disputeDeadline);
        IOBRResolutionFacet(address(diamond)).finalizeResolution(marketId);

        vm.expectRevert(abi.encodeWithSelector(Errors.MarketAlreadyResolved.selector, marketId));
        IOBRResolutionFacet(address(diamond)).finalizeResolution(marketId);

        vm.expectRevert(abi.encodeWithSelector(Errors.MarketAlreadyResolved.selector, marketId));
        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(marketId, 1);

        vm.expectRevert(abi.encodeWithSelector(Errors.MarketAlreadyResolved.selector, marketId));
        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarketEarly(marketId, 1);

        vm.expectRevert(abi.encodeWithSelector(Errors.MarketAlreadyResolved.selector, marketId));
        vm.prank(challengerOne);
        IOBRResolutionFacet(address(diamond)).openResolution(marketId, 2);
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

    function _assertCreatorStatus(
        bytes32 marketId,
        bool expectedSettledHonestly,
        bool expectedFeeEligible,
        bool expectedBondReturnable
    ) internal view {
        (bool creatorSettledHonestly, bool creatorFeeEligible, bool creationBondReturnable) =
            StateProbeFacet(address(diamond)).getStoredCreatorStatus(marketId);

        assertEq(creatorSettledHonestly, expectedSettledHonestly);
        assertEq(creatorFeeEligible, expectedFeeEligible);
        assertEq(creationBondReturnable, expectedBondReturnable);
    }

    function _assertCreationBondState(bytes32 marketId, uint128 expectedBond, bool expectedReleased) internal view {
        (uint128 creationBond, bool creationBondReleased) =
            StateProbeFacet(address(diamond)).getStoredCreationBond(marketId);

        assertEq(creationBond, expectedBond);
        assertEq(creationBondReleased, expectedReleased);
    }

    function _assertClearedBond(address account) internal view {
        uint256 bonded = StateProbeFacet(address(diamond)).getBondedTotals(account);

        assertEq(bonded, 0);
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

        assertFalse(reported);
        assertEq(payoutDenominator, 0);
        if (prepared) {
            assertEq(payouts.length, 2);
            assertEq(payouts[0], 0);
            assertEq(payouts[1], 0);
        } else {
            assertEq(payouts.length, 0);
        }
    }

    function _assertParimutuelPool(
        bytes32 marketId,
        uint128 expectedYesShares,
        uint128 expectedNoShares,
        uint128 expectedPayoutPool,
        uint128 expectedClaimedPayout,
        uint128 expectedClaimedClaimableShares,
        bool expectedDustSwept
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
        assertEq(claimedPayout, expectedClaimedPayout);
        assertEq(claimedClaimableShares, expectedClaimedClaimableShares);
        assertEq(dustSwept, expectedDustSwept);
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

    function _markParimutuelMarket(bytes32 marketId) internal {
        ResolutionHarnessFacet(address(diamond))
            .setMarketTypeAndPositionToken(
                marketId, uint256(uint8(LibEveMarket.MarketType.PARIMUTUEL)), address(0x1155)
            );
    }

    function _markMultiOutcomeMarket(bytes32 marketId, uint256 outcomeCount) internal {
        ResolutionHarnessFacet(address(diamond))
            .setMultiOutcomeResolutionMarket(marketId, address(conditionalTokens), outcomeCount);
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

    function _createUnsyncedTradingMarket(string memory question, string memory category, uint64 duration)
        internal
        returns (bytes32 marketId, ExpectedMarketData memory expected, uint64 expiryTime)
    {
        expiryTime = uint64(block.timestamp) + duration;
        uint128 creationFee = StateProbeFacet(address(diamond)).marketCreationFee();

        _approveCreator(creationFee);

        vm.prank(creator);
        marketId = IMarketFactoryFacet(address(diamond))
            .createMarket(question, category, DEFAULT_RESOLUTION_SOURCE, uint64(block.timestamp), expiryTime, 0, true);

        expected = _expectedFromStored(marketId);
    }
}
