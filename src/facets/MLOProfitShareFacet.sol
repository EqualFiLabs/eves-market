// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IMLOProfitShareFacet} from "../interfaces/IMLOProfitShareFacet.sol";
import {IMarginAccountFacet} from "../interfaces/IMarginAccountFacet.sol";
import {Errors} from "../libraries/Errors.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibGovernanceDelay} from "../libraries/LibGovernanceDelay.sol";
import {LibMLOProfitShare} from "../libraries/LibMLOProfitShare.sol";
import {LibReentrancy} from "../libraries/LibReentrancy.sol";
import {MarginTypes} from "../types/MarginTypes.sol";
import {MLOProfitShareTypes} from "../types/MLOProfitShareTypes.sol";

contract MLOProfitShareFacet is IMLOProfitShareFacet {
    modifier nonReentrant() {
        LibReentrancy.enter();
        _;
        LibReentrancy.exit();
    }

    function initializeMLOProfitSplit(
        uint256 makerBps,
        uint256 seniorBps,
        uint256 insuranceBps,
        uint64 profitSplitDelay
    ) external {
        LibDiamond.enforceIsContractOwnerRaw();
        LibMLOProfitShare.initialize(makerBps, seniorBps, insuranceBps, profitSplitDelay);
    }

    function scheduleMLOProfitSplit(uint256 makerBps, uint256 seniorBps, uint256 insuranceBps) external {
        LibDiamond.enforceIsContractOwnerRaw();
        LibMLOProfitShare.schedule(makerBps, seniorBps, insuranceBps);
    }

    function cancelMLOProfitSplit() external {
        LibDiamond.enforceIsContractOwnerRaw();
        LibMLOProfitShare.cancel();
    }

    function executeMLOProfitSplit() external {
        LibDiamond.enforceIsContractOwnerRaw();
        LibMLOProfitShare.execute();
    }

    function setMLOProfitSplitDelay(uint64 newDelay) external {
        LibDiamond.enforceIsContractOwner();
        if (!LibGovernanceDelay.s().finalized) revert Errors.GovernanceDelayNotFinalized();
        LibMLOProfitShare.setProfitSplitDelay(newDelay);
    }

    function mloProfitSplitDelay() external view returns (uint64) {
        return LibMLOProfitShare.profitSplitDelay();
    }

    function activeMLOProfitSplit() external view returns (MLOProfitShareTypes.ProfitSplit memory split) {
        split = LibMLOProfitShare.activeSplit();
    }

    function pendingMLOProfitSplit() external view returns (MLOProfitShareTypes.PendingProfitSplit memory pending) {
        pending = LibMLOProfitShare.pendingSplit();
    }

    function mloBucketProfitAccount(bytes32 bucketId)
        external
        view
        returns (MLOProfitShareTypes.BucketProfitAccount memory account)
    {
        account = LibMLOProfitShare.bucketAccount(bucketId);
    }

    function previewMLOProfitRelease(bytes32 bucketId, uint256 assets)
        external
        view
        returns (MLOProfitShareTypes.ProfitRelease memory release)
    {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        MarginTypes.MarginBucket storage bucket = state.marginBuckets[bucketId];
        if (!bucket.exists) revert IMarginAccountFacet.MarginBucketNotFound(bucketId);
        if (assets == 0) revert IMarginAccountFacet.ZeroAmount();
        if (assets > bucket.marginAllocated) {
            revert IMarginAccountFacet.InsufficientBucketMargin(bucketId, assets, bucket.marginAllocated);
        }
        release = LibMLOProfitShare.previewRelease(bucketId, assets);
    }

    function mloBucketProfitReward(bytes32 bucketId, address account)
        external
        view
        returns (MLOProfitShareTypes.BucketRewardView memory reward)
    {
        reward = LibMLOProfitShare.rewardView(bucketId, account);
    }

    function claimMLOBucketProfitReward(bytes32 bucketId, address receiver)
        external
        nonReentrant
        returns (uint256 assets)
    {
        assets = LibMLOProfitShare.claimReward(bucketId, msg.sender, receiver);
    }
}
