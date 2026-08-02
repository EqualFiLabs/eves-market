// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {DiamondCutFacet} from "../../src/facets/DiamondCutFacet.sol";
import {MarketFactoryFacet} from "../../src/facets/MarketFactoryFacet.sol";
import {MultiOutcomeOrderbookFacet} from "../../src/facets/MultiOutcomeOrderbookFacet.sol";
import {MultiOutcomeOrderbookViewFacet} from "../../src/facets/MultiOutcomeOrderbookViewFacet.sol";
import {OwnershipFacet} from "../../src/facets/OwnershipFacet.sol";
import {ParimutuelFacet} from "../../src/facets/ParimutuelFacet.sol";
import {ParimutuelViewFacet} from "../../src/facets/ParimutuelViewFacet.sol";
import {ResolverRegistryFacet} from "../../src/facets/ResolverRegistryFacet.sol";
import {ResolverJuryInit} from "../../src/init/ResolverJuryInit.sol";
import {IMultiOutcomeOrderbookFacet} from "../../src/interfaces/IMultiOutcomeOrderbookFacet.sol";
import {IOBRResolutionFacet} from "../../src/interfaces/IOBRResolutionFacet.sol";
import {IParimutuelFacet} from "../../src/interfaces/IParimutuelFacet.sol";
import {IResolverJuryFacet} from "../../src/interfaces/IResolverJuryFacet.sol";
import {IResolverRegistryFacet} from "../../src/interfaces/IResolverRegistryFacet.sol";
import {Events} from "../../src/libraries/Events.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {LibMarketCreation} from "../../src/libraries/LibMarketCreation.sol";
import {LibResolverJury} from "../../src/libraries/LibResolverJury.sol";
import {OwnershipConfigTypes} from "../../src/types/OwnershipConfigTypes.sol";
import {EveIdentity} from "../../src/tokens/EveIdentity.sol";
import {EvesPositionManager} from "../../src/tokens/EvesPositionManager.sol";
import {ParimutuelShareToken} from "../../src/tokens/ParimutuelShareToken.sol";

import {ResolutionFixture, ResolutionHarnessFacet, StateProbeFacet} from "../helpers/DiamondFixtures.sol";
import {MarketFactoryTypes} from "../../src/types/MarketFactoryTypes.sol";

