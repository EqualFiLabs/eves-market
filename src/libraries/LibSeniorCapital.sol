// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

import {ISeniorCapitalFacet} from "../interfaces/ISeniorCapitalFacet.sol";

library LibSeniorCapital {
    using SafeERC20 for IERC20;

    bytes32 internal constant STORAGE_SLOT = keccak256("eve.prediction.senior.capital.storage.v1");
    uint256 internal constant RAY = 1e27;
    uint64 internal constant ACTIVATION_DELAY = 24 hours;
    uint256 internal constant MAX_EXIT_BATCH = 50;

    uint8 internal constant FEE_SOURCE_DONATION = 0;
    uint8 internal constant FEE_SOURCE_MLO_FUNDING = 1;
    uint8 internal constant FEE_SOURCE_ORDERBOOK = 2;
    uint8 internal constant FEE_SOURCE_PARIMUTUEL = 3;
    uint8 internal constant FEE_SOURCE_PARLAY = 4;
    uint8 internal constant FEE_SOURCE_MLO_PROFIT_SHARE = 5;

    struct RewardIndex {
        uint256 accPerStoredRay;
        uint256 remainderRay;
        uint256 reserve;
    }

    struct Epoch {
        uint256 scaleRay;
        uint256 outstandingStored;
        RewardIndex fees;
    }

    struct Account {
        uint64 epoch;
        uint64 pendingSince;
        uint256 pendingPrincipal;
        uint256 stored;
        uint256 feeCheckpointRay;
        uint256 accruedFees;
        uint256 activeExitId;
    }

    struct ExitRequest {
        address owner;
        address receiver;
        uint64 epoch;
        uint256 stored;
        uint256 feeCheckpointRay;
        uint256 accruedFees;
        bool cancelled;
    }

    struct Bucket {
        uint256 reservedCapital;
        uint256 activeExposure;
        uint256 realizedLosses;
        uint256 fundingRevenue;
        uint64 riskSnapshotVersion;
        uint64 riskSnapshotEpoch;
        uint256 riskSnapshotStored;
        bool riskSnapshotSet;
    }

    struct MembershipCheckpoint {
        uint64 version;
        uint64 epoch;
        uint256 stored;
    }

    struct Storage {
        uint64 currentEpoch;
        uint256 pendingPrincipal;
        uint256 totalPrincipal;
        uint256 totalStored;
        uint256 totalExitStored;
        uint256 unreservedPrincipal;
        uint256 reservedCapital;
        uint256 activeExposure;
        uint256 totalFeeReserve;
        uint256 realizedLosses;
        uint256 fundingRevenue;
        uint256 nextExitId;
        uint256 exitHead;
        uint256 exitTail;
        mapping(uint64 epoch => Epoch state) epochs;
        mapping(address account => Account state) accounts;
        mapping(uint256 exitId => ExitRequest request) exits;
        mapping(bytes32 bucketId => Bucket state) buckets;
        uint256 totalExitClaims;
        mapping(address account => uint256 assets) exitClaims;
        uint64 membershipVersion;
        mapping(address account => uint64 epoch) providerEpoch;
        mapping(address account => uint256 stored) providerStored;
        mapping(address account => MembershipCheckpoint[] checkpoints) providerCheckpoints;
    }

    function s() internal pure returns (Storage storage state) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            state.slot := slot
        }
    }

    function currentEpoch(Storage storage state) internal returns (Epoch storage epoch) {
        epoch = state.epochs[state.currentEpoch];
        if (epoch.scaleRay == 0) epoch.scaleRay = RAY;
    }

    function availableCapital(Storage storage state) internal view returns (uint256 available) {
        uint256 exitClaim = exitEffective(state);
        available = state.unreservedPrincipal > exitClaim ? state.unreservedPrincipal - exitClaim : 0;
    }

    function exitEffective(Storage storage state) internal view returns (uint256 effective) {
        if (state.totalExitStored == 0 || state.totalStored == 0) return 0;
        if (state.totalExitStored == state.totalStored) return state.totalPrincipal;
        uint256 scale = state.epochs[state.currentEpoch].scaleRay;
        if (scale == 0) scale = RAY;
        effective = Math.mulDiv(state.totalExitStored, scale, RAY);
    }

    function effectiveFor(Storage storage state, uint64 epochId, uint256 stored) internal view returns (uint256) {
        if (stored == 0 || epochId != state.currentEpoch || state.totalStored == 0) return 0;
        if (stored == state.totalStored) return state.totalPrincipal;
        uint256 scale = state.epochs[epochId].scaleRay;
        if (scale == 0) return 0;
        return Math.mulDiv(stored, scale, RAY);
    }

    function pendingFees(Storage storage state, Account storage account) internal view returns (uint256 fees) {
        fees = account.accruedFees;
        if (account.stored == 0) return fees;
        RewardIndex storage index = state.epochs[account.epoch].fees;
        if (index.accPerStoredRay > account.feeCheckpointRay) {
            fees += Math.mulDiv(account.stored, index.accPerStoredRay - account.feeCheckpointRay, RAY);
        }
    }

    function pendingExitFees(Storage storage state, ExitRequest storage request) internal view returns (uint256 fees) {
        fees = request.accruedFees;
        if (request.stored == 0) return fees;
        RewardIndex storage index = state.epochs[request.epoch].fees;
        if (index.accPerStoredRay > request.feeCheckpointRay) {
            fees += Math.mulDiv(request.stored, index.accPerStoredRay - request.feeCheckpointRay, RAY);
        }
    }

    function settleAccount(Storage storage state, Account storage account) internal {
        if (account.stored == 0) return;
        RewardIndex storage index = state.epochs[account.epoch].fees;
        if (index.accPerStoredRay > account.feeCheckpointRay) {
            account.accruedFees += Math.mulDiv(account.stored, index.accPerStoredRay - account.feeCheckpointRay, RAY);
        }
        account.feeCheckpointRay = index.accPerStoredRay;
    }

    function settleExit(Storage storage state, ExitRequest storage request) internal {
        if (request.stored == 0) return;
        RewardIndex storage index = state.epochs[request.epoch].fees;
        if (index.accPerStoredRay > request.feeCheckpointRay) {
            request.accruedFees += Math.mulDiv(request.stored, index.accPerStoredRay - request.feeCheckpointRay, RAY);
        }
        request.feeCheckpointRay = index.accPerStoredRay;
    }

    function addPending(Account storage account, uint256 amount) internal returns (uint256 eligibleAt) {
        if (account.pendingPrincipal == 0) {
            account.pendingPrincipal = amount;
            account.pendingSince = uint64(block.timestamp);
        } else {
            uint256 age = block.timestamp - account.pendingSince;
            if (age > ACTIVATION_DELAY) age = ACTIVATION_DELAY;
            uint256 combined = account.pendingPrincipal + amount;
            uint256 weightedAge = Math.mulDiv(account.pendingPrincipal, age, combined);
            account.pendingPrincipal = combined;
            account.pendingSince = uint64(block.timestamp - weightedAge);
        }
        eligibleAt = uint256(account.pendingSince) + ACTIVATION_DELAY;
    }

    function activateStored(
        Storage storage state,
        Account storage account,
        address owner,
        uint256 storedUnits,
        uint256 principal
    ) internal {
        Epoch storage epoch = currentEpoch(state);
        _checkpointBeforeStoredIncrease(state, account, state.currentEpoch, epoch.fees.accPerStoredRay);

        account.stored += storedUnits;
        state.totalStored += storedUnits;
        epoch.outstandingStored += storedUnits;
        state.totalPrincipal += principal;
        state.unreservedPrincipal += principal;
        _increaseProviderStored(state, owner, storedUnits);
    }

    function restoreExit(Storage storage state, Account storage account, ExitRequest storage request)
        internal
        returns (uint256 principalRestored)
    {
        uint256 storedUnits = request.stored;
        _checkpointBeforeStoredIncrease(state, account, request.epoch, request.feeCheckpointRay);

        principalRestored = effectiveFor(state, request.epoch, storedUnits);
        account.stored += storedUnits;
        account.accruedFees += request.accruedFees;
        state.totalExitStored -= storedUnits;
        _increaseProviderStored(state, request.owner, storedUnits);
    }

    function accrueExitClaim(Storage storage state, address owner, uint256 assets) internal {
        if (assets == 0) return;
        state.exitClaims[owner] += assets;
        state.totalExitClaims += assets;
    }

    function takeExitClaim(Storage storage state, address owner) internal returns (uint256 assets) {
        assets = state.exitClaims[owner];
        if (assets == 0) revert ISeniorCapitalFacet.SeniorCapitalNoExitClaim(owner);
        state.exitClaims[owner] = 0;
        state.totalExitClaims -= assets;
    }

    function removeProviderStored(Storage storage state, address owner, uint64 epochId, uint256 storedUnits) internal {
        if (storedUnits == 0) return;
        uint256 providerUnits = state.providerEpoch[owner] == epochId ? state.providerStored[owner] : 0;
        if (storedUnits > providerUnits) {
            revert ISeniorCapitalFacet.SeniorCapitalProviderStoredInvariant(owner, storedUnits, providerUnits);
        }
        _writeProviderCheckpoint(state, owner, epochId, providerUnits - storedUnits);
    }

    function providerStoredAt(Storage storage state, address owner, uint64 version, uint64 epochId)
        internal
        view
        returns (uint256 storedUnits)
    {
        MembershipCheckpoint[] storage checkpoints = state.providerCheckpoints[owner];
        uint256 low;
        uint256 high = checkpoints.length;
        while (low < high) {
            uint256 middle = (low + high) >> 1;
            if (checkpoints[middle].version <= version) low = middle + 1;
            else high = middle;
        }
        if (low == 0) return 0;
        MembershipCheckpoint storage checkpoint = checkpoints[low - 1];
        if (checkpoint.epoch != epochId) return 0;
        storedUnits = checkpoint.stored;
    }

    function _increaseProviderStored(Storage storage state, address owner, uint256 storedUnits) private {
        uint256 providerUnits = state.providerEpoch[owner] == state.currentEpoch ? state.providerStored[owner] : 0;
        _writeProviderCheckpoint(state, owner, state.currentEpoch, providerUnits + storedUnits);
    }

    function _writeProviderCheckpoint(Storage storage state, address owner, uint64 epochId, uint256 storedUnits)
        private
    {
        uint64 version = state.membershipVersion + 1;
        state.membershipVersion = version;
        state.providerEpoch[owner] = epochId;
        state.providerStored[owner] = storedUnits;
        state.providerCheckpoints[owner].push(
            MembershipCheckpoint({version: version, epoch: epochId, stored: storedUnits})
        );
    }

    function _checkpointBeforeStoredIncrease(
        Storage storage state,
        Account storage account,
        uint64 incomingEpoch,
        uint256 incomingCheckpointRay
    ) private {
        if (account.stored == 0) {
            account.epoch = incomingEpoch;
            account.feeCheckpointRay = incomingCheckpointRay;
            return;
        }
        if (account.epoch != incomingEpoch) {
            revert ISeniorCapitalFacet.SeniorCapitalEpochMismatch(account.epoch, incomingEpoch);
        }
        settleAccount(state, account);
    }

    function accrueFees(Storage storage state, uint256 assets, uint8 sourceKind, bytes32 sourceId) internal {
        if (assets == 0) return;
        if (state.totalStored == 0) revert ISeniorCapitalFacet.SeniorCapitalNoEligiblePrincipal();
        Epoch storage epoch = currentEpoch(state);
        uint256 dividend = assets * RAY + epoch.fees.remainderRay;
        uint256 delta = dividend / state.totalStored;
        epoch.fees.remainderRay = dividend - delta * state.totalStored;
        epoch.fees.accPerStoredRay += delta;
        epoch.fees.reserve += assets;
        state.totalFeeReserve += assets;
        emit ISeniorCapitalFacet.SeniorCapitalFeesAccrued(state.currentEpoch, sourceKind, sourceId, assets);
    }

    function reserveCapital(Storage storage state, bytes32 bucketId, uint256 assets) internal {
        if (assets == 0) revert ISeniorCapitalFacet.SeniorCapitalZeroAmount();
        uint256 available = availableCapital(state);
        if (assets > available) revert ISeniorCapitalFacet.SeniorCapitalInsufficientAvailable(assets, available);
        Bucket storage bucket = state.buckets[bucketId];
        if (!bucket.riskSnapshotSet) {
            uint256 riskStored = state.totalStored - state.totalExitStored;
            bucket.riskSnapshotSet = true;
            bucket.riskSnapshotVersion = state.membershipVersion;
            bucket.riskSnapshotEpoch = state.currentEpoch;
            bucket.riskSnapshotStored = riskStored;
            emit ISeniorCapitalFacet.SeniorCapitalRiskCohortSnapshotted(
                bucketId, state.membershipVersion, state.currentEpoch, riskStored
            );
        }
        state.unreservedPrincipal -= assets;
        state.reservedCapital += assets;
        bucket.reservedCapital += assets;
        emit ISeniorCapitalFacet.SeniorCapitalReserved(bucketId, assets);
    }

    function releaseReservedCapital(Storage storage state, bytes32 bucketId, uint256 assets) internal {
        if (assets == 0) return;
        Bucket storage bucket = state.buckets[bucketId];
        if (assets > bucket.reservedCapital) {
            revert ISeniorCapitalFacet.SeniorCapitalInsufficientReserved(assets, bucket.reservedCapital);
        }
        bucket.reservedCapital -= assets;
        state.reservedCapital -= assets;
        state.unreservedPrincipal += assets;
        emit ISeniorCapitalFacet.SeniorCapitalReservationReleased(bucketId, assets);
    }

    function deployReservedCapital(Storage storage state, bytes32 bucketId, uint256 assets) internal {
        if (assets == 0) return;
        Bucket storage bucket = state.buckets[bucketId];
        if (assets > bucket.reservedCapital) {
            revert ISeniorCapitalFacet.SeniorCapitalInsufficientReserved(assets, bucket.reservedCapital);
        }
        bucket.reservedCapital -= assets;
        bucket.activeExposure += assets;
        state.reservedCapital -= assets;
        state.activeExposure += assets;
        emit ISeniorCapitalFacet.SeniorCapitalDeployed(bucketId, assets);
    }

    function repayActiveExposure(Storage storage state, bytes32 bucketId, uint256 assets) internal {
        if (assets == 0) return;
        Bucket storage bucket = state.buckets[bucketId];
        if (assets > bucket.activeExposure) {
            revert ISeniorCapitalFacet.SeniorCapitalInsufficientExposure(assets, bucket.activeExposure);
        }
        bucket.activeExposure -= assets;
        state.activeExposure -= assets;
        state.unreservedPrincipal += assets;
        emit ISeniorCapitalFacet.SeniorCapitalRepaid(bucketId, assets);
    }

    function recordRealizedLoss(Storage storage state, bytes32 bucketId, uint256 assets) internal {
        if (assets == 0) return;
        Bucket storage bucket = state.buckets[bucketId];
        if (assets > bucket.activeExposure) {
            revert ISeniorCapitalFacet.SeniorCapitalInsufficientExposure(assets, bucket.activeExposure);
        }
        uint64 epochId = state.currentEpoch;
        bucket.activeExposure -= assets;
        bucket.realizedLosses += assets;
        state.activeExposure -= assets;
        state.totalPrincipal -= assets;
        state.realizedLosses += assets;
        emit ISeniorCapitalFacet.SeniorCapitalLossRecorded(bucketId, epochId, assets);

        Epoch storage epoch = currentEpoch(state);
        if (state.totalPrincipal == 0) {
            epoch.scaleRay = 0;
            state.totalStored = 0;
            state.totalExitStored = 0;
            _rollEpoch(state, true);
        } else {
            uint256 newScale = Math.mulDiv(state.totalPrincipal, RAY, state.totalStored);
            if (newScale == 0) revert ISeniorCapitalFacet.SeniorCapitalAmountTooSmall(state.totalPrincipal);
            epoch.scaleRay = newScale;
        }
    }

    function noteFundingRevenue(Storage storage state, bytes32 bucketId, uint256 assets) internal {
        state.fundingRevenue += assets;
        state.buckets[bucketId].fundingRevenue += assets;
    }

    function removeOutstanding(Epoch storage epoch, uint256 stored) internal {
        epoch.outstandingStored -= stored;
    }

    function feePayout(Storage storage state, uint64 epochId, uint256 accrued, bool positionCleared)
        internal
        returns (uint256 payout)
    {
        Epoch storage epoch = state.epochs[epochId];
        payout = accrued;
        if (positionCleared && epoch.outstandingStored == 0) payout = epoch.fees.reserve;
        if (payout != 0) {
            epoch.fees.reserve -= payout;
            state.totalFeeReserve -= payout;
        }
    }

    function rollEmptyEpoch(Storage storage state) internal {
        if (state.totalStored == 0 && state.totalPrincipal == 0) _rollEpoch(state, false);
    }

    function _rollEpoch(Storage storage state, bool exhausted) private {
        uint64 previous = state.currentEpoch;
        state.currentEpoch = previous + 1;
        state.epochs[state.currentEpoch].scaleRay = RAY;
        emit ISeniorCapitalFacet.SeniorCapitalEpochRolled(previous, state.currentEpoch, exhausted);
    }
}
