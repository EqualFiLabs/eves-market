// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IResolverJuryFacet {
    struct DisputeView {
        bytes32 disputeId;
        bytes32 marketId;
        uint8 state;
        uint8 currentRound;
        uint8 finalResult;
        bool finalized;
        bool isMultiOutcome;
        uint8 outcomeCount;
        uint128 disputeBondBase;
        uint128 rewardPoolBond;
        bool rewardsDistributed;
        bool reputationApplied;
        uint16 committeeSize;
        uint32 validRevealCount;
        uint64 randomnessCommitDeadline;
        uint64 randomnessRevealDeadline;
        uint64 commitDeadline;
        uint64 revealDeadline;
        uint64 appealDeadline;
        uint8 provisionalResult;
        bool hasProvisional;
        uint32 randomnessAttempt;
        uint64 randomnessReferenceBlock;
        bytes32 seed;
        bytes32 randomnessAccumulator;
        bool allEligibleFallback;
    }

    function initiateDispute(bytes32 marketId) external;
    function openRandomnessCommit(bytes32 disputeId) external;
    function commitRandomness(bytes32 disputeId, bytes32 commitment) external;
    function closeRandomnessCommit(bytes32 disputeId) external;
    function revealRandomness(bytes32 disputeId, bytes32 value, bytes32 salt) external;
    function closeRandomnessReveal(bytes32 disputeId) external;
    function selectCommittee(bytes32 disputeId) external;
    function closeCommit(bytes32 disputeId) external;
    function closeRevealAndTally(bytes32 disputeId) external;
    function openAppeal(bytes32 disputeId) external;
    function finalizeDispute(bytes32 disputeId) external;
    function applyRandomnessFallback(bytes32 disputeId) external;
    function commitVote(bytes32 disputeId, bytes32 commitment) external;
    function revealVote(bytes32 disputeId, uint8 outcome, bytes32 salt) external;
    function disputeView(bytes32 disputeId) external view returns (DisputeView memory view_);
    function committeeMembers(bytes32 disputeId, uint8 round) external view returns (uint256[] memory identityIds);
    function outcomeTally(bytes32 disputeId, uint8 round)
        external
        view
        returns (uint8[] memory outcomes, uint256[] memory counts);
    function revealedVote(bytes32 disputeId, uint8 round, uint256 identityId)
        external
        view
        returns (bool revealed, uint8 outcome);
    function provisionalResult(bytes32 disputeId) external view returns (uint8 outcome, bool isFinal);
}
