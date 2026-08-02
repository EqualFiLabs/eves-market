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
        uint16 seniorPoolFeeBps,
        uint16 resolverFeeBps
    ) internal {
        setBookFeeSplit(
            config.orderbookFeeConfig, makerFeeBps, creatorFeeBps, protocolFeeBps, seniorPoolFeeBps, resolverFeeBps
        );
    }

    function setSpotFeeSplit(
        LibEveMarket.MarketConfig storage config,
        uint16 makerFeeBps,
        uint16 protocolFeeBps,
        uint16 seniorPoolFeeBps,
        uint16 resolverFeeBps
    ) internal {
        _enforceFeeSplit(uint256(makerFeeBps) + protocolFeeBps + seniorPoolFeeBps + resolverFeeBps);
        config.spotFeeConfig.makerFeeBps = makerFeeBps;
        config.spotFeeConfig.protocolFeeBps = protocolFeeBps;
        config.spotFeeConfig.seniorPoolFeeBps = seniorPoolFeeBps;
        config.spotFeeConfig.resolverFeeBps = resolverFeeBps;
    }

    function setComboFeeSplit(
        LibEveMarket.MarketConfig storage config,
        uint16 makerFeeBps,
        uint16 creatorFeeBps,
        uint16 protocolFeeBps,
        uint16 seniorPoolFeeBps,
        uint16 resolverFeeBps
    ) internal {
        _enforceFeeSplit(uint256(makerFeeBps) + creatorFeeBps + protocolFeeBps + seniorPoolFeeBps + resolverFeeBps);
        config.comboFeeConfig.makerFeeBps = makerFeeBps;
        config.comboFeeConfig.creatorFeeBps = creatorFeeBps;
        config.comboFeeConfig.protocolFeeBps = protocolFeeBps;
        config.comboFeeConfig.seniorPoolFeeBps = seniorPoolFeeBps;
        config.comboFeeConfig.resolverFeeBps = resolverFeeBps;
    }

    function setParimutuelFeeSplit(
        LibEveMarket.MarketConfig storage config,
        uint16 creatorFeeBps,
        uint16 protocolFeeBps,
        uint16 seniorPoolFeeBps,
        uint16 resolverFeeBps
    ) internal {
        _enforceFeeSplit(uint256(creatorFeeBps) + protocolFeeBps + seniorPoolFeeBps + resolverFeeBps);
        config.parimutuelFeeConfig.creatorFeeBps = creatorFeeBps;
        config.parimutuelFeeConfig.protocolFeeBps = protocolFeeBps;
        config.parimutuelFeeConfig.seniorPoolFeeBps = seniorPoolFeeBps;
        config.parimutuelFeeConfig.resolverFeeBps = resolverFeeBps;
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
        uint16 seniorPoolFeeBps,
        uint16 resolverFeeBps
    ) internal {
        _enforceFeeSplit(uint256(makerFeeBps) + creatorFeeBps + protocolFeeBps + seniorPoolFeeBps + resolverFeeBps);
        feeConfig.makerFeeBps = makerFeeBps;
        feeConfig.creatorFeeBps = creatorFeeBps;
        feeConfig.protocolFeeBps = protocolFeeBps;
        feeConfig.seniorPoolFeeBps = seniorPoolFeeBps;
        feeConfig.resolverFeeBps = resolverFeeBps;
    }

    function _enforceFeeSplit(uint256 totalBps) private pure {
        if (totalBps != 10_000) {
            revert Errors.InvalidFeeSplit(totalBps);
        }
    }
}
