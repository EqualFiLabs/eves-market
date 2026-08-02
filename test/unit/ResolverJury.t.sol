// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "../../lib/forge-std/src/Test.sol";

import {IResolverJuryFacet} from "src/interfaces/IResolverJuryFacet.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Events} from "src/libraries/Events.sol";
import {LibEveMarket} from "src/libraries/LibEveMarket.sol";
import {LibResolverJury} from "src/libraries/LibResolverJury.sol";
import {BondManagerFacet} from "src/facets/BondManagerFacet.sol";
import {ResolverJuryFacet} from "src/facets/ResolverJuryFacet.sol";
import {ResolverRegistryFacet} from "src/facets/ResolverRegistryFacet.sol";
import {EveIdentity} from "src/tokens/EveIdentity.sol";
import {MockEveToken} from "test/helpers/MockEveToken.sol";
import {MockUSDC} from "test/helpers/MockUSDC.sol";

contract ResolverJuryHarness is ResolverJuryFacet, ResolverRegistryFacet, BondManagerFacet {
    function configureIdentityAndRandomness(
        address eveIdentity,
        address mintFeeToken,
        address eveToken,
        uint256 commitDuration,
        uint256 revealDuration,
        uint256 minReveals,
        uint256 fallbackMode,
        uint256 allEligibleFallbackCap
    ) external {
        if (
            commitDuration > type(uint64).max || revealDuration > type(uint64).max || minReveals > type(uint8).max
                || fallbackMode > uint256(type(LibEveMarket.RandomnessFailureMode).max)
                || allEligibleFallbackCap > type(uint16).max
        ) {
            revert Errors.InvalidAmount(commitDuration);
        }

        LibResolverJury.store().eveIdentity = eveIdentity;
        LibEveMarket.MarketConfig storage config = LibEveMarket.store().config;
        config.eveToken = eveToken;
        if (config.bondToken == address(0)) {
            config.bondToken = eveToken;
        }
        config.eveTreasury = address(uint160(uint256(keccak256("resolver-jury-treasury"))));
        config.resolverJuryConfig.identityMintFeeToken = mintFeeToken;
        config.resolverJuryConfig.identityMintFee = 1e6;
        config.resolverJuryConfig.resolverStakeRequirement = 100e18;
        config.resolverJuryConfig.resolverStakeCap = 250e18;
        config.resolverJuryConfig.resolverPoolCap = 50;
        config.resolverJuryConfig.participationGraceCount = 5;
        config.resolverJuryConfig.concurrencyLimit = 5;
        config.resolverJuryConfig.randomnessCommitDuration = uint64(commitDuration);
        config.resolverJuryConfig.randomnessRevealDuration = uint64(revealDuration);
        config.resolverJuryConfig.commitDuration = 1 hours;
        config.resolverJuryConfig.revealDuration = 1 hours;
        config.resolverJuryConfig.minRandomnessReveals = uint8(minReveals);
        config.resolverJuryConfig.randomnessFailureMode = LibEveMarket.RandomnessFailureMode(fallbackMode);
        config.resolverJuryConfig.allEligibleFallbackCap = uint16(allEligibleFallbackCap);
        delete config.resolverJuryConfig.committeeSizesByRound;
        config.resolverJuryConfig.committeeSizesByRound.push(3);
        config.resolverJuryConfig.committeeSizesByRound.push(5);
        config.resolverJuryConfig.maxAppealRounds = 1;
        config.resolverJuryConfig.appealBondMultiplierBps = 20_000;
        config.resolutionBondL1 = 0.1 ether;
        config.resolutionBondL2 = 0.5 ether;
        config.resolverJuryConfig.missedCommitSlashBps = 1_000;
        config.resolverJuryConfig.missedRevealSlashBps = 2_000;
        config.resolverJuryConfig.invalidRevealSlashBps = 3_000;
        config.resolverJuryConfig.slashCooldown = 1 days;
    }

    function configureBondToken(address token) external {
        LibEveMarket.store().config.bondToken = token;
    }

    function configureCommittee(uint256 committeeSize, uint256 commitDuration) external {
        if (committeeSize > type(uint16).max || commitDuration > type(uint64).max) {
            revert Errors.InvalidAmount(committeeSize);
        }

        LibEveMarket.ResolverJuryConfig storage config = LibEveMarket.store().config.resolverJuryConfig;
        delete config.committeeSizesByRound;
        config.committeeSizesByRound.push(uint16(committeeSize));
        config.commitDuration = uint64(commitDuration);
    }

    function configureVoting(uint256 revealDuration) external {
        if (revealDuration > type(uint64).max) {
            revert Errors.InvalidAmount(revealDuration);
        }

        LibEveMarket.store().config.resolverJuryConfig.revealDuration = uint64(revealDuration);
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

    function configureAppealParams(uint256 maxAppealRounds, uint256 appealBondMultiplierBps) external {
        if (maxAppealRounds > type(uint8).max || appealBondMultiplierBps > type(uint16).max) {
            revert Errors.InvalidAmount(maxAppealRounds);
        }

        LibEveMarket.ResolverJuryConfig storage config = LibEveMarket.store().config.resolverJuryConfig;
        config.maxAppealRounds = uint8(maxAppealRounds);
        config.appealBondMultiplierBps = uint16(appealBondMultiplierBps);
    }

    function configureAppealRouting(uint16[4] calldata successRoutingBps, uint16[3] calldata failureRoutingBps)
        external
    {
        LibEveMarket.ResolverJuryConfig storage config = LibEveMarket.store().config.resolverJuryConfig;
        config.appealSuccessRoutingBps = successRoutingBps;
        config.appealFailureRoutingBps = failureRoutingBps;
    }

    function configureProtocolFeeAllocation(uint256 allocationBps) external {
        if (allocationBps > type(uint16).max) {
            revert Errors.InvalidAmount(allocationBps);
        }

        LibEveMarket.store().config.resolverJuryConfig.protocolFeeAllocationBps = uint16(allocationBps);
    }

    function seedResolutionClaimant(bytes32 marketId, address claimant, uint8 outcome) external {
        LibEveMarket.Resolution memory proposal = LibEveMarket.Resolution({
            marketId: marketId,
            proposer: claimant,
            proposedOutcome: outcome,
            escalationLevel: 1,
            disputed: true,
            bondAmount: 0,
            reservedBondAmount: 0,
            proposedAt: uint64(block.timestamp),
            disputeDeadline: uint64(block.timestamp + 1 days),
            snapshotBlock: uint64(block.number)
        });
        LibEveMarket.store().resolutionHistory[marketId].push(proposal);
    }

    function seedMarket(bytes32 marketId, uint256 marketType, uint256 marketState, uint256 outcomeCount) external {
        if (
            marketType > uint256(type(LibEveMarket.MarketType).max)
                || marketState > uint256(type(LibEveMarket.MarketState).max)
        ) {
            revert Errors.InvalidAmount(marketType);
        }
        if (outcomeCount > type(uint8).max) {
            revert Errors.InvalidAmount(outcomeCount);
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        state.markets[marketId].marketId = marketId;
        state.markets[marketId].marketType = LibEveMarket.MarketType(marketType);
        state.markets[marketId].state = LibEveMarket.MarketState(marketState);
        if (LibEveMarket.MarketType(marketType) == LibEveMarket.MarketType.MULTI_OUTCOME_ORDERBOOK) {
            state.multiOutcomeMarkets[marketId].marketId = marketId;
            state.multiOutcomeMarkets[marketId].outcomeCount = uint8(outcomeCount);
            state.multiOutcomeMarkets[marketId].exists = true;
        }
    }

    function seedProtocolFees(bytes32 marketId, address collateralToken, uint256 amount) external {
        if (amount > type(uint128).max) {
            revert Errors.InvalidAmount(amount);
        }

        LibEveMarket.Market storage market = LibEveMarket.store().markets[marketId];
        market.collateralToken = collateralToken;
        market.protocolFeesAccrued = uint128(amount);
        market.totalFeePool = uint128(amount);
    }

    function protocolFeesAccrued(bytes32 marketId) external view returns (uint128) {
        return LibEveMarket.store().markets[marketId].protocolFeesAccrued;
    }

    function initiateViaSelf(bytes32 marketId) external {
        IResolverJuryFacet(address(this)).initiateDispute(marketId);
    }

    function exposedRandomnessSeed(bytes32 disputeId, bytes32 accumulator, bytes32 delayedBlockEntropy)
        external
        pure
        returns (bytes32)
    {
        return _deriveRandomnessSeed(disputeId, accumulator, delayedBlockEntropy);
    }

    function seedSelectionReady(bytes32 disputeId, bytes32 seed, bool allEligibleFallback) external {
        // Synthetic setup for sortition unit coverage; randomness lifecycle tests cover the real seed path.
        LibResolverJury.Dispute storage dispute = LibResolverJury.store().disputes[disputeId];
        LibResolverJury.DisputeRound storage round = dispute.rounds[dispute.currentRound];
        round.seed = seed;
        round.allEligibleFallback = allEligibleFallback;
    }

    function seedRoundView(bytes32 disputeId, uint256[] calldata committee) external {
        LibResolverJury.Dispute storage dispute = LibResolverJury.store().disputes[disputeId];
        dispute.marketId = keccak256("view-market");
        dispute.state = LibResolverJury.DisputeState.RevealOpen;
        dispute.currentRound = 1;
        dispute.isMultiOutcome = true;
        dispute.outcomeCount = 3;

        LibResolverJury.DisputeRound storage round = dispute.rounds[1];
        round.round = 1;
        round.committeeSize = uint16(committee.length);
        round.validRevealCount = 2;
        round.randomnessCommitDeadline = 11;
        round.randomnessRevealDeadline = 22;
        round.commitDeadline = 33;
        round.revealDeadline = 44;
        round.appealDeadline = 55;
        round.provisionalResult = 2;
        round.hasProvisional = true;
        round.tally[0] = 1;
        round.tally[2] = 2;
        round.tally[255] = 3;
        round.hasRevealed[committee[0]] = true;
        round.revealedOutcome[committee[0]] = 2;

        for (uint256 index; index < committee.length; ++index) {
            round.committee.push(committee[index]);
        }
    }

    function seedFinalized(bytes32 disputeId, uint256 finalResult) external {
        if (finalResult > type(uint8).max) {
            revert Errors.InvalidAmount(finalResult);
        }

        LibResolverJury.Dispute storage dispute = LibResolverJury.store().disputes[disputeId];
        dispute.finalized = true;
        dispute.finalResult = uint8(finalResult);
    }

    function appealBondForRound(bytes32 disputeId, uint256 round)
        external
        view
        returns (uint128 bond, address appellant)
    {
        if (round > type(uint8).max) {
            revert Errors.InvalidAmount(round);
        }

        LibResolverJury.Dispute storage dispute = LibResolverJury.store().disputes[disputeId];
        bond = dispute.appealBond[uint8(round)];
        appellant = dispute.appellant[uint8(round)];
    }

    function resolverSlashState(uint256 identityId)
        external
        view
        returns (uint128 stake, bool slashLockActive, uint64 slashLockUntil)
    {
        LibResolverJury.ResolverIdentityRecord storage record = LibResolverJury.store().identities[identityId];
        stake = record.resolverStake;
        slashLockActive = record.slashLockActive;
        slashLockUntil = record.slashLockUntil;
    }

    function resolverUnresolvedCommittees(uint256 identityId) external view returns (uint16) {
        return LibResolverJury.store().identities[identityId].unresolvedCommittees;
    }

    function eveTreasury() external view returns (address) {
        return LibEveMarket.store().config.eveTreasury;
    }

    function finalizeFromJury(bytes32, uint8) external {}
}

contract ResolverJuryTest is Test {
    uint256 internal constant RESOLVER_STAKE = 100e18;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal dave = makeAddr("dave");
    address internal erin = makeAddr("erin");
    address internal claimant = makeAddr("claimant");

    ResolverJuryHarness internal jury;
    EveIdentity internal identity;
    MockUSDC internal feeToken;
    MockEveToken internal eveToken;
    MockEveToken internal bondToken;

    function setUp() public {
        jury = new ResolverJuryHarness();
        identity = new EveIdentity(address(jury), "Eve Identity", "EVE-ID");
        feeToken = new MockUSDC();
        eveToken = new MockEveToken();
        bondToken = new MockEveToken();
        jury.configureIdentityAndRandomness(
            address(identity),
            address(feeToken),
            address(eveToken),
            1 hours,
            1 hours,
            2,
            uint8(LibEveMarket.RandomnessFailureMode.Retry),
            10
        );
        jury.configureBondToken(address(bondToken));
    }

    function test_InitiateDisputeRequiresSelfCall() public {
        bytes32 marketId = keccak256("self-call-market");
        jury.seedMarket(marketId, uint8(LibEveMarket.MarketType.CLOB), uint8(LibEveMarket.MarketState.Disputed), 0);

        vm.expectRevert(abi.encodeWithSelector(Errors.InternalCallOnly.selector, address(this)));
        jury.initiateDispute(marketId);
    }

    function test_InitiateDisputePersistsStateAndReadViews() public {
        bytes32 marketId = keccak256("multi-jury-market");
        jury.seedMarket(
            marketId,
            uint8(LibEveMarket.MarketType.MULTI_OUTCOME_ORDERBOOK),
            uint8(LibEveMarket.MarketState.Disputed),
            4
        );
        bytes32 disputeId = jury.disputeIdForMarket(marketId);

        vm.expectEmit(true, true, false, true);
        emit Events.ResolverJuryInitiated(disputeId, marketId, 0);
        jury.initiateViaSelf(marketId);

        IResolverJuryFacet.DisputeView memory view_ = jury.disputeView(disputeId);
        assertEq(view_.disputeId, disputeId);
        assertEq(view_.marketId, marketId);
        assertEq(view_.state, uint8(LibResolverJury.DisputeState.CommitteeSelectionPending));
        assertEq(view_.currentRound, 0);
        assertFalse(view_.finalized);
        assertTrue(view_.isMultiOutcome);
        assertEq(view_.outcomeCount, 4);

        (uint8 provisional, bool isFinal) = jury.provisionalResult(disputeId);
        assertEq(provisional, 0);
        assertFalse(isFinal);
    }

    function test_InitiateDisputeRejectsNonDisputedMarket() public {
        bytes32 marketId = keccak256("trading-market");
        jury.seedMarket(marketId, uint8(LibEveMarket.MarketType.CLOB), uint8(LibEveMarket.MarketState.Trading), 0);

        vm.expectRevert(abi.encodeWithSelector(Errors.MarketNotDisputed.selector, marketId));
        jury.initiateViaSelf(marketId);
    }

    function test_DisputeReadViewsExposeRoundState() public {
        bytes32 disputeId = keccak256("read-view-dispute");
        uint256[] memory committee = new uint256[](2);
        committee[0] = 11;
        committee[1] = 22;
        jury.seedRoundView(disputeId, committee);

        IResolverJuryFacet.DisputeView memory view_ = jury.disputeView(disputeId);
        assertEq(view_.state, uint8(LibResolverJury.DisputeState.RevealOpen));
        assertEq(view_.currentRound, 1);
        assertEq(view_.committeeSize, 2);
        assertEq(view_.validRevealCount, 2);
        assertEq(view_.randomnessCommitDeadline, 11);
        assertEq(view_.randomnessRevealDeadline, 22);
        assertEq(view_.commitDeadline, 33);
        assertEq(view_.revealDeadline, 44);
        assertEq(view_.appealDeadline, 55);
        assertEq(view_.provisionalResult, 2);
        assertTrue(view_.hasProvisional);

        uint256[] memory members = jury.committeeMembers(disputeId, 1);
        assertEq(members.length, 2);
        assertEq(members[0], 11);
        assertEq(members[1], 22);

        (uint8[] memory outcomes, uint256[] memory counts) = jury.outcomeTally(disputeId, 1);
        assertEq(outcomes.length, 4);
        assertEq(counts.length, 4);
        assertEq(outcomes[0], 0);
        assertEq(counts[0], 1);
        assertEq(outcomes[2], 2);
        assertEq(counts[2], 2);
        assertEq(outcomes[3], 255);
        assertEq(counts[3], 3);

        (bool revealed, uint8 outcome) = jury.revealedVote(disputeId, 1, 11);
        assertTrue(revealed);
        assertEq(outcome, 2);
    }

    function test_FinalizedDisputeRejectsFurtherTransitions() public {
        bytes32 disputeId = keccak256("finalized-dispute");
        jury.seedFinalized(disputeId, uint8(LibEveMarket.MarketOutcome.Yes));

        vm.expectRevert(abi.encodeWithSelector(Errors.DisputeAlreadyFinalized.selector, disputeId));
        jury.openRandomnessCommit(disputeId);

        (uint8 outcome, bool isFinal) = jury.provisionalResult(disputeId);
        assertEq(outcome, uint8(LibEveMarket.MarketOutcome.Yes));
        assertTrue(isFinal);
    }

    function test_RandomnessCommitRevealDerivesDelayedEntropySeed() public {
        uint256 aliceId = _activateResolver(alice);
        uint256 bobId = _activateResolver(bob);
        bytes32 disputeId = _initiateDisputedMarket(keccak256("randomness-success-market"));
        bytes32 aliceValue = keccak256("alice-value");
        bytes32 bobValue = keccak256("bob-value");
        bytes32 aliceSalt = keccak256("alice-salt");
        bytes32 bobSalt = keccak256("bob-salt");

        jury.openRandomnessCommit(disputeId);
        vm.prank(alice);
        jury.commitRandomness(disputeId, keccak256(abi.encode(disputeId, aliceId, aliceValue, aliceSalt)));
        vm.prank(bob);
        jury.commitRandomness(disputeId, keccak256(abi.encode(disputeId, bobId, bobValue, bobSalt)));

        vm.warp(block.timestamp + 1 hours);
        jury.closeRandomnessCommit(disputeId);
        uint256 referenceBlock = block.number + 1;

        vm.prank(alice);
        jury.revealRandomness(disputeId, aliceValue, aliceSalt);
        vm.prank(bob);
        jury.revealRandomness(disputeId, bobValue, bobSalt);

        vm.roll(referenceBlock + 1);
        vm.warp(block.timestamp + 1 hours);
        jury.closeRandomnessReveal(disputeId);

        IResolverJuryFacet.DisputeView memory view_ = jury.disputeView(disputeId);
        bytes32 accumulator = keccak256(abi.encode(bytes32(0), aliceId, aliceValue));
        accumulator = keccak256(abi.encode(accumulator, bobId, bobValue));
        assertEq(view_.validRevealCount, 2);
        assertEq(view_.randomnessAccumulator, accumulator);
        assertEq(view_.randomnessReferenceBlock, referenceBlock);
        assertEq(view_.seed, jury.exposedRandomnessSeed(disputeId, accumulator, blockhash(referenceBlock)));
        assertFalse(view_.allEligibleFallback);

        vm.expectRevert(abi.encodeWithSelector(Errors.RandomnessNotReady.selector, disputeId));
        jury.openRandomnessCommit(disputeId);
    }

    function test_RandomnessRejectsDuplicateAndMismatchedReveal() public {
        uint256 aliceId = _activateResolver(alice);
        bytes32 disputeId = _initiateDisputedMarket(keccak256("randomness-duplicate-market"));
        bytes32 value = keccak256("value");
        bytes32 salt = keccak256("salt");

        jury.openRandomnessCommit(disputeId);
        bytes32 commitment = keccak256(abi.encode(disputeId, aliceId, value, salt));
        vm.prank(alice);
        jury.commitRandomness(disputeId, commitment);

        vm.expectRevert(abi.encodeWithSelector(Errors.AlreadyCommitted.selector, aliceId));
        vm.prank(alice);
        jury.commitRandomness(disputeId, commitment);

        vm.warp(block.timestamp + 1 hours);
        jury.closeRandomnessCommit(disputeId);

        vm.expectRevert(abi.encodeWithSelector(Errors.JuryCommitmentMismatch.selector, aliceId));
        vm.prank(alice);
        jury.revealRandomness(disputeId, value, keccak256("wrong-salt"));

        vm.prank(alice);
        jury.revealRandomness(disputeId, value, salt);

        vm.expectRevert(abi.encodeWithSelector(Errors.AlreadyRevealed.selector, aliceId));
        vm.prank(alice);
        jury.revealRandomness(disputeId, value, salt);
    }

    function test_RandomnessRetryFallbackReopensCommitWindow() public {
        _activateResolver(alice);
        bytes32 disputeId = _initiateDisputedMarket(keccak256("randomness-retry-market"));

        jury.openRandomnessCommit(disputeId);
        vm.warp(block.timestamp + 1 hours);
        jury.closeRandomnessCommit(disputeId);

        vm.expectRevert(abi.encodeWithSelector(Errors.RandomnessNotReady.selector, disputeId));
        jury.applyRandomnessFallback(disputeId);

        vm.roll(block.number + 2);
        vm.warp(block.timestamp + 1 hours);

        vm.expectEmit(true, true, false, true);
        emit Events.RandomnessFailure(disputeId, 0, uint8(LibEveMarket.RandomnessFailureMode.Retry), 0);
        jury.closeRandomnessReveal(disputeId);

        IResolverJuryFacet.DisputeView memory view_ = jury.disputeView(disputeId);
        assertEq(view_.randomnessAttempt, 2);
        assertEq(view_.validRevealCount, 0);
        assertEq(view_.randomnessRevealDeadline, 0);
        assertGt(view_.randomnessCommitDeadline, block.timestamp);
        assertEq(view_.marketId, jury.disputeView(disputeId).marketId);
    }

    function test_RandomnessAllEligibleFallbackCap() public {
        _activateResolver(alice);
        bytes32 disputeId = _initiateDisputedMarket(keccak256("randomness-all-eligible-market"));
        jury.configureIdentityAndRandomness(
            address(identity),
            address(feeToken),
            address(eveToken),
            1 hours,
            1 hours,
            2,
            uint8(LibEveMarket.RandomnessFailureMode.AllEligible),
            1
        );

        jury.openRandomnessCommit(disputeId);
        vm.warp(block.timestamp + 1 hours);
        jury.closeRandomnessCommit(disputeId);
        vm.roll(block.number + 2);
        vm.warp(block.timestamp + 1 hours);

        vm.expectEmit(true, true, false, true);
        emit Events.RandomnessFailure(disputeId, 0, uint8(LibEveMarket.RandomnessFailureMode.AllEligible), 0);
        jury.closeRandomnessReveal(disputeId);

        IResolverJuryFacet.DisputeView memory view_ = jury.disputeView(disputeId);
        assertTrue(view_.allEligibleFallback);

        _activateResolver(bob);
        bytes32 cappedDisputeId = _initiateDisputedMarket(keccak256("randomness-all-eligible-capped-market"));
        jury.openRandomnessCommit(cappedDisputeId);
        vm.warp(block.timestamp + 1 hours);
        jury.closeRandomnessCommit(cappedDisputeId);
        vm.roll(block.number + 2);
        vm.warp(block.timestamp + 1 hours);

        vm.expectRevert(abi.encodeWithSelector(Errors.RandomnessFallbackUnavailable.selector, cappedDisputeId));
        jury.closeRandomnessReveal(cappedDisputeId);
    }

    function test_SelectCommitteeUsesEntireEligibleSetAtExactSize() public {
        uint256 aliceId = _activateResolver(alice);
        uint256 bobId = _activateResolver(bob);
        uint256 carolId = _activateResolver(carol);
        bytes32 disputeId = _initiateDisputedMarket(keccak256("committee-exact-market"));
        jury.seedSelectionReady(disputeId, keccak256("committee-seed"), false);

        uint256[] memory expected = new uint256[](3);
        expected[0] = aliceId;
        expected[1] = bobId;
        expected[2] = carolId;
        vm.expectEmit(true, true, false, true);
        emit Events.CommitteeSelected(disputeId, 0, 3, keccak256("committee-seed"), expected);
        jury.selectCommittee(disputeId);

        uint256[] memory members = jury.committeeMembers(disputeId, 0);
        assertEq(members.length, 3);
        assertEq(members[0], aliceId);
        assertEq(members[1], bobId);
        assertEq(members[2], carolId);

        IResolverJuryFacet.DisputeView memory view_ = jury.disputeView(disputeId);
        assertEq(view_.state, uint8(LibResolverJury.DisputeState.CommitOpen));
        assertEq(view_.committeeSize, 3);
        assertEq(view_.commitDeadline, block.timestamp + 1 hours);
        assertEq(jury.resolverReputation(aliceId).totalSelections, 1);
    }

    function test_SelectCommitteeDrawsDuplicateFreeSubset() public {
        uint256 aliceId = _activateResolver(alice);
        uint256 bobId = _activateResolver(bob);
        uint256 carolId = _activateResolver(carol);
        uint256 daveId = _activateResolver(makeAddr("dave"));
        bytes32 disputeId = _initiateDisputedMarket(keccak256("committee-random-market"));
        jury.seedSelectionReady(disputeId, keccak256("committee-random-seed"), false);

        jury.selectCommittee(disputeId);

        uint256[] memory members = jury.committeeMembers(disputeId, 0);
        assertEq(members.length, 3);
        for (uint256 index; index < members.length; ++index) {
            assertTrue(
                members[index] == aliceId || members[index] == bobId || members[index] == carolId
                    || members[index] == daveId
            );
            for (uint256 inner = index + 1; inner < members.length; ++inner) {
                assertNotEq(members[index], members[inner]);
            }
        }
    }

    function test_SelectCommitteeAllEligibleFallbackCanSelectBelowConfiguredSize() public {
        uint256 aliceId = _activateResolver(alice);
        uint256 bobId = _activateResolver(bob);
        bytes32 disputeId = _initiateDisputedMarket(keccak256("committee-all-eligible-market"));
        jury.seedSelectionReady(disputeId, bytes32(0), true);

        jury.selectCommittee(disputeId);

        uint256[] memory members = jury.committeeMembers(disputeId, 0);
        assertEq(members.length, 2);
        assertEq(members[0], aliceId);
        assertEq(members[1], bobId);
        assertEq(jury.disputeView(disputeId).committeeSize, 2);
    }

    function test_SelectCommitteeRejectsBelowSizeWithoutFallback() public {
        _activateResolver(alice);
        _activateResolver(bob);
        bytes32 disputeId = _initiateDisputedMarket(keccak256("committee-below-size-market"));
        jury.seedSelectionReady(disputeId, keccak256("committee-below-size-seed"), false);

        vm.expectRevert(abi.encodeWithSelector(Errors.RandomnessFallbackUnavailable.selector, disputeId));
        jury.selectCommittee(disputeId);
    }

    function test_SelectCommitteeRejectsInvalidCommitteeSizes() public {
        _activateResolver(alice);
        _activateResolver(bob);
        bytes32 disputeId = _initiateDisputedMarket(keccak256("committee-even-size-market"));
        jury.configureCommittee(2, 1 hours);
        jury.seedSelectionReady(disputeId, keccak256("committee-even-seed"), false);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidCommitteeSize.selector, uint16(2)));
        jury.selectCommittee(disputeId);

        bytes32 zeroSizeDisputeId = _initiateDisputedMarket(keccak256("committee-zero-size-market"));
        jury.configureCommittee(0, 1 hours);
        jury.seedSelectionReady(zeroSizeDisputeId, keccak256("committee-zero-seed"), false);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidCommitteeSize.selector, uint16(0)));
        jury.selectCommittee(zeroSizeDisputeId);
    }

    function test_SelectCommitteeRejectsInvalidCommitDuration() public {
        _activateResolver(alice);
        _activateResolver(bob);
        _activateResolver(carol);
        bytes32 disputeId = _initiateDisputedMarket(keccak256("committee-duration-market"));
        jury.configureCommittee(3, 59 minutes);
        jury.seedSelectionReady(disputeId, keccak256("committee-duration-seed"), false);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidConfigValue.selector, bytes32("commitDuration")));
        jury.selectCommittee(disputeId);
    }

    function test_VoteCommitRequiresCommitteeMembershipAndFirstWins() public {
        uint256 aliceId = _activateResolver(alice);
        _activateResolver(bob);
        _activateResolver(carol);
        bytes32 disputeId = _initiateDisputedMarket(keccak256("vote-commit-market"));
        jury.seedSelectionReady(disputeId, keccak256("vote-commit-seed"), false);
        jury.selectCommittee(disputeId);

        bytes32 commitment = keccak256("alice-vote-commitment");
        vm.expectEmit(true, true, true, true);
        emit Events.VoteCommitted(disputeId, 0, aliceId);
        vm.prank(alice);
        jury.commitVote(disputeId, commitment);

        assertEq(jury.resolverReputation(aliceId).commitCount, 1);

        vm.expectRevert(abi.encodeWithSelector(Errors.AlreadyCommitted.selector, aliceId));
        vm.prank(alice);
        jury.commitVote(disputeId, keccak256("alice-second-commitment"));

        uint256 daveId = _activateResolver(makeAddr("dave"));
        vm.expectRevert(abi.encodeWithSelector(Errors.NotCommitteeMember.selector, daveId));
        vm.prank(makeAddr("dave"));
        jury.commitVote(disputeId, keccak256("dave-commitment"));
    }

    function test_CloseCommitOpensRevealPhaseFromConfig() public {
        _activateResolver(alice);
        _activateResolver(bob);
        _activateResolver(carol);
        bytes32 disputeId = _initiateDisputedMarket(keccak256("vote-close-commit-market"));
        jury.seedSelectionReady(disputeId, keccak256("vote-close-commit-seed"), false);
        jury.selectCommittee(disputeId);

        vm.expectRevert(abi.encodeWithSelector(Errors.CommitPhaseClosed.selector, disputeId));
        jury.closeCommit(disputeId);

        vm.warp(block.timestamp + 1 hours);
        jury.closeCommit(disputeId);

        IResolverJuryFacet.DisputeView memory view_ = jury.disputeView(disputeId);
        assertEq(view_.state, uint8(LibResolverJury.DisputeState.RevealOpen));
        assertEq(view_.revealDeadline, block.timestamp + 1 hours);
    }

    function test_CloseCommitSlashesMissedCommit() public {
        uint256 aliceId = _activateResolver(alice);
        uint256 bobId = _activateResolver(bob);
        uint256 carolId = _activateResolver(carol);
        bytes32 disputeId = _initiateDisputedMarket(keccak256("missed-commit-market"));
        jury.seedSelectionReady(disputeId, keccak256("missed-commit-seed"), false);
        jury.selectCommittee(disputeId);

        vm.prank(alice);
        jury.commitVote(disputeId, keccak256("alice-commit"));
        vm.prank(bob);
        jury.commitVote(disputeId, keccak256("bob-commit"));

        vm.warp(block.timestamp + 1 hours);
        vm.expectEmit(true, true, true, true);
        emit Events.ResolverSlashed(disputeId, 0, carolId, 10e18);
        jury.closeCommit(disputeId);

        (uint128 stake, bool slashLockActive, uint64 slashLockUntil) = jury.resolverSlashState(carolId);
        assertEq(stake, 90e18);
        assertTrue(slashLockActive);
        assertEq(slashLockUntil, block.timestamp + 1 days);
        assertEq(jury.disputeView(disputeId).rewardPoolBond, 10e18);
        assertEq(jury.resolverReputation(carolId).missedCommitCount, 1);
        assertEq(jury.resolverReputation(carolId).slashCount, 1);
        assertEq(jury.resolverReputation(aliceId).slashCount, 0);
        assertEq(jury.resolverReputation(bobId).slashCount, 0);
    }

    function test_RevealVoteCountsNativeOutcomeOnce() public {
        uint256 aliceId = _activateResolver(alice);
        uint256 bobId = _activateResolver(bob);
        _activateResolver(carol);
        bytes32 disputeId = _initiateDisputedMarket(keccak256("vote-reveal-market"));
        jury.seedSelectionReady(disputeId, keccak256("vote-reveal-seed"), false);
        jury.selectCommittee(disputeId);
        bytes32 aliceSalt = keccak256("alice-vote-salt");
        bytes32 bobSalt = keccak256("bob-vote-salt");
        uint8 yesOutcome = uint8(LibEveMarket.MarketOutcome.Yes);
        uint8 noOutcome = uint8(LibEveMarket.MarketOutcome.No);

        vm.prank(alice);
        jury.commitVote(disputeId, keccak256(abi.encode(disputeId, aliceId, yesOutcome, aliceSalt)));
        vm.prank(bob);
        jury.commitVote(disputeId, keccak256(abi.encode(disputeId, bobId, noOutcome, bobSalt)));

        vm.warp(block.timestamp + 1 hours);
        jury.closeCommit(disputeId);

        vm.expectEmit(true, true, true, true);
        emit Events.VoteRevealed(disputeId, 0, aliceId, yesOutcome);
        vm.prank(alice);
        jury.revealVote(disputeId, yesOutcome, aliceSalt);
        vm.prank(bob);
        jury.revealVote(disputeId, noOutcome, bobSalt);

        (bool revealed, uint8 outcome) = jury.revealedVote(disputeId, 0, aliceId);
        assertTrue(revealed);
        assertEq(outcome, yesOutcome);
        assertEq(jury.disputeView(disputeId).validRevealCount, 2);
        assertEq(jury.resolverReputation(aliceId).revealCount, 1);

        (uint8[] memory outcomes, uint256[] memory counts) = jury.outcomeTally(disputeId, 0);
        assertEq(outcomes[0], yesOutcome);
        assertEq(counts[0], 1);
        assertEq(outcomes[1], noOutcome);
        assertEq(counts[1], 1);

        vm.expectRevert(abi.encodeWithSelector(Errors.AlreadyRevealed.selector, aliceId));
        vm.prank(alice);
        jury.revealVote(disputeId, yesOutcome, aliceSalt);
    }

    function test_RevealVoteRejectsMismatchInvalidOutcomeAndLateReveal() public {
        uint256 aliceId = _activateResolver(alice);
        uint256 bobId = _activateResolver(bob);
        uint256 carolId = _activateResolver(carol);
        bytes32 disputeId = _initiateDisputedMarket(keccak256("vote-invalid-reveal-market"));
        jury.seedSelectionReady(disputeId, keccak256("vote-invalid-reveal-seed"), false);
        jury.selectCommittee(disputeId);
        uint8 yesOutcome = uint8(LibEveMarket.MarketOutcome.Yes);
        bytes32 aliceSalt = keccak256("alice-invalid-salt");
        bytes32 bobSalt = keccak256("bob-invalid-salt");
        bytes32 carolSalt = keccak256("carol-invalid-salt");

        vm.prank(alice);
        jury.commitVote(disputeId, keccak256(abi.encode(disputeId, aliceId, yesOutcome, aliceSalt)));
        vm.prank(bob);
        jury.commitVote(disputeId, keccak256(abi.encode(disputeId, bobId, uint8(9), bobSalt)));

        vm.warp(block.timestamp + 1 hours);
        jury.closeCommit(disputeId);

        vm.expectRevert(abi.encodeWithSelector(Errors.JuryCommitmentMismatch.selector, carolId));
        vm.prank(carol);
        jury.revealVote(disputeId, yesOutcome, carolSalt);

        vm.expectEmit(true, true, true, true);
        emit Events.ResolverSlashed(disputeId, 0, aliceId, 30e18);
        vm.prank(alice);
        jury.revealVote(disputeId, yesOutcome, keccak256("wrong-vote-salt"));

        vm.expectRevert(abi.encodeWithSelector(Errors.AlreadyRevealed.selector, aliceId));
        vm.prank(alice);
        jury.revealVote(disputeId, yesOutcome, aliceSalt);

        vm.expectEmit(true, true, true, true);
        emit Events.ResolverSlashed(disputeId, 0, bobId, 30e18);
        vm.prank(bob);
        jury.revealVote(disputeId, 9, bobSalt);

        (uint128 aliceStake,,) = jury.resolverSlashState(aliceId);
        (uint128 bobStake,,) = jury.resolverSlashState(bobId);
        assertEq(aliceStake, 70e18);
        assertEq(bobStake, 70e18);
        assertEq(jury.resolverReputation(aliceId).invalidRevealCount, 1);
        assertEq(jury.resolverReputation(bobId).invalidRevealCount, 1);
        assertEq(jury.disputeView(disputeId).validRevealCount, 0);
        assertEq(jury.disputeView(disputeId).rewardPoolBond, 70e18);

        vm.warp(block.timestamp + 1 hours);
        vm.expectRevert(abi.encodeWithSelector(Errors.RevealPhaseClosed.selector, disputeId));
        vm.prank(alice);
        jury.revealVote(disputeId, yesOutcome, aliceSalt);
    }

    function test_CloseRevealSlashesMissedRevealButNotHonestMinority() public {
        uint256 aliceId = _activateResolver(alice);
        uint256 bobId = _activateResolver(bob);
        uint256 carolId = _activateResolver(carol);
        bytes32 disputeId = _initiateDisputedMarket(keccak256("missed-reveal-market"));
        jury.configureTally(
            2,
            0,
            uint8(LibEveMarket.LowQuorumMode.FinalizeInvalid),
            uint8(LibEveMarket.TieBreakMode.ResolveInvalid),
            1 hours
        );
        jury.seedSelectionReady(disputeId, keccak256("missed-reveal-seed"), false);
        jury.selectCommittee(disputeId);

        _commitVote(disputeId, alice, aliceId, uint8(LibEveMarket.MarketOutcome.Yes), keccak256("alice-missed"));
        _commitVote(disputeId, bob, bobId, uint8(LibEveMarket.MarketOutcome.No), keccak256("bob-missed"));
        _commitVote(disputeId, carol, carolId, uint8(LibEveMarket.MarketOutcome.Yes), keccak256("carol-missed"));
        vm.warp(block.timestamp + 1 hours);
        jury.closeCommit(disputeId);
        _revealVote(disputeId, alice, uint8(LibEveMarket.MarketOutcome.Yes), keccak256("alice-missed"));
        _revealVote(disputeId, bob, uint8(LibEveMarket.MarketOutcome.No), keccak256("bob-missed"));

        vm.warp(block.timestamp + 1 hours);
        vm.expectEmit(true, true, true, true);
        emit Events.ResolverSlashed(disputeId, 0, carolId, 20e18);
        jury.closeRevealAndTally(disputeId);

        (uint128 aliceStake,,) = jury.resolverSlashState(aliceId);
        (uint128 bobStake,,) = jury.resolverSlashState(bobId);
        (uint128 carolStake, bool carolLocked,) = jury.resolverSlashState(carolId);
        assertEq(aliceStake, 100e18);
        assertEq(bobStake, 100e18);
        assertEq(carolStake, 80e18);
        assertTrue(carolLocked);
        assertEq(jury.resolverReputation(carolId).missedRevealCount, 1);
        assertEq(jury.resolverReputation(carolId).slashCount, 1);
        assertEq(jury.resolverReputation(bobId).slashCount, 0);
        assertEq(jury.disputeView(disputeId).rewardPoolBond, 20e18);
    }

    function test_CloseRevealAndTallySetsUniquePluralityResult() public {
        uint256 aliceId = _activateResolver(alice);
        uint256 bobId = _activateResolver(bob);
        uint256 carolId = _activateResolver(carol);
        bytes32 disputeId = _initiateDisputedMarket(keccak256("tally-plurality-market"));
        jury.configureTally(
            2,
            0,
            uint8(LibEveMarket.LowQuorumMode.FinalizeInvalid),
            uint8(LibEveMarket.TieBreakMode.ResolveInvalid),
            2 hours
        );
        jury.seedSelectionReady(disputeId, keccak256("tally-plurality-seed"), false);
        jury.selectCommittee(disputeId);

        _commitVote(disputeId, alice, aliceId, uint8(LibEveMarket.MarketOutcome.Yes), keccak256("alice-tally"));
        _commitVote(disputeId, bob, bobId, uint8(LibEveMarket.MarketOutcome.Yes), keccak256("bob-tally"));
        _commitVote(disputeId, carol, carolId, uint8(LibEveMarket.MarketOutcome.No), keccak256("carol-tally"));
        vm.warp(block.timestamp + 1 hours);
        jury.closeCommit(disputeId);
        _revealVote(disputeId, alice, uint8(LibEveMarket.MarketOutcome.Yes), keccak256("alice-tally"));
        _revealVote(disputeId, bob, uint8(LibEveMarket.MarketOutcome.Yes), keccak256("bob-tally"));
        _revealVote(disputeId, carol, uint8(LibEveMarket.MarketOutcome.No), keccak256("carol-tally"));

        vm.warp(block.timestamp + 1 hours);
        jury.closeRevealAndTally(disputeId);

        IResolverJuryFacet.DisputeView memory view_ = jury.disputeView(disputeId);
        assertEq(view_.state, uint8(LibResolverJury.DisputeState.AppealOpen));
        assertEq(view_.provisionalResult, uint8(LibEveMarket.MarketOutcome.Yes));
        assertTrue(view_.hasProvisional);
        assertEq(view_.appealDeadline, block.timestamp + 2 hours);
    }

    function test_CloseRevealAndTallyResolvesTieToInvalidWhenConfigured() public {
        uint256 aliceId = _activateResolver(alice);
        uint256 bobId = _activateResolver(bob);
        _activateResolver(carol);
        bytes32 disputeId = _initiateDisputedMarket(keccak256("tally-tie-market"));
        jury.configureTally(
            2,
            0,
            uint8(LibEveMarket.LowQuorumMode.FinalizeInvalid),
            uint8(LibEveMarket.TieBreakMode.ResolveInvalid),
            1 hours
        );
        jury.seedSelectionReady(disputeId, keccak256("tally-tie-seed"), false);
        jury.selectCommittee(disputeId);

        _commitVote(disputeId, alice, aliceId, uint8(LibEveMarket.MarketOutcome.Yes), keccak256("alice-tie"));
        _commitVote(disputeId, bob, bobId, uint8(LibEveMarket.MarketOutcome.No), keccak256("bob-tie"));
        vm.warp(block.timestamp + 1 hours);
        jury.closeCommit(disputeId);
        _revealVote(disputeId, alice, uint8(LibEveMarket.MarketOutcome.Yes), keccak256("alice-tie"));
        _revealVote(disputeId, bob, uint8(LibEveMarket.MarketOutcome.No), keccak256("bob-tie"));

        vm.warp(block.timestamp + 1 hours);
        jury.closeRevealAndTally(disputeId);

        IResolverJuryFacet.DisputeView memory view_ = jury.disputeView(disputeId);
        assertEq(view_.state, uint8(LibResolverJury.DisputeState.AppealOpen));
        assertEq(view_.provisionalResult, uint8(LibEveMarket.MarketOutcome.Invalid));
    }

    function test_CloseRevealAndTallyLowQuorumFinalizesInvalid() public {
        uint256 aliceId = _activateResolver(alice);
        _activateResolver(bob);
        _activateResolver(carol);
        bytes32 disputeId = _initiateDisputedMarket(keccak256("tally-low-quorum-market"));
        jury.configureTally(
            3,
            0,
            uint8(LibEveMarket.LowQuorumMode.FinalizeInvalid),
            uint8(LibEveMarket.TieBreakMode.ResolveInvalid),
            1 hours
        );
        jury.seedSelectionReady(disputeId, keccak256("tally-low-quorum-seed"), false);
        jury.selectCommittee(disputeId);

        _commitVote(disputeId, alice, aliceId, uint8(LibEveMarket.MarketOutcome.Yes), keccak256("alice-low"));
        vm.warp(block.timestamp + 1 hours);
        jury.closeCommit(disputeId);
        _revealVote(disputeId, alice, uint8(LibEveMarket.MarketOutcome.Yes), keccak256("alice-low"));

        vm.warp(block.timestamp + 1 hours);
        jury.closeRevealAndTally(disputeId);

        IResolverJuryFacet.DisputeView memory view_ = jury.disputeView(disputeId);
        assertEq(view_.state, uint8(LibResolverJury.DisputeState.AppealOpen));
        assertEq(view_.provisionalResult, uint8(LibEveMarket.MarketOutcome.Invalid));
    }

    function test_CloseRevealAndTallyRedrawReopensCommitteeSelection() public {
        uint256 aliceId = _activateResolver(alice);
        _activateResolver(bob);
        _activateResolver(carol);
        bytes32 disputeId = _initiateDisputedMarket(keccak256("tally-redraw-market"));
        jury.configureTally(
            3, 1, uint8(LibEveMarket.LowQuorumMode.Redraw), uint8(LibEveMarket.TieBreakMode.ResolveInvalid), 1 hours
        );
        jury.seedSelectionReady(disputeId, keccak256("tally-redraw-seed"), false);
        jury.selectCommittee(disputeId);

        _commitVote(disputeId, alice, aliceId, uint8(LibEveMarket.MarketOutcome.Yes), keccak256("alice-redraw"));
        vm.warp(block.timestamp + 1 hours);
        jury.closeCommit(disputeId);
        _revealVote(disputeId, alice, uint8(LibEveMarket.MarketOutcome.Yes), keccak256("alice-redraw"));

        vm.warp(block.timestamp + 1 hours);
        jury.closeRevealAndTally(disputeId);

        IResolverJuryFacet.DisputeView memory view_ = jury.disputeView(disputeId);
        assertEq(view_.state, uint8(LibResolverJury.DisputeState.CommitteeSelectionPending));
        assertEq(view_.committeeSize, 0);
        assertEq(view_.validRevealCount, 0);
        assertEq(view_.seed, bytes32(0));
        assertEq(jury.committeeMembers(disputeId, 0).length, 0);

        jury.openRandomnessCommit(disputeId);
        assertGt(jury.disputeView(disputeId).randomnessCommitDeadline, block.timestamp);
    }

    function test_OpenAppealCollectsBondTokenAndAdvancesRound() public {
        bytes32 disputeId = _openAppealableDispute(keccak256("appeal-success-market"));
        uint128 requiredBond = 1 ether;
        bondToken.mint(alice, requiredBond);
        vm.prank(alice);
        bondToken.approve(address(jury), requiredBond);

        vm.expectEmit(true, true, true, true);
        emit Events.AppealOpened(disputeId, 1, alice, requiredBond);
        vm.prank(alice);
        jury.openAppeal(disputeId);

        IResolverJuryFacet.DisputeView memory view_ = jury.disputeView(disputeId);
        assertEq(view_.state, uint8(LibResolverJury.DisputeState.CommitteeSelectionPending));
        assertEq(view_.currentRound, 1);
        assertEq(view_.disputeBondBase, 0.5 ether);
        assertEq(bondToken.balanceOf(alice), 0);
        assertEq(eveToken.balanceOf(address(jury)), 3 * RESOLVER_STAKE);
        assertEq(bondToken.balanceOf(address(jury)), requiredBond);

        (uint128 storedBond, address appellant) = jury.appealBondForRound(disputeId, 1);
        assertEq(storedBond, requiredBond);
        assertEq(appellant, alice);
    }

    function test_OpenAppealRejectsUnderfundedBondTokenAndRetainsResult() public {
        bytes32 disputeId = _openAppealableDispute(keccak256("appeal-underfunded-market"));
        uint128 requiredBond = 1 ether;
        uint128 shortBond = requiredBond - 1;
        bondToken.mint(alice, shortBond);
        vm.prank(alice);
        bondToken.approve(address(jury), shortBond);

        vm.expectRevert(abi.encodeWithSelector(Errors.AppealBondTooLow.selector, requiredBond, shortBond));
        vm.prank(alice);
        jury.openAppeal(disputeId);

        IResolverJuryFacet.DisputeView memory view_ = jury.disputeView(disputeId);
        assertEq(view_.state, uint8(LibResolverJury.DisputeState.AppealOpen));
        assertEq(view_.currentRound, 0);
        assertEq(view_.provisionalResult, uint8(LibEveMarket.MarketOutcome.Yes));
        assertEq(eveToken.balanceOf(address(jury)), 3 * RESOLVER_STAKE);
        assertEq(bondToken.balanceOf(address(jury)), 0);
    }

    function test_OpenAppealRejectsLateAppeal() public {
        bytes32 disputeId = _openAppealableDispute(keccak256("appeal-late-market"));
        uint128 requiredBond = 1 ether;
        bondToken.mint(alice, requiredBond);
        vm.prank(alice);
        bondToken.approve(address(jury), requiredBond);

        vm.warp(jury.disputeView(disputeId).appealDeadline);

        vm.expectRevert(abi.encodeWithSelector(Errors.AppealWindowClosed.selector, disputeId));
        vm.prank(alice);
        jury.openAppeal(disputeId);

        assertEq(eveToken.balanceOf(address(jury)), 3 * RESOLVER_STAKE);
        assertEq(bondToken.balanceOf(address(jury)), 0);
    }

    function test_OpenAppealRejectsMaxRoundAndRetainsResult() public {
        bytes32 disputeId = _openAppealableDispute(keccak256("appeal-max-market"));
        jury.configureAppealParams(0, 20_000);
        uint128 requiredBond = 1 ether;
        bondToken.mint(alice, requiredBond);
        vm.prank(alice);
        bondToken.approve(address(jury), requiredBond);

        vm.expectRevert(abi.encodeWithSelector(Errors.MaxAppealRoundsReached.selector, uint8(0)));
        vm.prank(alice);
        jury.openAppeal(disputeId);

        IResolverJuryFacet.DisputeView memory view_ = jury.disputeView(disputeId);
        assertEq(view_.state, uint8(LibResolverJury.DisputeState.AppealOpen));
        assertEq(view_.currentRound, 0);
        assertEq(view_.provisionalResult, uint8(LibEveMarket.MarketOutcome.Yes));
        assertEq(eveToken.balanceOf(address(jury)), 3 * RESOLVER_STAKE);
        assertEq(bondToken.balanceOf(address(jury)), 0);
    }

    function test_FinalizeDisputeRoutesSuccessfulAppealBond() public {
        bytes32 marketId = keccak256("appeal-route-success-market");
        bytes32 disputeId = _openAppealableDispute(marketId);
        jury.configureAppealRouting(
            [uint16(7_000), uint16(1_000), uint16(1_000), uint16(1_000)], [uint16(4_000), uint16(3_000), uint16(3_000)]
        );
        jury.seedResolutionClaimant(marketId, claimant, uint8(LibEveMarket.MarketOutcome.No));
        _openBondedAppeal(disputeId, alice, 1 ether);
        _activateResolver(dave);
        _activateResolver(erin);
        _resolveAppealRound(disputeId, uint8(LibEveMarket.MarketOutcome.No), keccak256("appeal-success-route"));

        vm.warp(jury.disputeView(disputeId).appealDeadline);
        jury.finalizeDispute(disputeId);

        assertEq(bondToken.balanceOf(alice), 0.72 ether);
        assertEq(bondToken.balanceOf(bob), 0.02 ether);
        assertEq(bondToken.balanceOf(carol), 0.02 ether);
        assertEq(bondToken.balanceOf(dave), 0.02 ether);
        assertEq(bondToken.balanceOf(erin), 0.02 ether);
        assertEq(bondToken.balanceOf(claimant), 0.1 ether);
        assertEq(bondToken.balanceOf(jury.eveTreasury()), 0.1 ether);
        assertEq(eveToken.balanceOf(address(jury)), 5 * RESOLVER_STAKE);
        assertEq(bondToken.balanceOf(address(jury)), 0);
        assertEq(jury.disputeView(disputeId).finalResult, uint8(LibEveMarket.MarketOutcome.No));
    }

    function test_FinalizeDisputeRoutesFailedAppealBond() public {
        bytes32 marketId = keccak256("appeal-route-failure-market");
        bytes32 disputeId = _openAppealableDispute(marketId);
        jury.configureAppealRouting(
            [uint16(7_000), uint16(1_000), uint16(1_000), uint16(1_000)], [uint16(4_000), uint16(3_000), uint16(3_000)]
        );
        jury.seedResolutionClaimant(marketId, claimant, uint8(LibEveMarket.MarketOutcome.Yes));
        _openBondedAppeal(disputeId, alice, 1 ether);
        _activateResolver(dave);
        _activateResolver(erin);
        _resolveAppealRound(disputeId, uint8(LibEveMarket.MarketOutcome.Yes), keccak256("appeal-failure-route"));

        vm.warp(jury.disputeView(disputeId).appealDeadline);
        jury.finalizeDispute(disputeId);

        assertEq(bondToken.balanceOf(alice), 0.08 ether);
        assertEq(bondToken.balanceOf(bob), 0.08 ether);
        assertEq(bondToken.balanceOf(carol), 0.08 ether);
        assertEq(bondToken.balanceOf(dave), 0.08 ether);
        assertEq(bondToken.balanceOf(erin), 0.08 ether);
        assertEq(bondToken.balanceOf(claimant), 0.3 ether);
        assertEq(bondToken.balanceOf(jury.eveTreasury()), 0.3 ether);
        assertEq(eveToken.balanceOf(address(jury)), 5 * RESOLVER_STAKE);
        assertEq(bondToken.balanceOf(address(jury)), 0);
        assertEq(jury.disputeView(disputeId).finalResult, uint8(LibEveMarket.MarketOutcome.Yes));
    }

    function test_FinalizeDisputeRoutesAbsentFailureClaimantToTreasury() public {
        bytes32 disputeId = _openAppealableDispute(keccak256("appeal-route-absent-claimant-market"));
        jury.configureAppealRouting(
            [uint16(7_000), uint16(1_000), uint16(1_000), uint16(1_000)], [uint16(4_000), uint16(3_000), uint16(3_000)]
        );
        _openBondedAppeal(disputeId, alice, 1 ether);
        _activateResolver(dave);
        _activateResolver(erin);
        _resolveAppealRound(disputeId, uint8(LibEveMarket.MarketOutcome.Yes), keccak256("appeal-absent-route"));

        vm.warp(jury.disputeView(disputeId).appealDeadline);
        jury.finalizeDispute(disputeId);

        assertEq(bondToken.balanceOf(alice), 0.08 ether);
        assertEq(bondToken.balanceOf(bob), 0.08 ether);
        assertEq(bondToken.balanceOf(carol), 0.08 ether);
        assertEq(bondToken.balanceOf(dave), 0.08 ether);
        assertEq(bondToken.balanceOf(erin), 0.08 ether);
        assertEq(bondToken.balanceOf(jury.eveTreasury()), 0.6 ether);
        assertEq(eveToken.balanceOf(address(jury)), 5 * RESOLVER_STAKE);
        assertEq(bondToken.balanceOf(address(jury)), 0);
    }

    function test_FinalizeDisputeRejectsInvalidAppealRoutingAndRetainsBond() public {
        bytes32 disputeId = _openAppealableDispute(keccak256("appeal-route-invalid-market"));
        jury.configureAppealRouting(
            [uint16(7_000), uint16(1_000), uint16(1_000), uint16(1_000)], [uint16(4_000), uint16(3_000), uint16(2_999)]
        );
        _openBondedAppeal(disputeId, alice, 1 ether);
        _activateResolver(dave);
        _activateResolver(erin);
        _resolveAppealRound(disputeId, uint8(LibEveMarket.MarketOutcome.Yes), keccak256("appeal-invalid-route"));

        vm.warp(jury.disputeView(disputeId).appealDeadline);
        vm.expectRevert(Errors.InvalidRoutingSplit.selector);
        jury.finalizeDispute(disputeId);

        IResolverJuryFacet.DisputeView memory view_ = jury.disputeView(disputeId);
        assertFalse(view_.finalized);
        assertEq(view_.state, uint8(LibResolverJury.DisputeState.AppealOpen));
        assertEq(eveToken.balanceOf(address(jury)), 5 * RESOLVER_STAKE);
        assertEq(bondToken.balanceOf(address(jury)), 1 ether);
        (uint128 storedBond,) = jury.appealBondForRound(disputeId, 1);
        assertEq(storedBond, 1 ether);
    }

    function test_FinalizeDisputeDistributesRewardsAndAppliesReputation() public {
        (bytes32 disputeId, uint256 aliceId, uint256 bobId, uint256 carolId) =
            _openFinalizableRewardDispute(keccak256("finality-reward-market"));

        assertEq(jury.resolverUnresolvedCommittees(aliceId), 1);
        assertEq(jury.disputeView(disputeId).rewardPoolBond, 20e18);

        vm.expectRevert(abi.encodeWithSelector(Errors.AppealWindowClosed.selector, disputeId));
        jury.finalizeDispute(disputeId);

        vm.warp(jury.disputeView(disputeId).appealDeadline);

        vm.expectEmit(true, true, true, true);
        emit Events.RewardDistributed(disputeId, aliceId, alice, address(eveToken), 10e18);
        vm.expectEmit(true, true, true, true);
        emit Events.RewardDistributed(disputeId, bobId, bob, address(eveToken), 10e18);
        vm.expectEmit(true, true, false, true);
        emit Events.DisputeFinalized(
            disputeId, jury.disputeView(disputeId).marketId, uint8(LibEveMarket.MarketOutcome.Yes)
        );
        jury.finalizeDispute(disputeId);

        IResolverJuryFacet.DisputeView memory view_ = jury.disputeView(disputeId);
        assertTrue(view_.finalized);
        assertTrue(view_.rewardsDistributed);
        assertTrue(view_.reputationApplied);
        assertEq(view_.state, uint8(LibResolverJury.DisputeState.Finalized));
        assertEq(view_.finalResult, uint8(LibEveMarket.MarketOutcome.Yes));
        assertEq(eveToken.balanceOf(alice), 10e18);
        assertEq(eveToken.balanceOf(bob), 10e18);
        assertEq(eveToken.balanceOf(carol), 0);
        assertEq(jury.resolverUnresolvedCommittees(aliceId), 0);
        assertEq(jury.resolverUnresolvedCommittees(bobId), 0);
        assertEq(jury.resolverUnresolvedCommittees(carolId), 0);
        assertEq(jury.resolverReputation(aliceId).finalAgreementCount, 1);
        assertEq(jury.resolverReputation(bobId).finalAgreementCount, 1);
        assertEq(jury.resolverReputation(carolId).finalAgreementCount, 0);

        vm.expectRevert(abi.encodeWithSelector(Errors.DisputeAlreadyFinalized.selector, disputeId));
        jury.finalizeDispute(disputeId);
    }

    function test_FinalizeDisputeDistributesProtocolFeeAllocationToValidReveals() public {
        (bytes32 disputeId, uint256 aliceId, uint256 bobId,) =
            _openFinalizableRewardDispute(keccak256("finality-protocol-fee-market"));
        bytes32 marketId = jury.disputeView(disputeId).marketId;
        MockUSDC collateralToken = new MockUSDC();
        uint128 accruedProtocolFees = 101e6;
        uint16 allocationBps = 2_500;
        uint256 expectedRewardPool = 25_250_000;
        uint256 expectedPerResolver = 12_625_000;

        jury.configureProtocolFeeAllocation(allocationBps);
        jury.seedProtocolFees(marketId, address(collateralToken), accruedProtocolFees);
        collateralToken.mint(address(jury), accruedProtocolFees);

        vm.warp(jury.disputeView(disputeId).appealDeadline);

        vm.expectEmit(true, true, true, true);
        emit Events.RewardDistributed(disputeId, aliceId, alice, address(collateralToken), expectedPerResolver);
        vm.expectEmit(true, true, true, true);
        emit Events.RewardDistributed(disputeId, bobId, bob, address(collateralToken), expectedPerResolver);
        jury.finalizeDispute(disputeId);

        assertEq(collateralToken.balanceOf(alice), expectedPerResolver);
        assertEq(collateralToken.balanceOf(bob), expectedPerResolver);
        assertEq(collateralToken.balanceOf(jury.eveTreasury()), 0);
        assertEq(jury.protocolFeesAccrued(marketId), accruedProtocolFees - uint128(expectedRewardPool));
    }

    function test_FinalizeDisputeRoutesRewardPoolToTreasuryWhenNoValidReveal() public {
        bytes32 disputeId = _openFinalizableNoRevealDispute(keccak256("finality-treasury-market"));
        address treasury = jury.eveTreasury();
        uint256 treasuryBefore = eveToken.balanceOf(treasury);

        vm.warp(jury.disputeView(disputeId).appealDeadline);
        jury.finalizeDispute(disputeId);

        IResolverJuryFacet.DisputeView memory view_ = jury.disputeView(disputeId);
        assertTrue(view_.finalized);
        assertTrue(view_.rewardsDistributed);
        assertEq(view_.finalResult, uint8(LibEveMarket.MarketOutcome.Invalid));
        assertEq(eveToken.balanceOf(treasury), treasuryBefore + 30e18);
    }

    function test_FinalizeDisputeRoutesProtocolFeeAllocationToTreasuryWhenNoValidReveal() public {
        bytes32 disputeId = _openFinalizableNoRevealDispute(keccak256("finality-protocol-fee-treasury-market"));
        bytes32 marketId = jury.disputeView(disputeId).marketId;
        address treasury = jury.eveTreasury();
        MockUSDC collateralToken = new MockUSDC();
        uint128 accruedProtocolFees = 10_000_001;
        uint16 allocationBps = 4_000;
        uint256 expectedRewardPool = 4_000_000;

        jury.configureProtocolFeeAllocation(allocationBps);
        jury.seedProtocolFees(marketId, address(collateralToken), accruedProtocolFees);
        collateralToken.mint(address(jury), accruedProtocolFees);

        vm.warp(jury.disputeView(disputeId).appealDeadline);
        jury.finalizeDispute(disputeId);

        assertEq(collateralToken.balanceOf(treasury), expectedRewardPool);
        assertEq(jury.protocolFeesAccrued(marketId), accruedProtocolFees - uint128(expectedRewardPool));
    }

    function _initiateDisputedMarket(bytes32 marketId) internal returns (bytes32 disputeId) {
        jury.seedMarket(marketId, uint8(LibEveMarket.MarketType.CLOB), uint8(LibEveMarket.MarketState.Disputed), 0);
        disputeId = jury.disputeIdForMarket(marketId);
        jury.initiateViaSelf(marketId);
    }

    function _commitVote(bytes32 disputeId, address owner, uint256 identityId, uint8 outcome, bytes32 salt) internal {
        vm.prank(owner);
        jury.commitVote(disputeId, keccak256(abi.encode(disputeId, identityId, outcome, salt)));
    }

    function _revealVote(bytes32 disputeId, address owner, uint8 outcome, bytes32 salt) internal {
        vm.prank(owner);
        jury.revealVote(disputeId, outcome, salt);
    }

    function _commitVoteByIdentity(bytes32 disputeId, uint256 identityId, uint8 outcome, bytes32 salt) internal {
        _commitVote(
            disputeId, identity.ownerOf(identityId), identityId, outcome, keccak256(abi.encode(salt, identityId))
        );
    }

    function _revealVoteByIdentity(bytes32 disputeId, uint256 identityId, uint8 outcome, bytes32 salt) internal {
        _revealVote(disputeId, identity.ownerOf(identityId), outcome, keccak256(abi.encode(salt, identityId)));
    }

    function _openBondedAppeal(bytes32 disputeId, address appellant, uint128 requiredBond) internal {
        bondToken.mint(appellant, requiredBond);
        vm.prank(appellant);
        bondToken.approve(address(jury), requiredBond);
        vm.prank(appellant);
        jury.openAppeal(disputeId);
    }

    function _resolveAppealRound(bytes32 disputeId, uint8 outcome, bytes32 salt) internal {
        jury.seedSelectionReady(disputeId, keccak256(abi.encode(salt, "seed")), false);
        jury.selectCommittee(disputeId);
        uint8 round = jury.disputeView(disputeId).currentRound;
        uint256[] memory members = jury.committeeMembers(disputeId, round);
        for (uint256 index; index < members.length; ++index) {
            _commitVoteByIdentity(disputeId, members[index], outcome, salt);
        }

        vm.warp(block.timestamp + 1 hours);
        jury.closeCommit(disputeId);
        for (uint256 index; index < members.length; ++index) {
            _revealVoteByIdentity(disputeId, members[index], outcome, salt);
        }

        vm.warp(block.timestamp + 1 hours);
        jury.closeRevealAndTally(disputeId);
    }

    function _openAppealableDispute(bytes32 marketId) internal returns (bytes32 disputeId) {
        uint256 aliceId = _activateResolver(alice);
        uint256 bobId = _activateResolver(bob);
        uint256 carolId = _activateResolver(carol);
        disputeId = _initiateDisputedMarket(marketId);
        jury.configureTally(
            2,
            0,
            uint8(LibEveMarket.LowQuorumMode.FinalizeInvalid),
            uint8(LibEveMarket.TieBreakMode.ResolveInvalid),
            2 hours
        );
        jury.seedSelectionReady(disputeId, keccak256("appealable-seed"), false);
        jury.selectCommittee(disputeId);

        _commitVote(disputeId, alice, aliceId, uint8(LibEveMarket.MarketOutcome.Yes), keccak256("alice-appeal"));
        _commitVote(disputeId, bob, bobId, uint8(LibEveMarket.MarketOutcome.Yes), keccak256("bob-appeal"));
        _commitVote(disputeId, carol, carolId, uint8(LibEveMarket.MarketOutcome.No), keccak256("carol-appeal"));
        vm.warp(block.timestamp + 1 hours);
        jury.closeCommit(disputeId);
        _revealVote(disputeId, alice, uint8(LibEveMarket.MarketOutcome.Yes), keccak256("alice-appeal"));
        _revealVote(disputeId, bob, uint8(LibEveMarket.MarketOutcome.Yes), keccak256("bob-appeal"));
        _revealVote(disputeId, carol, uint8(LibEveMarket.MarketOutcome.No), keccak256("carol-appeal"));
        vm.warp(block.timestamp + 1 hours);
        jury.closeRevealAndTally(disputeId);
    }

    function _openFinalizableRewardDispute(bytes32 marketId)
        internal
        returns (bytes32 disputeId, uint256 aliceId, uint256 bobId, uint256 carolId)
    {
        aliceId = _activateResolver(alice);
        bobId = _activateResolver(bob);
        carolId = _activateResolver(carol);
        disputeId = _initiateDisputedMarket(marketId);
        jury.configureTally(
            2,
            0,
            uint8(LibEveMarket.LowQuorumMode.FinalizeInvalid),
            uint8(LibEveMarket.TieBreakMode.ResolveInvalid),
            2 hours
        );
        jury.seedSelectionReady(disputeId, keccak256("finality-reward-seed"), false);
        jury.selectCommittee(disputeId);

        _commitVote(disputeId, alice, aliceId, uint8(LibEveMarket.MarketOutcome.Yes), keccak256("alice-finality"));
        _commitVote(disputeId, bob, bobId, uint8(LibEveMarket.MarketOutcome.Yes), keccak256("bob-finality"));
        _commitVote(disputeId, carol, carolId, uint8(LibEveMarket.MarketOutcome.No), keccak256("carol-finality"));
        vm.warp(block.timestamp + 1 hours);
        jury.closeCommit(disputeId);
        _revealVote(disputeId, alice, uint8(LibEveMarket.MarketOutcome.Yes), keccak256("alice-finality"));
        _revealVote(disputeId, bob, uint8(LibEveMarket.MarketOutcome.Yes), keccak256("bob-finality"));
        vm.warp(block.timestamp + 1 hours);
        jury.closeRevealAndTally(disputeId);
    }

    function _openFinalizableNoRevealDispute(bytes32 marketId) internal returns (bytes32 disputeId) {
        _activateResolver(alice);
        _activateResolver(bob);
        _activateResolver(carol);
        disputeId = _initiateDisputedMarket(marketId);
        jury.configureTally(
            1,
            0,
            uint8(LibEveMarket.LowQuorumMode.FinalizeInvalid),
            uint8(LibEveMarket.TieBreakMode.ResolveInvalid),
            1 hours
        );
        jury.seedSelectionReady(disputeId, keccak256("finality-no-reveal-seed"), false);
        jury.selectCommittee(disputeId);
        vm.warp(block.timestamp + 1 hours);
        jury.closeCommit(disputeId);
        vm.warp(block.timestamp + 1 hours);
        jury.closeRevealAndTally(disputeId);
    }

    function _activateResolver(address owner) internal returns (uint256 identityId) {
        feeToken.mint(owner, 1e6);
        vm.prank(owner);
        feeToken.approve(address(jury), 1e6);
        vm.prank(owner);
        identityId = jury.mintIdentity();

        vm.prank(owner);
        jury.setResolverRole(true);

        eveToken.mint(owner, RESOLVER_STAKE);
        vm.prank(owner);
        eveToken.approve(address(jury), RESOLVER_STAKE);
        vm.prank(owner);
        jury.depositResolverStake(RESOLVER_STAKE);

        vm.prank(owner);
        jury.activateResolver();
    }
}
