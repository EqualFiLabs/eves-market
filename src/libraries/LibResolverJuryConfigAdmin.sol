// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Errors} from "./Errors.sol";
import {LibAdminConfig} from "./LibAdminConfig.sol";
import {LibEveMarket} from "./LibEveMarket.sol";
import {OwnershipConfigTypes} from "../types/OwnershipConfigTypes.sol";

library LibResolverJuryConfigAdmin {
    uint64 internal constant MAX_RESOLVER_ACTIVATION_DELAY = 30 days;
    uint64 internal constant MAX_RESOLVER_EXIT_COOLDOWN = 90 days;
    uint64 internal constant MIN_RESOLVER_EPOCH_DURATION = 30 days;
    uint64 internal constant MAX_RESOLVER_EPOCH_DURATION = 730 days;
    uint64 internal constant MIN_RESOLVER_ROTATION_WINDOW = 1 days;
    uint64 internal constant MAX_RESOLVER_ROTATION_WINDOW = 90 days;
    uint64 internal constant MIN_RESOLVER_EPOCH_PHASE_DURATION = 1 hours;
    uint64 internal constant MAX_RESOLVER_EPOCH_PHASE_DURATION = 30 days;
    uint64 internal constant MIN_RESOLVER_PHASE_DURATION = 1 hours;
    uint64 internal constant MAX_RESOLVER_PHASE_DURATION = 7 days;
    uint64 internal constant MIN_RANDOMNESS_TIMEOUT = 60;
    uint64 internal constant MAX_RANDOMNESS_TIMEOUT = 1 days;

    function applyIdentitySettings(
        LibEveMarket.ResolverJuryConfig storage config,
        OwnershipConfigTypes.ResolverJuryIdentitySettings calldata settings
    ) internal {
        if (settings.identityMintFee != 0) {
            LibAdminConfig.enforceERC20(settings.identityMintFeeToken);
        }
        if (settings.epochCandidateFeeAmount != 0) {
            LibAdminConfig.enforceERC20(settings.epochCandidateFeeToken);
        }
        if (settings.resolverSeatStake == 0) {
            revert Errors.InvalidConfigValue("resolverSeatStake");
        }

        LibAdminConfig.emitConfigUpdate("identityMintFee", config.identityMintFee, settings.identityMintFee);
        LibAdminConfig.emitConfigUpdateAddress(
            "identityMintFeeToken", config.identityMintFeeToken, settings.identityMintFeeToken
        );
        LibAdminConfig.emitConfigUpdate("resolverSeatStake", config.resolverSeatStake, settings.resolverSeatStake);
        LibAdminConfig.emitConfigUpdateAddress(
            "epochCandidateFeeToken", config.epochCandidateFeeToken, settings.epochCandidateFeeToken
        );
        LibAdminConfig.emitConfigUpdate(
            "epochCandidateFeeAmount", config.epochCandidateFeeAmount, settings.epochCandidateFeeAmount
        );

        config.identityMintFeeToken = settings.identityMintFeeToken;
        config.identityMintFee = settings.identityMintFee;
        config.resolverSeatStake = settings.resolverSeatStake;
        config.epochCandidateFeeToken = settings.epochCandidateFeeToken;
        config.epochCandidateFeeAmount = settings.epochCandidateFeeAmount;
    }

    function applyPoolSettings(
        LibEveMarket.ResolverJuryConfig storage config,
        OwnershipConfigTypes.ResolverJuryPoolSettings calldata settings
    ) internal {
        enforcePoolSettings(settings);
        enforceExistingCommitteeSizes(config, settings.activeEpochSize);

        LibAdminConfig.emitConfigUpdate("activeEpochSize", config.activeEpochSize, settings.activeEpochSize);
        LibAdminConfig.emitConfigUpdate(
            "resolverEpochDuration", config.resolverEpochDuration, settings.resolverEpochDuration
        );
        LibAdminConfig.emitConfigUpdate(
            "resolverRotationWindow", config.resolverRotationWindow, settings.resolverRotationWindow
        );
        LibAdminConfig.emitConfigUpdate(
            "epochRandomnessCommitDuration",
            config.epochRandomnessCommitDuration,
            settings.epochRandomnessCommitDuration
        );
        LibAdminConfig.emitConfigUpdate(
            "epochRandomnessRevealDuration",
            config.epochRandomnessRevealDuration,
            settings.epochRandomnessRevealDuration
        );
        LibAdminConfig.emitConfigUpdate(
            "epochSelectionDuration", config.epochSelectionDuration, settings.epochSelectionDuration
        );
        LibAdminConfig.emitConfigUpdate(
            "minEpochRandomnessReveals", config.minEpochRandomnessReveals, settings.minEpochRandomnessReveals
        );
        LibAdminConfig.emitConfigUpdate("activationDelay", config.activationDelay, settings.activationDelay);
        LibAdminConfig.emitConfigUpdate("exitCooldown", config.exitCooldown, settings.exitCooldown);
        LibAdminConfig.emitConfigUpdate(
            "participationThresholdBps", config.participationThresholdBps, settings.participationThresholdBps
        );
        LibAdminConfig.emitConfigUpdate("concurrencyLimit", config.concurrencyLimit, settings.concurrencyLimit);
        LibAdminConfig.emitConfigUpdate(
            "participationGraceCount", config.participationGraceCount, settings.participationGraceCount
        );
        LibAdminConfig.emitConfigUpdate(
            "conflictPositionThreshold", config.conflictPositionThreshold, settings.conflictPositionThreshold
        );

        config.activeEpochSize = settings.activeEpochSize;
        config.resolverEpochDuration = settings.resolverEpochDuration;
        config.resolverRotationWindow = settings.resolverRotationWindow;
        config.epochRandomnessCommitDuration = settings.epochRandomnessCommitDuration;
        config.epochRandomnessRevealDuration = settings.epochRandomnessRevealDuration;
        config.epochSelectionDuration = settings.epochSelectionDuration;
        config.minEpochRandomnessReveals = settings.minEpochRandomnessReveals;
        config.activationDelay = settings.activationDelay;
        config.exitCooldown = settings.exitCooldown;
        config.participationThresholdBps = settings.participationThresholdBps;
        config.concurrencyLimit = settings.concurrencyLimit;
        config.participationGraceCount = settings.participationGraceCount;
        config.conflictPositionThreshold = settings.conflictPositionThreshold;
    }

    function applyRoundSettings(
        LibEveMarket.ResolverJuryConfig storage config,
        OwnershipConfigTypes.ResolverJuryRoundSettings calldata settings
    ) internal {
        enforceRoundSettings(settings, config.activeEpochSize);

        LibAdminConfig.emitConfigUpdate(
            "committeeSizesHash",
            committeeSizesHash(config.committeeSizesByRound),
            uint256(keccak256(abi.encode(settings.committeeSizesByRound)))
        );
        LibAdminConfig.emitConfigUpdate("maxAppealRounds", config.maxAppealRounds, settings.maxAppealRounds);
        LibAdminConfig.emitConfigUpdate(
            "appealBondMultiplierBps", config.appealBondMultiplierBps, settings.appealBondMultiplierBps
        );
        LibAdminConfig.emitConfigUpdate(
            "randomnessCommitDuration", config.randomnessCommitDuration, settings.randomnessCommitDuration
        );
        LibAdminConfig.emitConfigUpdate(
            "randomnessRevealDuration", config.randomnessRevealDuration, settings.randomnessRevealDuration
        );
        LibAdminConfig.emitConfigUpdate("commitDuration", config.commitDuration, settings.commitDuration);
        LibAdminConfig.emitConfigUpdate("revealDuration", config.revealDuration, settings.revealDuration);
        LibAdminConfig.emitConfigUpdate("appealWindow", config.appealWindow, settings.appealWindow);
        LibAdminConfig.emitConfigUpdate("randomnessTimeout", config.randomnessTimeout, settings.randomnessTimeout);
        LibAdminConfig.emitConfigUpdate("quorum", config.quorum, settings.quorum);
        LibAdminConfig.emitConfigUpdate("redrawLimit", config.redrawLimit, settings.redrawLimit);
        LibAdminConfig.emitConfigUpdate("lowQuorumMode", uint8(config.lowQuorumMode), uint8(settings.lowQuorumMode));
        LibAdminConfig.emitConfigUpdate("tieBreakMode", uint8(config.tieBreakMode), uint8(settings.tieBreakMode));
        LibAdminConfig.emitConfigUpdate(
            "randomnessFailureMode", uint8(config.randomnessFailureMode), uint8(settings.randomnessFailureMode)
        );
        LibAdminConfig.emitConfigUpdate(
            "minRandomnessReveals", config.minRandomnessReveals, settings.minRandomnessReveals
        );
        LibAdminConfig.emitConfigUpdate(
            "allEligibleFallbackCap", config.allEligibleFallbackCap, settings.allEligibleFallbackCap
        );

        delete config.committeeSizesByRound;
        for (uint256 index; index < settings.committeeSizesByRound.length; ++index) {
            config.committeeSizesByRound.push(settings.committeeSizesByRound[index]);
        }
        config.maxAppealRounds = settings.maxAppealRounds;
        config.appealBondMultiplierBps = settings.appealBondMultiplierBps;
        config.randomnessCommitDuration = settings.randomnessCommitDuration;
        config.randomnessRevealDuration = settings.randomnessRevealDuration;
        config.commitDuration = settings.commitDuration;
        config.revealDuration = settings.revealDuration;
        config.appealWindow = settings.appealWindow;
        config.randomnessTimeout = settings.randomnessTimeout;
        config.quorum = settings.quorum;
        config.redrawLimit = settings.redrawLimit;
        config.lowQuorumMode = settings.lowQuorumMode;
        config.tieBreakMode = settings.tieBreakMode;
        config.randomnessFailureMode = settings.randomnessFailureMode;
        config.minRandomnessReveals = settings.minRandomnessReveals;
        config.allEligibleFallbackCap = settings.allEligibleFallbackCap;
    }

    function applyEconomicsSettings(
        LibEveMarket.ResolverJuryConfig storage config,
        OwnershipConfigTypes.ResolverJuryEconomicsSettings calldata settings
    ) internal {
        enforceEconomicsSettings(settings);

        LibAdminConfig.emitConfigUpdate(
            "missedCommitSlashBps", config.missedCommitSlashBps, settings.missedCommitSlashBps
        );
        LibAdminConfig.emitConfigUpdate(
            "missedRevealSlashBps", config.missedRevealSlashBps, settings.missedRevealSlashBps
        );
        LibAdminConfig.emitConfigUpdate(
            "invalidRevealSlashBps", config.invalidRevealSlashBps, settings.invalidRevealSlashBps
        );
        LibAdminConfig.emitConfigUpdate("slashCooldown", config.slashCooldown, settings.slashCooldown);
        LibAdminConfig.emitConfigUpdate(
            "protocolFeeAllocationBps", config.protocolFeeAllocationBps, settings.protocolFeeAllocationBps
        );
        LibAdminConfig.emitConfigUpdate(
            "appealSuccessRoutingHash",
            routingHash4(config.appealSuccessRoutingBps),
            routingHash4(settings.appealSuccessRoutingBps)
        );
        LibAdminConfig.emitConfigUpdate(
            "appealFailureRoutingHash",
            routingHash3(config.appealFailureRoutingBps),
            routingHash3(settings.appealFailureRoutingBps)
        );
        LibAdminConfig.emitConfigUpdate(
            "incentiveSelectCommittee", config.incentiveSelectCommittee, settings.incentiveSelectCommittee
        );
        LibAdminConfig.emitConfigUpdate(
            "incentiveCloseCommit", config.incentiveCloseCommit, settings.incentiveCloseCommit
        );
        LibAdminConfig.emitConfigUpdate(
            "incentiveCloseReveal", config.incentiveCloseReveal, settings.incentiveCloseReveal
        );
        LibAdminConfig.emitConfigUpdate("incentiveOpenAppeal", config.incentiveOpenAppeal, settings.incentiveOpenAppeal);
        LibAdminConfig.emitConfigUpdate("incentiveFinalize", config.incentiveFinalize, settings.incentiveFinalize);
        LibAdminConfig.emitConfigUpdate("incentiveRandomness", config.incentiveRandomness, settings.incentiveRandomness);

        config.missedCommitSlashBps = settings.missedCommitSlashBps;
        config.missedRevealSlashBps = settings.missedRevealSlashBps;
        config.invalidRevealSlashBps = settings.invalidRevealSlashBps;
        config.slashCooldown = settings.slashCooldown;
        config.protocolFeeAllocationBps = settings.protocolFeeAllocationBps;
        config.appealSuccessRoutingBps = settings.appealSuccessRoutingBps;
        config.appealFailureRoutingBps = settings.appealFailureRoutingBps;
        config.incentiveSelectCommittee = settings.incentiveSelectCommittee;
        config.incentiveCloseCommit = settings.incentiveCloseCommit;
        config.incentiveCloseReveal = settings.incentiveCloseReveal;
        config.incentiveOpenAppeal = settings.incentiveOpenAppeal;
        config.incentiveFinalize = settings.incentiveFinalize;
        config.incentiveRandomness = settings.incentiveRandomness;
    }

    function enforcePoolSettings(OwnershipConfigTypes.ResolverJuryPoolSettings calldata settings) internal pure {
        if (settings.activeEpochSize == 0) {
            revert Errors.InvalidConfigValue("activeEpochSize");
        }
        enforceDurationRange(
            "resolverEpochDuration",
            settings.resolverEpochDuration,
            MIN_RESOLVER_EPOCH_DURATION,
            MAX_RESOLVER_EPOCH_DURATION
        );
        enforceDurationRange(
            "resolverRotationWindow",
            settings.resolverRotationWindow,
            MIN_RESOLVER_ROTATION_WINDOW,
            MAX_RESOLVER_ROTATION_WINDOW
        );
        if (settings.resolverRotationWindow >= settings.resolverEpochDuration) {
            revert Errors.InvalidConfigValue("resolverRotationWindow");
        }
        enforceDurationRange(
            "epochRandomnessCommitDuration",
            settings.epochRandomnessCommitDuration,
            MIN_RESOLVER_EPOCH_PHASE_DURATION,
            MAX_RESOLVER_EPOCH_PHASE_DURATION
        );
        enforceDurationRange(
            "epochRandomnessRevealDuration",
            settings.epochRandomnessRevealDuration,
            MIN_RESOLVER_EPOCH_PHASE_DURATION,
            MAX_RESOLVER_EPOCH_PHASE_DURATION
        );
        enforceDurationRange(
            "epochSelectionDuration",
            settings.epochSelectionDuration,
            MIN_RESOLVER_EPOCH_PHASE_DURATION,
            MAX_RESOLVER_EPOCH_PHASE_DURATION
        );
        if (settings.minEpochRandomnessReveals < 1 || settings.minEpochRandomnessReveals > settings.activeEpochSize) {
            revert Errors.InvalidConfigValue("minEpochRandomnessReveals");
        }
        if (settings.activationDelay > MAX_RESOLVER_ACTIVATION_DELAY) {
            revert Errors.InvalidConfigValue("activationDelay");
        }
        if (settings.exitCooldown > MAX_RESOLVER_EXIT_COOLDOWN) {
            revert Errors.InvalidConfigValue("exitCooldown");
        }
        if (settings.participationThresholdBps > 10_000) {
            revert Errors.InvalidConfigValue("participationThresholdBps");
        }
        if (settings.concurrencyLimit == 0) {
            revert Errors.InvalidConfigValue("concurrencyLimit");
        }
    }

    function enforceExistingCommitteeSizes(LibEveMarket.ResolverJuryConfig storage config, uint16 activeEpochSize)
        internal
        view
    {
        uint256 length = config.committeeSizesByRound.length;
        for (uint256 index; index < length; ++index) {
            if (config.committeeSizesByRound[index] > activeEpochSize) {
                revert Errors.InvalidCommitteeSize(config.committeeSizesByRound[index]);
            }
        }
        if (config.minRandomnessReveals > activeEpochSize) {
            revert Errors.InvalidConfigValue("minRandomnessReveals");
        }
        if (config.allEligibleFallbackCap > activeEpochSize) {
            revert Errors.InvalidConfigValue("allEligibleFallbackCap");
        }
    }

    function enforceRoundSettings(
        OwnershipConfigTypes.ResolverJuryRoundSettings calldata settings,
        uint16 activeEpochSize
    ) internal pure {
        if (activeEpochSize == 0) {
            revert Errors.InvalidConfigValue("activeEpochSize");
        }
        enforceCommitteeSizes(settings.committeeSizesByRound, activeEpochSize, settings.maxAppealRounds);
        if (settings.appealBondMultiplierBps <= 10_000) {
            revert Errors.InvalidConfigValue("appealBondMultiplierBps");
        }
        enforceDurationRange("randomnessCommitDuration", settings.randomnessCommitDuration, 60, MAX_RANDOMNESS_TIMEOUT);
        enforceDurationRange("randomnessRevealDuration", settings.randomnessRevealDuration, 60, MAX_RANDOMNESS_TIMEOUT);
        enforceDurationRange(
            "commitDuration", settings.commitDuration, MIN_RESOLVER_PHASE_DURATION, MAX_RESOLVER_PHASE_DURATION
        );
        enforceDurationRange(
            "revealDuration", settings.revealDuration, MIN_RESOLVER_PHASE_DURATION, MAX_RESOLVER_PHASE_DURATION
        );
        enforceDurationRange("appealWindow", settings.appealWindow, 60, MAX_RESOLVER_EXIT_COOLDOWN);
        enforceDurationRange(
            "randomnessTimeout", settings.randomnessTimeout, MIN_RANDOMNESS_TIMEOUT, MAX_RANDOMNESS_TIMEOUT
        );
        if (settings.minRandomnessReveals < 2 || settings.minRandomnessReveals > activeEpochSize) {
            revert Errors.InvalidConfigValue("minRandomnessReveals");
        }
        if (settings.allEligibleFallbackCap > activeEpochSize) {
            revert Errors.InvalidConfigValue("allEligibleFallbackCap");
        }
    }

    function enforceCommitteeSizes(uint16[] calldata committeeSizes, uint16 activeEpochSize, uint8 maxAppealRounds)
        internal
        pure
    {
        if (committeeSizes.length == 0 || maxAppealRounds >= committeeSizes.length) {
            revert Errors.InvalidCommitteeSize(0);
        }

        uint16 previous;
        for (uint256 index; index < committeeSizes.length; ++index) {
            uint16 size = committeeSizes[index];
            if (size == 0 || size % 2 == 0 || size > activeEpochSize || (index != 0 && size <= previous)) {
                revert Errors.InvalidCommitteeSize(size);
            }
            previous = size;
        }
    }

    function enforceDurationRange(bytes32 paramName, uint64 duration, uint64 minimum, uint64 maximum) internal pure {
        if (duration < minimum || duration > maximum) {
            revert Errors.InvalidConfigValue(paramName);
        }
    }

    function enforceEconomicsSettings(OwnershipConfigTypes.ResolverJuryEconomicsSettings calldata settings)
        internal
        pure
    {
        enforceSlashBps("missedCommitSlashBps", settings.missedCommitSlashBps);
        enforceSlashBps("missedRevealSlashBps", settings.missedRevealSlashBps);
        enforceSlashBps("invalidRevealSlashBps", settings.invalidRevealSlashBps);
        if (settings.protocolFeeAllocationBps > 10_000) {
            revert Errors.InvalidConfigValue("protocolFeeAllocationBps");
        }
        if (sumRouting4(settings.appealSuccessRoutingBps) != 10_000) {
            revert Errors.InvalidRoutingSplit();
        }
        if (sumRouting3(settings.appealFailureRoutingBps) != 10_000) {
            revert Errors.InvalidRoutingSplit();
        }
    }

    function enforceSlashBps(bytes32 paramName, uint16 slashBps) internal pure {
        if (slashBps == 0 || slashBps > 10_000) {
            revert Errors.InvalidConfigValue(paramName);
        }
    }

    function committeeSizesHash(uint16[] storage committeeSizes) internal view returns (uint256 hashValue) {
        uint16[] memory values = new uint16[](committeeSizes.length);
        for (uint256 index; index < committeeSizes.length; ++index) {
            values[index] = committeeSizes[index];
        }
        hashValue = uint256(keccak256(abi.encode(values)));
    }

    function routingHash4(uint16[4] storage routing) internal view returns (uint256) {
        uint16[4] memory values;
        for (uint256 index; index < values.length; ++index) {
            values[index] = routing[index];
        }
        return uint256(keccak256(abi.encode(values)));
    }

    function routingHash4(uint16[4] calldata routing) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(routing)));
    }

    function routingHash3(uint16[3] storage routing) internal view returns (uint256) {
        uint16[3] memory values;
        for (uint256 index; index < values.length; ++index) {
            values[index] = routing[index];
        }
        return uint256(keccak256(abi.encode(values)));
    }

    function routingHash3(uint16[3] calldata routing) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(routing)));
    }

    function sumRouting4(uint16[4] calldata routing) internal pure returns (uint256 sum) {
        for (uint256 index; index < routing.length; ++index) {
            sum += routing[index];
        }
    }

    function sumRouting3(uint16[3] calldata routing) internal pure returns (uint256 sum) {
        for (uint256 index; index < routing.length; ++index) {
            sum += routing[index];
        }
    }
}
