// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {IMarginAccountFacet} from "../interfaces/IMarginAccountFacet.sol";
import {LibEveMarket} from "./LibEveMarket.sol";
import {LibRiskEngine} from "./LibRiskEngine.sol";
import {MarginTypes} from "../types/MarginTypes.sol";

library LibMarginAccount {
    using SafeERC20 for IERC20;

    function marginConfig(LibEveMarket.EveMarketStorage storage state)
        internal
        view
        returns (MarginTypes.MarginConfig memory config)
    {
        config = MarginTypes.MarginConfig({
            marginAsset: state.marginAsset,
            riskManager: state.marginRiskManager,
            warningRiskIncreaseAllowed: state.marginWarningRiskIncreaseAllowed
        });
    }

    function setMarginAsset(LibEveMarket.EveMarketStorage storage state, address asset) internal {
        if (asset == address(0)) {
            revert IMarginAccountFacet.ZeroAddress();
        }
        if (asset.code.length == 0) {
            revert IMarginAccountFacet.ContractHasNoCode(asset);
        }
        if (state.totalMarginLiabilities != 0) {
            revert IMarginAccountFacet.MarginAssetInUse(state.totalMarginLiabilities);
        }

        address previousAsset = state.marginAsset;
        state.marginAsset = asset;

        emit IMarginAccountFacet.MarginAssetSet(previousAsset, asset);
    }

    function setRiskManager(LibEveMarket.EveMarketStorage storage state, address riskManager) internal {
        if (riskManager == address(0)) {
            revert IMarginAccountFacet.ZeroAddress();
        }

        address previousRiskManager = state.marginRiskManager;
        state.marginRiskManager = riskManager;

        emit IMarginAccountFacet.MarginRiskManagerSet(previousRiskManager, riskManager);
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
        _requireAmount(credited);

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

        IERC20(_requireMarginAsset(state)).safeTransfer(receiver, assets);

        emit IMarginAccountFacet.MarginWithdrawn(msg.sender, receiver, assets);
        withdrawn = assets;
    }

    function allocateToBucket(LibEveMarket.EveMarketStorage storage state, bytes32 riskDomainId, uint256 assets)
        internal
        returns (bytes32 bucketId)
    {
        bucketId = allocateToBucketWithKind(state, riskDomainId, assets, MarginTypes.BucketKind.MLO);
    }

    function allocateToBucketWithKind(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 riskDomainId,
        uint256 assets,
        MarginTypes.BucketKind kind
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
            state.marginBucketIds[msg.sender][riskDomainId] = bucketId;

            emit IMarginAccountFacet.MarginBucketCreated(msg.sender, riskDomainId, bucketId);
            emit IMarginAccountFacet.MarginBucketKindSet(bucketId, kind);
        }

        account.freeMargin -= assets;
        account.allocatedMargin += assets;
        bucket.marginAllocated += assets;

        emit IMarginAccountFacet.BucketMarginAllocated(msg.sender, bucketId, assets);
    }

    function releaseFromBucket(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId, uint256 assets) internal {
        _requireAmount(assets);
        MarginTypes.MarginBucket storage bucket = _requireBucket(state, bucketId);
        if (msg.sender != bucket.operator) {
            revert IMarginAccountFacet.NotMarginBucketOperator(msg.sender, bucket.operator);
        }

        _releaseBucketMargin(state, bucket, bucketId, assets);

        MarginTypes.MarginAccount storage account = state.marginAccounts[msg.sender];
        account.allocatedMargin -= assets;
        account.freeMargin += assets;

        emit IMarginAccountFacet.BucketMarginReleased(msg.sender, bucketId, assets);
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

    function reserveRisk(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId, uint256 assets) internal {
        enforceRiskManager(state);
        reserveBucketRiskTrusted(state, bucketId, assets);
    }

    function reserveBucketRiskTrusted(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId, uint256 assets)
        internal
    {
        LibRiskEngine.increaseOpenOrderRisk(state, bucketId, assets);
        emit IMarginAccountFacet.BucketRiskReserved(bucketId, assets);
    }

    function releaseReservedRisk(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId, uint256 assets)
        internal
    {
        enforceRiskManager(state);
        releaseReservedBucketRiskTrusted(state, bucketId, assets);
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

    function activateReservedRisk(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId, uint256 assets)
        internal
    {
        enforceRiskManager(state);
        MarginTypes.MarginBucket storage bucket = _requireBucket(state, bucketId);
        if (assets > bucket.reservedRisk) {
            revert IMarginAccountFacet.InsufficientReservedRisk(bucketId, assets, bucket.reservedRisk);
        }

        LibRiskEngine.moveOpenOrderToPositionRisk(state, bucketId, assets);
        emit IMarginAccountFacet.BucketRiskActivated(bucketId, assets);
    }

    function releaseActiveRisk(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId, uint256 assets) internal {
        enforceRiskManager(state);
        MarginTypes.MarginBucket storage bucket = _requireBucket(state, bucketId);
        if (assets > bucket.activeRisk) {
            revert IMarginAccountFacet.InsufficientActiveRisk(bucketId, assets, bucket.activeRisk);
        }

        LibRiskEngine.releasePositionRisk(state, bucketId, assets);
        emit IMarginAccountFacet.BucketActiveRiskReleased(bucketId, assets);
    }

    function recordProfit(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId, uint256 assets) internal {
        enforceRiskManager(state);
        _requireAmount(assets);
        MarginTypes.MarginBucket storage bucket = _requireBucket(state, bucketId);

        address marginAsset = _requireMarginAsset(state);
        uint256 balanceBefore = IERC20(marginAsset).balanceOf(address(this));
        IERC20(marginAsset).safeTransferFrom(msg.sender, address(this), assets);
        uint256 credited = IERC20(marginAsset).balanceOf(address(this)) - balanceBefore;
        _requireAmount(credited);

        MarginTypes.MarginAccount storage account = state.marginAccounts[bucket.operator];
        account.allocatedMargin += credited;
        account.realizedProfits += credited;
        bucket.marginAllocated += credited;
        bucket.realizedProfits += credited;
        state.totalMarginLiabilities += credited;

        emit IMarginAccountFacet.BucketProfitRecorded(bucketId, credited);
    }

    function recordLoss(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId, uint256 assets) internal {
        enforceRiskManager(state);
        recordLossTrusted(state, bucketId, assets);
    }

    function recordProfitTrusted(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId, uint256 assets)
        internal
    {
        _requireAmount(assets);
        MarginTypes.MarginBucket storage bucket = _requireBucket(state, bucketId);

        MarginTypes.MarginAccount storage account = state.marginAccounts[bucket.operator];
        account.allocatedMargin += assets;
        account.realizedProfits += assets;
        bucket.marginAllocated += assets;
        bucket.realizedProfits += assets;
        state.totalMarginLiabilities += assets;

        emit IMarginAccountFacet.BucketProfitRecorded(bucketId, assets);
    }

    function recordLossTrusted(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId, uint256 assets) internal {
        _requireAmount(assets);
        MarginTypes.MarginBucket storage bucket = _requireBucket(state, bucketId);

        if (assets > bucket.marginAllocated) {
            revert IMarginAccountFacet.InsufficientBucketMargin(bucketId, assets, bucket.marginAllocated);
        }
        bucket.marginAllocated -= assets;

        MarginTypes.MarginAccount storage account = state.marginAccounts[bucket.operator];
        account.allocatedMargin -= assets;
        account.realizedLosses += assets;
        bucket.realizedLosses += assets;
        state.totalMarginLiabilities -= assets;

        emit IMarginAccountFacet.BucketLossRecorded(bucketId, assets);
    }

    function setBucketState(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bucketId,
        MarginTypes.BucketState newState
    ) internal {
        enforceRiskManager(state);
        MarginTypes.MarginBucket storage bucket = _requireBucket(state, bucketId);

        MarginTypes.BucketState previousState = bucket.state;
        bucket.state = newState;

        emit IMarginAccountFacet.BucketStateSet(bucketId, previousState, newState);
    }

    function bucketIdFor(address operator, bytes32 riskDomainId) internal pure returns (bytes32 bucketId) {
        bucketId = keccak256(abi.encodePacked("eve.margin.bucket", operator, riskDomainId));
    }

    function riskDomainForBook(bytes32 bookId) internal pure returns (bytes32 riskDomainId) {
        riskDomainId = keccak256(abi.encodePacked("eve.margin.risk-domain.book", bookId));
    }

    function riskDomainForMarketBook(bytes32 marketId, bytes32 bookId) internal pure returns (bytes32 riskDomainId) {
        riskDomainId = keccak256(abi.encodePacked("eve.margin.risk-domain.market-book", marketId, bookId));
    }

    function _releaseBucketMargin(
        LibEveMarket.EveMarketStorage storage state,
        MarginTypes.MarginBucket storage bucket,
        bytes32 bucketId,
        uint256 assets
    ) private {
        if (assets > bucket.marginAllocated) {
            revert IMarginAccountFacet.InsufficientBucketMargin(bucketId, assets, bucket.marginAllocated);
        }

        LibRiskEngine.accrueConfiguredFunding(state, bucketId);
        uint256 remaining = bucket.marginAllocated - assets;
        LibRiskEngine.enforceInitialMarginAfter(state, bucketId, bucket, 0, assets);

        bucket.marginAllocated = remaining;
    }

    function enforceRiskManager(LibEveMarket.EveMarketStorage storage state) internal view {
        if (msg.sender != state.marginRiskManager) {
            revert IMarginAccountFacet.NotMarginRiskManager(msg.sender);
        }
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
