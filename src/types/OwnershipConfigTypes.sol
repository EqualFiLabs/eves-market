// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {LibEveMarket} from "../libraries/LibEveMarket.sol";

library OwnershipConfigTypes {
    struct ResolverJuryIdentitySettings {
        address identityMintFeeToken;
        uint128 identityMintFee;
        uint128 resolverStakeRequirement;
        uint128 resolverStakeCap;
    }

    struct ResolverJuryPoolSettings {
        uint16 resolverPoolCap;
        uint64 activationDelay;
        uint64 exitCooldown;
        uint16 participationThresholdBps;
        uint16 concurrencyLimit;
        uint32 participationGraceCount;
        uint256 conflictPositionThreshold;
    }

    struct ResolverJuryRoundSettings {
        uint16[] committeeSizesByRound;
        uint8 maxAppealRounds;
        uint16 appealBondMultiplierBps;
        uint64 randomnessCommitDuration;
        uint64 randomnessRevealDuration;
        uint64 commitDuration;
        uint64 revealDuration;
        uint64 appealWindow;
        uint64 randomnessTimeout;
        uint32 quorum;
        uint16 redrawLimit;
        LibEveMarket.LowQuorumMode lowQuorumMode;
        LibEveMarket.TieBreakMode tieBreakMode;
        LibEveMarket.RandomnessFailureMode randomnessFailureMode;
        uint8 minRandomnessReveals;
        uint16 allEligibleFallbackCap;
    }

    struct ResolverJuryEconomicsSettings {
        uint16 missedCommitSlashBps;
        uint16 missedRevealSlashBps;
        uint16 invalidRevealSlashBps;
        uint64 slashCooldown;
        uint16 protocolFeeAllocationBps;
        uint16[4] appealSuccessRoutingBps;
        uint16[3] appealFailureRoutingBps;
        uint128 incentiveSelectCommittee;
        uint128 incentiveCloseCommit;
        uint128 incentiveCloseReveal;
        uint128 incentiveOpenAppeal;
        uint128 incentiveFinalize;
        uint128 incentiveRandomness;
    }
}
