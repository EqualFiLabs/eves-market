// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {StdInvariant} from "../../lib/forge-std/src/StdInvariant.sol";
import {Test} from "../../lib/forge-std/src/Test.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IBookAdminFacet} from "../../src/interfaces/IBookAdminFacet.sol";
import {IBookOrderFacet} from "../../src/interfaces/IBookOrderFacet.sol";
import {IBookTradeFacet} from "../../src/interfaces/IBookTradeFacet.sol";
import {IBookViewFacet} from "../../src/interfaces/IBookViewFacet.sol";
import {ICurveInventoryFacet} from "../../src/interfaces/ICurveInventoryFacet.sol";
import {ICurveLifecycleFacet} from "../../src/interfaces/ICurveLifecycleFacet.sol";
import {ICurveTradeFacet} from "../../src/interfaces/ICurveTradeFacet.sol";
import {ICurveViewFacet} from "../../src/interfaces/ICurveViewFacet.sol";
import {CurveCLOBTypes} from "../../src/types/CurveCLOBTypes.sol";
import {IMarketFactoryFacet} from "../../src/interfaces/IMarketFactoryFacet.sol";
import {LibCurvePacking} from "../../src/libraries/LibCurvePacking.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";

import {CurveTradingFixture, StateProbeFacet} from "../helpers/DiamondFixtures.sol";
import {MockConditionalTokens} from "../helpers/MockConditionalTokens.sol";
import {MockEveToken} from "../helpers/MockEveToken.sol";
import {MockUSDG} from "../helpers/MockUSDG.sol";

