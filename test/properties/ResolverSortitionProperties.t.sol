// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "../../lib/forge-std/src/Test.sol";

import {Errors} from "src/libraries/Errors.sol";
import {IOBRResolutionFacet} from "src/interfaces/IOBRResolutionFacet.sol";
import {LibEveMarket} from "src/libraries/LibEveMarket.sol";
import {LibMarketCreation} from "src/libraries/LibMarketCreation.sol";
import {LibResolverJury} from "src/libraries/LibResolverJury.sol";
import {ResolverJuryFacet} from "src/facets/ResolverJuryFacet.sol";
import {ResolverRegistryFacet} from "src/facets/ResolverRegistryFacet.sol";
import {IEvesPositionManager} from "src/interfaces/IEvesPositionManager.sol";
import {IResolverJuryFacet} from "src/interfaces/IResolverJuryFacet.sol";
import {EveIdentity} from "src/tokens/EveIdentity.sol";
import {EvesPositionManager} from "src/tokens/EvesPositionManager.sol";
import {MockEveToken} from "test/helpers/MockEveToken.sol";
import {MockUSDC} from "test/helpers/MockUSDC.sol";
import {ResolutionFixture, StateProbeFacet} from "test/helpers/DiamondFixtures.sol";

contract ResolverSortitionPropertyHarness is ResolverJuryFacet, ResolverRegistryFacet {
    function configure(address eveIdentity, address mintFeeToken, address eveToken, uint256 threshold) external {
        LibResolverJury.store().eveIdentity = eveIdentity;
        LibEveMarket.MarketConfig storage config = LibEveMarket.store().config;
        config.eveToken = eveToken;
        config.bondToken = eveToken;
        config.resolverJuryConfig.identityMintFeeToken = mintFeeToken;
        config.resolverJuryConfig.identityMintFee = 1e6;
        config.resolverJuryConfig.resolverSeatStake = 100e18;
        config.resolverJuryConfig.activeEpochSize = 16;
        config.resolverJuryConfig.concurrencyLimit = 2;
        config.resolverJuryConfig.participationGraceCount = 5;
        config.resolverJuryConfig.conflictPositionThreshold = threshold;
        config.resolverJuryConfig.commitDuration = 1 hours;
        delete config.resolverJuryConfig.committeeSizesByRound;
        config.resolverJuryConfig.committeeSizesByRound.push(3);
    }

    function setBinaryMarket(
        bytes32 marketId,
        address creator,
        address positionToken,
        uint256 yesPositionId,
        uint256 noPositionId
    ) external {
        LibEveMarket.Market storage market = LibEveMarket.store().markets[marketId];
        market.marketId = marketId;
        market.creator = creator;
        market.marketType = LibEveMarket.MarketType.CLOB;
        market.positionToken = positionToken;
        market.yesPositionId = yesPositionId;
        market.noPositionId = noPositionId;
    }

    function setDisputeMarket(bytes32 disputeId, bytes32 marketId) external {
        LibResolverJury.store().disputes[disputeId].marketId = marketId;
    }

    function seedDisputedMarket(bytes32 marketId) external returns (bytes32 disputeId) {
        LibEveMarket.Market storage market = LibEveMarket.store().markets[marketId];
        market.marketId = marketId;
        market.marketType = LibEveMarket.MarketType.CLOB;
        market.state = LibEveMarket.MarketState.Disputed;
        disputeId = this.disputeIdForMarket(marketId);
        IResolverJuryFacet(address(this)).initiateDispute(marketId);
    }

    function setCommitteeSize(uint256 committeeSize) external {
        if (committeeSize > type(uint16).max) {
            revert Errors.InvalidAmount(committeeSize);
        }

        LibEveMarket.ResolverJuryConfig storage config = LibEveMarket.store().config.resolverJuryConfig;
        delete config.committeeSizesByRound;
        config.committeeSizesByRound.push(uint16(committeeSize));
    }

    function setSelectionSeed(bytes32 disputeId, bytes32 seed) external {
        LibResolverJury.Dispute storage dispute = LibResolverJury.store().disputes[disputeId];
        dispute.rounds[dispute.currentRound].seed = seed == bytes32(0) ? keccak256("property-selection-seed") : seed;
    }

    function setResolverRole(uint256 identityId, bool resolverRole) external {
        EveIdentity(LibResolverJury.store().eveIdentity).setRoles(identityId, false, resolverRole);
    }

    function setRecordedStake(uint256 identityId, uint256 stake) external {
        if (stake > type(uint128).max) {
            revert Errors.InvalidAmount(stake);
        }

        LibResolverJury.store().identities[identityId].resolverStake = uint128(stake);
    }

    function setSlashLock(uint256 identityId, uint256 slashLockUntil) external {
        if (slashLockUntil > type(uint64).max) {
            revert Errors.InvalidAmount(slashLockUntil);
        }

        LibResolverJury.ResolverIdentityRecord storage record = LibResolverJury.store().identities[identityId];
        record.slashLockActive = true;
        record.slashLockUntil = uint64(slashLockUntil);
    }

    function setUnresolvedCommittees(uint256 identityId, uint256 unresolvedCommittees) external {
        if (unresolvedCommittees > type(uint16).max) {
            revert Errors.InvalidAmount(unresolvedCommittees);
        }

        LibResolverJury.store().identities[identityId].unresolvedCommittees = uint16(unresolvedCommittees);
    }

    function setParticipation(
        uint256 identityId,
        uint256 totalSelections,
        uint256 revealCount,
        uint256 thresholdBps,
        uint256 graceCount
    ) external {
        if (totalSelections > type(uint64).max || revealCount > type(uint64).max || graceCount > type(uint32).max) {
            revert Errors.InvalidAmount(totalSelections);
        }
        if (thresholdBps > type(uint16).max) {
            revert Errors.InvalidAmount(thresholdBps);
        }

        LibResolverJury.ResolverReputation storage reputation = LibResolverJury.store().resolverRep[identityId];
        reputation.totalSelections = uint64(totalSelections);
        reputation.revealCount = uint64(revealCount);
        LibEveMarket.ResolverJuryConfig storage config = LibEveMarket.store().config.resolverJuryConfig;
        config.participationThresholdBps = uint16(thresholdBps);
        config.participationGraceCount = uint32(graceCount);
    }

    function setActivationDelay(uint256 activationDelay) external {
        if (activationDelay > type(uint64).max) {
            revert Errors.InvalidAmount(activationDelay);
        }

        LibEveMarket.store().config.resolverJuryConfig.activationDelay = uint64(activationDelay);
    }

    function mintPosition(address positionToken, address to, uint256 positionId, uint256 amount) external {
        IEvesPositionManager(positionToken).mint(to, positionId, amount);
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

    function clearActiveResolverEpochMember(uint256 identityId) external {
        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        LibResolverJury.ResolverEpoch storage epoch = jury.resolverEpochs[jury.currentResolverEpoch];
        epoch.activeIndex[identityId] = 0;
        jury.identities[identityId].lifecycle = LibResolverJury.ResolverLifecycle.ResolverCandidate;
    }
}

contract ResolverRandomnessSeedHarness is ResolverJuryFacet {
    function deriveSeed(bytes32 disputeId, bytes32 accumulator, bytes32 delayedBlockEntropy)
        external
        pure
        returns (bytes32)
    {
        return _deriveRandomnessSeed(disputeId, accumulator, delayedBlockEntropy);
    }
}

contract ResolverSortitionPropertiesTest is Test {
    address internal owner = makeAddr("resolver-owner");
    address internal other = makeAddr("other-creator");

    ResolverSortitionPropertyHarness internal registry;
    ResolverRandomnessSeedHarness internal seedHarness;
    EveIdentity internal identity;
    MockUSDC internal feeToken;
    MockEveToken internal eveToken;
    EvesPositionManager internal positions;

    function setUp() public {
        registry = new ResolverSortitionPropertyHarness();
        seedHarness = new ResolverRandomnessSeedHarness();
        identity = new EveIdentity(address(registry), "Eve Identity", "EVE-ID");
        feeToken = new MockUSDC();
        eveToken = new MockEveToken();
        positions = new EvesPositionManager(address(registry), "");
    }

    function testFuzz_ConflictOfInterestExclusionAtSelection(uint256 threshold, uint256 excess, bool creatorConflict)
        public
    {
        threshold = bound(threshold, 1, 1e24);
        excess = bound(excess, 1, 1e24);
        registry.configure(address(identity), address(feeToken), address(eveToken), threshold);
        uint256 identityId = _activateResolver(owner);

        bytes32 conflictedMarketId = keccak256("conflicted-market");
        bytes32 conflictedDisputeId = keccak256("conflicted-dispute");
        address creator = creatorConflict ? owner : other;
        registry.setBinaryMarket(conflictedMarketId, creator, address(positions), 111, 222);
        registry.setDisputeMarket(conflictedDisputeId, conflictedMarketId);
        if (!creatorConflict) {
            registry.mintPosition(address(positions), owner, 111, threshold + excess);
        }

        // Feature: resolver-identity-jury, Property 8: Conflict-of-interest exclusion at selection
        assertTrue(registry.hasConflict(identityId, conflictedMarketId));
        assertFalse(registry.isEligibleResolver(identityId, conflictedDisputeId));

        bytes32 cleanMarketId = keccak256("clean-market");
        bytes32 cleanDisputeId = keccak256("clean-dispute");
        registry.setBinaryMarket(cleanMarketId, other, address(positions), 333, 444);
        registry.setDisputeMarket(cleanDisputeId, cleanMarketId);
        registry.mintPosition(address(positions), owner, 333, threshold);

        assertFalse(registry.hasConflict(identityId, cleanMarketId));
        assertTrue(registry.isEligibleResolver(identityId, cleanDisputeId));
    }

    function testFuzz_EligibilityIsConjunctionOfAllGates(uint8 gateMask, uint64 activationDelay, uint256 threshold)
        public
    {
        activationDelay = uint64(bound(activationDelay, 1, 30 days));
        threshold = bound(threshold, 1, 1e24);
        registry.configure(address(identity), address(feeToken), address(eveToken), threshold);
        registry.setActivationDelay(activationDelay);
        uint256 identityId = _activateResolver(owner);

        bytes32 marketId = keccak256("eligibility-market");
        bytes32 disputeId = keccak256("eligibility-dispute");
        registry.setBinaryMarket(marketId, other, address(positions), 555, 666);
        registry.setDisputeMarket(disputeId, marketId);

        bool roleGate = (gateMask & 1) == 0;
        bool stakeGate = (gateMask & 2) == 0;
        bool activeEpochGate = (gateMask & 4) == 0;
        bool slashGate = (gateMask & 8) == 0;
        bool participationGate = (gateMask & 16) == 0;
        bool concurrencyGate = (gateMask & 32) == 0;
        bool conflictGate = (gateMask & 64) == 0;

        if (!roleGate) {
            registry.setResolverRole(identityId, false);
        }
        if (!stakeGate) {
            registry.setRecordedStake(identityId, 99e18);
        }
        if (!activeEpochGate) {
            registry.clearActiveResolverEpochMember(identityId);
        }
        if (!slashGate) {
            registry.setSlashLock(identityId, block.timestamp + 1 days);
        }
        if (!participationGate) {
            registry.setParticipation(identityId, 10, 4, 5_000, 0);
        }
        if (!concurrencyGate) {
            registry.setUnresolvedCommittees(identityId, 2);
        }
        if (!conflictGate) {
            registry.mintPosition(address(positions), owner, 555, threshold + 1);
        }

        bool expected = roleGate && stakeGate && activeEpochGate && slashGate && participationGate && concurrencyGate
            && conflictGate;

        // Feature: resolver-identity-jury, Property 7: Eligibility is the conjunction of all gates
        assertEq(registry.isEligibleResolver(identityId, disputeId), expected);
    }

    function testFuzz_NativeRandomnessSeedIsDeterministicInDeclaredInputsOnly(
        bytes32 disputeId,
        bytes32 accumulator,
        bytes32 delayedBlockEntropy,
        bytes32 alternateEntropy
    ) public view {
        vm.assume(alternateEntropy != delayedBlockEntropy);

        // Feature: resolver-identity-jury, Property 23: Native randomness seed is deterministic in declared inputs only
        bytes32 seed = seedHarness.deriveSeed(disputeId, accumulator, delayedBlockEntropy);
        assertEq(seed, seedHarness.deriveSeed(disputeId, accumulator, delayedBlockEntropy));
        assertEq(seed, keccak256(abi.encode(disputeId, accumulator, delayedBlockEntropy)));
        assertNotEq(seed, seedHarness.deriveSeed(disputeId, accumulator, alternateEntropy));
    }

    function testFuzz_SortitionDrawsExactOddDuplicateFreeEligibleSubset(
        uint8 activeCountInput,
        uint8 committeeSizeInput,
        bytes32 seed
    ) public {
        uint256 activeCount = bound(activeCountInput, 1, 5);
        uint16 committeeSize = uint16(bound(committeeSizeInput, 1, activeCount));
        if (committeeSize % 2 == 0) {
            committeeSize -= 1;
        }
        if (committeeSize == 0) {
            committeeSize = 1;
        }

        registry.configure(address(identity), address(feeToken), address(eveToken), 1e24);
        registry.setCommitteeSize(committeeSize);
        uint256[] memory eligible = new uint256[](activeCount);
        for (uint256 index; index < activeCount; ++index) {
            eligible[index] = _activateResolver(_resolverAccount(index));
        }

        bytes32 disputeId = registry.seedDisputedMarket(keccak256("property-sortition-market"));
        registry.setSelectionSeed(disputeId, seed);

        // Feature: resolver-identity-jury, Property 10: Sortition draws an exact, odd, duplicate-free eligible subset
        registry.selectCommittee(disputeId);

        uint256[] memory members = registry.committeeMembers(disputeId, 0);
        assertEq(members.length, committeeSize);
        assertEq(members.length % 2, 1);
        for (uint256 index; index < members.length; ++index) {
            assertTrue(_contains(eligible, members[index]));
            for (uint256 inner = index + 1; inner < members.length; ++inner) {
                assertNotEq(members[index], members[inner]);
            }
        }
    }

    function _activateResolver(address account) internal returns (uint256 identityId) {
        feeToken.mint(account, 1e6);
        vm.prank(account);
        feeToken.approve(address(registry), 1e6);
        vm.prank(account);
        identityId = registry.mintIdentity();

        vm.prank(account);
        registry.setResolverRole(true);

        eveToken.mint(account, 100e18);
        vm.prank(account);
        eveToken.approve(address(registry), 100e18);
        vm.prank(account);
        registry.depositResolverStake(100e18);

        registry.seedActiveResolverEpochMember(identityId);
    }

    function _resolverAccount(uint256 index) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encode("resolver-sortition-account", index)))));
    }

    function _contains(uint256[] memory values, uint256 target) internal pure returns (bool) {
        for (uint256 index; index < values.length; ++index) {
            if (values[index] == target) {
                return true;
            }
        }
        return false;
    }
}

