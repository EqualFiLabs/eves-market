// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "../../lib/forge-std/src/Test.sol";

import {IResolverRegistryFacet} from "src/interfaces/IResolverRegistryFacet.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Events} from "src/libraries/Events.sol";
import {LibCLOBBook} from "src/libraries/LibCLOBBook.sol";
import {LibDiamond} from "src/libraries/LibDiamond.sol";
import {LibEveMarket} from "src/libraries/LibEveMarket.sol";
import {LibResolverJury} from "src/libraries/LibResolverJury.sol";
import {LibResolverRewards} from "src/libraries/LibResolverRewards.sol";
import {ResolverRegistryFacet} from "src/facets/ResolverRegistryFacet.sol";
import {EveIdentity} from "src/tokens/EveIdentity.sol";
import {EvesPositionManager} from "src/tokens/EvesPositionManager.sol";
import {IEvesPositionManager} from "src/interfaces/IEvesPositionManager.sol";
import {MockEveToken} from "test/helpers/MockEveToken.sol";
import {MockUSDC} from "test/helpers/MockUSDC.sol";

contract ResolverRegistryHarness is ResolverRegistryFacet {
    function configureIdentity(
        address eveIdentity,
        address mintFeeToken,
        address eveToken,
        uint256 mintFee,
        uint256 poolCap,
        uint256 stakeRequirement,
        uint256 stakeCap
    ) external {
        if (
            mintFee > type(uint128).max || poolCap > type(uint16).max || stakeRequirement > type(uint128).max
                || stakeCap > type(uint128).max
        ) {
            revert Errors.InvalidConfigValue("registryConfig");
        }

        LibResolverJury.store().eveIdentity = eveIdentity;
        LibDiamond.setContractOwner(msg.sender);
        LibEveMarket.MarketConfig storage config = LibEveMarket.store().config;
        config.eveToken = eveToken;
        config.bondToken = eveToken;
        config.eveTreasury = address(uint160(uint256(keccak256("resolver-registry-treasury"))));
        config.resolverJuryConfig.identityMintFeeToken = mintFeeToken;
        config.resolverJuryConfig.identityMintFee = uint128(mintFee);
        config.resolverJuryConfig.activeEpochSize = uint16(poolCap);
        config.resolverJuryConfig.resolverEpochDuration = 180 days;
        config.resolverJuryConfig.resolverRotationWindow = 30 days;
        config.resolverJuryConfig.epochRandomnessCommitDuration = 1 days;
        config.resolverJuryConfig.epochRandomnessRevealDuration = 1 days;
        config.resolverJuryConfig.epochSelectionDuration = 1 days;
        config.resolverJuryConfig.minEpochRandomnessReveals = 1;
        config.resolverJuryConfig.resolverSeatStake = uint128(stakeRequirement);
        config.resolverJuryConfig.missedCommitSlashBps = 1_000;
        config.resolverJuryConfig.missedRevealSlashBps = 1_000;
        config.resolverJuryConfig.conflictPositionThreshold = 1e6;
    }

    function setLifecycle(uint256 identityId, uint8 lifecycle) external {
        LibResolverJury.store().identities[identityId].lifecycle = LibResolverJury.ResolverLifecycle(lifecycle);
    }

    function setRecordedStake(uint256 identityId, uint256 stakeAmount) external {
        if (stakeAmount > type(uint128).max) {
            revert Errors.InvalidAmount(stakeAmount);
        }

        LibResolverJury.store().identities[identityId].resolverStake = uint128(stakeAmount);
    }

    function recordedStake(uint256 identityId) external view returns (uint128) {
        return LibResolverJury.store().identities[identityId].resolverStake;
    }

    function setResolverTiming(uint256 activationDelay, uint256 exitCooldown) external {
        if (activationDelay > type(uint64).max || exitCooldown > type(uint64).max) {
            revert Errors.InvalidConfigValue("resolverTiming");
        }

        LibEveMarket.ResolverJuryConfig storage config = LibEveMarket.store().config.resolverJuryConfig;
        config.activationDelay = uint64(activationDelay);
        config.exitCooldown = uint64(exitCooldown);
    }

    function setResolverPoolCap(uint256 poolCap) external {
        if (poolCap > type(uint16).max) {
            revert Errors.InvalidConfigValue("activeEpochSize");
        }

        LibEveMarket.store().config.resolverJuryConfig.activeEpochSize = uint16(poolCap);
    }

    function setBondToken(address bondToken) external {
        LibEveMarket.store().config.bondToken = bondToken;
    }

    function setTreasury(address treasury) external {
        LibEveMarket.store().config.eveTreasury = treasury;
    }

    function setEpochCandidateFee(address token, uint128 amount) external {
        LibEveMarket.store().config.resolverJuryConfig.epochCandidateFeeToken = token;
        LibEveMarket.store().config.resolverJuryConfig.epochCandidateFeeAmount = amount;
    }

    function setIdentityMintFee(address token, uint256 amount) external {
        if (amount > type(uint128).max) {
            revert Errors.InvalidAmount(amount);
        }

        LibEveMarket.store().config.resolverJuryConfig.identityMintFeeToken = token;
        LibEveMarket.store().config.resolverJuryConfig.identityMintFee = uint128(amount);
    }

    function accrueTradingReward(address token, uint128 amount) external {
        LibResolverRewards.accrueTradingFee(token, amount);
    }

    function setMarketCreator(bytes32 marketId, address creator) external {
        LibEveMarket.store().markets[marketId].marketId = marketId;
        LibEveMarket.store().markets[marketId].creator = creator;
    }

    function setConflictPositionThreshold(uint256 threshold) external {
        LibEveMarket.store().config.resolverJuryConfig.conflictPositionThreshold = threshold;
    }

    function setBinaryMarket(
        bytes32 marketId,
        uint8 marketType,
        address positionToken,
        uint256 yesPositionId,
        uint256 noPositionId
    ) external {
        LibEveMarket.Market storage market = LibEveMarket.store().markets[marketId];
        market.marketId = marketId;
        market.marketType = LibEveMarket.MarketType(marketType);
        market.positionToken = positionToken;
        market.yesPositionId = yesPositionId;
        market.noPositionId = noPositionId;
    }

    function setMultiOutcomeMarket(bytes32 marketId, address positionToken, uint8 outcomeCount) external {
        LibEveMarket.Market storage market = LibEveMarket.store().markets[marketId];
        market.marketId = marketId;
        market.marketType = LibEveMarket.MarketType.MULTI_OUTCOME_ORDERBOOK;
        market.positionToken = positionToken;
        LibEveMarket.store().multiOutcomeMarkets[marketId].marketId = marketId;
        LibEveMarket.store().multiOutcomeMarkets[marketId].outcomeCount = outcomeCount;
        LibEveMarket.store().multiOutcomeMarkets[marketId].exists = true;
        for (uint8 outcome; outcome < outcomeCount; ++outcome) {
            LibEveMarket.store().multiOutcomePositionIds[marketId][outcome] = uint256(uint32(outcome + 1));
        }
    }

    function mintPosition(address positionToken, address to, uint256 positionId, uint256 amount) external {
        IEvesPositionManager(positionToken).mint(to, positionId, amount);
    }

    function seedBinaryCurveInventory(
        bytes32 marketId,
        bool isYesSide,
        address maker,
        uint256 curveId,
        uint256 curveSide,
        uint256 remainingVolume
    ) external {
        LibEveMarket.Market storage market = LibEveMarket.store().markets[marketId];
        bytes32 bookId = isYesSide ? market.yesBookId : market.noBookId;
        if (bookId == bytes32(0)) {
            bookId = LibCLOBBook.marketBookId(marketId, isYesSide);
            if (isYesSide) {
                market.yesBookId = bookId;
            } else {
                market.noBookId = bookId;
            }
        }

        _seedCurveInventory(
            bookId,
            marketId,
            isYesSide,
            market.positionToken,
            isYesSide ? market.yesPositionId : market.noPositionId,
            maker,
            curveId,
            curveSide,
            remainingVolume
        );
    }

    function seedMultiOutcomeCurveInventory(
        bytes32 marketId,
        uint256 outcome,
        address maker,
        uint256 curveId,
        uint256 curveSide,
        uint256 remainingVolume
    ) external {
        if (outcome > type(uint8).max) {
            revert Errors.InvalidAmount(outcome);
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        bytes32 bookId = state.multiOutcomeBookIds[marketId][uint8(outcome)];
        if (bookId == bytes32(0)) {
            bookId = LibCLOBBook.multiOutcomeBookId(marketId, uint8(outcome));
            state.multiOutcomeBookIds[marketId][uint8(outcome)] = bookId;
        }

        _seedCurveInventory(
            bookId,
            marketId,
            false,
            state.markets[marketId].positionToken,
            state.multiOutcomePositionIds[marketId][uint8(outcome)],
            maker,
            curveId,
            curveSide,
            remainingVolume
        );
    }

    function seedFinalityReputation(
        bytes32 disputeId,
        bytes32 marketId,
        address creator,
        uint256 proposedOutcome,
        uint256 currentRound,
        uint256[] calldata selectedIdentityIds,
        uint256[] calldata revealedOutcomes
    ) external {
        if (proposedOutcome > type(uint8).max || currentRound > type(uint8).max) {
            revert Errors.InvalidAmount(proposedOutcome > type(uint8).max ? proposedOutcome : currentRound);
        }
        if (selectedIdentityIds.length != revealedOutcomes.length) {
            revert Errors.ArrayLengthMismatch(selectedIdentityIds.length, revealedOutcomes.length);
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        state.markets[marketId].marketId = marketId;
        state.markets[marketId].creator = creator;
        state.resolutions[marketId].marketId = marketId;
        state.resolutions[marketId].proposedOutcome = uint8(proposedOutcome);
        state.resolutions[marketId].proposer = creator;

        LibResolverJury.Dispute storage dispute = LibResolverJury.store().disputes[disputeId];
        dispute.marketId = marketId;
        dispute.currentRound = uint8(currentRound);
        for (uint256 index; index < selectedIdentityIds.length; ++index) {
            if (revealedOutcomes[index] > type(uint8).max) {
                revert Errors.InvalidAmount(revealedOutcomes[index]);
            }

            uint256 identityId = selectedIdentityIds[index];
            dispute.allSelected.push(identityId);
            dispute.everSelected[identityId] = true;
            dispute.rounds[uint8(currentRound)].hasRevealed[identityId] = true;
            dispute.rounds[uint8(currentRound)].revealedOutcome[identityId] = uint8(revealedOutcomes[index]);
        }
    }

    function applyFinality(bytes32 disputeId, uint256 finalResult) external {
        if (finalResult > type(uint8).max) {
            revert Errors.InvalidAmount(finalResult);
        }

        IResolverRegistryFacet(address(this)).applyFinalityReputation(disputeId, uint8(finalResult));
    }

    function _seedCurveInventory(
        bytes32 bookId,
        bytes32 marketId,
        bool isYesSide,
        address positionToken,
        uint256 positionId,
        address maker,
        uint256 curveId,
        uint256 curveSide,
        uint256 remainingVolume
    ) internal {
        if (curveSide > uint256(type(LibEveMarket.CurveSide).max) || remainingVolume > type(uint128).max) {
            revert Errors.InvalidAmount(curveSide > uint256(type(LibEveMarket.CurveSide).max)
                    ? curveSide
                    : remainingVolume);
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Book storage book = state.books[bookId];
        book.bookId = bookId;
        book.marketId = marketId;
        book.isYesSide = isYesSide;
        book.assetType = LibEveMarket.BookAssetType.ERC1155;
        book.baseToken = positionToken;
        book.baseTokenId = positionId;
        book.active = true;

        LibEveMarket.StoredCurve storage curve = state.curves[curveId];
        curve.active = true;
        curve.isYesSide = isYesSide;
        curve.curveSide = LibEveMarket.CurveSide(curveSide);
        curve.maker = maker;
        curve.bookId = bookId;
        curve.remainingVolume = uint128(remainingVolume);
        state.bookCurveIds[bookId].push(curveId);
    }
}

contract ResolverRegistryTest is Test {
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    ResolverRegistryHarness internal registry;
    EveIdentity internal identity;
    MockUSDC internal feeToken;
    MockEveToken internal eveToken;
    MockEveToken internal bondToken;
    EvesPositionManager internal positions;

    function setUp() public {
        registry = new ResolverRegistryHarness();
        identity = new EveIdentity(address(registry), "Eve Identity", "EVE-ID");
        feeToken = new MockUSDC();
        eveToken = new MockEveToken();
        bondToken = new MockEveToken();
        positions = new EvesPositionManager(address(registry), "");
        registry.configureIdentity(address(identity), address(feeToken), address(eveToken), 25e6, 50, 100e18, 250e18);
        registry.setBondToken(address(bondToken));
    }

    function test_MintIdentityCollectsFeeAndInitializesRecords() public {
        vm.warp(1_700_000_000);
        address expectedTreasury = address(uint160(uint256(keccak256("resolver-registry-treasury"))));
        feeToken.mint(alice, 25e6);

        vm.prank(alice);
        feeToken.approve(address(registry), 25e6);

        vm.prank(alice);
        uint256 identityId = registry.mintIdentity();

        assertEq(identityId, 1);
        assertEq(identity.ownerOf(identityId), alice);
        assertEq(identity.identityOf(alice), identityId);
        assertEq(registry.identityByOwner(alice), identityId);
        assertEq(registry.identityByOwner(bob), 0);
        assertEq(feeToken.balanceOf(address(registry)), 0);
        assertEq(feeToken.balanceOf(expectedTreasury), 25e6);

        IResolverRegistryFacet.CreatorReputationView memory creatorRep = registry.creatorReputation(identityId);
        assertEq(creatorRep.marketsCreated, 0);
        assertEq(creatorRep.marketsResolved, 0);
        assertEq(creatorRep.disputesRaised, 0);
        assertEq(creatorRep.outcomesUpheld, 0);
        assertEq(creatorRep.outcomesOverturned, 0);

        IResolverRegistryFacet.ResolverReputationView memory resolverRep = registry.resolverReputation(identityId);
        assertEq(resolverRep.activationTimestamp, uint64(block.timestamp));
        assertEq(resolverRep.totalSelections, 0);
        assertEq(resolverRep.commitCount, 0);
        assertEq(resolverRep.revealCount, 0);
        assertEq(registry.resolverLifecycleState(identityId), uint8(LibResolverJury.ResolverLifecycle.Minted));
    }

    function test_MintIdentityFeeFailureLeavesTokenAndIdentityStateUnchanged() public {
        feeToken.mint(alice, 25e6);

        vm.expectRevert(Errors.MintFeeCollectionFailed.selector);
        vm.prank(alice);
        registry.mintIdentity();

        assertEq(identity.totalMinted(), 0);
        assertEq(identity.identityOf(alice), 0);
        assertEq(feeToken.balanceOf(alice), 25e6);
        assertEq(feeToken.balanceOf(address(registry)), 0);
    }

    function test_MintIdentityRejectsMissingTreasuryForNonzeroFee() public {
        feeToken.mint(alice, 25e6);
        registry.setTreasury(address(0));

        vm.prank(alice);
        feeToken.approve(address(registry), 25e6);

        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(alice);
        registry.mintIdentity();

        assertEq(identity.totalMinted(), 0);
        assertEq(feeToken.balanceOf(alice), 25e6);
    }

    function test_MintIdentitySkipsTreasuryTransferWhenFeeIsZero() public {
        address expectedTreasury = address(uint160(uint256(keccak256("resolver-registry-treasury"))));
        registry.setIdentityMintFee(address(feeToken), 0);

        vm.prank(alice);
        uint256 identityId = registry.mintIdentity();

        assertEq(identityId, 1);
        assertEq(identity.ownerOf(identityId), alice);
        assertEq(feeToken.balanceOf(expectedTreasury), 0);
        assertEq(feeToken.balanceOf(address(registry)), 0);
    }

    function test_RoleSpecificSettersPreserveOtherIdentityRole() public {
        _mintIdentity(alice);

        vm.prank(alice);
        registry.setCreatorRole(true);

        vm.prank(alice);
        registry.setResolverRole(true);

        uint256 identityId = identity.identityOf(alice);
        assertTrue(identity.hasCreatorRole(identityId));
        assertTrue(identity.hasResolverRole(identityId));

        vm.prank(alice);
        registry.setResolverRole(false);

        assertTrue(identity.hasCreatorRole(identityId));
        assertFalse(identity.hasResolverRole(identityId));
    }

    function test_RoleSettersRejectCallerWithoutIdentity() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.NotIdentityOwner.selector, bob));
        vm.prank(bob);
        registry.setResolverRole(false);
    }

    function test_DisablingResolverRoleRejectsRestrictedLifecycle() public {
        uint256 identityId = _mintIdentity(alice);

        vm.prank(alice);
        registry.setResolverRole(true);
        registry.setLifecycle(identityId, uint8(LibResolverJury.ResolverLifecycle.ResolverActive));

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.CannotExitFromState.selector, uint8(LibResolverJury.ResolverLifecycle.ResolverActive)
            )
        );
        vm.prank(alice);
        registry.setResolverRole(false);
    }

    function test_ActiveResolverEpochSizeReadsConfig() public view {
        assertEq(registry.activeResolverEpochSize(), 50);
    }

    function test_ResolverDashboardSurfacesIdentityConfigAndEpochState() public {
        registry.setResolverTiming(1 days, 7 days);
        uint256 identityId = _mintIdentity(alice);

        vm.prank(alice);
        registry.setCreatorRole(true);
        vm.prank(alice);
        registry.setResolverRole(true);

        eveToken.mint(alice, 100e18);
        vm.prank(alice);
        eveToken.approve(address(registry), 100e18);
        vm.prank(alice);
        registry.depositResolverStake(100e18);

        _finalizeSingleCandidateEpoch(alice, identityId);

        (
            IResolverRegistryFacet.ResolverIdentityView memory resolver,
            IResolverRegistryFacet.ResolverJuryConfigView memory config,
            IResolverRegistryFacet.ResolverEpochPoolView memory pool
        ) = registry.resolverDashboard(alice);

        assertEq(resolver.identityId, identityId);
        assertEq(resolver.owner, alice);
        assertTrue(resolver.creatorRole);
        assertTrue(resolver.resolverRole);
        assertEq(resolver.lifecycle, uint8(LibResolverJury.ResolverLifecycle.ResolverActive));
        assertEq(resolver.effectiveLifecycle, uint8(LibResolverJury.ResolverLifecycle.ResolverActive));
        assertEq(resolver.resolverStake, 100e18);
        assertGt(resolver.activationTimestamp, 0);
        assertEq(resolver.activeAt, uint64(resolver.activationTimestamp + 1 days));
        assertEq(resolver.withdrawableAt, 0);
        assertTrue(resolver.currentEpochMember);
        assertTrue(resolver.globallyEligible);

        assertEq(config.eveIdentity, address(identity));
        assertEq(config.identityMintFeeToken, address(feeToken));
        assertEq(config.identityMintFee, 25e6);
        assertEq(config.resolverSeatStake, 100e18);
        assertEq(config.epochCandidateFeeToken, address(0));
        assertEq(config.epochCandidateFeeAmount, 0);
        assertEq(config.activeEpochSize, 1);
        assertEq(config.activationDelay, 1 days);
        assertEq(config.exitCooldown, 7 days);

        assertEq(pool.currentEpochId, 1);
        assertEq(pool.activeResolverCount, 1);
        assertEq(pool.eligibleResolverCount, 1);
        assertEq(pool.activeEpochSize, 1);
    }

    function test_DepositResolverStakePullsEveIntoCustodyAndRecordsStake() public {
        uint256 identityId = _mintIdentity(alice);

        vm.prank(alice);
        registry.setResolverRole(true);

        eveToken.mint(alice, 150e18);
        vm.prank(alice);
        eveToken.approve(address(registry), 150e18);

        vm.expectEmit(true, true, false, true);
        emit Events.ResolverStakeDeposited(identityId, alice, 100e18, 100e18);

        vm.prank(alice);
        registry.depositResolverStake(100e18);

        assertEq(registry.recordedStake(identityId), 100e18);
        assertEq(eveToken.balanceOf(address(registry)), 100e18);
        assertEq(bondToken.balanceOf(address(registry)), 0);
        assertEq(eveToken.balanceOf(alice), 50e18);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidAmount.selector, 150e18));
        vm.prank(alice);
        registry.depositResolverStake(50e18);

        assertEq(registry.recordedStake(identityId), 100e18);
        assertEq(eveToken.balanceOf(address(registry)), 100e18);
        assertEq(bondToken.balanceOf(address(registry)), 0);
        assertEq(eveToken.balanceOf(alice), 50e18);
    }

    function test_DepositResolverStakeRejectsStakeCapOverflowWithoutTokenMovement() public {
        uint256 identityId = _mintResolverIdentity(alice);
        eveToken.mint(alice, 251e18);

        vm.prank(alice);
        eveToken.approve(address(registry), 251e18);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidAmount.selector, uint256(251e18)));
        vm.prank(alice);
        registry.depositResolverStake(251e18);

        assertEq(registry.recordedStake(identityId), 0);
        assertEq(eveToken.balanceOf(address(registry)), 0);
        assertEq(eveToken.balanceOf(alice), 251e18);
    }

    function test_DepositResolverStakeRejectsNonResolverRoleWithoutTokenMovement() public {
        uint256 identityId = _mintIdentity(alice);
        eveToken.mint(alice, 100e18);

        vm.prank(alice);
        eveToken.approve(address(registry), 100e18);

        vm.expectRevert(abi.encodeWithSelector(Errors.NotResolverRole.selector, identityId));
        vm.prank(alice);
        registry.depositResolverStake(100e18);

        assertEq(registry.recordedStake(identityId), 0);
        assertEq(eveToken.balanceOf(address(registry)), 0);
        assertEq(eveToken.balanceOf(alice), 100e18);
    }

    function test_DepositResolverStakeRejectsInsufficientAllowanceWithoutStateChange() public {
        uint256 identityId = _mintResolverIdentity(alice);
        eveToken.mint(alice, 100e18);

        vm.expectRevert(abi.encodeWithSelector(Errors.InsufficientResolverStake.selector, uint128(100e18), uint128(0)));
        vm.prank(alice);
        registry.depositResolverStake(100e18);

        assertEq(registry.recordedStake(identityId), 0);
        assertEq(eveToken.balanceOf(address(registry)), 0);
        assertEq(eveToken.balanceOf(alice), 100e18);
    }

    function test_DepositResolverStakeIgnoresMarketBondTokenBalanceAndAllowance() public {
        uint256 identityId = _mintResolverIdentity(alice);
        bondToken.mint(alice, 100e18);

        vm.prank(alice);
        bondToken.approve(address(registry), 100e18);

        vm.expectRevert(abi.encodeWithSelector(Errors.InsufficientResolverStake.selector, uint128(100e18), uint128(0)));
        vm.prank(alice);
        registry.depositResolverStake(100e18);

        assertEq(registry.recordedStake(identityId), 0);
        assertEq(eveToken.balanceOf(address(registry)), 0);
        assertEq(bondToken.balanceOf(address(registry)), 0);
        assertEq(bondToken.balanceOf(alice), 100e18);
    }

    function test_DepositResolverStakeRejectsInsufficientBalanceWithoutStateChange() public {
        uint256 identityId = _mintResolverIdentity(alice);

        vm.prank(alice);
        eveToken.approve(address(registry), 100e18);

        vm.expectRevert(abi.encodeWithSelector(Errors.InsufficientResolverStake.selector, uint128(100e18), uint128(0)));
        vm.prank(alice);
        registry.depositResolverStake(100e18);

        assertEq(registry.recordedStake(identityId), 0);
        assertEq(eveToken.balanceOf(address(registry)), 0);
        assertEq(eveToken.balanceOf(alice), 0);
    }

    function test_DepositResolverStakeRejectsZeroAmount() public {
        _mintResolverIdentity(alice);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidAmount.selector, uint256(0)));
        vm.prank(alice);
        registry.depositResolverStake(0);
    }

    function test_EpochSelectionActivatesSelectedResolvers() public {
        uint256 identityId = _fundedResolverIdentity(alice, 100e18);

        _finalizeSingleCandidateEpoch(alice, identityId);

        assertEq(registry.activeResolverCount(), 1);
        assertEq(registry.activeResolverAt(0), identityId);
        assertEq(registry.resolverLifecycleState(identityId), uint8(LibResolverJury.ResolverLifecycle.ResolverActive));
        assertTrue(registry.isEligibleResolver(identityId, bytes32(0)));
        assertEq(registry.eligibleResolverCount(), 1);
    }

    function test_EpochCandidateSetIsUncappedButActiveSetIsBounded() public {
        registry.setResolverPoolCap(1);
        uint256 firstIdentityId = _fundedResolverIdentity(alice, 100e18);
        uint256 secondIdentityId = _fundedResolverIdentity(bob, 100e18);

        address[] memory owners = new address[](2);
        owners[0] = alice;
        owners[1] = bob;
        uint256[] memory identityIds = new uint256[](2);
        identityIds[0] = firstIdentityId;
        identityIds[1] = secondIdentityId;
        _finalizeCandidateEpoch(owners, identityIds);

        assertEq(registry.activeResolverCount(), 1);
        assertEq(registry.resolverEpoch(1).candidateCount, 2);
        assertEq(registry.recordedStake(secondIdentityId), 100e18);
    }

    function test_OpenGenesisResolverEpochRequiresOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.NotContractOwner.selector, alice));
        vm.prank(alice);
        registry.openResolverEpochRotation();

        uint64 epochId = registry.openResolverEpochRotation();
        assertEq(epochId, 1);
        assertEq(registry.resolverEpoch(epochId).epochId, 1);
    }

    function test_GenesisOptInSkipsCandidateFee() public {
        address treasury = makeAddr("candidateFeeTreasury");
        registry.setTreasury(treasury);
        registry.setEpochCandidateFee(address(feeToken), 5e6);
        registry.setIdentityMintFee(address(feeToken), 0);

        uint256 identityId = _mintResolverIdentity(alice);
        eveToken.mint(alice, 100e18);
        feeToken.mint(alice, 5e6);

        vm.startPrank(alice);
        eveToken.approve(address(registry), 100e18);
        registry.depositResolverStake(100e18);
        feeToken.approve(address(registry), 5e6);
        vm.stopPrank();

        uint64 epochId = registry.openResolverEpochRotation();
        uint256 aliceFeeTokenBefore = feeToken.balanceOf(alice);

        vm.prank(alice);
        registry.optIntoResolverEpoch(_epochCommitment(epochId, identityId));

        assertEq(feeToken.balanceOf(treasury), 0);
        assertEq(feeToken.balanceOf(alice), aliceFeeTokenBefore);
        assertEq(registry.resolverEpoch(epochId).candidateCount, 1);
    }

    function test_OptIntoPostGenesisResolverEpochCollectsCandidateFeeToTreasury() public {
        uint256 identityId = _activateFundedResolver(alice, 100e18);
        address treasury = makeAddr("candidateFeeTreasury");
        registry.setTreasury(treasury);
        registry.setEpochCandidateFee(address(feeToken), 5e6);
        feeToken.mint(alice, 5e6);

        vm.prank(alice);
        feeToken.approve(address(registry), 5e6);

        vm.warp(block.timestamp + 151 days);
        uint64 epochId = registry.openResolverEpochRotation();

        vm.expectEmit(true, true, true, true);
        emit Events.ResolverEpochCandidateFeePaid(epochId, identityId, address(feeToken), 5e6);
        vm.prank(alice);
        registry.optIntoResolverEpoch(_epochCommitment(epochId, identityId));

        assertEq(epochId, 2);
        assertEq(feeToken.balanceOf(treasury), 5e6);
        assertEq(registry.resolverEpoch(epochId).candidateCount, 1);
    }

    function test_FinalizedTradingRewardsCanBeClaimedByCompliantActiveJurors() public {
        uint256 identityId = _activateFundedResolver(alice, 100e18);
        feeToken.mint(address(registry), 99e6);
        registry.accrueTradingReward(address(feeToken), 99e6);

        vm.warp(block.timestamp + 181 days);
        registry.finalizeResolverTradingRewards(1, address(feeToken));

        (uint128 accrued, uint128 claimed, uint128 claimable) =
            registry.previewResolverRewards(identityId, address(feeToken));
        assertEq(accrued, 99e6);
        assertEq(claimed, 0);
        assertEq(claimable, 99e6);

        vm.prank(alice);
        registry.claimResolverRewards(address(feeToken));

        assertEq(feeToken.balanceOf(alice), 99e6);
        (,, claimable) = registry.previewResolverRewards(identityId, address(feeToken));
        assertEq(claimable, 0);
    }

    function test_EpochSeedUsesStoredReferenceBlockAcrossLaterFinalizerBlock() public {
        registry.setResolverPoolCap(1);
        uint256 identityId = _fundedResolverIdentity(alice, 100e18);
        uint64 epochId = registry.openResolverEpochRotation();

        vm.prank(alice);
        registry.optIntoResolverEpoch(_epochCommitment(epochId, identityId));

        vm.warp(block.timestamp + 1 days + 1);
        registry.closeResolverEpochRandomnessCommit(epochId);
        uint256 referenceBlock = block.number + 1;

        vm.prank(alice);
        registry.revealResolverEpochRandomness(epochId, _epochValue(identityId), _epochSalt(identityId));

        vm.roll(referenceBlock + 10);
        vm.warp(block.timestamp + 1 days + 1);
        uint64 seedReferenceBlock = uint64(block.number + 1);
        vm.expectEmit(true, false, false, true);
        emit Events.ResolverEpochSeedReferenceBlockSet(epochId, seedReferenceBlock);
        assertEq(registry.finalizeResolverEpochSeed(epochId), bytes32(0));
        vm.roll(seedReferenceBlock + 10);

        bytes32 accumulator = keccak256(abi.encode(bytes32(0), identityId, _epochValue(identityId)));
        bytes32 expectedSeed = keccak256(
            abi.encode(accumulator, epochId, block.chainid, address(registry), blockhash(seedReferenceBlock), 1)
        );
        bytes32 seed = registry.finalizeResolverEpochSeed(epochId);

        assertEq(seed, expectedSeed);
        assertEq(registry.resolverEpoch(epochId).seedReferenceBlock, seedReferenceBlock);
    }

    function test_EpochSeedFinalizesWithLowRevealCountUsingReferenceEntropy() public {
        registry.setResolverPoolCap(2);
        uint256 firstIdentityId = _fundedResolverIdentity(alice, 100e18);
        uint256 secondIdentityId = _fundedResolverIdentity(bob, 100e18);
        uint64 epochId = registry.openResolverEpochRotation();

        vm.prank(alice);
        registry.optIntoResolverEpoch(_epochCommitment(epochId, firstIdentityId));
        vm.prank(bob);
        registry.optIntoResolverEpoch(_epochCommitment(epochId, secondIdentityId));

        vm.warp(block.timestamp + 1 days + 1);
        registry.closeResolverEpochRandomnessCommit(epochId);

        vm.prank(alice);
        registry.revealResolverEpochRandomness(epochId, _epochValue(firstIdentityId), _epochSalt(firstIdentityId));

        vm.roll(block.number + 2);
        vm.warp(block.timestamp + 1 days + 1);
        assertEq(registry.finalizeResolverEpochSeed(epochId), bytes32(0));
        vm.roll(block.number + 2);
        bytes32 seed = registry.finalizeResolverEpochSeed(epochId);

        assertGt(uint256(seed), 0);
        assertEq(registry.resolverEpoch(epochId).validRevealCount, 1);
    }

    function test_FinalizeEpochSelectionRejectsPartiallyScoredCandidateSet() public {
        registry.setResolverPoolCap(2);
        uint256 firstIdentityId = _fundedResolverIdentity(alice, 100e18);
        uint256 secondIdentityId = _fundedResolverIdentity(bob, 100e18);
        uint64 epochId = registry.openResolverEpochRotation();

        vm.prank(alice);
        registry.optIntoResolverEpoch(_epochCommitment(epochId, firstIdentityId));
        vm.prank(bob);
        registry.optIntoResolverEpoch(_epochCommitment(epochId, secondIdentityId));
        vm.warp(block.timestamp + 1 days + 1);
        registry.closeResolverEpochRandomnessCommit(epochId);
        vm.prank(alice);
        registry.revealResolverEpochRandomness(epochId, _epochValue(firstIdentityId), _epochSalt(firstIdentityId));
        vm.prank(bob);
        registry.revealResolverEpochRandomness(epochId, _epochValue(secondIdentityId), _epochSalt(secondIdentityId));
        vm.roll(block.number + 2);
        vm.warp(block.timestamp + 1 days + 1);
        assertEq(registry.finalizeResolverEpochSeed(epochId), bytes32(0));
        vm.roll(block.number + 2);
        registry.finalizeResolverEpochSeed(epochId);

        registry.submitResolverEpochCandidateScore(epochId, firstIdentityId);
        vm.warp(block.timestamp + 1 days + 1);

        vm.expectRevert(abi.encodeWithSelector(Errors.ResolverEpochUnderfilled.selector, epochId, 1, 2));
        registry.finalizeResolverEpochSelection(epochId);
    }

    function test_FinalizeEpochSelectionDoesNotScanAllCandidatesToRefillPrunedSelection() public {
        registry.setResolverPoolCap(1);
        uint256 firstIdentityId = _fundedResolverIdentity(alice, 100e18);
        uint256 secondIdentityId = _fundedResolverIdentity(bob, 100e18);
        uint64 epochId = registry.openResolverEpochRotation();

        vm.prank(alice);
        registry.optIntoResolverEpoch(_epochCommitment(epochId, firstIdentityId));
        vm.prank(bob);
        registry.optIntoResolverEpoch(_epochCommitment(epochId, secondIdentityId));

        vm.warp(block.timestamp + 1 days + 1);
        registry.closeResolverEpochRandomnessCommit(epochId);
        vm.prank(alice);
        registry.revealResolverEpochRandomness(epochId, _epochValue(firstIdentityId), _epochSalt(firstIdentityId));
        vm.prank(bob);
        registry.revealResolverEpochRandomness(epochId, _epochValue(secondIdentityId), _epochSalt(secondIdentityId));

        vm.roll(block.number + 2);
        vm.warp(block.timestamp + 1 days + 1);
        assertEq(registry.finalizeResolverEpochSeed(epochId), bytes32(0));
        vm.roll(block.number + 2);
        registry.finalizeResolverEpochSeed(epochId);

        uint256 firstScore = registry.submitResolverEpochCandidateScore(epochId, firstIdentityId);
        uint256 secondScore = registry.submitResolverEpochCandidateScore(epochId, secondIdentityId);
        uint256 selectedIdentityId = firstScore <= secondScore ? firstIdentityId : secondIdentityId;

        // Synthetic stake drift isolates the bounded-finalization branch: old finalization would scan all
        // scored candidates and refill with the non-selected resolver.
        registry.setRecordedStake(selectedIdentityId, 0);

        vm.warp(block.timestamp + 1 days + 1);
        vm.expectRevert(abi.encodeWithSelector(Errors.ResolverEpochUnderfilled.selector, epochId, 0, 1));
        registry.finalizeResolverEpochSelection(epochId);
    }

    function test_SlashedEpochCandidateCannotSubmitScoreOrActivate() public {
        uint256 identityId = _activateFundedResolver(alice, 100e18);

        vm.warp(block.timestamp + 151 days);
        uint64 epochId = registry.openResolverEpochRotation();
        vm.prank(alice);
        registry.optIntoResolverEpoch(_epochCommitment(epochId, identityId));
        vm.warp(block.timestamp + 1 days + 1);
        registry.closeResolverEpochRandomnessCommit(epochId);
        vm.prank(alice);
        registry.revealResolverEpochRandomness(epochId, _epochValue(identityId), _epochSalt(identityId));

        vm.roll(block.number + 2);
        vm.warp(block.timestamp + 1 days + 1);
        assertEq(registry.finalizeResolverEpochSeed(epochId), bytes32(0));
        vm.roll(block.number + 2);
        registry.finalizeResolverEpochSeed(epochId);

        vm.expectRevert(abi.encodeWithSelector(Errors.ResolverEpochCandidateIneligible.selector, epochId, identityId));
        registry.submitResolverEpochCandidateScore(epochId, identityId);
        assertLt(registry.recordedStake(identityId), 100e18);
    }

    function test_FullConfiguredEpochActivatesAllSelectedResolvers() public {
        registry.setResolverPoolCap(16);
        address[] memory owners = new address[](16);
        uint256[] memory identityIds = new uint256[](16);
        for (uint256 index; index < 16; ++index) {
            owners[index] = vm.addr(10_000 + index);
            identityIds[index] = _fundedResolverIdentity(owners[index], 100e18);
        }

        _finalizeCandidateEpoch(owners, identityIds);

        assertEq(registry.activeResolverCount(), 16);
        assertEq(registry.eligibleResolverCount(), 16);
        assertEq(registry.resolverEpoch(1).activeCount, 16);
    }

    function test_RequestResolverExitAllowsUnlockedStakedResolver() public {
        uint256 identityId = _mintResolverIdentity(alice);

        vm.prank(alice);
        registry.requestResolverExit();

        assertEq(registry.resolverLifecycleState(identityId), uint8(LibResolverJury.ResolverLifecycle.ExitCooldown));
    }

    function test_RequestResolverExitFromCandidateRevertsWhileSelectionPending() public {
        registry.setResolverTiming(1 days, 7 days);
        uint256 identityId = _fundedResolverIdentity(alice, 100e18);
        uint64 epochId = registry.openResolverEpochRotation();
        vm.prank(alice);
        registry.optIntoResolverEpoch(_epochCommitment(epochId, identityId));

        vm.expectRevert(abi.encodeWithSelector(Errors.StakeLocked.selector, identityId));
        vm.prank(alice);
        registry.requestResolverExit();

        assertEq(
            registry.resolverLifecycleState(identityId), uint8(LibResolverJury.ResolverLifecycle.ResolverCandidate)
        );
        assertEq(registry.currentResolverEpoch(), 0);
        assertFalse(registry.isEligibleResolver(identityId, bytes32(0)));
    }

    function test_WithdrawResolverStakeReleasesAfterCooldown() public {
        registry.setResolverTiming(0, 7 days);
        uint256 identityId = _fundedResolverIdentity(alice, 100e18);

        vm.prank(alice);
        registry.requestResolverExit();

        vm.expectRevert(abi.encodeWithSelector(Errors.StakeLocked.selector, identityId));
        vm.prank(alice);
        registry.withdrawResolverStake();

        vm.warp(block.timestamp + 7 days);

        vm.prank(alice);
        registry.withdrawResolverStake();

        assertEq(registry.recordedStake(identityId), 0);
        assertEq(registry.resolverLifecycleState(identityId), uint8(LibResolverJury.ResolverLifecycle.Exited));
        assertEq(eveToken.balanceOf(alice), 100e18);
        assertEq(eveToken.balanceOf(address(registry)), 0);
        assertEq(bondToken.balanceOf(address(registry)), 0);
    }

    function test_HasConflictExcludesMarketCreator() public {
        uint256 identityId = _fundedResolverIdentity(alice, 100e18);
        bytes32 marketId = keccak256("creator-conflict");
        registry.setMarketCreator(marketId, alice);

        assertTrue(registry.hasConflict(identityId, marketId));
    }

    function test_HasConflictExcludesDirectBinaryOutcomeHoldingsAboveThreshold() public {
        uint256 identityId = _fundedResolverIdentity(alice, 100e18);
        bytes32 marketId = keccak256("binary-holding-conflict");
        registry.setBinaryMarket(marketId, uint8(LibEveMarket.MarketType.CLOB), address(positions), 111, 222);

        registry.mintPosition(address(positions), alice, 111, 1e6);
        assertFalse(registry.hasConflict(identityId, marketId));

        registry.mintPosition(address(positions), alice, 111, 1);
        assertTrue(registry.hasConflict(identityId, marketId));
    }

    function test_HasConflictExcludesEscrowedBinaryAskInventoryAboveThreshold() public {
        uint256 identityId = _fundedResolverIdentity(alice, 100e18);
        bytes32 marketId = keccak256("binary-escrow-conflict");
        registry.setBinaryMarket(marketId, uint8(LibEveMarket.MarketType.CLOB), address(positions), 111, 222);

        registry.seedBinaryCurveInventory(marketId, true, alice, 1, uint8(LibEveMarket.CurveSide.BID), 1e6 + 1);
        assertFalse(registry.hasConflict(identityId, marketId));

        registry.seedBinaryCurveInventory(marketId, true, alice, 2, uint8(LibEveMarket.CurveSide.ASK), 1e6);
        assertFalse(registry.hasConflict(identityId, marketId));

        registry.seedBinaryCurveInventory(marketId, true, alice, 3, uint8(LibEveMarket.CurveSide.ASK), 1);
        assertTrue(registry.hasConflict(identityId, marketId));
    }

    function test_HasConflictExcludesDirectParimutuelOutcomeHoldingsAboveThreshold() public {
        uint256 identityId = _fundedResolverIdentity(alice, 100e18);
        bytes32 marketId = keccak256("parimutuel-holding-conflict");
        registry.setBinaryMarket(marketId, uint8(LibEveMarket.MarketType.PARIMUTUEL), address(positions), 333, 444);

        registry.mintPosition(address(positions), alice, 444, 1e6 + 1);

        assertTrue(registry.hasConflict(identityId, marketId));
    }

    function test_HasConflictExcludesDirectMultiOutcomeHoldingsAboveThreshold() public {
        uint256 identityId = _fundedResolverIdentity(alice, 100e18);
        bytes32 marketId = keccak256("multi-holding-conflict");
        registry.setMultiOutcomeMarket(marketId, address(positions), 3);

        registry.mintPosition(address(positions), alice, 2, 1e6 + 1);

        assertTrue(registry.hasConflict(identityId, marketId));
    }

    function test_HasConflictExcludesEscrowedMultiOutcomeAskInventoryAboveThreshold() public {
        uint256 identityId = _fundedResolverIdentity(alice, 100e18);
        bytes32 marketId = keccak256("multi-escrow-conflict");
        registry.setMultiOutcomeMarket(marketId, address(positions), 3);

        registry.seedMultiOutcomeCurveInventory(marketId, 1, alice, 4, uint8(LibEveMarket.CurveSide.ASK), 1e6 + 1);

        assertTrue(registry.hasConflict(identityId, marketId));
    }

    function test_HasConflictDoesNotExcludeUndeterminableHolding() public {
        uint256 identityId = _fundedResolverIdentity(alice, 100e18);
        bytes32 marketId = keccak256("undeterminable-conflict");
        registry.setMarketCreator(marketId, bob);

        assertFalse(registry.hasConflict(identityId, marketId));
    }

    function test_HasConflictIgnoresPositionDustWhenThresholdDisabled() public {
        uint256 identityId = _fundedResolverIdentity(alice, 100e18);
        bytes32 marketId = keccak256("disabled-threshold-conflict");
        registry.setConflictPositionThreshold(0);
        registry.setBinaryMarket(marketId, uint8(LibEveMarket.MarketType.CLOB), address(positions), 111, 222);
        registry.mintPosition(address(positions), alice, 111, 10e6);

        assertFalse(registry.hasConflict(identityId, marketId));
    }

    function test_ApplyFinalityReputationUpdatesCreatorAndResolversOnce() public {
        uint256 creatorIdentityId = _mintIdentity(alice);
        uint256 agreeingResolverId = _mintResolverIdentity(bob);
        uint256 dissentingResolverId = _mintResolverIdentity(carol);
        bytes32 marketId = keccak256("finality-reputation-market");
        bytes32 disputeId = keccak256("finality-reputation-dispute");

        uint256[] memory selected = new uint256[](2);
        selected[0] = agreeingResolverId;
        selected[1] = dissentingResolverId;
        uint256[] memory outcomes = new uint256[](2);
        outcomes[0] = uint8(LibEveMarket.MarketOutcome.No);
        outcomes[1] = uint8(LibEveMarket.MarketOutcome.Yes);
        registry.seedFinalityReputation(
            disputeId, marketId, alice, uint8(LibEveMarket.MarketOutcome.Yes), 0, selected, outcomes
        );

        registry.applyFinality(disputeId, uint8(LibEveMarket.MarketOutcome.No));

        IResolverRegistryFacet.CreatorReputationView memory creatorRep = registry.creatorReputation(creatorIdentityId);
        assertEq(creatorRep.marketsResolved, 1);
        assertEq(creatorRep.outcomesUpheld, 0);
        assertEq(creatorRep.outcomesOverturned, 1);

        IResolverRegistryFacet.ResolverReputationView memory agreeingRep =
            registry.resolverReputation(agreeingResolverId);
        IResolverRegistryFacet.ResolverReputationView memory dissentingRep =
            registry.resolverReputation(dissentingResolverId);
        assertEq(agreeingRep.finalAgreementCount, 1);
        assertEq(dissentingRep.finalAgreementCount, 0);

        registry.applyFinality(disputeId, uint8(LibEveMarket.MarketOutcome.No));

        creatorRep = registry.creatorReputation(creatorIdentityId);
        agreeingRep = registry.resolverReputation(agreeingResolverId);
        assertEq(creatorRep.marketsResolved, 1);
        assertEq(creatorRep.outcomesOverturned, 1);
        assertEq(agreeingRep.finalAgreementCount, 1);
    }

    function _mintIdentity(address owner) internal returns (uint256 identityId) {
        feeToken.mint(owner, 25e6);

        vm.prank(owner);
        feeToken.approve(address(registry), 25e6);

        vm.prank(owner);
        identityId = registry.mintIdentity();
    }

    function _mintResolverIdentity(address owner) internal returns (uint256 identityId) {
        identityId = _mintIdentity(owner);

        vm.prank(owner);
        registry.setResolverRole(true);
    }

    function _fundedResolverIdentity(address owner, uint256 stakeAmount) internal returns (uint256 identityId) {
        identityId = _mintResolverIdentity(owner);
        eveToken.mint(owner, stakeAmount);

        vm.prank(owner);
        eveToken.approve(address(registry), stakeAmount);

        vm.prank(owner);
        registry.depositResolverStake(stakeAmount);
    }

    function _activateFundedResolver(address owner, uint256 stakeAmount) internal returns (uint256 identityId) {
        identityId = _fundedResolverIdentity(owner, stakeAmount);
        _finalizeSingleCandidateEpoch(owner, identityId);
    }

    function _finalizeSingleCandidateEpoch(address owner, uint256 identityId) internal {
        registry.setResolverPoolCap(1);
        address[] memory owners = new address[](1);
        owners[0] = owner;
        uint256[] memory identityIds = new uint256[](1);
        identityIds[0] = identityId;
        _finalizeCandidateEpoch(owners, identityIds);
    }

    function _finalizeCandidateEpoch(address[] memory owners, uint256[] memory identityIds) internal {
        uint64 epochId = registry.openResolverEpochRotation();
        for (uint256 index; index < owners.length; ++index) {
            uint256 identityId = identityIds[index];
            vm.prank(owners[index]);
            registry.optIntoResolverEpoch(_epochCommitment(epochId, identityId));
        }

        vm.warp(block.timestamp + 1 days + 1);
        registry.closeResolverEpochRandomnessCommit(epochId);

        for (uint256 index; index < owners.length; ++index) {
            uint256 identityId = identityIds[index];
            vm.prank(owners[index]);
            registry.revealResolverEpochRandomness(epochId, _epochValue(identityId), _epochSalt(identityId));
        }

        vm.roll(block.number + 2);
        vm.warp(block.timestamp + 1 days + 1);
        assertEq(registry.finalizeResolverEpochSeed(epochId), bytes32(0));
        vm.roll(block.number + 2);
        registry.finalizeResolverEpochSeed(epochId);

        for (uint256 index; index < identityIds.length; ++index) {
            registry.submitResolverEpochCandidateScore(epochId, identityIds[index]);
        }

        vm.warp(block.timestamp + 1 days + 1);
        registry.finalizeResolverEpochSelection(epochId);
    }

    function _epochCommitment(uint64 epochId, uint256 identityId) internal pure returns (bytes32) {
        return keccak256(abi.encode(epochId, identityId, _epochValue(identityId), _epochSalt(identityId)));
    }

    function _epochValue(uint256 identityId) internal pure returns (bytes32) {
        return keccak256(abi.encode("epoch-value", identityId));
    }

    function _epochSalt(uint256 identityId) internal pure returns (bytes32) {
        return keccak256(abi.encode("epoch-salt", identityId));
    }
}
