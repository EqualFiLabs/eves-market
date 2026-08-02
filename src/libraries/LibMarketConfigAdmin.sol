// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Errors} from "./Errors.sol";
import {Events} from "./Events.sol";
import {LibAdminConfig} from "./LibAdminConfig.sol";
import {LibEveMarket} from "./LibEveMarket.sol";

library LibMarketConfigAdmin {
    uint8 internal constant MAX_ESCALATION_LIMIT = 3;
    uint16 internal constant MAX_PARIMUTUEL_MULTIPLIER_BPS = 50_000;

    function setResolutionBondConfig(
        LibEveMarket.MarketConfig storage config,
        address bondToken,
        uint128 l1Amount,
        uint128 l2Amount
    ) internal returns (address previousBondToken, uint128 previousL1Amount, uint128 previousL2Amount) {
        if (bondToken == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (l2Amount < l1Amount) {
            revert Errors.InvalidAmount(l2Amount);
        }

        previousBondToken = config.bondToken;
        previousL1Amount = config.resolutionBondL1;
        previousL2Amount = config.resolutionBondL2;
        config.bondToken = bondToken;
        config.resolutionBondL1 = l1Amount;
        config.resolutionBondL2 = l2Amount;
    }

    function setMarketCreationFee(LibEveMarket.MarketConfig storage config, uint128 newMarketCreationFee)
        internal
        returns (uint128 previousMarketCreationFee)
    {
        previousMarketCreationFee = config.marketCreationFee;
        config.marketCreationFee = newMarketCreationFee;
    }

    function setParimutuelCreationSeedAmount(
        LibEveMarket.MarketConfig storage config,
        uint128 newParimutuelCreationSeedAmount
    ) internal returns (uint128 previousParimutuelCreationSeedAmount) {
        previousParimutuelCreationSeedAmount = config.parimutuelCreationSeedAmount;
        config.parimutuelCreationSeedAmount = newParimutuelCreationSeedAmount;
    }

    function setSpotBookCreationFee(LibEveMarket.MarketConfig storage config, uint128 newSpotBookCreationFee)
        internal
        returns (uint128 previousSpotBookCreationFee)
    {
        previousSpotBookCreationFee = config.spotBookCreationFee;
        config.spotBookCreationFee = newSpotBookCreationFee;
    }

    function setComboMarketCreationFee(LibEveMarket.MarketConfig storage config, uint128 newComboMarketCreationFee)
        internal
        returns (uint128 previousComboMarketCreationFee)
    {
        previousComboMarketCreationFee = config.comboMarketCreationFee;
        config.comboMarketCreationFee = newComboMarketCreationFee;
    }

    function setMarketCreationBond(LibEveMarket.MarketConfig storage config, uint128 newMarketCreationBond)
        internal
        returns (uint128 previousMarketCreationBond)
    {
        previousMarketCreationBond = config.marketCreationBond;
        config.marketCreationBond = newMarketCreationBond;
    }

    function setPermissionlessCreationEnabled(LibEveMarket.MarketConfig storage config, bool enabled)
        internal
        returns (bool previousEnabled)
    {
        previousEnabled = config.permissionlessCreationEnabled;
        config.permissionlessCreationEnabled = enabled;
    }

    function setDefaultConditionalTokens(LibEveMarket.MarketConfig storage config, address defaultConditionalTokens)
        internal
        returns (address previousDefaultConditionalTokens)
    {
        LibAdminConfig.enforceConditionalTokens(defaultConditionalTokens);
        previousDefaultConditionalTokens = config.defaultConditionalTokens;
        config.defaultConditionalTokens = defaultConditionalTokens;
    }

    function setEvesPositionManager(LibEveMarket.MarketConfig storage config, address evesPositionManager)
        internal
        returns (address previousEvesPositionManager)
    {
        if (evesPositionManager == address(0)) {
            revert Errors.ZeroAddress();
        }
        LibAdminConfig.enforceERC1155(evesPositionManager);
        previousEvesPositionManager = config.evesPositionManager;
        config.evesPositionManager = evesPositionManager;
    }

    function setCollateralToken(LibEveMarket.MarketConfig storage config, address collateralToken)
        internal
        returns (address previousCollateralToken)
    {
        LibAdminConfig.enforceERC20(collateralToken);
        previousCollateralToken = config.collateralToken;
        config.collateralToken = collateralToken;
    }

    function setEveToken(LibEveMarket.MarketConfig storage config, address eveToken)
        internal
        returns (address previousEveToken)
    {
        LibAdminConfig.enforceERC20(eveToken);
        previousEveToken = config.eveToken;
        config.eveToken = eveToken;
    }

    function setEveTreasury(LibEveMarket.MarketConfig storage config, address eveTreasury)
        internal
        returns (address previousEveTreasury)
    {
        if (eveTreasury == address(0)) {
            revert Errors.ZeroAddress();
        }
        previousEveTreasury = config.eveTreasury;
        config.eveTreasury = eveTreasury;
    }

    function setStakingVault(LibEveMarket.MarketConfig storage config, address stakingVault)
        internal
        returns (address previousStakingVault)
    {
        if (stakingVault != address(0)) {
            LibAdminConfig.enforceVault(stakingVault);
        }
        previousStakingVault = config.stakingVault;
        config.stakingVault = stakingVault;
    }

    function setParimutuelConfig(
        LibEveMarket.MarketConfig storage config,
        address shareToken,
        uint16 entryFeeBps,
        uint128 minEntry
    ) internal {
        LibAdminConfig.enforceParimutuelShareToken(shareToken);
        LibAdminConfig.enforceBps(entryFeeBps);
        config.parimutuelShareToken = shareToken;
        config.parimutuelFeeConfig.entryFeeBps = entryFeeBps;
        config.parimutuelMinEntry = minEntry;
    }

    function setParimutuelEpochWindowCap(LibEveMarket.MarketConfig storage config, uint64 epochWindowCap)
        internal
        returns (uint64 previous)
    {
        previous = config.parimutuelEpochWindowCap;
        config.parimutuelEpochWindowCap = epochWindowCap;
    }

    function setMarketCreationBatchCap(LibEveMarket.MarketConfig storage config, uint16 batchCap)
        internal
        returns (uint16 previous)
    {
        if (batchCap == 0) {
            revert Errors.InvalidAmount(batchCap);
        }
        previous = config.marketCreationBatchCap;
        config.marketCreationBatchCap = batchCap;
    }

    function setParimutuelEpochMultipliers(LibEveMarket.MarketConfig storage config, uint16[8] calldata multipliersBps)
        internal
    {
        for (uint256 index = 0; index < multipliersBps.length; ++index) {
            uint16 multiplierBps = multipliersBps[index];
            if (multiplierBps == 0 || multiplierBps > MAX_PARIMUTUEL_MULTIPLIER_BPS) {
                revert Errors.InvalidParimutuelEpochMultiplier(index, multiplierBps);
            }
        }

        config.parimutuelEpochMultipliersBps = multipliersBps;
        emit Events.ParimutuelEpochMultipliersUpdated(multipliersBps);
    }

    function setDurationParams(
        LibEveMarket.MarketConfig storage config,
        uint64 minMarketDuration,
        uint64 maxMarketDuration
    ) internal returns (uint64 previousMinMarketDuration, uint64 previousMaxMarketDuration) {
        if (minMarketDuration > maxMarketDuration) {
            revert Errors.InvalidDurationBounds(minMarketDuration, maxMarketDuration);
        }

        previousMinMarketDuration = config.minMarketDuration;
        previousMaxMarketDuration = config.maxMarketDuration;
        config.minMarketDuration = minMarketDuration;
        config.maxMarketDuration = maxMarketDuration;
    }

    function setDisputeWindow(LibEveMarket.MarketConfig storage config, uint64 disputeWindow)
        internal
        returns (uint64 previousDisputeWindow)
    {
        LibAdminConfig.enforceNonZero(disputeWindow);
        previousDisputeWindow = config.disputeWindow;
        config.disputeWindow = disputeWindow;
    }

    function setCreatorSettleGrace(LibEveMarket.MarketConfig storage config, uint64 creatorSettleGrace)
        internal
        returns (uint64 previousCreatorSettleGrace)
    {
        LibAdminConfig.enforceNonZero(creatorSettleGrace);
        previousCreatorSettleGrace = config.creatorSettleGrace;
        config.creatorSettleGrace = creatorSettleGrace;
    }

    function setOpenResolutionTimeout(LibEveMarket.MarketConfig storage config, uint64 openResolutionTimeout)
        internal
        returns (uint64 previousOpenResolutionTimeout)
    {
        LibAdminConfig.enforceNonZero(openResolutionTimeout);
        previousOpenResolutionTimeout = config.openResolutionTimeout;
        config.openResolutionTimeout = openResolutionTimeout;
    }

    function setMaxEscalation(LibEveMarket.MarketConfig storage config, uint8 maxEscalation)
        internal
        returns (uint8 previousMaxEscalation)
    {
        if (maxEscalation == 0 || maxEscalation > MAX_ESCALATION_LIMIT) {
            revert Errors.InvalidAmount(maxEscalation);
        }
        previousMaxEscalation = config.maxEscalation;
        config.maxEscalation = maxEscalation;
    }

    function registerCurveProfile(LibEveMarket.EveMarketStorage storage state, uint8 profileId, address profileContract)
        internal
        returns (address previousProfile)
    {
        if (profileContract == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (profileContract.code.length == 0) {
            revert Errors.ContractHasNoCode(profileContract);
        }
        previousProfile = state.curveProfiles[profileId];
        state.curveProfiles[profileId] = profileContract;
    }
}
