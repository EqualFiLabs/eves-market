// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/// forge-config: default.fuzz.runs = 100

import {Test} from "../../lib/forge-std/src/Test.sol";

import {IResolverJuryFacet} from "src/interfaces/IResolverJuryFacet.sol";
import {Errors} from "src/libraries/Errors.sol";
import {LibEveMarket} from "src/libraries/LibEveMarket.sol";
import {LibResolverJury} from "src/libraries/LibResolverJury.sol";
import {BondManagerFacet} from "src/facets/BondManagerFacet.sol";
import {ResolverJuryFacet} from "src/facets/ResolverJuryFacet.sol";
import {ResolverRegistryFacet} from "src/facets/ResolverRegistryFacet.sol";
import {ResolverRegistryReputationFacet} from "src/facets/ResolverRegistryReputationFacet.sol";
import {ResolverRegistryRewardsFacet} from "src/facets/ResolverRegistryRewardsFacet.sol";
import {ResolverRegistryViewFacet} from "src/facets/ResolverRegistryViewFacet.sol";
import {EveIdentity} from "src/tokens/EveIdentity.sol";
import {MockEveToken} from "test/helpers/MockEveToken.sol";
import {MockUSDG} from "test/helpers/MockUSDG.sol";

contract ResolverJuryEconomicsPropertyHarness is
    ResolverJuryFacet,
    ResolverRegistryFacet,
    ResolverRegistryViewFacet,
    ResolverRegistryRewardsFacet,
    ResolverRegistryReputationFacet,
    BondManagerFacet
{
    function configure(address eveIdentity, address mintFeeToken, address eveToken) external {
        LibResolverJury.store().eveIdentity = eveIdentity;
        LibEveMarket.MarketConfig storage config = LibEveMarket.store().config;
        config.eveToken = eveToken;
        config.bondToken = eveToken;
        config.eveTreasury = address(uint160(uint256(keccak256("resolver-economics-treasury"))));
        config.resolverJuryConfig.identityMintFeeToken = mintFeeToken;
        config.resolverJuryConfig.identityMintFee = 1e6;
        config.resolverJuryConfig.resolverSeatStake = 100e18;
        config.resolverJuryConfig.activeEpochSize = 16;
        config.resolverJuryConfig.participationGraceCount = 5;
        config.resolverJuryConfig.concurrencyLimit = 5;
        config.resolverJuryConfig.commitDuration = 1 hours;
        config.resolverJuryConfig.revealDuration = 1 hours;
        config.resolverJuryConfig.randomnessCommitDuration = 1 hours;
        config.resolverJuryConfig.randomnessRevealDuration = 1 hours;
        config.resolverJuryConfig.minRandomnessReveals = 2;
        config.resolverJuryConfig.randomnessFailureMode = LibEveMarket.RandomnessFailureMode.AllEligible;
        config.resolverJuryConfig.allEligibleFallbackCap = 10;
        config.resolverJuryConfig.quorum = 2;
        config.resolverJuryConfig.appealWindow = 1 hours;
        config.resolverJuryConfig.lowQuorumMode = LibEveMarket.LowQuorumMode.FinalizeInvalid;
        config.resolverJuryConfig.tieBreakMode = LibEveMarket.TieBreakMode.ResolveInvalid;
        config.resolverJuryConfig.maxAppealRounds = 1;
        config.resolverJuryConfig.appealBondMultiplierBps = 20_000;
        config.resolverJuryConfig.missedCommitSlashBps = 1_000;
        config.resolverJuryConfig.missedRevealSlashBps = 2_000;
        config.resolverJuryConfig.invalidRevealSlashBps = 3_000;
        config.resolverJuryConfig.slashCooldown = 1 days;
        delete config.resolverJuryConfig.committeeSizesByRound;
        config.resolverJuryConfig.committeeSizesByRound.push(3);
        config.resolverJuryConfig.committeeSizesByRound.push(5);
        config.resolutionBondL2 = 0.5 ether;
    }

    function configureIncentives(
        address bondToken,
        uint128 randomness,
        uint128 selectCommittee,
        uint128 closeCommit,
        uint128 closeReveal,
        uint128 openAppeal,
        uint128 finalize
    ) external {
        LibEveMarket.MarketConfig storage config = LibEveMarket.store().config;
        config.bondToken = bondToken;
        config.resolverJuryConfig.incentiveRandomness = randomness;
        config.resolverJuryConfig.incentiveSelectCommittee = selectCommittee;
        config.resolverJuryConfig.incentiveCloseCommit = closeCommit;
        config.resolverJuryConfig.incentiveCloseReveal = closeReveal;
        config.resolverJuryConfig.incentiveOpenAppeal = openAppeal;
        config.resolverJuryConfig.incentiveFinalize = finalize;
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

    function configureSlashBps(
        uint256 missedCommitSlashBps,
        uint256 missedRevealSlashBps,
        uint256 invalidRevealSlashBps
    ) external {
        if (
            missedCommitSlashBps > type(uint16).max || missedRevealSlashBps > type(uint16).max
                || invalidRevealSlashBps > type(uint16).max
        ) {
            revert Errors.InvalidAmount(missedCommitSlashBps);
        }

        LibEveMarket.ResolverJuryConfig storage config = LibEveMarket.store().config.resolverJuryConfig;
        config.missedCommitSlashBps = uint16(missedCommitSlashBps);
        config.missedRevealSlashBps = uint16(missedRevealSlashBps);
        config.invalidRevealSlashBps = uint16(invalidRevealSlashBps);
    }

    function configureAppealRouting(
        address bondToken,
        uint16[4] calldata successRouting,
        uint16[3] calldata failureRouting
    ) external {
        LibEveMarket.MarketConfig storage config = LibEveMarket.store().config;
        config.bondToken = bondToken;
        config.resolverJuryConfig.appealSuccessRoutingBps = successRouting;
        config.resolverJuryConfig.appealFailureRoutingBps = failureRouting;
    }

    function configureConfigDrivenBehavior(
        address bondToken,
        uint256 resolverSeatStake,
        uint256 committeeSize,
        uint256 nextCommitteeSize,
        uint256 commitDuration,
        uint256 revealDuration,
        uint256 quorum,
        uint256 missedRevealSlashBps,
        uint256 appealBondMultiplierBps,
        uint256 closeCommitIncentive
    ) external {
        if (
            resolverSeatStake > type(uint128).max || committeeSize > type(uint16).max
                || nextCommitteeSize > type(uint16).max || commitDuration > type(uint64).max
                || revealDuration > type(uint64).max || quorum > type(uint32).max
                || missedRevealSlashBps > type(uint16).max || appealBondMultiplierBps > type(uint16).max
                || closeCommitIncentive > type(uint128).max
        ) {
            revert Errors.InvalidAmount(resolverSeatStake);
        }

        LibEveMarket.MarketConfig storage config = LibEveMarket.store().config;
        config.bondToken = bondToken;
        config.resolverJuryConfig.resolverSeatStake = uint128(resolverSeatStake);
        delete config.resolverJuryConfig.committeeSizesByRound;
        config.resolverJuryConfig.committeeSizesByRound.push(uint16(committeeSize));
        config.resolverJuryConfig.committeeSizesByRound.push(uint16(nextCommitteeSize));
        config.resolverJuryConfig.maxAppealRounds = 1;
        config.resolverJuryConfig.commitDuration = uint64(commitDuration);
        config.resolverJuryConfig.revealDuration = uint64(revealDuration);
        config.resolverJuryConfig.quorum = uint32(quorum);
        config.resolverJuryConfig.lowQuorumMode = LibEveMarket.LowQuorumMode.FinalizeInvalid;
        config.resolverJuryConfig.tieBreakMode = LibEveMarket.TieBreakMode.ResolveInvalid;
        config.resolverJuryConfig.missedRevealSlashBps = uint16(missedRevealSlashBps);
        config.resolverJuryConfig.appealBondMultiplierBps = uint16(appealBondMultiplierBps);
        config.resolverJuryConfig.incentiveCloseCommit = uint128(closeCommitIncentive);
    }

    function resolverStakeOf(uint256 identityId) external view returns (uint128) {
        return LibResolverJury.store().identities[identityId].resolverStake;
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

    function requiredAppealBondForRound(bytes32 disputeId, uint256 targetRound)
        external
        view
        returns (uint128 requiredBond)
    {
        if (targetRound > type(uint8).max) {
            revert Errors.InvalidAmount(targetRound);
        }

        LibResolverJury.Dispute storage dispute = LibResolverJury.store().disputes[disputeId];
        requiredBond = _requiredAppealBond(dispute, LibEveMarket.store().config.resolverJuryConfig, uint8(targetRound));
    }

    function storedAppealBondForRound(bytes32 disputeId, uint8 round)
        external
        view
        returns (uint128 storedBond, address appellant)
    {
        LibResolverJury.Dispute storage dispute = LibResolverJury.store().disputes[disputeId];
        storedBond = dispute.appealBond[round];
        appellant = dispute.appellant[round];
    }

    function seedDisputedMarket(bytes32 marketId) external returns (bytes32 disputeId) {
        LibEveMarket.Market storage market = LibEveMarket.store().markets[marketId];
        market.marketId = marketId;
        market.marketType = LibEveMarket.MarketType.CLOB;
        market.state = LibEveMarket.MarketState.Disputed;
        disputeId = this.disputeIdForMarket(marketId);
        IResolverJuryFacet(address(this)).initiateDispute(marketId);
    }

    function seedSelectionReady(bytes32 disputeId, bytes32 seed) external {
        LibResolverJury.Dispute storage dispute = LibResolverJury.store().disputes[disputeId];
        dispute.rounds[dispute.currentRound].seed = seed == bytes32(0) ? keccak256("economics-seed") : seed;
    }

    function finalizeFromJury(bytes32, uint8) external {}
}

contract ResolverJuryEconomicsPropertiesTest is Test {
    address internal alice = makeAddr("economics-alice");
    address internal bob = makeAddr("economics-bob");
    address internal carol = makeAddr("economics-carol");
    address internal dave = makeAddr("economics-dave");
    address internal erin = makeAddr("economics-erin");

    ResolverJuryEconomicsPropertyHarness internal jury;
    EveIdentity internal identity;
    MockUSDG internal feeToken;
    MockEveToken internal eveToken;
    MockEveToken internal bondToken;

    struct ConfigDrivenInputs {
        uint16 committeeSize;
        uint16 nextCommitteeSize;
        uint64 commitDuration;
        uint64 revealDuration;
        uint32 quorum;
        uint16 missedRevealSlashBps;
        uint16 appealBondMultiplierBps;
        uint128 closeCommitIncentive;
    }

    function setUp() public {
        jury = new ResolverJuryEconomicsPropertyHarness();
        identity = new EveIdentity(address(jury), "Eve Identity", "EVE-ID");
        feeToken = new MockUSDG();
        eveToken = new MockEveToken();
        bondToken = new MockEveToken();
        jury.configure(address(identity), address(feeToken), address(bondToken));
    }

    function testFuzz_BehaviorIsConfigDrivenWithNoHardcodedEconomicValue(
        bool useFiveMemberCommittee,
        uint64 commitDurationInput,
        uint64 revealDurationInput,
        uint16 slashInput,
        uint16 appealMultiplierInput,
        uint128 incentiveInput,
        bytes32 seed
    ) public {
        // Feature: resolver-identity-jury, Property 22: Behavior is config-driven with no hardcoded economic value
        ConfigDrivenInputs memory config = _configDrivenInputs(
            useFiveMemberCommittee,
            commitDurationInput,
            revealDurationInput,
            slashInput,
            appealMultiplierInput,
            incentiveInput
        );
        uint256 aliceId = _activateFiveResolvers();
        _assertStakeRequirementConfig(aliceId, config);

        bytes32 disputeId = _selectConfigDrivenCommittee(config, seed);
        uint256[] memory members = jury.committeeMembers(disputeId, 0);
        _commitAllSelected(disputeId, members);
        address caller = _closeCommitAndAssertConfig(disputeId, config);
        _closeRevealAndAssertConfig(disputeId, members, config);
        _openAppealAndAssertConfig(disputeId, caller, config);
    }

    function testFuzz_FixedSeatStakeYieldsEqualWeightVoting(uint128 extraStakeInput, bytes32 seed, bytes32 salt)
        public
    {
        uint128 extraStake = uint128(bound(extraStakeInput, 1, 150e18));
        uint256 aliceId = _activateResolver(alice);
        uint256 bobId = _activateResolver(bob);
        uint256 carolId = _activateResolver(carol);
        _expectStakeTopUpRejected(alice, extraStake);

        bytes32 disputeId = jury.seedDisputedMarket(keccak256("equal-weight-voting-market"));
        assertTrue(jury.isEligibleResolver(aliceId, disputeId));
        assertTrue(jury.isEligibleResolver(bobId, disputeId));
        assertTrue(jury.isEligibleResolver(carolId, disputeId));
        assertEq(jury.resolverStakeOf(aliceId), 100e18);
        assertEq(jury.resolverStakeOf(bobId), 100e18);
        assertEq(jury.resolverStakeOf(carolId), 100e18);

        jury.seedSelectionReady(disputeId, seed);
        jury.selectCommittee(disputeId);

        // Feature: resolver-identity-jury, Property 4: Fixed seat stake yields equal-weight voting
        _commitVote(
            disputeId, alice, aliceId, uint8(LibEveMarket.MarketOutcome.Yes), keccak256(abi.encode(salt, alice))
        );
        _commitVote(disputeId, bob, bobId, uint8(LibEveMarket.MarketOutcome.No), keccak256(abi.encode(salt, bob)));
        _commitVote(disputeId, carol, carolId, uint8(LibEveMarket.MarketOutcome.No), keccak256(abi.encode(salt, carol)));
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        jury.closeCommit(disputeId);
        _revealVote(disputeId, alice, uint8(LibEveMarket.MarketOutcome.Yes), keccak256(abi.encode(salt, alice)));
        _revealVote(disputeId, bob, uint8(LibEveMarket.MarketOutcome.No), keccak256(abi.encode(salt, bob)));
        _revealVote(disputeId, carol, uint8(LibEveMarket.MarketOutcome.No), keccak256(abi.encode(salt, carol)));
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        jury.closeRevealAndTally(disputeId);

        (uint8[] memory outcomes, uint256[] memory counts) = jury.outcomeTally(disputeId, 0);
        assertEq(outcomes[0], uint8(LibEveMarket.MarketOutcome.Yes));
        assertEq(counts[0], 1);
        assertEq(outcomes[1], uint8(LibEveMarket.MarketOutcome.No));
        assertEq(counts[1], 2);

        IResolverJuryFacet.DisputeView memory view_ = jury.disputeView(disputeId);
        assertEq(view_.validRevealCount, 3);
        assertEq(view_.provisionalResult, uint8(LibEveMarket.MarketOutcome.No));
        assertTrue(view_.hasProvisional);
    }

    function testFuzz_PermissionlessTransitionsPayConfiguredCallerIncentive(
        uint128 randomnessInput,
        uint128 selectInput,
        uint128 closeCommitInput,
        uint128 closeRevealInput,
        uint128 appealInput,
        uint128 finalizeInput
    ) public {
        uint128 randomnessIncentive = uint128(bound(randomnessInput, 1, 1e18));
        uint128 selectIncentive = uint128(bound(selectInput, 1, 1e18));
        uint128 closeCommitIncentive = uint128(bound(closeCommitInput, 1, 1e18));
        uint128 closeRevealIncentive = uint128(bound(closeRevealInput, 1, 1e18));
        uint128 appealIncentive = uint128(bound(appealInput, 1, 1e18));
        uint128 finalizeIncentive = uint128(bound(finalizeInput, 1, 1e18));

        jury.configureIncentives(
            address(bondToken),
            randomnessIncentive,
            selectIncentive,
            closeCommitIncentive,
            closeRevealIncentive,
            appealIncentive,
            finalizeIncentive
        );

        address caller = makeAddr("permissionless-caller");
        uint128 requiredAppealBond = 1 ether;
        uint256 expectedCallerBalance;
        uint256 totalIncentiveFunding = uint256(randomnessIncentive) * 3 + selectIncentive + closeCommitIncentive
            + closeRevealIncentive + appealIncentive + finalizeIncentive;
        totalIncentiveFunding += uint256(selectIncentive) + closeCommitIncentive + closeRevealIncentive;
        bondToken.mint(address(jury), totalIncentiveFunding);
        bondToken.mint(caller, requiredAppealBond);

        uint256 aliceId = _activateResolver(alice);
        uint256 bobId = _activateResolver(bob);
        uint256 carolId = _activateResolver(carol);

        bytes32 disputeId = jury.seedDisputedMarket(keccak256("caller-incentive-market"));

        // Feature: resolver-identity-jury, Property 21: Permissionless transitions pay the configured caller incentive
        vm.prank(caller);
        jury.openRandomnessCommit(disputeId);
        expectedCallerBalance += randomnessIncentive;
        assertEq(bondToken.balanceOf(caller), expectedCallerBalance + requiredAppealBond);

        vm.warp(vm.getBlockTimestamp() + 1 hours);
        vm.prank(caller);
        jury.closeRandomnessCommit(disputeId);
        expectedCallerBalance += randomnessIncentive;
        assertEq(bondToken.balanceOf(caller), expectedCallerBalance + requiredAppealBond);

        vm.warp(vm.getBlockTimestamp() + 1 hours);
        vm.prank(caller);
        jury.applyRandomnessFallback(disputeId);
        expectedCallerBalance += randomnessIncentive;
        assertEq(bondToken.balanceOf(caller), expectedCallerBalance + requiredAppealBond);

        vm.prank(caller);
        jury.selectCommittee(disputeId);
        expectedCallerBalance += selectIncentive;
        assertEq(bondToken.balanceOf(caller), expectedCallerBalance + requiredAppealBond);

        vm.expectRevert(abi.encodeWithSelector(Errors.CommitPhaseClosed.selector, disputeId));
        vm.prank(caller);
        jury.closeCommit(disputeId);
        assertEq(bondToken.balanceOf(caller), expectedCallerBalance + requiredAppealBond);

        _commitVote(disputeId, alice, aliceId, uint8(LibEveMarket.MarketOutcome.Yes), keccak256("alice-incentive"));
        _commitVote(disputeId, bob, bobId, uint8(LibEveMarket.MarketOutcome.Yes), keccak256("bob-incentive"));
        _commitVote(disputeId, carol, carolId, uint8(LibEveMarket.MarketOutcome.No), keccak256("carol-incentive"));
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        vm.prank(caller);
        jury.closeCommit(disputeId);
        expectedCallerBalance += closeCommitIncentive;
        assertEq(bondToken.balanceOf(caller), expectedCallerBalance + requiredAppealBond);

        _revealVote(disputeId, alice, uint8(LibEveMarket.MarketOutcome.Yes), keccak256("alice-incentive"));
        _revealVote(disputeId, bob, uint8(LibEveMarket.MarketOutcome.Yes), keccak256("bob-incentive"));
        _revealVote(disputeId, carol, uint8(LibEveMarket.MarketOutcome.No), keccak256("carol-incentive"));
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        vm.prank(caller);
        jury.closeRevealAndTally(disputeId);
        expectedCallerBalance += closeRevealIncentive;
        assertEq(bondToken.balanceOf(caller), expectedCallerBalance + requiredAppealBond);

        vm.prank(caller);
        bondToken.approve(address(jury), requiredAppealBond);
        vm.prank(caller);
        jury.openAppeal(disputeId);
        expectedCallerBalance = expectedCallerBalance + appealIncentive;
        assertEq(bondToken.balanceOf(caller), expectedCallerBalance);

        bytes32 finalizableDisputeId = _openFinalizableDispute(keccak256("caller-incentive-finality-market"));
        vm.warp(jury.disputeView(finalizableDisputeId).appealDeadline);
        vm.prank(caller);
        jury.finalizeDispute(finalizableDisputeId);
        expectedCallerBalance += finalizeIncentive;
        assertEq(bondToken.balanceOf(caller), expectedCallerBalance);
    }

    function testFuzz_BoundedFinalityWithMonotonicCommitteesAndAppealBonds(bytes32 seed, bytes32 salt) public {
        jury.configureAppealRouting(
            address(bondToken),
            [uint16(7_000), uint16(1_000), uint16(1_000), uint16(1_000)],
            [uint16(4_000), uint16(3_000), uint16(3_000)]
        );
        _activateFiveResolvers();
        bytes32 disputeId = _selectCommittee(seed, keccak256("bounded-finality-market"));
        _resolveCurrentRound(disputeId, uint8(LibEveMarket.MarketOutcome.Yes), keccak256(abi.encode(salt, "round0")));

        IResolverJuryFacet.DisputeView memory round0 = jury.disputeView(disputeId);
        uint128 requiredBond = jury.requiredAppealBondForRound(disputeId, 1);
        assertEq(round0.currentRound, 0);
        assertEq(round0.committeeSize, 3);
        assertEq(round0.provisionalResult, uint8(LibEveMarket.MarketOutcome.Yes));
        assertEq(requiredBond, 1 ether);
        assertGt(requiredBond, round0.disputeBondBase);

        // Feature: resolver-identity-jury, Property 17: Bounded finality with monotonic committees and appeal bonds
        bondToken.mint(alice, requiredBond - 1);
        vm.prank(alice);
        bondToken.approve(address(jury), requiredBond - 1);
        vm.expectRevert(abi.encodeWithSelector(Errors.AppealBondTooLow.selector, requiredBond, requiredBond - 1));
        vm.prank(alice);
        jury.openAppeal(disputeId);
        assertEq(jury.disputeView(disputeId).currentRound, 0);
        assertEq(jury.disputeView(disputeId).provisionalResult, uint8(LibEveMarket.MarketOutcome.Yes));

        bondToken.mint(alice, requiredBond);
        vm.prank(alice);
        bondToken.approve(address(jury), requiredBond);
        vm.prank(alice);
        jury.openAppeal(disputeId);

        (uint128 storedBond, address appellant) = jury.storedAppealBondForRound(disputeId, 1);
        IResolverJuryFacet.DisputeView memory appealView = jury.disputeView(disputeId);
        assertEq(storedBond, requiredBond);
        assertEq(appellant, alice);
        assertEq(appealView.currentRound, 1);
        assertEq(appealView.state, uint8(LibResolverJury.DisputeState.CommitteeSelectionPending));

        jury.seedSelectionReady(disputeId, keccak256(abi.encode(seed, "round1")));
        jury.selectCommittee(disputeId);
        IResolverJuryFacet.DisputeView memory round1Selected = jury.disputeView(disputeId);
        assertEq(round1Selected.committeeSize, 5);
        assertGt(round1Selected.committeeSize, round0.committeeSize);

        _resolveCurrentRound(disputeId, uint8(LibEveMarket.MarketOutcome.No), keccak256(abi.encode(salt, "round1")));
        IResolverJuryFacet.DisputeView memory round1 = jury.disputeView(disputeId);
        assertEq(round1.currentRound, 1);
        assertEq(round1.provisionalResult, uint8(LibEveMarket.MarketOutcome.No));

        vm.expectRevert(abi.encodeWithSelector(Errors.MaxAppealRoundsReached.selector, uint8(1)));
        jury.openAppeal(disputeId);
        assertEq(jury.disputeView(disputeId).provisionalResult, uint8(LibEveMarket.MarketOutcome.No));

        vm.expectRevert(abi.encodeWithSelector(Errors.AppealWindowClosed.selector, disputeId));
        jury.finalizeDispute(disputeId);
        vm.warp(round1.appealDeadline);
        jury.finalizeDispute(disputeId);

        IResolverJuryFacet.DisputeView memory finalView = jury.disputeView(disputeId);
        assertTrue(finalView.finalized);
        assertEq(finalView.finalResult, uint8(LibEveMarket.MarketOutcome.No));
        assertEq(finalView.state, uint8(LibResolverJury.DisputeState.Finalized));
    }

    function testFuzz_ReputationUpdatesOnlyAtFinalityAndNeverPunishHonestMinorities(bytes32 seed, bytes32 salt) public {
        uint256 aliceId = _activateResolver(alice);
        uint256 bobId = _activateResolver(bob);
        uint256 carolId = _activateResolver(carol);
        bytes32 disputeId = _selectCommittee(seed, keccak256("economics-reputation-market"));

        // Feature: resolver-identity-jury, Property 18: Reputation updates only at finality and never punish honest minorities
        _commitVote(
            disputeId, alice, aliceId, uint8(LibEveMarket.MarketOutcome.Yes), keccak256(abi.encode(salt, alice))
        );
        _commitVote(disputeId, bob, bobId, uint8(LibEveMarket.MarketOutcome.No), keccak256(abi.encode(salt, bob)));
        _commitVote(disputeId, carol, carolId, uint8(LibEveMarket.MarketOutcome.No), keccak256(abi.encode(salt, carol)));
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        jury.closeCommit(disputeId);
        _revealVote(disputeId, alice, uint8(LibEveMarket.MarketOutcome.Yes), keccak256(abi.encode(salt, alice)));
        _revealVote(disputeId, bob, uint8(LibEveMarket.MarketOutcome.No), keccak256(abi.encode(salt, bob)));
        _revealVote(disputeId, carol, uint8(LibEveMarket.MarketOutcome.No), keccak256(abi.encode(salt, carol)));
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        jury.closeRevealAndTally(disputeId);

        assertEq(jury.resolverReputation(aliceId).finalAgreementCount, 0);
        assertEq(jury.resolverReputation(bobId).finalAgreementCount, 0);
        assertEq(jury.resolverReputation(carolId).finalAgreementCount, 0);

        vm.warp(jury.disputeView(disputeId).appealDeadline);
        jury.finalizeDispute(disputeId);

        assertEq(jury.resolverReputation(aliceId).finalAgreementCount, 0);
        assertEq(jury.resolverReputation(aliceId).slashCount, 0);
        assertEq(jury.resolverReputation(aliceId).missedCommitCount, 0);
        assertEq(jury.resolverReputation(aliceId).missedRevealCount, 0);
        assertEq(jury.resolverReputation(aliceId).invalidRevealCount, 0);
        assertEq(jury.resolverReputation(bobId).finalAgreementCount, 1);
        assertEq(jury.resolverReputation(carolId).finalAgreementCount, 1);

        vm.expectRevert(abi.encodeWithSelector(Errors.DisputeAlreadyFinalized.selector, disputeId));
        jury.finalizeDispute(disputeId);
        assertEq(jury.resolverReputation(bobId).finalAgreementCount, 1);
        assertEq(jury.resolverReputation(carolId).finalAgreementCount, 1);
    }

    function testFuzz_SlashingCorrectBoundedLimitedToNonParticipationOrInvalid(
        uint16 missedCommitInput,
        uint16 missedRevealInput,
        uint16 invalidRevealInput,
        bytes32 seed,
        bytes32 salt
    ) public {
        uint16 missedCommitSlashBps = uint16(bound(missedCommitInput, 1, 10_000));
        uint16 missedRevealSlashBps = uint16(bound(missedRevealInput, 1, 10_000));
        uint16 invalidRevealSlashBps = uint16(bound(invalidRevealInput, 1, 10_000));
        jury.configureSlashBps(missedCommitSlashBps, missedRevealSlashBps, invalidRevealSlashBps);

        // Feature: resolver-identity-jury, Property 19: Slashing is correct, bounded, and limited to non-participation/invalid
        _activateResolver(alice);
        _activateResolver(bob);
        _activateResolver(carol);
        _assertMissedCommitSlash(seed, missedCommitSlashBps);

        _activateResolver(dave);
        _activateResolver(erin);
        _assertMissedRevealSlash(keccak256(abi.encode(seed, "missed-reveal")), missedRevealSlashBps, salt);

        _assertInvalidRevealSlash(keccak256(abi.encode(seed, "invalid-reveal")), invalidRevealSlashBps, salt);
    }

    function _selectCommittee(bytes32 seed, bytes32 marketId) internal returns (bytes32 disputeId) {
        disputeId = jury.seedDisputedMarket(marketId);
        jury.seedSelectionReady(disputeId, seed);
        jury.selectCommittee(disputeId);
    }

    function _configDrivenInputs(
        bool useFiveMemberCommittee,
        uint64 commitDurationInput,
        uint64 revealDurationInput,
        uint16 slashInput,
        uint16 appealMultiplierInput,
        uint128 incentiveInput
    ) internal pure returns (ConfigDrivenInputs memory config) {
        config.committeeSize = useFiveMemberCommittee ? 5 : 3;
        config.nextCommitteeSize = config.committeeSize + 2;
        config.commitDuration = uint64(bound(commitDurationInput, 1 hours, 7 days));
        config.revealDuration = uint64(bound(revealDurationInput, 1 hours, 7 days));
        config.quorum = uint32(config.committeeSize - 1);
        config.missedRevealSlashBps = uint16(bound(slashInput, 1, 10_000));
        config.appealBondMultiplierBps = uint16(bound(appealMultiplierInput, 10_001, 50_000));
        config.closeCommitIncentive = uint128(bound(incentiveInput, 1, 1e18));
    }

    function _activateFiveResolvers() internal returns (uint256 aliceId) {
        aliceId = _activateResolver(alice);
        _activateResolver(bob);
        _activateResolver(carol);
        _activateResolver(dave);
        _activateResolver(erin);
    }

    function _applyConfigDrivenBehavior(uint128 stakeRequirement, ConfigDrivenInputs memory config) internal {
        jury.configureConfigDrivenBehavior(
            address(bondToken),
            stakeRequirement,
            config.committeeSize,
            config.nextCommitteeSize,
            config.commitDuration,
            config.revealDuration,
            config.quorum,
            config.missedRevealSlashBps,
            config.appealBondMultiplierBps,
            config.closeCommitIncentive
        );
    }

    function _assertStakeRequirementConfig(uint256 aliceId, ConfigDrivenInputs memory config) internal {
        bytes32 disputeId = jury.seedDisputedMarket(keccak256("config-driven-stake-market"));
        _applyConfigDrivenBehavior(101e18, config);
        assertFalse(jury.isEligibleResolver(aliceId, disputeId));

        _applyConfigDrivenBehavior(100e18, config);
        assertTrue(jury.isEligibleResolver(aliceId, disputeId));
    }

    function _selectConfigDrivenCommittee(ConfigDrivenInputs memory config, bytes32 seed)
        internal
        returns (bytes32 disputeId)
    {
        disputeId = jury.seedDisputedMarket(keccak256("config-driven-behavior-market"));
        jury.seedSelectionReady(disputeId, seed);
        uint256 selectionTimestamp = block.timestamp;
        jury.selectCommittee(disputeId);

        IResolverJuryFacet.DisputeView memory view_ = jury.disputeView(disputeId);
        assertEq(view_.committeeSize, config.committeeSize);
        assertEq(view_.commitDeadline, selectionTimestamp + config.commitDuration);
    }

    function _commitAllSelected(bytes32 disputeId, uint256[] memory members) internal {
        for (uint256 index; index < members.length; ++index) {
            _commitVoteByIdentity(disputeId, members[index], uint8(LibEveMarket.MarketOutcome.Yes), "config-driven");
        }
    }

    function _closeCommitAndAssertConfig(bytes32 disputeId, ConfigDrivenInputs memory config)
        internal
        returns (address caller)
    {
        caller = makeAddr("config-driven-caller");
        bondToken.mint(address(jury), config.closeCommitIncentive);
        vm.warp(jury.disputeView(disputeId).commitDeadline);
        uint256 revealOpenTimestamp = block.timestamp;
        vm.prank(caller);
        jury.closeCommit(disputeId);

        assertEq(bondToken.balanceOf(caller), config.closeCommitIncentive);
        assertEq(jury.disputeView(disputeId).revealDeadline, revealOpenTimestamp + config.revealDuration);
    }

    function _closeRevealAndAssertConfig(bytes32 disputeId, uint256[] memory members, ConfigDrivenInputs memory config)
        internal
    {
        uint256 missedIdentityId = members[members.length - 1];
        uint128 stakeBeforeSlash = jury.resolverStakeOf(missedIdentityId);
        for (uint256 index; index < members.length - 1; ++index) {
            _revealVoteByIdentity(disputeId, members[index], uint8(LibEveMarket.MarketOutcome.Yes), "config-driven");
        }

        vm.warp(jury.disputeView(disputeId).revealDeadline);
        jury.closeRevealAndTally(disputeId);

        uint128 expectedSlash = uint128((uint256(stakeBeforeSlash) * config.missedRevealSlashBps) / 10_000);
        assertEq(jury.resolverStakeOf(missedIdentityId), stakeBeforeSlash - expectedSlash);

        IResolverJuryFacet.DisputeView memory view_ = jury.disputeView(disputeId);
        assertEq(view_.validRevealCount, config.quorum);
        assertEq(view_.provisionalResult, uint8(LibEveMarket.MarketOutcome.Yes));
    }

    function _openAppealAndAssertConfig(bytes32 disputeId, address caller, ConfigDrivenInputs memory config) internal {
        IResolverJuryFacet.DisputeView memory view_ = jury.disputeView(disputeId);
        uint128 expectedAppealBond =
            uint128((uint256(view_.disputeBondBase) * config.appealBondMultiplierBps + 9_999) / 10_000);
        assertEq(jury.requiredAppealBondForRound(disputeId, 1), expectedAppealBond);

        bondToken.mint(caller, expectedAppealBond);
        vm.startPrank(caller);
        bondToken.approve(address(jury), expectedAppealBond);
        jury.openAppeal(disputeId);
        vm.stopPrank();

        (uint128 storedAppealBond, address appellant) = jury.storedAppealBondForRound(disputeId, 1);
        assertEq(storedAppealBond, expectedAppealBond);
        assertEq(appellant, caller);
    }

    function _openFinalizableDispute(bytes32 marketId) internal returns (bytes32 disputeId) {
        uint256 aliceId = identity.identityOf(alice);
        uint256 bobId = identity.identityOf(bob);
        uint256 carolId = identity.identityOf(carol);
        disputeId = _selectCommittee(keccak256(abi.encode(marketId, "finality-seed")), marketId);
        _commitVote(disputeId, alice, aliceId, uint8(LibEveMarket.MarketOutcome.Yes), keccak256("alice-finality"));
        _commitVote(disputeId, bob, bobId, uint8(LibEveMarket.MarketOutcome.Yes), keccak256("bob-finality"));
        _commitVote(disputeId, carol, carolId, uint8(LibEveMarket.MarketOutcome.No), keccak256("carol-finality"));
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        jury.closeCommit(disputeId);
        _revealVote(disputeId, alice, uint8(LibEveMarket.MarketOutcome.Yes), keccak256("alice-finality"));
        _revealVote(disputeId, bob, uint8(LibEveMarket.MarketOutcome.Yes), keccak256("bob-finality"));
        _revealVote(disputeId, carol, uint8(LibEveMarket.MarketOutcome.No), keccak256("carol-finality"));
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        jury.closeRevealAndTally(disputeId);
    }

    function _resolveCurrentRound(bytes32 disputeId, uint8 outcome, bytes32 salt) internal {
        uint8 round = jury.disputeView(disputeId).currentRound;
        uint256[] memory members = jury.committeeMembers(disputeId, round);
        for (uint256 index; index < members.length; ++index) {
            _commitVoteByIdentity(disputeId, members[index], outcome, salt);
        }

        vm.warp(vm.getBlockTimestamp() + 1 hours);
        jury.closeCommit(disputeId);
        for (uint256 index; index < members.length; ++index) {
            _revealVoteByIdentity(disputeId, members[index], outcome, salt);
        }

        vm.warp(vm.getBlockTimestamp() + 1 hours);
        jury.closeRevealAndTally(disputeId);
    }

    function _assertMissedCommitSlash(bytes32 seed, uint16 slashBps) internal {
        bytes32 disputeId = _selectCommittee(seed, keccak256("slash-missed-commit-market"));
        uint256[] memory members = jury.committeeMembers(disputeId, 0);
        _commitVoteByIdentity(disputeId, members[0], uint8(LibEveMarket.MarketOutcome.Yes), "missed-commit");
        _commitVoteByIdentity(disputeId, members[1], uint8(LibEveMarket.MarketOutcome.No), "missed-commit");

        uint128 stakeBefore = jury.resolverStakeOf(members[2]);
        (uint256[] memory activeIds, uint128[] memory rewardsBefore, uint256 treasuryBefore) = _rewardSnapshot();
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        jury.closeCommit(disputeId);

        _assertSlashedOnce(disputeId, members[2], stakeBefore, slashBps, activeIds, rewardsBefore, treasuryBefore);
        assertEq(jury.resolverReputation(members[2]).missedCommitCount, 1);
        assertEq(jury.resolverReputation(members[0]).slashCount, 0);
        assertEq(jury.resolverReputation(members[1]).slashCount, 0);
    }

    function _assertMissedRevealSlash(bytes32 seed, uint16 slashBps, bytes32 salt) internal {
        bytes32 disputeId = _selectCommittee(seed, keccak256("slash-missed-reveal-market"));
        uint256[] memory members = jury.committeeMembers(disputeId, 0);
        _commitVoteByIdentity(disputeId, members[0], uint8(LibEveMarket.MarketOutcome.Yes), salt);
        _commitVoteByIdentity(disputeId, members[1], uint8(LibEveMarket.MarketOutcome.No), salt);
        _commitVoteByIdentity(disputeId, members[2], uint8(LibEveMarket.MarketOutcome.Yes), salt);

        vm.warp(vm.getBlockTimestamp() + 1 hours);
        jury.closeCommit(disputeId);
        _revealVoteByIdentity(disputeId, members[0], uint8(LibEveMarket.MarketOutcome.Yes), salt);
        _revealVoteByIdentity(disputeId, members[1], uint8(LibEveMarket.MarketOutcome.No), salt);

        uint128 stakeBefore = jury.resolverStakeOf(members[2]);
        (uint256[] memory activeIds, uint128[] memory rewardsBefore, uint256 treasuryBefore) = _rewardSnapshot();
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        jury.closeRevealAndTally(disputeId);

        _assertSlashedOnce(disputeId, members[2], stakeBefore, slashBps, activeIds, rewardsBefore, treasuryBefore);
        assertEq(jury.resolverReputation(members[2]).missedRevealCount, 1);
        assertEq(jury.resolverReputation(members[0]).slashCount, 0);
        assertEq(jury.resolverReputation(members[1]).slashCount, 0);
    }

    function _assertInvalidRevealSlash(bytes32 seed, uint16 slashBps, bytes32 salt) internal {
        bytes32 disputeId = _selectCommittee(seed, keccak256("slash-invalid-reveal-market"));
        uint256[] memory members = jury.committeeMembers(disputeId, 0);
        bytes32 invalidSalt = keccak256(abi.encode(salt, "invalid"));
        _commitVoteByIdentity(disputeId, members[0], uint8(LibEveMarket.MarketOutcome.Unresolved), invalidSalt);
        _commitVoteByIdentity(disputeId, members[1], uint8(LibEveMarket.MarketOutcome.Yes), salt);
        _commitVoteByIdentity(disputeId, members[2], uint8(LibEveMarket.MarketOutcome.No), salt);

        vm.warp(vm.getBlockTimestamp() + 1 hours);
        jury.closeCommit(disputeId);

        uint128 stakeBefore = jury.resolverStakeOf(members[0]);
        (uint256[] memory activeIds, uint128[] memory rewardsBefore, uint256 treasuryBefore) = _rewardSnapshot();
        _revealVoteByIdentity(disputeId, members[0], uint8(LibEveMarket.MarketOutcome.Unresolved), invalidSalt);
        address invalidResolver = identity.ownerOf(members[0]);
        vm.expectRevert(abi.encodeWithSelector(Errors.AlreadyRevealed.selector, members[0]));
        vm.prank(invalidResolver);
        jury.revealVote(
            disputeId, uint8(LibEveMarket.MarketOutcome.Yes), keccak256(abi.encode(invalidSalt, members[0]))
        );
        _revealVoteByIdentity(disputeId, members[1], uint8(LibEveMarket.MarketOutcome.Yes), salt);
        _revealVoteByIdentity(disputeId, members[2], uint8(LibEveMarket.MarketOutcome.No), salt);

        vm.warp(vm.getBlockTimestamp() + 1 hours);
        jury.closeRevealAndTally(disputeId);

        _assertSlashedOnce(disputeId, members[0], stakeBefore, slashBps, activeIds, rewardsBefore, treasuryBefore);
        assertEq(jury.resolverReputation(members[0]).invalidRevealCount, 1);
        assertEq(jury.resolverReputation(members[0]).missedRevealCount, 0);
        assertEq(jury.resolverReputation(members[1]).slashCount, 0);
        assertEq(jury.resolverReputation(members[2]).slashCount, 0);
    }

    function _assertSlashedOnce(
        bytes32 disputeId,
        uint256 identityId,
        uint128 stakeBefore,
        uint16 slashBps,
        uint256[] memory activeIds,
        uint128[] memory rewardsBefore,
        uint256 treasuryBefore
    ) internal view {
        uint128 expectedSlash = uint128((uint256(stakeBefore) * slashBps) / 10_000);
        (uint128 stakeAfter, bool slashLockActive, uint64 slashLockUntil) = jury.resolverSlashState(identityId);
        assertEq(stakeAfter, stakeBefore - expectedSlash);
        assertTrue(slashLockActive);
        assertGt(slashLockUntil, block.timestamp);
        assertEq(jury.disputeView(disputeId).rewardPoolBond, 0);
        _assertSlashRewards(identityId, expectedSlash, activeIds, rewardsBefore, treasuryBefore);
        assertEq(jury.resolverReputation(identityId).slashCount, 1);
    }

    function _assertSlashRewards(
        uint256 slashedIdentityId,
        uint128 expectedSlash,
        uint256[] memory activeIds,
        uint128[] memory rewardsBefore,
        uint256 treasuryBefore
    ) internal view {
        uint256 totalRewardDelta;
        uint128 equalRewardDelta;
        uint256 recipientCount;
        for (uint256 index; index < activeIds.length; ++index) {
            (,, uint128 rewardsAfter) = jury.previewResolverRewards(activeIds[index], address(bondToken));
            uint128 delta = rewardsAfter - rewardsBefore[index];
            if (activeIds[index] == slashedIdentityId) {
                assertEq(delta, 0);
                continue;
            }
            if (delta == 0) {
                continue;
            }
            if (equalRewardDelta == 0) {
                equalRewardDelta = delta;
            } else {
                assertEq(delta, equalRewardDelta);
            }
            totalRewardDelta += delta;
            recipientCount += 1;
        }

        uint256 treasuryDelta = bondToken.balanceOf(_resolverTreasury()) - treasuryBefore;
        assertEq(totalRewardDelta + treasuryDelta, expectedSlash);
        if (expectedSlash != 0) {
            assertGt(recipientCount, 0);
            assertGt(equalRewardDelta, 0);
        }
    }

    function _rewardSnapshot()
        internal
        view
        returns (uint256[] memory activeIds, uint128[] memory rewardsBefore, uint256 treasuryBefore)
    {
        uint256 activeCount = jury.activeResolverCount();
        activeIds = new uint256[](activeCount);
        rewardsBefore = new uint128[](activeCount);
        for (uint256 index; index < activeCount; ++index) {
            activeIds[index] = jury.activeResolverAt(index);
            (,, rewardsBefore[index]) = jury.previewResolverRewards(activeIds[index], address(bondToken));
        }
        treasuryBefore = bondToken.balanceOf(_resolverTreasury());
    }

    function _resolverTreasury() internal pure returns (address) {
        return address(uint160(uint256(keccak256("resolver-economics-treasury"))));
    }

    function _commitVote(bytes32 disputeId, address owner, uint256 identityId, uint8 outcome, bytes32 salt) internal {
        vm.prank(owner);
        jury.commitVote(disputeId, keccak256(abi.encode(disputeId, identityId, outcome, salt)));
    }

    function _commitVoteByIdentity(bytes32 disputeId, uint256 identityId, uint8 outcome, bytes32 salt) internal {
        address owner = identity.ownerOf(identityId);
        _commitVote(disputeId, owner, identityId, outcome, keccak256(abi.encode(salt, identityId)));
    }

    function _revealVote(bytes32 disputeId, address owner, uint8 outcome, bytes32 salt) internal {
        vm.prank(owner);
        jury.revealVote(disputeId, outcome, salt);
    }

    function _revealVoteByIdentity(bytes32 disputeId, uint256 identityId, uint8 outcome, bytes32 salt) internal {
        vm.prank(identity.ownerOf(identityId));
        jury.revealVote(disputeId, outcome, keccak256(abi.encode(salt, identityId)));
    }

    function _activateResolver(address owner) internal returns (uint256 identityId) {
        feeToken.mint(owner, 1e6);
        vm.prank(owner);
        feeToken.approve(address(jury), 1e6);
        vm.prank(owner);
        identityId = jury.mintIdentity();

        vm.prank(owner);
        jury.setResolverRole(true);

        bondToken.mint(owner, 100e18);
        vm.prank(owner);
        bondToken.approve(address(jury), 100e18);
        vm.prank(owner);
        jury.depositResolverStake(100e18);

        jury.seedActiveResolverEpochMember(identityId);
    }

    function _expectStakeTopUpRejected(address owner, uint256 amount) internal {
        bondToken.mint(owner, amount);
        vm.prank(owner);
        bondToken.approve(address(jury), amount);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidAmount.selector, 100e18 + amount));
        jury.depositResolverStake(amount);
    }
}
