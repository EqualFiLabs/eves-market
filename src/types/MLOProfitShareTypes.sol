// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

library MLOProfitShareTypes {
    struct ProfitSplit {
        uint16 makerBps;
        uint16 seniorBps;
        uint16 insuranceBps;
        uint64 version;
    }

    struct PendingProfitSplit {
        ProfitSplit split;
        uint256 executableAt;
        uint256 expiresAt;
        bool exists;
    }

    struct BucketProfitAccount {
        ProfitSplit split;
        uint256 remainingCapitalBasis;
        uint256 cumulativeProfitReleased;
        uint256 seniorShareSettled;
        uint256 insuranceShareSettled;
        bool initialized;
        uint256 cumulativeProfitRecognized;
        uint256 lossCarryforward;
        uint256 seniorRewardFunded;
        uint256 seniorRewardClaimed;
    }

    struct ProfitRecognition {
        uint256 grossProfit;
        uint256 netProfitRecognized;
        uint256 makerRetained;
        uint256 seniorRewardFunded;
        uint256 insuranceShare;
        uint256 seniorRedirectedToInsurance;
    }

    struct BucketRewardView {
        uint64 snapshotVersion;
        uint64 snapshotEpoch;
        uint256 snapshotStored;
        uint256 eligibleStored;
        uint256 totalFunded;
        uint256 totalClaimed;
        uint256 accountClaimed;
        uint256 accountClaimable;
    }

    struct ProfitRelease {
        uint256 grossAssets;
        uint256 principalReturned;
        uint256 profitRecognized;
        uint256 makerCredit;
        uint256 seniorShare;
        uint256 insuranceShare;
        uint256 seniorRedirectedToInsurance;
        uint256 remainingCapitalBasis;
    }
}
