// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC1155} from "../../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";
import {BookFacet} from "../../src/facets/BookFacet.sol";
import {BookTradeFacet} from "../../src/facets/BookTradeFacet.sol";
import {CurveInventoryFacet} from "../../src/facets/CurveInventoryFacet.sol";
import {CurveLifecycleFacet} from "../../src/facets/CurveLifecycleFacet.sol";
import {CurveViewFacet} from "../../src/facets/CurveViewFacet.sol";
import {DelayedOrderFacet} from "../../src/facets/DelayedOrderFacet.sol";
import {IBookAdminFacet} from "../../src/interfaces/IBookAdminFacet.sol";
import {IBookTradeFacet} from "../../src/interfaces/IBookTradeFacet.sol";
import {ICurveInventoryFacet} from "../../src/interfaces/ICurveInventoryFacet.sol";
import {ICurveLifecycleFacet} from "../../src/interfaces/ICurveLifecycleFacet.sol";
import {ICurveViewFacet} from "../../src/interfaces/ICurveViewFacet.sol";
import {Events} from "../../src/libraries/Events.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {LibCLOBBook} from "../../src/libraries/LibCLOBBook.sol";
import {LibCurvePacking} from "../../src/libraries/LibCurvePacking.sol";
import {LibCurveStorage} from "../../src/libraries/LibCurveStorage.sol";
import {LibDelayedOrder} from "../../src/libraries/LibDelayedOrder.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {CurveCLOBTypes} from "../../src/types/CurveCLOBTypes.sol";
import {DelayedOrderTypes} from "../../src/types/DelayedOrderTypes.sol";
import {ITestStateFacet, TestBase} from "../helpers/TestBase.sol";

interface IDelayedOrderFlatCurveHarnessFacet {
    function createFlatCurveFromEscrow(
        bytes32 bookId,
        address owner,
        LibEveMarket.CurveSide curveSide,
        uint128 volume,
        uint128 quoteEscrow,
        uint72 price,
        uint24 durationMinutes
    ) external returns (uint256 curveId);

    function bookCurveIdsLength(bytes32 bookId) external view returns (uint256 length);
    function bookCurveIdAt(bytes32 bookId, uint256 index) external view returns (uint256 curveId);
    function bookCurveCount(bytes32 bookId) external view returns (uint256 count);
    function marketCurveCount(bytes32 marketId) external view returns (uint256 count);
    function setMarketPayoutUnit(bytes32 marketId, uint128 payoutUnit) external;
}

interface IDelayedOrderLifecycleFacet {
    function submitDelayedOrder(DelayedOrderTypes.SubmitDelayedOrderParams calldata params)
        external
        returns (uint256 orderId);

    function processDelayedOrders(
        bytes32 bookId,
        uint256 maxOrders,
        DelayedOrderTypes.DelayedOrderRoute[] calldata routes
    ) external returns (DelayedOrderTypes.ProcessDelayedOrderResult memory result);

    function processDelayedOrdersFrom(
        bytes32 bookId,
        uint64 expectedHeadSequence,
        uint256 maxOrders,
        DelayedOrderTypes.DelayedOrderRoute[] calldata routes
    ) external returns (DelayedOrderTypes.ProcessDelayedOrderResult memory result);

    function expireDelayedOrders(bytes32 bookId, uint256 maxOrders)
        external
        returns (DelayedOrderTypes.ProcessDelayedOrderResult memory result);

    function getDelayedOrder(uint256 orderId) external view returns (DelayedOrderTypes.DelayedOrderView memory order);

    function getQuoteCredit(address owner, address token)
        external
        view
        returns (DelayedOrderTypes.CreditBalanceView memory credit);
    function getBaseCredit(address owner, uint8 assetType, address token, uint256 tokenId)
        external
        view
        returns (DelayedOrderTypes.CreditBalanceView memory credit);
    function getBookQueue(bytes32 bookId) external view returns (DelayedOrderTypes.BookQueueView memory queue);
    function getDelayedOrderHead(bytes32 bookId) external view returns (DelayedOrderTypes.DelayedOrderHeadView memory view_);
    function withdrawBaseCredit(uint8 assetType, address token, uint256 tokenId, uint128 amount) external;
}

contract DelayedOrderFlatCurveHarnessFacet {
    function createFlatCurveFromEscrow(
        bytes32 bookId,
        address owner,
        LibEveMarket.CurveSide curveSide,
        uint128 volume,
        uint128 quoteEscrow,
        uint72 price,
        uint24 durationMinutes
    ) external returns (uint256 curveId) {
        curveId = LibCurveStorage.createFlatCurveFromEscrow(
            LibEveMarket.store(),
            LibCurveStorage.FlatCurveFromEscrowParams({
                bookId: bookId,
                maker: owner,
                curveSide: curveSide,
                volume: volume,
                quoteEscrow: quoteEscrow,
                price: price,
                durationMinutes: durationMinutes
            })
        );
    }

    function bookCurveIdsLength(bytes32 bookId) external view returns (uint256 length) {
        length = LibEveMarket.store().bookCurveIds[bookId].length;
    }

    function bookCurveIdAt(bytes32 bookId, uint256 index) external view returns (uint256 curveId) {
        curveId = LibEveMarket.store().bookCurveIds[bookId][index];
    }

    function bookCurveCount(bytes32 bookId) external view returns (uint256 count) {
        count = LibEveMarket.store().books[bookId].curveCount;
    }

    function marketCurveCount(bytes32 marketId) external view returns (uint256 count) {
        count = LibEveMarket.store().markets[marketId].curveCount;
    }

    function setMarketPayoutUnit(bytes32 marketId, uint128 payoutUnit) external {
        LibEveMarket.store().markets[marketId].payoutUnit = payoutUnit;
    }
}

