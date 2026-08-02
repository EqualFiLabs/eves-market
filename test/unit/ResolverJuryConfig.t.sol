// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "../../lib/forge-std/src/Test.sol";

import {Errors} from "src/libraries/Errors.sol";
import {Events} from "src/libraries/Events.sol";
import {OwnershipFacet} from "src/facets/OwnershipFacet.sol";
import {LibDiamond} from "src/libraries/LibDiamond.sol";
import {LibEveMarket} from "src/libraries/LibEveMarket.sol";
import {LibResolverJury} from "src/libraries/LibResolverJury.sol";
import {OwnershipConfigTypes} from "src/types/OwnershipConfigTypes.sol";
import {MockEveToken} from "test/helpers/MockEveToken.sol";

contract ResolverJuryConfigHarness is OwnershipFacet {
    function setOwner(address owner_) external {
        LibDiamond.setContractOwner(owner_);
    }

    function setExistingConfig(address conditionalTokens, address eveToken, uint128 comboMarketCreationFee) external {
        LibEveMarket.MarketConfig storage config = LibEveMarket.store().config;
        config.defaultConditionalTokens = conditionalTokens;
        config.eveToken = eveToken;
        config.comboMarketCreationFee = comboMarketCreationFee;
    }

    function setResolverJuryConfig(
        address mintFeeToken,
        uint256 mintFee,
        uint256 stakeRequirement,
        uint256 stakeCap,
        uint256 poolCap
    ) external {
        if (
            mintFee > type(uint128).max || stakeRequirement > type(uint128).max || stakeCap > type(uint128).max
                || poolCap > type(uint16).max
        ) {
            revert Errors.InvalidConfigValue("resolverJuryConfig");
        }

        LibEveMarket.ResolverJuryConfig storage config = LibEveMarket.store().config.resolverJuryConfig;
        config.identityMintFeeToken = mintFeeToken;
        config.identityMintFee = uint128(mintFee);
        config.resolverStakeRequirement = uint128(stakeRequirement);
        config.resolverStakeCap = uint128(stakeCap);
        config.resolverPoolCap = uint16(poolCap);
        config.activationDelay = 1 days;
        config.exitCooldown = 7 days;
        config.participationThresholdBps = 8_000;
        config.concurrencyLimit = 3;
        config.participationGraceCount = 5;
        config.conflictPositionThreshold = 1e6;
        delete config.committeeSizesByRound;
        config.committeeSizesByRound.push(3);
        config.committeeSizesByRound.push(5);
        config.maxAppealRounds = 1;
        config.appealBondMultiplierBps = 20_000;
        config.randomnessCommitDuration = 1 hours;
        config.randomnessRevealDuration = 1 hours;
        config.commitDuration = 2 hours;
        config.revealDuration = 2 hours;
        config.appealWindow = 1 days;
        config.randomnessTimeout = 5 minutes;
        config.quorum = 2;
        config.redrawLimit = 1;
        config.lowQuorumMode = LibEveMarket.LowQuorumMode.Redraw;
        config.tieBreakMode = LibEveMarket.TieBreakMode.Escalate;
        config.randomnessFailureMode = LibEveMarket.RandomnessFailureMode.Retry;
        config.minRandomnessReveals = 2;
        config.allEligibleFallbackCap = 10;
        config.missedCommitSlashBps = 500;
        config.missedRevealSlashBps = 700;
        config.invalidRevealSlashBps = 1_000;
        config.slashCooldown = 14 days;
        config.protocolFeeAllocationBps = 250;
        config.appealSuccessRoutingBps = [uint16(7_000), 1_000, 1_000, 1_000];
        config.appealFailureRoutingBps = [uint16(4_000), 3_000, 3_000];
        config.incentiveSelectCommittee = 1e18;
        config.incentiveCloseCommit = 2e18;
        config.incentiveCloseReveal = 3e18;
        config.incentiveOpenAppeal = 4e18;
        config.incentiveFinalize = 5e18;
        config.incentiveRandomness = 6e18;
    }

    function existingConfig()
        external
        view
        returns (address conditionalTokens, address eveToken, uint128 comboMarketCreationFee)
    {
        LibEveMarket.MarketConfig storage config = LibEveMarket.store().config;
        return (config.defaultConditionalTokens, config.eveToken, config.comboMarketCreationFee);
    }

    function resolverJuryIdentityConfigSample()
        external
        view
        returns (address mintFeeToken, uint128 mintFee, uint128 stakeRequirement, uint128 stakeCap, uint16 poolCap)
    {
        LibEveMarket.ResolverJuryConfig storage config = LibEveMarket.store().config.resolverJuryConfig;
        return (
            config.identityMintFeeToken,
            config.identityMintFee,
            config.resolverStakeRequirement,
            config.resolverStakeCap,
            config.resolverPoolCap
        );
    }

    function resolverJuryPoolConfigSample()
        external
        view
        returns (
            uint16 poolCap,
            uint64 activationDelay,
            uint64 exitCooldown,
            uint16 participationThresholdBps,
            uint16 concurrencyLimit
        )
    {
        LibEveMarket.ResolverJuryConfig storage config = LibEveMarket.store().config.resolverJuryConfig;
        return (
            config.resolverPoolCap,
            config.activationDelay,
            config.exitCooldown,
            config.participationThresholdBps,
            config.concurrencyLimit
        );
    }

    function resolverJuryEconomicsConfigSample()
        external
        view
        returns (
            uint16 missedCommitSlashBps,
            uint16 missedRevealSlashBps,
            uint16 invalidRevealSlashBps,
            uint16 protocolFeeAllocationBps,
            uint128 incentiveRandomness
        )
    {
        LibEveMarket.ResolverJuryConfig storage config = LibEveMarket.store().config.resolverJuryConfig;
        return (
            config.missedCommitSlashBps,
            config.missedRevealSlashBps,
            config.invalidRevealSlashBps,
            config.protocolFeeAllocationBps,
            config.incentiveRandomness
        );
    }

    function resolverJuryRoundConfigSample()
        external
        view
        returns (
            uint16 firstCommitteeSize,
            uint16 secondCommitteeSize,
            uint8 lowQuorumMode,
            uint8 tieBreakMode,
            uint8 randomnessFailureMode,
            uint128 incentiveFinalize
        )
    {
        LibEveMarket.ResolverJuryConfig storage config = LibEveMarket.store().config.resolverJuryConfig;
        return (
            config.committeeSizesByRound[0],
            config.committeeSizesByRound[1],
            uint8(config.lowQuorumMode),
            uint8(config.tieBreakMode),
            uint8(config.randomnessFailureMode),
            config.incentiveFinalize
        );
    }

    function setResolverJuryStorage(address eveIdentity, uint256 identityId, uint256 stake) external {
        if (stake > type(uint128).max) {
            revert Errors.InvalidAmount(stake);
        }

        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        jury.eveIdentity = eveIdentity;
        jury.identityByOwner[msg.sender] = identityId;
        jury.identities[identityId].resolverStake = uint128(stake);
        jury.identities[identityId].lifecycle = LibResolverJury.ResolverLifecycle.ResolverActive;
        jury.activeResolverSet.push(identityId);
        jury.activeResolverIndex[identityId] = jury.activeResolverSet.length;
    }

    function resolverJuryStorageSample(address owner, uint256 identityId)
        external
        view
        returns (address eveIdentity, uint256 ownerIdentityId, uint128 stake, uint8 lifecycle, uint256 activeCount)
    {
        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        return (
            jury.eveIdentity,
            jury.identityByOwner[owner],
            jury.identities[identityId].resolverStake,
            uint8(jury.identities[identityId].lifecycle),
            jury.activeResolverSet.length
        );
    }

    function resolverJurySlot() external pure returns (bytes32) {
        return bytes32(uint256(keccak256("eve.resolver.identity.jury.storage")) - 1);
    }

    function eveMarketSlot() external pure returns (bytes32) {
        return bytes32(uint256(keccak256("eve.prediction.market.storage")) - 1);
    }

    function revertInvalidCommitteeSize() external pure {
        revert Errors.InvalidCommitteeSize(2);
    }

    function emitConfigUpdated(bytes32 paramName, uint256 priorValue, uint256 newValue) external {
        emit Events.ConfigUpdated(paramName, priorValue, newValue);
    }
}

