// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {LibMarginAccount} from "../../src/libraries/LibMarginAccount.sol";
import {LibRiskEngine} from "../../src/libraries/LibRiskEngine.sol";
import {LibSeniorCapital} from "../../src/libraries/LibSeniorCapital.sol";
import {MarginTypes} from "../../src/types/MarginTypes.sol";
import {IMarginAccountFacet} from "../../src/interfaces/IMarginAccountFacet.sol";

interface IMarginAccountingHarness {
    function reserveBucketRisk(bytes32 bucketId, uint256 assets) external;
    function releaseReservedBucketRisk(bytes32 bucketId, uint256 assets) external;
    function activateReservedBucketRisk(bytes32 bucketId, uint256 assets) external;
    function releaseActiveBucketRisk(bytes32 bucketId, uint256 assets) external;
    function increaseOpenOrderRisk(bytes32 bucketId, uint256 assets) external;
    function releaseOpenOrderRisk(bytes32 bucketId, uint256 assets) external;
    function moveOpenOrderToPositionRisk(bytes32 bucketId, uint256 assets) external;
    function releasePositionRisk(bytes32 bucketId, uint256 assets) external;
    function recordBucketDebt(bytes32 bucketId, uint256 assets) external;
    function repayBucketDebt(bytes32 bucketId, uint256 assets) external;
    function recordBucketUnrealizedPnl(bytes32 bucketId, uint256 profits, uint256 losses) external;
    function recordBucketRecoveryPnl(bytes32 bucketId, uint256 profits, uint256 losses) external;
    function recordBucketBadDebt(bytes32 bucketId, uint256 assets) external;
    function recordBucketProfit(bytes32 bucketId, uint256 assets) external;
    function recordBucketLoss(bytes32 bucketId, uint256 assets) external;
    function snapshotSeniorRiskCohort(bytes32 bucketId, uint256 assets) external;
    function setBucketState(bytes32 bucketId, MarginTypes.BucketState state) external;
}

interface IMarginTestFacet is IMarginAccountFacet, IMarginAccountingHarness {}

contract MarginAccountingHarnessFacet is IMarginAccountingHarness {
    using SafeERC20 for IERC20;

    function reserveBucketRisk(bytes32 bucketId, uint256 assets) external {
        LibMarginAccount.reserveBucketRiskTrusted(LibEveMarket.store(), bucketId, assets);
    }

    function releaseReservedBucketRisk(bytes32 bucketId, uint256 assets) external {
        LibMarginAccount.releaseReservedBucketRiskTrusted(LibEveMarket.store(), bucketId, assets);
    }

    function activateReservedBucketRisk(bytes32 bucketId, uint256 assets) external {
        LibMarginAccount.activateReservedRiskTrusted(LibEveMarket.store(), bucketId, assets);
    }

    function releaseActiveBucketRisk(bytes32 bucketId, uint256 assets) external {
        LibMarginAccount.releaseActiveRiskTrusted(LibEveMarket.store(), bucketId, assets);
    }

    function increaseOpenOrderRisk(bytes32 bucketId, uint256 assets) external {
        LibRiskEngine.increaseOpenOrderRisk(LibEveMarket.store(), bucketId, assets);
    }

    function releaseOpenOrderRisk(bytes32 bucketId, uint256 assets) external {
        LibRiskEngine.releaseOpenOrderRisk(LibEveMarket.store(), bucketId, assets);
    }

    function moveOpenOrderToPositionRisk(bytes32 bucketId, uint256 assets) external {
        LibRiskEngine.moveOpenOrderToPositionRisk(LibEveMarket.store(), bucketId, assets);
    }

    function releasePositionRisk(bytes32 bucketId, uint256 assets) external {
        LibRiskEngine.releasePositionRisk(LibEveMarket.store(), bucketId, assets);
    }

    function recordBucketDebt(bytes32 bucketId, uint256 assets) external {
        LibRiskEngine.recordDebt(LibEveMarket.store(), bucketId, assets);
    }

    function repayBucketDebt(bytes32 bucketId, uint256 assets) external {
        LibRiskEngine.repayDebt(LibEveMarket.store(), bucketId, assets);
    }

    function recordBucketUnrealizedPnl(bytes32 bucketId, uint256 profits, uint256 losses) external {
        LibRiskEngine.recordUnrealizedPnl(LibEveMarket.store(), bucketId, profits, losses);
    }

    function recordBucketRecoveryPnl(bytes32 bucketId, uint256 profits, uint256 losses) external {
        LibRiskEngine.recordRecoveryPnl(LibEveMarket.store(), bucketId, profits, losses);
    }

    function recordBucketBadDebt(bytes32 bucketId, uint256 assets) external {
        LibRiskEngine.recordBadDebt(LibEveMarket.store(), bucketId, assets);
    }

    function recordBucketProfit(bytes32 bucketId, uint256 assets) external {
        IERC20 token = IERC20(LibEveMarket.store().marginAsset);
        token.safeTransferFrom(msg.sender, address(this), assets);
        LibMarginAccount.recordProfitTrusted(LibEveMarket.store(), bucketId, assets);
    }

    function recordBucketLoss(bytes32 bucketId, uint256 assets) external {
        LibMarginAccount.recordLossTrusted(LibEveMarket.store(), bucketId, assets);
    }

    /// @dev Narrow unit-fixture shortcut for snapshotting the production Senior
    /// risk boundary without constructing an MLO quote. Live-flow coverage uses
    /// the adapter reservation path instead.
    function snapshotSeniorRiskCohort(bytes32 bucketId, uint256 assets) external {
        LibSeniorCapital.Storage storage senior = LibSeniorCapital.s();
        LibSeniorCapital.reserveCapital(senior, bucketId, assets);
        LibSeniorCapital.releaseReservedCapital(senior, bucketId, assets);
    }

    function setBucketState(bytes32 bucketId, MarginTypes.BucketState state) external {
        MarginTypes.MarginBucket storage bucket = LibRiskEngine.requireBucket(LibEveMarket.store(), bucketId);
        MarginTypes.BucketState previous = bucket.state;
        bucket.state = state;
        emit IMarginAccountFacet.BucketStateSet(bucketId, previous, state);
    }
}

