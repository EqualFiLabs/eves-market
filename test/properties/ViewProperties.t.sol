// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IBookAdminFacet} from "../../src/interfaces/IBookAdminFacet.sol";
import {IBookOrderFacet} from "../../src/interfaces/IBookOrderFacet.sol";
import {IBookTradeFacet} from "../../src/interfaces/IBookTradeFacet.sol";
import {IBookViewFacet} from "../../src/interfaces/IBookViewFacet.sol";
import {ICurveInventoryFacet} from "../../src/interfaces/ICurveInventoryFacet.sol";
import {ICurveLifecycleFacet} from "../../src/interfaces/ICurveLifecycleFacet.sol";
import {ICurveTradeFacet} from "../../src/interfaces/ICurveTradeFacet.sol";
import {ICurveViewFacet} from "../../src/interfaces/ICurveViewFacet.sol";
import {CurveCLOBTypes} from "../../src/types/CurveCLOBTypes.sol";
import {IFeeRouterFacet} from "../../src/interfaces/IFeeRouterFacet.sol";
import {IMarketFactoryFacet} from "../../src/interfaces/IMarketFactoryFacet.sol";
import {IOBRResolutionFacet} from "../../src/interfaces/IOBRResolutionFacet.sol";
import {OwnershipFacet} from "../../src/facets/OwnershipFacet.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";

import {SettlementFeeFixture, StateProbeFacet} from "../helpers/DiamondFixtures.sol";

