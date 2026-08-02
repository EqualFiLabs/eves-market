// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface ISeniorCapitalFacet {
    error SeniorCapitalAssetNotSet();
    error SeniorCapitalZeroAmount();
    error SeniorCapitalZeroAddress();
    error SeniorCapitalActivationPending(uint256 eligibleAt);
    error SeniorCapitalAmountTooSmall(uint256 requested);
    error SeniorCapitalInsufficientPending(uint256 requested, uint256 available);
    error SeniorCapitalInsufficientPrincipal(uint256 requested, uint256 available);
    error SeniorCapitalInsufficientAvailable(uint256 requested, uint256 available);
    error SeniorCapitalInsufficientReserved(uint256 requested, uint256 available);
    error SeniorCapitalInsufficientExposure(uint256 requested, uint256 available);
    error SeniorCapitalNoEligiblePrincipal();
    error SeniorCapitalExitAlreadyPending(uint256 exitId);
    error SeniorCapitalExitNotFound(uint256 exitId);
    error SeniorCapitalExitNotOwner(uint256 exitId, address caller);
    error SeniorCapitalInvalidExitBatch(uint256 supplied, uint256 maximum);
    error SeniorCapitalNoExitClaim(address account);
    error SeniorCapitalEpochMismatch(uint64 accountEpoch, uint64 incomingEpoch);
    error SeniorCapitalProviderStoredInvariant(address account, uint256 requested, uint256 available);
    error SeniorCapitalNonExactTransfer(uint256 expected, uint256 actual);

    struct SeniorCapitalState {
        address asset;
        uint64 epoch;
        uint64 activationDelay;
        uint256 pendingPrincipal;
        uint256 totalPrincipal;
        uint256 totalStored;
        uint256 exitStored;
        uint256 availableCapital;
        uint256 reservedCapital;
        uint256 activeExposure;
        uint256 feeReserve;
        uint256 realizedLosses;
        uint256 fundingRevenue;
        uint256 scaleRay;
        uint256 feeIndexRay;
        uint256 feeRemainderRay;
        uint256 exitHead;
        uint256 exitTail;
        uint256 exitClaims;
    }

    struct SeniorCapitalAccount {
        uint64 epoch;
        uint64 pendingSince;
        uint256 pendingPrincipal;
        uint256 storedUnits;
        uint256 effectivePrincipal;
        uint256 accruedFees;
        uint256 pendingFees;
        uint256 activeExitId;
    }

    struct SeniorCapitalExit {
        uint256 exitId;
        address owner;
        address receiver;
        uint64 epoch;
        uint256 storedUnits;
        uint256 effectivePrincipal;
        uint256 accruedFees;
        uint256 pendingFees;
        bool cancelled;
    }

    struct SeniorCapitalBucket {
        uint256 reservedCapital;
        uint256 activeExposure;
        uint256 realizedLosses;
        uint256 fundingRevenue;
        uint64 riskSnapshotVersion;
        uint64 riskSnapshotEpoch;
        uint256 riskSnapshotStored;
        bool riskSnapshotSet;
    }

    event SeniorCapitalDeposited(address indexed account, uint256 assets, uint256 eligibleAt);
    event SeniorCapitalPendingWithdrawn(address indexed account, address indexed receiver, uint256 assets);
    event SeniorCapitalActivated(address indexed account, uint64 indexed epoch, uint256 principal, uint256 storedUnits);
    event SeniorCapitalExitRequested(
        uint256 indexed exitId,
        address indexed account,
        address indexed receiver,
        uint64 epoch,
        uint256 principal,
        uint256 storedUnits
    );
    event SeniorCapitalExitCancelled(
        uint256 indexed exitId, address indexed account, uint256 principalRestored, uint256 storedUnits
    );
    event SeniorCapitalExitProcessed(
        uint256 indexed exitId,
        address indexed account,
        address indexed receiver,
        uint256 principalPaid,
        uint256 feesPaid,
        uint256 storedUnitsRemaining
    );
    event SeniorCapitalExitClaimAccrued(address indexed account, uint256 indexed exitId, uint256 assets);
    event SeniorCapitalExitClaimed(address indexed account, address indexed receiver, uint256 assets);
    event SeniorCapitalFeesAccrued(
        uint64 indexed epoch, uint8 indexed sourceKind, bytes32 indexed sourceId, uint256 assets
    );
    event SeniorCapitalFeesClaimed(address indexed account, address indexed receiver, uint256 assets);
    event SeniorCapitalFeesDonated(address indexed donor, uint256 assets);
    event SeniorCapitalReserved(bytes32 indexed bucketId, uint256 assets);
    event SeniorCapitalRiskCohortSnapshotted(
        bytes32 indexed bucketId, uint64 indexed membershipVersion, uint64 indexed epoch, uint256 storedUnits
    );
    event SeniorCapitalReservationReleased(bytes32 indexed bucketId, uint256 assets);
    event SeniorCapitalDeployed(bytes32 indexed bucketId, uint256 assets);
    event SeniorCapitalRepaid(bytes32 indexed bucketId, uint256 assets);
    event SeniorCapitalLossRecorded(bytes32 indexed bucketId, uint64 indexed epoch, uint256 assets);
    event SeniorCapitalEpochRolled(uint64 indexed previousEpoch, uint64 indexed newEpoch, bool exhausted);

    function depositSeniorCapital(uint256 assets) external returns (uint256 credited);

    function withdrawPendingSeniorCapital(uint256 assets, address receiver) external returns (uint256 withdrawn);

    function activateSeniorCapital() external returns (uint256 principal, uint256 storedUnits);

    function requestSeniorCapitalExit(uint256 principal, address receiver)
        external
        returns (uint256 exitId, uint256 principalQueued, uint256 storedUnits);

    function cancelSeniorCapitalExit(uint256 exitId) external returns (uint256 principalRestored);

    function processSeniorCapitalExits(uint256 maxRequests)
        external
        returns (uint256 inspected, uint256 completed, uint256 principalPaid, uint256 feesPaid);

    function claimSeniorCapitalExit(address receiver) external returns (uint256 assets);

    function claimSeniorCapitalFees(address receiver) external returns (uint256 amount);

    function donateSeniorCapitalFees(uint256 assets) external returns (uint256 credited);

    function seniorCapitalState() external view returns (SeniorCapitalState memory state);

    function seniorCapitalAccount(address account) external view returns (SeniorCapitalAccount memory accountView);

    function seniorCapitalExit(uint256 exitId) external view returns (SeniorCapitalExit memory exitView);

    function seniorCapitalBucket(bytes32 bucketId) external view returns (SeniorCapitalBucket memory bucketView);

    function pendingSeniorCapitalFees(address account) external view returns (uint256 fees);

    function claimableSeniorCapitalExit(address account) external view returns (uint256 assets);
}
