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
import {ITradeRouter} from "../../src/interfaces/ITradeRouter.sol";
import {IMarketFactoryFacet} from "../../src/interfaces/IMarketFactoryFacet.sol";
import {TradeRouterFacet} from "../../src/facets/TradeRouterFacet.sol";
import {TradeRouterSellFacet} from "../../src/facets/TradeRouterSellFacet.sol";
import {OwnershipFacet} from "../../src/facets/OwnershipFacet.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {LibRouter} from "../../src/libraries/LibRouter.sol";

import {EveUSDCRouterFixture, ResolutionHarnessFacet, StateProbeFacet} from "../helpers/DiamondFixtures.sol";
import {MockConditionalTokens} from "../helpers/MockConditionalTokens.sol";

contract TradeRouterTest is EveUSDCRouterFixture {
    ITradeRouter internal tradeRouter;
    address internal alternateReceiver;

    function setUp() public override {
        super.setUp();
        _addFacet(address(new TradeRouterFacet()), _tradeRouterSelectors());
        _addFacet(address(new TradeRouterSellFacet()), _tradeRouterSellSelectors());
        _addFacet(address(new ResolutionHarnessFacet()), _resolutionHarnessSelectors());
        tradeRouter = ITradeRouter(address(diamond));
        alternateReceiver = makeAddr("trade-router-alt-receiver");
    }

    function test_BuyWithUSDCWrapsExecutesRefundsAndHonorsReceiver() public {
        (bytes32 marketId,) = _createTradingMarket("trade-router-usdc", 7 days);
        _splitFromMaker(marketId, 10e18);
        _approvePositions(maker);

        uint256 curveId = _postCurveFromMaker(marketId, true, 6e18, DEFAULT_FLAT_PRICE, DEFAULT_FLAT_PRICE, 180);
        uint256[] memory curveIds = new uint256[](1);
        curveIds[0] = curveId;

        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        (uint128 previewSharesOut,,,) =
            ICurveViewFacet(address(diamond)).previewBestExecution(marketId, true, 5e18, curveIds);

        usdc.mint(taker, 5e6);
        vm.prank(taker);
        usdc.approve(address(diamond), type(uint256).max);

        uint256 takerUsdcBefore = usdc.balanceOf(taker);
        uint256 diamondEveUsdcBefore = eveUSDC.balanceOf(address(diamond));

        CurveCLOBTypes.FillBestParams memory params = CurveCLOBTypes.FillBestParams({
            marketId: marketId,
            isYesSide: true,
            maxCollateralIn: 5e6,
            minSharesOut: 1,
            maxAveragePrice: type(uint128).max,
            curveIds: curveIds,
            expectedGenerations: _singleGeneration(generation),
            expectedCommitments: _singleCommitment(commitment),
            payer: taker,
            receiver: alternateReceiver
        });

        vm.prank(taker);
        CurveCLOBTypes.FillBestResult memory result = tradeRouter.buyWithUSDC(params);
        (,, uint256 yesPositionId,) = IMarketFactoryFacet(address(diamond)).getMarketPositions(marketId);

        assertEq(result.sharesOut, previewSharesOut);
        assertEq(usdc.balanceOf(taker), takerUsdcBefore - result.collateralUsed);
        assertEq(conditionalTokens.balanceOf(alternateReceiver, yesPositionId), result.sharesOut);
        assertEq(conditionalTokens.balanceOf(taker, yesPositionId), 0);
        assertEq(usdc.balanceOf(address(diamond)), 0);
        assertEq(eveUSDC.balanceOf(address(diamond)), diamondEveUsdcBefore);
    }

    function test_BuyWithEveUSDCUsesCanonicalCollateralAndRefundsUnusedAmount() public {
        (bytes32 marketId,) = _createTradingMarket("trade-router-eveusdc", 7 days);
        _splitFromMaker(marketId, 12e18);
        _approvePositions(maker);

        uint256 curveId = _postCurveFromMaker(marketId, true, 8e18, DEFAULT_FLAT_PRICE, DEFAULT_FLAT_PRICE, 180);
        uint256[] memory curveIds = new uint256[](1);
        curveIds[0] = curveId;

        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        (uint128 previewSharesOut,,,) =
            ICurveViewFacet(address(diamond)).previewBestExecution(marketId, true, 6e18, curveIds);

        vm.prank(taker);
        eveUSDC.approve(address(diamond), type(uint256).max);

        uint256 takerEveUsdcBefore = eveUSDC.balanceOf(taker);
        uint256 diamondEveUsdcBefore = eveUSDC.balanceOf(address(diamond));

        CurveCLOBTypes.FillBestParams memory params = CurveCLOBTypes.FillBestParams({
            marketId: marketId,
            isYesSide: true,
            maxCollateralIn: 6e18,
            minSharesOut: 1,
            maxAveragePrice: type(uint128).max,
            curveIds: curveIds,
            expectedGenerations: _singleGeneration(generation),
            expectedCommitments: _singleCommitment(commitment),
            payer: taker,
            receiver: taker
        });

        vm.prank(taker);
        CurveCLOBTypes.FillBestResult memory result = tradeRouter.buyWithEveUSDC(params);
        (,, uint256 yesPositionId,) = IMarketFactoryFacet(address(diamond)).getMarketPositions(marketId);

        assertEq(result.sharesOut, previewSharesOut);
        assertEq(eveUSDC.balanceOf(taker), takerEveUsdcBefore - result.collateralUsed);
        assertEq(conditionalTokens.balanceOf(taker, yesPositionId), result.sharesOut);
        assertEq(eveUSDC.balanceOf(address(diamond)), diamondEveUsdcBefore);
    }

    function test_BuyWithEveUSDCAllowsRetainedMakerAndCreatorFees() public {
        _configureSmallFeeSplit();
        (bytes32 marketId,) = _createTradingMarket("trade-router-eveusdc-retained-fees", 7 days);
        _splitFromMaker(marketId, 30_000e18);
        _approvePositions(maker);

        uint256 curveId = _postCurveFromMaker(marketId, true, 25_000e18, 480_000_000, 480_000_000, 180);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        CurveCLOBTypes.FillBestParams memory params =
            _singleCurveBuyParams(marketId, curveId, generation, commitment, 50e18);

        uint256 diamondEveUsdcBefore = eveUSDC.balanceOf(address(diamond));

        vm.prank(taker);
        CurveCLOBTypes.FillBestResult memory result = tradeRouter.buyWithEveUSDC(params);

        uint128 retainedFeeBalance = _retainedFeeBalance(result.feePaid);
        assertGt(retainedFeeBalance, 0);
        assertEq(eveUSDC.balanceOf(address(diamond)), diamondEveUsdcBefore + retainedFeeBalance);
    }

    function test_BuyWithUSDCAllowsRetainedMakerAndCreatorFees() public {
        _configureSmallFeeSplit();
        (bytes32 marketId,) = _createTradingMarket("trade-router-usdc-retained-fees", 7 days);
        _splitFromMaker(marketId, 30_000e18);
        _approvePositions(maker);

        uint256 curveId = _postCurveFromMaker(marketId, true, 25_000e18, 480_000_000, 480_000_000, 180);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        CurveCLOBTypes.FillBestParams memory params =
            _singleCurveBuyParams(marketId, curveId, generation, commitment, 50e6);

        usdc.mint(taker, 50e6);
        vm.prank(taker);
        usdc.approve(address(diamond), type(uint256).max);

        uint256 diamondUsdcBefore = usdc.balanceOf(address(diamond));
        uint256 diamondEveUsdcBefore = eveUSDC.balanceOf(address(diamond));

        vm.prank(taker);
        CurveCLOBTypes.FillBestResult memory result = tradeRouter.buyWithUSDC(params);

        uint256 retainedFeeBalance = eveUSDC.balanceOf(address(diamond)) - diamondEveUsdcBefore;
        uint128 retainedFeeFloor = _retainedFeeBalance(uint128(uint256(result.feePaid) * USDC_TO_EVEUSDC_SCALE));
        assertGt(retainedFeeBalance, 0);
        assertEq(usdc.balanceOf(address(diamond)), diamondUsdcBefore);
        assertApproxEqAbs(retainedFeeBalance, retainedFeeFloor, USDC_TO_EVEUSDC_SCALE);
    }

    function test_SellWithEveUSDCMergesOppositeCurveAndReturnsCollateral() public {
        (bytes32 marketId,) = _createTradingMarket("trade-router-sell-eveusdc", 7 days);
        _splitFromMaker(marketId, 10e18);
        _approvePositions(maker);

        uint72 noPrice = 600_000_000;
        uint256 curveId = _postCurveFromMaker(marketId, false, 6e18, noPrice, noPrice, 180);
        vm.prank(taker);
        ICurveInventoryFacet(address(diamond)).splitInventory(marketId, 4e18);
        _approvePositions(taker);

        (,, uint256 yesPositionId, uint256 noPositionId) =
            IMarketFactoryFacet(address(diamond)).getMarketPositions(marketId);

        uint256 makerEveUsdcBefore = eveUSDC.balanceOf(maker);
        uint256 receiverEveUsdcBefore = eveUSDC.balanceOf(alternateReceiver);
        ITradeRouter.SellBestParams memory params = _singleCurveSellParams(marketId, true, 3e18, curveId);

        (uint128 expectedOut, uint128 expectedFee, uint128 expectedGrossCost) = _expectedSellAmounts(3e18, noPrice);
        _assertSellPreview(params, 3e18, expectedOut, expectedFee, 0);

        vm.prank(taker);
        ITradeRouter.SellBestResult memory result = tradeRouter.sellWithEveUSDC(params);

        assertEq(result.sharesSold, 3e18);
        assertEq(result.collateralOut, expectedOut);
        assertEq(result.feePaid, expectedFee);
        assertEq(result.unfilledShares, 0);
        assertEq(eveUSDC.balanceOf(alternateReceiver), receiverEveUsdcBefore + expectedOut);
        assertEq(eveUSDC.balanceOf(maker), makerEveUsdcBefore + expectedGrossCost);
        (,, uint128 totalQuoteVolume) = StateProbeFacet(address(diamond)).getStoredMarketTrading(marketId);
        (uint128 makerQuoteVolume,,) = StateProbeFacet(address(diamond)).getStoredMakerAccounting(marketId, maker);
        assertEq(totalQuoteVolume, expectedGrossCost + expectedFee);
        assertEq(makerQuoteVolume, totalQuoteVolume);
        assertEq(conditionalTokens.balanceOf(taker, yesPositionId), 1e18);
        assertEq(conditionalTokens.balanceOf(taker, noPositionId), 4e18);
    }

    function test_SellWithUSDCUnwrapsNetCollateralToReceiver() public {
        (bytes32 marketId,) = _createTradingMarket("trade-router-sell-usdc", 7 days);
        _splitFromMaker(marketId, 10e18);
        _approvePositions(maker);

        uint72 yesPrice = 400_000_000;
        uint256 curveId = _postCurveFromMaker(marketId, true, 6e18, yesPrice, yesPrice, 180);
        vm.prank(taker);
        ICurveInventoryFacet(address(diamond)).splitInventory(marketId, 4e18);
        _approvePositions(taker);

        (,, uint256 yesPositionId, uint256 noPositionId) =
            IMarketFactoryFacet(address(diamond)).getMarketPositions(marketId);

        uint256 makerEveUsdcBefore = eveUSDC.balanceOf(maker);
        uint256 receiverUsdcBefore = usdc.balanceOf(alternateReceiver);
        uint256 diamondUsdcBefore = usdc.balanceOf(address(diamond));
        ITradeRouter.SellBestParams memory params = _singleCurveSellParams(marketId, false, 2e18, curveId);

        (uint128 expectedOut, uint128 expectedFee, uint128 expectedGrossCost) = _expectedSellAmounts(2e18, yesPrice);
        uint128 expectedUsdcOut = uint128(uint256(expectedOut) / USDC_TO_EVEUSDC_SCALE);
        uint128 expectedUsdcFee = uint128(uint256(expectedFee) / USDC_TO_EVEUSDC_SCALE);

        vm.prank(taker);
        ITradeRouter.SellBestResult memory result = tradeRouter.sellWithUSDC(params);

        assertEq(result.sharesSold, 2e18);
        assertEq(result.collateralOut, expectedUsdcOut);
        assertEq(result.feePaid, expectedUsdcFee);
        assertEq(usdc.balanceOf(alternateReceiver), receiverUsdcBefore + expectedUsdcOut);
        assertEq(eveUSDC.balanceOf(maker), makerEveUsdcBefore + expectedGrossCost);
        assertEq(usdc.balanceOf(address(diamond)), diamondUsdcBefore);
        assertEq(conditionalTokens.balanceOf(taker, yesPositionId), 4e18);
        assertEq(conditionalTokens.balanceOf(taker, noPositionId), 2e18);
    }

    function test_SplitWithUSDCWrapsAndSendsMatchedInventory() public {
        (bytes32 marketId,) = _createTradingMarket("trade-router-split-usdc", 7 days);
        uint128 usdcAmount = 5e6;

        usdc.mint(taker, usdcAmount);
        vm.prank(taker);
        usdc.approve(address(diamond), type(uint256).max);

        uint256 diamondUsdcBefore = usdc.balanceOf(address(diamond));

        vm.prank(taker);
        uint128 sharesMinted = tradeRouter.splitWithUSDC(marketId, usdcAmount, alternateReceiver);
        (,, uint256 yesPositionId, uint256 noPositionId) =
            IMarketFactoryFacet(address(diamond)).getMarketPositions(marketId);

        assertEq(sharesMinted, 5e18);
        assertEq(conditionalTokens.balanceOf(alternateReceiver, yesPositionId), 5e18);
        assertEq(conditionalTokens.balanceOf(alternateReceiver, noPositionId), 5e18);
        assertEq(conditionalTokens.balanceOf(taker, yesPositionId), 0);
        assertEq(conditionalTokens.balanceOf(taker, noPositionId), 0);
        assertEq(usdc.balanceOf(address(diamond)), diamondUsdcBefore);
    }

    function test_SplitWithUSDCUsesStoredPositionTokenAfterDefaultChange() public {
        (bytes32 marketId,) = _createTradingMarket("trade-router-stored-token", 7 days);
        MockConditionalTokens replacementDefault = new MockConditionalTokens();
        uint128 usdcAmount = 5e6;

        vm.prank(owner);
        OwnershipFacet(address(diamond)).setDefaultConditionalTokens(address(replacementDefault));

        usdc.mint(taker, usdcAmount);
        vm.prank(taker);
        usdc.approve(address(diamond), type(uint256).max);

        vm.prank(taker);
        uint128 sharesMinted = tradeRouter.splitWithUSDC(marketId, usdcAmount, alternateReceiver);
        (,, uint256 yesPositionId, uint256 noPositionId) =
            IMarketFactoryFacet(address(diamond)).getMarketPositions(marketId);

        uint128 expectedShares = uint128(uint256(usdcAmount) * USDC_TO_EVEUSDC_SCALE);
        assertEq(sharesMinted, expectedShares);
        assertEq(conditionalTokens.balanceOf(alternateReceiver, yesPositionId), expectedShares);
        assertEq(conditionalTokens.balanceOf(alternateReceiver, noPositionId), expectedShares);
        assertEq(replacementDefault.balanceOf(alternateReceiver, yesPositionId), 0);
        assertEq(replacementDefault.balanceOf(alternateReceiver, noPositionId), 0);
    }

    function test_BuyRouterAllowsParimutuelPositionTokenMarketsButCTFOnlyInventoryFlowsReject() public {
        vm.prank(owner);
        OwnershipFacet(address(diamond)).setOrderbookEntryFeeBps(0);

        (bytes32 marketId,) = _createTradingMarket("trade-router-parimutuel-guard", 7 days);
        _splitFromMaker(marketId, 5e6);
        _approvePositions(maker);

        ResolutionHarnessFacet(address(diamond))
            .setMarketTypeAndPositionToken(
                marketId, uint8(LibEveMarket.MarketType.PARIMUTUEL), address(conditionalTokens)
            );

        vm.prank(maker);
        uint256 eveUsdcCurveId = ICurveLifecycleFacet(address(diamond))
            .postCurve(
                marketId,
                true,
                2e6,
                DEFAULT_FLAT_PRICE,
                DEFAULT_FLAT_PRICE,
                180,
                0,
                LibEveMarket.PositionTokenType.PARIMUTUEL
            );
        vm.prank(maker);
        uint256 usdcCurveId = ICurveLifecycleFacet(address(diamond))
            .postCurve(
                marketId,
                true,
                2e6,
                DEFAULT_FLAT_PRICE,
                DEFAULT_FLAT_PRICE,
                180,
                0,
                LibEveMarket.PositionTokenType.PARIMUTUEL
            );

        CurveCLOBTypes.FillBestResult memory eveUsdcResult = _buySingleCurveWithEveUSDC(marketId, eveUsdcCurveId);

        usdc.mint(taker, 1e6);
        vm.prank(taker);
        usdc.approve(address(diamond), type(uint256).max);

        CurveCLOBTypes.FillBestResult memory usdcResult = _buySingleCurveWithUSDC(marketId, usdcCurveId);

        assertEq(eveUsdcResult.sharesOut, 2e6);
        assertEq(usdcResult.sharesOut, 2e6);

        vm.expectRevert(_positionTokenTypeMismatch(marketId));
        vm.prank(taker);
        tradeRouter.splitWithUSDC(marketId, 1, alternateReceiver);
    }

    function test_CanFillDirectCTFBidCurveWithEveUSDC() public {
        vm.prank(owner);
        OwnershipFacet(address(diamond)).setOrderbookEntryFeeBps(100);

        (bytes32 marketId,) = _createTradingMarket("trade-router-direct-ctf-bid", 7 days);
        vm.prank(taker);
        ICurveInventoryFacet(address(diamond)).splitInventory(marketId, 4e6);
        _approvePositions(taker);

        uint72 bidPrice = 500_000_000;
        vm.startPrank(maker);
        eveUSDC.approve(address(diamond), type(uint256).max);
        uint256 curveId = ICurveLifecycleFacet(address(diamond))
            .postBidCurve(marketId, true, 3e6, bidPrice, bidPrice, 180, 0, LibEveMarket.PositionTokenType.CTF);
        vm.stopPrank();

        (,, uint256 yesPositionId,) = IMarketFactoryFacet(address(diamond)).getMarketPositions(marketId);
        uint256 receiverEveUsdcBefore = eveUSDC.balanceOf(alternateReceiver);

        ITradeRouter.SellBestParams memory params = _singleCurveSellParams(marketId, true, 2e6, curveId);

        _assertSellPreview(params, 2e6, 990_000, 10_000, 0);

        vm.prank(taker);
        ITradeRouter.SellBestResult memory result = tradeRouter.sellWithEveUSDC(params);

        assertEq(result.sharesSold, 2e6);
        assertEq(result.feePaid, 10_000);
        assertEq(result.collateralOut, 990_000);
        assertEq(eveUSDC.balanceOf(alternateReceiver), receiverEveUsdcBefore + result.collateralOut);
        assertEq(conditionalTokens.balanceOf(maker, yesPositionId), 2e6);
    }

    function test_PostBidCurveWithUSDCWrapsEscrowsAndRecordsMaker() public {
        vm.prank(owner);
        OwnershipFacet(address(diamond)).setOrderbookEntryFeeBps(0);

        (bytes32 marketId,) = _createTradingMarket("trade-router-usdc-bid-post", 7 days);
        vm.prank(taker);
        ICurveInventoryFacet(address(diamond)).splitInventory(marketId, 4e18);
        _approvePositions(taker);

        uint72 bidPrice = 500_000_000;
        usdc.mint(maker, 2e6);
        vm.startPrank(maker);
        usdc.approve(address(diamond), type(uint256).max);
        (uint256 curveId, uint128 usdcEscrowed) = ICurveLifecycleFacet(address(diamond))
            .postBidCurveWithUSDC(marketId, true, 4e18, bidPrice, bidPrice, 180, 0, LibEveMarket.PositionTokenType.CTF);
        vm.stopPrank();

        CurveCLOBTypes.CurveInfo memory curveInfo = ICurveViewFacet(address(diamond)).getCurveInfo(curveId);
        assertEq(usdcEscrowed, 2e6);
        assertEq(usdc.balanceOf(maker), 0);
        assertEq(usdc.balanceOf(address(diamond)), 0);
        assertEq(curveInfo.maker, maker);
        assertEq(uint8(curveInfo.curveSide), uint8(LibEveMarket.CurveSide.BID));
        assertEq(curveInfo.remainingVolume, 4e18);
        assertEq(curveInfo.quoteEscrowRemaining, 2e18);

        ITradeRouter.SellBestParams memory params = _singleCurveSellParams(marketId, true, 1e18, curveId);
        vm.prank(taker);
        ITradeRouter.SellBestResult memory result = tradeRouter.sellWithEveUSDC(params);
        (,, uint256 yesPositionId,) = IMarketFactoryFacet(address(diamond)).getMarketPositions(marketId);

        assertEq(result.sharesSold, 1e18);
        assertEq(conditionalTokens.balanceOf(maker, yesPositionId), 1e18);
        assertEq(eveUSDC.balanceOf(alternateReceiver), 500_000e12);
    }

    function test_CanFillDirectNonCTFBidCurveWithEveUSDC() public {
        (bytes32 marketId,) = _createTradingMarket("trade-router-direct-generic-bid", 7 days);
        vm.prank(taker);
        ICurveInventoryFacet(address(diamond)).splitInventory(marketId, 4e6);
        _approvePositions(taker);

        ResolutionHarnessFacet(address(diamond))
            .setMarketTypeAndPositionToken(
                marketId, uint8(LibEveMarket.MarketType.PARIMUTUEL), address(conditionalTokens)
            );

        uint72 bidPrice = 500_000_000;
        vm.startPrank(maker);
        eveUSDC.approve(address(diamond), type(uint256).max);
        uint256 curveId = ICurveLifecycleFacet(address(diamond))
            .postBidCurve(marketId, true, 3e6, bidPrice, bidPrice, 180, 0, LibEveMarket.PositionTokenType.PARIMUTUEL);
        vm.stopPrank();

        (,, uint256 yesPositionId,) = IMarketFactoryFacet(address(diamond)).getMarketPositions(marketId);
        ITradeRouter.SellBestParams memory params = _singleCurveSellParams(marketId, true, 2e6, curveId);

        vm.prank(taker);
        ITradeRouter.SellBestResult memory result = tradeRouter.sellWithEveUSDC(params);

        assertEq(result.sharesSold, 2e6);
        assertEq(result.collateralOut, 1_000_000);
        assertEq(conditionalTokens.balanceOf(maker, yesPositionId), 2e6);
    }

    function test_RevertWhen_TradeRouterResidualBalanceCheckFails() public {
        TradeRouterResidualHarness harness = new TradeRouterResidualHarness();
        usdc.mint(address(harness), 1);

        vm.expectRevert(abi.encodeWithSelector(ITradeRouter.ResidualRouterBalance.selector, address(usdc), 0, 1));
        harness.exposedAssertBalanceRestored(address(usdc), 0);
    }

    function _singleGeneration(uint32 generation) internal pure returns (uint32[] memory values) {
        values = new uint32[](1);
        values[0] = generation;
    }

    function _singleCommitment(bytes32 commitment) internal pure returns (bytes32[] memory values) {
        values = new bytes32[](1);
        values[0] = commitment;
    }

    function _singleCurve(uint256 curveId) internal pure returns (uint256[] memory values) {
        values = new uint256[](1);
        values[0] = curveId;
    }

    function _positionTokenTypeMismatch(bytes32 marketId) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(
            Errors.PositionTokenTypeMismatch.selector,
            marketId,
            uint8(LibEveMarket.PositionTokenType.CTF),
            uint8(LibEveMarket.PositionTokenType.PARIMUTUEL)
        );
    }

    function _buySingleCurveWithEveUSDC(bytes32 marketId, uint256 curveId)
        internal
        returns (CurveCLOBTypes.FillBestResult memory result)
    {
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        vm.prank(taker);
        result = tradeRouter.buyWithEveUSDC(_singleCurveBuyParams(marketId, curveId, generation, commitment, 1e6));
    }

    function _buySingleCurveWithUSDC(bytes32 marketId, uint256 curveId)
        internal
        returns (CurveCLOBTypes.FillBestResult memory result)
    {
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        vm.prank(taker);
        result = tradeRouter.buyWithUSDC(_singleCurveBuyParams(marketId, curveId, generation, commitment, 1e6));
    }

    function _singleCurveBuyParams(
        bytes32 marketId,
        uint256 curveId,
        uint32 generation,
        bytes32 commitment,
        uint128 maxCollateralIn
    ) internal view returns (CurveCLOBTypes.FillBestParams memory params) {
        params = CurveCLOBTypes.FillBestParams({
            marketId: marketId,
            isYesSide: true,
            maxCollateralIn: maxCollateralIn,
            minSharesOut: 0,
            maxAveragePrice: type(uint128).max,
            curveIds: _singleCurve(curveId),
            expectedGenerations: _singleGeneration(generation),
            expectedCommitments: _singleCommitment(commitment),
            payer: taker,
            receiver: alternateReceiver
        });
    }

    function _configureSmallFeeSplit() internal {
        vm.startPrank(owner);
        OwnershipFacet(address(diamond)).setOrderbookEntryFeeBps(100);
        OwnershipFacet(address(diamond)).setOrderbookFeeSplit(8_500, 400, 1_000, 100, 0, 0);
        vm.stopPrank();
    }

    function _retainedFeeBalance(uint128 fee) internal pure returns (uint128) {
        uint128 makerFee = uint128((uint256(fee) * 8_500) / 10_000);
        uint128 creatorFee = uint128((uint256(fee) * 400) / 10_000);
        return makerFee + creatorFee;
    }

    function _emptySellParams(bytes32 marketId) internal view returns (ITradeRouter.SellBestParams memory params) {
        params = ITradeRouter.SellBestParams({
            marketId: marketId,
            isYesSide: true,
            maxSharesIn: 1,
            minCollateralOut: 0,
            curveIds: new uint256[](0),
            expectedGenerations: new uint32[](0),
            expectedCommitments: new bytes32[](0),
            receiver: alternateReceiver
        });
    }

    function _singleCurveSellParams(bytes32 marketId, bool isYesSide, uint128 sharesIn, uint256 curveId)
        internal
        view
        returns (ITradeRouter.SellBestParams memory params)
    {
        uint256[] memory curveIds = new uint256[](1);
        curveIds[0] = curveId;
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        params = ITradeRouter.SellBestParams({
            marketId: marketId,
            isYesSide: isYesSide,
            maxSharesIn: sharesIn,
            minCollateralOut: 1,
            curveIds: curveIds,
            expectedGenerations: _singleGeneration(generation),
            expectedCommitments: _singleCommitment(commitment),
            receiver: alternateReceiver
        });
    }

    function _tradeRouterSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = ITradeRouter.buyWithEveUSDC.selector;
        selectors[1] = ITradeRouter.buyWithUSDC.selector;
        selectors[2] = ITradeRouter.splitWithUSDC.selector;
        selectors[3] = ITradeRouter.buyWithCollateral.selector;
    }

    function _tradeRouterSellSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = ITradeRouter.sellWithEveUSDC.selector;
        selectors[1] = ITradeRouter.sellWithUSDC.selector;
        selectors[2] = ITradeRouter.previewSellBest.selector;
        selectors[3] = ITradeRouter.sellWithCollateral.selector;
    }

    function _expectedSellAmounts(uint128 shares, uint128 oppositePrice)
        internal
        pure
        returns (uint128 collateralOut, uint128 fee, uint128 grossCost)
    {
        grossCost = uint128((uint256(shares) * oppositePrice) / 1_000_000_000);
        fee = uint128((uint256(grossCost) * DEFAULT_FILL_FEE_RATE) / 10_000);
        collateralOut = uint128(uint256(shares) - grossCost - fee);
    }

    function _assertSellPreview(
        ITradeRouter.SellBestParams memory params,
        uint128 expectedSharesSold,
        uint128 expectedCollateralOut,
        uint128 expectedFee,
        uint128 expectedUnfilledShares
    ) internal view {
        ITradeRouter.SellBestResult memory preview = tradeRouter.previewSellBest(params);
        assertEq(preview.sharesSold, expectedSharesSold);
        assertEq(preview.collateralOut, expectedCollateralOut);
        assertEq(preview.feePaid, expectedFee);
        assertEq(preview.unfilledShares, expectedUnfilledShares);
    }
}

contract TradeRouterResidualHarness is TradeRouterFacet {
    function exposedAssertBalanceRestored(address token, uint256 balanceBefore) external view {
        LibRouter.assertBalanceRestored(token, balanceBefore);
    }
}
