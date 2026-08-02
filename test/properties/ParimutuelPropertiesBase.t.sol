// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {MarketFactoryFacet} from "../../src/facets/MarketFactoryFacet.sol";
import {OwnershipFacet} from "../../src/facets/OwnershipFacet.sol";
import {ParimutuelFacet} from "../../src/facets/ParimutuelFacet.sol";
import {ParimutuelViewFacet} from "../../src/facets/ParimutuelViewFacet.sol";
import {IOBRResolutionFacet} from "../../src/interfaces/IOBRResolutionFacet.sol";
import {IParimutuelFacet} from "../../src/interfaces/IParimutuelFacet.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {ParimutuelShareToken} from "../../src/tokens/ParimutuelShareToken.sol";

import {ResolutionFixture, ResolutionHarnessFacet, StateProbeFacet} from "../helpers/DiamondFixtures.sol";

abstract contract ParimutuelPropertiesBase is ResolutionFixture {
    ParimutuelFacet internal parimutuelFacet;
    ParimutuelShareToken internal shareToken;

    address internal alice;
    address internal bob;
    address internal carol;

    function setUp() public virtual override {
        super.setUp();

        alice = makeAddr("alice");
        bob = makeAddr("bob");
        carol = makeAddr("carol");

        parimutuelFacet = new ParimutuelFacet();
        shareToken = new ParimutuelShareToken(address(diamond), "uri://parimutuel/{id}");

        _addFacet(address(parimutuelFacet), _parimutuelSelectors());
        _addFacet(address(new ParimutuelViewFacet()), _parimutuelViewSelectors());

        vm.startPrank(owner);
        OwnershipFacet(address(diamond)).setParimutuelFeeSplit(500, 1_000, 8_500);
        OwnershipFacet(address(diamond)).setParimutuelConfig(address(shareToken), 250, 1);
        vm.stopPrank();
    }

    function _setParimutuelFees(uint16 entryFeeBps, uint128 minEntry) internal {
        ResolutionHarnessFacet(address(diamond)).setParimutuelConfig(address(shareToken), entryFeeBps, minEntry);
    }

    function _createParimutuelMarket(string memory label)
        internal
        returns (bytes32 marketId, uint64 expiryTime, uint256 yesPositionId, uint256 noPositionId)
    {
        expiryTime = uint64(block.timestamp + 7 days);
        marketId = _createParimutuelMarket(label, expiryTime);
        (,,,, yesPositionId, noPositionId) = StateProbeFacet(address(diamond)).getStoredMarketCore(marketId);
    }

    function _createParimutuelMarket(string memory question, uint64 expiryTime) internal returns (bytes32 marketId) {
        _approveCreatorWithEve(StateProbeFacet(address(diamond)).parimutuelCreationSeedAmount(), type(uint256).max);
        uint64 duration = expiryTime - uint64(block.timestamp);
        uint64 epochWindow = duration > 30 days ? uint64(30 days) : duration;

        vm.prank(creator);
        marketId = IParimutuelFacet(address(diamond))
            .createParimutuelMarket(
                question, "property", DEFAULT_RESOLUTION_SOURCE, uint64(block.timestamp), expiryTime, epochWindow
            );
    }

    function _buyShares(address buyer, bytes32 marketId, bool isYes, uint128 amount, address receiver)
        internal
        returns (uint128 sharesMinted)
    {
        collateralToken.mint(buyer, amount);

        vm.startPrank(buyer);
        collateralToken.approve(address(diamond), amount);
        sharesMinted = IParimutuelFacet(address(diamond)).buyShares(marketId, isYes, amount, receiver, 0);
        vm.stopPrank();
    }

    function _resolveParimutuelMarket(bytes32 marketId, uint64 expiryTime, LibEveMarket.MarketOutcome outcome)
        internal
    {
        vm.warp(expiryTime);
        MarketFactoryFacet(address(diamond)).syncMarketState(marketId);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(marketId, uint8(outcome));

        (,,,,,, uint64 disputeDeadline,) = StateProbeFacet(address(diamond)).getStoredResolution(marketId);
        vm.warp(disputeDeadline);
        IOBRResolutionFacet(address(diamond)).finalizeResolution(marketId);
    }

    function _marketIds(bytes32 first, bytes32 second) internal pure returns (bytes32[] memory marketIds) {
        marketIds = new bytes32[](2);
        marketIds[0] = first;
        marketIds[1] = second;
    }
}