contract DelayedOrderTest is TestBase {
    uint72 internal constant HALF_PRICE = 500_000_000;
    uint72 internal constant LOW_PRICE = 400_000_000;
    uint64 internal constant DELAY_BLOCKS = 3;
    uint64 internal constant GRACE_BLOCKS = 10;
    uint24 internal constant FLAT_DURATION = 180;
    uint128 internal constant BASE_VOLUME = 1_000e6;
    uint128 internal constant QUOTE_ESCROW = 500e6;

    function setUp() public override {
        super.setUp();

        vm.startPrank(owner);
        diamond.registerFacet(address(new DelayedOrderFacet()), _delayedOrderSelectors());
        diamond.registerFacet(address(new BookFacet()), _bookSelectors());
        diamond.registerFacet(address(new BookTradeFacet()), _bookTradeSelectors());
        diamond.registerFacet(address(new CurveInventoryFacet()), _curveInventorySelectors());
        diamond.registerFacet(address(new CurveLifecycleFacet()), _curveLifecycleSelectors());
        diamond.registerFacet(address(new CurveViewFacet()), _curveViewSelectors());
        diamond.registerFacet(address(new DelayedOrderFlatCurveHarnessFacet()), _flatCurveHarnessSelectors());
        ITestStateFacet(address(diamond)).setDelayedOrderConfigFixture(DELAY_BLOCKS, GRACE_BLOCKS, FLAT_DURATION);
        ITestStateFacet(address(diamond))
            .setDelayedOrderProcessingFixture(uint8(LibEveMarket.ProcessingMode.Permissionless), 0);
        vm.stopPrank();
    }

    function test_CreateAskFlatCurveFromEscrowIndexesAndCancels() public {
        (bytes32 marketId, bytes32 bookId, uint256 yesPositionId) = _createYesBook();
        _splitToMakerEscrow(marketId, yesPositionId, BASE_VOLUME);

        uint256 makerBefore = conditionalTokens.balanceOf(maker, yesPositionId);
        uint256 curveId = _createFlatAsk(bookId, BASE_VOLUME);

        _assertStoredFlatCurve(curveId, marketId, bookId, maker, LibEveMarket.CurveSide.ASK, BASE_VOLUME, 0);
        _assertCurveIndexes(marketId, bookId, curveId);

        vm.prank(maker);
        ICurveLifecycleFacet(address(diamond)).cancelCurve(curveId);

        CurveCLOBTypes.CurveInfo memory cancelled = ICurveViewFacet(address(diamond)).getCurveInfo(curveId);
        assertFalse(cancelled.active);
        assertEq(cancelled.remainingVolume, 0);
        assertEq(conditionalTokens.balanceOf(maker, yesPositionId), makerBefore + BASE_VOLUME);
    }

    function test_CreateAskFlatCurveFromEscrowFillsThroughBookEngine() public {
        (bytes32 marketId, bytes32 bookId, uint256 yesPositionId) = _createYesBook();
        _splitToMakerEscrow(marketId, yesPositionId, BASE_VOLUME);
        uint256 curveId = _createFlatAsk(bookId, BASE_VOLUME);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        uint256 takerBefore = conditionalTokens.balanceOf(taker, yesPositionId);
        uint256 makerQuoteBefore = usdc.balanceOf(maker);

        vm.startPrank(taker);
        usdc.approve(address(diamond), QUOTE_ESCROW);
        CurveCLOBTypes.FillBestResult memory result =
            _fillSingleBookCurve(bookId, curveId, QUOTE_ESCROW, BASE_VOLUME, generation, commitment);
        vm.stopPrank();

        assertEq(result.sharesOut, BASE_VOLUME);
        assertEq(result.collateralUsed, QUOTE_ESCROW);
        assertEq(conditionalTokens.balanceOf(taker, yesPositionId), takerBefore + BASE_VOLUME);
        assertEq(usdc.balanceOf(maker), makerQuoteBefore + QUOTE_ESCROW);

        CurveCLOBTypes.CurveInfo memory filled = ICurveViewFacet(address(diamond)).getCurveInfo(curveId);
        assertEq(filled.remainingVolume, 0);
    }

    function test_CreateBidFlatCurveFromEscrowIndexesAndCancels() public {
        (bytes32 marketId, bytes32 bookId,) = _createYesBook();
        _transferQuoteToDiamond(maker, QUOTE_ESCROW);
        uint256 makerBefore = usdc.balanceOf(maker);

        (uint128 bidVolume,) =
            LibDelayedOrder.bidVolumeFromEscrow(QUOTE_ESCROW, HALF_PRICE, uint128(LibCurvePacking.PRICE_SCALE));
        uint256 curveId = _createFlatBid(bookId, bidVolume, QUOTE_ESCROW);

        _assertStoredFlatCurve(curveId, marketId, bookId, maker, LibEveMarket.CurveSide.BID, bidVolume, QUOTE_ESCROW);
        _assertCurveIndexes(marketId, bookId, curveId);

        vm.prank(maker);
        ICurveLifecycleFacet(address(diamond)).cancelCurve(curveId);

        CurveCLOBTypes.CurveInfo memory cancelled = ICurveViewFacet(address(diamond)).getCurveInfo(curveId);
        assertFalse(cancelled.active);
        assertEq(cancelled.remainingVolume, 0);
        assertEq(cancelled.quoteEscrowRemaining, 0);
        assertEq(usdc.balanceOf(maker), makerBefore + QUOTE_ESCROW);
    }

    function test_CreateBidFlatCurveFromEscrowSellsThroughBookEngine() public {
        (bytes32 marketId, bytes32 bookId, uint256 yesPositionId) = _createYesBook();
        _transferQuoteToDiamond(maker, QUOTE_ESCROW);
        (uint128 bidVolume,) =
            LibDelayedOrder.bidVolumeFromEscrow(QUOTE_ESCROW, HALF_PRICE, uint128(LibCurvePacking.PRICE_SCALE));
        uint256 curveId = _createFlatBid(bookId, bidVolume, QUOTE_ESCROW);
        _splitToTaker(marketId, BASE_VOLUME);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        uint256 makerBaseBefore = conditionalTokens.balanceOf(maker, yesPositionId);
        uint256 takerQuoteBefore = usdc.balanceOf(taker);

        vm.startPrank(taker);
        conditionalTokens.setApprovalForAll(address(diamond), true);
        CurveCLOBTypes.SellBookResult memory result =
            _sellSingleBookCurve(bookId, curveId, BASE_VOLUME, generation, commitment);
        vm.stopPrank();

        assertEq(result.baseSold, BASE_VOLUME);
        assertEq(result.quoteOut, QUOTE_ESCROW);
        assertEq(conditionalTokens.balanceOf(maker, yesPositionId), makerBaseBefore + BASE_VOLUME);
        assertEq(usdc.balanceOf(taker), takerQuoteBefore + QUOTE_ESCROW);

        CurveCLOBTypes.CurveInfo memory filled = ICurveViewFacet(address(diamond)).getCurveInfo(curveId);
        assertEq(filled.remainingVolume, 0);
        assertEq(filled.quoteEscrowRemaining, 0);
    }

    function test_DelayedMarketBuyFillsAfterDelay() public {
        (bytes32 marketId, bytes32 bookId, uint256 yesPositionId) = _createYesBook();
        _splitToMakerEscrow(marketId, yesPositionId, BASE_VOLUME);
        uint256 curveId = _createFlatAsk(bookId, BASE_VOLUME);
        DelayedOrderTypes.DelayedOrderRoute memory route = _route(curveId);
        uint256 orderId = _submitMarketBuy(bookId, QUOTE_ESCROW, route);
        _rollExecutable();

        _processOne(bookId, route);

        DelayedOrderTypes.DelayedOrderView memory order = _delayedOrder(orderId);
        assertEq(uint8(order.status), uint8(LibEveMarket.DelayedOrderStatus.Filled));
        assertEq(conditionalTokens.balanceOf(taker, yesPositionId), BASE_VOLUME);
        assertEq(order.remainingAmount, 0);
    }

    function test_RevertWhen_DelayedRouteExceedsConfiguredCap() public {
        (, bytes32 bookId,) = _createYesBook();
        ITestStateFacet(address(diamond)).setDelayedOrderGuardsFixture(64, 0, 0);
        DelayedOrderTypes.DelayedOrderRoute memory route = _sizedRoute(65);

        DelayedOrderTypes.SubmitDelayedOrderParams memory params = _submitParams(bookId, QUOTE_ESCROW, route);
        params.kind = LibEveMarket.DelayedOrderKind.MarketBuy;

        vm.startPrank(taker);
        usdc.approve(address(diamond), QUOTE_ESCROW);
        vm.expectRevert(abi.encodeWithSelector(Errors.DelayedOrderRouteTooLong.selector, 65, 64));
        IDelayedOrderLifecycleFacet(address(diamond)).submitDelayedOrder(params);
        vm.stopPrank();
    }

    function test_DelayedRouteAcceptsConfiguredCapBoundary() public {
        (, bytes32 bookId,) = _createYesBook();
        ITestStateFacet(address(diamond)).setDelayedOrderGuardsFixture(64, 0, 0);

        uint256 orderId = _submitMarketBuy(bookId, QUOTE_ESCROW, _sizedRoute(64));

        DelayedOrderTypes.DelayedOrderView memory order = _delayedOrder(orderId);
        assertEq(uint8(order.status), uint8(LibEveMarket.DelayedOrderStatus.Pending));
    }

    function test_RevertWhen_DelayedBuyBelowNormalizedQuoteMinimum() public {
        (bytes32 marketId, bytes32 bookId,) = _createYesBook();
        IDelayedOrderFlatCurveHarnessFacet(address(diamond)).setMarketPayoutUnit(marketId, 1e6);
        ITestStateFacet(address(diamond)).setDelayedOrderGuardsFixture(0, 1e18, 0);

        uint128 amount = 999_999;
        DelayedOrderTypes.SubmitDelayedOrderParams memory params = _submitParams(bookId, amount, _emptyRoute());
        params.kind = LibEveMarket.DelayedOrderKind.MarketBuy;

        vm.startPrank(taker);
        usdc.approve(address(diamond), amount);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.DelayedOrderQuoteBelowMinimum.selector, 999_999_000_000_000_000, 1e18)
        );
        IDelayedOrderLifecycleFacet(address(diamond)).submitDelayedOrder(params);
        vm.stopPrank();
    }

    function test_RevertWhen_DelayedSellBelowNormalizedBaseMinimum() public {
        (bytes32 marketId, bytes32 bookId,) = _createYesBook();
        IDelayedOrderFlatCurveHarnessFacet(address(diamond)).setMarketPayoutUnit(marketId, 1e6);
        ITestStateFacet(address(diamond)).setDelayedOrderGuardsFixture(0, 0, 1e18);

        uint128 amount = 999_999;
        DelayedOrderTypes.SubmitDelayedOrderParams memory params = _submitParams(bookId, amount, _emptyRoute());
        params.kind = LibEveMarket.DelayedOrderKind.MarketSell;

        vm.startPrank(taker);
        conditionalTokens.setApprovalForAll(address(diamond), true);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.DelayedOrderBaseBelowMinimum.selector, 999_999_000_000_000_000, 1e18)
        );
        IDelayedOrderLifecycleFacet(address(diamond)).submitDelayedOrder(params);
        vm.stopPrank();
    }

    function test_ProcessDelayedOrdersFromRequiresExpectedHead() public {
        (bytes32 marketId, bytes32 bookId, uint256 yesPositionId) = _createYesBook();
        _splitToMakerEscrow(marketId, yesPositionId, BASE_VOLUME);
        uint256 curveId = _createFlatAsk(bookId, BASE_VOLUME);
        DelayedOrderTypes.DelayedOrderRoute memory route = _route(curveId);
        uint256 orderId = _submitMarketBuy(bookId, QUOTE_ESCROW, route);
        _rollExecutable();

        vm.expectRevert(abi.encodeWithSelector(Errors.DelayedOrderHeadMismatch.selector, bookId, 1, 0));
        IDelayedOrderLifecycleFacet(address(diamond)).processDelayedOrdersFrom(bookId, 1, 1, _routes(route));

        DelayedOrderTypes.ProcessDelayedOrderResult memory result =
            IDelayedOrderLifecycleFacet(address(diamond)).processDelayedOrdersFrom(bookId, 0, 1, _routes(route));

        assertEq(result.processedCount, 1);
        assertEq(uint8(_delayedOrder(orderId).status), uint8(LibEveMarket.DelayedOrderStatus.Filled));
    }

    function test_ExpireDelayedOrdersExpiresOnlyExpiredHeads() public {
        (, bytes32 bookId,) = _createYesBook();
        uint256 firstOrderId = _submitMarketBuy(bookId, QUOTE_ESCROW, _emptyRoute());
        uint256 secondOrderId = _submitMarketBuy(bookId, QUOTE_ESCROW, _emptyRoute());

        vm.roll(_delayedOrder(firstOrderId).expiryBlock + 1);
        DelayedOrderTypes.ProcessDelayedOrderResult memory result =
            IDelayedOrderLifecycleFacet(address(diamond)).expireDelayedOrders(bookId, 10);

        assertEq(result.processedCount, 2);
        assertEq(result.stoppedOrderId, 0);
        assertEq(uint8(_delayedOrder(firstOrderId).status), uint8(LibEveMarket.DelayedOrderStatus.Expired));
        assertEq(uint8(_delayedOrder(secondOrderId).status), uint8(LibEveMarket.DelayedOrderStatus.Expired));
        assertEq(
            IDelayedOrderLifecycleFacet(address(diamond)).getQuoteCredit(taker, address(usdc)).withdrawable,
            QUOTE_ESCROW * 2
        );
    }

    function test_ExpireDelayedOrdersStopsAtNonExpiredHead() public {
        (, bytes32 bookId,) = _createYesBook();
        uint256 orderId = _submitMarketBuy(bookId, QUOTE_ESCROW, _emptyRoute());

        vm.roll(_delayedOrder(orderId).executableBlock);
        DelayedOrderTypes.ProcessDelayedOrderResult memory result =
            IDelayedOrderLifecycleFacet(address(diamond)).expireDelayedOrders(bookId, 10);

        assertEq(result.processedCount, 0);
        assertEq(result.stoppedOrderId, orderId);
        assertEq(uint8(_delayedOrder(orderId).status), uint8(LibEveMarket.DelayedOrderStatus.Pending));
    }

    function test_ExpireDelayedOrdersWorksWhenProcessingPaused() public {
        (, bytes32 bookId,) = _createYesBook();
        uint256 orderId = _submitMarketBuy(bookId, QUOTE_ESCROW, _emptyRoute());
        ITestStateFacet(address(diamond))
            .setDelayedOrderProcessingFixture(uint8(LibEveMarket.ProcessingMode.Paused), 0);

        vm.roll(_delayedOrder(orderId).expiryBlock + 1);
        DelayedOrderTypes.ProcessDelayedOrderResult memory result =
            IDelayedOrderLifecycleFacet(address(diamond)).expireDelayedOrders(bookId, 1);

        assertEq(result.processedCount, 1);
        assertEq(uint8(_delayedOrder(orderId).status), uint8(LibEveMarket.DelayedOrderStatus.Expired));
    }

    function test_GetDelayedOrderHeadReportsProcessorState() public {
        bytes32 emptyBookId = keccak256("empty-delayed-book");
        DelayedOrderTypes.DelayedOrderHeadView memory head =
            IDelayedOrderLifecycleFacet(address(diamond)).getDelayedOrderHead(emptyBookId);
        assertEq(uint8(head.processState), uint8(DelayedOrderTypes.DelayedOrderHeadState.Empty));

        (, bytes32 bookId,) = _createYesBook();
        uint256 orderId = _submitMarketBuy(bookId, QUOTE_ESCROW, _emptyRoute());
        head = IDelayedOrderLifecycleFacet(address(diamond)).getDelayedOrderHead(bookId);
        assertEq(head.orderId, orderId);
        assertEq(head.head, 0);
        assertEq(head.tail, 1);
        assertEq(uint8(head.processState), uint8(DelayedOrderTypes.DelayedOrderHeadState.Waiting));

        vm.roll(_delayedOrder(orderId).executableBlock);
        head = IDelayedOrderLifecycleFacet(address(diamond)).getDelayedOrderHead(bookId);
        assertEq(uint8(head.processState), uint8(DelayedOrderTypes.DelayedOrderHeadState.NeedsRoute));

        ITestStateFacet(address(diamond))
            .setDelayedOrderProcessingFixture(uint8(LibEveMarket.ProcessingMode.Paused), 0);
        head = IDelayedOrderLifecycleFacet(address(diamond)).getDelayedOrderHead(bookId);
        assertEq(uint8(head.processState), uint8(DelayedOrderTypes.DelayedOrderHeadState.Paused));

        vm.roll(_delayedOrder(orderId).expiryBlock + 1);
        head = IDelayedOrderLifecycleFacet(address(diamond)).getDelayedOrderHead(bookId);
        assertEq(uint8(head.processState), uint8(DelayedOrderTypes.DelayedOrderHeadState.Expired));
    }

    function test_DelayedMarketBuyDoesNotProcessBeforeDelay() public {
        (bytes32 marketId, bytes32 bookId, uint256 yesPositionId) = _createYesBook();
        _splitToMakerEscrow(marketId, yesPositionId, BASE_VOLUME);
        uint256 curveId = _createFlatAsk(bookId, BASE_VOLUME);
        DelayedOrderTypes.DelayedOrderRoute memory route = _route(curveId);
        uint256 orderId = _submitMarketBuy(bookId, QUOTE_ESCROW, route);

        DelayedOrderTypes.ProcessDelayedOrderResult memory result = _processOne(bookId, route);

        assertEq(result.processedCount, 0);
        assertEq(result.stoppedOrderId, orderId);
        assertEq(uint8(_delayedOrder(orderId).status), uint8(LibEveMarket.DelayedOrderStatus.Pending));
        assertEq(conditionalTokens.balanceOf(taker, yesPositionId), 0);
    }

    function test_DelayedMarketBuyMissesAfterMakerUpdateAndCreditsQuote() public {
        (bytes32 marketId, bytes32 bookId, uint256 yesPositionId) = _createYesBook();
        _splitToMakerEscrow(marketId, yesPositionId, BASE_VOLUME);
        uint256 curveId = _createFlatAsk(bookId, BASE_VOLUME);
        DelayedOrderTypes.DelayedOrderRoute memory route = _route(curveId);
        uint256 orderId = _submitMarketBuy(bookId, QUOTE_ESCROW, route);

        vm.prank(maker);
        ICurveLifecycleFacet(address(diamond)).updateCurve(curveId, _flatPacked(LOW_PRICE), 1);
        _rollExecutable();
        _processOne(bookId, route);

        DelayedOrderTypes.DelayedOrderView memory order = _delayedOrder(orderId);
        assertEq(uint8(order.status), uint8(LibEveMarket.DelayedOrderStatus.Cancelled));
        assertEq(conditionalTokens.balanceOf(taker, yesPositionId), 0);
        assertEq(
            IDelayedOrderLifecycleFacet(address(diamond)).getQuoteCredit(taker, address(usdc)).withdrawable,
            QUOTE_ESCROW
        );
    }

    function test_DelayedMarketBuyMissesAfterMakerCancellationAndCreditsQuote() public {
        (bytes32 marketId, bytes32 bookId, uint256 yesPositionId) = _createYesBook();
        _splitToMakerEscrow(marketId, yesPositionId, BASE_VOLUME);
        uint256 curveId = _createFlatAsk(bookId, BASE_VOLUME);
        DelayedOrderTypes.DelayedOrderRoute memory route = _route(curveId);
        uint256 orderId = _submitMarketBuy(bookId, QUOTE_ESCROW, route);

        vm.prank(maker);
        ICurveLifecycleFacet(address(diamond)).cancelCurve(curveId);
        _rollExecutable();
        _processOne(bookId, route);

        DelayedOrderTypes.DelayedOrderView memory order = _delayedOrder(orderId);
        assertEq(uint8(order.status), uint8(LibEveMarket.DelayedOrderStatus.Cancelled));
        assertEq(conditionalTokens.balanceOf(taker, yesPositionId), 0);
        assertEq(
            IDelayedOrderLifecycleFacet(address(diamond)).getQuoteCredit(taker, address(usdc)).withdrawable,
            QUOTE_ESCROW
        );
    }

    function test_DelayedLimitBuyFullyFills() public {
        (bytes32 marketId, bytes32 bookId, uint256 yesPositionId) = _createYesBook();
        _splitToMakerEscrow(marketId, yesPositionId, BASE_VOLUME);
        uint256 curveId = _createFlatAsk(bookId, BASE_VOLUME);
        DelayedOrderTypes.DelayedOrderRoute memory route = _route(curveId);
        uint256 orderId = _submitLimitBuy(bookId, QUOTE_ESCROW, HALF_PRICE, route);
        _rollExecutable();

        _processOne(bookId, route);

        DelayedOrderTypes.DelayedOrderView memory order = _delayedOrder(orderId);
        assertEq(uint8(order.status), uint8(LibEveMarket.DelayedOrderStatus.Filled));
        assertEq(order.restingCurveId, 0);
        assertEq(conditionalTokens.balanceOf(taker, yesPositionId), BASE_VOLUME);
    }

    function test_DelayedLimitBuyPartiallyFillsAndCreatesFlatBid() public {
        (bytes32 marketId, bytes32 bookId, uint256 yesPositionId) = _createYesBook();
        uint128 askVolume = BASE_VOLUME / 2;
        _splitToMakerEscrow(marketId, yesPositionId, askVolume);
        uint256 curveId = _createFlatAsk(bookId, askVolume);
        DelayedOrderTypes.DelayedOrderRoute memory route = _route(curveId);
        uint256 orderId = _submitLimitBuy(bookId, QUOTE_ESCROW, HALF_PRICE, route);
        _rollExecutable();

        _processOne(bookId, route);

        DelayedOrderTypes.DelayedOrderView memory order = _delayedOrder(orderId);
        assertEq(uint8(order.status), uint8(LibEveMarket.DelayedOrderStatus.Resting));
        assertEq(conditionalTokens.balanceOf(taker, yesPositionId), askVolume);
        CurveCLOBTypes.CurveInfo memory resting = ICurveViewFacet(address(diamond)).getCurveInfo(order.restingCurveId);
        assertEq(resting.maker, taker);
        assertEq(uint8(resting.curveSide), uint8(LibEveMarket.CurveSide.BID));
        assertEq(resting.startPrice, HALF_PRICE);
        assertEq(resting.endPrice, HALF_PRICE);
        assertEq(resting.quoteEscrowRemaining, QUOTE_ESCROW / 2);
    }

    function test_DelayedLimitBuyMissCreatesFlatBid() public {
        (bytes32 marketId, bytes32 bookId, uint256 yesPositionId) = _createYesBook();
        _splitToMakerEscrow(marketId, yesPositionId, BASE_VOLUME);
        uint256 curveId = _createFlatAsk(bookId, BASE_VOLUME);
        DelayedOrderTypes.DelayedOrderRoute memory route = _route(curveId);
        uint256 orderId = _submitLimitBuy(bookId, QUOTE_ESCROW, HALF_PRICE, route);

        vm.prank(maker);
        ICurveLifecycleFacet(address(diamond)).cancelCurve(curveId);
        _rollExecutable();
        _processOne(bookId, route);

        DelayedOrderTypes.DelayedOrderView memory order = _delayedOrder(orderId);
        assertEq(uint8(order.status), uint8(LibEveMarket.DelayedOrderStatus.Resting));
        assertEq(conditionalTokens.balanceOf(taker, yesPositionId), 0);
        CurveCLOBTypes.CurveInfo memory resting = ICurveViewFacet(address(diamond)).getCurveInfo(order.restingCurveId);
        assertEq(resting.maker, taker);
        assertEq(uint8(resting.curveSide), uint8(LibEveMarket.CurveSide.BID));
        assertEq(resting.remainingVolume, BASE_VOLUME);
        assertEq(resting.quoteEscrowRemaining, QUOTE_ESCROW);
    }

    function test_DelayedMarketSellFillsAfterDelay() public {
        (bytes32 marketId, bytes32 bookId, uint256 yesPositionId) = _createYesBook();
        _splitToTaker(marketId, BASE_VOLUME);
        _transferQuoteToDiamond(maker, QUOTE_ESCROW);
        uint256 curveId = _createFlatBid(bookId, BASE_VOLUME, QUOTE_ESCROW);
        DelayedOrderTypes.DelayedOrderRoute memory route = _route(curveId);
        uint256 orderId = _submitMarketSell(bookId, BASE_VOLUME, route);
        uint256 takerQuoteBefore = usdc.balanceOf(taker);
        _rollExecutable();

        _processOne(bookId, route);

        DelayedOrderTypes.DelayedOrderView memory order = _delayedOrder(orderId);
        assertEq(uint8(order.status), uint8(LibEveMarket.DelayedOrderStatus.Filled));
        assertEq(order.remainingAmount, 0);
        assertEq(conditionalTokens.balanceOf(maker, yesPositionId), BASE_VOLUME);
        assertEq(usdc.balanceOf(taker), takerQuoteBefore + QUOTE_ESCROW);
        assertEq(_baseCredit(taker, yesPositionId), 0);
    }

    function test_DelayedMarketSellMissCreditsBase() public {
        (bytes32 marketId, bytes32 bookId, uint256 yesPositionId) = _createYesBook();
        _splitToTaker(marketId, BASE_VOLUME);
        _transferQuoteToDiamond(maker, QUOTE_ESCROW);
        uint256 curveId = _createFlatBid(bookId, BASE_VOLUME, QUOTE_ESCROW);
        DelayedOrderTypes.DelayedOrderRoute memory route = _route(curveId);
        uint256 orderId = _submitMarketSell(bookId, BASE_VOLUME, route);

        vm.prank(maker);
        ICurveLifecycleFacet(address(diamond)).cancelCurve(curveId);
        _rollExecutable();
        _processOne(bookId, route);

        DelayedOrderTypes.DelayedOrderView memory order = _delayedOrder(orderId);
        assertEq(uint8(order.status), uint8(LibEveMarket.DelayedOrderStatus.Cancelled));
        assertEq(_baseCredit(taker, yesPositionId), BASE_VOLUME);
        assertEq(conditionalTokens.balanceOf(taker, yesPositionId), 0);
    }

    function test_DelayedLimitSellPartiallyFillsAndCreatesFlatAsk() public {
        (bytes32 marketId, bytes32 bookId, uint256 yesPositionId) = _createYesBook();
        uint128 bidVolume = BASE_VOLUME / 2;
        _splitToTaker(marketId, BASE_VOLUME);
        _transferQuoteToDiamond(maker, QUOTE_ESCROW / 2);
        uint256 curveId = _createFlatBid(bookId, bidVolume, QUOTE_ESCROW / 2);
        DelayedOrderTypes.DelayedOrderRoute memory route = _route(curveId);
        uint256 orderId = _submitLimitSell(bookId, BASE_VOLUME, HALF_PRICE, route);
        _rollExecutable();

        _processOne(bookId, route);

        DelayedOrderTypes.DelayedOrderView memory order = _delayedOrder(orderId);
        assertEq(uint8(order.status), uint8(LibEveMarket.DelayedOrderStatus.Resting));
        assertEq(_baseCredit(taker, yesPositionId), 0);
        assertEq(conditionalTokens.balanceOf(maker, yesPositionId), bidVolume);
        CurveCLOBTypes.CurveInfo memory resting = ICurveViewFacet(address(diamond)).getCurveInfo(order.restingCurveId);
        assertEq(resting.maker, taker);
        assertEq(uint8(resting.curveSide), uint8(LibEveMarket.CurveSide.ASK));
        assertEq(resting.remainingVolume, BASE_VOLUME - bidVolume);
        assertEq(resting.quoteEscrowRemaining, 0);
        assertEq(resting.startPrice, HALF_PRICE);
    }

    function test_DelayedLimitSellMissCreatesFlatAskAndOwnerCanCancel() public {
        (bytes32 marketId, bytes32 bookId, uint256 yesPositionId) = _createYesBook();
        _splitToTaker(marketId, BASE_VOLUME);
        _transferQuoteToDiamond(maker, QUOTE_ESCROW);
        uint256 curveId = _createFlatBid(bookId, BASE_VOLUME, QUOTE_ESCROW);
        DelayedOrderTypes.DelayedOrderRoute memory route = _route(curveId);
        uint256 orderId = _submitLimitSell(bookId, BASE_VOLUME, HALF_PRICE, route);

        vm.prank(maker);
        ICurveLifecycleFacet(address(diamond)).cancelCurve(curveId);
        _rollExecutable();
        _processOne(bookId, route);

        DelayedOrderTypes.DelayedOrderView memory order = _delayedOrder(orderId);
        assertEq(uint8(order.status), uint8(LibEveMarket.DelayedOrderStatus.Resting));
        CurveCLOBTypes.CurveInfo memory resting = ICurveViewFacet(address(diamond)).getCurveInfo(order.restingCurveId);
        assertEq(uint8(resting.curveSide), uint8(LibEveMarket.CurveSide.ASK));
        assertEq(resting.remainingVolume, BASE_VOLUME);

        vm.prank(taker);
        ICurveLifecycleFacet(address(diamond)).cancelCurve(order.restingCurveId);

        CurveCLOBTypes.CurveInfo memory cancelled = ICurveViewFacet(address(diamond)).getCurveInfo(order.restingCurveId);
        assertFalse(cancelled.active);
        assertEq(conditionalTokens.balanceOf(taker, yesPositionId), BASE_VOLUME);
    }

    function test_DelayedLimitSellRestingAskIsFillable() public {
        (bytes32 marketId, bytes32 bookId, uint256 yesPositionId) = _createYesBook();
        _splitToTaker(marketId, BASE_VOLUME);
        uint256 orderId = _submitLimitSell(bookId, BASE_VOLUME, HALF_PRICE, _emptyRoute());
        _rollExecutable();
        _processOne(bookId, _emptyRoute());

        uint256 restingCurveId = _delayedOrder(orderId).restingCurveId;
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(restingCurveId);

        vm.startPrank(maker);
        usdc.approve(address(diamond), QUOTE_ESCROW);
        _fillSingleBookCurveFor(maker, bookId, restingCurveId, QUOTE_ESCROW, BASE_VOLUME, generation, commitment);
        vm.stopPrank();

        assertEq(conditionalTokens.balanceOf(maker, yesPositionId), BASE_VOLUME);
        CurveCLOBTypes.CurveInfo memory filled = ICurveViewFacet(address(diamond)).getCurveInfo(restingCurveId);
        assertEq(filled.remainingVolume, 0);
    }

    function test_DelayedSellExpiryCreditsBase() public {
        (bytes32 marketId, bytes32 bookId, uint256 yesPositionId) = _createYesBook();
        _splitToTaker(marketId, BASE_VOLUME);
        uint256 orderId = _submitMarketSell(bookId, BASE_VOLUME, _emptyRoute());

        vm.roll(block.number + DELAY_BLOCKS + GRACE_BLOCKS + 1);
        IDelayedOrderLifecycleFacet(address(diamond))
            .processDelayedOrders(bookId, 1, new DelayedOrderTypes.DelayedOrderRoute[](0));

        DelayedOrderTypes.DelayedOrderView memory order = _delayedOrder(orderId);
        assertEq(uint8(order.status), uint8(LibEveMarket.DelayedOrderStatus.Expired));
        assertEq(_baseCredit(taker, yesPositionId), BASE_VOLUME);
        assertEq(order.restingCurveId, 0);
    }

    function test_DelayedSellRouteMismatchRejectsWithoutAdvancing() public {
        (bytes32 marketId, bytes32 bookId,) = _createYesBook();
        _splitToTaker(marketId, BASE_VOLUME);
        _transferQuoteToDiamond(maker, QUOTE_ESCROW);
        uint256 curveId = _createFlatBid(bookId, BASE_VOLUME, QUOTE_ESCROW);
        DelayedOrderTypes.DelayedOrderRoute memory route = _route(curveId);
        uint256 orderId = _submitMarketSell(bookId, BASE_VOLUME, route);
        route.expectedGenerations[0] += 1;
        _rollExecutable();

        vm.expectRevert();
        _processOne(bookId, route);

        assertEq(uint8(_delayedOrder(orderId).status), uint8(LibEveMarket.DelayedOrderStatus.Pending));
    }

    function test_DelayedSellCreditReuseFundsNewOrderAndWithdrawalReturnsBase() public {
        (bytes32 marketId, bytes32 bookId, uint256 yesPositionId) = _createYesBook();
        _splitToTaker(marketId, BASE_VOLUME);
        _transferQuoteToDiamond(maker, QUOTE_ESCROW);
        uint256 firstCurveId = _createFlatBid(bookId, BASE_VOLUME, QUOTE_ESCROW);
        DelayedOrderTypes.DelayedOrderRoute memory firstRoute = _route(firstCurveId);
        _submitMarketSell(bookId, BASE_VOLUME, firstRoute);
        vm.prank(maker);
        ICurveLifecycleFacet(address(diamond)).cancelCurve(firstCurveId);
        _rollExecutable();
        _processOne(bookId, firstRoute);
        assertEq(_baseCredit(taker, yesPositionId), BASE_VOLUME);

        vm.prank(taker);
        IDelayedOrderLifecycleFacet(address(diamond))
            .withdrawBaseCredit(
                uint8(LibEveMarket.BookAssetType.ERC1155), address(conditionalTokens), yesPositionId, BASE_VOLUME / 2
            );
        assertEq(_baseCredit(taker, yesPositionId), BASE_VOLUME / 2);
        assertEq(conditionalTokens.balanceOf(taker, yesPositionId), BASE_VOLUME / 2);

        _transferQuoteToDiamond(maker, QUOTE_ESCROW / 2);
        uint256 secondCurveId = _createFlatBid(bookId, BASE_VOLUME / 2, QUOTE_ESCROW / 2);
        DelayedOrderTypes.DelayedOrderRoute memory secondRoute = _route(secondCurveId);
        uint256 secondOrderId = _submitMarketSellWithoutApproval(bookId, BASE_VOLUME / 2, secondRoute);
        _rollExecutable();
        _processOne(bookId, secondRoute);

        assertEq(uint8(_delayedOrder(secondOrderId).status), uint8(LibEveMarket.DelayedOrderStatus.Filled));
        assertEq(_baseCredit(taker, yesPositionId), 0);
        assertEq(conditionalTokens.balanceOf(maker, yesPositionId), BASE_VOLUME / 2);
    }

    function test_DelayedOrderEventsAndViewsReconstructLifecycle() public {
        (bytes32 marketId, bytes32 bookId, uint256 yesPositionId) = _createYesBook();
        _splitToMakerEscrow(marketId, yesPositionId, BASE_VOLUME);
        uint256 curveId = _createFlatAsk(bookId, BASE_VOLUME);
        DelayedOrderTypes.DelayedOrderRoute memory route = _route(curveId);
        DelayedOrderTypes.SubmitDelayedOrderParams memory params = _submitParams(bookId, QUOTE_ESCROW, route);
        params.kind = LibEveMarket.DelayedOrderKind.MarketBuy;
        bytes32 routeHash =
            LibDelayedOrder.routeHashMemory(route.curveIds, route.expectedGenerations, route.expectedCommitments);

        vm.startPrank(taker);
        usdc.approve(address(diamond), QUOTE_ESCROW);
        vm.expectEmit(true, true, true, true, address(diamond));
        emit Events.DelayedOrderSubmitted(
            1,
            bookId,
            taker,
            uint8(LibEveMarket.DelayedOrderKind.MarketBuy),
            QUOTE_ESCROW,
            0,
            0,
            routeHash,
            route.curveIds,
            route.expectedGenerations,
            route.expectedCommitments
        );
        uint256 orderId = IDelayedOrderLifecycleFacet(address(diamond)).submitDelayedOrder(params);
        vm.stopPrank();

        DelayedOrderTypes.DelayedOrderView memory pending = _delayedOrder(orderId);
        DelayedOrderTypes.BookQueueView memory queue =
            IDelayedOrderLifecycleFacet(address(diamond)).getBookQueue(bookId);
        DelayedOrderTypes.CreditBalanceView memory lockedQuote =
            IDelayedOrderLifecycleFacet(address(diamond)).getQuoteCredit(taker, address(usdc));
        assertEq(pending.orderId, orderId);
        assertTrue(!pending.executable);
        assertTrue(!pending.expired);
        assertEq(queue.headOrderId, orderId);
        assertEq(queue.pendingCount, 1);
        assertEq(lockedQuote.locked, QUOTE_ESCROW);
        assertEq(lockedQuote.withdrawable, 0);

        vm.prank(maker);
        ICurveLifecycleFacet(address(diamond)).cancelCurve(curveId);
        _rollExecutable();
        vm.expectEmit(true, true, true, true, address(diamond));
        emit Events.UserCreditChanged(
            taker, LibDelayedOrder.CREDIT_ASSET_QUOTE, address(usdc), 0, int256(uint256(QUOTE_ESCROW))
        );
        vm.expectEmit(true, true, true, true, address(diamond));
        emit Events.DelayedOrderProcessed(
            orderId,
            bookId,
            taker,
            address(this),
            uint8(LibEveMarket.DelayedOrderStatus.Cancelled),
            0,
            0,
            QUOTE_ESCROW,
            0,
            0,
            0
        );
        _processOne(bookId, route);

        DelayedOrderTypes.DelayedOrderView memory cancelled = _delayedOrder(orderId);
        DelayedOrderTypes.BookQueueView memory emptyQueue =
            IDelayedOrderLifecycleFacet(address(diamond)).getBookQueue(bookId);
        DelayedOrderTypes.CreditBalanceView memory withdrawableQuote =
            IDelayedOrderLifecycleFacet(address(diamond)).getQuoteCredit(taker, address(usdc));
        assertEq(uint8(cancelled.status), uint8(LibEveMarket.DelayedOrderStatus.Cancelled));
        assertTrue(!cancelled.executable);
        assertTrue(!cancelled.expired);
        assertEq(emptyQueue.pendingCount, 0);
        assertEq(withdrawableQuote.locked, 0);
        assertEq(withdrawableQuote.withdrawable, QUOTE_ESCROW);
        assertEq(withdrawableQuote.available, QUOTE_ESCROW);
    }

    function _createYesBook() internal returns (bytes32 marketId, bytes32 bookId, uint256 yesPositionId) {
        (marketId,) = _createMarketFixture("Can delayed orders become flat curves?", _expiry(7 days));
        ITestStateFacet(address(diamond)).materializeMarketSideBookFixture(marketId, true);
        bookId = LibCLOBBook.marketBookId(marketId, true);
        (,,,, yesPositionId,) = ITestStateFacet(address(diamond)).getStoredMarketCore(marketId);
    }

    function _splitToMakerEscrow(bytes32 marketId, uint256 yesPositionId, uint128 volume) internal {
        _splitFrom(maker, marketId, volume);
        vm.prank(maker);
        IERC1155(address(conditionalTokens)).safeTransferFrom(maker, address(diamond), yesPositionId, volume, "");
    }

    function _splitToTaker(bytes32 marketId, uint128 amount) internal {
        vm.startPrank(taker);
        usdc.approve(address(diamond), amount);
        ICurveInventoryFacet(address(diamond)).splitInventory(marketId, amount);
        vm.stopPrank();
    }

    function _transferQuoteToDiamond(address account, uint128 amount) internal {
        vm.prank(account);
        usdc.transfer(address(diamond), amount);
    }

    function _createFlatAsk(bytes32 bookId, uint128 volume) internal returns (uint256 curveId) {
        curveId = IDelayedOrderFlatCurveHarnessFacet(address(diamond))
            .createFlatCurveFromEscrow(bookId, maker, LibEveMarket.CurveSide.ASK, volume, 0, HALF_PRICE, FLAT_DURATION);
    }

    function _createFlatBid(bytes32 bookId, uint128 volume, uint128 quoteEscrow) internal returns (uint256 curveId) {
        curveId = IDelayedOrderFlatCurveHarnessFacet(address(diamond))
            .createFlatCurveFromEscrow(
                bookId, maker, LibEveMarket.CurveSide.BID, volume, quoteEscrow, HALF_PRICE, FLAT_DURATION
            );
    }

    function _submitMarketBuy(bytes32 bookId, uint128 amountIn, DelayedOrderTypes.DelayedOrderRoute memory route)
        internal
        returns (uint256 orderId)
    {
        DelayedOrderTypes.SubmitDelayedOrderParams memory params = _submitParams(bookId, amountIn, route);
        params.kind = LibEveMarket.DelayedOrderKind.MarketBuy;
        vm.startPrank(taker);
        usdc.approve(address(diamond), amountIn);
        orderId = IDelayedOrderLifecycleFacet(address(diamond)).submitDelayedOrder(params);
        vm.stopPrank();
    }

    function _submitLimitBuy(
        bytes32 bookId,
        uint128 amountIn,
        uint128 limitPrice,
        DelayedOrderTypes.DelayedOrderRoute memory route
    ) internal returns (uint256 orderId) {
        DelayedOrderTypes.SubmitDelayedOrderParams memory params = _submitParams(bookId, amountIn, route);
        params.kind = LibEveMarket.DelayedOrderKind.LimitBuy;
        params.limitPrice = limitPrice;
        vm.startPrank(taker);
        usdc.approve(address(diamond), amountIn);
        orderId = IDelayedOrderLifecycleFacet(address(diamond)).submitDelayedOrder(params);
        vm.stopPrank();
    }

    function _submitMarketSell(bytes32 bookId, uint128 amountIn, DelayedOrderTypes.DelayedOrderRoute memory route)
        internal
        returns (uint256 orderId)
    {
        DelayedOrderTypes.SubmitDelayedOrderParams memory params = _submitParams(bookId, amountIn, route);
        params.kind = LibEveMarket.DelayedOrderKind.MarketSell;
        vm.startPrank(taker);
        conditionalTokens.setApprovalForAll(address(diamond), true);
        orderId = IDelayedOrderLifecycleFacet(address(diamond)).submitDelayedOrder(params);
        vm.stopPrank();
    }

    function _submitMarketSellWithoutApproval(
        bytes32 bookId,
        uint128 amountIn,
        DelayedOrderTypes.DelayedOrderRoute memory route
    ) internal returns (uint256 orderId) {
        DelayedOrderTypes.SubmitDelayedOrderParams memory params = _submitParams(bookId, amountIn, route);
        params.kind = LibEveMarket.DelayedOrderKind.MarketSell;
        vm.prank(taker);
        orderId = IDelayedOrderLifecycleFacet(address(diamond)).submitDelayedOrder(params);
    }

    function _submitLimitSell(
        bytes32 bookId,
        uint128 amountIn,
        uint128 limitPrice,
        DelayedOrderTypes.DelayedOrderRoute memory route
    ) internal returns (uint256 orderId) {
        DelayedOrderTypes.SubmitDelayedOrderParams memory params = _submitParams(bookId, amountIn, route);
        params.kind = LibEveMarket.DelayedOrderKind.LimitSell;
        params.limitPrice = limitPrice;
        vm.startPrank(taker);
        conditionalTokens.setApprovalForAll(address(diamond), true);
        orderId = IDelayedOrderLifecycleFacet(address(diamond)).submitDelayedOrder(params);
        vm.stopPrank();
    }

    function _submitParams(bytes32 bookId, uint128 amountIn, DelayedOrderTypes.DelayedOrderRoute memory route)
        internal
        pure
        returns (DelayedOrderTypes.SubmitDelayedOrderParams memory params)
    {
        params.bookId = bookId;
        params.amountIn = amountIn;
        params.maxAveragePrice = 0;
        params.curveIds = route.curveIds;
        params.expectedGenerations = route.expectedGenerations;
        params.expectedCommitments = route.expectedCommitments;
    }

    function _processOne(bytes32 bookId, DelayedOrderTypes.DelayedOrderRoute memory route)
        internal
        returns (DelayedOrderTypes.ProcessDelayedOrderResult memory result)
    {
        result = IDelayedOrderLifecycleFacet(address(diamond)).processDelayedOrders(bookId, 1, _routes(route));
    }

    function _delayedOrder(uint256 orderId) internal view returns (DelayedOrderTypes.DelayedOrderView memory order) {
        order = IDelayedOrderLifecycleFacet(address(diamond)).getDelayedOrder(orderId);
    }

    function _route(uint256 curveId) internal view returns (DelayedOrderTypes.DelayedOrderRoute memory route) {
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        route.curveIds = _singleCurve(curveId);
        route.expectedGenerations = _singleGeneration(generation);
        route.expectedCommitments = _singleCommitment(commitment);
    }

    function _emptyRoute() internal pure returns (DelayedOrderTypes.DelayedOrderRoute memory route) {
        route.curveIds = new uint256[](0);
        route.expectedGenerations = new uint32[](0);
        route.expectedCommitments = new bytes32[](0);
    }

    function _sizedRoute(uint256 length) internal pure returns (DelayedOrderTypes.DelayedOrderRoute memory route) {
        route.curveIds = new uint256[](length);
        route.expectedGenerations = new uint32[](length);
        route.expectedCommitments = new bytes32[](length);
    }

    function _routes(DelayedOrderTypes.DelayedOrderRoute memory route)
        internal
        pure
        returns (DelayedOrderTypes.DelayedOrderRoute[] memory routes)
    {
        routes = new DelayedOrderTypes.DelayedOrderRoute[](1);
        routes[0] = route;
    }

    function _rollExecutable() internal {
        vm.roll(block.number + DELAY_BLOCKS);
    }

    function _baseCredit(address owner_, uint256 tokenId) internal view returns (uint128 amount) {
        amount = uint128(
            IDelayedOrderLifecycleFacet(address(diamond))
            .getBaseCredit(owner_, uint8(LibEveMarket.BookAssetType.ERC1155), address(conditionalTokens), tokenId)
            .withdrawable
        );
    }

    function _flatPacked(uint72 price) internal pure returns (uint256 packed) {
        packed = LibCurvePacking.pack(price, price, FLAT_DURATION, 0, 0, bytes32(0));
    }

    function _assertStoredFlatCurve(
        uint256 curveId,
        bytes32 marketId,
        bytes32 bookId,
        address expectedMaker,
        LibEveMarket.CurveSide expectedSide,
        uint128 remainingVolume,
        uint128 quoteEscrowRemaining
    ) internal view {
        CurveCLOBTypes.CurveInfo memory info = ICurveViewFacet(address(diamond)).getCurveInfo(curveId);
        assertEq(info.curveId, curveId);
        assertEq(info.marketId, marketId);
        assertEq(info.bookId, bookId);
        assertEq(info.maker, expectedMaker);
        assertTrue(info.isYesSide);
        assertEq(uint8(info.curveSide), uint8(expectedSide));
        assertTrue(info.active);
        assertEq(info.remainingVolume, remainingVolume);
        assertEq(info.quoteEscrowRemaining, quoteEscrowRemaining);
        assertEq(info.startPrice, HALF_PRICE);
        assertEq(info.endPrice, HALF_PRICE);
        assertEq(info.currentPrice, HALF_PRICE);
        assertEq(info.durationMinutes, FLAT_DURATION);
        assertEq(info.profileId, uint8(0));
    }

    function _assertCurveIndexes(bytes32 marketId, bytes32 bookId, uint256 curveId) internal view {
        IDelayedOrderFlatCurveHarnessFacet harness = IDelayedOrderFlatCurveHarnessFacet(address(diamond));
        assertEq(harness.bookCurveIdsLength(bookId), 1);
        assertEq(harness.bookCurveIdAt(bookId, 0), curveId);
        assertEq(harness.bookCurveCount(bookId), 1);
        assertEq(harness.marketCurveCount(marketId), 1);
    }

    function _fillSingleBookCurve(
        bytes32 bookId,
        uint256 curveId,
        uint128 quoteIn,
        uint128 baseOut,
        uint32 generation,
        bytes32 commitment
    ) internal returns (CurveCLOBTypes.FillBestResult memory result) {
        result = IBookTradeFacet(address(diamond))
            .fillBookBest(
                CurveCLOBTypes.FillBookParams({
                    bookId: bookId,
                    maxQuoteIn: quoteIn,
                    minBaseOut: baseOut,
                    maxAveragePrice: HALF_PRICE,
                    curveIds: _singleCurve(curveId),
                    expectedGenerations: _singleGeneration(generation),
                    expectedCommitments: _singleCommitment(commitment),
                    payer: taker,
                    receiver: taker
                })
            );
    }

    function _fillSingleBookCurveFor(
        address account,
        bytes32 bookId,
        uint256 curveId,
        uint128 quoteIn,
        uint128 baseOut,
        uint32 generation,
        bytes32 commitment
    ) internal returns (CurveCLOBTypes.FillBestResult memory result) {
        result = IBookTradeFacet(address(diamond))
            .fillBookBest(
                CurveCLOBTypes.FillBookParams({
                    bookId: bookId,
                    maxQuoteIn: quoteIn,
                    minBaseOut: baseOut,
                    maxAveragePrice: HALF_PRICE,
                    curveIds: _singleCurve(curveId),
                    expectedGenerations: _singleGeneration(generation),
                    expectedCommitments: _singleCommitment(commitment),
                    payer: account,
                    receiver: account
                })
            );
    }

    function _sellSingleBookCurve(
        bytes32 bookId,
        uint256 curveId,
        uint128 baseIn,
        uint32 generation,
        bytes32 commitment
    ) internal returns (CurveCLOBTypes.SellBookResult memory result) {
        result = IBookTradeFacet(address(diamond))
            .sellBookBest(
                CurveCLOBTypes.SellBookParams({
                    bookId: bookId,
                    maxBaseIn: baseIn,
                    minQuoteOut: QUOTE_ESCROW,
                    curveIds: _singleCurve(curveId),
                    expectedGenerations: _singleGeneration(generation),
                    expectedCommitments: _singleCommitment(commitment),
                    receiver: taker
                })
            );
    }

    function _expiry(uint256 duration) internal view returns (uint64) {
        return uint64(block.timestamp + duration);
    }

    function _splitFrom(address account, bytes32 marketId, uint128 amount) internal {
        vm.startPrank(account);
        usdc.approve(address(diamond), amount);
        ICurveInventoryFacet(address(diamond)).splitInventory(marketId, amount);
        vm.stopPrank();
    }

    function _singleCurve(uint256 curveId) internal pure returns (uint256[] memory curveIds) {
        curveIds = new uint256[](1);
        curveIds[0] = curveId;
    }

    function _singleGeneration(uint32 generation) internal pure returns (uint32[] memory generations) {
        generations = new uint32[](1);
        generations[0] = generation;
    }

    function _singleCommitment(bytes32 commitment) internal pure returns (bytes32[] memory commitments) {
        commitments = new bytes32[](1);
        commitments[0] = commitment;
    }

    function _bookSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = IBookAdminFacet.getBookInfo.selector;
    }

    function _bookTradeSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = IBookTradeFacet.sellBookBest.selector;
        selectors[1] = IBookTradeFacet.fillBookBest.selector;
        selectors[2] = IBookTradeFacet.fillBookBestFor.selector;
        selectors[3] = IBookTradeFacet.sellBookBestFor.selector;
    }

    function _curveInventorySelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = ICurveInventoryFacet.splitInventory.selector;
    }

    function _curveLifecycleSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = ICurveLifecycleFacet.cancelCurve.selector;
        selectors[1] = ICurveLifecycleFacet.updateCurve.selector;
    }

    function _curveViewSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = ICurveViewFacet.getCurveCommitment.selector;
        selectors[1] = ICurveViewFacet.getCurveInfo.selector;
    }

    function _flatCurveHarnessSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](6);
        selectors[0] = IDelayedOrderFlatCurveHarnessFacet.createFlatCurveFromEscrow.selector;
        selectors[1] = IDelayedOrderFlatCurveHarnessFacet.bookCurveIdsLength.selector;
        selectors[2] = IDelayedOrderFlatCurveHarnessFacet.bookCurveIdAt.selector;
        selectors[3] = IDelayedOrderFlatCurveHarnessFacet.bookCurveCount.selector;
        selectors[4] = IDelayedOrderFlatCurveHarnessFacet.marketCurveCount.selector;
        selectors[5] = IDelayedOrderFlatCurveHarnessFacet.setMarketPayoutUnit.selector;
    }

    function _delayedOrderSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](10);
        selectors[0] = IDelayedOrderLifecycleFacet.submitDelayedOrder.selector;
        selectors[1] = IDelayedOrderLifecycleFacet.processDelayedOrders.selector;
        selectors[2] = IDelayedOrderLifecycleFacet.getDelayedOrder.selector;
        selectors[3] = IDelayedOrderLifecycleFacet.getQuoteCredit.selector;
        selectors[4] = DelayedOrderFacet.getBaseCredit.selector;
        selectors[5] = IDelayedOrderLifecycleFacet.withdrawBaseCredit.selector;
        selectors[6] = IDelayedOrderLifecycleFacet.getBookQueue.selector;
        selectors[7] = IDelayedOrderLifecycleFacet.processDelayedOrdersFrom.selector;
        selectors[8] = IDelayedOrderLifecycleFacet.expireDelayedOrders.selector;
        selectors[9] = IDelayedOrderLifecycleFacet.getDelayedOrderHead.selector;
    }
}
