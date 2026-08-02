// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

import {IMLOInsuranceFund} from "../interfaces/IMLOInsuranceFund.sol";
import {IMLOPredictionAdapterFacet} from "../interfaces/IMLOPredictionAdapterFacet.sol";
import {IMLOProfitShareFacet} from "../interfaces/IMLOProfitShareFacet.sol";
import {LibEveMarket} from "./LibEveMarket.sol";
import {LibSeniorCapital} from "./LibSeniorCapital.sol";
import {MLOProfitShareTypes} from "../types/MLOProfitShareTypes.sol";

library LibMLOProfitShare {
    using SafeERC20 for IERC20;

    bytes32 internal constant STORAGE_SLOT = keccak256("eve.prediction.mlo.profit.share.storage.v1");
    uint256 internal constant BPS_DENOMINATOR = 10_000;
    uint64 internal constant CONFIG_TIMELOCK = 7 days;
    uint64 internal constant CONFIG_EXECUTION_WINDOW = 2 days;
    uint16 internal constant DEFAULT_MAKER_BPS = 7_500;
    uint16 internal constant DEFAULT_SENIOR_BPS = 2_000;
    uint16 internal constant DEFAULT_INSURANCE_BPS = 500;

    struct Storage {
        MLOProfitShareTypes.ProfitSplit activeSplit;
        MLOProfitShareTypes.PendingProfitSplit pendingSplit;
        bool initialized;
        mapping(bytes32 bucketId => MLOProfitShareTypes.BucketProfitAccount account) bucketAccounts;
        uint256 totalSeniorRewardReserve;
        mapping(bytes32 bucketId => mapping(address account => uint256 assets)) rewardClaimed;
    }

    function s() internal pure returns (Storage storage state) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            state.slot := slot
        }
    }

    function initialize(uint256 makerBps, uint256 seniorBps, uint256 insuranceBps) internal {
        Storage storage state = s();
        if (state.initialized) revert IMLOProfitShareFacet.MLOProfitSplitAlreadyInitialized();
        MLOProfitShareTypes.ProfitSplit memory split = _validatedSplit(makerBps, seniorBps, insuranceBps);
        split.version = 1;
        state.activeSplit = split;
        state.initialized = true;
        emit IMLOProfitShareFacet.MLOProfitSplitInitialized(
            split.makerBps, split.seniorBps, split.insuranceBps, split.version
        );
    }

    function schedule(uint256 makerBps, uint256 seniorBps, uint256 insuranceBps) internal {
        Storage storage state = s();
        if (!state.initialized) revert IMLOProfitShareFacet.MLOProfitSplitNotInitialized();
        MLOProfitShareTypes.ProfitSplit memory split = _validatedSplit(makerBps, seniorBps, insuranceBps);
        split.version = state.activeSplit.version + 1;
        uint64 executableAt = uint64(block.timestamp + CONFIG_TIMELOCK);
        uint64 expiresAt = executableAt + CONFIG_EXECUTION_WINDOW;
        state.pendingSplit = MLOProfitShareTypes.PendingProfitSplit({
            split: split, executableAt: executableAt, expiresAt: expiresAt, exists: true
        });
        emit IMLOProfitShareFacet.MLOProfitSplitScheduled(
            split.makerBps, split.seniorBps, split.insuranceBps, split.version, executableAt, expiresAt
        );
    }

    function cancel() internal {
        Storage storage state = s();
        MLOProfitShareTypes.PendingProfitSplit memory pending = state.pendingSplit;
        if (!pending.exists) revert IMLOProfitShareFacet.NoPendingMLOProfitSplit();
        delete state.pendingSplit;
        emit IMLOProfitShareFacet.MLOProfitSplitCancelled(
            pending.split.makerBps, pending.split.seniorBps, pending.split.insuranceBps
        );
    }

    function execute() internal {
        Storage storage state = s();
        MLOProfitShareTypes.PendingProfitSplit memory pending = state.pendingSplit;
        if (!pending.exists) revert IMLOProfitShareFacet.NoPendingMLOProfitSplit();
        if (block.timestamp < pending.executableAt) {
            revert IMLOProfitShareFacet.MLOProfitSplitTimelocked(pending.executableAt);
        }
        if (block.timestamp > pending.expiresAt) {
            revert IMLOProfitShareFacet.MLOProfitSplitExpired(pending.expiresAt);
        }
        state.activeSplit = pending.split;
        delete state.pendingSplit;
        emit IMLOProfitShareFacet.MLOProfitSplitActivated(
            pending.split.makerBps, pending.split.seniorBps, pending.split.insuranceBps, pending.split.version
        );
    }

    function activeSplit() internal view returns (MLOProfitShareTypes.ProfitSplit memory split) {
        Storage storage state = s();
        if (state.initialized) return state.activeSplit;
        split = MLOProfitShareTypes.ProfitSplit({
            makerBps: DEFAULT_MAKER_BPS, seniorBps: DEFAULT_SENIOR_BPS, insuranceBps: DEFAULT_INSURANCE_BPS, version: 1
        });
    }

    function pendingSplit() internal view returns (MLOProfitShareTypes.PendingProfitSplit memory pending) {
        pending = s().pendingSplit;
    }

    function bucketAccount(bytes32 bucketId)
        internal
        view
        returns (MLOProfitShareTypes.BucketProfitAccount memory account)
    {
        account = s().bucketAccounts[bucketId];
    }

    function noteAllocation(bytes32 bucketId, uint256 assets, uint256 expectedVersion) internal {
        MLOProfitShareTypes.BucketProfitAccount storage account = s().bucketAccounts[bucketId];
        if (!account.initialized) {
            MLOProfitShareTypes.ProfitSplit memory split = activeSplit();
            if (expectedVersion != split.version) {
                revert IMLOProfitShareFacet.MLOProfitSplitVersionMismatch(expectedVersion, split.version);
            }
            account.split = split;
            account.initialized = true;
            emit IMLOProfitShareFacet.MLOBucketProfitSplitSnapshotted(
                bucketId,
                account.split.makerBps,
                account.split.seniorBps,
                account.split.insuranceBps,
                account.split.version
            );
        } else if (expectedVersion != account.split.version) {
            revert IMLOProfitShareFacet.MLOProfitSplitVersionMismatch(expectedVersion, account.split.version);
        }
        account.remainingCapitalBasis += assets;
    }

    function previewRelease(bytes32 bucketId, uint256 assets)
        internal
        view
        returns (MLOProfitShareTypes.ProfitRelease memory release)
    {
        MLOProfitShareTypes.BucketProfitAccount storage account = s().bucketAccounts[bucketId];
        if (!account.initialized) revert IMLOProfitShareFacet.MLOProfitAccountNotInitialized(bucketId);
        MLOProfitShareTypes.BucketProfitAccount memory snapshot = account;
        release = _preview(snapshot, assets);
    }

    function applyRelease(bytes32 bucketId, uint256 assets)
        internal
        returns (MLOProfitShareTypes.ProfitRelease memory release)
    {
        MLOProfitShareTypes.BucketProfitAccount storage account = s().bucketAccounts[bucketId];
        if (!account.initialized) revert IMLOProfitShareFacet.MLOProfitAccountNotInitialized(bucketId);
        MLOProfitShareTypes.BucketProfitAccount memory snapshot = account;
        release = _preview(snapshot, assets);
        account.remainingCapitalBasis = release.remainingCapitalBasis;
        account.cumulativeProfitReleased += release.profitRecognized;
    }

    function noteLoss(bytes32 bucketId, uint256 assets) internal {
        MLOProfitShareTypes.BucketProfitAccount storage account = s().bucketAccounts[bucketId];
        if (!account.initialized || assets == 0) return;
        account.lossCarryforward += assets;
    }

    function recognizeProfit(bytes32 bucketId, uint256 assets)
        internal
        returns (MLOProfitShareTypes.ProfitRecognition memory recognition)
    {
        Storage storage state = s();
        MLOProfitShareTypes.BucketProfitAccount storage account = state.bucketAccounts[bucketId];
        if (!account.initialized) revert IMLOProfitShareFacet.MLOProfitAccountNotInitialized(bucketId);

        recognition.grossProfit = assets;
        uint256 recoveredLoss = assets < account.lossCarryforward ? assets : account.lossCarryforward;
        account.lossCarryforward -= recoveredLoss;
        recognition.netProfitRecognized = assets - recoveredLoss;
        account.cumulativeProfitRecognized += recognition.netProfitRecognized;

        (uint256 cumulativeSenior, uint256 cumulativeInsurance) = cumulativeEntitlements(
            account.cumulativeProfitRecognized, account.split.seniorBps, account.split.insuranceBps
        );
        uint256 seniorEntitlement = cumulativeSenior - account.seniorShareSettled;
        uint256 insuranceEntitlement = cumulativeInsurance - account.insuranceShareSettled;
        account.seniorShareSettled = cumulativeSenior;
        account.insuranceShareSettled = cumulativeInsurance;

        LibSeniorCapital.Bucket storage seniorBucket = LibSeniorCapital.s().buckets[bucketId];
        if (seniorEntitlement != 0 && seniorBucket.riskSnapshotSet && seniorBucket.riskSnapshotStored != 0) {
            recognition.seniorRewardFunded = seniorEntitlement;
            account.seniorRewardFunded += seniorEntitlement;
            state.totalSeniorRewardReserve += seniorEntitlement;
        } else {
            recognition.seniorRedirectedToInsurance = seniorEntitlement;
        }
        recognition.insuranceShare = insuranceEntitlement + recognition.seniorRedirectedToInsurance;
        recognition.makerRetained = assets - seniorEntitlement - insuranceEntitlement;
    }

    function cumulativeEntitlements(uint256 profit, uint256 seniorBps, uint256 insuranceBps)
        internal
        pure
        returns (uint256 senior, uint256 insurance)
    {
        uint256 nonMakerBps = seniorBps + insuranceBps;
        uint256 nonMaker = Math.mulDiv(profit, nonMakerBps, BPS_DENOMINATOR);
        if (nonMakerBps == 0) return (0, 0);
        insurance = Math.mulDiv(nonMaker, insuranceBps, nonMakerBps);
        senior = nonMaker - insurance;
    }

    function distributeRecognized(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bucketId,
        MLOProfitShareTypes.ProfitRecognition memory recognition
    ) internal {
        if (recognition.insuranceShare != 0) {
            address insuranceFund = state.mloInsuranceFund;
            if (insuranceFund == address(0)) {
                revert IMLOPredictionAdapterFacet.InvalidMLOInsuranceFund(insuranceFund);
            }
            IERC20(state.marginAsset).forceApprove(insuranceFund, recognition.insuranceShare);
            IMLOInsuranceFund(insuranceFund).notifyProfitShare(bucketId, recognition.insuranceShare);
        }
        emit IMLOProfitShareFacet.MLOProfitRecognized(
            bucketId,
            recognition.grossProfit,
            recognition.netProfitRecognized,
            recognition.makerRetained,
            recognition.seniorRewardFunded,
            recognition.insuranceShare,
            recognition.seniorRedirectedToInsurance
        );
    }

    function rewardView(bytes32 bucketId, address owner)
        internal
        view
        returns (MLOProfitShareTypes.BucketRewardView memory reward)
    {
        Storage storage state = s();
        MLOProfitShareTypes.BucketProfitAccount storage account = state.bucketAccounts[bucketId];
        LibSeniorCapital.Storage storage senior = LibSeniorCapital.s();
        LibSeniorCapital.Bucket storage seniorBucket = senior.buckets[bucketId];
        reward.snapshotVersion = seniorBucket.riskSnapshotVersion;
        reward.snapshotEpoch = seniorBucket.riskSnapshotEpoch;
        reward.snapshotStored = seniorBucket.riskSnapshotStored;
        if (seniorBucket.riskSnapshotSet) {
            reward.eligibleStored = LibSeniorCapital.providerStoredAt(
                senior, owner, seniorBucket.riskSnapshotVersion, seniorBucket.riskSnapshotEpoch
            );
        }
        reward.totalFunded = account.seniorRewardFunded;
        reward.totalClaimed = account.seniorRewardClaimed;
        reward.accountClaimed = state.rewardClaimed[bucketId][owner];
        if (reward.eligibleStored != 0 && reward.snapshotStored != 0) {
            uint256 entitlement = Math.mulDiv(reward.eligibleStored, reward.totalFunded, reward.snapshotStored);
            if (entitlement > reward.accountClaimed) reward.accountClaimable = entitlement - reward.accountClaimed;
        }
    }

    function claimReward(bytes32 bucketId, address owner, address receiver) internal returns (uint256 assets) {
        if (receiver == address(0)) revert IMLOProfitShareFacet.MLOProfitRewardZeroAddress();
        Storage storage state = s();
        MLOProfitShareTypes.BucketProfitAccount storage account = state.bucketAccounts[bucketId];
        MLOProfitShareTypes.BucketRewardView memory reward = rewardView(bucketId, owner);
        assets = reward.accountClaimable;
        if (assets == 0) revert IMLOProfitShareFacet.NoMLOBucketProfitReward(bucketId, owner);
        state.rewardClaimed[bucketId][owner] = reward.accountClaimed + assets;
        account.seniorRewardClaimed += assets;
        state.totalSeniorRewardReserve -= assets;
        IERC20 token = IERC20(LibEveMarket.store().marginAsset);
        uint256 receiverBefore = token.balanceOf(receiver);
        token.safeTransfer(receiver, assets);
        uint256 receiverAfter = token.balanceOf(receiver);
        uint256 received = receiverAfter >= receiverBefore ? receiverAfter - receiverBefore : 0;
        if (received != assets) revert IMLOProfitShareFacet.MLOProfitRewardNonExactTransfer(assets, received);
        emit IMLOProfitShareFacet.MLOBucketProfitRewardClaimed(bucketId, owner, receiver, assets);
    }

    function distribute(address operator, bytes32 bucketId, MLOProfitShareTypes.ProfitRelease memory release) internal {
        emit IMLOProfitShareFacet.MLOProfitDistributed(
            operator,
            bucketId,
            release.grossAssets,
            release.principalReturned,
            release.profitRecognized,
            release.makerCredit,
            release.seniorShare,
            release.insuranceShare,
            release.seniorRedirectedToInsurance
        );
    }

    function _preview(MLOProfitShareTypes.BucketProfitAccount memory account, uint256 assets)
        private
        pure
        returns (MLOProfitShareTypes.ProfitRelease memory release)
    {
        release.grossAssets = assets;
        release.principalReturned = assets < account.remainingCapitalBasis ? assets : account.remainingCapitalBasis;
        release.profitRecognized = assets - release.principalReturned;
        release.remainingCapitalBasis = account.remainingCapitalBasis - release.principalReturned;

        release.makerCredit = assets;
    }

    function _validatedSplit(uint256 makerBps, uint256 seniorBps, uint256 insuranceBps)
        private
        pure
        returns (MLOProfitShareTypes.ProfitSplit memory split)
    {
        if (
            makerBps > BPS_DENOMINATOR || seniorBps > BPS_DENOMINATOR || insuranceBps > BPS_DENOMINATOR
                || makerBps + seniorBps + insuranceBps != BPS_DENOMINATOR
        ) revert IMLOProfitShareFacet.InvalidMLOProfitSplit(makerBps, seniorBps, insuranceBps);
        split = MLOProfitShareTypes.ProfitSplit({
            makerBps: uint16(makerBps), seniorBps: uint16(seniorBps), insuranceBps: uint16(insuranceBps), version: 0
        });
    }
}
