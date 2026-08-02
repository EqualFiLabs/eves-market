// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {MLOProfitShareTypes} from "../types/MLOProfitShareTypes.sol";

interface IMLOProfitShareFacet {
    error MLOProfitSplitAlreadyInitialized();
    error MLOProfitSplitNotInitialized();
    error InvalidMLOProfitSplit(uint256 makerBps, uint256 seniorBps, uint256 insuranceBps);
    error NoPendingMLOProfitSplit();
    error MLOProfitSplitTimelocked(uint256 executableAt);
    error MLOProfitSplitExpired(uint256 expiresAt);
    error MLOProfitAccountNotInitialized(bytes32 bucketId);
    error MLOProfitSplitVersionMismatch(uint256 expectedVersion, uint256 actualVersion);
    error NoMLOBucketProfitReward(bytes32 bucketId, address account);
    error MLOProfitRewardZeroAddress();
    error MLOProfitRewardNonExactTransfer(uint256 expected, uint256 actual);

    event MLOProfitSplitInitialized(uint16 makerBps, uint16 seniorBps, uint16 insuranceBps, uint64 version);
    event MLOProfitSplitScheduled(
        uint16 makerBps, uint16 seniorBps, uint16 insuranceBps, uint64 version, uint64 executableAt, uint64 expiresAt
    );
    event MLOProfitSplitCancelled(uint16 makerBps, uint16 seniorBps, uint16 insuranceBps);
    event MLOProfitSplitActivated(uint16 makerBps, uint16 seniorBps, uint16 insuranceBps, uint64 version);
    event MLOBucketProfitSplitSnapshotted(
        bytes32 indexed bucketId, uint16 makerBps, uint16 seniorBps, uint16 insuranceBps, uint64 version
    );
    event MLOProfitDistributed(
        address indexed operator,
        bytes32 indexed bucketId,
        uint256 grossAssets,
        uint256 principalReturned,
        uint256 profitRecognized,
        uint256 makerCredit,
        uint256 seniorShare,
        uint256 insuranceShare,
        uint256 seniorRedirectedToInsurance
    );
    event MLOProfitRecognized(
        bytes32 indexed bucketId,
        uint256 grossProfit,
        uint256 netProfitRecognized,
        uint256 makerRetained,
        uint256 seniorRewardFunded,
        uint256 insuranceShare,
        uint256 seniorRedirectedToInsurance
    );
    event MLOBucketProfitRewardClaimed(
        bytes32 indexed bucketId, address indexed account, address indexed receiver, uint256 assets
    );

    function initializeMLOProfitSplit(uint256 makerBps, uint256 seniorBps, uint256 insuranceBps) external;
    function scheduleMLOProfitSplit(uint256 makerBps, uint256 seniorBps, uint256 insuranceBps) external;
    function cancelMLOProfitSplit() external;
    function executeMLOProfitSplit() external;

    function activeMLOProfitSplit() external view returns (MLOProfitShareTypes.ProfitSplit memory split);
    function pendingMLOProfitSplit() external view returns (MLOProfitShareTypes.PendingProfitSplit memory pending);
    function mloBucketProfitAccount(bytes32 bucketId)
        external
        view
        returns (MLOProfitShareTypes.BucketProfitAccount memory account);
    function previewMLOProfitRelease(bytes32 bucketId, uint256 assets)
        external
        view
        returns (MLOProfitShareTypes.ProfitRelease memory release);
    function mloBucketProfitReward(bytes32 bucketId, address account)
        external
        view
        returns (MLOProfitShareTypes.BucketRewardView memory reward);
    function claimMLOBucketProfitReward(bytes32 bucketId, address receiver) external returns (uint256 assets);
}
