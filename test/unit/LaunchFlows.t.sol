// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {OwnershipFacet} from "../../src/facets/OwnershipFacet.sol";
import {FeeConfigFacet} from "../../src/facets/FeeConfigFacet.sol";
import {ParimutuelFacet} from "../../src/facets/ParimutuelFacet.sol";
import {ParimutuelViewFacet} from "../../src/facets/ParimutuelViewFacet.sol";
import {BookFacet} from "../../src/facets/BookFacet.sol";
import {BookOrderFacet} from "../../src/facets/BookOrderFacet.sol";
import {BookTradeFacet} from "../../src/facets/BookTradeFacet.sol";
import {BookSellFacet} from "../../src/facets/BookSellFacet.sol";
import {BookViewFacet} from "../../src/facets/BookViewFacet.sol";
import {CollateralTradeRouterFacet} from "../../src/facets/CollateralTradeRouterFacet.sol";
import {CollateralTradeRouterSellFacet} from "../../src/facets/CollateralTradeRouterSellFacet.sol";
import {CollateralTradeRouterPreviewFacet} from "../../src/facets/CollateralTradeRouterPreviewFacet.sol";
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
import {IMarketSettlementFacet} from "../../src/interfaces/IMarketSettlementFacet.sol";
import {IOBRResolutionFacet} from "../../src/interfaces/IOBRResolutionFacet.sol";
import {IParimutuelFacet} from "../../src/interfaces/IParimutuelFacet.sol";
import {ITradeRouter} from "../../src/interfaces/ITradeRouter.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {ParimutuelShareToken} from "../../src/tokens/ParimutuelShareToken.sol";

import {
    CollateralRouterFixture,
    ResolutionHarnessFacet,
    SettlementFeeFixture,
    StateProbeFacet
} from "../helpers/DiamondFixtures.sol";
import {MockUSDG} from "../helpers/MockUSDG.sol";
import {MarketFactoryTypes} from "../../src/types/MarketFactoryTypes.sol";

