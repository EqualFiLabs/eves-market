// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IEveIdentity} from "../interfaces/IEveIdentity.sol";
import {Errors} from "./Errors.sol";

library LibResolverJury {
    bytes32 internal constant STORAGE_SLOT = bytes32(uint256(keccak256("eve.resolver.identity.jury.storage")) - 1);

    enum ResolverLifecycle {
        None,
        Minted,
        ResolverCandidate,
        ResolverActive,
        ExitRequested,
        ExitCooldown,
        Exited,
        Slashed
    }

    enum DisputeState {
        None,
        CommitteeSelectionPending,
        CommitOpen,
        RevealOpen,
        ProvisionalJuryResult,
        AppealOpen,
        Finalized
    }

    struct ResolverIdentityRecord {
        uint64 activationTimestamp;
        uint64 exitTimestamp;
        uint128 resolverStake;
        ResolverLifecycle lifecycle;
        uint16 unresolvedCommittees;
        uint64 slashLockUntil;
        bool slashLockActive;
    }

    struct CreatorReputation {
        uint64 marketsCreated;
        uint64 marketsResolved;
        uint64 disputesRaised;
        uint64 outcomesUpheld;
        uint64 outcomesOverturned;
        uint128 totalVolume;
        uint64 cumulativeSettleDelay;
    }

    struct ResolverReputation {
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

    struct RandomnessContribution {
        bytes32 commitment;
        bool hasCommitted;
        bool hasRevealed;
        bytes32 revealedValue;
        uint32 attempt;
    }

    struct ResolverEpochRandomness {
        bytes32 commitment;
        bool hasCommitted;
        bool hasRevealed;
        bytes32 revealedValue;
    }

    struct ResolverEpochCandidate {
        bool optedIn;
        bool selected;
        bool scoreSubmitted;
        uint256 score;
        ResolverEpochRandomness randomness;
    }

    struct ResolverEpochSelection {
        uint256 identityId;
        uint256 score;
    }

    struct ResolverEpoch {
        uint64 epochId;
        uint64 startTime;
        uint64 endTime;
        uint64 rotationOpenedAt;
        uint64 commitDeadline;
        uint64 revealDeadline;
        uint64 selectionDeadline;
        uint64 randomnessReferenceBlock;
        uint64 seedReferenceBlock;
        uint32 validRevealCount;
        uint32 scoreSubmittedCount;
        bytes32 randomnessAccumulator;
        bytes32 seed;
        bool seedFinalized;
        bool selectionFinalized;
        uint16 compliantActiveCount;
        uint256[] activeSet;
        ResolverEpochSelection[] selected;
        uint256[] candidates;
        mapping(uint256 => uint256) activeIndex;
        mapping(uint256 => bool) selectedIdentity;
        mapping(uint256 => bool) rewardExcluded;
        mapping(uint256 => ResolverEpochCandidate) candidateByIdentity;
        mapping(uint256 => ResolverEpochRandomness) activeRandomness;
        mapping(address => uint128) tradingRewardsAccrued;
        mapping(address => bool) tradingRewardsFinalized;
    }

    struct DisputeRound {
        uint8 round;
        uint16 committeeSize;
        uint64 randomnessCommitDeadline;
        uint64 randomnessRevealDeadline;
        uint64 commitDeadline;
        uint64 revealDeadline;
        uint64 appealDeadline;
        uint8 provisionalResult;
        bool hasProvisional;
        uint32 validRevealCount;
        uint16 redrawsUsed;
        uint32 randomnessAttempt;
        uint64 randomnessReferenceBlock;
        bytes32 seed;
        bytes32 randomnessAccumulator;
        bool allEligibleFallback;
        uint256[] committee;
        mapping(uint8 => uint256) tally;
        mapping(uint256 => bytes32) commitment;
        mapping(uint256 => bool) hasCommitted;
        mapping(uint256 => bool) hasRevealed;
        mapping(uint256 => uint8) revealedOutcome;
        mapping(uint256 => bool) inCommittee;
        mapping(uint256 => bool) slashedThisRound;
        mapping(uint256 => RandomnessContribution) randomness;
    }

    struct Dispute {
        bytes32 marketId;
        bool isMultiOutcome;
        uint8 outcomeCount;
        DisputeState state;
        uint8 currentRound;
        uint8 finalResult;
        bool finalized;
        uint128 disputeBondBase;
        uint128 rewardPoolBond;
        bool rewardsDistributed;
        bool reputationApplied;
        mapping(uint8 => DisputeRound) rounds;
        uint256[] allSelected;
        mapping(uint256 => bool) everSelected;
        mapping(uint8 => uint128) appealBond;
        mapping(uint8 => address) appellant;
    }

    struct ResolverJuryStorage {
        mapping(bytes32 => Dispute) disputes;
        mapping(bytes32 => bytes32) disputeIdByMarket;
        mapping(uint256 => ResolverIdentityRecord) identities;
        mapping(uint256 => CreatorReputation) creatorRep;
        mapping(uint256 => ResolverReputation) resolverRep;
        mapping(address => uint256) identityByOwner;
        uint64 currentResolverEpoch;
        mapping(uint64 => ResolverEpoch) resolverEpochs;
        mapping(uint256 => mapping(address => uint128)) resolverRewardsAccrued;
        mapping(uint256 => mapping(address => uint128)) resolverRewardsClaimed;
        address eveIdentity;
    }

    function store() internal pure returns (ResolverJuryStorage storage storage_) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            storage_.slot := slot
        }
    }

    function requireIdentityId(address identityContract, address owner) internal view returns (uint256 identityId) {
        if (identityContract == address(0)) {
            revert Errors.ZeroAddress();
        }
        identityId = IEveIdentity(identityContract).identityOf(owner);
        if (identityId == 0) {
            revert Errors.NotIdentityOwner(owner);
        }
    }
}
