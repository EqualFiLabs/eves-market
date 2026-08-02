// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IResolverRegistryFacet {
    struct CreatorReputationView {
        uint64 marketsCreated;
        uint64 marketsResolved;
        uint64 disputesRaised;
        uint64 outcomesUpheld;
        uint64 outcomesOverturned;
        uint128 totalVolume;
        uint64 cumulativeSettleDelay;
    }

    struct ResolverReputationView {
        uint64 activationTimestamp;
        uint64 totalSelections;
        uint64 commitCount;
        uint64 revealCount;
        uint64 missedCommitCount;
        uint64 missedRevealCount;
        uint64 invalidRevealCount;
        uint64 finalAgreementCount;
        uint64 slashCount;
        uint64 minorityUpheldCount;
    }

    struct ResolverJuryConfigView {
        address eveIdentity;
        address identityMintFeeToken;
        uint128 identityMintFee;
        uint128 resolverStakeRequirement;
        uint128 resolverStakeCap;
        uint16 resolverPoolCap;
        uint64 activationDelay;
        uint64 exitCooldown;
        uint16 participationThresholdBps;
        uint16 concurrencyLimit;
        uint32 participationGraceCount;
        uint256 conflictPositionThreshold;
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
        uint8 lowQuorumMode;
        uint8 tieBreakMode;
        uint8 randomnessFailureMode;
        uint8 minRandomnessReveals;
        uint16 allEligibleFallbackCap;
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

    struct ResolverIdentityView {
        uint256 identityId;
        address owner;
        bool creatorRole;
        bool resolverRole;
        uint8 lifecycle;
        uint8 effectiveLifecycle;
        uint128 resolverStake;
        uint64 activationTimestamp;
        uint64 activeAt;
        uint64 exitTimestamp;
        uint64 withdrawableAt;
        uint16 unresolvedCommittees;
        uint64 slashLockUntil;
        bool slashLockActive;
        bool activePoolMember;
        bool globallyEligible;
    }

    struct ResolverPoolView {
        uint256 activeResolverCount;
        uint256 eligibleResolverCount;
        uint16 resolverPoolCapacity;
    }

    function mintIdentity() external returns (uint256 identityId);
    function setCreatorRole(bool enabled) external;
    function setResolverRole(bool enabled) external;
    function depositResolverStake(uint256 amount) external;
    function activateResolver() external;
    function requestResolverExit() external;
    function withdrawResolverStake() external;
    function eveIdentity() external view returns (address);
    function resolverDashboard(address owner)
        external
        view
        returns (ResolverIdentityView memory identity, ResolverJuryConfigView memory config, ResolverPoolView memory pool);
    function resolverIdentity(uint256 identityId) external view returns (ResolverIdentityView memory view_);
    function resolverIdentityByOwner(address owner) external view returns (ResolverIdentityView memory view_);
    function resolverJuryConfig() external view returns (ResolverJuryConfigView memory view_);
    function identityByOwner(address owner) external view returns (uint256 identityId);
    function isEligibleResolver(uint256 identityId, bytes32 disputeId) external view returns (bool);
    function hasConflict(uint256 identityId, bytes32 marketId) external view returns (bool);
    function resolverLifecycleState(uint256 identityId) external view returns (uint8);
    function creatorReputation(uint256 identityId) external view returns (CreatorReputationView memory);
    function resolverReputation(uint256 identityId) external view returns (ResolverReputationView memory);
    function eligibleResolverCount() external view returns (uint256);
    function activeResolverCount() external view returns (uint256);
    function resolverPoolCapacity() external view returns (uint16);
    function resolverPoolMemberAt(uint256 index) external view returns (uint256 identityId);
    function applyFinalityReputation(bytes32 disputeId, uint8 finalResult) external;
}
