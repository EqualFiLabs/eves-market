// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "../../lib/forge-std/src/Test.sol";

import {IResolverRegistryFacet} from "src/interfaces/IResolverRegistryFacet.sol";
import {Errors} from "src/libraries/Errors.sol";
import {LibEveMarket} from "src/libraries/LibEveMarket.sol";
import {LibResolverJury} from "src/libraries/LibResolverJury.sol";
import {ResolverRegistryFacet} from "src/facets/ResolverRegistryFacet.sol";
import {EveIdentity} from "src/tokens/EveIdentity.sol";
import {MockEveToken} from "test/helpers/MockEveToken.sol";
import {MockUSDC} from "test/helpers/MockUSDC.sol";

contract ResolverIdentityReputationHarness {
    function creatorCounts(uint256 identityId)
        external
        view
        returns (
            uint64 marketsCreated,
            uint64 marketsResolved,
            uint64 disputesRaised,
            uint64 outcomesUpheld,
            uint64 outcomesOverturned
        )
    {
        LibResolverJury.CreatorReputation storage rep = LibResolverJury.store().creatorRep[identityId];
        return (
            rep.marketsCreated,
            rep.marketsResolved,
            rep.disputesRaised,
            rep.outcomesUpheld,
            rep.outcomesOverturned
        );
    }

    function resolverCounts(uint256 identityId)
        external
        view
        returns (
            uint64 totalSelections,
            uint64 commitCount,
            uint64 revealCount,
            uint64 missedCommitCount,
            uint64 missedRevealCount,
            uint64 invalidRevealCount,
            uint64 finalAgreementCount,
            uint64 slashCount
        )
    {
        LibResolverJury.ResolverReputation storage rep = LibResolverJury.store().resolverRep[identityId];
        return (
            rep.totalSelections,
            rep.commitCount,
            rep.revealCount,
            rep.missedCommitCount,
            rep.missedRevealCount,
            rep.invalidRevealCount,
            rep.finalAgreementCount,
            rep.slashCount
        );
    }
}

