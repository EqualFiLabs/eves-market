// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {OwnershipFacet} from "../../src/facets/OwnershipFacet.sol";
import {ParimutuelFacet} from "../../src/facets/ParimutuelFacet.sol";
import {ParimutuelViewFacet} from "../../src/facets/ParimutuelViewFacet.sol";
import {IMarketFactoryFacet} from "../../src/interfaces/IMarketFactoryFacet.sol";
import {IParimutuelFacet} from "../../src/interfaces/IParimutuelFacet.sol";
import {ParimutuelShareToken} from "../../src/tokens/ParimutuelShareToken.sol";

import {CurveTradingFixture, ResolutionHarnessFacet, StateProbeFacet} from "../helpers/DiamondFixtures.sol";
import {MarketFactoryTypes} from "../../src/types/MarketFactoryTypes.sol";

contract ParimutuelViewPropertiesTest is CurveTradingFixture {
    ParimutuelFacet internal parimutuelFacet;
    ParimutuelShareToken internal shareToken;

    function setUp() public override {
        super.setUp();

        parimutuelFacet = new ParimutuelFacet();
        shareToken = new ParimutuelShareToken(address(diamond), "uri://parimutuel/{id}");

        _addFacet(address(parimutuelFacet), _parimutuelSelectors());
        _addFacet(address(new ParimutuelViewFacet()), _parimutuelViewSelectors());
        ResolutionHarnessFacet(address(diamond)).setParimutuelConfig(address(shareToken), 0, 1);

        vm.startPrank(owner);
        OwnershipFacet(address(diamond)).setParimutuelFeeSplit(500, 9_500, 0);
        OwnershipFacet(address(diamond)).setParimutuelEpochWindowCap(30 days);
        OwnershipFacet(address(diamond)).setOrderbookEntryFeeBps(0);
        vm.stopPrank();
    }

    // Feature: parimutuel-facet, Property 12: balance queries type awareness
    function testFuzz_BalanceViewsUseStoredPositionTokenPerMarketType(
        uint128 clobAmountSeed,
        uint128 yesShareSeed,
        uint128 noShareSeed
    ) public {
        uint128 clobAmount = uint128(bound(uint256(clobAmountSeed), 1, 1_000_000_000e6));
        uint128 yesShares = uint128(bound(uint256(yesShareSeed), 0, 1_000_000_000e6));
        uint128 noShares = uint128(bound(uint256(noShareSeed), 0, 1_000_000_000e6));

        (bytes32 clobMarketId,,) = _createTradingMarket("view clob property", "views", 7 days);
        collateralToken.mint(maker, clobAmount);
        _splitFrom(maker, clobMarketId, clobAmount);

        bytes32 parimutuelMarketId = _createParimutuelMarket("view parimutuel property");
        if (yesShares != 0) {
            _buyShares(maker, parimutuelMarketId, true, yesShares);
        }
        if (noShares != 0) {
            _buyShares(maker, parimutuelMarketId, false, noShares);
        }

        // Epoch 0 (2x multiplier): actual share balances are 2x the collateral deposited
        uint256 expectedYes = uint256(yesShares) * 2;
        uint256 expectedNo = uint256(noShares) * 2;

        bytes32[] memory marketIds = new bytes32[](2);
        marketIds[0] = clobMarketId;
        marketIds[1] = parimutuelMarketId;

        (uint256[] memory yesBalances, uint256[] memory noBalances) =
            IMarketFactoryFacet(address(diamond)).getUserMarketPositions(maker, marketIds);
        MarketFactoryTypes.MarketSummary[] memory summaries =
            IMarketFactoryFacet(address(diamond)).getMarketSummaries(maker, marketIds);
        (uint256 parimutuelYes, uint256 parimutuelNo) =
            IParimutuelFacet(address(diamond)).getParimutuelBalances(parimutuelMarketId, maker);

        assertEq(yesBalances[0], clobAmount);
        assertEq(noBalances[0], clobAmount);
        assertEq(yesBalances[1], expectedYes);
        assertEq(noBalances[1], expectedNo);
        assertEq(summaries[0].yesBalance, clobAmount);
        assertEq(summaries[0].noBalance, clobAmount);
        assertEq(summaries[1].yesBalance, expectedYes);
        assertEq(summaries[1].noBalance, expectedNo);
        assertEq(parimutuelYes, expectedYes);
        assertEq(parimutuelNo, expectedNo);
    }

    function _createParimutuelMarket(string memory question) internal returns (bytes32 marketId) {
        _approveCreatorWithEve(StateProbeFacet(address(diamond)).parimutuelCreationSeedAmount(), type(uint256).max);

        vm.prank(creator);
        marketId = IParimutuelFacet(address(diamond))
            .createParimutuelMarket(
                question,
                "views",
                DEFAULT_RESOLUTION_SOURCE,
                uint64(block.timestamp),
                uint64(block.timestamp + 8 days),
                8 days
            );
    }

    function _buyShares(address buyer, bytes32 marketId, bool isYes, uint128 amount) internal {
        collateralToken.mint(buyer, amount);

        vm.startPrank(buyer);
        collateralToken.approve(address(diamond), amount);
        IParimutuelFacet(address(diamond)).buyShares(marketId, isYes, amount, buyer, 0);
        vm.stopPrank();
    }
}