contract LaunchMarketFlowsTest is SettlementFeeFixture {
    uint72 internal constant TWO_USDC = 2_000_000_000_000_000_000;
    uint72 internal constant ONE_POINT_EIGHT_USDC = 1_800_000_000_000_000_000;

    ParimutuelShareToken internal shareToken;

    struct SpotLaunchCase {
        bytes32 bookId;
        address baseToken;
        uint72 askPrice;
        uint72 bidPrice;
        uint256 askCurveId;
        uint256 bidCurveId;
    }

    function setUp() public override {
        super.setUp();

        shareToken = new ParimutuelShareToken(address(diamond), "uri://launch-parimutuel/{id}");
        _addFacet(address(new ParimutuelFacet()), _parimutuelSelectors());
        _addFacet(address(new ParimutuelViewFacet()), _parimutuelViewSelectors());
        _addFacet(address(new BookFacet()), _bookSelectors());
        _addFacet(address(new BookOrderFacet()), _bookOrderSelectors());
        _addFacet(address(new BookTradeFacet()), _bookTradeSelectors());
        _addFacet(address(new BookSellFacet()), _bookSellSelectors());
        _addFacet(address(new BookViewFacet()), _bookViewSelectors());

        vm.startPrank(owner);
        OwnershipFacet(address(diamond)).setParimutuelConfig(address(shareToken), 0, 1);
        FeeConfigFacet(address(diamond)).setParimutuelFeeSplit(0, 10_000, 0, 0);
        OwnershipFacet(address(diamond)).setParimutuelEpochWindowCap(30 days);
        vm.stopPrank();
    }

    function test_CLOBCreateTradeResolveAndRedeemFlow() public {
        (bytes32 marketId,, uint64 expiryTime) = _createTradingMarket("launch clob redeem", "launch", 7 days);
        _splitFrom(maker, marketId, 1_000e6);
        _approvePositions(maker);

        uint256 curveId = _postCurveFromMaker(marketId, true, 700e6, 500_000_000, 500_000_000, 180, 0);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        vm.startPrank(taker);
        collateralToken.approve(address(diamond), 350e6);
        uint128 sharesOut = ICurveTradeFacet(address(diamond)).fillCurve(curveId, 350e6, 1, generation, commitment);
        vm.stopPrank();

        assertGt(sharesOut, 0);

        _finalizeCreatorResolution(marketId, expiryTime, uint8(LibEveMarket.MarketOutcome.Yes));

        (address redemptionCollateral, bytes32 conditionId, uint256[] memory indexSets) =
            IMarketSettlementFacet(address(diamond)).getCTFRedemptionParams(marketId);
        uint256 takerCollateralBefore = collateralToken.balanceOf(taker);

        vm.prank(taker);
        conditionalTokens.redeemPositions(IERC20(redemptionCollateral), bytes32(0), conditionId, indexSets);

        assertEq(redemptionCollateral, address(collateralToken));
        assertEq(collateralToken.balanceOf(taker), takerCollateralBefore + sharesOut);
    }

    function test_SpotBookPresetCreateTradeAndSellFlow() public {
        SpotLaunchCase memory spot = _createSpotLaunchCase();
        _assertSpotPreviewAndTopOfBook(spot);
        _executeSpotAskBuy(spot);
        _executeSpotBidSell(spot);
    }

    function test_ParimutuelSharesCanTradeThroughGenericCLOBFlow() public {
        (bytes32 marketId, uint256 yesPositionId,) = _createParimutuelMarket("launch parimutuel secondary", 7 days);
        bytes32 yesBookId = IBookAdminFacet(address(diamond)).getMarketSideBook(marketId, true);

        assertFalse(IBookAdminFacet(address(diamond)).isBookMaterialized(yesBookId));

        vm.startPrank(maker);
        collateralToken.approve(address(diamond), 1_000e6);
        uint128 sharesMinted = IParimutuelFacet(address(diamond)).buyShares(marketId, true, 1_000e6, maker, 0);
        shareToken.setApprovalForAll(address(diamond), true);
        vm.stopPrank();

        uint256 curveId = _postParimutuelCurve(marketId, true, sharesMinted, 500_000_000);
        assertTrue(IBookAdminFacet(address(diamond)).isBookMaterialized(yesBookId));

        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        (uint128 previewSharesOut,,,) = ICurveViewFacet(address(diamond)).previewCurveQuote(curveId, 250e6);

        vm.startPrank(taker);
        collateralToken.approve(address(diamond), 250e6);
        uint128 sharesOut = ICurveTradeFacet(address(diamond)).fillCurve(curveId, 250e6, 1, generation, commitment);
        vm.stopPrank();

        assertEq(sharesOut, previewSharesOut);
        assertEq(shareToken.balanceOf(taker, yesPositionId), sharesOut);
        assertEq(shareToken.balanceOf(address(diamond), yesPositionId), sharesMinted - sharesOut);
    }

    function test_ParimutuelBuyResolveClaimAndSweepFlow() public {
        (bytes32 marketId,,) = _createParimutuelMarket("launch parimutuel claim", 7 days);

        vm.startPrank(maker);
        collateralToken.approve(address(diamond), 1_000e6);
        uint128 yesShares = IParimutuelFacet(address(diamond)).buyShares(marketId, true, 1_000e6, maker, 0);
        vm.stopPrank();

        vm.startPrank(taker);
        collateralToken.approve(address(diamond), 1_000e6);
        uint128 noShares = IParimutuelFacet(address(diamond)).buyShares(marketId, false, 1_000e6, taker, 0);
        vm.stopPrank();

        // 0% fee, epoch 0 (2x): 1_000e6 collateral → 2_000e6 shares
        assertEq(yesShares, 2_000e6);
        assertEq(noShares, 2_000e6);

        _resolveMarket(marketId, uint8(LibEveMarket.MarketOutcome.Yes));

        uint256 makerCollateralBefore = collateralToken.balanceOf(maker);
        vm.prank(maker);
        uint128 payout = IParimutuelFacet(address(diamond)).claimPayout(marketId);

        // payoutPool = 2_000e6, maker has 2_000e6 of 2_000e6 winning shares → full pool
        assertEq(payout, 2_000e6);
        assertEq(collateralToken.balanceOf(maker), makerCollateralBefore + payout);

        vm.prank(creator);
        uint128 swept = IParimutuelFacet(address(diamond)).sweepParimutuelDust(marketId);
        IParimutuelFacet.PoolView memory pool = IParimutuelFacet(address(diamond)).getParimutuelPool(marketId);

        assertEq(swept, 0);
        assertTrue(pool.dustSwept);
        assertEq(pool.claimedPayout, pool.payoutPoolAtResolution);
        assertEq(pool.claimedClaimableShares, pool.totalClaimableSharesAtResolution);
    }

    function _createParimutuelMarket(string memory question, uint64 duration)
        internal
        returns (bytes32 marketId, uint256 yesPositionId, uint256 noPositionId)
    {
        uint64 expiryTime = uint64(block.timestamp) + duration;
        _approveCreatorWithEve(StateProbeFacet(address(diamond)).parimutuelCreationSeedAmount(), type(uint256).max);

        vm.prank(creator);
        marketId = IParimutuelFacet(address(diamond))
            .createParimutuelMarket(
                question, "launch", DEFAULT_RESOLUTION_SOURCE, uint64(block.timestamp), expiryTime, duration
            );

        (,,,, yesPositionId, noPositionId) = StateProbeFacet(address(diamond)).getStoredMarketCore(marketId);
    }

    function _createSpotLaunchCase() internal returns (SpotLaunchCase memory spot) {
        uint8 tickPresetId = 4;
        uint72 askTick = uint72(uint256(TWO_USDC) / 20);
        uint72 bidTick = uint72(uint256(ONE_POINT_EIGHT_USDC) / 20);
        MockUSDG baseToken = new MockUSDG();
        baseToken.mint(maker, 1_000e6);
        baseToken.mint(taker, 1_000e6);

        vm.prank(owner);
        FeeConfigFacet(address(diamond)).setOrderbookEntryFeeBps(0);

        vm.prank(maker);
        spot.bookId = IBookAdminFacet(address(diamond))
            .createBook(
                LibEveMarket.BookAssetType.ERC20,
                LibEveMarket.BaseTransferMode.EXACT,
                address(baseToken),
                0,
                address(collateralToken),
                tickPresetId,
                keccak256("launch-spot-book")
            );

        CurveCLOBTypes.BookInfo memory bookInfo = IBookAdminFacet(address(diamond)).getBookInfo(spot.bookId);
        assertEq(bookInfo.tickPresetId, tickPresetId);
        assertEq(bookInfo.tickSize, 20);

        vm.startPrank(maker);
        baseToken.approve(address(diamond), 100e6);
        collateralToken.approve(address(diamond), 90e6);
        spot.askCurveId = IBookOrderFacet(address(diamond))
            .postBookCurve(spot.bookId, LibEveMarket.CurveSide.ASK, 100e6, askTick, askTick, 180, 0, type(uint8).max);
        spot.bidCurveId = IBookOrderFacet(address(diamond))
            .postBookCurve(spot.bookId, LibEveMarket.CurveSide.BID, 50e6, bidTick, bidTick, 180, 0, type(uint8).max);
        vm.stopPrank();

        spot.baseToken = address(baseToken);
        spot.askPrice = TWO_USDC;
        spot.bidPrice = ONE_POINT_EIGHT_USDC;
    }

    function _assertSpotPreviewAndTopOfBook(SpotLaunchCase memory spot) internal view {
        (uint128 previewBaseOut, uint128 previewFee, uint128 previewAveragePrice, uint128 unfilledQuote) =
            IBookViewFacet(address(diamond)).previewBookExecution(spot.bookId, 200e6, _singleCurve(spot.askCurveId));
        (uint128 bestAskPrice, bool hasAsk, uint128 bestBidPrice, bool hasBid,,,) =
            IBookViewFacet(address(diamond)).getBookTopOfBookPage(spot.bookId, 0, 128);
        uint128 midpointPrice = (bestAskPrice + bestBidPrice) / 2;

        assertEq(previewBaseOut, 100e6);
        assertEq(previewFee, 0);
        assertEq(previewAveragePrice, spot.askPrice);
        assertEq(unfilledQuote, 0);
        assertTrue(hasAsk);
        assertTrue(hasBid);
        assertEq(bestAskPrice, spot.askPrice);
        assertEq(bestBidPrice, spot.bidPrice);
        assertEq(midpointPrice, 1_900_000_000_000_000_000);
    }

    function _executeSpotAskBuy(SpotLaunchCase memory spot) internal {
        MockUSDG baseToken = MockUSDG(spot.baseToken);
        uint256 takerQuoteBeforeBuy = collateralToken.balanceOf(taker);
        uint256 takerBaseBeforeBuy = baseToken.balanceOf(taker);
        (uint32 askGeneration, bytes32 askCommitment) =
            ICurveViewFacet(address(diamond)).getCurveCommitment(spot.askCurveId);

        vm.startPrank(taker);
        collateralToken.approve(address(diamond), 200e6);
        CurveCLOBTypes.FillBestResult memory buyResult = IBookTradeFacet(address(diamond))
            .fillBookBest(
                CurveCLOBTypes.FillBookParams({
                    bookId: spot.bookId,
                    maxQuoteIn: 200e6,
                    minBaseOut: 100e6,
                    maxAveragePrice: spot.askPrice,
                    curveIds: _singleCurve(spot.askCurveId),
                    expectedGenerations: _singleGeneration(askGeneration),
                    expectedCommitments: _singleCommitment(askCommitment),
                    payer: taker,
                    receiver: taker
                })
            );
        vm.stopPrank();

        assertEq(buyResult.sharesOut, 100e6);
        assertEq(buyResult.collateralUsed, 200e6);
        assertEq(buyResult.feePaid, 0);
        assertEq(buyResult.averagePrice, spot.askPrice);
        assertEq(collateralToken.balanceOf(taker), takerQuoteBeforeBuy - 200e6);
        assertEq(baseToken.balanceOf(taker), takerBaseBeforeBuy + 100e6);

        CurveCLOBTypes.CurveInfo memory askInfo = ICurveViewFacet(address(diamond)).getCurveInfo(spot.askCurveId);
        assertEq(askInfo.currentPrice, spot.askPrice);
        assertEq(askInfo.remainingVolume, 0);
        assertEq(askInfo.quoteEscrowRemaining, 0);
    }

    function _executeSpotBidSell(SpotLaunchCase memory spot) internal {
        MockUSDG baseToken = MockUSDG(spot.baseToken);
        uint256 takerQuoteBeforeSell = collateralToken.balanceOf(taker);
        uint256 takerBaseBeforeSell = baseToken.balanceOf(taker);
        (uint32 bidGeneration, bytes32 bidCommitment) =
            ICurveViewFacet(address(diamond)).getCurveCommitment(spot.bidCurveId);

        vm.startPrank(taker);
        baseToken.approve(address(diamond), 20e6);
        CurveCLOBTypes.SellBookResult memory sellResult = IBookTradeFacet(address(diamond))
            .sellBookBest(
                CurveCLOBTypes.SellBookParams({
                    bookId: spot.bookId,
                    maxBaseIn: 20e6,
                    minQuoteOut: 36e6,
                    curveIds: _singleCurve(spot.bidCurveId),
                    expectedGenerations: _singleGeneration(bidGeneration),
                    expectedCommitments: _singleCommitment(bidCommitment),
                    receiver: taker
                })
            );
        vm.stopPrank();

        assertEq(sellResult.baseSold, 20e6);
        assertEq(sellResult.quoteOut, 36e6);
        assertEq(sellResult.feePaid, 0);
        assertEq(sellResult.averagePrice, spot.bidPrice);
        assertEq(collateralToken.balanceOf(taker), takerQuoteBeforeSell + 36e6);
        assertEq(baseToken.balanceOf(taker), takerBaseBeforeSell - 20e6);

        CurveCLOBTypes.CurveInfo memory bidInfo = ICurveViewFacet(address(diamond)).getCurveInfo(spot.bidCurveId);
        assertEq(bidInfo.currentPrice, spot.bidPrice);
        assertEq(bidInfo.remainingVolume, 30e6);
        assertEq(bidInfo.quoteEscrowRemaining, 54e6);
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

    function _bookSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](6);
        selectors[0] = IBookAdminFacet.createBook.selector;
        selectors[1] = IBookAdminFacet.getBookInfo.selector;
        selectors[2] = IBookAdminFacet.isBookMaterialized.selector;
        selectors[3] = IBookAdminFacet.getMarketSideBook.selector;
        selectors[4] = IBookAdminFacet.requestBookDecommission.selector;
        selectors[5] = IBookAdminFacet.finalizeBookDecommission.selector;
    }

    function _bookOrderSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = IBookOrderFacet.postBookCurve.selector;
    }

    function _bookTradeSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = IBookTradeFacet.fillBookBest.selector;
        selectors[1] = IBookTradeFacet.fillBookBestFor.selector;
    }

    function _bookSellSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = IBookTradeFacet.sellBookBest.selector;
    }

    function _bookViewSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = IBookViewFacet.previewBookExecution.selector;
        selectors[1] = IBookViewFacet.getBookCurveIdsPage.selector;
        selectors[2] = IBookViewFacet.getActiveBookCurveIdsPage.selector;
        selectors[3] = IBookViewFacet.getBookTopOfBookPage.selector;
    }

    function _postParimutuelCurve(bytes32 marketId, bool isYesSide, uint128 volume, uint72 price)
        internal
        returns (uint256 curveId)
    {
        vm.prank(maker);
        curveId = ICurveLifecycleFacet(address(diamond))
            .postCurve(marketId, isYesSide, volume, price, price, 180, 0, LibEveMarket.PositionTokenType.PARIMUTUEL);
    }

    function _resolveMarket(bytes32 marketId, uint8 outcome) internal {
        MarketFactoryTypes.MarketInfo memory market = IMarketFactoryFacet(address(diamond)).getMarketInfo(marketId);
        vm.warp(market.expiryTime);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(marketId, outcome);

        (,,,,,, uint64 disputeDeadline,) = StateProbeFacet(address(diamond)).getStoredResolution(marketId);
        vm.warp(disputeDeadline);
        IOBRResolutionFacet(address(diamond)).finalizeResolution(marketId);
    }
}

