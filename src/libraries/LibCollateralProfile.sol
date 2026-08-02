// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Errors} from "./Errors.sol";
import {LibAdminConfig} from "./LibAdminConfig.sol";
import {LibEveMarket} from "./LibEveMarket.sol";

library LibCollateralProfile {
    function requireProfile(LibEveMarket.EveMarketStorage storage state, uint8 profileId)
        internal
        view
        returns (LibEveMarket.CollateralProfile storage profile)
    {
        profile = state.collateralProfiles[profileId];
        if (profile.collateralToken == address(0)) {
            revert Errors.CollateralProfileNotFound(profileId);
        }
    }

    function requireEnabled(LibEveMarket.EveMarketStorage storage state, uint8 profileId)
        internal
        view
        returns (LibEveMarket.CollateralProfile storage profile)
    {
        profile = requireProfile(state, profileId);
        if (!profile.enabled) {
            revert Errors.CollateralProfileDisabled(profileId);
        }
    }

    function setProfile(
        LibEveMarket.EveMarketStorage storage state,
        uint8 profileId,
        address collateralToken,
        address wrapperToken,
        uint128 payoutUnit,
        uint128 marketCreationFee,
        bool enabled
    ) internal {
        LibAdminConfig.enforceERC20(collateralToken);
        if (wrapperToken != address(0)) {
            LibAdminConfig.enforceERC20(wrapperToken);
        }
        LibAdminConfig.enforceNonZero(payoutUnit);

        LibEveMarket.CollateralProfile storage profile = state.collateralProfiles[profileId];
        profile.collateralToken = collateralToken;
        profile.wrapperToken = wrapperToken;
        profile.payoutUnit = payoutUnit;
        profile.marketCreationFee = marketCreationFee;
        profile.enabled = enabled;
    }

    function setEnabled(LibEveMarket.EveMarketStorage storage state, uint8 profileId, bool enabled)
        internal
        returns (bool previousEnabled)
    {
        LibEveMarket.CollateralProfile storage profile = requireProfile(state, profileId);
        previousEnabled = profile.enabled;
        profile.enabled = enabled;
    }

    function setPayoutUnit(LibEveMarket.EveMarketStorage storage state, uint8 profileId, uint128 payoutUnit)
        internal
        returns (uint128 previousPayoutUnit)
    {
        LibAdminConfig.enforceNonZero(payoutUnit);
        LibEveMarket.CollateralProfile storage profile = requireProfile(state, profileId);
        previousPayoutUnit = profile.payoutUnit;
        profile.payoutUnit = payoutUnit;
    }

    function setMarketCreationFee(
        LibEveMarket.EveMarketStorage storage state,
        uint8 profileId,
        uint128 marketCreationFee
    ) internal returns (uint128 previousMarketCreationFee) {
        LibEveMarket.CollateralProfile storage profile = requireProfile(state, profileId);
        previousMarketCreationFee = profile.marketCreationFee;
        profile.marketCreationFee = marketCreationFee;
    }

    function setParimutuelCreationSeedAmount(
        LibEveMarket.EveMarketStorage storage state,
        uint8 profileId,
        uint256 parimutuelCreationSeedAmount
    ) internal returns (uint128 previousParimutuelCreationSeedAmount, uint128 newParimutuelCreationSeedAmount) {
        requireProfile(state, profileId);
        newParimutuelCreationSeedAmount = LibAdminConfig.toUint128(parimutuelCreationSeedAmount);
        previousParimutuelCreationSeedAmount = state.parimutuelProfileCreationSeedAmount[profileId];
        state.parimutuelProfileCreationSeedAmount[profileId] = newParimutuelCreationSeedAmount;
    }

    function setParimutuelMinEntry(
        LibEveMarket.EveMarketStorage storage state,
        uint8 profileId,
        uint256 parimutuelMinEntry
    ) internal returns (uint128 previousParimutuelMinEntry, uint128 newParimutuelMinEntry) {
        requireProfile(state, profileId);
        newParimutuelMinEntry = LibAdminConfig.toUint128(parimutuelMinEntry);
        previousParimutuelMinEntry = state.parimutuelProfileMinEntry[profileId];
        state.parimutuelProfileMinEntry[profileId] = newParimutuelMinEntry;
    }

    function setParlayUnderwritingFee(
        LibEveMarket.EveMarketStorage storage state,
        uint8 profileId,
        uint256 parlayUnderwritingFee
    ) internal returns (uint128 previousParlayUnderwritingFee, uint128 newParlayUnderwritingFee) {
        requireProfile(state, profileId);
        newParlayUnderwritingFee = LibAdminConfig.toUint128(parlayUnderwritingFee);
        previousParlayUnderwritingFee = state.parlayUnderwritingFeeByProfile[profileId];
        state.parlayUnderwritingFeeByProfile[profileId] = newParlayUnderwritingFee;
    }
}