contract ResolverJuryConfigTest is Test {
    ResolverJuryConfigHarness internal harness;
    MockEveToken internal mintFeeToken;

    function setUp() public {
        harness = new ResolverJuryConfigHarness();
        mintFeeToken = new MockEveToken();
        harness.setOwner(address(this));
    }

    function test_ResolverJuryStorageUsesDedicatedSlot() public {
        address conditionalTokens = address(0xCA11);
        address eveToken = address(0xE000);
        address eveIdentity = address(0x1D);
        uint256 identityId = 17;
        uint128 stake = 100 ether;

        harness.setExistingConfig(conditionalTokens, eveToken, 123);
        harness.setResolverJuryStorage(eveIdentity, identityId, stake);

        bytes32 jurySlot = harness.resolverJurySlot();
        bytes32 marketSlot = harness.eveMarketSlot();

        assertNotEq(jurySlot, marketSlot);
        assertEq(address(uint160(uint256(vm.load(address(harness), marketSlot)))), conditionalTokens);
        assertEq(address(uint160(uint256(vm.load(address(harness), bytes32(uint256(jurySlot) + 8))))), eveIdentity);

        (address storedIdentity, uint256 ownerIdentityId, uint128 storedStake, uint8 lifecycle, uint256 activeCount) =
            harness.resolverJuryStorageSample(address(this), identityId);

        assertEq(storedIdentity, eveIdentity);
        assertEq(ownerIdentityId, identityId);
        assertEq(storedStake, stake);
        assertEq(lifecycle, uint8(LibResolverJury.ResolverLifecycle.ResolverActive));
        assertEq(activeCount, 1);
    }

    function test_AppendedResolverJuryConfigPreservesExistingConfig() public {
        address conditionalTokens = address(0xCA11);
        address eveToken = address(0xE000);
        address legacyMintFeeToken = address(0xFEE);

        harness.setExistingConfig(conditionalTokens, eveToken, 999);
        harness.setResolverJuryConfig(legacyMintFeeToken, 10e18, 100e18, 250e18, 50);

        (address storedConditionalTokens, address storedEveToken, uint128 comboMarketCreationFee) =
            harness.existingConfig();

        assertEq(storedConditionalTokens, conditionalTokens);
        assertEq(storedEveToken, eveToken);
        assertEq(comboMarketCreationFee, 999);

        (address storedMintFeeToken, uint128 mintFee, uint128 stakeRequirement, uint128 stakeCap, uint16 poolCap) =
            harness.resolverJuryIdentityConfigSample();

        assertEq(storedMintFeeToken, legacyMintFeeToken);
        assertEq(mintFee, 10e18);
        assertEq(stakeRequirement, 100e18);
        assertEq(stakeCap, 250e18);
        assertEq(poolCap, 50);

        (
            uint16 firstCommitteeSize,
            uint16 secondCommitteeSize,
            uint8 lowQuorumMode,
            uint8 tieBreakMode,
            uint8 randomnessFailureMode,
            uint128 incentiveFinalize
        ) = harness.resolverJuryRoundConfigSample();

        assertEq(firstCommitteeSize, 3);
        assertEq(secondCommitteeSize, 5);
        assertEq(lowQuorumMode, uint8(LibEveMarket.LowQuorumMode.Redraw));
        assertEq(tieBreakMode, uint8(LibEveMarket.TieBreakMode.Escalate));
        assertEq(randomnessFailureMode, uint8(LibEveMarket.RandomnessFailureMode.Retry));
        assertEq(incentiveFinalize, 5e18);
    }

    function test_ResolverJuryErrorsAndEventsAreReachable() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidCommitteeSize.selector, uint16(2)));
        harness.revertInvalidCommitteeSize();

        vm.expectEmit(false, false, false, true);
        emit Events.ConfigUpdated("resolverPoolCap", 10, 50);
        harness.emitConfigUpdated("resolverPoolCap", 10, 50);
    }

    function test_OwnerCanSetResolverJuryConfigWithEvents() public {
        vm.expectEmit(false, false, false, true);
        emit Events.ConfigUpdated("identityMintFee", 0, 10e18);
        harness.setResolverJuryIdentitySettings(
            OwnershipConfigTypes.ResolverJuryIdentitySettings({
                identityMintFeeToken: address(mintFeeToken),
                identityMintFee: 10e18,
                resolverStakeRequirement: 100e18,
                resolverStakeCap: 250e18
            })
        );

        vm.expectEmit(false, false, false, true);
        emit Events.ConfigUpdated("resolverPoolCap", 0, 50);
        harness.setResolverJuryPoolSettings(
            OwnershipConfigTypes.ResolverJuryPoolSettings({
                resolverPoolCap: 50,
                activationDelay: 1 days,
                exitCooldown: 7 days,
                participationThresholdBps: 8_000,
                concurrencyLimit: 3,
                participationGraceCount: 5,
                conflictPositionThreshold: 1e6
            })
        );

        uint16[] memory committeeSizes = new uint16[](3);
        committeeSizes[0] = 3;
        committeeSizes[1] = 5;
        committeeSizes[2] = 7;
        vm.expectEmit(false, false, false, true);
        emit Events.ConfigUpdated(
            "committeeSizesHash",
            uint256(keccak256(abi.encode(new uint16[](0)))),
            uint256(keccak256(abi.encode(committeeSizes)))
        );
        harness.setResolverJuryRoundSettings(
            OwnershipConfigTypes.ResolverJuryRoundSettings({
                committeeSizesByRound: committeeSizes,
                maxAppealRounds: 2,
                appealBondMultiplierBps: 20_000,
                randomnessCommitDuration: 1 hours,
                randomnessRevealDuration: 1 hours,
                commitDuration: 2 hours,
                revealDuration: 2 hours,
                appealWindow: 1 days,
                randomnessTimeout: 5 minutes,
                quorum: 2,
                redrawLimit: 1,
                lowQuorumMode: LibEveMarket.LowQuorumMode.Redraw,
                tieBreakMode: LibEveMarket.TieBreakMode.Escalate,
                randomnessFailureMode: LibEveMarket.RandomnessFailureMode.Retry,
                minRandomnessReveals: 2,
                allEligibleFallbackCap: 10
            })
        );

        vm.expectEmit(false, false, false, true);
        emit Events.ConfigUpdated("missedCommitSlashBps", 0, 500);
        harness.setResolverJuryEconomicsSettings(
            OwnershipConfigTypes.ResolverJuryEconomicsSettings({
                missedCommitSlashBps: 500,
                missedRevealSlashBps: 700,
                invalidRevealSlashBps: 1_000,
                slashCooldown: 14 days,
                protocolFeeAllocationBps: 250,
                appealSuccessRoutingBps: [uint16(7_000), 1_000, 1_000, 1_000],
                appealFailureRoutingBps: [uint16(4_000), 3_000, 3_000],
                incentiveSelectCommittee: 1e18,
                incentiveCloseCommit: 2e18,
                incentiveCloseReveal: 3e18,
                incentiveOpenAppeal: 4e18,
                incentiveFinalize: 5e18,
                incentiveRandomness: 6e18
            })
        );

        (address storedMintFeeToken, uint128 mintFee, uint128 stakeRequirement, uint128 stakeCap, uint16 poolCap) =
            harness.resolverJuryIdentityConfigSample();
        assertEq(storedMintFeeToken, address(mintFeeToken));
        assertEq(mintFee, 10e18);
        assertEq(stakeRequirement, 100e18);
        assertEq(stakeCap, 250e18);
        assertEq(poolCap, 50);

        (
            uint16 storedPoolCap,
            uint64 activationDelay,
            uint64 exitCooldown,
            uint16 participationThresholdBps,
            uint16 concurrencyLimit
        ) = harness.resolverJuryPoolConfigSample();
        assertEq(storedPoolCap, 50);
        assertEq(activationDelay, 1 days);
        assertEq(exitCooldown, 7 days);
        assertEq(participationThresholdBps, 8_000);
        assertEq(concurrencyLimit, 3);

        (
            uint16 firstCommitteeSize,
            uint16 secondCommitteeSize,
            uint8 lowQuorumMode,
            uint8 tieBreakMode,
            uint8 randomnessFailureMode,
            uint128 incentiveFinalize
        ) = harness.resolverJuryRoundConfigSample();
        assertEq(firstCommitteeSize, 3);
        assertEq(secondCommitteeSize, 5);
        assertEq(lowQuorumMode, uint8(LibEveMarket.LowQuorumMode.Redraw));
        assertEq(tieBreakMode, uint8(LibEveMarket.TieBreakMode.Escalate));
        assertEq(randomnessFailureMode, uint8(LibEveMarket.RandomnessFailureMode.Retry));
        assertEq(incentiveFinalize, 5e18);

        (
            uint16 missedCommitSlashBps,
            uint16 missedRevealSlashBps,
            uint16 invalidRevealSlashBps,
            uint16 protocolFeeAllocationBps,
            uint128 incentiveRandomness
        ) = harness.resolverJuryEconomicsConfigSample();
        assertEq(missedCommitSlashBps, 500);
        assertEq(missedRevealSlashBps, 700);
        assertEq(invalidRevealSlashBps, 1_000);
        assertEq(protocolFeeAllocationBps, 250);
        assertEq(incentiveRandomness, 6e18);
    }

    function test_RevertWhen_NonOwnerSetsResolverJuryConfig() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert(abi.encodeWithSelector(Errors.NotContractOwner.selector, address(0xBEEF)));
        harness.setResolverJuryPoolSettings(
            OwnershipConfigTypes.ResolverJuryPoolSettings({
                resolverPoolCap: 50,
                activationDelay: 0,
                exitCooldown: 0,
                participationThresholdBps: 0,
                concurrencyLimit: 1,
                participationGraceCount: 0,
                conflictPositionThreshold: 0
            })
        );
    }

    function test_RevertWhen_InvalidResolverJuryConfigBounds() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidConfigValue.selector, bytes32("resolverStakeCap")));
        harness.setResolverJuryIdentitySettings(
            OwnershipConfigTypes.ResolverJuryIdentitySettings({
                identityMintFeeToken: address(mintFeeToken),
                identityMintFee: 10e18,
                resolverStakeRequirement: 250e18,
                resolverStakeCap: 100e18
            })
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidConfigValue.selector, bytes32("resolverPoolCap")));
        harness.setResolverJuryPoolSettings(
            OwnershipConfigTypes.ResolverJuryPoolSettings({
                resolverPoolCap: 0,
                activationDelay: 0,
                exitCooldown: 0,
                participationThresholdBps: 0,
                concurrencyLimit: 1,
                participationGraceCount: 0,
                conflictPositionThreshold: 0
            })
        );

        harness.setResolverJuryPoolSettings(
            OwnershipConfigTypes.ResolverJuryPoolSettings({
                resolverPoolCap: 5,
                activationDelay: 0,
                exitCooldown: 0,
                participationThresholdBps: 0,
                concurrencyLimit: 1,
                participationGraceCount: 0,
                conflictPositionThreshold: 0
            })
        );

        uint16[] memory evenCommitteeSizes = new uint16[](2);
        evenCommitteeSizes[0] = 2;
        evenCommitteeSizes[1] = 5;
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidCommitteeSize.selector, uint16(2)));
        harness.setResolverJuryRoundSettings(_validRoundSettings(evenCommitteeSizes, 1));

        uint16[] memory tooManyReveals = new uint16[](2);
        tooManyReveals[0] = 3;
        tooManyReveals[1] = 5;
        OwnershipConfigTypes.ResolverJuryRoundSettings memory roundSettings = _validRoundSettings(tooManyReveals, 1);
        roundSettings.minRandomnessReveals = 6;
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidConfigValue.selector, bytes32("minRandomnessReveals")));
        harness.setResolverJuryRoundSettings(roundSettings);

        roundSettings = _validRoundSettings(tooManyReveals, 1);
        roundSettings.commitDuration = 30 minutes;
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidConfigValue.selector, bytes32("commitDuration")));
        harness.setResolverJuryRoundSettings(roundSettings);

        OwnershipConfigTypes.ResolverJuryEconomicsSettings memory economicsSettings = _validEconomicsSettings();
        economicsSettings.appealSuccessRoutingBps = [uint16(7_001), 1_000, 1_000, 1_000];
        vm.expectRevert(Errors.InvalidRoutingSplit.selector);
        harness.setResolverJuryEconomicsSettings(economicsSettings);
    }

    function _validRoundSettings(uint16[] memory committeeSizes, uint8 maxAppealRounds)
        internal
        pure
        returns (OwnershipConfigTypes.ResolverJuryRoundSettings memory settings)
    {
        settings = OwnershipConfigTypes.ResolverJuryRoundSettings({
            committeeSizesByRound: committeeSizes,
            maxAppealRounds: maxAppealRounds,
            appealBondMultiplierBps: 20_000,
            randomnessCommitDuration: 1 hours,
            randomnessRevealDuration: 1 hours,
            commitDuration: 2 hours,
            revealDuration: 2 hours,
            appealWindow: 1 days,
            randomnessTimeout: 5 minutes,
            quorum: 2,
            redrawLimit: 1,
            lowQuorumMode: LibEveMarket.LowQuorumMode.Redraw,
            tieBreakMode: LibEveMarket.TieBreakMode.Escalate,
            randomnessFailureMode: LibEveMarket.RandomnessFailureMode.Retry,
            minRandomnessReveals: 2,
            allEligibleFallbackCap: 5
        });
    }

    function _validEconomicsSettings()
        internal
        pure
        returns (OwnershipConfigTypes.ResolverJuryEconomicsSettings memory settings)
    {
        settings = OwnershipConfigTypes.ResolverJuryEconomicsSettings({
            missedCommitSlashBps: 500,
            missedRevealSlashBps: 700,
            invalidRevealSlashBps: 1_000,
            slashCooldown: 14 days,
            protocolFeeAllocationBps: 250,
            appealSuccessRoutingBps: [uint16(7_000), 1_000, 1_000, 1_000],
            appealFailureRoutingBps: [uint16(4_000), 3_000, 3_000],
            incentiveSelectCommittee: 1e18,
            incentiveCloseCommit: 2e18,
            incentiveCloseReveal: 3e18,
            incentiveOpenAppeal: 4e18,
            incentiveFinalize: 5e18,
            incentiveRandomness: 6e18
        });
    }
}
