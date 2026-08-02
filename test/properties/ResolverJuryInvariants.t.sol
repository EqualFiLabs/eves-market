// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/// forge-config: default.fuzz.runs = 100
/// forge-config: default.invariant.runs = 10
/// forge-config: default.invariant.depth = 5
/// forge-config: default.invariant.fail-on-revert = true

import {StdInvariant} from "../../lib/forge-std/src/StdInvariant.sol";
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
import {MockUSDC} from "test/helpers/MockUSDC.sol";

contract ResolverJuryFundHarness is
    ResolverJuryFacet,
    ResolverRegistryFacet,
    ResolverRegistryViewFacet,
    ResolverRegistryRewardsFacet,
    ResolverRegistryReputationFacet,
    BondManagerFacet
{
    function configure(address eveIdentity, address mintFeeToken, address eveToken, address bondToken) external {
        LibResolverJury.store().eveIdentity = eveIdentity;
        LibEveMarket.MarketConfig storage config = LibEveMarket.store().config;
        config.eveToken = eveToken;
        config.bondToken = bondToken;
        config.eveTreasury = address(uint160(uint256(keccak256(abi.encode(address(this), "treasury")))));
        config.resolutionBondL2 = 0.5 ether;
        config.resolverJuryConfig.identityMintFeeToken = mintFeeToken;
        config.resolverJuryConfig.identityMintFee = 1e6;
        config.resolverJuryConfig.resolverSeatStake = 100e18;
        config.resolverJuryConfig.activeEpochSize = 16;
        config.resolverJuryConfig.participationGraceCount = 5;
        config.resolverJuryConfig.concurrencyLimit = 5;
        config.resolverJuryConfig.commitDuration = 1 hours;
        config.resolverJuryConfig.revealDuration = 1 hours;
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
        config.resolverJuryConfig.appealSuccessRoutingBps = [uint16(7_000), 1_000, 1_000, 1_000];
        config.resolverJuryConfig.appealFailureRoutingBps = [uint16(4_000), 3_000, 3_000];
        delete config.resolverJuryConfig.committeeSizesByRound;
        config.resolverJuryConfig.committeeSizesByRound.push(3);
        config.resolverJuryConfig.committeeSizesByRound.push(5);
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
        dispute.rounds[dispute.currentRound].seed = seed == bytes32(0) ? keccak256("fund-seed") : seed;
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

    function rewardPool(bytes32 disputeId) external view returns (uint128) {
        return LibResolverJury.store().disputes[disputeId].rewardPoolBond;
    }

    function eveTreasury() external view returns (address) {
        return LibEveMarket.store().config.eveTreasury;
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

    function finalizeFromJury(bytes32, uint8) external {}
}

contract ResolverJuryFundConservationHandler is Test {
    address internal alice = makeAddr("fund-alice");
    address internal bob = makeAddr("fund-bob");
    address internal carol = makeAddr("fund-carol");
    address internal dave = makeAddr("fund-dave");
    address internal erin = makeAddr("fund-erin");
    address internal claimant = makeAddr("fund-claimant");

    uint256 public bondEntered;
    uint256 public bondRouted;
    uint256 public eveRewardEntered;
    uint256 public eveRewardRouted;
    uint256 public completedLifecycles;
    uint256 internal nonce;

    function runAppealLifecycle(uint8 mode, bytes32 salt) external {
        bool appealSucceeds = (mode & 1) != 0;
        bool withClaimant = (mode & 2) != 0;
        Scenario memory scenario = _newScenario();
        _activateResolvers(scenario, 5);

        bytes32 marketId = keccak256(abi.encode("fund-appeal", nonce, mode, salt));
        bytes32 disputeId = scenario.jury.seedDisputedMarket(marketId);
        scenario.jury.seedSelectionReady(disputeId, keccak256(abi.encode(salt, "round0")));
        scenario.jury.selectCommittee(disputeId);
        _resolveCurrentRound(scenario, disputeId, uint8(LibEveMarket.MarketOutcome.Yes), salt);

        uint8 finalOutcome =
            appealSucceeds ? uint8(LibEveMarket.MarketOutcome.No) : uint8(LibEveMarket.MarketOutcome.Yes);
        if (withClaimant) {
            scenario.jury.seedResolutionClaimant(marketId, claimant, finalOutcome);
        }

        uint128 appealBond = 1 ether;
        scenario.bondToken.mint(alice, appealBond);
        vm.prank(alice);
        scenario.bondToken.approve(address(scenario.jury), appealBond);
        vm.prank(alice);
        scenario.jury.openAppeal(disputeId);

        scenario.jury.seedSelectionReady(disputeId, keccak256(abi.encode(salt, "round1")));
        scenario.jury.selectCommittee(disputeId);
        _resolveCurrentRound(scenario, disputeId, finalOutcome, keccak256(abi.encode(salt, "appeal")));

        uint256 beforeTotal = _bondRecipientTotal(scenario);
        vm.warp(scenario.jury.disputeView(disputeId).appealDeadline);
        scenario.jury.finalizeDispute(disputeId);
        uint256 routed = _bondRecipientTotal(scenario) - beforeTotal;

        assertEq(routed, appealBond);
        assertEq(scenario.eveToken.balanceOf(address(scenario.jury)), 5 * 100e18);
        assertEq(scenario.bondToken.balanceOf(address(scenario.jury)), 0);
        bondEntered += appealBond;
        bondRouted += routed;
        ++completedLifecycles;
        ++nonce;
    }

    function runNoRevealRewardLifecycle(bytes32 salt) external {
        Scenario memory scenario = _newScenario();
        _activateResolvers(scenario, 3);

        bytes32 disputeId = scenario.jury.seedDisputedMarket(keccak256(abi.encode("fund-no-reveal", nonce, salt)));
        scenario.jury.seedSelectionReady(disputeId, keccak256(abi.encode(salt, "no-reveal")));
        scenario.jury.selectCommittee(disputeId);

        vm.warp(vm.getBlockTimestamp() + 1 hours);
        scenario.jury.closeCommit(disputeId);
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        scenario.jury.closeRevealAndTally(disputeId);

        uint256 rewardPool = scenario.jury.rewardPool(disputeId);
        uint256 treasuryBefore = scenario.eveToken.balanceOf(scenario.jury.eveTreasury());
        vm.warp(scenario.jury.disputeView(disputeId).appealDeadline);
        scenario.jury.finalizeDispute(disputeId);
        uint256 routed = scenario.eveToken.balanceOf(scenario.jury.eveTreasury()) - treasuryBefore;

        assertEq(routed, rewardPool);
        eveRewardEntered += rewardPool;
        eveRewardRouted += routed;
        ++completedLifecycles;
        ++nonce;
    }

    struct Scenario {
        ResolverJuryFundHarness jury;
        EveIdentity identity;
        MockUSDC feeToken;
        MockEveToken eveToken;
        MockEveToken bondToken;
    }

    function _newScenario() internal returns (Scenario memory scenario) {
        scenario.jury = new ResolverJuryFundHarness();
        scenario.identity = new EveIdentity(address(scenario.jury), "Eve Identity", "EVE-ID");
        scenario.feeToken = new MockUSDC();
        scenario.eveToken = new MockEveToken();
        scenario.bondToken = new MockEveToken();
        scenario.jury
            .configure(
                address(scenario.identity),
                address(scenario.feeToken),
                address(scenario.eveToken),
                address(scenario.bondToken)
            );
    }

    function _activateResolvers(Scenario memory scenario, uint256 count) internal {
        _activateResolver(scenario, alice);
        _activateResolver(scenario, bob);
        _activateResolver(scenario, carol);
        if (count > 3) {
            _activateResolver(scenario, dave);
            _activateResolver(scenario, erin);
        }
    }

    function _activateResolver(Scenario memory scenario, address owner) internal {
        scenario.feeToken.mint(owner, 1e6);
        vm.prank(owner);
        scenario.feeToken.approve(address(scenario.jury), 1e6);
        vm.prank(owner);
        uint256 identityId = scenario.jury.mintIdentity();

        vm.prank(owner);
        scenario.jury.setResolverRole(true);

        scenario.eveToken.mint(owner, 100e18);
        vm.prank(owner);
        scenario.eveToken.approve(address(scenario.jury), 100e18);
        vm.prank(owner);
        scenario.jury.depositResolverStake(100e18);

        scenario.jury.seedActiveResolverEpochMember(identityId);
    }

    function _resolveCurrentRound(Scenario memory scenario, bytes32 disputeId, uint8 outcome, bytes32 salt) internal {
        uint8 round = scenario.jury.disputeView(disputeId).currentRound;
        uint256[] memory members = scenario.jury.committeeMembers(disputeId, round);
        for (uint256 index; index < members.length; ++index) {
            _commitVoteByIdentity(scenario, disputeId, members[index], outcome, salt);
        }

        vm.warp(vm.getBlockTimestamp() + 1 hours);
        scenario.jury.closeCommit(disputeId);
        for (uint256 index; index < members.length; ++index) {
            _revealVoteByIdentity(scenario, disputeId, members[index], outcome, salt);
        }

        vm.warp(vm.getBlockTimestamp() + 1 hours);
        scenario.jury.closeRevealAndTally(disputeId);
    }

    function _commitVoteByIdentity(
        Scenario memory scenario,
        bytes32 disputeId,
        uint256 identityId,
        uint8 outcome,
        bytes32 salt
    ) internal {
        address owner = scenario.identity.ownerOf(identityId);
        vm.prank(owner);
        scenario.jury
            .commitVote(
                disputeId,
                keccak256(abi.encode(disputeId, identityId, outcome, keccak256(abi.encode(salt, identityId))))
            );
    }

    function _revealVoteByIdentity(
        Scenario memory scenario,
        bytes32 disputeId,
        uint256 identityId,
        uint8 outcome,
        bytes32 salt
    ) internal {
        vm.prank(scenario.identity.ownerOf(identityId));
        scenario.jury.revealVote(disputeId, outcome, keccak256(abi.encode(salt, identityId)));
    }

    function _bondRecipientTotal(Scenario memory scenario) internal view returns (uint256) {
        return scenario.bondToken.balanceOf(alice) + scenario.bondToken.balanceOf(bob)
            + scenario.bondToken.balanceOf(carol) + scenario.bondToken.balanceOf(dave)
            + scenario.bondToken.balanceOf(erin) + scenario.bondToken.balanceOf(claimant)
            + scenario.bondToken.balanceOf(scenario.jury.eveTreasury());
    }
}

contract ResolverJuryInvariantsTest is StdInvariant, Test {
    ResolverJuryFundConservationHandler internal handler;

    function setUp() public {
        handler = new ResolverJuryFundConservationHandler();
        targetContract(address(handler));
    }

    function testFuzz_FundConservationAcrossBondsSlashingAndRewards(uint8 mode, bytes32 salt) public {
        // Feature: resolver-identity-jury, Property 20: Fund conservation across bonds, slashing, and rewards
        handler.runAppealLifecycle(mode, salt);
        handler.runNoRevealRewardLifecycle(keccak256(abi.encode(salt, "reward")));
        assertEq(handler.bondRouted(), handler.bondEntered());
        assertEq(handler.eveRewardRouted(), handler.eveRewardEntered());
    }

    function invariant_FundConservationAcrossBondsSlashingAndRewards() public view {
        assertEq(handler.bondRouted(), handler.bondEntered());
        assertEq(handler.eveRewardRouted(), handler.eveRewardEntered());
    }

    function afterInvariant() public view {
        assertGt(handler.completedLifecycles(), 0);
    }
}