contract ResolverRegistryPropertyHarness is ResolverRegistryFacet {
    function configure(address eveIdentity, address mintFeeToken, address eveToken, uint256 activationDelay, uint256 exitCooldown)
        external
    {
        if (activationDelay > type(uint64).max || exitCooldown > type(uint64).max) {
            revert Errors.InvalidConfigValue("resolverPropertyConfig");
        }

        LibResolverJury.store().eveIdentity = eveIdentity;
        LibEveMarket.MarketConfig storage config = LibEveMarket.store().config;
        config.eveToken = eveToken;
        config.bondToken = eveToken;
        config.resolverJuryConfig.identityMintFeeToken = mintFeeToken;
        config.resolverJuryConfig.identityMintFee = 1e6;
        config.resolverJuryConfig.resolverStakeRequirement = 100e18;
        config.resolverJuryConfig.resolverStakeCap = 250e18;
        config.resolverJuryConfig.resolverPoolCap = 50;
        config.resolverJuryConfig.activationDelay = uint64(activationDelay);
        config.resolverJuryConfig.exitCooldown = uint64(exitCooldown);
    }

    function setUnresolvedCommittees(uint256 identityId, uint256 unresolvedCommittees) external {
        if (unresolvedCommittees > type(uint16).max) {
            revert Errors.InvalidAmount(unresolvedCommittees);
        }

        LibResolverJury.store().identities[identityId].unresolvedCommittees = uint16(unresolvedCommittees);
    }

    function setSlashLock(uint256 identityId, uint256 slashLockUntil) external {
        if (slashLockUntil > type(uint64).max) {
            revert Errors.InvalidAmount(slashLockUntil);
        }

        LibResolverJury.ResolverIdentityRecord storage record = LibResolverJury.store().identities[identityId];
        record.slashLockActive = true;
        record.slashLockUntil = uint64(slashLockUntil);
    }

    function clearSlashLock(uint256 identityId) external {
        LibResolverJury.ResolverIdentityRecord storage record = LibResolverJury.store().identities[identityId];
        record.slashLockActive = false;
        record.slashLockUntil = 0;
    }

    function recordedStake(uint256 identityId) external view returns (uint128) {
        return LibResolverJury.store().identities[identityId].resolverStake;
    }

    function seedCreatorFinality(
        bytes32 disputeId,
        bytes32 marketId,
        address creator,
        uint256 proposedOutcome
    ) external {
        if (proposedOutcome > type(uint8).max) {
            revert Errors.InvalidAmount(proposedOutcome);
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        state.markets[marketId].marketId = marketId;
        state.markets[marketId].creator = creator;
        state.resolutions[marketId].marketId = marketId;
        state.resolutions[marketId].proposedOutcome = uint8(proposedOutcome);
        state.resolutions[marketId].proposer = creator;
        LibResolverJury.store().disputes[disputeId].marketId = marketId;
    }

    function applyFinality(bytes32 disputeId, uint256 finalResult) external {
        if (finalResult > type(uint8).max) {
            revert Errors.InvalidAmount(finalResult);
        }

        IResolverRegistryFacet(address(this)).applyFinalityReputation(disputeId, uint8(finalResult));
    }
}

contract ResolverIdentityPropertiesTest is Test {
    address internal diamond = makeAddr("diamond");
    EveIdentity internal identity;
    ResolverIdentityReputationHarness internal reputation;
    ResolverRegistryPropertyHarness internal registry;
    EveIdentity internal registryIdentity;
    MockUSDC internal feeToken;
    MockEveToken internal eveToken;

    function setUp() public {
        identity = new EveIdentity(diamond, "Eve Identity", "EVE-ID");
        reputation = new ResolverIdentityReputationHarness();
        registry = new ResolverRegistryPropertyHarness();
        registryIdentity = new EveIdentity(address(registry), "Eve Identity", "EVE-ID");
        feeToken = new MockUSDC();
        eveToken = new MockEveToken();
        registry.configure(address(registryIdentity), address(feeToken), address(eveToken), 1 days, 7 days);
    }

    function testFuzz_IdentityMintUniquenessAndZeroInitializedReputation(address first, address second, address third)
        public
    {
        vm.assume(first != address(0) && second != address(0) && third != address(0));
        vm.assume(first != second && first != third && second != third);
        vm.assume(first.code.length == 0 && second.code.length == 0 && third.code.length == 0);

        // Feature: resolver-identity-jury, Property 1: Identity mint uniqueness and zero-initialized reputation
        vm.startPrank(diamond);
        uint256 firstId = identity.mint(first);
        uint256 secondId = identity.mint(second);
        uint256 thirdId = identity.mint(third);
        vm.stopPrank();

        assertEq(firstId, 1);
        assertEq(secondId, 2);
        assertEq(thirdId, 3);
        assertEq(identity.identityOf(first), firstId);
        assertEq(identity.identityOf(second), secondId);
        assertEq(identity.identityOf(third), thirdId);
        assertEq(identity.totalMinted(), 3);

        vm.expectRevert(abi.encodeWithSelector(Errors.IdentityAlreadyOwned.selector, first));
        vm.prank(diamond);
        identity.mint(first);

        _assertZeroReputation(firstId);
        _assertZeroReputation(secondId);
        _assertZeroReputation(thirdId);
    }

    function testFuzz_PermanentSoulboundTransferRestriction(
        address owner,
        address receiver,
        address operator,
        uint8 attempt
    ) public {
        vm.assume(owner != address(0) && receiver != address(0) && operator != address(0));
        vm.assume(owner != receiver);
        vm.assume(owner.code.length == 0 && receiver.code.length == 0 && operator.code.length == 0);

        vm.prank(diamond);
        uint256 identityId = identity.mint(owner);

        attempt = uint8(bound(attempt, 0, 4));

        // Feature: resolver-identity-jury, Property 2: Permanent soulbound transfer restriction
        if (attempt == 0) {
            vm.expectRevert(Errors.IdentityTransferDisabled.selector);
            vm.prank(owner);
            identity.transferFrom(owner, receiver, identityId);
        } else if (attempt == 1) {
            vm.expectRevert(Errors.IdentityTransferDisabled.selector);
            vm.prank(owner);
            identity.safeTransferFrom(owner, receiver, identityId);
        } else if (attempt == 2) {
            vm.expectRevert(Errors.IdentityTransferDisabled.selector);
            vm.prank(owner);
            identity.safeTransferFrom(owner, receiver, identityId, "");
        } else if (attempt == 3) {
            vm.expectRevert(Errors.IdentityApprovalDisabled.selector);
            vm.prank(owner);
            identity.approve(operator, identityId);
        } else {
            vm.expectRevert(Errors.IdentityApprovalDisabled.selector);
            vm.prank(owner);
            identity.setApprovalForAll(operator, true);
        }

        assertEq(identity.ownerOf(identityId), owner);
        assertEq(identity.identityOf(owner), identityId);
        assertEq(identity.identityOf(receiver), 0);
        assertEq(identity.getApproved(identityId), address(0));
        assertFalse(identity.isApprovedForAll(owner, operator));
    }

    function testFuzz_CreatorReputationConsistencyAtFinality(address creator, bool upheld) public {
        vm.assume(creator != address(0));
        vm.assume(creator.code.length == 0);
        uint256 identityId = _mintRegistryIdentity(creator);
        bytes32 marketId = keccak256(abi.encode("creator-finality", creator, upheld));
        bytes32 disputeId = keccak256(abi.encode("creator-dispute", creator, upheld));
        uint8 proposedOutcome = uint8(LibEveMarket.MarketOutcome.Yes);
        uint8 finalResult = upheld ? proposedOutcome : uint8(LibEveMarket.MarketOutcome.No);

        registry.seedCreatorFinality(disputeId, marketId, creator, proposedOutcome);

        // Feature: resolver-identity-jury, Property 3: Creator reputation consistency at finality
        registry.applyFinality(disputeId, finalResult);

        IResolverRegistryFacet.CreatorReputationView memory creatorRep = registry.creatorReputation(identityId);
        assertEq(creatorRep.marketsCreated, 0);
        assertEq(creatorRep.marketsResolved, 1);
        assertEq(creatorRep.disputesRaised, 0);
        assertEq(creatorRep.outcomesUpheld, upheld ? 1 : 0);
        assertEq(creatorRep.outcomesOverturned, upheld ? 0 : 1);
        assertLe(creatorRep.outcomesUpheld + creatorRep.outcomesOverturned, creatorRep.marketsResolved);

        creatorRep = registry.creatorReputation(identityId + 1);
        assertEq(creatorRep.marketsCreated, 0);
        assertEq(creatorRep.marketsResolved, 0);
        assertEq(creatorRep.disputesRaised, 0);
        assertEq(creatorRep.outcomesUpheld, 0);
        assertEq(creatorRep.outcomesOverturned, 0);
    }

    function testFuzz_ActivationDelayBoundary(address owner, uint64 activationDelay) public {
        vm.assume(owner != address(0));
        vm.assume(owner.code.length == 0);
        activationDelay = uint64(bound(activationDelay, 1, 30 days));
        registry.configure(address(registryIdentity), address(feeToken), address(eveToken), activationDelay, 7 days);
        uint256 identityId = _fundedResolverIdentity(owner, 100e18);

        vm.prank(owner);
        registry.activateResolver();

        // Feature: resolver-identity-jury, Property 5: Activation delay boundary
        assertFalse(registry.isEligibleResolver(identityId, bytes32(0)));
        assertEq(
            registry.resolverLifecycleState(identityId),
            uint8(LibResolverJury.ResolverLifecycle.ResolverPendingActivation)
        );

        vm.warp(block.timestamp + activationDelay - 1);
        assertFalse(registry.isEligibleResolver(identityId, bytes32(0)));

        vm.warp(block.timestamp + 1);
        assertTrue(registry.isEligibleResolver(identityId, bytes32(0)));
        assertEq(registry.resolverLifecycleState(identityId), uint8(LibResolverJury.ResolverLifecycle.ResolverActive));
    }

    function testFuzz_StakeReleaseOnlyWhenAllReleaseGatesAreSatisfied(
        address owner,
        uint64 exitCooldown,
        bool unresolvedGate,
        bool slashGate
    ) public {
        vm.assume(owner != address(0));
        vm.assume(owner.code.length == 0);
        exitCooldown = uint64(bound(exitCooldown, 1, 90 days));
        registry.configure(address(registryIdentity), address(feeToken), address(eveToken), 0, exitCooldown);
        uint256 identityId = _fundedResolverIdentity(owner, 100e18);

        vm.prank(owner);
        registry.activateResolver();
        vm.prank(owner);
        registry.requestResolverExit();

        // Feature: resolver-identity-jury, Property 6: Stake release only when all release gates are satisfied
        vm.expectRevert(abi.encodeWithSelector(Errors.StakeLocked.selector, identityId));
        vm.prank(owner);
        registry.withdrawResolverStake();

        vm.warp(block.timestamp + exitCooldown);
        if (unresolvedGate) {
            registry.setUnresolvedCommittees(identityId, 1);
        }
        if (slashGate) {
            registry.setSlashLock(identityId, block.timestamp + 1 days);
        }

        if (unresolvedGate || slashGate) {
            vm.expectRevert(abi.encodeWithSelector(Errors.StakeLocked.selector, identityId));
            vm.prank(owner);
            registry.withdrawResolverStake();

            registry.setUnresolvedCommittees(identityId, 0);
            registry.clearSlashLock(identityId);
        }

        vm.prank(owner);
        registry.withdrawResolverStake();

        assertEq(registry.recordedStake(identityId), 0);
        assertEq(eveToken.balanceOf(owner), 100e18);
        assertEq(registry.resolverLifecycleState(identityId), uint8(LibResolverJury.ResolverLifecycle.Exited));
    }

    function _assertZeroReputation(uint256 identityId) internal view {
        (
            uint64 marketsCreated,
            uint64 marketsResolved,
            uint64 disputesRaised,
            uint64 outcomesUpheld,
            uint64 outcomesOverturned
        ) = reputation.creatorCounts(identityId);

        assertEq(marketsCreated, 0);
        assertEq(marketsResolved, 0);
        assertEq(disputesRaised, 0);
        assertEq(outcomesUpheld, 0);
        assertEq(outcomesOverturned, 0);

        (
            uint64 totalSelections,
            uint64 commitCount,
            uint64 revealCount,
            uint64 missedCommitCount,
            uint64 missedRevealCount,
            uint64 invalidRevealCount,
            uint64 finalAgreementCount,
            uint64 slashCount
        ) = reputation.resolverCounts(identityId);

        assertEq(totalSelections, 0);
        assertEq(commitCount, 0);
        assertEq(revealCount, 0);
        assertEq(missedCommitCount, 0);
        assertEq(missedRevealCount, 0);
        assertEq(invalidRevealCount, 0);
        assertEq(finalAgreementCount, 0);
        assertEq(slashCount, 0);
    }

    function _fundedResolverIdentity(address owner, uint256 stakeAmount) internal returns (uint256 identityId) {
        identityId = _mintRegistryIdentity(owner);

        vm.prank(owner);
        registry.setResolverRole(true);

        eveToken.mint(owner, stakeAmount);
        vm.prank(owner);
        eveToken.approve(address(registry), stakeAmount);
        vm.prank(owner);
        registry.depositResolverStake(stakeAmount);
    }

    function _mintRegistryIdentity(address owner) internal returns (uint256 identityId) {
        feeToken.mint(owner, 1e6);
        vm.prank(owner);
        feeToken.approve(address(registry), 1e6);
        vm.prank(owner);
        identityId = registry.mintIdentity();
    }
}
