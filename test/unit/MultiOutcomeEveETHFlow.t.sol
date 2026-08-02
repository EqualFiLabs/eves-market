// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IMultiOutcomeOrderbookFacet} from "../../src/interfaces/IMultiOutcomeOrderbookFacet.sol";
import {IBookAdminFacet} from "../../src/interfaces/IBookAdminFacet.sol";
import {IBookOrderFacet} from "../../src/interfaces/IBookOrderFacet.sol";
import {IBookTradeFacet} from "../../src/interfaces/IBookTradeFacet.sol";
import {IBookViewFacet} from "../../src/interfaces/IBookViewFacet.sol";
import {ICurveInventoryFacet} from "../../src/interfaces/ICurveInventoryFacet.sol";
import {ICurveLifecycleFacet} from "../../src/interfaces/ICurveLifecycleFacet.sol";
import {ICurveTradeFacet} from "../../src/interfaces/ICurveTradeFacet.sol";
import {ICurveViewFacet} from "../../src/interfaces/ICurveViewFacet.sol";
import {CurveCLOBTypes} from "../../src/types/CurveCLOBTypes.sol";
import {OwnershipFacet} from "../../src/facets/OwnershipFacet.sol";
import {MultiOutcomeOrderbookFacet} from "../../src/facets/MultiOutcomeOrderbookFacet.sol";
import {MultiOutcomeOrderbookViewFacet} from "../../src/facets/MultiOutcomeOrderbookViewFacet.sol";
import {BookFacet} from "../../src/facets/BookFacet.sol";
import {BookOrderFacet} from "../../src/facets/BookOrderFacet.sol";
import {BookTradeFacet} from "../../src/facets/BookTradeFacet.sol";
import {BookViewFacet} from "../../src/facets/BookViewFacet.sol";
import {DelayedOrderFacet} from "../../src/facets/DelayedOrderFacet.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {LibMultiOutcome} from "../../src/libraries/LibMultiOutcome.sol";
import {DelayedOrderTypes} from "../../src/types/DelayedOrderTypes.sol";
import {EvesPositionManager} from "../../src/tokens/EvesPositionManager.sol";
import {EveETH} from "../../src/tokens/EveETH.sol";

import {CanonicalWETH9} from "../../src/mocks/CanonicalWETH9.sol";
import {SettlementFeeFixture} from "../helpers/DiamondFixtures.sol";
import {MarketFactoryTypes} from "../../src/types/MarketFactoryTypes.sol";

