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
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibReentrancy} from "../libraries/LibReentrancy.sol";
import {LibResolverJury} from "../libraries/LibResolverJury.sol";
import {LibResolverRewards} from "../libraries/LibResolverRewards.sol";

contract ResolverRegistryFacet is IResolverRegistryFacet {
    using SafeERC20 for IERC20;

    uint256 internal constant EPOCH_BLOCKHASH_LOOKUP_WINDOW = 256;

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
        _collectMintFee(config.identityMintFeeToken, LibEveMarket.store().config.eveTreasury, config.identityMintFee);

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
        if (nextStake > marketConfig.resolverJuryConfig.resolverSeatStake) {
            revert Errors.InvalidAmount(nextStake);
        }

        record.resolverStake = uint128(nextStake);
        eveToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Events.ResolverStakeDeposited(identityId, msg.sender, uint128(amount), record.resolverStake);
    }

    function openResolverEpochRotation() external override returns (uint64 epochId) {
        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        LibEveMarket.ResolverJuryConfig storage config = LibEveMarket.store().config.resolverJuryConfig;
        epochId = jury.currentResolverEpoch + 1;
        LibResolverJury.ResolverEpoch storage epoch = jury.resolverEpochs[epochId];
        if (epoch.rotationOpenedAt != 0) {
            revert Errors.ResolverEpochClosed(epochId);
        }
        if (jury.currentResolverEpoch == 0) {
            LibDiamond.enforceIsContractOwner();
        } else {
            LibResolverJury.ResolverEpoch storage current = jury.resolverEpochs[jury.currentResolverEpoch];
            if (block.timestamp + config.resolverRotationWindow < current.endTime) {
                revert Errors.ResolverEpochNotReady(epochId);
            }
        }

        uint64 startTime = jury.currentResolverEpoch == 0
            ? uint64(block.timestamp)
            : jury.resolverEpochs[jury.currentResolverEpoch].endTime;
        epoch.epochId = epochId;
        epoch.startTime = startTime;
        epoch.endTime = uint64(uint256(startTime) + config.resolverEpochDuration);
        epoch.rotationOpenedAt = uint64(block.timestamp);
        epoch.commitDeadline = uint64(block.timestamp + config.epochRandomnessCommitDuration);

        emit Events.ResolverEpochRotationOpened(
            epochId, epoch.startTime, epoch.endTime, epoch.commitDeadline, epoch.revealDeadline, epoch.selectionDeadline
        );
    }

    function optIntoResolverEpoch(bytes32 randomnessCommitment) external override returns (uint64 epochId) {
        if (randomnessCommitment == bytes32(0)) {
            revert Errors.InvalidConfigValue("randomnessCommitment");
        }

        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        IEveIdentity identityToken = IEveIdentity(_requireEveIdentity(jury));
        uint256 identityId = LibResolverJury.requireIdentityId(address(identityToken), msg.sender);
        _requireResolverCandidate(jury, identityToken, identityId);

        epochId = jury.currentResolverEpoch + 1;
        LibResolverJury.ResolverEpoch storage epoch = jury.resolverEpochs[epochId];
        _requireEpochCommitOpen(epoch, epochId);

        LibResolverJury.ResolverEpochCandidate storage candidate = epoch.candidateByIdentity[identityId];
        if (candidate.optedIn) {
            revert Errors.ResolverEpochCandidateExists(epochId, identityId);
        }
        _collectEpochCandidateFee(epochId, identityId, LibEveMarket.store().config);

        candidate.optedIn = true;
        candidate.randomness.commitment = randomnessCommitment;
        candidate.randomness.hasCommitted = true;
        epoch.candidates.push(identityId);
        jury.identities[identityId].activationTimestamp = uint64(block.timestamp);
        jury.identities[identityId].lifecycle = LibResolverJury.ResolverLifecycle.ResolverCandidate;

        emit Events.ResolverEpochCandidateOptedIn(epochId, identityId);
    }

    function commitResolverEpochRandomness(uint64 epochId, bytes32 randomnessCommitment) external override {
        if (randomnessCommitment == bytes32(0)) {
            revert Errors.InvalidConfigValue("randomnessCommitment");
        }

        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        IEveIdentity identityToken = IEveIdentity(_requireEveIdentity(jury));
        uint256 identityId = LibResolverJury.requireIdentityId(address(identityToken), msg.sender);
        if (!_isCurrentEpochMember(jury, identityId)) {
            revert Errors.ResolverNotActive(identityId);
        }

        LibResolverJury.ResolverEpoch storage epoch = jury.resolverEpochs[epochId];
        _requireEpochCommitOpen(epoch, epochId);
        LibResolverJury.ResolverEpochRandomness storage randomness = epoch.activeRandomness[identityId];
        if (randomness.hasCommitted) {
            revert Errors.AlreadyCommitted(identityId);
        }

        randomness.commitment = randomnessCommitment;
        randomness.hasCommitted = true;
    }

    function closeResolverEpochRandomnessCommit(uint64 epochId) external override {
        LibResolverJury.ResolverEpoch storage epoch = LibResolverJury.store().resolverEpochs[epochId];
        if (epoch.rotationOpenedAt == 0 || block.timestamp <= epoch.commitDeadline) {
            revert Errors.ResolverEpochNotReady(epochId);
        }
        if (epoch.randomnessReferenceBlock != 0) {
            revert Errors.ResolverEpochClosed(epochId);
        }

        LibEveMarket.ResolverJuryConfig storage config = LibEveMarket.store().config.resolverJuryConfig;
        epoch.randomnessReferenceBlock = uint64(block.number + 1);
        epoch.revealDeadline = uint64(block.timestamp + config.epochRandomnessRevealDuration);
        epoch.selectionDeadline = uint64(uint256(epoch.revealDeadline) + config.epochSelectionDuration);
    }

    function revealResolverEpochRandomness(uint64 epochId, bytes32 value, bytes32 salt) external override {
        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        IEveIdentity identityToken = IEveIdentity(_requireEveIdentity(jury));
        uint256 identityId = LibResolverJury.requireIdentityId(address(identityToken), msg.sender);
        LibResolverJury.ResolverEpoch storage epoch = jury.resolverEpochs[epochId];
        if (
            epoch.randomnessReferenceBlock == 0 || block.timestamp > epoch.revealDeadline || epoch.seedFinalized
                || epoch.selectionFinalized
        ) {
            revert Errors.ResolverEpochNotReady(epochId);
        }
        LibResolverJury.ResolverEpochRandomness storage randomness =
            _epochRandomnessForIdentity(jury, epoch, identityId);
        if (!randomness.hasCommitted) {
            revert Errors.ResolverEpochCandidateMissing(epochId, identityId);
        }
        if (randomness.hasRevealed) {
            revert Errors.AlreadyRevealed(identityId);
        }
        bytes32 expected = keccak256(abi.encode(epochId, identityId, value, salt));
        if (expected != randomness.commitment) {
            revert Errors.JuryCommitmentMismatch(identityId);
        }

        randomness.hasRevealed = true;
        randomness.revealedValue = value;
        epoch.validRevealCount += 1;
        epoch.randomnessAccumulator = keccak256(abi.encode(epoch.randomnessAccumulator, identityId, value));

        emit Events.ResolverEpochRandomnessRevealed(epochId, identityId);
    }

    function finalizeResolverEpochSeed(uint64 epochId) external override returns (bytes32 seed) {
        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        LibResolverJury.ResolverEpoch storage epoch = jury.resolverEpochs[epochId];
        LibEveMarket.ResolverJuryConfig storage config = LibEveMarket.store().config.resolverJuryConfig;
        if (epoch.seedFinalized) {
            revert Errors.ResolverEpochAlreadyFinalized(epochId);
        }
        if (epoch.randomnessReferenceBlock == 0 || block.timestamp <= epoch.revealDeadline) {
            revert Errors.ResolverEpochNotReady(epochId);
        }

        if (epoch.seedReferenceBlock == 0) {
            epoch.seedReferenceBlock = uint64(block.number + 1);
            emit Events.ResolverEpochSeedReferenceBlockSet(epochId, epoch.seedReferenceBlock);
            return bytes32(0);
        }
        if (block.number <= epoch.seedReferenceBlock) {
            revert Errors.ResolverEpochNotReady(epochId);
        }
        if (block.number > uint256(epoch.seedReferenceBlock) + EPOCH_BLOCKHASH_LOOKUP_WINDOW) {
            revert Errors.ResolverEpochNotReady(epochId);
        }

        _slashMissedEpochRandomnessDuties(jury, epoch, epochId, config);

        bytes32 referenceHash = blockhash(epoch.seedReferenceBlock);
        seed = keccak256(
            abi.encode(
                epoch.randomnessAccumulator,
                epochId,
                block.chainid,
                address(this),
                referenceHash,
                epoch.candidates.length
            )
        );
        epoch.seed = seed;
        epoch.seedFinalized = true;

        emit Events.ResolverEpochSeedFinalized(epochId, seed, epoch.validRevealCount);
    }

    function submitResolverEpochCandidateScore(uint64 epochId, uint256 identityId)
        external
        override
        returns (uint256 score)
    {
        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        LibResolverJury.ResolverEpoch storage epoch = jury.resolverEpochs[epochId];
        LibEveMarket.ResolverJuryConfig storage config = LibEveMarket.store().config.resolverJuryConfig;
        if (!epoch.seedFinalized || block.timestamp > epoch.selectionDeadline || epoch.selectionFinalized) {
            revert Errors.ResolverEpochNotReady(epochId);
        }

        LibResolverJury.ResolverEpochCandidate storage candidate = epoch.candidateByIdentity[identityId];
        if (!candidate.optedIn) {
            revert Errors.ResolverEpochCandidateMissing(epochId, identityId);
        }
        if (candidate.scoreSubmitted) {
            revert Errors.ResolverEpochScoreSubmitted(epochId, identityId);
        }
        if (!_isSelectableEpochCandidate(jury, config, identityId)) {
            revert Errors.ResolverEpochCandidateIneligible(epochId, identityId);
        }

        score = uint256(keccak256(abi.encode(epoch.seed, epochId, identityId)));
        candidate.score = score;
        candidate.scoreSubmitted = true;
        epoch.scoreSubmittedCount += 1;
        _pruneEpochSelection(jury, epoch, config);
        _insertEpochSelection(epoch, identityId, score, config.activeEpochSize);

        emit Events.ResolverEpochCandidateScoreSubmitted(epochId, identityId, score);
    }

    function finalizeResolverEpochSelection(uint64 epochId) external override {
        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        LibResolverJury.ResolverEpoch storage epoch = jury.resolverEpochs[epochId];
        if (!epoch.seedFinalized || block.timestamp <= epoch.selectionDeadline) {
            revert Errors.ResolverEpochNotReady(epochId);
        }
        if (epoch.selectionFinalized) {
            revert Errors.ResolverEpochAlreadyFinalized(epochId);
        }
        LibEveMarket.ResolverJuryConfig storage config = LibEveMarket.store().config.resolverJuryConfig;
        _pruneEpochSelection(jury, epoch, config);
        if (epoch.selected.length != config.activeEpochSize) {
            revert Errors.ResolverEpochUnderfilled(epochId, epoch.selected.length, config.activeEpochSize);
        }

        uint256 selectedCount = epoch.selected.length;
        uint256[] memory selected = new uint256[](selectedCount);
        for (uint256 index; index < selectedCount; ++index) {
            uint256 identityId = epoch.selected[index].identityId;
            selected[index] = identityId;
            epoch.candidateByIdentity[identityId].selected = true;
        }
        epoch.selectionFinalized = true;

        emit Events.ResolverEpochSelectionFinalized(epochId, selected);
        if (jury.currentResolverEpoch == 0) {
            _activateResolverEpoch(jury, epoch, epochId);
        }
    }

    function activateFinalizedResolverEpoch(uint64 epochId) external override {
        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        if (epochId != jury.currentResolverEpoch + 1) {
            revert Errors.ResolverEpochNotReady(epochId);
        }
        if (jury.currentResolverEpoch != 0 && block.timestamp < jury.resolverEpochs[jury.currentResolverEpoch].endTime)
        {
            revert Errors.ResolverEpochNotReady(epochId);
        }

        LibResolverJury.ResolverEpoch storage epoch = jury.resolverEpochs[epochId];
        if (!epoch.selectionFinalized) {
            revert Errors.ResolverEpochNotReady(epochId);
        }
        _activateResolverEpoch(jury, epoch, epochId);
    }

    function finalizeResolverTradingRewards(uint64 epochId, address token)
        external
        override
        nonReentrant
        returns (uint128 amount)
    {
        amount = LibResolverRewards.finalizeTradingRewards(epochId, token);
    }

    function claimResolverRewards(address token) external override nonReentrant returns (uint128 amount) {
        if (token == address(0)) {
            revert Errors.ZeroAddress();
        }

        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        uint256 identityId = LibResolverJury.requireIdentityId(_requireEveIdentity(jury), msg.sender);
        (,, amount) = LibResolverRewards.claimable(identityId, token);
        LibResolverRewards.recordClaim(identityId, token, amount);
        IERC20(token).safeTransfer(msg.sender, amount);

        emit Events.ResolverRewardsClaimed(identityId, msg.sender, token, amount);
    }

    function _requireResolverCandidate(
        LibResolverJury.ResolverJuryStorage storage jury,
        IEveIdentity identityToken,
        uint256 identityId
    ) internal view {
        if (!identityToken.hasResolverRole(identityId)) {
            revert Errors.NotResolverRole(identityId);
        }
        LibEveMarket.ResolverJuryConfig storage config = LibEveMarket.store().config.resolverJuryConfig;
        LibResolverJury.ResolverIdentityRecord storage record = jury.identities[identityId];
        if (record.resolverStake != config.resolverSeatStake) {
            revert Errors.InsufficientResolverStake(config.resolverSeatStake, record.resolverStake);
        }
    }

    function requestResolverExit() external override {
        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        IEveIdentity identityToken = IEveIdentity(_requireEveIdentity(jury));
        uint256 identityId = LibResolverJury.requireIdentityId(address(identityToken), msg.sender);
        LibResolverJury.ResolverIdentityRecord storage record = jury.identities[identityId];
        LibResolverJury.ResolverLifecycle lifecycle =
            _effectiveLifecycle(record, LibEveMarket.store().config.resolverJuryConfig);

        if (
            lifecycle != LibResolverJury.ResolverLifecycle.ResolverCandidate
                && lifecycle != LibResolverJury.ResolverLifecycle.ResolverActive
                && lifecycle != LibResolverJury.ResolverLifecycle.Minted
        ) {
            revert Errors.CannotExitFromState(uint8(record.lifecycle));
        }
        if (_isSelectedForLockedEpoch(jury, identityId)) {
            revert Errors.StakeLocked(identityId);
        }

        record.exitTimestamp = uint64(block.timestamp);
        record.lifecycle = LibResolverJury.ResolverLifecycle.ExitCooldown;

        emit Events.ResolverExitRequested(identityId, record.exitTimestamp);
    }

    function withdrawResolverStake() external override nonReentrant {
        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        IEveIdentity identityToken = IEveIdentity(_requireEveIdentity(jury));
        uint256 identityId = LibResolverJury.requireIdentityId(address(identityToken), msg.sender);
        LibResolverJury.ResolverIdentityRecord storage record = jury.identities[identityId];
        LibEveMarket.ResolverJuryConfig storage config = LibEveMarket.store().config.resolverJuryConfig;

        bool unselectedCandidateWithdraw = _canWithdrawUnselectedCandidate(jury, identityId);
        if (record.lifecycle != LibResolverJury.ResolverLifecycle.ExitCooldown && !unselectedCandidateWithdraw) {
            revert Errors.CannotExitFromState(uint8(record.lifecycle));
        }
        if (!unselectedCandidateWithdraw && block.timestamp < uint256(record.exitTimestamp) + config.exitCooldown) {
            revert Errors.StakeLocked(identityId);
        }
        if (record.slashLockActive && block.timestamp < record.slashLockUntil) {
            revert Errors.StakeLocked(identityId);
        }
        if (record.unresolvedCommittees != 0) {
            revert Errors.StakeLocked(identityId);
        }
        if (_isSelectedForLockedEpoch(jury, identityId)) {
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
            IResolverRegistryFacet.ResolverEpochPoolView memory epochPool
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
        epochPool = _resolverEpochPoolView(jury, state);
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
        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        return jury.resolverEpochs[jury.currentResolverEpoch].activeSet.length;
    }

    function activeResolverEpochSize() external view override returns (uint16) {
        return LibEveMarket.store().config.resolverJuryConfig.activeEpochSize;
    }

    function activeResolverAt(uint256 index) external view override returns (uint256 identityId) {
        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        return jury.resolverEpochs[jury.currentResolverEpoch].activeSet[index];
    }

    function currentResolverEpoch() external view override returns (uint64) {
        return LibResolverJury.store().currentResolverEpoch;
    }

    function resolverEpoch(uint64 epochId)
        external
        view
        override
        returns (IResolverRegistryFacet.ResolverEpochView memory view_)
    {
        LibResolverJury.ResolverEpoch storage epoch = LibResolverJury.store().resolverEpochs[epochId];
        view_ = IResolverRegistryFacet.ResolverEpochView({
            epochId: epoch.epochId,
            startTime: epoch.startTime,
            endTime: epoch.endTime,
            rotationOpenedAt: epoch.rotationOpenedAt,
            commitDeadline: epoch.commitDeadline,
            revealDeadline: epoch.revealDeadline,
            selectionDeadline: epoch.selectionDeadline,
            seedReferenceBlock: epoch.seedReferenceBlock,
            validRevealCount: epoch.validRevealCount,
            seed: epoch.seed,
            seedFinalized: epoch.seedFinalized,
            selectionFinalized: epoch.selectionFinalized,
            candidateCount: epoch.candidates.length,
            scoreSubmittedCount: epoch.scoreSubmittedCount,
            selectedCount: epoch.selected.length,
            activeCount: epoch.activeSet.length
        });
    }

    function resolverEpochCandidate(uint64 epochId, uint256 identityId)
        external
        view
        override
        returns (IResolverRegistryFacet.ResolverEpochCandidateView memory view_)
    {
        LibResolverJury.ResolverEpochCandidate storage candidate =
            LibResolverJury.store().resolverEpochs[epochId].candidateByIdentity[identityId];
        view_ = IResolverRegistryFacet.ResolverEpochCandidateView({
            optedIn: candidate.optedIn,
            selected: candidate.selected,
            scoreSubmitted: candidate.scoreSubmitted,
            score: candidate.score,
            hasCommitted: candidate.randomness.hasCommitted,
            hasRevealed: candidate.randomness.hasRevealed
        });
    }

    function previewResolverRewards(uint256 identityId, address token)
        external
        view
        override
        returns (uint128 accrued, uint128 claimed, uint128 claimable)
    {
        return LibResolverRewards.claimable(identityId, token);
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

    function _collectMintFee(address mintFeeToken, address treasury, uint128 mintFee) internal {
        if (mintFee == 0) {
            return;
        }
        if (mintFeeToken == address(0) || treasury == address(0)) {
            revert Errors.ZeroAddress();
        }

        IERC20 token = IERC20(mintFeeToken);
        if (token.balanceOf(msg.sender) < mintFee || token.allowance(msg.sender, address(this)) < mintFee) {
            revert Errors.MintFeeCollectionFailed();
        }

        token.safeTransferFrom(msg.sender, treasury, mintFee);
    }

    function _collectEpochCandidateFee(
        uint64 epochId,
        uint256 identityId,
        LibEveMarket.MarketConfig storage marketConfig
    ) internal {
        uint128 feeAmount = marketConfig.resolverJuryConfig.epochCandidateFeeAmount;
        if (epochId == 1 || feeAmount == 0) {
            return;
        }
        address feeToken = marketConfig.resolverJuryConfig.epochCandidateFeeToken;
        address treasury = marketConfig.eveTreasury;
        if (feeToken == address(0) || treasury == address(0)) {
            revert Errors.ZeroAddress();
        }

        IERC20(feeToken).safeTransferFrom(msg.sender, treasury, feeAmount);
        emit Events.ResolverEpochCandidateFeePaid(epochId, identityId, feeToken, feeAmount);
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
            currentEpochMember: _isCurrentEpochMember(jury, identityId),
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
            resolverSeatStake: config.resolverSeatStake,
            epochCandidateFeeToken: config.epochCandidateFeeToken,
            epochCandidateFeeAmount: config.epochCandidateFeeAmount,
            activeEpochSize: config.activeEpochSize,
            resolverEpochDuration: config.resolverEpochDuration,
            resolverRotationWindow: config.resolverRotationWindow,
            epochRandomnessCommitDuration: config.epochRandomnessCommitDuration,
            epochRandomnessRevealDuration: config.epochRandomnessRevealDuration,
            epochSelectionDuration: config.epochSelectionDuration,
            minEpochRandomnessReveals: config.minEpochRandomnessReveals,
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

    function _resolverEpochPoolView(
        LibResolverJury.ResolverJuryStorage storage jury,
        LibEveMarket.EveMarketStorage storage state
    ) internal view returns (IResolverRegistryFacet.ResolverEpochPoolView memory view_) {
        view_ = IResolverRegistryFacet.ResolverEpochPoolView({
            currentEpochId: jury.currentResolverEpoch,
            activeResolverCount: jury.resolverEpochs[jury.currentResolverEpoch].activeSet.length,
            eligibleResolverCount: _eligibleResolverCount(jury, state),
            activeEpochSize: state.config.resolverJuryConfig.activeEpochSize
        });
    }

    function _eligibleResolverCount(
        LibResolverJury.ResolverJuryStorage storage jury,
        LibEveMarket.EveMarketStorage storage state
    ) internal view returns (uint256 count) {
        uint256 length = jury.resolverEpochs[jury.currentResolverEpoch].activeSet.length;
        for (uint256 index; index < length; ++index) {
            if (_isEligibleResolver(
                    jury, state, jury.resolverEpochs[jury.currentResolverEpoch].activeSet[index], bytes32(0)
                )) {
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
            lifecycle == LibResolverJury.ResolverLifecycle.ResolverCandidate
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
        if (identityContract == address(0) || !_isCurrentEpochMember(jury, identityId)) {
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
        if (record.resolverStake != config.resolverSeatStake) {
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

    function _requireEpochCommitOpen(LibResolverJury.ResolverEpoch storage epoch, uint64 epochId) internal view {
        if (epoch.rotationOpenedAt == 0 || block.timestamp > epoch.commitDeadline || epoch.seedFinalized) {
            revert Errors.ResolverEpochClosed(epochId);
        }
    }

    function _epochRandomnessForIdentity(
        LibResolverJury.ResolverJuryStorage storage jury,
        LibResolverJury.ResolverEpoch storage epoch,
        uint256 identityId
    ) internal view returns (LibResolverJury.ResolverEpochRandomness storage randomness) {
        if (_isCurrentEpochMember(jury, identityId)) {
            LibResolverJury.ResolverEpochRandomness storage activeRandomness = epoch.activeRandomness[identityId];
            if (activeRandomness.hasCommitted && !activeRandomness.hasRevealed) {
                return activeRandomness;
            }
        }
        LibResolverJury.ResolverEpochCandidate storage candidate = epoch.candidateByIdentity[identityId];
        if (candidate.optedIn) {
            return candidate.randomness;
        }
        return candidate.randomness;
    }

    function _pruneEpochSelection(
        LibResolverJury.ResolverJuryStorage storage jury,
        LibResolverJury.ResolverEpoch storage epoch,
        LibEveMarket.ResolverJuryConfig storage config
    ) internal {
        uint256 index;
        while (index < epoch.selected.length) {
            uint256 identityId = epoch.selected[index].identityId;
            if (_isSelectableEpochCandidate(jury, config, identityId)) {
                ++index;
                continue;
            }

            epoch.selectedIdentity[identityId] = false;
            epoch.candidateByIdentity[identityId].selected = false;

            uint256 lastIndex = epoch.selected.length - 1;
            if (index != lastIndex) {
                epoch.selected[index] = epoch.selected[lastIndex];
            }
            epoch.selected.pop();
        }
    }

    function _isSelectableEpochCandidate(
        LibResolverJury.ResolverJuryStorage storage jury,
        LibEveMarket.ResolverJuryConfig storage config,
        uint256 identityId
    ) internal view returns (bool) {
        address identityContract = jury.eveIdentity;
        if (identityContract == address(0) || !IEveIdentity(identityContract).hasResolverRole(identityId)) {
            return false;
        }

        LibResolverJury.ResolverIdentityRecord storage record = jury.identities[identityId];
        if (record.resolverStake != config.resolverSeatStake) {
            return false;
        }
        if (record.slashLockActive && block.timestamp < record.slashLockUntil) {
            return false;
        }

        return true;
    }

    function _insertEpochSelection(
        LibResolverJury.ResolverEpoch storage epoch,
        uint256 identityId,
        uint256 score,
        uint16 activeEpochSize
    ) internal {
        if (epoch.selectedIdentity[identityId]) {
            return;
        }

        if (epoch.selected.length < activeEpochSize) {
            epoch.selected.push(LibResolverJury.ResolverEpochSelection({identityId: identityId, score: score}));
            epoch.selectedIdentity[identityId] = true;
            return;
        }

        uint256 worstIndex;
        uint256 worstScore = epoch.selected[0].score;
        for (uint256 index = 1; index < epoch.selected.length; ++index) {
            if (epoch.selected[index].score > worstScore) {
                worstScore = epoch.selected[index].score;
                worstIndex = index;
            }
        }

        if (score >= worstScore) {
            return;
        }

        uint256 removedIdentityId = epoch.selected[worstIndex].identityId;
        epoch.selectedIdentity[removedIdentityId] = false;
        epoch.selected[worstIndex] = LibResolverJury.ResolverEpochSelection({identityId: identityId, score: score});
        epoch.selectedIdentity[identityId] = true;
    }

    function _slashMissedEpochRandomnessDuties(
        LibResolverJury.ResolverJuryStorage storage jury,
        LibResolverJury.ResolverEpoch storage epoch,
        uint64 epochId,
        LibEveMarket.ResolverJuryConfig storage config
    ) internal {
        if (jury.currentResolverEpoch == 0) {
            return;
        }

        LibResolverJury.ResolverEpoch storage current = jury.resolverEpochs[jury.currentResolverEpoch];
        uint256 activeCount = current.activeSet.length;
        for (uint256 index; index < activeCount; ++index) {
            uint256 identityId = current.activeSet[index];
            LibResolverJury.ResolverEpochRandomness storage randomness = epoch.activeRandomness[identityId];
            if (!randomness.hasCommitted) {
                jury.resolverRep[identityId].missedCommitCount += 1;
                _slashEpochDuty(jury, epochId, identityId, config.missedCommitSlashBps, config, 1);
            } else if (!randomness.hasRevealed) {
                jury.resolverRep[identityId].missedRevealCount += 1;
                _slashEpochDuty(jury, epochId, identityId, config.missedRevealSlashBps, config, 2);
            }
        }
    }

    function _slashEpochDuty(
        LibResolverJury.ResolverJuryStorage storage jury,
        uint64 epochId,
        uint256 identityId,
        uint16 slashBps,
        LibEveMarket.ResolverJuryConfig storage config,
        uint8 duty
    ) internal {
        if (slashBps == 0 || slashBps > 10_000) {
            revert Errors.InvalidConfigValue("slashBps");
        }

        LibResolverJury.ResolverIdentityRecord storage record = jury.identities[identityId];
        uint128 slashAmount = uint128((uint256(record.resolverStake) * slashBps) / 10_000);
        if (slashAmount != 0) {
            record.resolverStake -= slashAmount;
            LibResolverRewards.distributeSlashedStake(identityId, LibEveMarket.store().config.eveToken, slashAmount);
        }
        record.slashLockActive = true;
        record.slashLockUntil = uint64(block.timestamp + config.slashCooldown);
        jury.resolverRep[identityId].slashCount += 1;

        emit Events.ResolverEpochDutySlashed(epochId, identityId, slashAmount, duty);
    }

    function _activateResolverEpoch(
        LibResolverJury.ResolverJuryStorage storage jury,
        LibResolverJury.ResolverEpoch storage epoch,
        uint64 epochId
    ) internal {
        uint256 selectedCount = epoch.selected.length;
        LibEveMarket.ResolverJuryConfig storage config = LibEveMarket.store().config.resolverJuryConfig;
        if (selectedCount != config.activeEpochSize) {
            revert Errors.ResolverEpochUnderfilled(epochId, selectedCount, config.activeEpochSize);
        }

        uint256[] memory activeSet = new uint256[](selectedCount);
        for (uint256 index; index < selectedCount; ++index) {
            uint256 identityId = epoch.selected[index].identityId;
            if (!_isSelectableEpochCandidate(jury, config, identityId)) {
                revert Errors.ResolverEpochCandidateIneligible(epochId, identityId);
            }
            if (epoch.activeIndex[identityId] == 0) {
                epoch.activeSet.push(identityId);
                epoch.activeIndex[identityId] = epoch.activeSet.length;
            }
            jury.identities[identityId].lifecycle = LibResolverJury.ResolverLifecycle.ResolverActive;
            activeSet[index] = identityId;
        }
        jury.currentResolverEpoch = epochId;
        epoch.compliantActiveCount = uint16(selectedCount);

        emit Events.ResolverEpochActivated(epochId, activeSet);
    }

    function _isCurrentEpochMember(LibResolverJury.ResolverJuryStorage storage jury, uint256 identityId)
        internal
        view
        returns (bool)
    {
        return jury.resolverEpochs[jury.currentResolverEpoch].activeIndex[identityId] != 0;
    }

    function _canWithdrawUnselectedCandidate(LibResolverJury.ResolverJuryStorage storage jury, uint256 identityId)
        internal
        view
        returns (bool)
    {
        uint64 currentEpochId = jury.currentResolverEpoch;
        if (_isUnselectedFinalizedCandidate(jury.resolverEpochs[currentEpochId], identityId)) {
            return true;
        }
        return _isUnselectedFinalizedCandidate(jury.resolverEpochs[currentEpochId + 1], identityId);
    }

    function _isUnselectedFinalizedCandidate(LibResolverJury.ResolverEpoch storage epoch, uint256 identityId)
        internal
        view
        returns (bool)
    {
        return epoch.selectionFinalized && epoch.candidateByIdentity[identityId].optedIn
            && !epoch.selectedIdentity[identityId] && epoch.activeIndex[identityId] == 0;
    }

    function _isSelectedForLockedEpoch(LibResolverJury.ResolverJuryStorage storage jury, uint256 identityId)
        internal
        view
        returns (bool)
    {
        uint64 currentEpochId = jury.currentResolverEpoch;
        if (currentEpochId != 0 && jury.resolverEpochs[currentEpochId].activeIndex[identityId] != 0) {
            return true;
        }
        LibResolverJury.ResolverEpoch storage nextEpoch = jury.resolverEpochs[currentEpochId + 1];
        if (!nextEpoch.selectionFinalized && nextEpoch.candidateByIdentity[identityId].optedIn) {
            return true;
        }
        return nextEpoch.selectionFinalized && nextEpoch.selectedIdentity[identityId];
    }
}