contract TradingInvariantHandler is Test {
    uint72 internal constant PRICE_SCALE = 1_000_000_000;
    string internal constant DEFAULT_RESOLUTION_SOURCE = "Invariant harness settlement rules and primary source.";

    address internal immutable diamond;
    MockUSDG internal immutable collateralToken;
    MockConditionalTokens internal immutable conditionalTokens;
    MockEveToken internal immutable eveToken;
    address internal immutable creator;

    address[] internal actors;
    bytes32[] public marketIds;
    uint256[] public curveIds;
    uint256 internal nextMarketNonce;

    constructor(
        address diamond_,
        MockUSDG collateralToken_,
        MockConditionalTokens conditionalTokens_,
        MockEveToken eveToken_,
        address creator_,
        address[] memory actors_
    ) {
        diamond = diamond_;
        collateralToken = collateralToken_;
        conditionalTokens = conditionalTokens_;
        eveToken = eveToken_;
        creator = creator_;

        for (uint256 index = 0; index < actors_.length; ++index) {
            actors.push(actors_[index]);

            vm.startPrank(actors_[index]);
            collateralToken.approve(diamond_, type(uint256).max);
            conditionalTokens.setApprovalForAll(diamond_, true);
            vm.stopPrank();
        }

        eveToken.mint(creator_, 20_000e18);
        vm.startPrank(creator_);
        collateralToken.approve(diamond_, type(uint256).max);
        eveToken.approve(diamond_, type(uint256).max);
        conditionalTokens.setApprovalForAll(diamond_, true);
        vm.stopPrank();
    }

    function marketCount() external view returns (uint256) {
        return marketIds.length;
    }

    function curveCount() external view returns (uint256) {
        return curveIds.length;
    }

    function createMarket(uint64 durationSeed) external {
        uint64 duration = uint64(bound(uint256(durationSeed), 2 hours, 30 days));
        uint64 expiryTime = uint64(block.timestamp) + duration;
        string memory question = string.concat("stateful-", vm.toString(nextMarketNonce));
        unchecked {
            ++nextMarketNonce;
        }

        vm.prank(creator);
        try IMarketFactoryFacet(diamond).createMarket(question, "invariant", DEFAULT_RESOLUTION_SOURCE, uint64(block.timestamp), expiryTime, 0, true) returns (
            bytes32 marketId
        ) {
            marketIds.push(marketId);
        } catch {}
    }

    function splitInventory(uint256 actorSeed, uint256 marketSeed, uint128 collateralSeed) external {
        if (marketIds.length == 0) {
            return;
        }

        address actor = _actor(actorSeed);
        bytes32 marketId = marketIds[marketSeed % marketIds.length];
        uint256 maxAmount = _min(collateralToken.balanceOf(actor), 250_000e6);
        if (maxAmount < 1e6) {
            return;
        }

        uint128 collateralAmount = uint128(bound(uint256(collateralSeed), 1e6, maxAmount));

        vm.prank(actor);
        try ICurveInventoryFacet(diamond).splitInventory(marketId, collateralAmount) {} catch {}
    }

    function mergeInventory(uint256 actorSeed, uint256 marketSeed, uint128 shareSeed) external {
        if (marketIds.length == 0) {
            return;
        }

        address actor = _actor(actorSeed);
        bytes32 marketId = marketIds[marketSeed % marketIds.length];
        (,, uint256 yesPositionId, uint256 noPositionId) = IMarketFactoryFacet(diamond).getMarketPositions(marketId);

        uint256 maxShareAmount =
            _min(conditionalTokens.balanceOf(actor, yesPositionId), conditionalTokens.balanceOf(actor, noPositionId));
        if (maxShareAmount == 0) {
            return;
        }

        uint128 shareAmount = uint128(bound(uint256(shareSeed), 1, maxShareAmount));

        vm.prank(actor);
        try ICurveInventoryFacet(diamond).mergeInventory(marketId, shareAmount) {} catch {}
    }

    function postCurve(
        uint256 actorSeed,
        uint256 marketSeed,
        bool preferYesSide,
        uint128 volumeSeed,
        uint72 startPriceSeed,
        uint72 endPriceSeed,
        uint24 durationSeed
    ) external {
        if (marketIds.length == 0) {
            return;
        }

        address maker = _actor(actorSeed);
        bytes32 marketId = marketIds[marketSeed % marketIds.length];
        (,, uint256 yesPositionId, uint256 noPositionId) = IMarketFactoryFacet(diamond).getMarketPositions(marketId);

        bool isYesSide = preferYesSide;
        uint256 availableInventory = conditionalTokens.balanceOf(maker, isYesSide ? yesPositionId : noPositionId);
        if (availableInventory == 0) {
            isYesSide = !isYesSide;
            availableInventory = conditionalTokens.balanceOf(maker, isYesSide ? yesPositionId : noPositionId);
        }
        if (availableInventory == 0) {
            return;
        }

        uint128 volume = uint128(bound(uint256(volumeSeed), 1, _min(availableInventory, 100_000e6)));
        uint72 startPrice = uint72(bound(uint256(startPriceSeed), 1, PRICE_SCALE - 1));
        uint72 endPrice = uint72(bound(uint256(endPriceSeed), 1, PRICE_SCALE - 1));
        uint24 durationMinutes = uint24(bound(uint256(durationSeed), 1, 720));

        vm.prank(maker);
        try ICurveLifecycleFacet(diamond)
            .postCurve(
                marketId,
                isYesSide,
                volume,
                startPrice,
                endPrice,
                durationMinutes,
                0,
                LibEveMarket.PositionTokenType.CTF
            ) returns (
            uint256 curveId
        ) {
            curveIds.push(curveId);
        } catch {}
    }

    function updateCurve(uint256 curveSeed, uint72 startPriceSeed, uint72 endPriceSeed, uint24 durationSeed) external {
        if (curveIds.length == 0) {
            return;
        }

        uint256 curveId = curveIds[curveSeed % curveIds.length];
        (,,, uint32 generation, bool active,, address maker, bytes32 marketId) =
            StateProbeFacet(diamond).getStoredCurve(curveId);
        if (!active || maker == address(0) || marketId == bytes32(0)) {
            return;
        }

        (,,,,,, uint8 state,) = StateProbeFacet(diamond).getStoredMarketStatus(marketId);
        if (state != 1) {
            return;
        }

        uint72 startPrice = uint72(bound(uint256(startPriceSeed), 1, PRICE_SCALE - 1));
        uint72 endPrice = uint72(bound(uint256(endPriceSeed), 1, PRICE_SCALE - 1));
        uint24 durationMinutes = uint24(bound(uint256(durationSeed), 1, 720));
        uint256 newPacked = LibCurvePacking.pack(startPrice, endPrice, durationMinutes, 0);

        vm.prank(maker);
        try ICurveLifecycleFacet(diamond).updateCurve(curveId, newPacked, generation) {} catch {}
    }

    function cancelCurve(uint256 curveSeed) external {
        if (curveIds.length == 0) {
            return;
        }

        uint256 curveId = curveIds[curveSeed % curveIds.length];
        (,,,, bool active,, address maker,) = StateProbeFacet(diamond).getStoredCurve(curveId);
        if (!active || maker == address(0)) {
            return;
        }

        vm.prank(maker);
        try ICurveLifecycleFacet(diamond).cancelCurve(curveId) {} catch {}
    }

    function fillCurve(uint256 actorSeed, uint256 curveSeed, uint128 collateralSeed) external {
        if (curveIds.length == 0) {
            return;
        }

        uint256 curveId = curveIds[curveSeed % curveIds.length];
        (,,,, bool active,,,) = StateProbeFacet(diamond).getStoredCurve(curveId);
        if (!active) {
            return;
        }

        address taker = _actor(actorSeed);
        uint256 maxAmount = _min(collateralToken.balanceOf(taker), 100_000e6);
        if (maxAmount < 1e6) {
            return;
        }

        uint128 collateralIn = uint128(bound(uint256(collateralSeed), 1e6, maxAmount));
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(diamond).getCurveCommitment(curveId);
        (uint128 sharesOut,,,) = ICurveViewFacet(diamond).previewCurveQuote(curveId, collateralIn);
        if (sharesOut == 0) {
            return;
        }

        vm.prank(taker);
        try ICurveTradeFacet(diamond).fillCurve(curveId, collateralIn, 0, generation, commitment) returns (uint128) {}
            catch {}
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _min(uint256 left, uint256 right) internal pure returns (uint256) {
        return left < right ? left : right;
    }
}

contract TradingStatefulInvariantsTest is StdInvariant, CurveTradingFixture {
    TradingInvariantHandler internal handler;
    address[] internal trackedActors;

    function setUp() public override {
        super.setUp();

        trackedActors.push(maker);
        trackedActors.push(trader);
        trackedActors.push(taker);
        trackedActors.push(outsider);
        for (uint256 index = 0; index < trackedActors.length; ++index) {
            collateralToken.mint(trackedActors[index], 10_000_000e6);
        }
        collateralToken.mint(creator, 10_000_000e6);

        handler = new TradingInvariantHandler(
            address(diamond), collateralToken, conditionalTokens, eveToken, creator, trackedActors
        );

        handler.createMarket(7 days);
        targetContract(address(handler));
    }

    function invariant_CtfInventoryTracksLockedCollateral() public view {
        uint256 totalYes;
        uint256 totalNo;
        uint256 marketCount = handler.marketCount();

        for (uint256 index = 0; index < marketCount; ++index) {
            bytes32 marketId = handler.marketIds(index);
            (,, uint256 yesPositionId, uint256 noPositionId) =
                IMarketFactoryFacet(address(diamond)).getMarketPositions(marketId);
            totalYes += _positionSupplyAcrossActors(yesPositionId);
            totalNo += _positionSupplyAcrossActors(noPositionId);
        }

        uint256 lockedCollateral = conditionalTokens.collateralBalance(IERC20(address(collateralToken)));

        assertEq(totalYes, totalNo);
        assertEq(totalYes, lockedCollateral);
    }

    function invariant_FeeBucketsMatchMarketTotals() public view {
        uint256 marketCount = handler.marketCount();

        for (uint256 index = 0; index < marketCount; ++index) {
            bytes32 marketId = handler.marketIds(index);
            (, uint128 totalFeePool, uint128 totalQuoteVolume) =
                StateProbeFacet(address(diamond)).getStoredMarketTrading(marketId);
            (uint128 creatorFeesEscrowed, uint128 protocolFeesAccrued,,) =
                StateProbeFacet(address(diamond)).getStoredMarketFees(marketId);

            uint256 makerQuoteVolume;
            uint256 makerFeesAccrued;

            for (uint256 actorIndex = 0; actorIndex < trackedActors.length; ++actorIndex) {
                (uint128 storedQuoteVolume, uint128 storedFeesAccrued, uint128 storedFeesClaimed) =
                    StateProbeFacet(address(diamond)).getStoredMakerAccounting(marketId, trackedActors[actorIndex]);

                makerQuoteVolume += storedQuoteVolume;
                makerFeesAccrued += storedFeesAccrued;
                assertGe(storedFeesAccrued, storedFeesClaimed);
            }

            assertEq(totalQuoteVolume, makerQuoteVolume);
            assertEq(totalFeePool, makerFeesAccrued + creatorFeesEscrowed + protocolFeesAccrued);
        }
    }

    function invariant_CurveIdsStaySequential() public view {
        assertEq(StateProbeFacet(address(diamond)).nextCurveId(), handler.curveCount());
    }

    function _positionSupplyAcrossActors(uint256 positionId) internal view returns (uint256 totalSupply) {
        totalSupply += conditionalTokens.balanceOf(address(diamond), positionId);

        for (uint256 index = 0; index < trackedActors.length; ++index) {
            totalSupply += conditionalTokens.balanceOf(trackedActors[index], positionId);
        }
    }
}
