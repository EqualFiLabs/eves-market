// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/// forge-config: default.fuzz.runs = 100

import {Test} from "../../lib/forge-std/src/Test.sol";

import {IResolverJuryFacet} from "src/interfaces/IResolverJuryFacet.sol";
import {Errors} from "src/libraries/Errors.sol";
import {LibEveMarket} from "src/libraries/LibEveMarket.sol";
import {LibMultiOutcome} from "src/libraries/LibMultiOutcome.sol";
import {LibResolverJury} from "src/libraries/LibResolverJury.sol";
import {ResolverJuryFacet} from "src/facets/ResolverJuryFacet.sol";
import {ResolverRegistryFacet} from "src/facets/ResolverRegistryFacet.sol";
import {EveIdentity} from "src/tokens/EveIdentity.sol";
import {MockEveToken} from "test/helpers/MockEveToken.sol";
import {MockUSDC} from "test/helpers/MockUSDC.sol";

contract ResolverJuryTallyPropertyHarness is ResolverJuryFacet, ResolverRegistryFacet {
    function configure(address eveIdentity, address mintFeeToken, address eveToken) external {
        LibResolverJury.store().eveIdentity = eveIdentity;
        LibEveMarket.MarketConfig storage config = LibEveMarket.store().config;
        config.eveToken = eveToken;
        config.bondToken = eveToken;
        config.eveTreasury = address(uint160(uint256(keccak256("resolver-tally-treasury"))));
        config.resolverJuryConfig.identityMintFeeToken = mintFeeToken;
        config.resolverJuryConfig.identityMintFee = 1e6;
        config.resolverJuryConfig.resolverSeatStake = 100e18;
        config.resolverJuryConfig.activeEpochSize = 16;
        config.resolverJuryConfig.participationGraceCount = 5;
        config.resolverJuryConfig.concurrencyLimit = 5;
        config.resolverJuryConfig.commitDuration = 1 hours;
        config.resolverJuryConfig.revealDuration = 1 hours;
        config.resolverJuryConfig.missedCommitSlashBps = 1_000;
        config.resolverJuryConfig.missedRevealSlashBps = 2_000;
        config.resolverJuryConfig.invalidRevealSlashBps = 3_000;
        config.resolverJuryConfig.slashCooldown = 1 days;
        delete config.resolverJuryConfig.committeeSizesByRound;
        config.resolverJuryConfig.committeeSizesByRound.push(3);
    }

    function configureTally(
        uint256 quorum,
        uint256 redrawLimit,
        uint256 lowQuorumMode,
        uint256 tieBreakMode,
        uint256 appealWindow
    ) external {
        if (
            quorum > type(uint32).max || redrawLimit > type(uint16).max
                || lowQuorumMode > uint256(type(LibEveMarket.LowQuorumMode).max)
                || tieBreakMode > uint256(type(LibEveMarket.TieBreakMode).max) || appealWindow > type(uint64).max
        ) {
            revert Errors.InvalidAmount(quorum);
        }

        LibEveMarket.ResolverJuryConfig storage config = LibEveMarket.store().config.resolverJuryConfig;
        config.quorum = uint32(quorum);
        config.redrawLimit = uint16(redrawLimit);
        config.lowQuorumMode = LibEveMarket.LowQuorumMode(lowQuorumMode);
        config.tieBreakMode = LibEveMarket.TieBreakMode(tieBreakMode);
        config.appealWindow = uint64(appealWindow);
    }

    function configurePhaseDurations(uint256 commitDuration, uint256 revealDuration) external {
        if (commitDuration > type(uint64).max || revealDuration > type(uint64).max) {
            revert Errors.InvalidAmount(commitDuration);
        }

        LibEveMarket.ResolverJuryConfig storage config = LibEveMarket.store().config.resolverJuryConfig;
        config.commitDuration = uint64(commitDuration);
        config.revealDuration = uint64(revealDuration);
    }

    function seedDisputedMarket(bytes32 marketId) external returns (bytes32 disputeId) {
        LibEveMarket.Market storage market = LibEveMarket.store().markets[marketId];
        market.marketId = marketId;
        market.marketType = LibEveMarket.MarketType.CLOB;
        market.state = LibEveMarket.MarketState.Disputed;
        disputeId = this.disputeIdForMarket(marketId);
        IResolverJuryFacet(address(this)).initiateDispute(marketId);
    }

    function seedMultiOutcomeDisputedMarket(bytes32 marketId, uint256 outcomeCount)
        external
        returns (bytes32 disputeId)
    {
        if (outcomeCount > type(uint8).max) {
            revert Errors.InvalidAmount(outcomeCount);
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Market storage market = state.markets[marketId];
        market.marketId = marketId;
        market.marketType = LibEveMarket.MarketType.MULTI_OUTCOME_ORDERBOOK;
        market.state = LibEveMarket.MarketState.Disputed;
        state.multiOutcomeMarkets[marketId].marketId = marketId;
        state.multiOutcomeMarkets[marketId].outcomeCount = uint8(outcomeCount);
        state.multiOutcomeMarkets[marketId].exists = true;
        disputeId = this.disputeIdForMarket(marketId);
        IResolverJuryFacet(address(this)).initiateDispute(marketId);
    }

    function seedSelectionReady(bytes32 disputeId, bytes32 seed) external {
        LibResolverJury.Dispute storage dispute = LibResolverJury.store().disputes[disputeId];
        dispute.rounds[dispute.currentRound].seed = seed == bytes32(0) ? keccak256("fallback-seed") : seed;
    }

    function seedActiveResolverEpochMember(uint256 identityId) external {
        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        jury.currentResolverEpoch = 1;
        LibResolverJury.ResolverEpoch storage epoch = jury.resolverEpochs[1];
        if (epoch.epochId == 0) {
            epoch.epochId = 1;
            epoch.startTime = uint64(block.timestamp);
            epoch.endTime = uint64(block.timestamp + 180 days);
            epoch.selectionFinalized = true;
        }
        if (epoch.activeIndex[identityId] == 0) {
            epoch.activeSet.push(identityId);
            epoch.activeIndex[identityId] = epoch.activeSet.length;
            epoch.compliantActiveCount += 1;
        }
        jury.identities[identityId].lifecycle = LibResolverJury.ResolverLifecycle.ResolverActive;
    }
}

contract ResolverJuryTallyPropertiesTest is Test {
    address internal alice = makeAddr("tally-alice");
    address internal bob = makeAddr("tally-bob");
    address internal carol = makeAddr("tally-carol");
    address internal dave = makeAddr("tally-dave");
    address internal erin = makeAddr("tally-erin");
    address internal frank = makeAddr("tally-frank");
    address internal outsider = makeAddr("tally-outsider");

    ResolverJuryTallyPropertyHarness internal jury;
    EveIdentity internal identity;
    MockUSDC internal feeToken;
    MockEveToken internal eveToken;

    function setUp() public {
        jury = new ResolverJuryTallyPropertyHarness();
        identity = new EveIdentity(address(jury), "Eve Identity", "EVE-ID");
        feeToken = new MockUSDC();
        eveToken = new MockEveToken();
        jury.configure(address(identity), address(feeToken), address(eveToken));
    }

    function testFuzz_CommitteeMembershipGatesAllVoting(bytes32 seed, bytes32 salt) public {
        _activateResolver(alice);
        _activateResolver(bob);
        _activateResolver(carol);
        bytes32 disputeId = _selectCommittee(seed, keccak256("membership-market"));
        uint256 outsiderId = _activateResolver(outsider);
        uint8 outcome = uint8(LibEveMarket.MarketOutcome.Yes);

        // Feature: resolver-identity-jury, Property 11: Committee membership gates all voting
        vm.expectRevert(abi.encodeWithSelector(Errors.NotCommitteeMember.selector, outsiderId));
        vm.prank(outsider);
        jury.commitVote(disputeId, keccak256(abi.encode(disputeId, outsiderId, outcome, salt)));

        vm.warp(block.timestamp + 1 hours);
        jury.closeCommit(disputeId);

        vm.expectRevert(abi.encodeWithSelector(Errors.NotCommitteeMember.selector, outsiderId));
        vm.prank(outsider);
        jury.revealVote(disputeId, outcome, salt);
    }

    function testFuzz_AtMostOneCountedVotePerIdentityFirstWins(bytes32 seed, bytes32 salt, bytes32 secondSalt) public {
        vm.assume(secondSalt != salt);
        uint256 aliceId = _activateResolver(alice);
        _activateResolver(bob);
        _activateResolver(carol);
        bytes32 disputeId = _selectCommittee(seed, keccak256("first-wins-market"));
        uint8 outcome = uint8(LibEveMarket.MarketOutcome.Yes);
        bytes32 firstCommitment = keccak256(abi.encode(disputeId, aliceId, outcome, salt));
        bytes32 secondCommitment = keccak256(abi.encode(disputeId, aliceId, outcome, secondSalt));

        // Feature: resolver-identity-jury, Property 12: At most one counted vote per identity per round (first wins)
        vm.prank(alice);
        jury.commitVote(disputeId, firstCommitment);
        vm.expectRevert(abi.encodeWithSelector(Errors.AlreadyCommitted.selector, aliceId));
        vm.prank(alice);
        jury.commitVote(disputeId, secondCommitment);

        vm.warp(block.timestamp + 1 hours);
        jury.closeCommit(disputeId);

        vm.prank(alice);
        jury.revealVote(disputeId, outcome, salt);
        vm.expectRevert(abi.encodeWithSelector(Errors.AlreadyRevealed.selector, aliceId));
        vm.prank(alice);
        jury.revealVote(disputeId, outcome, salt);

        (uint8[] memory outcomes, uint256[] memory counts) = jury.outcomeTally(disputeId, 0);
        assertEq(outcomes[0], outcome);
        assertEq(counts[0], 1);
        assertEq(jury.disputeView(disputeId).validRevealCount, 1);
    }

    function testFuzz_CommitRevealIntegrityAcrossBothEncodings(bytes32 binarySeed, bytes32 multiSeed, bytes32 salt)
        public
    {
        // Feature: resolver-identity-jury, Property 13: Commit-reveal integrity across both encodings
        _assertBinaryCommitRevealIntegrity(binarySeed, salt);
        _assertMultiOutcomeCommitRevealIntegrity(multiSeed, salt);
    }

    function _assertBinaryCommitRevealIntegrity(bytes32 seed, bytes32 salt) internal {
        uint256 aliceId = _activateResolver(alice);
        uint256 bobId = _activateResolver(bob);
        uint256 carolId = _activateResolver(carol);
        bytes32 disputeId = _selectCommittee(seed, keccak256("binary-integrity-market"));
        bytes32 aliceSalt = keccak256(abi.encode(salt, "binary-alice"));
        bytes32 bobSalt = keccak256(abi.encode(salt, "binary-bob"));
        bytes32 carolSalt = keccak256(abi.encode(salt, "binary-carol"));

        _commitVote(disputeId, alice, aliceId, uint8(LibEveMarket.MarketOutcome.Yes), aliceSalt);
        _commitVote(disputeId, bob, bobId, uint8(LibEveMarket.MarketOutcome.No), bobSalt);
        _commitVote(disputeId, carol, carolId, uint8(LibEveMarket.MarketOutcome.Unresolved), carolSalt);
        vm.warp(block.timestamp + 1 hours);
        jury.closeCommit(disputeId);
        _revealVote(disputeId, alice, uint8(LibEveMarket.MarketOutcome.Yes), aliceSalt);
        _revealVote(disputeId, bob, uint8(LibEveMarket.MarketOutcome.Yes), bobSalt);
        _revealVote(disputeId, carol, uint8(LibEveMarket.MarketOutcome.Unresolved), carolSalt);
        vm.warp(block.timestamp + 1 hours);
        jury.closeRevealAndTally(disputeId);

        (uint8[] memory binaryOutcomes, uint256[] memory binaryCounts) = jury.outcomeTally(disputeId, 0);
        assertEq(binaryOutcomes[0], uint8(LibEveMarket.MarketOutcome.Yes));
        assertEq(binaryCounts[0], 1);
        assertEq(binaryOutcomes[1], uint8(LibEveMarket.MarketOutcome.No));
        assertEq(binaryCounts[1], 0);
        assertEq(jury.disputeView(disputeId).validRevealCount, 1);
        (bool bobRevealed,) = jury.revealedVote(disputeId, 0, bobId);
        (bool carolRevealed,) = jury.revealedVote(disputeId, 0, carolId);
        assertFalse(bobRevealed);
        assertFalse(carolRevealed);
    }

    function _assertMultiOutcomeCommitRevealIntegrity(bytes32 seed, bytes32 salt) internal {
        jury.configureTally(
            1,
            0,
            uint8(LibEveMarket.LowQuorumMode.FinalizeInvalid),
            uint8(LibEveMarket.TieBreakMode.ResolveInvalid),
            1 hours
        );
        _activateResolver(dave);
        _activateResolver(erin);
        _activateResolver(frank);
        bytes32 disputeId = _selectMultiOutcomeCommittee(seed, keccak256("multi-integrity-market"), 4);
        uint256[] memory members = jury.committeeMembers(disputeId, 0);
        bytes32 daveSalt = keccak256(abi.encode(salt, "multi-dave"));
        bytes32 erinSalt = keccak256(abi.encode(salt, "multi-erin"));
        bytes32 frankSalt = keccak256(abi.encode(salt, "multi-frank"));
        uint8 validMultiOutcome = 2;
        uint8 validMultiInvalid = LibMultiOutcome.OUTCOME_INVALID;
        uint8 invalidMultiOutcome = 4;

        _commitVoteByIdentity(disputeId, members[0], validMultiOutcome, daveSalt);
        _commitVoteByIdentity(disputeId, members[1], validMultiInvalid, erinSalt);
        _commitVoteByIdentity(disputeId, members[2], invalidMultiOutcome, frankSalt);
        vm.warp(block.timestamp + 1 hours);
        jury.closeCommit(disputeId);
        _revealVoteByIdentity(disputeId, members[0], validMultiOutcome, daveSalt);
        _revealVoteByIdentity(disputeId, members[1], validMultiInvalid, erinSalt);
        _revealVoteByIdentity(disputeId, members[2], invalidMultiOutcome, frankSalt);
        vm.warp(block.timestamp + 1 hours);
        jury.closeRevealAndTally(disputeId);

        (uint8[] memory multiOutcomes, uint256[] memory multiCounts) = jury.outcomeTally(disputeId, 0);
        assertEq(multiOutcomes.length, 5);
        assertEq(multiOutcomes[2], validMultiOutcome);
        assertEq(multiCounts[2], 1);
        assertEq(multiOutcomes[4], validMultiInvalid);
        assertEq(multiCounts[4], 1);
        assertEq(jury.disputeView(disputeId).validRevealCount, 2);
        (bool frankRevealed,) = jury.revealedVote(disputeId, 0, members[2]);
        assertFalse(frankRevealed);
    }

    function testFuzz_PluralityTallyOverLocalNativeBucketsWithQuorum(bytes32 seed, bytes32 salt) public {
        uint256 aliceId = _activateResolver(alice);
        uint256 bobId = _activateResolver(bob);
        uint256 carolId = _activateResolver(carol);
        bytes32 disputeId = _selectCommittee(seed, keccak256("plurality-property-market"));
        jury.configureTally(
            2,
            0,
            uint8(LibEveMarket.LowQuorumMode.FinalizeInvalid),
            uint8(LibEveMarket.TieBreakMode.ResolveInvalid),
            1 hours
        );

        // Feature: resolver-identity-jury, Property 15: Plurality tally over local native buckets with quorum on total reveals
        _commitVote(
            disputeId, alice, aliceId, uint8(LibEveMarket.MarketOutcome.Yes), keccak256(abi.encode(salt, alice))
        );
        _commitVote(disputeId, bob, bobId, uint8(LibEveMarket.MarketOutcome.Yes), keccak256(abi.encode(salt, bob)));
        _commitVote(disputeId, carol, carolId, uint8(LibEveMarket.MarketOutcome.No), keccak256(abi.encode(salt, carol)));
        vm.warp(block.timestamp + 1 hours);
        jury.closeCommit(disputeId);
        _revealVote(disputeId, alice, uint8(LibEveMarket.MarketOutcome.Yes), keccak256(abi.encode(salt, alice)));
        _revealVote(disputeId, bob, uint8(LibEveMarket.MarketOutcome.Yes), keccak256(abi.encode(salt, bob)));
        _revealVote(disputeId, carol, uint8(LibEveMarket.MarketOutcome.No), keccak256(abi.encode(salt, carol)));
        vm.warp(block.timestamp + 1 hours);
        jury.closeRevealAndTally(disputeId);

        IResolverJuryFacet.DisputeView memory view_ = jury.disputeView(disputeId);
        assertEq(view_.validRevealCount, 3);
        assertEq(view_.provisionalResult, uint8(LibEveMarket.MarketOutcome.Yes));
        assertTrue(view_.hasProvisional);
    }

    function testFuzz_TieBreakAndLowQuorumFallbackFollowConfiguredMode(
        bytes32 seed,
        bytes32 salt,
        bool redrawLowQuorum,
        bool escalateTie
    ) public {
        uint256 aliceId = _activateResolver(alice);
        uint256 bobId = _activateResolver(bob);
        uint256 carolId = _activateResolver(carol);

        uint8 lowMode = redrawLowQuorum
            ? uint8(LibEveMarket.LowQuorumMode.Redraw)
            : uint8(LibEveMarket.LowQuorumMode.FinalizeInvalid);
        uint8 tieMode =
            escalateTie ? uint8(LibEveMarket.TieBreakMode.Escalate) : uint8(LibEveMarket.TieBreakMode.ResolveInvalid);

        // Feature: resolver-identity-jury, Property 16: Tie-break and low-quorum fallback follow configured mode
        bytes32 lowDisputeId = _selectCommittee(seed, keccak256("low-quorum-property-market"));
        jury.configureTally(4, 1, lowMode, tieMode, 1 hours);
        _commitVote(
            lowDisputeId, alice, aliceId, uint8(LibEveMarket.MarketOutcome.Yes), keccak256(abi.encode(salt, "low"))
        );
        _commitVote(
            lowDisputeId, bob, bobId, uint8(LibEveMarket.MarketOutcome.Yes), keccak256(abi.encode(salt, "low-bob"))
        );
        _commitVote(
            lowDisputeId, carol, carolId, uint8(LibEveMarket.MarketOutcome.No), keccak256(abi.encode(salt, "low-carol"))
        );
        vm.warp(block.timestamp + 1 hours);
        jury.closeCommit(lowDisputeId);
        _revealVote(lowDisputeId, alice, uint8(LibEveMarket.MarketOutcome.Yes), keccak256(abi.encode(salt, "low")));
        _revealVote(lowDisputeId, bob, uint8(LibEveMarket.MarketOutcome.Yes), keccak256(abi.encode(salt, "low-bob")));
        _revealVote(lowDisputeId, carol, uint8(LibEveMarket.MarketOutcome.No), keccak256(abi.encode(salt, "low-carol")));
        vm.warp(block.timestamp + 1 hours);
        jury.closeRevealAndTally(lowDisputeId);

        IResolverJuryFacet.DisputeView memory lowView = jury.disputeView(lowDisputeId);
        if (redrawLowQuorum) {
            assertEq(lowView.state, uint8(LibResolverJury.DisputeState.CommitteeSelectionPending));
            assertEq(lowView.currentRound, 0);
            assertEq(lowView.committeeSize, 0);
        } else {
            assertEq(lowView.state, uint8(LibResolverJury.DisputeState.AppealOpen));
            assertEq(lowView.provisionalResult, uint8(LibEveMarket.MarketOutcome.Invalid));
        }

        bytes32 tieDisputeId = _selectCommittee(keccak256(abi.encode(seed, "tie")), keccak256("tie-property-market"));
        jury.configureTally(2, 0, uint8(LibEveMarket.LowQuorumMode.FinalizeInvalid), tieMode, 1 hours);
        _commitVote(
            tieDisputeId, alice, aliceId, uint8(LibEveMarket.MarketOutcome.Yes), keccak256(abi.encode(salt, "yes"))
        );
        _commitVote(tieDisputeId, bob, bobId, uint8(LibEveMarket.MarketOutcome.No), keccak256(abi.encode(salt, "no")));
        vm.warp(block.timestamp + 1 hours);
        jury.closeCommit(tieDisputeId);
        _revealVote(tieDisputeId, alice, uint8(LibEveMarket.MarketOutcome.Yes), keccak256(abi.encode(salt, "yes")));
        _revealVote(tieDisputeId, bob, uint8(LibEveMarket.MarketOutcome.No), keccak256(abi.encode(salt, "no")));
        vm.warp(block.timestamp + 1 hours);
        jury.closeRevealAndTally(tieDisputeId);

        IResolverJuryFacet.DisputeView memory tieView = jury.disputeView(tieDisputeId);
        if (escalateTie) {
            assertEq(tieView.state, uint8(LibResolverJury.DisputeState.CommitteeSelectionPending));
            assertEq(tieView.currentRound, 1);
        } else {
            assertEq(tieView.state, uint8(LibResolverJury.DisputeState.AppealOpen));
            assertEq(tieView.provisionalResult, uint8(LibEveMarket.MarketOutcome.Invalid));
        }
    }

    function testFuzz_PhaseDeadlinesComputedFromConfiguredDurations(
        uint64 commitDurationInput,
        uint64 revealDurationInput,
        bytes32 seed,
        bytes32 salt
    ) public {
        uint64 commitDuration = uint64(bound(commitDurationInput, 1 hours, 7 days));
        uint64 revealDuration = uint64(bound(revealDurationInput, 1 hours, 7 days));
        jury.configurePhaseDurations(commitDuration, revealDuration);
        uint256 aliceId = _activateResolver(alice);
        uint256 bobId = _activateResolver(bob);
        uint256 carolId = _activateResolver(carol);

        bytes32 disputeId = jury.seedDisputedMarket(keccak256("phase-deadline-market"));
        jury.seedSelectionReady(disputeId, seed);
        uint256 selectionTimestamp = block.timestamp;
        jury.selectCommittee(disputeId);

        // Feature: resolver-identity-jury, Property 14: Phase deadlines computed from configured durations
        IResolverJuryFacet.DisputeView memory selectedView = jury.disputeView(disputeId);
        assertEq(selectedView.commitDeadline, selectionTimestamp + commitDuration);

        _commitVote(
            disputeId, alice, aliceId, uint8(LibEveMarket.MarketOutcome.Yes), keccak256(abi.encode(salt, alice))
        );
        _commitVote(disputeId, bob, bobId, uint8(LibEveMarket.MarketOutcome.Yes), keccak256(abi.encode(salt, bob)));
        _commitVote(disputeId, carol, carolId, uint8(LibEveMarket.MarketOutcome.No), keccak256(abi.encode(salt, carol)));

        vm.warp(selectedView.commitDeadline - 1);
        vm.expectRevert(abi.encodeWithSelector(Errors.CommitPhaseClosed.selector, disputeId));
        jury.closeCommit(disputeId);

        vm.warp(selectedView.commitDeadline);
        uint256 revealOpenTimestamp = block.timestamp;
        jury.closeCommit(disputeId);

        IResolverJuryFacet.DisputeView memory revealView = jury.disputeView(disputeId);
        assertEq(revealView.revealDeadline, revealOpenTimestamp + revealDuration);

        _revealVote(disputeId, alice, uint8(LibEveMarket.MarketOutcome.Yes), keccak256(abi.encode(salt, alice)));
        _revealVote(disputeId, bob, uint8(LibEveMarket.MarketOutcome.Yes), keccak256(abi.encode(salt, bob)));
        _revealVote(disputeId, carol, uint8(LibEveMarket.MarketOutcome.No), keccak256(abi.encode(salt, carol)));

        vm.warp(revealView.revealDeadline - 1);
        vm.expectRevert(abi.encodeWithSelector(Errors.RevealPhaseClosed.selector, disputeId));
        jury.closeRevealAndTally(disputeId);

        vm.warp(revealView.revealDeadline);
        jury.closeRevealAndTally(disputeId);
        assertEq(jury.disputeView(disputeId).provisionalResult, uint8(LibEveMarket.MarketOutcome.Yes));
    }

    function _selectCommittee(bytes32 seed, bytes32 marketId) internal returns (bytes32 disputeId) {
        disputeId = jury.seedDisputedMarket(marketId);
        jury.seedSelectionReady(disputeId, seed);
        jury.selectCommittee(disputeId);
    }

    function _selectMultiOutcomeCommittee(bytes32 seed, bytes32 marketId, uint8 outcomeCount)
        internal
        returns (bytes32 disputeId)
    {
        disputeId = jury.seedMultiOutcomeDisputedMarket(marketId, outcomeCount);
        jury.seedSelectionReady(disputeId, seed);
        jury.selectCommittee(disputeId);
    }

    function _commitVote(bytes32 disputeId, address owner, uint256 identityId, uint8 outcome, bytes32 salt) internal {
        vm.prank(owner);
        jury.commitVote(disputeId, keccak256(abi.encode(disputeId, identityId, outcome, salt)));
    }

    function _commitVoteByIdentity(bytes32 disputeId, uint256 identityId, uint8 outcome, bytes32 salt) internal {
        _commitVote(disputeId, identity.ownerOf(identityId), identityId, outcome, salt);
    }

    function _revealVote(bytes32 disputeId, address owner, uint8 outcome, bytes32 salt) internal {
        vm.prank(owner);
        jury.revealVote(disputeId, outcome, salt);
    }

    function _revealVoteByIdentity(bytes32 disputeId, uint256 identityId, uint8 outcome, bytes32 salt) internal {
        _revealVote(disputeId, identity.ownerOf(identityId), outcome, salt);
    }

    function _activateResolver(address account) internal returns (uint256 identityId) {
        feeToken.mint(account, 1e6);
        vm.prank(account);
        feeToken.approve(address(jury), 1e6);
        vm.prank(account);
        identityId = jury.mintIdentity();

        vm.prank(account);
        jury.setResolverRole(true);

        eveToken.mint(account, 100e18);
        vm.prank(account);
        eveToken.approve(address(jury), 100e18);
        vm.prank(account);
        jury.depositResolverStake(100e18);

        jury.seedActiveResolverEpochMember(identityId);
    }
}
