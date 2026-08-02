// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC1155} from "../../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {IEveIdentity} from "../interfaces/IEveIdentity.sol";
import {IResolverRegistryFacet} from "../interfaces/IResolverRegistryFacet.sol";
import {Errors} from "../libraries/Errors.sol";
import {Events} from "../libraries/Events.sol";
import {LibCLOBBook} from "../libraries/LibCLOBBook.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibReentrancy} from "../libraries/LibReentrancy.sol";
import {LibResolverJury} from "../libraries/LibResolverJury.sol";

contract ResolverRegistryFacet is IResolverRegistryFacet {
    using SafeERC20 for IERC20;

    modifier nonReentrant() {
        LibReentrancy.enter();
        _;
        LibReentrancy.exit();
    }

    function mintIdentity() external override nonReentrant returns (uint256 identityId) {
        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        address identityContract = jury.eveIdentity;
        if (identityContract == address(0)) {
            revert Errors.ZeroAddress();
        }

        LibEveMarket.ResolverJuryConfig storage config = LibEveMarket.store().config.resolverJuryConfig;
        _collectMintFee(config.identityMintFeeToken, config.identityMintFee);

        identityId = IEveIdentity(identityContract).mint(msg.sender);
        jury.identityByOwner[msg.sender] = identityId;
        jury.identities[identityId].lifecycle = LibResolverJury.ResolverLifecycle.Minted;
        jury.resolverRep[identityId].activationTimestamp = uint64(block.timestamp);
    }

    function setCreatorRole(bool enabled) external override {
        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        IEveIdentity identityToken = IEveIdentity(_requireEveIdentity(jury));
        uint256 identityId = identityToken.identityOf(msg.sender);
        if (identityId == 0) {
            revert Errors.NotIdentityOwner(msg.sender);
        }

        _setIdentityRoleFlags(jury, identityToken, identityId, enabled, identityToken.hasResolverRole(identityId));
    }

    function setResolverRole(bool enabled) external override {
        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        IEveIdentity identityToken = IEveIdentity(_requireEveIdentity(jury));
        uint256 identityId = identityToken.identityOf(msg.sender);
        if (identityId == 0) {
            revert Errors.NotIdentityOwner(msg.sender);
        }

        _setIdentityRoleFlags(jury, identityToken, identityId, identityToken.hasCreatorRole(identityId), enabled);
    }

    function _setIdentityRoleFlags(
        LibResolverJury.ResolverJuryStorage storage jury,
        IEveIdentity identityToken,
        uint256 identityId,
        bool creatorRole,
        bool resolverRole
    ) internal {
        LibResolverJury.ResolverIdentityRecord storage record = jury.identities[identityId];
        if (record.lifecycle == LibResolverJury.ResolverLifecycle.None) {
            record.lifecycle = LibResolverJury.ResolverLifecycle.Minted;
        }

        if (!resolverRole && identityToken.hasResolverRole(identityId)) {
            _requireResolverRoleCanDisable(identityId, record);
        }

        identityToken.setRoles(identityId, creatorRole, resolverRole);
    }

    function depositResolverStake(uint256 amount) external override nonReentrant {
        if (amount == 0 || amount > type(uint128).max) {
            revert Errors.InvalidAmount(amount);
        }

        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        IEveIdentity identityToken = IEveIdentity(_requireEveIdentity(jury));
        uint256 identityId = identityToken.identityOf(msg.sender);
        if (identityId == 0) {
            revert Errors.NotIdentityOwner(msg.sender);
        }
        if (!identityToken.hasResolverRole(identityId)) {
            revert Errors.NotResolverRole(identityId);
        }

        LibEveMarket.MarketConfig storage marketConfig = LibEveMarket.store().config;
        if (marketConfig.eveToken == address(0)) {
            revert Errors.ZeroAddress();
        }

        IERC20 eveToken = IERC20(marketConfig.eveToken);
        if (eveToken.balanceOf(msg.sender) < amount || eveToken.allowance(msg.sender, address(this)) < amount) {
            revert Errors.InsufficientResolverStake(uint128(amount), 0);
        }

        LibResolverJury.ResolverIdentityRecord storage record = jury.identities[identityId];
        uint256 nextStake = uint256(record.resolverStake) + amount;
        if (nextStake > type(uint128).max) {
            revert Errors.InvalidAmount(nextStake);
        }
        if (nextStake > marketConfig.resolverJuryConfig.resolverStakeCap) {
            revert Errors.InvalidAmount(nextStake);
        }

        record.resolverStake = uint128(nextStake);
        eveToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Events.ResolverStakeDeposited(identityId, msg.sender, uint128(amount), record.resolverStake);
    }

    function activateResolver() external override {
        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        IEveIdentity identityToken = IEveIdentity(_requireEveIdentity(jury));
        uint256 identityId = LibResolverJury.requireIdentityId(address(identityToken), msg.sender);
        if (!identityToken.hasResolverRole(identityId)) {
            revert Errors.NotResolverRole(identityId);
        }

        LibEveMarket.ResolverJuryConfig storage config = LibEveMarket.store().config.resolverJuryConfig;
        LibResolverJury.ResolverIdentityRecord storage record = jury.identities[identityId];
        if (record.resolverStake < config.resolverStakeRequirement) {
            revert Errors.InsufficientResolverStake(config.resolverStakeRequirement, record.resolverStake);
        }
        if (jury.activeResolverIndex[identityId] == 0 && jury.activeResolverSet.length >= config.resolverPoolCap) {
            revert Errors.ResolverPoolFull(config.resolverPoolCap);
        }
        if (
            record.lifecycle != LibResolverJury.ResolverLifecycle.Minted
                && record.lifecycle != LibResolverJury.ResolverLifecycle.Exited
        ) {
            revert Errors.CannotExitFromState(uint8(record.lifecycle));
        }

        record.activationTimestamp = uint64(block.timestamp);
        record.lifecycle = LibResolverJury.ResolverLifecycle.ResolverPendingActivation;
        _addActiveResolver(jury, identityId);

        emit Events.ResolverActivationRequested(identityId, record.activationTimestamp);
    }

    function requestResolverExit() external override {
        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        IEveIdentity identityToken = IEveIdentity(_requireEveIdentity(jury));
        uint256 identityId = LibResolverJury.requireIdentityId(address(identityToken), msg.sender);
        LibResolverJury.ResolverIdentityRecord storage record = jury.identities[identityId];
        LibResolverJury.ResolverLifecycle lifecycle =
            _effectiveLifecycle(record, LibEveMarket.store().config.resolverJuryConfig);

        if (
            lifecycle != LibResolverJury.ResolverLifecycle.ResolverPendingActivation
                && lifecycle != LibResolverJury.ResolverLifecycle.ResolverActive
        ) {
            revert Errors.CannotExitFromState(uint8(record.lifecycle));
        }

        record.exitTimestamp = uint64(block.timestamp);
        record.lifecycle = LibResolverJury.ResolverLifecycle.ExitCooldown;
        _removeActiveResolver(jury, identityId);

        emit Events.ResolverExitRequested(identityId, record.exitTimestamp);
    }

    function withdrawResolverStake() external override nonReentrant {
        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        IEveIdentity identityToken = IEveIdentity(_requireEveIdentity(jury));
        uint256 identityId = LibResolverJury.requireIdentityId(address(identityToken), msg.sender);
        LibResolverJury.ResolverIdentityRecord storage record = jury.identities[identityId];
        LibEveMarket.ResolverJuryConfig storage config = LibEveMarket.store().config.resolverJuryConfig;

        if (record.lifecycle != LibResolverJury.ResolverLifecycle.ExitCooldown) {
            revert Errors.CannotExitFromState(uint8(record.lifecycle));
        }
        if (block.timestamp < uint256(record.exitTimestamp) + config.exitCooldown) {
            revert Errors.StakeLocked(identityId);
        }
        if (record.slashLockActive && block.timestamp < record.slashLockUntil) {
            revert Errors.StakeLocked(identityId);
        }
        if (record.unresolvedCommittees != 0) {
            revert Errors.StakeLocked(identityId);
        }

        uint128 stake = record.resolverStake;
        if (stake == 0) {
            revert Errors.InvalidAmount(0);
        }
        address eveToken = LibEveMarket.store().config.eveToken;
        if (eveToken == address(0)) {
            revert Errors.ZeroAddress();
        }

        record.resolverStake = 0;
        record.lifecycle = LibResolverJury.ResolverLifecycle.Exited;
        _removeActiveResolver(jury, identityId);
        IERC20(eveToken).safeTransfer(msg.sender, stake);

        emit Events.ResolverStakeWithdrawn(identityId, msg.sender, stake);
    }

    function eveIdentity() external view override returns (address) {
        return LibResolverJury.store().eveIdentity;
    }

    function resolverDashboard(address owner)
        external
        view
        override
        returns (
            IResolverRegistryFacet.ResolverIdentityView memory identity,
            IResolverRegistryFacet.ResolverJuryConfigView memory config,
            IResolverRegistryFacet.ResolverPoolView memory pool
        )
    {
        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        uint256 identityId;
        if (jury.eveIdentity != address(0)) {
            identityId = IEveIdentity(jury.eveIdentity).identityOf(owner);
        }

        identity = _resolverIdentityView(jury, state, identityId);
        config = _resolverJuryConfigView(jury.eveIdentity, state.config.resolverJuryConfig);
        pool = _resolverPoolView(jury, state);
    }

    function resolverIdentity(uint256 identityId)
        external
        view
        override
        returns (IResolverRegistryFacet.ResolverIdentityView memory view_)
    {
        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        view_ = _resolverIdentityView(jury, LibEveMarket.store(), identityId);
    }

    function resolverIdentityByOwner(address owner)
        external
        view
        override
        returns (IResolverRegistryFacet.ResolverIdentityView memory view_)
    {
        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        uint256 identityId;
        if (jury.eveIdentity != address(0)) {
            identityId = IEveIdentity(jury.eveIdentity).identityOf(owner);
        }

        view_ = _resolverIdentityView(jury, LibEveMarket.store(), identityId);
    }

    function resolverJuryConfig()
        external
        view
        override
        returns (IResolverRegistryFacet.ResolverJuryConfigView memory view_)
    {
        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        view_ = _resolverJuryConfigView(jury.eveIdentity, LibEveMarket.store().config.resolverJuryConfig);
    }

    function identityByOwner(address owner) external view override returns (uint256 identityId) {
        address identityContract = LibResolverJury.store().eveIdentity;
        if (identityContract == address(0)) {
            return 0;
        }

        return IEveIdentity(identityContract).identityOf(owner);
    }

    function isEligibleResolver(uint256 identityId, bytes32 disputeId) external view override returns (bool) {
        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        return _isEligibleResolver(jury, LibEveMarket.store(), identityId, disputeId);
    }

    function hasConflict(uint256 identityId, bytes32 marketId) external view override returns (bool) {
        return _hasConflict(LibResolverJury.store(), LibEveMarket.store(), identityId, marketId);
    }

    function resolverLifecycleState(uint256 identityId) external view override returns (uint8) {
        LibResolverJury.ResolverIdentityRecord storage record = LibResolverJury.store().identities[identityId];
        return uint8(_effectiveLifecycle(record, LibEveMarket.store().config.resolverJuryConfig));
    }

    function creatorReputation(uint256 identityId) external view override returns (CreatorReputationView memory view_) {
        LibResolverJury.CreatorReputation storage rep = LibResolverJury.store().creatorRep[identityId];
        view_ = CreatorReputationView({
            marketsCreated: rep.marketsCreated,
            marketsResolved: rep.marketsResolved,
            disputesRaised: rep.disputesRaised,
            outcomesUpheld: rep.outcomesUpheld,
            outcomesOverturned: rep.outcomesOverturned,
            totalVolume: rep.totalVolume,
            cumulativeSettleDelay: rep.cumulativeSettleDelay
        });
    }

    function resolverReputation(uint256 identityId)
        external
        view
        override
        returns (ResolverReputationView memory view_)
    {
        LibResolverJury.ResolverReputation storage rep = LibResolverJury.store().resolverRep[identityId];
        view_ = ResolverReputationView({
            activationTimestamp: rep.activationTimestamp,
            totalSelections: rep.totalSelections,
            commitCount: rep.commitCount,
            revealCount: rep.revealCount,
            missedCommitCount: rep.missedCommitCount,
            missedRevealCount: rep.missedRevealCount,
            invalidRevealCount: rep.invalidRevealCount,
            finalAgreementCount: rep.finalAgreementCount,
            slashCount: rep.slashCount,
            minorityUpheldCount: rep.minorityUpheldCount
        });
    }

    function eligibleResolverCount() external view override returns (uint256 count) {
        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        return _eligibleResolverCount(jury, state);
    }

    function activeResolverCount() external view override returns (uint256) {
        return LibResolverJury.store().activeResolverSet.length;
    }

    function resolverPoolCapacity() external view override returns (uint16) {
        return LibEveMarket.store().config.resolverJuryConfig.resolverPoolCap;
    }

    function resolverPoolMemberAt(uint256 index) external view override returns (uint256 identityId) {
        return LibResolverJury.store().activeResolverSet[index];
    }

    function applyFinalityReputation(bytes32 disputeId, uint8 finalResult) external override {
        if (msg.sender != address(this)) {
            revert Errors.InternalCallOnly(msg.sender);
        }

        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        LibResolverJury.Dispute storage dispute = jury.disputes[disputeId];
        if (dispute.reputationApplied) {
            return;
        }
        if (dispute.marketId == bytes32(0)) {
            revert Errors.MarketNotFound(dispute.marketId);
        }

        dispute.reputationApplied = true;
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();

        _applyCreatorFinalityReputation(jury, state, dispute.marketId, finalResult);
        _applyResolverFinalityReputation(jury, dispute, finalResult);
    }

    function _collectMintFee(address mintFeeToken, uint128 mintFee) internal {
        if (mintFee == 0) {
            return;
        }
        if (mintFeeToken == address(0)) {
            revert Errors.ZeroAddress();
        }

        IERC20 token = IERC20(mintFeeToken);
        if (token.balanceOf(msg.sender) < mintFee || token.allowance(msg.sender, address(this)) < mintFee) {
            revert Errors.MintFeeCollectionFailed();
        }

        token.safeTransferFrom(msg.sender, address(this), mintFee);
    }

    function _resolverIdentityView(
        LibResolverJury.ResolverJuryStorage storage jury,
        LibEveMarket.EveMarketStorage storage state,
        uint256 identityId
    ) internal view returns (IResolverRegistryFacet.ResolverIdentityView memory view_) {
        if (identityId == 0) {
            return view_;
        }

        LibResolverJury.ResolverIdentityRecord storage record = jury.identities[identityId];
        LibEveMarket.ResolverJuryConfig storage config = state.config.resolverJuryConfig;
        address identityContract = jury.eveIdentity;
        address owner;
        bool creatorRole;
        bool resolverRole;
        if (identityContract != address(0)) {
            IEveIdentity identityToken = IEveIdentity(identityContract);
            owner = identityToken.ownerOf(identityId);
            creatorRole = identityToken.hasCreatorRole(identityId);
            resolverRole = identityToken.hasResolverRole(identityId);
        }

        view_ = IResolverRegistryFacet.ResolverIdentityView({
            identityId: identityId,
            owner: owner,
            creatorRole: creatorRole,
            resolverRole: resolverRole,
            lifecycle: uint8(record.lifecycle),
            effectiveLifecycle: uint8(_effectiveLifecycle(record, config)),
            resolverStake: record.resolverStake,
            activationTimestamp: record.activationTimestamp,
            activeAt: _boundedTimestamp(record.activationTimestamp, config.activationDelay),
            exitTimestamp: record.exitTimestamp,
            withdrawableAt: _boundedTimestamp(record.exitTimestamp, config.exitCooldown),
            unresolvedCommittees: record.unresolvedCommittees,
            slashLockUntil: record.slashLockUntil,
            slashLockActive: record.slashLockActive,
            activePoolMember: jury.activeResolverIndex[identityId] != 0,
            globallyEligible: _isEligibleResolver(jury, state, identityId, bytes32(0))
        });
    }

    function _resolverJuryConfigView(address identityContract, LibEveMarket.ResolverJuryConfig storage config)
        internal
        view
        returns (IResolverRegistryFacet.ResolverJuryConfigView memory view_)
    {
        uint256 committeeSizeCount = config.committeeSizesByRound.length;
        uint16[] memory committeeSizes = new uint16[](committeeSizeCount);
        for (uint256 index; index < committeeSizeCount; ++index) {
            committeeSizes[index] = config.committeeSizesByRound[index];
        }

        view_ = IResolverRegistryFacet.ResolverJuryConfigView({
            eveIdentity: identityContract,
            identityMintFeeToken: config.identityMintFeeToken,
            identityMintFee: config.identityMintFee,
            resolverStakeRequirement: config.resolverStakeRequirement,
            resolverStakeCap: config.resolverStakeCap,
            resolverPoolCap: config.resolverPoolCap,
            activationDelay: config.activationDelay,
            exitCooldown: config.exitCooldown,
            participationThresholdBps: config.participationThresholdBps,
            concurrencyLimit: config.concurrencyLimit,
            participationGraceCount: config.participationGraceCount,
            conflictPositionThreshold: config.conflictPositionThreshold,
            committeeSizesByRound: committeeSizes,
            maxAppealRounds: config.maxAppealRounds,
            appealBondMultiplierBps: config.appealBondMultiplierBps,
            randomnessCommitDuration: config.randomnessCommitDuration,
            randomnessRevealDuration: config.randomnessRevealDuration,
            commitDuration: config.commitDuration,
            revealDuration: config.revealDuration,
            appealWindow: config.appealWindow,
            randomnessTimeout: config.randomnessTimeout,
            quorum: config.quorum,
            redrawLimit: config.redrawLimit,
            lowQuorumMode: uint8(config.lowQuorumMode),
            tieBreakMode: uint8(config.tieBreakMode),
            randomnessFailureMode: uint8(config.randomnessFailureMode),
            minRandomnessReveals: config.minRandomnessReveals,
            allEligibleFallbackCap: config.allEligibleFallbackCap,
            missedCommitSlashBps: config.missedCommitSlashBps,
            missedRevealSlashBps: config.missedRevealSlashBps,
            invalidRevealSlashBps: config.invalidRevealSlashBps,
            slashCooldown: config.slashCooldown,
            protocolFeeAllocationBps: config.protocolFeeAllocationBps,
            appealSuccessRoutingBps: config.appealSuccessRoutingBps,
            appealFailureRoutingBps: config.appealFailureRoutingBps,
            incentiveSelectCommittee: config.incentiveSelectCommittee,
            incentiveCloseCommit: config.incentiveCloseCommit,
            incentiveCloseReveal: config.incentiveCloseReveal,
            incentiveOpenAppeal: config.incentiveOpenAppeal,
            incentiveFinalize: config.incentiveFinalize,
            incentiveRandomness: config.incentiveRandomness
        });
    }

    function _resolverPoolView(
        LibResolverJury.ResolverJuryStorage storage jury,
        LibEveMarket.EveMarketStorage storage state
    ) internal view returns (IResolverRegistryFacet.ResolverPoolView memory view_) {
        view_ = IResolverRegistryFacet.ResolverPoolView({
            activeResolverCount: jury.activeResolverSet.length,
            eligibleResolverCount: _eligibleResolverCount(jury, state),
            resolverPoolCapacity: state.config.resolverJuryConfig.resolverPoolCap
        });
    }

    function _eligibleResolverCount(
        LibResolverJury.ResolverJuryStorage storage jury,
        LibEveMarket.EveMarketStorage storage state
    ) internal view returns (uint256 count) {
        uint256 length = jury.activeResolverSet.length;
        for (uint256 index; index < length; ++index) {
            if (_isEligibleResolver(jury, state, jury.activeResolverSet[index], bytes32(0))) {
                ++count;
            }
        }
    }

    function _boundedTimestamp(uint64 timestamp, uint64 delay) internal pure returns (uint64) {
        if (timestamp == 0) {
            return 0;
        }

        uint256 delayed = uint256(timestamp) + delay;
        return delayed > type(uint64).max ? type(uint64).max : uint64(delayed);
    }

    function _requireEveIdentity(LibResolverJury.ResolverJuryStorage storage jury)
        internal
        view
        returns (address identityContract)
    {
        identityContract = jury.eveIdentity;
        if (identityContract == address(0)) {
            revert Errors.ZeroAddress();
        }
    }

    function _requireResolverRoleCanDisable(uint256 identityId, LibResolverJury.ResolverIdentityRecord storage record)
        internal
        view
    {
        if (record.unresolvedCommittees != 0) {
            revert Errors.StakeLocked(identityId);
        }
        if (record.slashLockActive && block.timestamp < record.slashLockUntil) {
            revert Errors.StakeLocked(identityId);
        }
        if (
            record.lifecycle != LibResolverJury.ResolverLifecycle.None
                && record.lifecycle != LibResolverJury.ResolverLifecycle.Minted
                && record.lifecycle != LibResolverJury.ResolverLifecycle.Exited
        ) {
            revert Errors.CannotExitFromState(uint8(record.lifecycle));
        }
    }

    function _effectiveLifecycle(
        LibResolverJury.ResolverIdentityRecord storage record,
        LibEveMarket.ResolverJuryConfig storage config
    ) internal view returns (LibResolverJury.ResolverLifecycle lifecycle) {
        lifecycle = record.lifecycle;
        if (
            lifecycle == LibResolverJury.ResolverLifecycle.ResolverPendingActivation
                && block.timestamp >= uint256(record.activationTimestamp) + config.activationDelay
        ) {
            return LibResolverJury.ResolverLifecycle.ResolverActive;
        }
    }

    function _isEligibleResolver(
        LibResolverJury.ResolverJuryStorage storage jury,
        LibEveMarket.EveMarketStorage storage state,
        uint256 identityId,
        bytes32 disputeId
    ) internal view returns (bool) {
        address identityContract = jury.eveIdentity;
        if (identityContract == address(0) || jury.activeResolverIndex[identityId] == 0) {
            return false;
        }
        if (!IEveIdentity(identityContract).hasResolverRole(identityId)) {
            return false;
        }

        LibResolverJury.ResolverIdentityRecord storage record = jury.identities[identityId];
        LibEveMarket.ResolverJuryConfig storage config = state.config.resolverJuryConfig;
        if (_effectiveLifecycle(record, config) != LibResolverJury.ResolverLifecycle.ResolverActive) {
            return false;
        }
        if (record.resolverStake < config.resolverStakeRequirement) {
            return false;
        }
        if (record.slashLockActive && block.timestamp < record.slashLockUntil) {
            return false;
        }
        if (config.concurrencyLimit != 0 && record.unresolvedCommittees >= config.concurrencyLimit) {
            return false;
        }
        if (!_meetsParticipationThreshold(jury.resolverRep[identityId], config)) {
            return false;
        }

        bytes32 marketId = jury.disputes[disputeId].marketId;
        return marketId == bytes32(0) || !_hasConflict(jury, state, identityId, marketId);
    }

    function _meetsParticipationThreshold(
        LibResolverJury.ResolverReputation storage reputation,
        LibEveMarket.ResolverJuryConfig storage config
    ) internal view returns (bool) {
        if (reputation.totalSelections < config.participationGraceCount) {
            return true;
        }
        if (reputation.totalSelections == 0) {
            return config.participationThresholdBps == 0;
        }
        return uint256(reputation.revealCount) * 10_000
            >= uint256(reputation.totalSelections) * config.participationThresholdBps;
    }

    function _hasConflict(
        LibResolverJury.ResolverJuryStorage storage jury,
        LibEveMarket.EveMarketStorage storage state,
        uint256 identityId,
        bytes32 marketId
    ) internal view returns (bool) {
        address identityContract = jury.eveIdentity;
        if (
            identityContract == address(0) || marketId == bytes32(0)
                || jury.identities[identityId].lifecycle == LibResolverJury.ResolverLifecycle.None
        ) {
            return false;
        }

        address owner = IEveIdentity(identityContract).ownerOf(identityId);
        if (state.markets[marketId].creator == owner && owner != address(0)) {
            return true;
        }

        uint256 threshold = state.config.resolverJuryConfig.conflictPositionThreshold;
        if (threshold == 0) {
            return false;
        }

        LibEveMarket.Market storage market = state.markets[marketId];
        if (market.positionToken == address(0)) {
            return false;
        }
        if (
            market.marketType == LibEveMarket.MarketType.CLOB || market.marketType == LibEveMarket.MarketType.PARIMUTUEL
        ) {
            IERC1155 positionToken = IERC1155(market.positionToken);
            if (
                positionToken.balanceOf(owner, market.yesPositionId) > threshold
                    || positionToken.balanceOf(owner, market.noPositionId) > threshold
            ) {
                return true;
            }
            if (market.marketType == LibEveMarket.MarketType.CLOB) {
                return _hasEscrowedOutcomeInventory(
                    state,
                    owner,
                    _marketBookId(market, marketId, true),
                    marketId,
                    market.positionToken,
                    market.yesPositionId,
                    threshold
                )
                    || _hasEscrowedOutcomeInventory(
                    state,
                    owner,
                    _marketBookId(market, marketId, false),
                    marketId,
                    market.positionToken,
                    market.noPositionId,
                    threshold
                );
            }

            return false;
        }
        if (market.marketType == LibEveMarket.MarketType.MULTI_OUTCOME_ORDERBOOK) {
            IERC1155 positionToken = IERC1155(market.positionToken);
            uint8 outcomeCount = state.multiOutcomeMarkets[marketId].outcomeCount;
            for (uint8 outcome; outcome < outcomeCount; ++outcome) {
                uint256 positionId = state.multiOutcomePositionIds[marketId][outcome];
                if (
                    positionToken.balanceOf(owner, positionId) > threshold
                        || _hasEscrowedOutcomeInventory(
                            state,
                            owner,
                            _multiOutcomeBookId(state, marketId, outcome),
                            marketId,
                            market.positionToken,
                            positionId,
                            threshold
                        )
                ) {
                    return true;
                }
            }
        }

        return false;
    }

    function _hasEscrowedOutcomeInventory(
        LibEveMarket.EveMarketStorage storage state,
        address owner,
        bytes32 bookId,
        bytes32 marketId,
        address positionToken,
        uint256 positionId,
        uint256 threshold
    ) internal view returns (bool) {
        LibEveMarket.Book storage book = state.books[bookId];
        if (
            book.bookId != bookId || book.marketId != marketId || book.assetType != LibEveMarket.BookAssetType.ERC1155
                || book.baseToken != positionToken || book.baseTokenId != positionId
        ) {
            return false;
        }

        uint256 escrowed;
        uint256[] storage curveIds = state.bookCurveIds[bookId];
        uint256 length = curveIds.length;
        for (uint256 index; index < length; ++index) {
            LibEveMarket.StoredCurve storage curve = state.curves[curveIds[index]];
            if (
                curve.active && curve.bookId == bookId && curve.maker == owner
                    && curve.curveSide == LibEveMarket.CurveSide.ASK
            ) {
                escrowed += curve.remainingVolume;
                if (escrowed > threshold) {
                    return true;
                }
            }
        }

        return false;
    }

    function _marketBookId(LibEveMarket.Market storage market, bytes32 marketId, bool isYesSide)
        internal
        view
        returns (bytes32 bookId)
    {
        bookId = isYesSide ? market.yesBookId : market.noBookId;
        if (bookId == bytes32(0)) {
            bookId = LibCLOBBook.marketBookId(marketId, isYesSide);
        }
    }

    function _multiOutcomeBookId(LibEveMarket.EveMarketStorage storage state, bytes32 marketId, uint8 outcome)
        internal
        view
        returns (bytes32 bookId)
    {
        bookId = state.multiOutcomeBookIds[marketId][outcome];
        if (bookId == bytes32(0)) {
            bookId = LibCLOBBook.multiOutcomeBookId(marketId, outcome);
        }
    }

    function _applyCreatorFinalityReputation(
        LibResolverJury.ResolverJuryStorage storage jury,
        LibEveMarket.EveMarketStorage storage state,
        bytes32 marketId,
        uint8 finalResult
    ) internal {
        address creator = state.markets[marketId].creator;
        if (creator == address(0)) {
            return;
        }

        uint256 creatorIdentityId = jury.identityByOwner[creator];
        if (creatorIdentityId == 0) {
            return;
        }

        LibResolverJury.CreatorReputation storage reputation = jury.creatorRep[creatorIdentityId];
        reputation.marketsResolved += 1;
        if (_creatorProposedOutcome(state, marketId) == finalResult) {
            reputation.outcomesUpheld += 1;
        } else {
            reputation.outcomesOverturned += 1;
        }

        emit Events.CreatorReputationUpdated(
            creatorIdentityId,
            reputation.marketsCreated,
            reputation.marketsResolved,
            reputation.disputesRaised,
            reputation.outcomesUpheld,
            reputation.outcomesOverturned
        );
    }

    function _applyResolverFinalityReputation(
        LibResolverJury.ResolverJuryStorage storage jury,
        LibResolverJury.Dispute storage dispute,
        uint8 finalResult
    ) internal {
        uint256 selectedCount = dispute.allSelected.length;
        for (uint256 index; index < selectedCount; ++index) {
            uint256 identityId = dispute.allSelected[index];
            LibResolverJury.ResolverReputation storage reputation = jury.resolverRep[identityId];
            if (_resolverAgreedWithFinalResult(dispute, identityId, finalResult)) {
                reputation.finalAgreementCount += 1;
            }

            emit Events.ResolverReputationUpdated(
                identityId,
                reputation.totalSelections,
                reputation.commitCount,
                reputation.revealCount,
                reputation.finalAgreementCount,
                reputation.slashCount
            );
        }
    }

    function _resolverAgreedWithFinalResult(
        LibResolverJury.Dispute storage dispute,
        uint256 identityId,
        uint8 finalResult
    ) internal view returns (bool) {
        for (uint8 round; round <= dispute.currentRound; ++round) {
            LibResolverJury.DisputeRound storage disputeRound = dispute.rounds[round];
            if (disputeRound.hasRevealed[identityId] && disputeRound.revealedOutcome[identityId] == finalResult) {
                return true;
            }
        }

        return false;
    }

    function _creatorProposedOutcome(LibEveMarket.EveMarketStorage storage state, bytes32 marketId)
        internal
        view
        returns (uint8)
    {
        LibEveMarket.Resolution storage current = state.resolutions[marketId];
        if (current.proposer != address(0)) {
            return current.proposedOutcome;
        }

        LibEveMarket.Resolution[] storage history = state.resolutionHistory[marketId];
        if (history.length == 0) {
            return uint8(LibEveMarket.MarketOutcome.Unresolved);
        }

        return history[history.length - 1].proposedOutcome;
    }

    function _addActiveResolver(LibResolverJury.ResolverJuryStorage storage jury, uint256 identityId) internal {
        if (jury.activeResolverIndex[identityId] != 0) {
            return;
        }

        jury.activeResolverSet.push(identityId);
        jury.activeResolverIndex[identityId] = jury.activeResolverSet.length;
    }

    function _removeActiveResolver(LibResolverJury.ResolverJuryStorage storage jury, uint256 identityId) internal {
        uint256 indexPlusOne = jury.activeResolverIndex[identityId];
        if (indexPlusOne == 0) {
            return;
        }

        uint256 index = indexPlusOne - 1;
        uint256 lastIndex = jury.activeResolverSet.length - 1;
        if (index != lastIndex) {
            uint256 movedIdentityId = jury.activeResolverSet[lastIndex];
            jury.activeResolverSet[index] = movedIdentityId;
            jury.activeResolverIndex[movedIdentityId] = indexPlusOne;
        }

        jury.activeResolverSet.pop();
        delete jury.activeResolverIndex[identityId];
    }
}
