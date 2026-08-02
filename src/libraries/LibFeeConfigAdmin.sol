// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Errors} from "./Errors.sol";
import {LibAdminConfig} from "./LibAdminConfig.sol";
import {LibEveMarket} from "./LibEveMarket.sol";

library LibFeeConfigAdmin {
    function setOrderbookEntryFeeBps(LibEveMarket.MarketConfig storage config, uint16 newEntryFeeBps)
        internal
        returns (uint16 previousEntryFeeBps)
    {
        previousEntryFeeBps = setEntryFeeBps(config.orderbookFeeConfig, newEntryFeeBps);
    }

    function setSpotTradeFeeBps(LibEveMarket.MarketConfig storage config, uint16 newTradeFeeBps)
        internal
        returns (uint16 previousTradeFeeBps)
    {
        LibAdminConfig.enforceBps(newTradeFeeBps);
        previousTradeFeeBps = config.spotFeeConfig.tradeFeeBps;
        config.spotFeeConfig.tradeFeeBps = newTradeFeeBps;
    }

    function setComboTradeFeeBps(LibEveMarket.MarketConfig storage config, uint16 newTradeFeeBps)
        internal
        returns (uint16 previousTradeFeeBps)
    {
        LibAdminConfig.enforceBps(newTradeFeeBps);
        previousTradeFeeBps = config.comboFeeConfig.tradeFeeBps;
        config.comboFeeConfig.tradeFeeBps = newTradeFeeBps;
    }

    function setOrderbookFeeSplit(
        LibEveMarket.MarketConfig storage config,
        uint16 makerFeeBps,
        uint16 creatorFeeBps,
        uint16 protocolFeeBps,
        uint16 vaultFeeBps,
        uint16 resolverFeeBps,
        uint16 evRiskFeeBps
    ) internal {
        setBookFeeSplit(
            config.orderbookFeeConfig,
            makerFeeBps,
            creatorFeeBps,
            protocolFeeBps,
            vaultFeeBps,
            resolverFeeBps,
            evRiskFeeBps
        );
    }

    function setSpotFeeSplit(
        LibEveMarket.MarketConfig storage config,
        uint16 makerFeeBps,
        uint16 protocolFeeBps,
        uint16 vaultFeeBps,
        uint16 resolverFeeBps,
        uint16 evRiskFeeBps
    ) internal {
        enforceFiveWayFeeSplit(makerFeeBps, protocolFeeBps, vaultFeeBps, resolverFeeBps, evRiskFeeBps);
        config.spotFeeConfig.makerFeeBps = makerFeeBps;
        config.spotFeeConfig.protocolFeeBps = protocolFeeBps;
        config.spotFeeConfig.vaultFeeBps = vaultFeeBps;
        config.spotFeeConfig.resolverFeeBps = resolverFeeBps;
        config.spotFeeConfig.evRiskFeeBps = evRiskFeeBps;
    }

    function setComboFeeSplit(
        LibEveMarket.MarketConfig storage config,
        uint16 makerFeeBps,
        uint16 creatorFeeBps,
        uint16 protocolFeeBps,
        uint16 vaultFeeBps,
        uint16 resolverFeeBps,
        uint16 evRiskFeeBps
    ) internal {
        enforceSixWayFeeSplit(makerFeeBps, creatorFeeBps, protocolFeeBps, vaultFeeBps, resolverFeeBps, evRiskFeeBps);
        config.comboFeeConfig.makerFeeBps = makerFeeBps;
        config.comboFeeConfig.creatorFeeBps = creatorFeeBps;
        config.comboFeeConfig.protocolFeeBps = protocolFeeBps;
        config.comboFeeConfig.vaultFeeBps = vaultFeeBps;
        config.comboFeeConfig.resolverFeeBps = resolverFeeBps;
        config.comboFeeConfig.evRiskFeeBps = evRiskFeeBps;
    }

    function setParimutuelFeeSplit(
        LibEveMarket.MarketConfig storage config,
        uint16 creatorFeeBps,
        uint16 protocolFeeBps,
        uint16 vaultFeeBps,
        uint16 resolverFeeBps,
        uint16 evRiskFeeBps
    ) internal {
        enforceFiveWayFeeSplit(creatorFeeBps, protocolFeeBps, vaultFeeBps, resolverFeeBps, evRiskFeeBps);
        config.parimutuelFeeConfig.creatorFeeBps = creatorFeeBps;
        config.parimutuelFeeConfig.protocolFeeBps = protocolFeeBps;
        config.parimutuelFeeConfig.vaultFeeBps = vaultFeeBps;
        config.parimutuelFeeConfig.resolverFeeBps = resolverFeeBps;
        config.parimutuelFeeConfig.evRiskFeeBps = evRiskFeeBps;
    }

    function setEntryFeeBps(LibEveMarket.BookFeeConfig storage feeConfig, uint16 newEntryFeeBps)
        internal
        returns (uint16 previousEntryFeeBps)
    {
        LibAdminConfig.enforceBps(newEntryFeeBps);
        previousEntryFeeBps = feeConfig.entryFeeBps;
        feeConfig.entryFeeBps = newEntryFeeBps;
    }

    function setBookFeeSplit(
        LibEveMarket.BookFeeConfig storage feeConfig,
        uint16 makerFeeBps,
        uint16 creatorFeeBps,
        uint16 protocolFeeBps,
        uint16 vaultFeeBps,
        uint16 resolverFeeBps,
        uint16 evRiskFeeBps
    ) internal {
        enforceSixWayFeeSplit(makerFeeBps, creatorFeeBps, protocolFeeBps, vaultFeeBps, resolverFeeBps, evRiskFeeBps);
        feeConfig.makerFeeBps = makerFeeBps;
        feeConfig.creatorFeeBps = creatorFeeBps;
        feeConfig.protocolFeeBps = protocolFeeBps;
        feeConfig.vaultFeeBps = vaultFeeBps;
        feeConfig.resolverFeeBps = resolverFeeBps;
        feeConfig.evRiskFeeBps = evRiskFeeBps;
    }

    function enforceFourWayFeeSplit(uint16 makerFeeBps, uint16 creatorFeeBps, uint16 protocolFeeBps, uint16 vaultFeeBps)
        internal
        pure
    {
        uint256 totalBps = uint256(makerFeeBps) + creatorFeeBps + protocolFeeBps + vaultFeeBps;
        if (totalBps != 10_000) {
            revert Errors.InvalidFeeSplit(totalBps);
        }
    }

    function enforceThreeWayFeeSplit(uint16 firstFeeBps, uint16 secondFeeBps, uint16 thirdFeeBps) internal pure {
        uint256 totalBps = uint256(firstFeeBps) + secondFeeBps + thirdFeeBps;
        if (totalBps != 10_000) {
            revert Errors.InvalidFeeSplit(totalBps);
        }
    }

    function enforceFiveWayFeeSplit(
        uint16 firstFeeBps,
        uint16 secondFeeBps,
        uint16 thirdFeeBps,
        uint16 fourthFeeBps,
        uint16 fifthFeeBps
    ) internal pure {
        uint256 totalBps =
            uint256(firstFeeBps) + secondFeeBps + thirdFeeBps + fourthFeeBps + fifthFeeBps;
        if (totalBps != 10_000) {
            revert Errors.InvalidFeeSplit(totalBps);
        }
    }

    function enforceSixWayFeeSplit(
        uint16 firstFeeBps,
        uint16 secondFeeBps,
        uint16 thirdFeeBps,
        uint16 fourthFeeBps,
        uint16 fifthFeeBps,
        uint16 sixthFeeBps
    ) internal pure {
        uint256 totalBps =
            uint256(firstFeeBps) + secondFeeBps + thirdFeeBps + fourthFeeBps + fifthFeeBps + sixthFeeBps;
        if (totalBps != 10_000) {
            revert Errors.InvalidFeeSplit(totalBps);
        }
    }
}
