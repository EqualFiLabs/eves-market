// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {IMarginAccountFacet} from "../interfaces/IMarginAccountFacet.sol";
import {IMLOProfitShareFacet} from "../interfaces/IMLOProfitShareFacet.sol";
import {LibEveMarket} from "./LibEveMarket.sol";
import {LibRiskEngine} from "./LibRiskEngine.sol";
import {LibMLOProfitShare} from "./LibMLOProfitShare.sol";
import {MarginTypes} from "../types/MarginTypes.sol";
import {MLOProfitShareTypes} from "../types/MLOProfitShareTypes.sol";

library LibMarginAccount {
    using SafeERC20 for IERC20;

    function marginConfig(LibEveMarket.EveMarketStorage storage state)
        internal
        view
        returns (MarginTypes.MarginConfig memory config)
    {
        config = MarginTypes.MarginConfig({
            marginAsset: state.marginAsset, warningRiskIncreaseAllowed: state.marginWarningRiskIncreaseAllowed
        });
    }

    function setMarginAsset(LibEveMarket.EveMarketStorage storage state, address asset) internal {
        if (asset == address(0)) {
            revert IMarginAccountFacet.ZeroAddress();
        }
        if (asset.code.length == 0) {
            revert IMarginAccountFacet.ContractHasNoCode(asset);
        }
        address previousAsset = state.marginAsset;
        if (previousAsset != address(0)) {
            if (previousAsset != asset) revert IMarginAccountFacet.MarginAssetImmutable(previousAsset, asset);
            return;
        }
        state.marginAsset = asset;

        emit IMarginAccountFacet.MarginAssetSet(previousAsset, asset);
    }

    function setWarningRiskIncreaseAllowed(LibEveMarket.EveMarketStorage storage state, bool allowed) internal {
        state.marginWarningRiskIncreaseAllowed = allowed;

        emit IMarginAccountFacet.WarningRiskIncreaseAllowedSet(allowed);
    }

    function deposit(LibEveMarket.EveMarketStorage storage state, uint256 assets, address receiver)
        internal
        returns (uint256 credited)
    {
        _requireAmount(assets);
        if (receiver == address(0)) {
            revert IMarginAccountFacet.ZeroAddress();
        }

        address marginAsset = _requireMarginAsset(state);
        uint256 balanceBefore = IERC20(marginAsset).balanceOf(address(this));
        IERC20(marginAsset).safeTransferFrom(msg.sender, address(this), assets);
        credited = IERC20(marginAsset).balanceOf(address(this)) - balanceBefore;
        if (credited != assets) revert IMarginAccountFacet.NonExactMarginTransfer(assets, credited);

        MarginTypes.MarginAccount storage account = state.marginAccounts[receiver];
        account.depositedMargin += credited;
        account.freeMargin += credited;
        state.totalMarginLiabilities += credited;

        emit IMarginAccountFacet.MarginDeposited(msg.sender, receiver, credited);
    }

    function withdraw(LibEveMarket.EveMarketStorage storage state, uint256 assets, address receiver)
        internal
        returns (uint256 withdrawn)
    {
        _requireAmount(assets);
        if (receiver == address(0)) {
            revert IMarginAccountFacet.ZeroAddress();
        }

        MarginTypes.MarginAccount storage account = state.marginAccounts[msg.sender];
        if (assets > account.freeMargin) {
            revert IMarginAccountFacet.InsufficientFreeMargin(msg.sender, assets, account.freeMargin);
        }

        account.freeMargin -= assets;
        account.withdrawnMargin += assets;
        state.totalMarginLiabilities -= assets;

        IERC20 token = IERC20(_requireMarginAsset(state));
        uint256 receiverBefore = token.balanceOf(receiver);
        token.safeTransfer(receiver, assets);
        uint256 receiverAfter = token.balanceOf(receiver);
        uint256 received = receiverAfter >= receiverBefore ? receiverAfter - receiverBefore : 0;
        if (received != assets) revert IMarginAccountFacet.NonExactMarginTransfer(assets, received);

        emit IMarginAccountFacet.MarginWithdrawn(msg.sender, receiver, assets);
        withdrawn = assets;
    }

    function allocateToBucket(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 riskDomainId,
        uint256 assets,
        uint256 expectedSplitVersion
    ) internal returns (bytes32 bucketId) {
        bucketId = allocateToBucketWithKind(
            state, riskDomainId, assets, MarginTypes.BucketKind.MLO, expectedSplitVersion
        );
    }

    function allocateToBucketWithKind(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 riskDomainId,
        uint256 assets,
        MarginTypes.BucketKind kind,
        uint256 expectedSplitVersion
    ) internal returns (bytes32 bucketId) {
        _requireAmount(assets);
        _requireRiskDomain(riskDomainId);

        MarginTypes.MarginAccount storage account = state.marginAccounts[msg.sender];
        if (assets > account.freeMargin) {
            revert IMarginAccountFacet.InsufficientFreeMargin(msg.sender, assets, account.freeMargin);
        }

        bucketId = bucketIdFor(msg.sender, riskDomainId);
        MarginTypes.MarginBucket storage bucket = state.marginBuckets[bucketId];
        if (!bucket.exists) {
            bucket.exists = true;
            bucket.operator = msg.sender;
            bucket.riskDomainId = riskDomainId;
            bucket.kind = kind;
            bucket.state = MarginTypes.BucketState.Healthy;
            bucket.fundingIndexWad = LibRiskEngine.initializeRiskDomainFunding(state, riskDomainId, kind);
            state.marginBucketIds[msg.sender][riskDomainId] = bucketId;

            emit IMarginAccountFacet.MarginBucketCreated(msg.sender, riskDomainId, bucketId);
            emit IMarginAccountFacet.MarginBucketKindSet(bucketId, kind);
        }

        account.freeMargin -= assets;
        account.allocatedMargin += assets;
        bucket.marginAllocated += assets;

        if (bucket.kind == MarginTypes.BucketKind.MLO) {
            LibMLOProfitShare.noteAllocation(bucketId, assets, expectedSplitVersion);
        } else if (expectedSplitVersion != 0) {
            revert IMLOProfitShareFacet.MLOProfitSplitVersionMismatch(expectedSplitVersion, 0);
        }

        if (bucket.kind == MarginTypes.BucketKind.MLO) LibRiskEngine.synchronizeMLOState(state, bucketId);

        emit IMarginAccountFacet.BucketMarginAllocated(msg.sender, bucketId, assets);
    }

    function releaseFromBucket(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId, uint256 assets)
        internal
        returns (MLOProfitShareTypes.ProfitRelease memory release)
    {
        _requireAmount(assets);
        MarginTypes.MarginBucket storage bucket = _requireBucket(state, bucketId);
        if (msg.sender != bucket.operator) {
            revert IMarginAccountFacet.NotMarginBucketOperator(msg.sender, bucket.operator);
        }
        bool closed = bucket.state == MarginTypes.BucketState.Closed;
        if (bucket.kind == MarginTypes.BucketKind.MLO && !closed) LibRiskEngine.synchronizeMLOState(state, bucketId);
        if (
            bucket.state == MarginTypes.BucketState.Liquidatable || bucket.state == MarginTypes.BucketState.Recovering
                || (closed && bucket.kind != MarginTypes.BucketKind.MLO)
        ) revert IMarginAccountFacet.BucketMarginFrozen(bucketId, bucket.state);

        if (closed) {
            uint256 locked = LibRiskEngine.lockedRisk(state, bucketId);
            if (locked == 0) locked = bucket.reservedRisk + bucket.activeRisk;
            if (locked != 0) revert IMarginAccountFacet.ClosedBucketHasObligations(bucketId, locked);
        }

        _releaseBucketMargin(state, bucket, bucketId, assets, closed);

        MarginTypes.MarginAccount storage account = state.marginAccounts[msg.sender];
        account.allocatedMargin -= assets;

        if (bucket.kind == MarginTypes.BucketKind.MLO) {
            release = LibMLOProfitShare.applyRelease(bucketId, assets);
        } else {
            release.grossAssets = assets;
            release.principalReturned = assets;
            release.makerCredit = assets;
        }
        account.freeMargin += release.makerCredit;
        state.totalMarginLiabilities -= assets - release.makerCredit;

        emit IMarginAccountFacet.BucketMarginReleased(msg.sender, bucketId, assets);
        if (bucket.kind == MarginTypes.BucketKind.MLO) {
            LibMLOProfitShare.distribute(msg.sender, bucketId, release);
        }
    }

    function canIncreaseRisk(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId)
        internal
        view
        returns (bool)
    {
        return LibRiskEngine.canIncreaseRisk(state, bucketId);
    }

    function canIncreaseRiskForBook(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId, bytes32 bookId)
        internal
        view
        returns (bool)
    {
        return LibRiskEngine.canIncreaseRiskForBook(state, bucketId, bookId);
    }

    function reserveBucketRiskTrusted(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId, uint256 assets)
        internal
    {
        LibRiskEngine.increaseOpenOrderRisk(state, bucketId, assets);
        emit IMarginAccountFacet.BucketRiskReserved(bucketId, assets);
    }

    function releaseReservedBucketRiskTrusted(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bucketId,
        uint256 assets
    ) internal {
        MarginTypes.MarginBucket storage bucket = _requireBucket(state, bucketId);
        if (assets > bucket.reservedRisk) {
            revert IMarginAccountFacet.InsufficientReservedRisk(bucketId, assets, bucket.reservedRisk);
        }
        LibRiskEngine.releaseOpenOrderRisk(state, bucketId, assets);
        emit IMarginAccountFacet.BucketReservedRiskReleased(bucketId, assets);
    }

    function activateReservedRiskTrusted(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId, uint256 assets)
        internal
    {
        MarginTypes.MarginBucket storage bucket = _requireBucket(state, bucketId);
        if (assets > bucket.reservedRisk) {
            revert IMarginAccountFacet.InsufficientReservedRisk(bucketId, assets, bucket.reservedRisk);
        }

        LibRiskEngine.moveOpenOrderToPositionRisk(state, bucketId, assets);
        emit IMarginAccountFacet.BucketRiskActivated(bucketId, assets);
    }

    function releaseActiveRiskTrusted(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId, uint256 assets)
        internal
    {
        MarginTypes.MarginBucket storage bucket = _requireBucket(state, bucketId);
        if (assets > bucket.activeRisk) {
            revert IMarginAccountFacet.InsufficientActiveRisk(bucketId, assets, bucket.activeRisk);
        }

        LibRiskEngine.releasePositionRisk(state, bucketId, assets);
        emit IMarginAccountFacet.BucketActiveRiskReleased(bucketId, assets);
    }

    function recordProfitTrusted(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId, uint256 assets)
        internal
    {
        _requireAmount(assets);
        MarginTypes.MarginBucket storage bucket = _requireBucket(state, bucketId);
        MLOProfitShareTypes.ProfitRecognition memory recognition;
        uint256 marginCredit = assets;
        if (bucket.kind == MarginTypes.BucketKind.MLO) {
            recognition = LibMLOProfitShare.recognizeProfit(bucketId, assets);
            marginCredit = recognition.makerRetained;
        }

        MarginTypes.MarginAccount storage account = state.marginAccounts[bucket.operator];
        account.allocatedMargin += marginCredit;
        account.realizedProfits += assets;
        bucket.marginAllocated += marginCredit;
        bucket.realizedProfits += assets;
        state.totalMarginLiabilities += marginCredit;

        emit IMarginAccountFacet.BucketProfitRecorded(bucketId, assets);
        if (bucket.kind == MarginTypes.BucketKind.MLO) {
            LibMLOProfitShare.distributeRecognized(state, bucketId, recognition);
        }
    }

    function recordLossTrusted(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId, uint256 assets) internal {
        _requireAmount(assets);
        MarginTypes.MarginBucket storage bucket = _requireBucket(state, bucketId);

        if (assets > bucket.marginAllocated) {
            revert IMarginAccountFacet.InsufficientBucketMargin(bucketId, assets, bucket.marginAllocated);
        }
        bucket.marginAllocated -= assets;
        if (bucket.kind == MarginTypes.BucketKind.MLO) LibMLOProfitShare.noteLoss(bucketId, assets);

        MarginTypes.MarginAccount storage account = state.marginAccounts[bucket.operator];
        account.allocatedMargin -= assets;
        account.realizedLosses += assets;
        bucket.realizedLosses += assets;
        state.totalMarginLiabilities -= assets;

        emit IMarginAccountFacet.BucketLossRecorded(bucketId, assets);
    }

    function payFundingFromMarginTrusted(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bucketId,
        uint256 maxAssets
    ) internal returns (uint256 paid) {
        MarginTypes.MarginBucket storage bucket = _requireBucket(state, bucketId);
        LibRiskEngine.accrueConfiguredFunding(state, bucketId);
        paid = maxAssets < bucket.fundingLiability ? maxAssets : bucket.fundingLiability;
        if (paid > bucket.marginAllocated) paid = bucket.marginAllocated;
        if (paid == 0) return 0;

        bucket.marginAllocated -= paid;
        MarginTypes.MarginAccount storage account = state.marginAccounts[bucket.operator];
        account.allocatedMargin -= paid;
        state.totalMarginLiabilities -= paid;
        LibRiskEngine.recordFundingPayment(state, bucketId, paid);
    }

    function bucketIdFor(address operator, bytes32 riskDomainId) internal pure returns (bytes32 bucketId) {
        bucketId = keccak256(abi.encodePacked("eve.margin.bucket", operator, riskDomainId));
    }

    function riskDomainForBook(bytes32 bookId) internal pure returns (bytes32 riskDomainId) {
        riskDomainId = keccak256(abi.encodePacked("eve.margin.risk-domain.book", bookId));
    }

    function riskDomainForMarket(bytes32 marketId) internal pure returns (bytes32 riskDomainId) {
        riskDomainId = keccak256(abi.encodePacked("eve.margin.risk-domain.market", marketId));
    }

    function _releaseBucketMargin(
        LibEveMarket.EveMarketStorage storage state,
        MarginTypes.MarginBucket storage bucket,
        bytes32 bucketId,
        uint256 assets,
        bool closed
    ) private {
        if (assets > bucket.marginAllocated) {
            revert IMarginAccountFacet.InsufficientBucketMargin(bucketId, assets, bucket.marginAllocated);
        }

        if (!closed) LibRiskEngine.accrueConfiguredFunding(state, bucketId);
        uint256 remaining = bucket.marginAllocated - assets;
        if (!closed) LibRiskEngine.enforceInitialMarginAfter(state, bucketId, bucket, 0, assets);

        bucket.marginAllocated = remaining;
    }

    function _requireBucket(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId)
        private
        view
        returns (MarginTypes.MarginBucket storage bucket)
    {
        bucket = state.marginBuckets[bucketId];
        if (!bucket.exists) {
            revert IMarginAccountFacet.MarginBucketNotFound(bucketId);
        }
    }

    function _requireMarginAsset(LibEveMarket.EveMarketStorage storage state)
        private
        view
        returns (address marginAsset)
    {
        marginAsset = state.marginAsset;
        if (marginAsset == address(0)) {
            revert IMarginAccountFacet.MarginAssetNotSet();
        }
    }

    function _requireRiskDomain(bytes32 riskDomainId) private pure {
        if (riskDomainId == bytes32(0)) {
            revert IMarginAccountFacet.InvalidRiskDomain(riskDomainId);
        }
    }

    function _requireAmount(uint256 assets) private pure {
        if (assets == 0) {
            revert IMarginAccountFacet.ZeroAmount();
        }
    }
}
