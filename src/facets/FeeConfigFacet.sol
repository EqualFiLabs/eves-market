// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {LibDiamond} from "../libraries/LibDiamond.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibFeeConfigAdmin} from "../libraries/LibFeeConfigAdmin.sol";

contract FeeConfigFacet {
    event OrderbookFeeSplitSet(
        uint16 makerFeeBps, uint16 creatorFeeBps, uint16 protocolFeeBps, uint16 seniorPoolFeeBps, uint16 resolverFeeBps
    );
    event OrderbookEntryFeeBpsSet(uint16 previousEntryFeeBps, uint16 newEntryFeeBps);
    event SpotFeeSplitSet(uint16 makerFeeBps, uint16 protocolFeeBps, uint16 seniorPoolFeeBps, uint16 resolverFeeBps);
    event SpotTradeFeeBpsSet(uint16 previousTradeFeeBps, uint16 newTradeFeeBps);
    event ComboFeeSplitSet(
        uint16 makerFeeBps, uint16 creatorFeeBps, uint16 protocolFeeBps, uint16 seniorPoolFeeBps, uint16 resolverFeeBps
    );
    event ComboTradeFeeBpsSet(uint16 previousTradeFeeBps, uint16 newTradeFeeBps);
    event ParimutuelFeeSplitSet(
        uint16 creatorFeeBps, uint16 protocolFeeBps, uint16 seniorPoolFeeBps, uint16 resolverFeeBps
    );

    function setOrderbookEntryFeeBps(uint16 newEntryFeeBps) external {
        LibDiamond.enforceIsContractOwner();
        uint16 previousEntryFeeBps =
            LibFeeConfigAdmin.setOrderbookEntryFeeBps(LibEveMarket.store().config, newEntryFeeBps);
        emit OrderbookEntryFeeBpsSet(previousEntryFeeBps, newEntryFeeBps);
    }

    function setSpotTradeFeeBps(uint16 newTradeFeeBps) external {
        LibDiamond.enforceIsContractOwner();
        uint16 previousTradeFeeBps = LibFeeConfigAdmin.setSpotTradeFeeBps(LibEveMarket.store().config, newTradeFeeBps);
        emit SpotTradeFeeBpsSet(previousTradeFeeBps, newTradeFeeBps);
    }

    function setComboTradeFeeBps(uint16 newTradeFeeBps) external {
        LibDiamond.enforceIsContractOwner();
        uint16 previousTradeFeeBps = LibFeeConfigAdmin.setComboTradeFeeBps(LibEveMarket.store().config, newTradeFeeBps);
        emit ComboTradeFeeBpsSet(previousTradeFeeBps, newTradeFeeBps);
    }

    function setOrderbookFeeSplit(
        uint16 makerFeeBps,
        uint16 creatorFeeBps,
        uint16 protocolFeeBps,
        uint16 seniorPoolFeeBps,
        uint16 resolverFeeBps
    ) external {
        LibDiamond.enforceIsContractOwner();
        LibFeeConfigAdmin.setOrderbookFeeSplit(
            LibEveMarket.store().config, makerFeeBps, creatorFeeBps, protocolFeeBps, seniorPoolFeeBps, resolverFeeBps
        );
        emit OrderbookFeeSplitSet(makerFeeBps, creatorFeeBps, protocolFeeBps, seniorPoolFeeBps, resolverFeeBps);
    }

    function setSpotFeeSplit(uint16 makerFeeBps, uint16 protocolFeeBps, uint16 seniorPoolFeeBps, uint16 resolverFeeBps)
        external
    {
        LibDiamond.enforceIsContractOwner();
        LibFeeConfigAdmin.setSpotFeeSplit(
            LibEveMarket.store().config, makerFeeBps, protocolFeeBps, seniorPoolFeeBps, resolverFeeBps
        );
        emit SpotFeeSplitSet(makerFeeBps, protocolFeeBps, seniorPoolFeeBps, resolverFeeBps);
    }

    function setComboFeeSplit(
        uint16 makerFeeBps,
        uint16 creatorFeeBps,
        uint16 protocolFeeBps,
        uint16 seniorPoolFeeBps,
        uint16 resolverFeeBps
    ) external {
        LibDiamond.enforceIsContractOwner();
        LibFeeConfigAdmin.setComboFeeSplit(
            LibEveMarket.store().config, makerFeeBps, creatorFeeBps, protocolFeeBps, seniorPoolFeeBps, resolverFeeBps
        );
        emit ComboFeeSplitSet(makerFeeBps, creatorFeeBps, protocolFeeBps, seniorPoolFeeBps, resolverFeeBps);
    }

    function setParimutuelFeeSplit(
        uint16 creatorFeeBps,
        uint16 protocolFeeBps,
        uint16 seniorPoolFeeBps,
        uint16 resolverFeeBps
    ) external {
        LibDiamond.enforceIsContractOwner();
        LibFeeConfigAdmin.setParimutuelFeeSplit(
            LibEveMarket.store().config, creatorFeeBps, protocolFeeBps, seniorPoolFeeBps, resolverFeeBps
        );
        emit ParimutuelFeeSplitSet(creatorFeeBps, protocolFeeBps, seniorPoolFeeBps, resolverFeeBps);
    }
}
