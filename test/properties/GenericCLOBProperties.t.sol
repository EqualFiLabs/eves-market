// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {OwnershipFacet} from "../../src/facets/OwnershipFacet.sol";
import {ParimutuelFacet} from "../../src/facets/ParimutuelFacet.sol";
import {ParimutuelViewFacet} from "../../src/facets/ParimutuelViewFacet.sol";
import {IBookAdminFacet} from "../../src/interfaces/IBookAdminFacet.sol";
import {IBookOrderFacet} from "../../src/interfaces/IBookOrderFacet.sol";
import {IBookTradeFacet} from "../../src/interfaces/IBookTradeFacet.sol";
import {IBookViewFacet} from "../../src/interfaces/IBookViewFacet.sol";
import {ICurveInventoryFacet} from "../../src/interfaces/ICurveInventoryFacet.sol";
import {ICurveLifecycleFacet} from "../../src/interfaces/ICurveLifecycleFacet.sol";
import {ICurveTradeFacet} from "../../src/interfaces/ICurveTradeFacet.sol";
import {ICurveViewFacet} from "../../src/interfaces/ICurveViewFacet.sol";
import {CurveCLOBTypes} from "../../src/types/CurveCLOBTypes.sol";
import {IParimutuelFacet} from "../../src/interfaces/IParimutuelFacet.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {ParimutuelShareToken} from "../../src/tokens/ParimutuelShareToken.sol";

import {CurveTradingFixture, ResolutionHarnessFacet, StateProbeFacet} from "../helpers/DiamondFixtures.sol";

contract GenericCLOBPropertiesTest is CurveTradingFixture {
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
        OwnershipFacet(address(diamond)).setParimutuelFeeSplit(500, 9_500, 0, 0, 0);
        OwnershipFacet(address(diamond)).setParimutuelEpochWindowCap(30 days);
        OwnershipFacet(address(diamond)).setOrderbookEntryFeeBps(0);
        vm.stopPrank();
    }

    // Feature: parimutuel-facet, Property 11: Generic CLOB uses the market position token
    function testFuzz_ParimutuelCurvesEscrowAndFillStoredPositionToken(uint128 makerSharesSeed, uint128 volumeSeed)
        public
    {
        uint128 makerShares = uint128(bound(uint256(makerSharesSeed), 1, 1_000_000e6));
        uint128 volume = uint128(bound(uint256(volumeSeed), 1, makerShares));
        uint128 collateralIn = uint128((uint256(volume) * 500_000_000) / 1_000_000_000);
        if (collateralIn == 0) {
            collateralIn = 1;
        }

        (bytes32 marketId, uint256 yesPositionId,) = _createParimutuelMarketWithMakerYesShares(makerShares);
        // maker has makerShares * 2 shares (epoch 0, 2x multiplier)
        uint256 actualMakerShares = shareToken.balanceOf(maker, yesPositionId);

        vm.prank(maker);
        uint256 curveId = ICurveLifecycleFacet(address(diamond))
            .postCurve(
                marketId, true, volume, 500_000_000, 500_000_000, 120, 0, LibEveMarket.PositionTokenType.PARIMUTUEL
            );
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        assertEq(shareToken.balanceOf(maker, yesPositionId), actualMakerShares - volume);
        assertEq(shareToken.balanceOf(address(diamond), yesPositionId), volume);
        assertEq(conditionalTokens.balanceOf(address(diamond), yesPositionId), 0);

        vm.prank(taker);
        collateralToken.approve(address(diamond), collateralIn);

        vm.prank(taker);
        uint128 sharesOut =
            ICurveTradeFacet(address(diamond)).fillCurve(curveId, collateralIn, 0, generation, commitment);

        assertGt(sharesOut, 0);
        assertLe(sharesOut, volume);
        assertEq(shareToken.balanceOf(taker, yesPositionId), sharesOut);
        assertEq(shareToken.balanceOf(address(diamond), yesPositionId), volume - sharesOut);
    }

    function _createParimutuelMarketWithMakerYesShares(uint128 amount)
        internal
        returns (bytes32 marketId, uint256 yesPositionId, uint256 noPositionId)
    {
        _approveCreatorWithEve(StateProbeFacet(address(diamond)).parimutuelCreationSeedAmount(), type(uint256).max);

        vm.prank(creator);
        marketId = IParimutuelFacet(address(diamond))
            .createParimutuelMarket(
                "generic clob property",
                "generic-clob",
                DEFAULT_RESOLUTION_SOURCE,
                uint64(block.timestamp),
                uint64(block.timestamp + 7 days),
                7 days
            );

        (,,,, yesPositionId, noPositionId) = StateProbeFacet(address(diamond)).getStoredMarketCore(marketId);
        (uint8 marketType, address positionToken) =
            StateProbeFacet(address(diamond)).getStoredMarketTypeAndPositionToken(marketId);
        assertEq(marketType, uint8(LibEveMarket.MarketType.PARIMUTUEL));
        assertEq(positionToken, address(shareToken));

        collateralToken.mint(maker, amount);

        vm.startPrank(maker);
        collateralToken.approve(address(diamond), amount);
        // 0% fee, epoch 0 (2x): amount collateral → amount * 2 shares
        uint128 sharesMinted = IParimutuelFacet(address(diamond)).buyShares(marketId, true, amount, maker, 0);
        assertEq(sharesMinted, amount * 2);
        shareToken.setApprovalForAll(address(diamond), true);
        vm.stopPrank();
    }
}