contract LaunchRouterFlowsTest is CollateralRouterFixture {
    ITradeRouter internal tradeRouter;
    ParimutuelShareToken internal shareToken;
    address internal receiver;

    function setUp() public override {
        super.setUp();

        tradeRouter = ITradeRouter(address(diamond));
        shareToken = new ParimutuelShareToken(address(diamond), "uri://launch-router/{id}");
        receiver = makeAddr("launch-router-receiver");

        _addFacet(address(new CollateralTradeRouterFacet()), _tradeRouterSelectors());
        _addFacet(address(new CollateralTradeRouterSellFacet()), _tradeRouterSellSelectors());
        _addFacet(address(new CollateralTradeRouterPreviewFacet()), _tradeRouterPreviewSelectors());
        _addFacet(address(new ResolutionHarnessFacet()), _resolutionHarnessSelectors());
        _addFacet(address(new ParimutuelFacet()), _parimutuelSelectors());
        _addFacet(address(new ParimutuelViewFacet()), _parimutuelViewSelectors());

        vm.startPrank(owner);
        OwnershipFacet(address(diamond)).setParimutuelConfig(address(shareToken), 0, 1);
        FeeConfigFacet(address(diamond)).setParimutuelFeeSplit(0, 10_000, 0, 0);
        OwnershipFacet(address(diamond)).setParimutuelEpochWindowCap(30 days);
        vm.stopPrank();
    }

    function test_RouterCLOBHappyPathsUseUserFacingEntrypoints() public {
        (bytes32 marketId,) = _createTradingMarket("launch router clob", 7 days);
        _splitFromMaker(marketId, 10e18);
        _approvePositions(maker);

        uint256 curveId = _postCurveFromMaker(marketId, true, 6e18, DEFAULT_FLAT_PRICE, DEFAULT_FLAT_PRICE, 180);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        CurveCLOBTypes.FillBestParams memory buyParams = CurveCLOBTypes.FillBestParams({
            marketId: marketId,
            isYesSide: true,
            maxCollateralIn: 3e18,
            minSharesOut: 1,
            maxAveragePrice: type(uint128).max,
            curveIds: _singleCurve(curveId),
            expectedGenerations: _singleGeneration(generation),
            expectedCommitments: _singleCommitment(commitment),
            payer: taker,
            receiver: receiver
        });

        vm.prank(taker);
        CurveCLOBTypes.FillBestResult memory buyResult = tradeRouter.buyWithCollateral(buyParams);

        (,, uint256 yesPositionId,) = IMarketFactoryFacet(address(diamond)).getMarketPositions(marketId);
        assertGt(buyResult.sharesOut, 0);
        assertEq(conditionalTokens.balanceOf(receiver, yesPositionId), buyResult.sharesOut);
    }

    function test_RouterSupportsDirectBidsOnNativeParimutuelMarketAndRejectsCTFInventory() public {
        bytes32 marketId = _createParimutuelMarket("launch router parimutuel");

        vm.expectRevert(_positionTokenTypeMismatch(marketId));
        vm.prank(taker);
        ICurveInventoryFacet(address(diamond)).splitInventory(marketId, 1);

        (,,,, uint256 yesPositionId,) = StateProbeFacet(address(diamond)).getStoredMarketCore(marketId);

        vm.startPrank(taker);
        IParimutuelFacet(address(diamond)).buyShares(marketId, true, 1e6, taker, 0);
        shareToken.setApprovalForAll(address(diamond), true);
        vm.stopPrank();

        vm.startPrank(maker);
        routerCollateral.approve(address(diamond), type(uint256).max);
        uint256 curveId = ICurveLifecycleFacet(address(diamond))
            .postBidCurve(
                marketId,
                true,
                1e6,
                DEFAULT_FLAT_PRICE,
                DEFAULT_FLAT_PRICE,
                180,
                0,
                LibEveMarket.PositionTokenType.PARIMUTUEL
            );
        vm.stopPrank();

        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        ITradeRouter.SellBestParams memory sellParams = ITradeRouter.SellBestParams({
            marketId: marketId,
            isYesSide: true,
            maxSharesIn: 500_000,
            minCollateralOut: 0,
            curveIds: _singleCurve(curveId),
            expectedGenerations: _singleGeneration(generation),
            expectedCommitments: _singleCommitment(commitment),
            receiver: receiver
        });

        vm.prank(taker);
        ITradeRouter.SellBestResult memory result = tradeRouter.sellWithCollateral(sellParams);

        assertEq(result.sharesSold, 500_000);
        assertEq(result.collateralOut, 250_000);
        assertEq(shareToken.balanceOf(maker, yesPositionId), 500_000);
        assertEq(shareToken.balanceOf(receiver, yesPositionId), 0);
    }

    function _createParimutuelMarket(string memory question) internal returns (bytes32 marketId) {
        uint64 expiryTime = uint64(block.timestamp) + 7 days;

        vm.prank(creator);
        marketId = IParimutuelFacet(address(diamond))
            .createParimutuelMarket(
                question, "launch-router", DEFAULT_RESOLUTION_SOURCE, uint64(block.timestamp), expiryTime, 7 days
            );
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

    function _tradeRouterSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = ITradeRouter.buyWithCollateral.selector;
    }

    function _tradeRouterSellSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = ITradeRouter.sellWithCollateral.selector;
    }

    function _tradeRouterPreviewSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = ITradeRouter.previewSellBest.selector;
        selectors[1] = ITradeRouter.executeExactRouterTransfer.selector;
    }
}