library MarginAccountingHarnessSelectors {
    function production() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](34);
        selectors[0] = IMarginAccountFacet.marginConfig.selector;
        selectors[1] = IMarginAccountFacet.depositMargin.selector;
        selectors[2] = IMarginAccountFacet.withdrawMargin.selector;
        selectors[3] = IMarginAccountFacet.allocateBucketMargin.selector;
        selectors[4] = IMarginAccountFacet.allocateBucketMarginWithKind.selector;
        selectors[5] = IMarginAccountFacet.releaseBucketMargin.selector;
        selectors[6] = IMarginAccountFacet.getMarginAccount.selector;
        selectors[7] = IMarginAccountFacet.getMarginBucket.selector;
        selectors[8] = IMarginAccountFacet.getBucketRisk.selector;
        selectors[9] = IMarginAccountFacet.bucketHealth.selector;
        selectors[10] = IMarginAccountFacet.riskParamsForBucket.selector;
        selectors[11] = IMarginAccountFacet.defaultRiskParams.selector;
        selectors[12] = IMarginAccountFacet.riskDomainRiskParams.selector;
        selectors[13] = IMarginAccountFacet.bucketLockedRisk.selector;
        selectors[14] = IMarginAccountFacet.bucketIdFor.selector;
        selectors[15] = IMarginAccountFacet.riskDomainForBook.selector;
        selectors[16] = IMarginAccountFacet.riskDomainForMarket.selector;
        selectors[17] = IMarginAccountFacet.canBucketIncreaseRisk.selector;
        selectors[18] = IMarginAccountFacet.canBucketIncreaseRiskForBook.selector;
        selectors[19] = IMarginAccountFacet.riskDomainOracleConfig.selector;
        selectors[20] = IMarginAccountFacet.riskDomainMarkConfig.selector;
        selectors[21] = IMarginAccountFacet.riskDomainRiskMark.selector;
        selectors[22] = IMarginAccountFacet.riskDomainFundingConfig.selector;
        selectors[23] = IMarginAccountFacet.defaultFundingConfig.selector;
        selectors[24] = IMarginAccountFacet.setMarginAsset.selector;
        selectors[25] = IMarginAccountFacet.setWarningRiskIncreaseAllowed.selector;
        selectors[26] = IMarginAccountFacet.setRiskDomainOracleConfig.selector;
        selectors[27] = IMarginAccountFacet.setRiskDomainMarkConfig.selector;
        selectors[28] = IMarginAccountFacet.setRiskDomainFundingConfig.selector;
        selectors[29] = IMarginAccountFacet.setDefaultFundingConfig.selector;
        selectors[30] = IMarginAccountFacet.setDefaultRiskParams.selector;
        selectors[31] = IMarginAccountFacet.setRiskDomainRiskParams.selector;
        selectors[32] = IMarginAccountFacet.clearRiskDomainRiskParams.selector;
        selectors[33] = IMarginAccountFacet.accrueBucketFundingNow.selector;
    }

    function harness() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](17);
        selectors[0] = IMarginAccountingHarness.reserveBucketRisk.selector;
        selectors[1] = IMarginAccountingHarness.releaseReservedBucketRisk.selector;
        selectors[2] = IMarginAccountingHarness.activateReservedBucketRisk.selector;
        selectors[3] = IMarginAccountingHarness.releaseActiveBucketRisk.selector;
        selectors[4] = IMarginAccountingHarness.increaseOpenOrderRisk.selector;
        selectors[5] = IMarginAccountingHarness.releaseOpenOrderRisk.selector;
        selectors[6] = IMarginAccountingHarness.moveOpenOrderToPositionRisk.selector;
        selectors[7] = IMarginAccountingHarness.releasePositionRisk.selector;
        selectors[8] = IMarginAccountingHarness.recordBucketDebt.selector;
        selectors[9] = IMarginAccountingHarness.repayBucketDebt.selector;
        selectors[10] = IMarginAccountingHarness.recordBucketUnrealizedPnl.selector;
        selectors[11] = IMarginAccountingHarness.recordBucketRecoveryPnl.selector;
        selectors[12] = IMarginAccountingHarness.recordBucketBadDebt.selector;
        selectors[13] = IMarginAccountingHarness.recordBucketProfit.selector;
        selectors[14] = IMarginAccountingHarness.recordBucketLoss.selector;
        selectors[15] = IMarginAccountingHarness.setBucketState.selector;
        selectors[16] = IMarginAccountingHarness.snapshotSeniorRiskCohort.selector;
    }
}
