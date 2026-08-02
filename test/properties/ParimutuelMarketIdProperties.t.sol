// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IMarketFactoryFacet} from "../../src/interfaces/IMarketFactoryFacet.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {LibMarketCreation} from "../../src/libraries/LibMarketCreation.sol";

import {MarketFactoryFixture} from "../helpers/DiamondFixtures.sol";

contract ParimutuelMarketIdPropertiesTest is MarketFactoryFixture {
    // Feature: parimutuel-market, Property 2: market id determinism and type separation
    function testFuzz_MarketIdsAreDeterministicAndTypeSeparated(bytes32 questionSeed, uint64 expiryTime) public view {
        string memory question = string.concat("Q-", vm.toString(uint256(questionSeed)));
        string memory category = "property";
        uint64 tradingStartTime = uint64(block.timestamp);
        IMarketFactoryFacet factory = IMarketFactoryFacet(address(diamond));

        bytes32 clobMarketId = factory.computeMarketId(
            question,
            category,
            tradingStartTime,
            expiryTime,
            address(collateralToken),
            LibEveMarket.MarketType.CLOB,
            LibEveMarket.PositionTokenType.CTF
        );
        bytes32 repeatedClobMarketId = factory.computeMarketId(
            question,
            category,
            tradingStartTime,
            expiryTime,
            address(collateralToken),
            LibEveMarket.MarketType.CLOB,
            LibEveMarket.PositionTokenType.CTF
        );
        bytes32 parimutuelMarketId = factory.computeMarketId(
            question,
            category,
            tradingStartTime,
            expiryTime,
            address(collateralToken),
            LibEveMarket.MarketType.PARIMUTUEL,
            LibEveMarket.PositionTokenType.PARIMUTUEL
        );
        bytes32 repeatedParimutuelMarketId = factory.computeMarketId(
            question,
            category,
            tradingStartTime,
            expiryTime,
            address(collateralToken),
            LibEveMarket.MarketType.PARIMUTUEL,
            LibEveMarket.PositionTokenType.PARIMUTUEL
        );

        assertEq(clobMarketId, repeatedClobMarketId);
        assertEq(parimutuelMarketId, repeatedParimutuelMarketId);
        assertTrue(clobMarketId != parimutuelMarketId);
        assertEq(
            clobMarketId,
            LibMarketCreation.marketIdFor(
                question,
                category,
                tradingStartTime,
                expiryTime,
                address(collateralToken),
                LibEveMarket.MarketType.CLOB,
                LibEveMarket.PositionTokenType.CTF
            )
        );
        assertEq(
            parimutuelMarketId,
            LibMarketCreation.marketIdFor(
                question,
                category,
                tradingStartTime,
                expiryTime,
                address(collateralToken),
                LibEveMarket.MarketType.PARIMUTUEL,
                LibEveMarket.PositionTokenType.PARIMUTUEL
            )
        );
    }
}
