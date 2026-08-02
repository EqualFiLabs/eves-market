// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IParimutuelFacet} from "../../src/interfaces/IParimutuelFacet.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {LibMarketCreation} from "../../src/libraries/LibMarketCreation.sol";

import {StateProbeFacet} from "../helpers/DiamondFixtures.sol";
import {ParimutuelPropertiesBase} from "./ParimutuelPropertiesBase.t.sol";

contract ParimutuelCreationPropertiesTest is ParimutuelPropertiesBase {
    // Feature: parimutuel-facet, Property 5: market creation field correctness
    function testFuzz_ParimutuelCreationStoresExpectedFields(bytes32 questionSeed, uint64 durationSeed) public {
        uint64 duration = uint64(bound(uint256(durationSeed), 1 hours, 90 days));
        uint64 expiryTime = uint64(block.timestamp) + duration;
        string memory question = string.concat("parimutuel-creation-", vm.toString(uint256(questionSeed)));

        bytes32 marketId = _createParimutuelMarket(question, expiryTime);

        (uint8 marketType, address positionToken) =
            StateProbeFacet(address(diamond)).getStoredMarketTypeAndPositionToken(marketId);
        (,,,, uint256 yesPositionId, uint256 noPositionId) =
            StateProbeFacet(address(diamond)).getStoredMarketCore(marketId);

        assertTrue(IParimutuelFacet(address(diamond)).isParimutuelMarket(marketId));
        assertEq(marketType, uint8(LibEveMarket.MarketType.PARIMUTUEL));
        assertEq(positionToken, address(shareToken));
        assertEq(yesPositionId, LibMarketCreation.parimutuelPositionId(address(diamond), marketId, 1));
        assertEq(noPositionId, LibMarketCreation.parimutuelPositionId(address(diamond), marketId, 2));
    }
}