contract ViewPropertiesTest is SettlementFeeFixture {
    uint256 internal constant PRICE_SCALE = 1_000_000_000;

    struct CurveContext {
        bytes32 marketId;
        uint128 collateralIn;
        uint256 curveId;
        uint256 yesPositionId;
        uint256 packed;
        uint32 storedGeneration;
        uint32 generation;
        bytes32 commitment;
    }

    struct CurvePreview {
        uint128 sharesOut;
        uint128 fee;
        uint128 price;
    }

    struct CurveExecution {
        uint128 sharesOut;
        uint96 lastTradePriceBefore;
        uint96 lastTradePriceAfter;
        uint128 totalFeeDelta;
        uint128 totalQuoteDelta;
        uint256 takerYesDelta;
    }

    struct RouteContext {
        bytes32 marketId;
        uint128 collateralIn;
        uint256 yesPositionId;
        uint256[] path;
        uint32[] generations;
        bytes32[] commitments;
    }

    struct RoutePreview {
        uint128 sharesOut;
        uint128 fee;
        uint128 averagePrice;
        uint128 unfilledCollateral;
    }

    // Feature: eve-prediction-market, Property 31: view function consistency
    function testFuzz_CurveCommitmentAndQuotePreviewMatchFill(
        uint72 priceSeed,
        uint16 feeRateSeed,
        uint128 inventorySeed,
        uint128 collateralSeed
    ) public {
        uint72 price = uint72(bound(uint256(priceSeed), 100_000_000, 900_000_000));
        uint16 feeRate = uint16(bound(uint256(feeRateSeed), 1, 10_000));
        uint128 makerInventory = uint128(bound(uint256(inventorySeed), 50_000, 500_000));
        uint128 collateralIn = uint128(bound(uint256(collateralSeed), 10_000e6, 100_000e6));
        CurveContext memory curve = _createCurveContext(price, feeRate, makerInventory, collateralIn);
        CurvePreview memory preview = _previewCurve(curve);
        CurveExecution memory execution = _executeCurveFill(curve);

        assertEq(curve.generation, curve.storedGeneration);
        assertEq(curve.commitment, keccak256(abi.encodePacked(curve.packed)));
        assertEq(execution.sharesOut, preview.sharesOut);
        assertEq(execution.lastTradePriceBefore, 0);
        assertEq(execution.lastTradePriceAfter, preview.price);
        assertEq(execution.totalFeeDelta, preview.fee);
        assertEq(execution.totalQuoteDelta, _grossCost(preview.sharesOut, preview.price) + preview.fee);
        assertEq(execution.takerYesDelta, preview.sharesOut);
    }

    // Feature: eve-prediction-market, Property 31: view function consistency
    function testFuzz_PreviewBestExecutionMatchesRoutedFill(
        uint72 firstPriceSeed,
        uint72 secondPriceSeed,
        uint128 inventorySeed
    ) public {
        uint72 firstPrice = uint72(bound(uint256(firstPriceSeed), 100_000_000, 400_000_000));
        uint72 secondPrice = uint72(bound(uint256(secondPriceSeed), uint256(firstPrice) + 100_000_000, 900_000_000));
        uint128 curveVolume = uint128(bound(uint256(inventorySeed), 20_000, 100_000));
        RouteContext memory route = _createRouteContext(firstPrice, secondPrice, curveVolume);
        RoutePreview memory preview = _previewRoute(route);
        (uint128 sharesOut, uint128 actualCollateralUsed, uint256 takerYesDelta) =
            _executeRoute(route, preview.sharesOut, preview.averagePrice);

        assertEq(preview.fee, 0);
        assertEq(sharesOut, preview.sharesOut);
        assertEq(actualCollateralUsed, route.collateralIn - preview.unfilledCollateral);
        assertEq(uint128((uint256(actualCollateralUsed) * PRICE_SCALE) / uint256(sharesOut)), preview.averagePrice);
        assertEq(takerYesDelta, preview.sharesOut);
    }

    // Feature: eve-prediction-market, Property 31: view function consistency
    function testFuzz_GetMarketStatusAndPreviewMakerFeesMatchStorage(uint128 collateralSeed, uint8 outcomeSeed) public {
        uint128 collateralIn = uint128(bound(uint256(collateralSeed), 10_000e6, 100_000e6));
        uint8 outcome = uint8(bound(uint256(outcomeSeed), 1, 3));

        (bytes32 marketId, uint64 expiryTime,) =
            _createFilledMarketWithFee("view-status", "properties", 7 days, 250_000e6, 500_000_000, 1_000, collateralIn);

        _assertMakerFeePreviewMatchesStorage(marketId);

        _expireMarket(marketId, expiryTime);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(marketId, outcome);

        _assertMarketStatusMatchesStorage(marketId);
    }

    // Feature: eve-prediction-market, Property 31: view function consistency
    function testFuzz_GetMarketPositionsAndTopOfBookReflectStoredMetadata(
        uint72 yesPriceSeed,
        uint72 noPriceSeed,
        uint128 inventorySeed
    ) public {
        uint72 yesPrice = uint72(bound(uint256(yesPriceSeed), 100_000_000, 600_000_000));
        uint72 noPrice = uint72(bound(uint256(noPriceSeed), 400_000_000, 900_000_000));
        uint128 curveVolume = uint128(bound(uint256(inventorySeed), 20_000, 100_000));

        (bytes32 marketId,,) = _createTradingMarket("view-book", "properties", 7 days);
        _splitFrom(maker, marketId, curveVolume);
        _splitFrom(trader, marketId, curveVolume);
        _approvePositions(maker);
        _approvePositions(trader);

        vm.prank(owner);
        OwnershipFacet(address(diamond)).setOrderbookEntryFeeBps(0);

        _postCurveFromMaker(marketId, true, curveVolume, yesPrice, yesPrice, 180, 0);

        vm.prank(trader);
        ICurveLifecycleFacet(address(diamond))
            .postCurve(marketId, false, curveVolume, noPrice, noPrice, 180, 0, LibEveMarket.PositionTokenType.CTF);

        _assertStoredMarketPositions(marketId);
        _assertTopOfBook(marketId, yesPrice, noPrice);
    }

    function _grossCost(uint128 sharesOut, uint128 price) internal pure returns (uint128) {
        return uint128((uint256(sharesOut) * price) / PRICE_SCALE);
    }

    function _createCurveContext(uint72 price, uint16 feeRate, uint128 makerInventory, uint128 collateralIn)
        internal
        returns (CurveContext memory curve)
    {
        curve.collateralIn = collateralIn;

        (curve.marketId,,) = _createTradingMarket("view-curve", "properties", 7 days);
        _splitFrom(maker, curve.marketId, makerInventory);
        _approvePositions(maker);

        vm.prank(owner);
        OwnershipFacet(address(diamond)).setOrderbookEntryFeeBps(feeRate);

        curve.curveId = _postCurveFromMaker(curve.marketId, true, makerInventory, price, price, 180, 0);
        (curve.packed,,, curve.storedGeneration,,,,) = StateProbeFacet(address(diamond)).getStoredCurve(curve.curveId);
        (curve.generation, curve.commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curve.curveId);
        (,, curve.yesPositionId,) = IMarketFactoryFacet(address(diamond)).getMarketPositions(curve.marketId);
    }

    function _previewCurve(CurveContext memory curve) internal view returns (CurvePreview memory preview) {
        (preview.sharesOut, preview.fee, preview.price,) =
            ICurveViewFacet(address(diamond)).previewCurveQuote(curve.curveId, curve.collateralIn);
    }

    function _executeCurveFill(CurveContext memory curve) internal returns (CurveExecution memory execution) {
        uint128 totalFeePoolBefore;
        uint128 totalQuoteVolumeBefore;
        (execution.lastTradePriceBefore, totalFeePoolBefore, totalQuoteVolumeBefore) =
            StateProbeFacet(address(diamond)).getStoredMarketTrading(curve.marketId);
        uint256 takerYesBefore = conditionalTokens.balanceOf(taker, curve.yesPositionId);

        vm.startPrank(taker);
        collateralToken.approve(address(diamond), curve.collateralIn);
        execution.sharesOut = ICurveTradeFacet(address(diamond))
            .fillCurve(curve.curveId, curve.collateralIn, 0, curve.generation, curve.commitment);
        vm.stopPrank();

        uint128 totalFeePoolAfter;
        uint128 totalQuoteVolumeAfter;
        (execution.lastTradePriceAfter, totalFeePoolAfter, totalQuoteVolumeAfter) =
            StateProbeFacet(address(diamond)).getStoredMarketTrading(curve.marketId);
        execution.totalFeeDelta = totalFeePoolAfter - totalFeePoolBefore;
        execution.totalQuoteDelta = totalQuoteVolumeAfter - totalQuoteVolumeBefore;
        execution.takerYesDelta = conditionalTokens.balanceOf(taker, curve.yesPositionId) - takerYesBefore;
    }

    function _createRouteContext(uint72 firstPrice, uint72 secondPrice, uint128 curveVolume)
        internal
        returns (RouteContext memory route)
    {
        route.collateralIn = _grossCost(curveVolume, firstPrice) + _grossCost(curveVolume / 2, secondPrice);

        (route.marketId,,) = _createTradingMarket("view-route", "properties", 7 days);
        _splitFrom(maker, route.marketId, curveVolume);
        _splitFrom(trader, route.marketId, curveVolume);
        _approvePositions(maker);
        _approvePositions(trader);

        vm.prank(owner);
        OwnershipFacet(address(diamond)).setOrderbookEntryFeeBps(0);

        uint256 firstCurveId = _postCurveFromMaker(route.marketId, true, curveVolume, firstPrice, firstPrice, 180, 0);

        vm.prank(trader);
        uint256 secondCurveId = ICurveLifecycleFacet(address(diamond))
            .postCurve(
                route.marketId, true, curveVolume, secondPrice, secondPrice, 180, 0, LibEveMarket.PositionTokenType.CTF
            );

        route.path = new uint256[](2);
        route.generations = new uint32[](2);
        route.commitments = new bytes32[](2);
        route.path[0] = firstCurveId;
        route.path[1] = secondCurveId;
        (route.generations[0], route.commitments[0]) =
            ICurveViewFacet(address(diamond)).getCurveCommitment(firstCurveId);
        (route.generations[1], route.commitments[1]) =
            ICurveViewFacet(address(diamond)).getCurveCommitment(secondCurveId);
        (,, route.yesPositionId,) = IMarketFactoryFacet(address(diamond)).getMarketPositions(route.marketId);
    }

    function _previewRoute(RouteContext memory route) internal view returns (RoutePreview memory preview) {
        (preview.sharesOut, preview.fee, preview.averagePrice, preview.unfilledCollateral) = ICurveViewFacet(
                address(diamond)
            ).previewBestExecution(route.marketId, true, route.collateralIn, route.path);
    }

    function _executeRoute(RouteContext memory route, uint128 minSharesOut, uint128 maxAveragePrice)
        internal
        returns (uint128 sharesOut, uint128 actualCollateralUsed, uint256 takerYesDelta)
    {
        (,, uint128 totalQuoteVolumeBefore) = StateProbeFacet(address(diamond)).getStoredMarketTrading(route.marketId);
        uint256 takerYesBefore = conditionalTokens.balanceOf(taker, route.yesPositionId);

        sharesOut = _fillBestAsTaker(route, minSharesOut, maxAveragePrice);

        (,, uint128 totalQuoteVolumeAfter) = StateProbeFacet(address(diamond)).getStoredMarketTrading(route.marketId);
        actualCollateralUsed = totalQuoteVolumeAfter - totalQuoteVolumeBefore;
        takerYesDelta = conditionalTokens.balanceOf(taker, route.yesPositionId) - takerYesBefore;
    }

    function _fillBestAsTaker(RouteContext memory route, uint128 minSharesOut, uint128 maxAveragePrice)
        internal
        returns (uint128 sharesOut)
    {
        vm.startPrank(taker);
        collateralToken.approve(address(diamond), route.collateralIn);
        sharesOut =
        ICurveTradeFacet(address(diamond))
        .fillBest(
            CurveCLOBTypes.FillBestParams({
                marketId: route.marketId,
                isYesSide: true,
                maxCollateralIn: route.collateralIn,
                minSharesOut: minSharesOut,
                maxAveragePrice: maxAveragePrice,
                curveIds: route.path,
                expectedGenerations: route.generations,
                expectedCommitments: route.commitments,
                payer: taker,
                receiver: taker
            })
        )
        .sharesOut;
        vm.stopPrank();
    }

    function _assertStoredMarketPositions(bytes32 marketId) internal view {
        (bytes32 conditionId, address collateralAddress, uint256 yesPositionId, uint256 noPositionId) =
            IMarketFactoryFacet(address(diamond)).getMarketPositions(marketId);
        (
            address storedCollateral,,,
            bytes32 storedConditionId,
            uint256 storedYesPositionId,
            uint256 storedNoPositionId
        ) = StateProbeFacet(address(diamond)).getStoredMarketCore(marketId);

        assertEq(conditionId, storedConditionId);
        assertEq(collateralAddress, storedCollateral);
        assertEq(yesPositionId, storedYesPositionId);
        assertEq(noPositionId, storedNoPositionId);
    }

    function _assertMakerFeePreviewMatchesStorage(bytes32 marketId) internal view {
        (uint128 previewAccrued, uint128 previewClaimed, uint128 previewClaimable) =
            IFeeRouterFacet(address(diamond)).previewMakerFees(marketId, maker);
        (, uint128 storedAccrued, uint128 storedClaimed) =
            StateProbeFacet(address(diamond)).getStoredMakerAccounting(marketId, maker);

        assertEq(previewAccrued, storedAccrued);
        assertEq(previewClaimed, storedClaimed);
        assertEq(previewClaimable, storedAccrued - storedClaimed);
    }

    function _assertMarketStatusMatchesStorage(bytes32 marketId) internal view {
        (uint8 viewState, uint8 viewOutcome, uint64 viewDisputeDeadline, uint128 viewCreatorFeesEscrowed) =
            IOBRResolutionFacet(address(diamond)).getMarketStatus(marketId);
        (,,,,, uint8 storedOutcome, uint8 storedState,) =
            StateProbeFacet(address(diamond)).getStoredMarketStatus(marketId);
        (,,,,,, uint64 storedDisputeDeadline,) = StateProbeFacet(address(diamond)).getStoredResolution(marketId);
        (uint128 storedCreatorFeesEscrowed,,,) = StateProbeFacet(address(diamond)).getStoredMarketFees(marketId);

        assertEq(viewState, storedState);
        assertEq(viewOutcome, storedOutcome);
        assertEq(viewDisputeDeadline, storedDisputeDeadline);
        assertEq(viewCreatorFeesEscrowed, storedCreatorFeesEscrowed);
    }

    function _assertTopOfBook(bytes32 marketId, uint72 yesPrice, uint72 noPrice) internal view {
        (
            uint128 bestYesPrice,
            uint128 bestNoPrice,
            uint128 midpointPrice,
            uint128 lastTradePrice,
            uint128 displayPrice
        ) = ICurveViewFacet(address(diamond)).getMarketTopOfBook(marketId);

        assertEq(bestYesPrice, yesPrice);
        assertEq(bestNoPrice, noPrice);
        assertEq(midpointPrice, uint128((uint256(yesPrice) + (PRICE_SCALE - noPrice)) / 2));
        assertEq(lastTradePrice, 0);
        assertEq(displayPrice, midpointPrice);
    }
}