contract MultiOutcomeEveETHFlowTest is SettlementFeeFixture {
    uint8 internal constant EVE_ETH_PROFILE_ID = 1;
    uint128 internal constant EVE_ETH_PAYOUT_UNIT = 0.0005 ether;
    uint72 internal constant HALF_PRICE = 500_000_000;

    CanonicalWETH9 internal weth;
    EveETH internal eveETH;
    EvesPositionManager internal outcomePositions;

    function setUp() public override {
        super.setUp();

        weth = new CanonicalWETH9();
        eveETH = new EveETH(address(weth));
        outcomePositions = new EvesPositionManager(address(diamond), "");

        _addFacet(address(ownershipFacet), _evesPositionManagerSelector());
        _addFacet(address(new MultiOutcomeOrderbookFacet()), _multiOutcomeSelectors());
        _addFacet(address(new MultiOutcomeOrderbookViewFacet()), _multiOutcomeViewSelectors());
        _addFacet(address(new BookFacet()), _bookSelectors());
        _addFacet(address(new BookOrderFacet()), _bookOrderSelectors());
        _addFacet(address(new BookTradeFacet()), _bookTradeSelectors());
        _addFacet(address(new BookViewFacet()), _bookViewSelectors());
        _addFacet(address(new DelayedOrderFacet()), _delayedOrderSelectors());

        vm.startPrank(owner);
        OwnershipFacet(address(diamond)).setEvesPositionManager(address(outcomePositions));
        OwnershipFacet(address(diamond))
            .setCollateralProfile(EVE_ETH_PROFILE_ID, address(eveETH), address(weth), EVE_ETH_PAYOUT_UNIT, 0, true);
        OwnershipFacet(address(diamond)).setOrderbookEntryFeeBps(100);
        OwnershipFacet(address(diamond)).setOrderbookFeeSplit(4_000, 0, 3_000, 3_000);
        OwnershipFacet(address(diamond)).setDelayedOrderConfig(2, 10, 180);
        OwnershipFacet(address(diamond)).setDelayedOrderProcessing(uint8(LibEveMarket.ProcessingMode.Permissionless), 0);
        vm.stopPrank();
    }

    function test_EveETHOutcomeBookSupportsAskFillAndWinnerRedemption() public {
        (bytes32 marketId, uint64 expiryTime) = _createEveETHMultiOutcomeMarket("Will eveETH outcome A win?");
        uint128 makerInventory = 0.004 ether;
        uint128 takerCollateral = 0.001 ether;
        uint8 winningOutcome = 1;
        bytes32 bookId = _outcomeBook(marketId, winningOutcome);

        _fundEveETH(maker, makerInventory);
        _fundEveETH(taker, takerCollateral);

        _splitOutcomeSet(maker, marketId, makerInventory);
        _approveOutcomePositions(maker);
        uint256 curveId = _postOutcomeBookAsk(bookId, makerInventory);
        uint128 sharesOut = _fillEveETHOutcomeAsk(marketId, bookId, curveId, winningOutcome, takerCollateral);

        _finalizeCreatorResolution(marketId, expiryTime, winningOutcome);
        _redeemWinningOutcome(marketId, winningOutcome, sharesOut);
    }

    function test_EveETHOutcomeBookSupportsBidFillAndCancelRefunds() public {
        (bytes32 marketId,) = _createEveETHMultiOutcomeMarket("Will eveETH bids settle?");
        uint8 outcome = 2;
        bytes32 bookId = _outcomeBook(marketId, outcome);
        uint256 positionId = IMultiOutcomeOrderbookFacet(address(diamond)).getOutcomePositionId(marketId, outcome);
        uint128 bidVolume = 0.002 ether;
        uint128 sellerInventory = 0.001 ether;

        _fundEveETH(maker, bidVolume);
        _fundEveETH(taker, sellerInventory);
        _splitOutcomeSet(taker, marketId, sellerInventory);
        _approveOutcomePositions(taker);

        vm.prank(maker);
        uint256 bidCurveId = IBookOrderFacet(address(diamond))
            .postBookCurve(bookId, LibEveMarket.CurveSide.BID, bidVolume, HALF_PRICE, HALF_PRICE, 180, 0, 0);
        (uint32 bidGeneration, bytes32 bidCommitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(bidCurveId);

        uint256 sellerBalanceBefore = eveETH.balanceOf(taker);
        vm.prank(taker);
        CurveCLOBTypes.SellBookResult memory sellResult = IBookTradeFacet(address(diamond))
            .sellBookBest(
                CurveCLOBTypes.SellBookParams({
                    bookId: bookId,
                    maxBaseIn: sellerInventory,
                    minQuoteOut: 0,
                    curveIds: _singleCurveId(bidCurveId),
                    expectedGenerations: _singleGeneration(bidGeneration),
                    expectedCommitments: _singleCommitment(bidCommitment),
                    receiver: taker
                })
            );

        assertEq(sellResult.baseSold, sellerInventory);
        assertEq(eveETH.balanceOf(taker), sellerBalanceBefore + sellResult.quoteOut);
        assertEq(outcomePositions.balanceOf(taker, positionId), 0);

        CurveCLOBTypes.CurveInfo memory partiallyFilled = ICurveViewFacet(address(diamond)).getCurveInfo(bidCurveId);
        uint256 makerBalanceBeforeCancel = eveETH.balanceOf(maker);
        vm.prank(maker);
        ICurveLifecycleFacet(address(diamond)).cancelCurve(bidCurveId);
        assertEq(eveETH.balanceOf(maker), makerBalanceBeforeCancel + partiallyFilled.quoteEscrowRemaining);

        _splitOutcomeSet(maker, marketId, sellerInventory);
        _approveOutcomePositions(maker);
        uint256 askCurveId = _postOutcomeBookAsk(bookId, sellerInventory);
        uint256 makerOutcomeBalanceBeforeCancel = outcomePositions.balanceOf(maker, positionId);
        vm.prank(maker);
        ICurveLifecycleFacet(address(diamond)).cancelCurve(askCurveId);
        assertEq(outcomePositions.balanceOf(maker, positionId), makerOutcomeBalanceBeforeCancel + sellerInventory);
    }

    function test_EveETHOutcomeBookSupportsDelayedMarketBuy() public {
        (bytes32 marketId,) = _createEveETHMultiOutcomeMarket("Will eveETH delayed outcome buy?");
        uint8 outcome = 1;
        bytes32 bookId = _outcomeBook(marketId, outcome);
        uint256 positionId = IMultiOutcomeOrderbookFacet(address(diamond)).getOutcomePositionId(marketId, outcome);
        uint128 makerInventory = 0.004 ether;
        uint128 takerCollateral = 0.001 ether;

        _fundEveETH(maker, makerInventory);
        _fundEveETH(taker, takerCollateral);
        _splitOutcomeSet(maker, marketId, makerInventory);
        _approveOutcomePositions(maker);
        uint256 curveId = _postOutcomeBookAsk(bookId, makerInventory);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        vm.prank(owner);
        OwnershipFacet(address(diamond)).setBookDelayedExecution(bookId, true);

        vm.prank(taker);
        uint256 orderId = DelayedOrderFacet(address(diamond))
            .submitDelayedOrder(
                DelayedOrderTypes.SubmitDelayedOrderParams({
                    bookId: bookId,
                    kind: LibEveMarket.DelayedOrderKind.MarketBuy,
                    amountIn: takerCollateral,
                    limitPrice: 0,
                    minOut: 0,
                    maxAveragePrice: type(uint128).max,
                    curveIds: _singleCurveId(curveId),
                    expectedGenerations: _singleGeneration(generation),
                    expectedCommitments: _singleCommitment(commitment)
                })
            );

        vm.roll(block.number + 2);
        DelayedOrderTypes.DelayedOrderRoute[] memory routes = new DelayedOrderTypes.DelayedOrderRoute[](1);
        routes[0] = DelayedOrderTypes.DelayedOrderRoute({
            curveIds: _singleCurveId(curveId),
            expectedGenerations: _singleGeneration(generation),
            expectedCommitments: _singleCommitment(commitment)
        });
        DelayedOrderFacet(address(diamond)).processDelayedOrders(bookId, 1, routes);

        DelayedOrderTypes.DelayedOrderView memory order = DelayedOrderFacet(address(diamond)).getDelayedOrder(orderId);
        assertTrue(
            order.status == LibEveMarket.DelayedOrderStatus.Filled
                || order.status == LibEveMarket.DelayedOrderStatus.PartiallyFilled
        );
        assertGt(outcomePositions.balanceOf(taker, positionId), 0);
    }

    function test_EveETHInvalidResolutionPaysProRataRefund() public {
        (bytes32 marketId, uint64 expiryTime) = _createEveETHMultiOutcomeMarket("Will eveETH invalid refund?");
        uint128 amount = 0.004 ether;
        uint8 outcome = 0;
        uint256 positionId = IMultiOutcomeOrderbookFacet(address(diamond)).getOutcomePositionId(marketId, outcome);

        _fundEveETH(taker, amount);
        _splitOutcomeSet(taker, marketId, amount);

        _finalizeCreatorResolution(marketId, expiryTime, LibMultiOutcome.OUTCOME_INVALID);
        uint256 balanceBefore = eveETH.balanceOf(taker);

        vm.prank(taker);
        uint128 collateralOut =
            IMultiOutcomeOrderbookFacet(address(diamond)).redeemOutcome(marketId, outcome, amount, taker);

        assertEq(collateralOut, amount / 4);
        assertEq(eveETH.balanceOf(taker), balanceBefore + collateralOut);
        assertEq(outcomePositions.balanceOf(taker, positionId), 0);
    }

    function test_DefaultEveUSDCOutcomeBookTradingStillUsesDefaultCollateral() public {
        bytes32 marketId = _createDefaultMultiOutcomeMarket("Will default outcome books keep using eveUSDC?");
        uint8 outcome = 0;
        bytes32 bookId = _outcomeBook(marketId, outcome);
        uint256 positionId = IMultiOutcomeOrderbookFacet(address(diamond)).getOutcomePositionId(marketId, outcome);
        uint128 makerInventory = 4_000e6;
        uint128 takerCollateral = 1_000e6;

        collateralToken.mint(maker, makerInventory);
        collateralToken.mint(taker, takerCollateral);

        vm.prank(maker);
        collateralToken.approve(address(diamond), makerInventory);
        vm.prank(maker);
        IMultiOutcomeOrderbookFacet(address(diamond)).splitOutcomeSet(marketId, makerInventory, maker);
        _approveOutcomePositions(maker);
        uint256 curveId = _postOutcomeBookAsk(bookId, makerInventory);

        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        (uint128 previewShares,,,) = ICurveViewFacet(address(diamond)).previewCurveQuote(curveId, takerCollateral);
        uint256 takerBalanceBefore = collateralToken.balanceOf(taker);

        vm.startPrank(taker);
        collateralToken.approve(address(diamond), takerCollateral);
        CurveCLOBTypes.FillBestResult memory result = IBookTradeFacet(address(diamond))
            .fillBookBest(
                CurveCLOBTypes.FillBookParams({
                    bookId: bookId,
                    maxQuoteIn: takerCollateral,
                    minBaseOut: previewShares,
                    maxAveragePrice: type(uint128).max,
                    curveIds: _singleCurveId(curveId),
                    expectedGenerations: _singleGeneration(generation),
                    expectedCommitments: _singleCommitment(commitment),
                    payer: taker,
                    receiver: taker
                })
            );
        vm.stopPrank();

        assertEq(result.sharesOut, previewShares);
        assertEq(outcomePositions.balanceOf(taker, positionId), previewShares);
        assertEq(collateralToken.balanceOf(taker), takerBalanceBefore - result.collateralUsed);
    }

    function _createEveETHMultiOutcomeMarket(string memory question)
        internal
        returns (bytes32 marketId, uint64 expiryTime)
    {
        expiryTime = uint64(block.timestamp + 7 days);

        vm.prank(creator);
        eveToken.approve(address(diamond), type(uint256).max);

        vm.prank(creator);
        marketId = IMultiOutcomeOrderbookFacet(address(diamond))
            .createMultiOutcomeMarketWithCollateralProfile(
                EVE_ETH_PROFILE_ID,
                IMultiOutcomeOrderbookFacet.CreateMultiOutcomeMarketParams({
                    question: question,
                    category: "crypto",
                    resolutionSource: DEFAULT_RESOLUTION_SOURCE,
                    tradingStartTime: uint64(block.timestamp),
                    expiryTime: expiryTime,
                    outcomes: _outcomes(),
                    display: _emptyMultiOutcomeDisplay(),
                    externalRef: _emptyMultiOutcomeExternalRef(),
                    outcomeDisplay: new IMultiOutcomeOrderbookFacet.OutcomeDisplayInput[](0)
                })
            );
    }

    function _createDefaultMultiOutcomeMarket(string memory question) internal returns (bytes32 marketId) {
        vm.prank(creator);
        collateralToken.approve(address(diamond), type(uint256).max);

        vm.prank(creator);
        eveToken.approve(address(diamond), type(uint256).max);

        vm.prank(creator);
        marketId = IMultiOutcomeOrderbookFacet(address(diamond))
            .createMultiOutcomeMarket(
                IMultiOutcomeOrderbookFacet.CreateMultiOutcomeMarketParams({
                    question: question,
                    category: "crypto",
                    resolutionSource: DEFAULT_RESOLUTION_SOURCE,
                    tradingStartTime: uint64(block.timestamp),
                    expiryTime: uint64(block.timestamp + 7 days),
                    outcomes: _outcomes(),
                    display: _emptyMultiOutcomeDisplay(),
                    externalRef: _emptyMultiOutcomeExternalRef(),
                    outcomeDisplay: new IMultiOutcomeOrderbookFacet.OutcomeDisplayInput[](0)
                })
            );
    }

    function _emptyMultiOutcomeDisplay() internal pure returns (MarketFactoryTypes.MarketDisplayInput memory display) {}

    function _emptyMultiOutcomeExternalRef()
        internal
        pure
        returns (MarketFactoryTypes.ExternalMarketRefInput memory externalRef)
    {}

    function _outcomeBook(bytes32 marketId, uint8 outcome) internal view returns (bytes32 bookId) {
        bytes32[] memory bookIds = IMultiOutcomeOrderbookFacet(address(diamond)).getMultiOutcomeBooks(marketId);
        bookId = bookIds[outcome];
        CurveCLOBTypes.BookInfo memory bookInfo = IBookAdminFacet(address(diamond)).getBookInfo(bookId);
        assertEq(bookInfo.marketId, marketId);
    }

    function _postOutcomeBookAsk(bytes32 bookId, uint128 volume) internal returns (uint256 curveId) {
        vm.prank(maker);
        curveId = IBookOrderFacet(address(diamond))
            .postBookCurve(bookId, LibEveMarket.CurveSide.ASK, volume, HALF_PRICE, HALF_PRICE, 180, 0, 0);
    }

    function _fillEveETHOutcomeAsk(
        bytes32 marketId,
        bytes32 bookId,
        uint256 curveId,
        uint8 outcome,
        uint128 takerCollateral
    ) internal returns (uint128 sharesOut) {
        uint256 positionId = IMultiOutcomeOrderbookFacet(address(diamond)).getOutcomePositionId(marketId, outcome);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        (uint128 previewShares, uint128 previewFee,,) =
            ICurveViewFacet(address(diamond)).previewCurveQuote(curveId, takerCollateral);
        uint256 takerBalanceBefore = eveETH.balanceOf(taker);

        vm.prank(taker);
        CurveCLOBTypes.FillBestResult memory result = IBookTradeFacet(address(diamond))
            .fillBookBest(
                CurveCLOBTypes.FillBookParams({
                    bookId: bookId,
                    maxQuoteIn: takerCollateral,
                    minBaseOut: previewShares,
                    maxAveragePrice: type(uint128).max,
                    curveIds: _singleCurveId(curveId),
                    expectedGenerations: _singleGeneration(generation),
                    expectedCommitments: _singleCommitment(commitment),
                    payer: taker,
                    receiver: taker
                })
            );

        assertEq(result.sharesOut, previewShares);
        assertEq(outcomePositions.balanceOf(taker, positionId), previewShares);
        assertEq(eveETH.balanceOf(taker), takerBalanceBefore - result.collateralUsed);
        uint256 makerFeeShare = (uint256(previewFee) * 4_000) / 10_000;
        assertEq(eveETH.balanceOf(treasury), previewFee - makerFeeShare);
        sharesOut = result.sharesOut;
    }

    function _redeemWinningOutcome(bytes32 marketId, uint8 outcome, uint128 amount) internal {
        uint256 positionId = IMultiOutcomeOrderbookFacet(address(diamond)).getOutcomePositionId(marketId, outcome);
        uint256 redeemBalanceBefore = eveETH.balanceOf(taker);

        vm.prank(taker);
        uint128 collateralOut =
            IMultiOutcomeOrderbookFacet(address(diamond)).redeemOutcome(marketId, outcome, amount, taker);

        assertEq(collateralOut, amount);
        assertEq(eveETH.balanceOf(taker), redeemBalanceBefore + amount);
        assertEq(outcomePositions.balanceOf(taker, positionId), 0);
    }

    function _splitOutcomeSet(address account, bytes32 marketId, uint128 amount) internal {
        vm.startPrank(account);
        eveETH.approve(address(diamond), amount);
        IMultiOutcomeOrderbookFacet(address(diamond)).splitOutcomeSet(marketId, amount, account);
        vm.stopPrank();
    }

    function _approveOutcomePositions(address account) internal {
        vm.prank(account);
        outcomePositions.setApprovalForAll(address(diamond), true);
    }

    function _fundEveETH(address account, uint256 amount) internal {
        vm.deal(account, amount);
        vm.startPrank(account);
        weth.deposit{value: amount}();
        weth.approve(address(eveETH), amount);
        eveETH.wrap(amount, account);
        eveETH.approve(address(diamond), type(uint256).max);
        vm.stopPrank();
    }

    function _outcomes() internal pure returns (string[] memory outcomes) {
        outcomes = new string[](4);
        outcomes[0] = "A";
        outcomes[1] = "B";
        outcomes[2] = "C";
        outcomes[3] = "D";
    }

    function _singleCurveId(uint256 curveId) internal pure returns (uint256[] memory values) {
        values = new uint256[](1);
        values[0] = curveId;
    }

    function _singleGeneration(uint32 generation) internal pure returns (uint32[] memory values) {
        values = new uint32[](1);
        values[0] = generation;
    }

    function _singleCommitment(bytes32 commitment) internal pure returns (bytes32[] memory values) {
        values = new bytes32[](1);
        values[0] = commitment;
    }

    function _evesPositionManagerSelector() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = OwnershipFacet.setEvesPositionManager.selector;
    }

    function _multiOutcomeSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](5);
        selectors[0] = IMultiOutcomeOrderbookFacet.createMultiOutcomeMarket.selector;
        selectors[1] = IMultiOutcomeOrderbookFacet.createMultiOutcomeMarketWithCollateralProfile.selector;
        selectors[2] = IMultiOutcomeOrderbookFacet.splitOutcomeSet.selector;
        selectors[3] = IMultiOutcomeOrderbookFacet.mergeOutcomeSet.selector;
        selectors[4] = IMultiOutcomeOrderbookFacet.redeemOutcome.selector;
    }

    function _multiOutcomeViewSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](6);
        selectors[0] = IMultiOutcomeOrderbookFacet.getMultiOutcomeMarket.selector;
        selectors[1] = IMultiOutcomeOrderbookFacet.getMultiOutcomeOutcomes.selector;
        selectors[2] = IMultiOutcomeOrderbookFacet.getOutcomePositionId.selector;
        selectors[3] = IMultiOutcomeOrderbookFacet.getMultiOutcomeBooks.selector;
        selectors[4] = IMultiOutcomeOrderbookFacet.getMultiOutcomeTopOfBook.selector;
        selectors[5] = IMultiOutcomeOrderbookFacet.getMultiOutcomeDisplay.selector;
    }

    function _bookSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](7);
        selectors[0] = IBookAdminFacet.createBook.selector;
        selectors[1] = IBookAdminFacet.computeBookId.selector;
        selectors[2] = IBookAdminFacet.getBookInfo.selector;
        selectors[3] = IBookAdminFacet.isBookMaterialized.selector;
        selectors[4] = IBookAdminFacet.getMarketSideBook.selector;
        selectors[5] = IBookAdminFacet.requestBookDecommission.selector;
        selectors[6] = IBookAdminFacet.finalizeBookDecommission.selector;
    }

    function _bookOrderSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = IBookOrderFacet.postBookCurve.selector;
        selectors[1] = IBookOrderFacet.postBookCurvesBatch.selector;
        selectors[2] = IBookOrderFacet.topUpBookCurvesBatch.selector;
        selectors[3] = IBookOrderFacet.reactivateBookCurve.selector;
    }

    function _bookTradeSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = IBookTradeFacet.fillBookBest.selector;
        selectors[1] = IBookTradeFacet.fillBookBestFor.selector;
        selectors[2] = IBookTradeFacet.sellBookBest.selector;
    }

    function _bookViewSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = IBookViewFacet.previewBookExecution.selector;
        selectors[1] = IBookViewFacet.getBookTopOfBook.selector;
    }

    function _delayedOrderSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = DelayedOrderFacet.submitDelayedOrder.selector;
        selectors[1] = DelayedOrderFacet.processDelayedOrders.selector;
        selectors[2] = DelayedOrderFacet.getDelayedOrder.selector;
        selectors[3] = DelayedOrderFacet.getQuoteCredit.selector;
    }
}