contract ResolverJuryLifecycleTest is ResolutionFixture {
    bytes32 internal constant DISPUTE_DOMAIN = keccak256("eve.dispute");

    address internal alice = makeAddr("lifecycleAlice");
    address internal bob = makeAddr("lifecycleBob");
    address internal carol = makeAddr("lifecycleCarol");
    address internal dave = makeAddr("lifecycleDave");
    address internal erin = makeAddr("lifecycleErin");

    ResolverRegistryFacet internal registryFacet;
    EveIdentity internal identity;
    ParimutuelShareToken internal parimutuelShareToken;
    EvesPositionManager internal outcomePositions;

    function setUp() public override {
        super.setUp();

        parimutuelShareToken = new ParimutuelShareToken(address(diamond), "uri://resolver-parimutuel/{id}");
        outcomePositions = new EvesPositionManager(address(diamond), "");

        _addFacet(address(new ParimutuelFacet()), _parimutuelSelectors());
        _addFacet(address(new ParimutuelViewFacet()), _parimutuelViewSelectors());
        _addFacet(address(new MultiOutcomeOrderbookFacet()), _multiOutcomeSelectors());
        _addFacet(address(new MultiOutcomeOrderbookViewFacet()), _multiOutcomeViewSelectors());
        _addFacet(address(ownershipFacet), _evesPositionManagerSelector());
        _addFacet(address(ownershipFacet), _resolverOwnershipSelectors());
        _addResolverRegistryAndIdentity();
        _configureResolverJury();

        vm.startPrank(owner);
        OwnershipFacet(address(diamond)).setParimutuelFeeSplit(500, 1_000, 8_500, 0, 0);
        OwnershipFacet(address(diamond)).setParimutuelConfig(address(parimutuelShareToken), 250, 1e6);
        OwnershipFacet(address(diamond)).setParimutuelCreationSeedAmount(0);
        OwnershipFacet(address(diamond)).setEvesPositionManager(address(outcomePositions));
        vm.stopPrank();
    }

    function test_CLOBDisputeRunsThroughJuryAndSettlement() public {
        address closer = makeAddr("juryCloser");
        ResolverAccount memory aliceResolver = _activateResolver(alice);
        ResolverAccount memory bobResolver = _activateResolver(bob);
        ResolverAccount memory carolResolver = _activateResolver(carol);
        (bytes32 marketId,) = _createPendingMarket("Lifecycle CLOB", "resolver", 9 days);
        ExpectedMarketData memory expected = _expectedFromStored(marketId);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(marketId, uint8(LibEveMarket.MarketOutcome.Yes));

        vm.prank(challengerOne);
        IOBRResolutionFacet(address(diamond)).disputeResolution(marketId, uint8(LibEveMarket.MarketOutcome.No));

        vm.prank(challengerTwo);
        IOBRResolutionFacet(address(diamond)).disputeResolution(marketId, uint8(LibEveMarket.MarketOutcome.Invalid));

        vm.prank(challengerThree);
        IOBRResolutionFacet(address(diamond)).disputeResolution(marketId, uint8(LibEveMarket.MarketOutcome.Yes));

        bytes32 disputeId = _disputeIdForMarket(marketId);
        _runRandomness(disputeId, aliceResolver, bobResolver);
        IResolverJuryFacet(address(diamond)).selectCommittee(disputeId);

        _commitVote(disputeId, aliceResolver, uint8(LibEveMarket.MarketOutcome.Yes), keccak256("alice-lifecycle-vote"));
        _commitVote(disputeId, bobResolver, uint8(LibEveMarket.MarketOutcome.Yes), keccak256("bob-lifecycle-vote"));
        _commitVote(disputeId, carolResolver, uint8(LibEveMarket.MarketOutcome.No), keccak256("carol-lifecycle-vote"));

        vm.warp(block.timestamp + 1 hours);
        IResolverJuryFacet(address(diamond)).closeCommit(disputeId);

        _revealVote(disputeId, aliceResolver, uint8(LibEveMarket.MarketOutcome.Yes), keccak256("alice-lifecycle-vote"));
        _revealVote(disputeId, bobResolver, uint8(LibEveMarket.MarketOutcome.Yes), keccak256("bob-lifecycle-vote"));
        _revealVote(disputeId, carolResolver, uint8(LibEveMarket.MarketOutcome.No), keccak256("carol-lifecycle-vote"));

        vm.warp(block.timestamp + 1 hours);
        IResolverJuryFacet(address(diamond)).closeRevealAndTally(disputeId);

        IResolverJuryFacet.DisputeView memory appealView = IResolverJuryFacet(address(diamond)).disputeView(disputeId);
        assertEq(appealView.state, uint8(LibResolverJury.DisputeState.AppealOpen));
        assertEq(appealView.provisionalResult, uint8(LibEveMarket.MarketOutcome.Yes));
        assertEq(appealView.validRevealCount, 3);

        vm.warp(appealView.appealDeadline);
        vm.prank(closer);
        IResolverJuryFacet(address(diamond)).finalizeDispute(disputeId);

        IResolverJuryFacet.DisputeView memory finalView = IResolverJuryFacet(address(diamond)).disputeView(disputeId);
        assertTrue(finalView.finalized);
        assertTrue(finalView.rewardsDistributed);
        assertTrue(finalView.reputationApplied);
        assertEq(finalView.state, uint8(LibResolverJury.DisputeState.Finalized));
        assertEq(finalView.finalResult, uint8(LibEveMarket.MarketOutcome.Yes));

        _assertResolvedStatus(marketId, expected.marketId, uint8(LibEveMarket.MarketOutcome.Yes));
        _assertPayout(expected.conditionId, 1, 0, 1);
        assertEq(
            IResolverRegistryFacet(address(diamond)).resolverReputation(aliceResolver.identityId).finalAgreementCount, 1
        );
        assertEq(
            IResolverRegistryFacet(address(diamond)).resolverReputation(bobResolver.identityId).finalAgreementCount, 1
        );
        assertEq(
            IResolverRegistryFacet(address(diamond)).resolverReputation(carolResolver.identityId).finalAgreementCount, 0
        );
        assertEq(StateProbeFacet(address(diamond)).getBondedTotals(challengerThree), 0);
    }

    function test_OwnerCanEnableObrJuryModeAfterFullHealthyResolverSet() public {
        ResolutionHarnessFacet(address(diamond)).setResolutionMode(
            uint8(LibEveMarket.ResolutionMode.CreatorAdminBootstrap)
        );
        _activateResolver(alice);
        _activateResolver(bob);
        _activateResolver(carol);

        vm.expectEmit(false, false, false, true, address(diamond));
        emit Events.ResolutionModeSet(
            uint8(LibEveMarket.ResolutionMode.CreatorAdminBootstrap), uint8(LibEveMarket.ResolutionMode.ObrJury)
        );
        vm.prank(owner);
        OwnershipFacet(address(diamond)).setResolutionMode(uint8(LibEveMarket.ResolutionMode.ObrJury));

        assertEq(IOBRResolutionFacet(address(diamond)).resolutionMode(), uint8(LibEveMarket.ResolutionMode.ObrJury));
    }

    function test_ParimutuelDisputeRunsThroughJuryAndSettlement() public {
        (bytes32 marketId, uint64 expiryTime) =
            _createTradingParimutuelMarket("Lifecycle parimutuel", "resolver", 9 days);

        collateralToken.mint(trader, 1_000e6);
        vm.startPrank(trader);
        collateralToken.approve(address(diamond), 300e6);
        IParimutuelFacet(address(diamond)).buyShares(marketId, true, 100e6, trader, 0);
        IParimutuelFacet(address(diamond)).buyShares(marketId, false, 200e6, trader, 0);
        vm.stopPrank();

        (, uint128 totalNoShares, uint128 payoutPool,,,) =
            StateProbeFacet(address(diamond)).getStoredParimutuelPool(marketId);

        vm.warp(expiryTime);
        MarketFactoryFacet(address(diamond)).syncMarketState(marketId);

        bytes32 disputeId = _resolveMarketThroughJury(
            marketId,
            uint8(LibEveMarket.MarketOutcome.No),
            uint8(LibEveMarket.MarketOutcome.Yes),
            uint8(LibEveMarket.MarketOutcome.Invalid),
            uint8(LibEveMarket.MarketOutcome.No)
        );

        IResolverJuryFacet.DisputeView memory finalView = IResolverJuryFacet(address(diamond)).disputeView(disputeId);
        assertTrue(finalView.finalized);
        assertEq(finalView.finalResult, uint8(LibEveMarket.MarketOutcome.No));
        _assertResolvedStatus(marketId, marketId, uint8(LibEveMarket.MarketOutcome.No));
        _assertParimutuelFinalization(
            marketId,
            uint8(LibEveMarket.MarketOutcome.No),
            uint8(LibEveMarket.MarketOutcome.No),
            payoutPool,
            totalNoShares
        );
    }

    function test_MultiOutcomeDisputeRunsThroughJuryAndSettlement() public {
        bytes32 marketId = _createPendingMultiOutcomeMarket("Lifecycle multi outcome", "resolver", 9 days);
        uint8 finalOutcome = 1;

        bytes32 disputeId = _resolveMarketThroughJury(marketId, finalOutcome, 0, 2, finalOutcome);

        IResolverJuryFacet.DisputeView memory finalView = IResolverJuryFacet(address(diamond)).disputeView(disputeId);
        assertTrue(finalView.finalized);
        assertTrue(finalView.isMultiOutcome);
        assertEq(finalView.outcomeCount, 3);
        assertEq(finalView.finalResult, finalOutcome);
        _assertResolvedStatus(marketId, marketId, uint8(LibEveMarket.MarketOutcome.Unresolved));

        IMultiOutcomeOrderbookFacet.MultiOutcomeMarketView memory multi =
            IMultiOutcomeOrderbookFacet(address(diamond)).getMultiOutcomeMarket(marketId);
        assertTrue(multi.resolved);
        assertFalse(multi.invalid);
        assertEq(multi.resolvedOutcome, finalOutcome);
        assertEq(multi.payoutDenominator, 1);
    }

    function test_MultiRoundAppealRoutesRealBondsWithFundConservation() public {
        _configureResolverJuryForAppeal();
        ResolverAccount memory aliceResolver = _activateResolver(alice);
        ResolverAccount memory bobResolver = _activateResolver(bob);
        _activateResolver(carol);
        _activateResolver(dave);
        _activateResolver(erin);

        (bytes32 marketId,) = _createPendingMarket("Lifecycle appeal", "resolver", 9 days);
        _openJuryDispute(
            marketId,
            uint8(LibEveMarket.MarketOutcome.Yes),
            uint8(LibEveMarket.MarketOutcome.No),
            uint8(LibEveMarket.MarketOutcome.Invalid),
            uint8(LibEveMarket.MarketOutcome.Yes)
        );

        bytes32 disputeId = _disputeIdForMarket(marketId);
        _runRandomness(disputeId, aliceResolver, bobResolver);
        _resolveSelectedCommittee(disputeId, uint8(LibEveMarket.MarketOutcome.Yes), keccak256("appeal-round-zero"));

        IResolverJuryFacet.DisputeView memory round0 = IResolverJuryFacet(address(diamond)).disputeView(disputeId);
        assertEq(round0.currentRound, 0);
        assertEq(round0.provisionalResult, uint8(LibEveMarket.MarketOutcome.Yes));

        uint128 appealBond = uint128((uint256(round0.disputeBondBase) * 20_000 + 9_999) / 10_000);
        eveToken.mint(trader, appealBond);
        vm.prank(trader);
        eveToken.approve(address(diamond), appealBond);
        vm.prank(trader);
        IResolverJuryFacet(address(diamond)).openAppeal(disputeId);

        _runRandomness(disputeId, aliceResolver, bobResolver);
        _resolveSelectedCommittee(disputeId, uint8(LibEveMarket.MarketOutcome.No), keccak256("appeal-round-one"));

        IResolverJuryFacet.DisputeView memory round1 = IResolverJuryFacet(address(diamond)).disputeView(disputeId);
        assertEq(round1.currentRound, 1);
        assertEq(round1.provisionalResult, uint8(LibEveMarket.MarketOutcome.No));

        address[] memory tracked = _appealConservationAccounts();
        uint256 diamondBefore = eveToken.balanceOf(address(diamond));
        uint256 externalBefore = _sumBalances(tracked);
        uint256 appellantBefore = eveToken.balanceOf(trader);

        vm.warp(round1.appealDeadline);
        IResolverJuryFacet(address(diamond)).finalizeDispute(disputeId);

        uint256 diamondDecrease = diamondBefore - eveToken.balanceOf(address(diamond));
        uint256 externalIncrease = _sumBalances(tracked) - externalBefore;
        assertEq(externalIncrease, diamondDecrease);
        assertEq(eveToken.balanceOf(trader) - appellantBefore, (uint256(appealBond) * 7_000) / 10_000);
        assertEq(StateProbeFacet(address(diamond)).getBondedTotals(challengerOne), 0);
        assertEq(StateProbeFacet(address(diamond)).getBondedTotals(challengerTwo), 0);
        assertEq(StateProbeFacet(address(diamond)).getBondedTotals(challengerThree), 0);

        IResolverJuryFacet.DisputeView memory finalView = IResolverJuryFacet(address(diamond)).disputeView(disputeId);
        assertTrue(finalView.finalized);
        assertEq(finalView.finalResult, uint8(LibEveMarket.MarketOutcome.No));
        _assertResolvedStatus(marketId, marketId, uint8(LibEveMarket.MarketOutcome.No));
    }

    function test_NativeRandomnessRetryAndAllEligibleFallbackIntegration() public {
        ResolverAccount memory aliceResolver = _activateResolver(alice);
        ResolverAccount memory bobResolver = _activateResolver(bob);
        _activateResolver(carol);

        (bytes32 retryMarketId,) = _createPendingMarket("Lifecycle randomness retry", "resolver", 9 days);
        _openJuryDispute(
            retryMarketId,
            uint8(LibEveMarket.MarketOutcome.Yes),
            uint8(LibEveMarket.MarketOutcome.No),
            uint8(LibEveMarket.MarketOutcome.Invalid),
            uint8(LibEveMarket.MarketOutcome.Yes)
        );
        bytes32 retryDisputeId = _disputeIdForMarket(retryMarketId);

        IResolverJuryFacet(address(diamond)).openRandomnessCommit(retryDisputeId);
        _commitRandomness(retryDisputeId, aliceResolver, keccak256("retry-value"), keccak256("retry-salt"));
        vm.warp(block.timestamp + 1 hours);
        IResolverJuryFacet(address(diamond)).closeRandomnessCommit(retryDisputeId);
        _revealRandomness(retryDisputeId, aliceResolver, keccak256("retry-value"), keccak256("retry-salt"));
        vm.roll(block.number + 2);
        vm.warp(block.timestamp + 1 hours);
        IResolverJuryFacet(address(diamond)).closeRandomnessReveal(retryDisputeId);

        IResolverJuryFacet.DisputeView memory retryView =
            IResolverJuryFacet(address(diamond)).disputeView(retryDisputeId);
        assertEq(retryView.randomnessAttempt, 2);
        assertEq(retryView.validRevealCount, 0);
        assertEq(retryView.seed, bytes32(0));
        assertGt(retryView.randomnessCommitDeadline, block.timestamp);

        _finishOpenRandomnessAttempt(retryDisputeId, aliceResolver, bobResolver);
        retryView = IResolverJuryFacet(address(diamond)).disputeView(retryDisputeId);
        assertGt(uint256(retryView.seed), 0);
        assertFalse(retryView.allEligibleFallback);

        _setRandomnessFailureMode(LibEveMarket.RandomnessFailureMode.AllEligible);
        (bytes32 allEligibleMarketId,) = _createPendingMarket("Lifecycle randomness all eligible", "resolver", 10 days);
        _openJuryDispute(
            allEligibleMarketId,
            uint8(LibEveMarket.MarketOutcome.Yes),
            uint8(LibEveMarket.MarketOutcome.No),
            uint8(LibEveMarket.MarketOutcome.Invalid),
            uint8(LibEveMarket.MarketOutcome.Yes)
        );
        bytes32 allEligibleDisputeId = _disputeIdForMarket(allEligibleMarketId);

        IResolverJuryFacet(address(diamond)).openRandomnessCommit(allEligibleDisputeId);
        vm.warp(block.timestamp + 1 hours);
        IResolverJuryFacet(address(diamond)).closeRandomnessCommit(allEligibleDisputeId);
        vm.warp(block.timestamp + 1 hours);
        IResolverJuryFacet(address(diamond)).closeRandomnessReveal(allEligibleDisputeId);

        IResolverJuryFacet.DisputeView memory fallbackView =
            IResolverJuryFacet(address(diamond)).disputeView(allEligibleDisputeId);
        assertTrue(fallbackView.allEligibleFallback);

        IResolverJuryFacet(address(diamond)).selectCommittee(allEligibleDisputeId);
        uint256[] memory selected = IResolverJuryFacet(address(diamond)).committeeMembers(allEligibleDisputeId, 0);
        assertEq(selected.length, 3);
    }

    function test_EventAndReadApiSurfaceExposesDisputeAndProfileHistory() public {
        ResolverAccount memory aliceResolver = _activateResolver(alice);
        ResolverAccount memory bobResolver = _activateResolver(bob);
        ResolverAccount memory carolResolver = _activateResolver(carol);
        (bytes32 marketId,) = _createPendingMarket("Lifecycle read api", "resolver", 9 days);
        bytes32 disputeId = _disputeIdForMarket(marketId);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(marketId, uint8(LibEveMarket.MarketOutcome.Yes));
        vm.prank(challengerOne);
        IOBRResolutionFacet(address(diamond)).disputeResolution(marketId, uint8(LibEveMarket.MarketOutcome.No));
        vm.prank(challengerTwo);
        IOBRResolutionFacet(address(diamond)).disputeResolution(marketId, uint8(LibEveMarket.MarketOutcome.Invalid));
        vm.expectEmit(true, true, false, true);
        emit Events.ResolverJuryInitiated(disputeId, marketId, 0);
        vm.prank(challengerThree);
        IOBRResolutionFacet(address(diamond)).disputeResolution(marketId, uint8(LibEveMarket.MarketOutcome.Yes));

        IResolverJuryFacet(address(diamond)).openRandomnessCommit(disputeId);
        vm.expectEmit(true, true, true, true);
        emit Events.RandomnessCommitted(disputeId, 0, aliceResolver.identityId);
        _commitRandomness(disputeId, aliceResolver, keccak256("read-alice-random"), keccak256("read-alice-salt"));
        _commitRandomness(disputeId, bobResolver, keccak256("read-bob-random"), keccak256("read-bob-salt"));

        vm.warp(block.timestamp + 1 hours);
        IResolverJuryFacet(address(diamond)).closeRandomnessCommit(disputeId);
        uint256 referenceBlock = block.number + 1;
        vm.expectEmit(true, true, true, true);
        emit Events.RandomnessRevealed(disputeId, 0, aliceResolver.identityId);
        _revealRandomness(disputeId, aliceResolver, keccak256("read-alice-random"), keccak256("read-alice-salt"));
        _revealRandomness(disputeId, bobResolver, keccak256("read-bob-random"), keccak256("read-bob-salt"));

        vm.roll(referenceBlock + 1);
        vm.warp(block.timestamp + 1 hours);
        IResolverJuryFacet(address(diamond)).closeRandomnessReveal(disputeId);

        vm.expectEmit(true, true, false, false);
        emit Events.CommitteeSelected(disputeId, 0, 3, bytes32(0), new uint256[](0));
        IResolverJuryFacet(address(diamond)).selectCommittee(disputeId);
        uint256[] memory selected = IResolverJuryFacet(address(diamond)).committeeMembers(disputeId, 0);
        assertEq(selected.length, 3);

        vm.expectEmit(true, true, true, true);
        emit Events.VoteCommitted(disputeId, 0, aliceResolver.identityId);
        _commitVote(disputeId, aliceResolver, uint8(LibEveMarket.MarketOutcome.Yes), keccak256("read-alice-vote"));
        _commitVote(disputeId, bobResolver, uint8(LibEveMarket.MarketOutcome.Yes), keccak256("read-bob-vote"));
        _commitVote(disputeId, carolResolver, uint8(LibEveMarket.MarketOutcome.No), keccak256("read-carol-vote"));

        vm.warp(block.timestamp + 1 hours);
        IResolverJuryFacet(address(diamond)).closeCommit(disputeId);

        vm.expectEmit(true, true, true, true);
        emit Events.VoteRevealed(disputeId, 0, aliceResolver.identityId, uint8(LibEveMarket.MarketOutcome.Yes));
        _revealVote(disputeId, aliceResolver, uint8(LibEveMarket.MarketOutcome.Yes), keccak256("read-alice-vote"));
        _revealVote(disputeId, bobResolver, uint8(LibEveMarket.MarketOutcome.Yes), keccak256("read-bob-vote"));

        vm.warp(block.timestamp + 1 hours);
        vm.expectEmit(true, true, true, true);
        emit Events.ResolverSlashed(disputeId, 0, carolResolver.identityId, 20e18);
        IResolverJuryFacet(address(diamond)).closeRevealAndTally(disputeId);

        IResolverJuryFacet.DisputeView memory appealView = IResolverJuryFacet(address(diamond)).disputeView(disputeId);
        assertEq(appealView.state, uint8(LibResolverJury.DisputeState.AppealOpen));
        assertEq(appealView.committeeSize, 3);
        assertEq(appealView.validRevealCount, 2);
        assertEq(appealView.provisionalResult, uint8(LibEveMarket.MarketOutcome.Yes));
        assertGt(appealView.appealDeadline, block.timestamp);

        (bool revealed, uint8 revealedOutcome) =
            IResolverJuryFacet(address(diamond)).revealedVote(disputeId, 0, aliceResolver.identityId);
        assertTrue(revealed);
        assertEq(revealedOutcome, uint8(LibEveMarket.MarketOutcome.Yes));

        (uint8[] memory outcomes, uint256[] memory counts) =
            IResolverJuryFacet(address(diamond)).outcomeTally(disputeId, 0);
        assertEq(outcomes.length, 3);
        assertEq(counts[0], 2);
        assertEq(counts[1], 0);
        assertEq(counts[2], 0);
        assertEq(IResolverRegistryFacet(address(diamond)).resolverReputation(aliceResolver.identityId).revealCount, 1);
        assertEq(
            IResolverRegistryFacet(address(diamond)).resolverReputation(carolResolver.identityId).missedRevealCount, 1
        );

        vm.warp(appealView.appealDeadline);
        IResolverJuryFacet(address(diamond)).finalizeDispute(disputeId);
        IResolverJuryFacet.DisputeView memory finalView = IResolverJuryFacet(address(diamond)).disputeView(disputeId);
        assertTrue(finalView.finalized);
        assertEq(finalView.finalResult, uint8(LibEveMarket.MarketOutcome.Yes));
        assertEq(
            IResolverRegistryFacet(address(diamond)).resolverReputation(aliceResolver.identityId).finalAgreementCount, 1
        );
    }

    struct ResolverAccount {
        address owner;
        uint256 identityId;
    }

    function _addResolverRegistryAndIdentity() internal {
        registryFacet = new ResolverRegistryFacet();
        identity = new EveIdentity(address(diamond), "Eve Identity", "EVE-ID");

        DiamondCutFacet.FacetCut[] memory cuts = new DiamondCutFacet.FacetCut[](1);
        cuts[0] = DiamondCutFacet.FacetCut({
            facetAddress: address(registryFacet),
            action: DiamondCutFacet.FacetCutAction.Add,
            functionSelectors: _resolverRegistrySelectors()
        });

        ResolverJuryInit init = new ResolverJuryInit();

        vm.prank(owner);
        DiamondCutFacet(address(diamond))
            .diamondCut(cuts, address(init), abi.encodeCall(ResolverJuryInit.initResolverJury, (address(identity))));
    }

    function _configureResolverJury() internal {
        uint16[] memory committeeSizes = new uint16[](1);
        committeeSizes[0] = 3;

        vm.startPrank(owner);
        OwnershipFacet(address(diamond))
            .setResolverJuryIdentitySettings(
                OwnershipConfigTypes.ResolverJuryIdentitySettings({
                    identityMintFeeToken: address(0),
                    identityMintFee: 0,
                    resolverSeatStake: 100e18,
                    epochCandidateFeeToken: address(0),
                    epochCandidateFeeAmount: 0
                })
            );
        OwnershipFacet(address(diamond))
            .setResolverJuryPoolSettings(
                OwnershipConfigTypes.ResolverJuryPoolSettings({
                    activeEpochSize: 3,
                    resolverEpochDuration: 180 days,
                    resolverRotationWindow: 30 days,
                    epochRandomnessCommitDuration: 1 days,
                    epochRandomnessRevealDuration: 1 days,
                    epochSelectionDuration: 1 days,
                    minEpochRandomnessReveals: 1,
                    activationDelay: 0,
                    exitCooldown: 1 days,
                    participationThresholdBps: 0,
                    concurrencyLimit: 3,
                    participationGraceCount: 5,
                    conflictPositionThreshold: 0
                })
            );
        OwnershipFacet(address(diamond))
            .setResolverJuryRoundSettings(
                OwnershipConfigTypes.ResolverJuryRoundSettings({
                    committeeSizesByRound: committeeSizes,
                    maxAppealRounds: 0,
                    appealBondMultiplierBps: 20_000,
                    randomnessCommitDuration: 1 hours,
                    randomnessRevealDuration: 1 hours,
                    commitDuration: 1 hours,
                    revealDuration: 1 hours,
                    appealWindow: 1 hours,
                    randomnessTimeout: 5 minutes,
                    quorum: 2,
                    redrawLimit: 0,
                    lowQuorumMode: LibEveMarket.LowQuorumMode.FinalizeInvalid,
                    tieBreakMode: LibEveMarket.TieBreakMode.ResolveInvalid,
                    randomnessFailureMode: LibEveMarket.RandomnessFailureMode.Retry,
                    minRandomnessReveals: 2,
                    allEligibleFallbackCap: 3
                })
            );
        OwnershipFacet(address(diamond))
            .setResolverJuryEconomicsSettings(
                OwnershipConfigTypes.ResolverJuryEconomicsSettings({
                    missedCommitSlashBps: 1_000,
                    missedRevealSlashBps: 2_000,
                    invalidRevealSlashBps: 3_000,
                    slashCooldown: 1 days,
                    protocolFeeAllocationBps: 0,
                    appealSuccessRoutingBps: [uint16(7_000), uint16(1_000), uint16(1_000), uint16(1_000)],
                    appealFailureRoutingBps: [uint16(4_000), uint16(3_000), uint16(3_000)],
                    incentiveSelectCommittee: 0,
                    incentiveCloseCommit: 0,
                    incentiveCloseReveal: 0,
                    incentiveOpenAppeal: 0,
                    incentiveFinalize: 0,
                    incentiveRandomness: 0
                })
            );
        vm.stopPrank();
    }

    function _configureResolverJuryForAppeal() internal {
        uint16[] memory committeeSizes = new uint16[](2);
        committeeSizes[0] = 3;
        committeeSizes[1] = 5;

        vm.startPrank(owner);
        OwnershipFacet(address(diamond))
            .setResolverJuryPoolSettings(
                OwnershipConfigTypes.ResolverJuryPoolSettings({
                    activeEpochSize: 5,
                    resolverEpochDuration: 180 days,
                    resolverRotationWindow: 30 days,
                    epochRandomnessCommitDuration: 1 days,
                    epochRandomnessRevealDuration: 1 days,
                    epochSelectionDuration: 1 days,
                    minEpochRandomnessReveals: 1,
                    activationDelay: 0,
                    exitCooldown: 1 days,
                    participationThresholdBps: 0,
                    concurrencyLimit: 5,
                    participationGraceCount: 5,
                    conflictPositionThreshold: 0
                })
            );
        OwnershipFacet(address(diamond))
            .setResolverJuryRoundSettings(
                OwnershipConfigTypes.ResolverJuryRoundSettings({
                    committeeSizesByRound: committeeSizes,
                    maxAppealRounds: 1,
                    appealBondMultiplierBps: 20_000,
                    randomnessCommitDuration: 1 hours,
                    randomnessRevealDuration: 1 hours,
                    commitDuration: 1 hours,
                    revealDuration: 1 hours,
                    appealWindow: 1 hours,
                    randomnessTimeout: 5 minutes,
                    quorum: 2,
                    redrawLimit: 0,
                    lowQuorumMode: LibEveMarket.LowQuorumMode.FinalizeInvalid,
                    tieBreakMode: LibEveMarket.TieBreakMode.ResolveInvalid,
                    randomnessFailureMode: LibEveMarket.RandomnessFailureMode.Retry,
                    minRandomnessReveals: 2,
                    allEligibleFallbackCap: 5
                })
            );
        vm.stopPrank();
    }

    function _setRandomnessFailureMode(LibEveMarket.RandomnessFailureMode mode) internal {
        uint16[] memory committeeSizes = new uint16[](1);
        committeeSizes[0] = 3;

        vm.prank(owner);
        OwnershipFacet(address(diamond))
            .setResolverJuryRoundSettings(
                OwnershipConfigTypes.ResolverJuryRoundSettings({
                    committeeSizesByRound: committeeSizes,
                    maxAppealRounds: 0,
                    appealBondMultiplierBps: 20_000,
                    randomnessCommitDuration: 1 hours,
                    randomnessRevealDuration: 1 hours,
                    commitDuration: 1 hours,
                    revealDuration: 1 hours,
                    appealWindow: 1 hours,
                    randomnessTimeout: 5 minutes,
                    quorum: 2,
                    redrawLimit: 0,
                    lowQuorumMode: LibEveMarket.LowQuorumMode.FinalizeInvalid,
                    tieBreakMode: LibEveMarket.TieBreakMode.ResolveInvalid,
                    randomnessFailureMode: mode,
                    minRandomnessReveals: 2,
                    allEligibleFallbackCap: 3
                })
            );
    }

    function _activateResolver(address account) internal returns (ResolverAccount memory resolver) {
        resolver.owner = account;

        vm.prank(account);
        resolver.identityId = IResolverRegistryFacet(address(diamond)).mintIdentity();

        vm.prank(account);
        IResolverRegistryFacet(address(diamond)).setResolverRole(true);

        eveToken.mint(account, 100e18);
        vm.prank(account);
        eveToken.approve(address(diamond), 100e18);

        vm.prank(account);
        IResolverRegistryFacet(address(diamond)).depositResolverStake(100e18);

        _seedActiveResolverEpochMember(resolver.identityId);
    }

    function _seedActiveResolverEpochMember(uint256 identityId) internal {
        // Synthetic setup: launch-flow tests need active jurors before exercising
        // settlement lifecycles; ResolverRegistry.t.sol covers the real epoch flow.
        bytes32 root = bytes32(uint256(keccak256("eve.resolver.identity.jury.storage")) - 1);
        vm.store(address(diamond), bytes32(uint256(root) + 6), bytes32(uint256(1)));

        bytes32 epochSlot = keccak256(abi.encode(uint64(1), bytes32(uint256(root) + 7)));
        bytes32 activeSetSlot = bytes32(uint256(epochSlot) + 6);
        bytes32 activeIndexSlot = keccak256(abi.encode(identityId, bytes32(uint256(epochSlot) + 9)));
        if (uint256(vm.load(address(diamond), activeIndexSlot)) == 0) {
            uint256 length = uint256(vm.load(address(diamond), activeSetSlot));
            vm.store(address(diamond), activeSetSlot, bytes32(length + 1));
            bytes32 activeElementSlot = bytes32(uint256(keccak256(abi.encode(activeSetSlot))) + length);
            vm.store(address(diamond), activeElementSlot, bytes32(identityId));
            vm.store(address(diamond), activeIndexSlot, bytes32(length + 1));
        }

        bytes32 identitySlot = keccak256(abi.encode(identityId, bytes32(uint256(root) + 2)));
        vm.store(
            address(diamond),
            bytes32(uint256(identitySlot) + 1),
            bytes32(uint256(uint8(LibResolverJury.ResolverLifecycle.ResolverActive)))
        );
    }

    function _resolveMarketThroughJury(
        bytes32 marketId,
        uint8 creatorOutcome,
        uint8 firstCounterOutcome,
        uint8 secondCounterOutcome,
        uint8 finalOutcome
    ) internal returns (bytes32 disputeId) {
        ResolverAccount memory aliceResolver = _activateResolver(alice);
        ResolverAccount memory bobResolver = _activateResolver(bob);
        ResolverAccount memory carolResolver = _activateResolver(carol);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(marketId, creatorOutcome);

        vm.prank(challengerOne);
        IOBRResolutionFacet(address(diamond)).disputeResolution(marketId, firstCounterOutcome);

        vm.prank(challengerTwo);
        IOBRResolutionFacet(address(diamond)).disputeResolution(marketId, secondCounterOutcome);

        vm.prank(challengerThree);
        IOBRResolutionFacet(address(diamond)).disputeResolution(marketId, finalOutcome);

        disputeId = _disputeIdForMarket(marketId);
        _runRandomness(disputeId, aliceResolver, bobResolver);
        IResolverJuryFacet(address(diamond)).selectCommittee(disputeId);

        _commitVote(disputeId, aliceResolver, finalOutcome, keccak256("alice-lifecycle-vote"));
        _commitVote(disputeId, bobResolver, finalOutcome, keccak256("bob-lifecycle-vote"));
        _commitVote(disputeId, carolResolver, firstCounterOutcome, keccak256("carol-lifecycle-vote"));

        vm.warp(block.timestamp + 1 hours);
        IResolverJuryFacet(address(diamond)).closeCommit(disputeId);

        _revealVote(disputeId, aliceResolver, finalOutcome, keccak256("alice-lifecycle-vote"));
        _revealVote(disputeId, bobResolver, finalOutcome, keccak256("bob-lifecycle-vote"));
        _revealVote(disputeId, carolResolver, firstCounterOutcome, keccak256("carol-lifecycle-vote"));

        vm.warp(block.timestamp + 1 hours);
        IResolverJuryFacet(address(diamond)).closeRevealAndTally(disputeId);

        IResolverJuryFacet.DisputeView memory appealView = IResolverJuryFacet(address(diamond)).disputeView(disputeId);
        assertEq(appealView.state, uint8(LibResolverJury.DisputeState.AppealOpen));
        assertEq(appealView.provisionalResult, finalOutcome);
        assertEq(appealView.validRevealCount, 3);

        vm.warp(appealView.appealDeadline);
        IResolverJuryFacet(address(diamond)).finalizeDispute(disputeId);
    }

    function _openJuryDispute(
        bytes32 marketId,
        uint8 creatorOutcome,
        uint8 firstCounterOutcome,
        uint8 secondCounterOutcome,
        uint8 finalCounterOutcome
    ) internal {
        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(marketId, creatorOutcome);

        vm.prank(challengerOne);
        IOBRResolutionFacet(address(diamond)).disputeResolution(marketId, firstCounterOutcome);

        vm.prank(challengerTwo);
        IOBRResolutionFacet(address(diamond)).disputeResolution(marketId, secondCounterOutcome);

        vm.prank(challengerThree);
        IOBRResolutionFacet(address(diamond)).disputeResolution(marketId, finalCounterOutcome);
    }

    function _resolveSelectedCommittee(bytes32 disputeId, uint8 outcome, bytes32 salt) internal {
        IResolverJuryFacet(address(diamond)).selectCommittee(disputeId);
        IResolverJuryFacet.DisputeView memory view_ = IResolverJuryFacet(address(diamond)).disputeView(disputeId);
        uint256[] memory members = IResolverJuryFacet(address(diamond)).committeeMembers(disputeId, view_.currentRound);

        for (uint256 index; index < members.length; ++index) {
            _commitVote(
                disputeId,
                ResolverAccount({owner: identity.ownerOf(members[index]), identityId: members[index]}),
                outcome,
                keccak256(abi.encode(salt, members[index]))
            );
        }

        vm.warp(block.timestamp + 1 hours);
        IResolverJuryFacet(address(diamond)).closeCommit(disputeId);

        for (uint256 index; index < members.length; ++index) {
            _revealVote(
                disputeId,
                ResolverAccount({owner: identity.ownerOf(members[index]), identityId: members[index]}),
                outcome,
                keccak256(abi.encode(salt, members[index]))
            );
        }

        vm.warp(block.timestamp + 1 hours);
        IResolverJuryFacet(address(diamond)).closeRevealAndTally(disputeId);
    }

    function _runRandomness(bytes32 disputeId, ResolverAccount memory first, ResolverAccount memory second) internal {
        bytes32 firstValue = keccak256("first-randomness-value");
        bytes32 secondValue = keccak256("second-randomness-value");
        bytes32 firstSalt = keccak256("first-randomness-salt");
        bytes32 secondSalt = keccak256("second-randomness-salt");

        IResolverJuryFacet(address(diamond)).openRandomnessCommit(disputeId);

        vm.prank(first.owner);
        IResolverJuryFacet(address(diamond))
            .commitRandomness(disputeId, keccak256(abi.encode(disputeId, first.identityId, firstValue, firstSalt)));

        vm.prank(second.owner);
        IResolverJuryFacet(address(diamond))
            .commitRandomness(disputeId, keccak256(abi.encode(disputeId, second.identityId, secondValue, secondSalt)));

        vm.warp(block.timestamp + 1 hours);
        IResolverJuryFacet(address(diamond)).closeRandomnessCommit(disputeId);
        uint256 referenceBlock = block.number + 1;

        vm.prank(first.owner);
        IResolverJuryFacet(address(diamond)).revealRandomness(disputeId, firstValue, firstSalt);

        vm.prank(second.owner);
        IResolverJuryFacet(address(diamond)).revealRandomness(disputeId, secondValue, secondSalt);

        vm.roll(referenceBlock + 1);
        vm.warp(block.timestamp + 1 hours);
        IResolverJuryFacet(address(diamond)).closeRandomnessReveal(disputeId);

        IResolverJuryFacet.DisputeView memory view_ = IResolverJuryFacet(address(diamond)).disputeView(disputeId);
        assertEq(view_.validRevealCount, 2);
        assertTrue(view_.seed != bytes32(0));
    }

    function _finishOpenRandomnessAttempt(
        bytes32 disputeId,
        ResolverAccount memory first,
        ResolverAccount memory second
    ) internal {
        bytes32 firstValue = keccak256("retry-second-value");
        bytes32 secondValue = keccak256("retry-third-value");
        bytes32 firstSalt = keccak256("retry-second-salt");
        bytes32 secondSalt = keccak256("retry-third-salt");

        _commitRandomness(disputeId, first, firstValue, firstSalt);
        _commitRandomness(disputeId, second, secondValue, secondSalt);

        vm.warp(block.timestamp + 1 hours);
        IResolverJuryFacet(address(diamond)).closeRandomnessCommit(disputeId);
        uint256 referenceBlock = block.number + 1;

        _revealRandomness(disputeId, first, firstValue, firstSalt);
        _revealRandomness(disputeId, second, secondValue, secondSalt);

        vm.roll(referenceBlock + 1);
        vm.warp(block.timestamp + 1 hours);
        IResolverJuryFacet(address(diamond)).closeRandomnessReveal(disputeId);
    }

    function _commitRandomness(bytes32 disputeId, ResolverAccount memory resolver, bytes32 value, bytes32 salt)
        internal
    {
        vm.prank(resolver.owner);
        IResolverJuryFacet(address(diamond))
            .commitRandomness(disputeId, keccak256(abi.encode(disputeId, resolver.identityId, value, salt)));
    }

    function _revealRandomness(bytes32 disputeId, ResolverAccount memory resolver, bytes32 value, bytes32 salt)
        internal
    {
        vm.prank(resolver.owner);
        IResolverJuryFacet(address(diamond)).revealRandomness(disputeId, value, salt);
    }

    function _commitVote(bytes32 disputeId, ResolverAccount memory resolver, uint8 outcome, bytes32 salt) internal {
        vm.prank(resolver.owner);
        IResolverJuryFacet(address(diamond))
            .commitVote(disputeId, keccak256(abi.encode(disputeId, resolver.identityId, outcome, salt)));
    }

    function _revealVote(bytes32 disputeId, ResolverAccount memory resolver, uint8 outcome, bytes32 salt) internal {
        vm.prank(resolver.owner);
        IResolverJuryFacet(address(diamond)).revealVote(disputeId, outcome, salt);
    }

    function _createTradingParimutuelMarket(string memory question, string memory category, uint64 duration)
        internal
        returns (bytes32 marketId, uint64 expiryTime)
    {
        expiryTime = uint64(block.timestamp) + duration;
        _approveCreator(0);

        vm.prank(creator);
        marketId = IParimutuelFacet(address(diamond))
            .createParimutuelMarket(
                question, category, DEFAULT_RESOLUTION_SOURCE, uint64(block.timestamp), expiryTime, 1 days
            );

        MarketFactoryFacet(address(diamond)).syncMarketState(marketId);
    }

    function _createPendingMultiOutcomeMarket(string memory question, string memory category, uint64 duration)
        internal
        returns (bytes32 marketId)
    {
        uint64 expiryTime = uint64(block.timestamp) + duration;
        _approveCreator(StateProbeFacet(address(diamond)).marketCreationFee());

        string[] memory outcomes = new string[](3);
        outcomes[0] = "Alpha";
        outcomes[1] = "Beta";
        outcomes[2] = "Gamma";

        vm.prank(creator);
        marketId = IMultiOutcomeOrderbookFacet(address(diamond))
            .createMultiOutcomeMarket(
                IMultiOutcomeOrderbookFacet.CreateMultiOutcomeMarketParams({
                    question: question,
                    category: category,
                    resolutionSource: DEFAULT_RESOLUTION_SOURCE,
                    tradingStartTime: uint64(block.timestamp),
                    expiryTime: expiryTime,
                    outcomes: outcomes,
                    display: _emptyMultiOutcomeDisplay(),
                    externalRef: _emptyMultiOutcomeExternalRef(),
                    outcomeDisplay: new IMultiOutcomeOrderbookFacet.OutcomeDisplayInput[](0)
                })
            );

        vm.warp(expiryTime);
        MarketFactoryFacet(address(diamond)).syncMarketState(marketId);
    }

    function _emptyMultiOutcomeDisplay() internal pure returns (MarketFactoryTypes.MarketDisplayInput memory display) {}

    function _emptyMultiOutcomeExternalRef()
        internal
        pure
        returns (MarketFactoryTypes.ExternalMarketRefInput memory externalRef)
    {}

    function _resolverOwnershipSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = OwnershipFacet.setResolverJuryIdentitySettings.selector;
        selectors[1] = OwnershipFacet.setResolverJuryPoolSettings.selector;
        selectors[2] = OwnershipFacet.setResolverJuryRoundSettings.selector;
        selectors[3] = OwnershipFacet.setResolverJuryEconomicsSettings.selector;
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
        selectors = new bytes4[](6);
        selectors[0] = IMultiOutcomeOrderbookFacet.getMultiOutcomeMarket.selector;
        selectors[1] = IMultiOutcomeOrderbookFacet.getMultiOutcomeOutcomes.selector;
        selectors[2] = IMultiOutcomeOrderbookFacet.getOutcomePositionId.selector;
        selectors[3] = IMultiOutcomeOrderbookFacet.getMultiOutcomeBooks.selector;
        selectors[4] = IMultiOutcomeOrderbookFacet.getMultiOutcomeTopOfBook.selector;
        selectors[5] = IMultiOutcomeOrderbookFacet.getMultiOutcomeDisplay.selector;
    }

    function _resolverRegistrySelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](23);
        selectors[0] = IResolverRegistryFacet.mintIdentity.selector;
        selectors[1] = IResolverRegistryFacet.setCreatorRole.selector;
        selectors[2] = IResolverRegistryFacet.setResolverRole.selector;
        selectors[3] = IResolverRegistryFacet.depositResolverStake.selector;
        selectors[4] = IResolverRegistryFacet.openResolverEpochRotation.selector;
        selectors[5] = IResolverRegistryFacet.requestResolverExit.selector;
        selectors[6] = IResolverRegistryFacet.withdrawResolverStake.selector;
        selectors[7] = IResolverRegistryFacet.eveIdentity.selector;
        selectors[8] = IResolverRegistryFacet.resolverDashboard.selector;
        selectors[9] = IResolverRegistryFacet.resolverIdentity.selector;
        selectors[10] = IResolverRegistryFacet.resolverIdentityByOwner.selector;
        selectors[11] = IResolverRegistryFacet.resolverJuryConfig.selector;
        selectors[12] = IResolverRegistryFacet.identityByOwner.selector;
        selectors[13] = IResolverRegistryFacet.isEligibleResolver.selector;
        selectors[14] = IResolverRegistryFacet.hasConflict.selector;
        selectors[15] = IResolverRegistryFacet.resolverLifecycleState.selector;
        selectors[16] = IResolverRegistryFacet.creatorReputation.selector;
        selectors[17] = IResolverRegistryFacet.resolverReputation.selector;
        selectors[18] = IResolverRegistryFacet.eligibleResolverCount.selector;
        selectors[19] = IResolverRegistryFacet.activeResolverCount.selector;
        selectors[20] = IResolverRegistryFacet.activeResolverEpochSize.selector;
        selectors[21] = IResolverRegistryFacet.activeResolverAt.selector;
        selectors[22] = IResolverRegistryFacet.applyFinalityReputation.selector;
    }

    function _disputeIdForMarket(bytes32 marketId) internal pure returns (bytes32 disputeId) {
        disputeId = keccak256(abi.encode(DISPUTE_DOMAIN, marketId));
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

    function _assertResolvedStatus(bytes32 marketId, bytes32 expectedMarketId, uint8 expectedOutcome) internal view {
        (bytes32 storedMarketId,,,,, uint8 outcome, uint8 state,) =
            StateProbeFacet(address(diamond)).getStoredMarketStatus(marketId);

        assertEq(storedMarketId, expectedMarketId);
        assertEq(outcome, expectedOutcome);
        assertEq(state, uint8(LibEveMarket.MarketState.Resolved));
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

    function _appealConservationAccounts() internal view returns (address[] memory accounts) {
        accounts = new address[](11);
        accounts[0] = creator;
        accounts[1] = challengerOne;
        accounts[2] = challengerTwo;
        accounts[3] = challengerThree;
        accounts[4] = trader;
        accounts[5] = treasury;
        accounts[6] = alice;
        accounts[7] = bob;
        accounts[8] = carol;
        accounts[9] = dave;
        accounts[10] = erin;
    }

    function _sumBalances(address[] memory accounts) internal view returns (uint256 total) {
        for (uint256 index; index < accounts.length; ++index) {
            total += eveToken.balanceOf(accounts[index]);
        }
    }

    function _assertParimutuelFinalization(
        bytes32 marketId,
        uint8 rawOutcome,
        uint8 effectiveOutcome,
        uint128 payoutPool,
        uint128 totalClaimableShares
    ) internal view {
        (
            uint8 rawResolvedOutcome,
            uint8 effectivePayoutOutcome,
            uint128 payoutPoolAtResolution,
            uint128 totalClaimableSharesAtResolution,
            bool finalized
        ) = StateProbeFacet(address(diamond)).getStoredParimutuelFinalization(marketId);

        assertTrue(finalized);
        assertEq(rawResolvedOutcome, rawOutcome);
        assertEq(effectivePayoutOutcome, effectiveOutcome);
        assertEq(payoutPoolAtResolution, payoutPool);
        assertEq(totalClaimableSharesAtResolution, totalClaimableShares);
    }
}