contract ResolverSortitionObrPropertiesTest is ResolutionFixture {
    function testFuzz_OptimisticFastPathAndJuryRouting(uint8 outcomeSeed) public {
        uint8 fastPathOutcome = uint8(bound(uint256(outcomeSeed), 1, 3));
        (bytes32 fastPathMarketId,) = _createPendingMarket("Property fast path", "sortition", 7 days);
        ExpectedMarketData memory expected = _expectedFromStored(fastPathMarketId);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(fastPathMarketId, fastPathOutcome);

        (,,,,,, uint64 fastPathDeadline,) = StateProbeFacet(address(diamond)).getStoredResolution(fastPathMarketId);
        vm.warp(fastPathDeadline);

        // Feature: resolver-identity-jury, Property 9: Optimistic fast path and jury routing
        IOBRResolutionFacet(address(diamond)).finalizeResolution(fastPathMarketId);
        _assertResolvedStatus(fastPathMarketId, expected.marketId, fastPathOutcome);

        (bytes32 juryMarketId,) = _createPendingMarket("Property jury route", "sortition", 8 days);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(juryMarketId, 1);

        vm.prank(challengerOne);
        IOBRResolutionFacet(address(diamond)).disputeResolution(juryMarketId, 2);

        vm.prank(challengerTwo);
        IOBRResolutionFacet(address(diamond)).disputeResolution(juryMarketId, 3);

        vm.prank(challengerThree);
        IOBRResolutionFacet(address(diamond)).disputeResolution(juryMarketId, 1);

        bytes32 disputeId = keccak256(abi.encode(keccak256("eve.dispute"), juryMarketId));
        IResolverJuryFacet.DisputeView memory dispute = IResolverJuryFacet(address(diamond)).disputeView(disputeId);
        (,,,,,, uint8 state,) = StateProbeFacet(address(diamond)).getStoredMarketStatus(juryMarketId);
        (,,,,,,, uint64 snapshotBlock) = StateProbeFacet(address(diamond)).getStoredResolution(juryMarketId);

        assertEq(dispute.marketId, juryMarketId);
        assertEq(dispute.state, uint8(LibResolverJury.DisputeState.CommitteeSelectionPending));
        assertEq(state, uint8(LibEveMarket.MarketState.Disputed));
        assertEq(snapshotBlock, 0);
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
}
