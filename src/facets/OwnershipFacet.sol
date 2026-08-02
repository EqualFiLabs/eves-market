// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IEveIdentity} from "../interfaces/IEveIdentity.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {LibCollateralProfile} from "../libraries/LibCollateralProfile.sol";
import {LibDelayedOrderConfigAdmin} from "../libraries/LibDelayedOrderConfigAdmin.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibMarketConfigAdmin} from "../libraries/LibMarketConfigAdmin.sol";
import {LibResolverJuryConfigAdmin} from "../libraries/LibResolverJuryConfigAdmin.sol";
import {Errors} from "../libraries/Errors.sol";
import {Events} from "../libraries/Events.sol";
import {LibResolverJury} from "../libraries/LibResolverJury.sol";
import {OwnershipConfigTypes} from "../types/OwnershipConfigTypes.sol";

contract OwnershipFacet {
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event StaticsDollarRailSet(address indexed core, uint256 indexed profileId, address indexed usdcToken);
    event ParimutuelConfigSet(address indexed shareToken, uint16 entryFeeBps, uint128 minEntry);
    event ResolutionBondConfigSet(
        address indexed previousBondToken,
        address indexed newBondToken,
        uint128 previousL1Amount,
        uint128 newL1Amount,
        uint128 previousL2Amount,
        uint128 newL2Amount
    );
    event MarketCreationFeeSet(uint128 previousMarketCreationFee, uint128 newMarketCreationFee);
    event ParimutuelCreationSeedAmountSet(
        uint128 previousParimutuelCreationSeedAmount, uint128 newParimutuelCreationSeedAmount
    );
    event SpotBookCreationFeeSet(uint128 previousSpotBookCreationFee, uint128 newSpotBookCreationFee);
    event ComboMarketCreationFeeSet(uint128 previousComboMarketCreationFee, uint128 newComboMarketCreationFee);
    event MarketCreationBondSet(uint128 previousMarketCreationBond, uint128 newMarketCreationBond);
    event PermissionlessCreationSet(bool previousEnabled, bool newEnabled);
    event DefaultConditionalTokensSet(
        address indexed previousDefaultConditionalTokens, address indexed newDefaultConditionalTokens
    );
    event EvesPositionManagerSet(address indexed previousEvesPositionManager, address indexed newEvesPositionManager);
    event CollateralTokenSet(address indexed previousCollateralToken, address indexed newCollateralToken);
    event CollateralProfileSet(
        uint8 indexed profileId,
        address indexed collateralToken,
        address indexed wrapperToken,
        uint128 payoutUnit,
        uint128 marketCreationFee,
        bool enabled
    );
    event CollateralProfileEnabledSet(uint8 indexed profileId, bool previousEnabled, bool newEnabled);
    event CollateralProfilePayoutUnitSet(uint8 indexed profileId, uint128 previousPayoutUnit, uint128 newPayoutUnit);
    event CollateralProfileMarketCreationFeeSet(
        uint8 indexed profileId, uint128 previousMarketCreationFee, uint128 newMarketCreationFee
    );
    event CollateralProfileParimutuelCreationSeedAmountSet(
        uint8 indexed profileId, uint128 previousParimutuelCreationSeedAmount, uint128 newParimutuelCreationSeedAmount
    );
    event CollateralProfileParimutuelMinEntrySet(
        uint8 indexed profileId, uint128 previousParimutuelMinEntry, uint128 newParimutuelMinEntry
    );
    event CollateralProfileParlayUnderwritingFeeSet(
        uint8 indexed profileId, uint128 previousParlayUnderwritingFee, uint128 newParlayUnderwritingFee
    );
    event EveTokenSet(address indexed previousEveToken, address indexed newEveToken);
    event EveTreasurySet(address indexed previousEveTreasury, address indexed newEveTreasury);
    event DurationParamsSet(
        uint64 previousMinMarketDuration,
        uint64 newMinMarketDuration,
        uint64 previousMaxMarketDuration,
        uint64 newMaxMarketDuration
    );
    event DisputeWindowSet(uint64 previousDisputeWindow, uint64 newDisputeWindow);
    event CreatorSettleGraceSet(uint64 previousCreatorSettleGrace, uint64 newCreatorSettleGrace);
    event OpenResolutionTimeoutSet(uint64 previousOpenResolutionTimeout, uint64 newOpenResolutionTimeout);
    event MaxEscalationSet(uint8 previousMaxEscalation, uint8 newMaxEscalation);
    event CurveProfileRegistered(uint8 indexed profileId, address indexed previousProfile, address indexed newProfile);
    event ParimutuelEpochWindowCapSet(uint64 previousEpochWindowCap, uint64 newEpochWindowCap);
    event MarketCreationBatchCapSet(uint16 previousBatchCap, uint16 newBatchCap);

    function transferOwnership(address newOwner) external {
        LibDiamond.enforceIsContractOwner();

        if (newOwner == address(0)) {
            revert Errors.ZeroAddress();
        }

        address previousOwner = LibDiamond.contractOwner();
        LibDiamond.setContractOwner(newOwner);
        emit OwnershipTransferred(previousOwner, newOwner);
    }

    function owner() external view returns (address) {
        return LibDiamond.contractOwner();
    }

    function setResolutionMode(uint8 newMode) external {
        LibDiamond.enforceIsContractOwner();
        if (newMode > uint8(LibEveMarket.ResolutionMode.ObrJury)) {
            revert Errors.InvalidConfigValue("resolutionMode");
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.ResolutionMode mode = LibEveMarket.ResolutionMode(newMode);
        if (mode == LibEveMarket.ResolutionMode.ObrJury) {
            _enforceFullHealthyResolverEpoch(state);
        }

        uint8 previousMode = uint8(state.config.resolutionMode);
        state.config.resolutionMode = mode;
        emit Events.ResolutionModeSet(previousMode, newMode);
    }

    function setResolutionBondConfig(address bondToken, uint128 l1Amount, uint128 l2Amount) external {
        LibDiamond.enforceIsContractOwner();
        (address previousBondToken, uint128 previousL1Amount, uint128 previousL2Amount) =
            LibMarketConfigAdmin.setResolutionBondConfig(LibEveMarket.store().config, bondToken, l1Amount, l2Amount);
        emit ResolutionBondConfigSet(
            previousBondToken, bondToken, previousL1Amount, l1Amount, previousL2Amount, l2Amount
        );
    }

    function _enforceFullHealthyResolverEpoch(LibEveMarket.EveMarketStorage storage state) private view {
        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        LibEveMarket.ResolverJuryConfig storage config = state.config.resolverJuryConfig;
        LibResolverJury.ResolverEpoch storage epoch = jury.resolverEpochs[jury.currentResolverEpoch];
        uint256 requiredCount = config.activeEpochSize;
        uint256 activeCount = epoch.activeSet.length;
        if (requiredCount == 0 || activeCount != requiredCount) {
            revert Errors.ResolverSetNotReady(activeCount, requiredCount);
        }

        address identityContract = jury.eveIdentity;
        if (identityContract == address(0)) {
            revert Errors.ZeroAddress();
        }

        for (uint256 index; index < activeCount; ++index) {
            uint256 identityId = epoch.activeSet[index];
            if (!IEveIdentity(identityContract).hasResolverRole(identityId)) {
                revert Errors.ResolverEpochCandidateIneligible(jury.currentResolverEpoch, identityId);
            }

            LibResolverJury.ResolverIdentityRecord storage record = jury.identities[identityId];
            if (
                record.lifecycle != LibResolverJury.ResolverLifecycle.ResolverActive
                    || record.resolverStake != config.resolverSeatStake
                    || (record.slashLockActive && block.timestamp < record.slashLockUntil)
            ) {
                revert Errors.ResolverEpochCandidateIneligible(jury.currentResolverEpoch, identityId);
            }
        }
    }

    function setResolverJuryIdentitySettings(OwnershipConfigTypes.ResolverJuryIdentitySettings calldata settings)
        external
    {
        LibDiamond.enforceIsContractOwner();
        LibResolverJuryConfigAdmin.applyIdentitySettings(LibEveMarket.store().config.resolverJuryConfig, settings);
    }

    function setResolverJuryPoolSettings(OwnershipConfigTypes.ResolverJuryPoolSettings calldata settings) external {
        LibDiamond.enforceIsContractOwner();
        LibResolverJuryConfigAdmin.applyPoolSettings(LibEveMarket.store().config.resolverJuryConfig, settings);
    }

    function setResolverJuryRoundSettings(OwnershipConfigTypes.ResolverJuryRoundSettings calldata settings) external {
        LibDiamond.enforceIsContractOwner();
        LibResolverJuryConfigAdmin.applyRoundSettings(LibEveMarket.store().config.resolverJuryConfig, settings);
    }

    function setResolverJuryEconomicsSettings(OwnershipConfigTypes.ResolverJuryEconomicsSettings calldata settings)
        external
    {
        LibDiamond.enforceIsContractOwner();
        LibResolverJuryConfigAdmin.applyEconomicsSettings(LibEveMarket.store().config.resolverJuryConfig, settings);
    }

    function setMarketCreationFee(uint128 newMarketCreationFee) external {
        LibDiamond.enforceIsContractOwner();
        uint128 previousMarketCreationFee =
            LibMarketConfigAdmin.setMarketCreationFee(LibEveMarket.store().config, newMarketCreationFee);
        emit MarketCreationFeeSet(previousMarketCreationFee, newMarketCreationFee);
    }

    function setParimutuelCreationSeedAmount(uint128 newParimutuelCreationSeedAmount) external {
        LibDiamond.enforceIsContractOwner();
        uint128 previousParimutuelCreationSeedAmount = LibMarketConfigAdmin.setParimutuelCreationSeedAmount(
            LibEveMarket.store().config, newParimutuelCreationSeedAmount
        );
        emit ParimutuelCreationSeedAmountSet(previousParimutuelCreationSeedAmount, newParimutuelCreationSeedAmount);
    }

    function setSpotBookCreationFee(uint128 newSpotBookCreationFee) external {
        LibDiamond.enforceIsContractOwner();
        uint128 previousSpotBookCreationFee =
            LibMarketConfigAdmin.setSpotBookCreationFee(LibEveMarket.store().config, newSpotBookCreationFee);
        emit SpotBookCreationFeeSet(previousSpotBookCreationFee, newSpotBookCreationFee);
    }

    function setComboMarketCreationFee(uint128 newComboMarketCreationFee) external {
        LibDiamond.enforceIsContractOwner();
        uint128 previousComboMarketCreationFee =
            LibMarketConfigAdmin.setComboMarketCreationFee(LibEveMarket.store().config, newComboMarketCreationFee);
        emit ComboMarketCreationFeeSet(previousComboMarketCreationFee, newComboMarketCreationFee);
    }

    function setMarketCreationBond(uint128 newMarketCreationBond) external {
        LibDiamond.enforceIsContractOwner();
        uint128 previousMarketCreationBond =
            LibMarketConfigAdmin.setMarketCreationBond(LibEveMarket.store().config, newMarketCreationBond);
        emit MarketCreationBondSet(previousMarketCreationBond, newMarketCreationBond);
    }

    function setPermissionlessCreationEnabled(bool enabled) external {
        LibDiamond.enforceIsContractOwner();
        bool previousEnabled =
            LibMarketConfigAdmin.setPermissionlessCreationEnabled(LibEveMarket.store().config, enabled);
        emit PermissionlessCreationSet(previousEnabled, enabled);
    }

    function setDefaultConditionalTokens(address defaultConditionalTokens) external {
        LibDiamond.enforceIsContractOwner();
        address previousDefaultConditionalTokens =
            LibMarketConfigAdmin.setDefaultConditionalTokens(LibEveMarket.store().config, defaultConditionalTokens);
        emit DefaultConditionalTokensSet(previousDefaultConditionalTokens, defaultConditionalTokens);
    }

    function setEvesPositionManager(address evesPositionManager) external {
        LibDiamond.enforceIsContractOwner();
        address previousEvesPositionManager =
            LibMarketConfigAdmin.setEvesPositionManager(LibEveMarket.store().config, evesPositionManager);
        emit EvesPositionManagerSet(previousEvesPositionManager, evesPositionManager);
    }

    function setCollateralToken(address collateralToken) external {
        LibDiamond.enforceIsContractOwner();
        address previousCollateralToken =
            LibMarketConfigAdmin.setCollateralToken(LibEveMarket.store().config, collateralToken);
        emit CollateralTokenSet(previousCollateralToken, collateralToken);
    }

    function setCollateralProfile(
        uint8 profileId,
        address collateralToken,
        address wrapperToken,
        uint128 payoutUnit,
        uint128 marketCreationFee,
        bool enabled
    ) external {
        LibDiamond.enforceIsContractOwner();
        LibCollateralProfile.setProfile(
            LibEveMarket.store(), profileId, collateralToken, wrapperToken, payoutUnit, marketCreationFee, enabled
        );

        emit CollateralProfileSet(profileId, collateralToken, wrapperToken, payoutUnit, marketCreationFee, enabled);
    }

    function setCollateralProfileEnabled(uint8 profileId, bool enabled) external {
        LibDiamond.enforceIsContractOwner();
        bool previousEnabled = LibCollateralProfile.setEnabled(LibEveMarket.store(), profileId, enabled);

        emit CollateralProfileEnabledSet(profileId, previousEnabled, enabled);
    }

    function setCollateralProfilePayoutUnit(uint8 profileId, uint128 payoutUnit) external {
        LibDiamond.enforceIsContractOwner();
        uint128 previousPayoutUnit = LibCollateralProfile.setPayoutUnit(LibEveMarket.store(), profileId, payoutUnit);

        emit CollateralProfilePayoutUnitSet(profileId, previousPayoutUnit, payoutUnit);
    }

    function setCollateralProfileMarketCreationFee(uint8 profileId, uint128 marketCreationFee) external {
        LibDiamond.enforceIsContractOwner();
        uint128 previousMarketCreationFee =
            LibCollateralProfile.setMarketCreationFee(LibEveMarket.store(), profileId, marketCreationFee);

        emit CollateralProfileMarketCreationFeeSet(profileId, previousMarketCreationFee, marketCreationFee);
    }

    function setCollateralProfileParimutuelCreationSeedAmount(uint8 profileId, uint256 parimutuelCreationSeedAmount)
        external
    {
        LibDiamond.enforceIsContractOwner();
        (uint128 previousParimutuelCreationSeedAmount, uint128 newParimutuelCreationSeedAmount) = LibCollateralProfile.setParimutuelCreationSeedAmount(
            LibEveMarket.store(), profileId, parimutuelCreationSeedAmount
        );

        emit CollateralProfileParimutuelCreationSeedAmountSet(
            profileId, previousParimutuelCreationSeedAmount, newParimutuelCreationSeedAmount
        );
    }

    function setCollateralProfileParimutuelMinEntry(uint8 profileId, uint256 parimutuelMinEntry) external {
        LibDiamond.enforceIsContractOwner();
        (uint128 previousParimutuelMinEntry, uint128 newParimutuelMinEntry) =
            LibCollateralProfile.setParimutuelMinEntry(LibEveMarket.store(), profileId, parimutuelMinEntry);

        emit CollateralProfileParimutuelMinEntrySet(profileId, previousParimutuelMinEntry, newParimutuelMinEntry);
    }

    function setCollateralProfileParlayUnderwritingFee(uint8 profileId, uint256 parlayUnderwritingFee) external {
        LibDiamond.enforceIsContractOwner();
        (uint128 previousParlayUnderwritingFee, uint128 newParlayUnderwritingFee) =
            LibCollateralProfile.setParlayUnderwritingFee(LibEveMarket.store(), profileId, parlayUnderwritingFee);

        emit CollateralProfileParlayUnderwritingFeeSet(
            profileId, previousParlayUnderwritingFee, newParlayUnderwritingFee
        );
    }

    function setEveToken(address eveToken) external {
        LibDiamond.enforceIsContractOwner();
        address previousEveToken = LibMarketConfigAdmin.setEveToken(LibEveMarket.store().config, eveToken);
        emit EveTokenSet(previousEveToken, eveToken);
    }

    function setEveTreasury(address eveTreasury) external {
        LibDiamond.enforceIsContractOwner();
        address previousEveTreasury = LibMarketConfigAdmin.setEveTreasury(LibEveMarket.store().config, eveTreasury);
        emit EveTreasurySet(previousEveTreasury, eveTreasury);
    }

    function setStaticsDollarRail(address core, uint256 profileId, address usdcToken) external {
        LibDiamond.enforceIsContractOwner();
        LibMarketConfigAdmin.setStaticsDollarRail(LibEveMarket.store().config, core, profileId, usdcToken);
        emit StaticsDollarRailSet(core, profileId, usdcToken);
    }

    function setParimutuelConfig(address shareToken, uint16 entryFeeBps, uint128 minEntry) external {
        LibDiamond.enforceIsContractOwner();
        LibMarketConfigAdmin.setParimutuelConfig(LibEveMarket.store().config, shareToken, entryFeeBps, minEntry);

        emit ParimutuelConfigSet(shareToken, entryFeeBps, minEntry);
    }

    function setParimutuelEpochWindowCap(uint64 epochWindowCap) external {
        LibDiamond.enforceIsContractOwner();
        uint64 previous = LibMarketConfigAdmin.setParimutuelEpochWindowCap(LibEveMarket.store().config, epochWindowCap);
        emit ParimutuelEpochWindowCapSet(previous, epochWindowCap);
    }

    function setMarketCreationBatchCap(uint16 batchCap) external {
        LibDiamond.enforceIsContractOwner();
        uint16 previous = LibMarketConfigAdmin.setMarketCreationBatchCap(LibEveMarket.store().config, batchCap);
        emit MarketCreationBatchCapSet(previous, batchCap);
    }

    function setParimutuelEpochMultipliers(uint16[8] calldata multipliersBps) external {
        LibDiamond.enforceIsContractOwner();
        LibMarketConfigAdmin.setParimutuelEpochMultipliers(LibEveMarket.store().config, multipliersBps);
    }

    function setDelayedOrderConfig(
        uint64 protectionDelayBlocks,
        uint64 executionGraceBlocks,
        uint24 restingDurationMinutes
    ) external {
        LibDiamond.enforceIsContractOwner();
        LibDelayedOrderConfigAdmin.setConfig(
            LibEveMarket.store().config, protectionDelayBlocks, executionGraceBlocks, restingDurationMinutes
        );
    }

    function setDelayedOrderProcessing(uint8 processingMode, uint16 processorFeeShareBps) external {
        LibDiamond.enforceIsContractOwner();
        LibDelayedOrderConfigAdmin.setProcessing(LibEveMarket.store().config, processingMode, processorFeeShareBps);
    }

    function setDelayedOrderGuards(uint256 maxRouteLength, uint256 minQuoteWad, uint256 minBaseWad) external {
        LibDiamond.enforceIsContractOwner();
        LibDelayedOrderConfigAdmin.setGuards(LibEveMarket.store().config, maxRouteLength, minQuoteWad, minBaseWad);
    }

    function setDelayedOrderProtocolProcessor(address processor, bool allowed) external {
        LibDiamond.enforceIsContractOwner();
        LibDelayedOrderConfigAdmin.setProtocolProcessor(processor, allowed);
    }

    function setMarketDelayedExecution(bytes32 marketId, bool enabled) external {
        LibDiamond.enforceIsContractOwner();
        LibDelayedOrderConfigAdmin.setMarketDelayedExecution(marketId, enabled);
    }

    function setBookDelayedExecution(bytes32 bookId, bool enabled) external {
        LibDiamond.enforceIsContractOwner();
        LibDelayedOrderConfigAdmin.setBookDelayedExecution(bookId, enabled);
    }

    function setDurationParams(uint64 minMarketDuration, uint64 maxMarketDuration) external {
        LibDiamond.enforceIsContractOwner();
        (uint64 previousMinMarketDuration, uint64 previousMaxMarketDuration) =
            LibMarketConfigAdmin.setDurationParams(LibEveMarket.store().config, minMarketDuration, maxMarketDuration);
        emit DurationParamsSet(
            previousMinMarketDuration, minMarketDuration, previousMaxMarketDuration, maxMarketDuration
        );
    }

    function setDisputeWindow(uint64 disputeWindow) external {
        LibDiamond.enforceIsContractOwner();
        uint64 previousDisputeWindow = LibMarketConfigAdmin.setDisputeWindow(LibEveMarket.store().config, disputeWindow);
        emit DisputeWindowSet(previousDisputeWindow, disputeWindow);
    }

    function setCreatorSettleGrace(uint64 creatorSettleGrace) external {
        LibDiamond.enforceIsContractOwner();
        uint64 previousCreatorSettleGrace =
            LibMarketConfigAdmin.setCreatorSettleGrace(LibEveMarket.store().config, creatorSettleGrace);
        emit CreatorSettleGraceSet(previousCreatorSettleGrace, creatorSettleGrace);
    }

    function setOpenResolutionTimeout(uint64 openResolutionTimeout) external {
        LibDiamond.enforceIsContractOwner();
        uint64 previousOpenResolutionTimeout =
            LibMarketConfigAdmin.setOpenResolutionTimeout(LibEveMarket.store().config, openResolutionTimeout);
        emit OpenResolutionTimeoutSet(previousOpenResolutionTimeout, openResolutionTimeout);
    }

    function setMaxEscalation(uint8 maxEscalation) external {
        LibDiamond.enforceIsContractOwner();
        uint8 previousMaxEscalation = LibMarketConfigAdmin.setMaxEscalation(LibEveMarket.store().config, maxEscalation);
        emit MaxEscalationSet(previousMaxEscalation, maxEscalation);
    }

    function registerCurveProfile(uint8 profileId, address profileContract) external {
        LibDiamond.enforceIsContractOwner();
        address previousProfile =
            LibMarketConfigAdmin.registerCurveProfile(LibEveMarket.store(), profileId, profileContract);
        emit CurveProfileRegistered(profileId, previousProfile, profileContract);
    }
}
