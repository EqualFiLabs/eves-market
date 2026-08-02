// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC1155} from "../../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";
import {BookFacet} from "../../src/facets/BookFacet.sol";
import {BookOrderFacet} from "../../src/facets/BookOrderFacet.sol";
import {BookTradeFacet} from "../../src/facets/BookTradeFacet.sol";
import {BookSellFacet} from "../../src/facets/BookSellFacet.sol";
import {CurveInventoryFacet} from "../../src/facets/CurveInventoryFacet.sol";
import {CurveLifecycleFacet} from "../../src/facets/CurveLifecycleFacet.sol";
import {CurveViewFacet} from "../../src/facets/CurveViewFacet.sol";
import {IBookAdminFacet} from "../../src/interfaces/IBookAdminFacet.sol";
import {IBookOrderFacet} from "../../src/interfaces/IBookOrderFacet.sol";
import {IBookTradeFacet} from "../../src/interfaces/IBookTradeFacet.sol";
import {ICurveInventoryFacet} from "../../src/interfaces/ICurveInventoryFacet.sol";
import {ICurveLifecycleFacet} from "../../src/interfaces/ICurveLifecycleFacet.sol";
import {ICurveViewFacet} from "../../src/interfaces/ICurveViewFacet.sol";
import {DelayedOrderFacet} from "../../src/facets/DelayedOrderFacet.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {LibCLOBBook} from "../../src/libraries/LibCLOBBook.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {CurveCLOBTypes} from "../../src/types/CurveCLOBTypes.sol";
import {DelayedOrderTypes} from "../../src/types/DelayedOrderTypes.sol";
import {ITestStateFacet, TestBase} from "../helpers/TestBase.sol";

interface IDelayedOrderProcessingFacet {
    function submitDelayedOrder(DelayedOrderTypes.SubmitDelayedOrderParams calldata params)
        external
        returns (uint256 orderId);
    function processDelayedOrders(
        bytes32 bookId,
        uint256 maxOrders,
        DelayedOrderTypes.DelayedOrderRoute[] calldata routes
    ) external returns (DelayedOrderTypes.ProcessDelayedOrderResult memory result);
    function getDelayedOrder(uint256 orderId) external view returns (DelayedOrderTypes.DelayedOrderView memory order);
    function getBookQueue(bytes32 bookId) external view returns (DelayedOrderTypes.BookQueueView memory queue);
    function getQuoteCredit(address owner, address token)
        external
        view
        returns (DelayedOrderTypes.CreditBalanceView memory credit);
    function getBaseCredit(address owner, uint8 assetType, address token, uint256 tokenId)
        external
        view
        returns (DelayedOrderTypes.CreditBalanceView memory credit);
}

contract DelayedOrderProcessingProperties is TestBase {
    uint64 internal constant DELAY_BLOCKS = 3;
    uint64 internal constant GRACE_BLOCKS = 10;
    uint24 internal constant RESTING_MINUTES = 120;
    uint72 internal constant HALF_PRICE = 500_000_000;
    uint72 internal constant LOW_PRICE = 400_000_000;
    uint72 internal constant HIGH_PRICE = 700_000_000;
    uint128 internal constant SHARES = 100e6;
    uint128 internal constant HALF_COST = 50e6;
    address internal processor;

    function setUp() public override {
        super.setUp();
        processor = makeAddr("processor");

        vm.startPrank(owner);
        diamond.registerFacet(address(new DelayedOrderFacet()), _delayedOrderSelectors());
        diamond.registerFacet(address(new BookFacet()), _bookSelectors());
        diamond.registerFacet(address(new BookOrderFacet()), _bookOrderSelectors());
        diamond.registerFacet(address(new BookTradeFacet()), _bookTradeSelectors());
        diamond.registerFacet(address(new BookSellFacet()), _bookSellSelectors());
        diamond.registerFacet(address(new CurveInventoryFacet()), _curveInventorySelectors());
        diamond.registerFacet(address(new CurveLifecycleFacet()), _curveLifecycleSelectors());
        diamond.registerFacet(address(new CurveViewFacet()), _curveViewSelectors());
        ITestStateFacet(address(diamond)).setDelayedOrderConfigFixture(DELAY_BLOCKS, GRACE_BLOCKS, RESTING_MINUTES);
        ITestStateFacet(address(diamond))
            .setDelayedOrderProcessingFixture(uint8(LibEveMarket.ProcessingMode.Permissionless), 0);
        vm.stopPrank();
    }

    // Feature: live-delayed-taker-order, Property 6: Processing stops at a not-yet-executable head.
    function test_ProcessingStopsAtNotYetExecutableHead() public {
        (bytes32 bookId, uint256 curveId) = _createBookWithAsk(HALF_PRICE, SHARES);
        uint256 orderId = _submitMarketBuy(bookId, HALF_COST, _route(curveId));

        DelayedOrderTypes.ProcessDelayedOrderResult memory result =
            IDelayedOrderProcessingFacet(address(diamond)).processDelayedOrders(bookId, 1, _routes(_route(curveId)));

        assertEq(result.processedCount, 0);
        assertEq(result.stoppedOrderId, orderId);
        DelayedOrderTypes.DelayedOrderView memory order =
            IDelayedOrderProcessingFacet(address(diamond)).getDelayedOrder(orderId);
        assertEq(uint8(order.status), uint8(LibEveMarket.DelayedOrderStatus.Pending));
        DelayedOrderTypes.BookQueueView memory queue =
            IDelayedOrderProcessingFacet(address(diamond)).getBookQueue(bookId);
        assertEq(queue.head, 0);
        assertEq(queue.tail, 1);
    }

    // Feature: live-delayed-taker-order, Property 7: FIFO processing by sequence with forward-only head.
    function test_FIFOProcessingBySequenceWithForwardOnlyHead() public {
        (bytes32 bookId, uint256 firstCurveId) = _createBookWithAsk(HALF_PRICE, SHARES);
        uint256 secondCurveId = _postAsk(bookId, HALF_PRICE, SHARES);
        uint256 firstOrderId = _submitMarketBuy(bookId, HALF_COST, _route(firstCurveId));
        uint256 secondOrderId = _submitMarketBuy(bookId, HALF_COST, _route(secondCurveId));
        _rollExecutable();

        DelayedOrderTypes.ProcessDelayedOrderResult memory result = IDelayedOrderProcessingFacet(address(diamond))
            .processDelayedOrders(bookId, 2, _routes(_route(firstCurveId), _route(secondCurveId)));

        assertEq(result.processedCount, 2);
        assertEq(
            uint8(IDelayedOrderProcessingFacet(address(diamond)).getDelayedOrder(firstOrderId).status),
            uint8(LibEveMarket.DelayedOrderStatus.Filled)
        );
        assertEq(
            uint8(IDelayedOrderProcessingFacet(address(diamond)).getDelayedOrder(secondOrderId).status),
            uint8(LibEveMarket.DelayedOrderStatus.Filled)
        );
        DelayedOrderTypes.BookQueueView memory queue =
            IDelayedOrderProcessingFacet(address(diamond)).getBookQueue(bookId);
        assertEq(queue.head, 2);
        assertEq(queue.tail, 2);
    }

    // Feature: live-delayed-taker-order, Property 8: Bounded processing.
    function test_BoundedProcessing() public {
        (bytes32 bookId, uint256 firstCurveId) = _createBookWithAsk(HALF_PRICE, SHARES);
        uint256 secondCurveId = _postAsk(bookId, HALF_PRICE, SHARES);
        _submitMarketBuy(bookId, HALF_COST, _route(firstCurveId));
        uint256 secondOrderId = _submitMarketBuy(bookId, HALF_COST, _route(secondCurveId));
        _rollExecutable();

        DelayedOrderTypes.ProcessDelayedOrderResult memory result = IDelayedOrderProcessingFacet(address(diamond))
            .processDelayedOrders(bookId, 1, _routes(_route(firstCurveId), _route(secondCurveId)));

        assertEq(result.processedCount, 1);
        DelayedOrderTypes.BookQueueView memory queue =
            IDelayedOrderProcessingFacet(address(diamond)).getBookQueue(bookId);
        assertEq(queue.head, 1);
        assertEq(
            uint8(IDelayedOrderProcessingFacet(address(diamond)).getDelayedOrder(secondOrderId).status),
            uint8(LibEveMarket.DelayedOrderStatus.Pending)
        );
    }

    // Feature: live-delayed-taker-order, Property 9: Route-hash gate.
    function test_RouteHashGate() public {
        (bytes32 bookId, uint256 curveId) = _createBookWithAsk(HALF_PRICE, SHARES);
        uint256 orderId = _submitMarketBuy(bookId, HALF_COST, _route(curveId));
        _rollExecutable();
        DelayedOrderTypes.DelayedOrderRoute memory badRoute = _route(curveId);
        badRoute.expectedGenerations[0] += 1;
        DelayedOrderTypes.DelayedOrderRoute[] memory badRoutes = _routes(badRoute);

        vm.expectRevert();
        IDelayedOrderProcessingFacet(address(diamond)).processDelayedOrders(bookId, 1, badRoutes);

        assertEq(
            uint8(IDelayedOrderProcessingFacet(address(diamond)).getDelayedOrder(orderId).status),
            uint8(LibEveMarket.DelayedOrderStatus.Pending)
        );
    }

    // Feature: live-delayed-taker-order, Property 10: No head-of-line blocking and no non-head bypass.
    function test_NoHeadOfLineBlockingAndNoNonHeadBypass() public {
        (bytes32 bookId, uint256 staleCurveId) = _createBookWithAsk(HALF_PRICE, SHARES);
        uint256 validCurveId = _postAsk(bookId, HALF_PRICE, SHARES);
        uint256 firstOrderId = _submitMarketBuy(bookId, HALF_COST, _route(staleCurveId));
        uint256 secondOrderId = _submitMarketBuy(bookId, HALF_COST, _route(validCurveId));
        _deactivateCurve(staleCurveId);
        _rollExecutable();
        DelayedOrderTypes.DelayedOrderRoute[] memory nonHeadRoutes = _routes(_route(validCurveId));

        vm.expectRevert();
        IDelayedOrderProcessingFacet(address(diamond)).processDelayedOrders(bookId, 1, nonHeadRoutes);

        DelayedOrderTypes.ProcessDelayedOrderResult memory result = IDelayedOrderProcessingFacet(address(diamond))
            .processDelayedOrders(bookId, 2, _routes(_route(staleCurveId), _route(validCurveId)));

        assertEq(result.processedCount, 2);
        assertEq(
            uint8(IDelayedOrderProcessingFacet(address(diamond)).getDelayedOrder(firstOrderId).status),
            uint8(LibEveMarket.DelayedOrderStatus.Cancelled)
        );
        assertEq(
            uint8(IDelayedOrderProcessingFacet(address(diamond)).getDelayedOrder(secondOrderId).status),
            uint8(LibEveMarket.DelayedOrderStatus.Filled)
        );
    }

    // Feature: live-delayed-taker-order, Property 34: Processing mode gates processor access.
    function test_ProcessingModeGatesProcessorAccess() public {
        (bytes32 bookId, uint256 curveId) = _createBookWithAsk(HALF_PRICE, SHARES);
        _submitMarketBuy(bookId, HALF_COST, _route(curveId));
        _rollExecutable();

        vm.prank(owner);
        ITestStateFacet(address(diamond))
            .setDelayedOrderProcessingFixture(uint8(LibEveMarket.ProcessingMode.ProtocolOnly), 0);
        DelayedOrderTypes.DelayedOrderRoute[] memory routes = _routes(_route(curveId));

        vm.prank(processor);
        vm.expectRevert(abi.encodeWithSelector(Errors.DelayedOrderProcessorNotAllowed.selector, processor));
        IDelayedOrderProcessingFacet(address(diamond)).processDelayedOrders(bookId, 1, routes);

        vm.prank(owner);
        ITestStateFacet(address(diamond)).setDelayedOrderProtocolProcessorFixture(processor, true);
        vm.prank(processor);
        IDelayedOrderProcessingFacet(address(diamond)).processDelayedOrders(bookId, 1, routes);
    }

    // Feature: live-delayed-taker-order, Property 11: Market buy executes and credits unspent quote.
    function test_MarketBuyExecutesAndCreditsUnspentQuote() public {
        (bytes32 bookId, uint256 curveId) = _createBookWithAsk(HALF_PRICE, SHARES);
        uint256 orderId = _submitMarketBuy(bookId, 2 * HALF_COST, _route(curveId));
        _rollExecutable();

        IDelayedOrderProcessingFacet(address(diamond)).processDelayedOrders(bookId, 1, _routes(_route(curveId)));

        DelayedOrderTypes.DelayedOrderView memory order =
            IDelayedOrderProcessingFacet(address(diamond)).getDelayedOrder(orderId);
        assertEq(uint8(order.status), uint8(LibEveMarket.DelayedOrderStatus.PartiallyFilled));
        assertEq(conditionalTokens.balanceOf(taker, _yesPositionId(bookId)), SHARES);
        assertEq(
            IDelayedOrderProcessingFacet(address(diamond)).getQuoteCredit(taker, address(usdc)).withdrawable, HALF_COST
        );
    }

    // Feature: live-delayed-taker-order, Property 13: Market orders never rest.
    function test_MarketOrdersNeverRest() public {
        (bytes32 bookId, uint256 curveId) = _createBookWithAsk(HALF_PRICE, SHARES);
        uint256 orderId = _submitMarketBuy(bookId, HALF_COST, _route(curveId));
        _deactivateCurve(curveId);
        _rollExecutable();

        IDelayedOrderProcessingFacet(address(diamond)).processDelayedOrders(bookId, 1, _routes(_route(curveId)));

        DelayedOrderTypes.DelayedOrderView memory order =
            IDelayedOrderProcessingFacet(address(diamond)).getDelayedOrder(orderId);
        assertEq(uint8(order.status), uint8(LibEveMarket.DelayedOrderStatus.Cancelled));
        assertEq(order.restingCurveId, 0);
    }

    // Feature: live-delayed-taker-order, Property 14: Limit buy fills only at or below the limit price.
    function test_LimitBuyFillsOnlyAtOrBelowLimitPrice() public {
        (bytes32 bookId, uint256 expensiveCurveId) = _createBookWithAsk(HIGH_PRICE, SHARES);
        uint256 cheapCurveId = _postAsk(bookId, LOW_PRICE, SHARES);
        uint256 orderId = _submitLimitBuy(bookId, HALF_COST, HALF_PRICE, _route(expensiveCurveId, cheapCurveId));
        _rollExecutable();

        IDelayedOrderProcessingFacet(address(diamond))
            .processDelayedOrders(bookId, 1, _routes(_route(expensiveCurveId, cheapCurveId)));

        DelayedOrderTypes.DelayedOrderView memory order =
            IDelayedOrderProcessingFacet(address(diamond)).getDelayedOrder(orderId);
        assertEq(uint8(order.status), uint8(LibEveMarket.DelayedOrderStatus.Resting));
        assertEq(conditionalTokens.balanceOf(taker, _yesPositionId(bookId)), SHARES);
        CurveCLOBTypes.CurveInfo memory expensive = ICurveViewFacet(address(diamond)).getCurveInfo(expensiveCurveId);
        assertEq(expensive.remainingVolume, SHARES);
    }

    // Feature: live-delayed-taker-order, Property 15: Limit buy remainder rests as owner-owned flat BID at the limit.
    function test_LimitBuyRemainderRestsAsOwnerOwnedFlatBid() public {
        (bytes32 bookId, uint256 curveId) = _createBookWithAsk(HALF_PRICE, SHARES / 2);
        uint256 orderId = _submitLimitBuy(bookId, HALF_COST, HALF_PRICE, _route(curveId));
        _rollExecutable();

        IDelayedOrderProcessingFacet(address(diamond)).processDelayedOrders(bookId, 1, _routes(_route(curveId)));

        DelayedOrderTypes.DelayedOrderView memory order =
            IDelayedOrderProcessingFacet(address(diamond)).getDelayedOrder(orderId);
        assertEq(uint8(order.status), uint8(LibEveMarket.DelayedOrderStatus.Resting));
        CurveCLOBTypes.CurveInfo memory resting = ICurveViewFacet(address(diamond)).getCurveInfo(order.restingCurveId);
        assertEq(resting.maker, taker);
        assertEq(resting.bookId, bookId);
        assertEq(uint8(resting.curveSide), uint8(LibEveMarket.CurveSide.BID));
        assertEq(resting.startPrice, HALF_PRICE);
        assertEq(resting.endPrice, HALF_PRICE);
    }

    // Feature: live-delayed-taker-order, Property 35: Processor reward is paid only from realized buy-side fees.
    function test_ProcessorRewardIsPaidOnlyFromRealizedBuySideFees() public {
        vm.prank(owner);
        ITestStateFacet(address(diamond)).setOrderbookFeeConfigFixture(1_000, 8_000, 500, 1_500, 0);
        vm.prank(owner);
        ITestStateFacet(address(diamond))
            .setDelayedOrderProcessingFixture(uint8(LibEveMarket.ProcessingMode.Permissionless), 2_000);
        (bytes32 bookId, uint256 curveId) = _createBookWithAsk(HALF_PRICE, SHARES);
        uint256 missCurveId = _postAsk(bookId, HALF_PRICE, SHARES);
        _submitMarketBuy(bookId, 55e6, _route(curveId));
        _submitMarketBuy(bookId, 55e6, _route(missCurveId));
        _deactivateCurve(missCurveId);
        _rollExecutable();

        uint256 processorBefore = usdc.balanceOf(processor);
        DelayedOrderTypes.DelayedOrderRoute[] memory routes = _routes(_route(curveId), _route(missCurveId));
        vm.prank(processor);
        IDelayedOrderProcessingFacet(address(diamond)).processDelayedOrders(bookId, 2, routes);

        assertEq(usdc.balanceOf(processor), processorBefore + 1e6);
    }

    // Feature: live-delayed-taker-order, Property 16: Market sell executes and credits unsold base.
    function test_MarketSellExecutesAndCreditsUnsoldBase() public {
        (bytes32 bookId, uint256 curveId) = _createBookWithBid(HALF_PRICE, SHARES);
        _splitToTaker(_marketIdForBook(bookId), 2 * SHARES);
        uint256 orderId = _submitMarketSell(bookId, 2 * SHARES, _route(curveId));
        _rollExecutable();

        IDelayedOrderProcessingFacet(address(diamond)).processDelayedOrders(bookId, 1, _routes(_route(curveId)));

        DelayedOrderTypes.DelayedOrderView memory order =
            IDelayedOrderProcessingFacet(address(diamond)).getDelayedOrder(orderId);
        assertEq(uint8(order.status), uint8(LibEveMarket.DelayedOrderStatus.PartiallyFilled));
        assertEq(conditionalTokens.balanceOf(maker, _yesPositionId(bookId)), SHARES);
        assertEq(_baseCredit(taker, _yesPositionId(bookId)), SHARES);
    }

    // Feature: live-delayed-taker-order, Property 17: Limit sell fills only at or above the limit price.
    function test_LimitSellFillsOnlyAtOrAboveLimitPrice() public {
        (bytes32 bookId, uint256 lowCurveId) = _createBookWithBid(LOW_PRICE, SHARES);
        uint256 highCurveId = _postBid(bookId, HIGH_PRICE, SHARES);
        _splitToTaker(_marketIdForBook(bookId), SHARES);
        uint256 orderId = _submitLimitSell(bookId, SHARES, HALF_PRICE, _route(lowCurveId, highCurveId));
        _rollExecutable();

        IDelayedOrderProcessingFacet(address(diamond))
            .processDelayedOrders(bookId, 1, _routes(_route(lowCurveId, highCurveId)));

        DelayedOrderTypes.DelayedOrderView memory order =
            IDelayedOrderProcessingFacet(address(diamond)).getDelayedOrder(orderId);
        assertEq(uint8(order.status), uint8(LibEveMarket.DelayedOrderStatus.Filled));
        CurveCLOBTypes.CurveInfo memory low = ICurveViewFacet(address(diamond)).getCurveInfo(lowCurveId);
        CurveCLOBTypes.CurveInfo memory high = ICurveViewFacet(address(diamond)).getCurveInfo(highCurveId);
        assertEq(low.remainingVolume, SHARES);
        assertEq(high.remainingVolume, 0);
    }

    // Feature: live-delayed-taker-order, Property 18: Limit sell remainder rests as owner-owned flat ASK.
    function test_LimitSellRemainderRestsAsOwnerOwnedFlatAsk() public {
        (bytes32 bookId, uint256 curveId) = _createBookWithBid(HALF_PRICE, SHARES / 2);
        _splitToTaker(_marketIdForBook(bookId), SHARES);
        uint256 orderId = _submitLimitSell(bookId, SHARES, HALF_PRICE, _route(curveId));
        _rollExecutable();

        IDelayedOrderProcessingFacet(address(diamond)).processDelayedOrders(bookId, 1, _routes(_route(curveId)));

        DelayedOrderTypes.DelayedOrderView memory order =
            IDelayedOrderProcessingFacet(address(diamond)).getDelayedOrder(orderId);
        assertEq(uint8(order.status), uint8(LibEveMarket.DelayedOrderStatus.Resting));
        CurveCLOBTypes.CurveInfo memory resting = ICurveViewFacet(address(diamond)).getCurveInfo(order.restingCurveId);
        assertEq(resting.maker, taker);
        assertEq(resting.bookId, bookId);
        assertEq(uint8(resting.curveSide), uint8(LibEveMarket.CurveSide.ASK));
        assertEq(resting.remainingVolume, SHARES / 2);
        assertEq(resting.quoteEscrowRemaining, 0);
        assertEq(resting.startPrice, HALF_PRICE);
        assertEq(resting.endPrice, HALF_PRICE);
    }

    // Feature: live-delayed-taker-order, Property 28: Delayed sells never pull base from the processor.
    function test_DelayedSellsNeverPullBaseFromProcessor() public {
        (bytes32 bookId, uint256 curveId) = _createBookWithBid(HALF_PRICE, SHARES);
        _splitToTaker(_marketIdForBook(bookId), SHARES);
        _submitMarketSell(bookId, SHARES, _route(curveId));
        _rollExecutable();

        uint256 processorBaseBefore = conditionalTokens.balanceOf(processor, _yesPositionId(bookId));
        vm.prank(processor);
        IDelayedOrderProcessingFacet(address(diamond)).processDelayedOrders(bookId, 1, _routes(_route(curveId)));

        assertEq(conditionalTokens.balanceOf(processor, _yesPositionId(bookId)), processorBaseBefore);
        assertEq(conditionalTokens.balanceOf(maker, _yesPositionId(bookId)), SHARES);
    }

    // Feature: live-delayed-taker-order, Property 29: Expiry finalizes, credits full escrow, and never rests.
    function test_ExpiryFinalizesCreditsFullEscrowAndNeverRests() public {
        (bytes32 bookId,) = _createBookWithBid(HALF_PRICE, SHARES);
        _splitToTaker(_marketIdForBook(bookId), SHARES);
        uint256 orderId = _submitMarketSell(bookId, SHARES, _emptyRoute());
        vm.roll(block.number + DELAY_BLOCKS + GRACE_BLOCKS + 1);

        IDelayedOrderProcessingFacet(address(diamond))
            .processDelayedOrders(bookId, 1, new DelayedOrderTypes.DelayedOrderRoute[](0));

        DelayedOrderTypes.DelayedOrderView memory order =
            IDelayedOrderProcessingFacet(address(diamond)).getDelayedOrder(orderId);
        assertEq(uint8(order.status), uint8(LibEveMarket.DelayedOrderStatus.Expired));
        assertEq(order.restingCurveId, 0);
        assertEq(_baseCredit(taker, _yesPositionId(bookId)), SHARES);
    }

    // Feature: live-delayed-taker-order, Property 36: Processor reward is paid only from realized sell-side fees.
    function test_ProcessorRewardIsPaidOnlyFromRealizedSellSideFees() public {
        vm.prank(owner);
        ITestStateFacet(address(diamond)).setOrderbookFeeConfigFixture(1_000, 8_000, 500, 1_500, 0);
        vm.prank(owner);
        ITestStateFacet(address(diamond))
            .setDelayedOrderProcessingFixture(uint8(LibEveMarket.ProcessingMode.Permissionless), 2_000);
        (bytes32 bookId, uint256 curveId) = _createBookWithBid(HALF_PRICE, SHARES);
        uint256 missCurveId = _postBid(bookId, HALF_PRICE, SHARES);
        _splitToTaker(_marketIdForBook(bookId), 2 * SHARES);
        _submitMarketSell(bookId, SHARES, _route(curveId));
        _submitMarketSell(bookId, SHARES, _route(missCurveId));
        _deactivateCurve(missCurveId);
        _rollExecutable();

        uint256 processorBefore = usdc.balanceOf(processor);
        DelayedOrderTypes.DelayedOrderRoute[] memory routes = _routes(_route(curveId), _route(missCurveId));
        vm.prank(processor);
        IDelayedOrderProcessingFacet(address(diamond)).processDelayedOrders(bookId, 2, routes);

        assertEq(usdc.balanceOf(processor), processorBefore + 1e6);
    }

    // Feature: live-delayed-taker-order, Property 12: Market order miss credits remaining escrow.
    function test_MarketSellMissAfterValidLiquidityExhaustedCancelsAndCreditsRemainingEscrow() public {
        (bytes32 bookId, uint256 curveId) = _createBookWithBid(HALF_PRICE, SHARES);
        _splitToTaker(_marketIdForBook(bookId), SHARES);
        uint256 orderId = _submitMarketSell(bookId, SHARES, _route(curveId));
        _deactivateCurve(curveId);
        _rollExecutable();

        IDelayedOrderProcessingFacet(address(diamond)).processDelayedOrders(bookId, 1, _routes(_route(curveId)));

        DelayedOrderTypes.DelayedOrderView memory order =
            IDelayedOrderProcessingFacet(address(diamond)).getDelayedOrder(orderId);
        assertEq(uint8(order.status), uint8(LibEveMarket.DelayedOrderStatus.Cancelled));
        assertEq(_baseCredit(taker, _yesPositionId(bookId)), SHARES);
    }

    // Feature: live-delayed-taker-order, Property 30: Expected misses produce terminal outcomes without reverting.
    function test_ExpectedMissesProduceTerminalOutcomesWithoutRevertingBatch() public {
        (bytes32 bookId, uint256 missCurveId) = _createBookWithBid(HALF_PRICE, SHARES);
        uint256 fillCurveId = _postBid(bookId, HALF_PRICE, SHARES);
        _splitToTaker(_marketIdForBook(bookId), 2 * SHARES);
        uint256 missOrderId = _submitMarketSell(bookId, SHARES, _route(missCurveId));
        uint256 fillOrderId = _submitMarketSell(bookId, SHARES, _route(fillCurveId));
        _deactivateCurve(missCurveId);
        _rollExecutable();

        DelayedOrderTypes.ProcessDelayedOrderResult memory result = IDelayedOrderProcessingFacet(address(diamond))
            .processDelayedOrders(bookId, 2, _routes(_route(missCurveId), _route(fillCurveId)));

        assertEq(result.processedCount, 2);
        assertEq(
            uint8(IDelayedOrderProcessingFacet(address(diamond)).getDelayedOrder(missOrderId).status),
            uint8(LibEveMarket.DelayedOrderStatus.Cancelled)
        );
        assertEq(
            uint8(IDelayedOrderProcessingFacet(address(diamond)).getDelayedOrder(fillOrderId).status),
            uint8(LibEveMarket.DelayedOrderStatus.Filled)
        );
    }

    // Feature: live-delayed-taker-order, Property 32: Limit remainder rests XOR credits, never both.
    function test_LimitSellRemainderRestsXorCreditsNeverBoth() public {
        (bytes32 bookId, uint256 curveId) = _createBookWithBid(HALF_PRICE, SHARES / 2);
        _splitToTaker(_marketIdForBook(bookId), SHARES);
        uint256 orderId = _submitLimitSell(bookId, SHARES, HALF_PRICE, _route(curveId));
        _rollExecutable();

        IDelayedOrderProcessingFacet(address(diamond)).processDelayedOrders(bookId, 1, _routes(_route(curveId)));

        DelayedOrderTypes.DelayedOrderView memory order =
            IDelayedOrderProcessingFacet(address(diamond)).getDelayedOrder(orderId);
        assertTrue(order.restingCurveId != 0);
        assertEq(_baseCredit(taker, _yesPositionId(bookId)), 0);
    }

    function _createBookWithAsk(uint72 price, uint128 volume) internal returns (bytes32 bookId, uint256 curveId) {
        bytes32 marketId;
        (marketId,) = _createMarketFixture("Delayed processing market", uint64(block.timestamp + 7 days));
        ITestStateFacet(address(diamond)).materializeMarketSideBookFixture(marketId, true);
        bookId = LibCLOBBook.marketBookId(marketId, true);
        curveId = _postAsk(bookId, price, volume);
    }

    function _createBookWithBid(uint72 price, uint128 volume) internal returns (bytes32 bookId, uint256 curveId) {
        bytes32 marketId;
        (marketId,) = _createMarketFixture("Delayed sell processing market", uint64(block.timestamp + 7 days));
        ITestStateFacet(address(diamond)).materializeMarketSideBookFixture(marketId, true);
        bookId = LibCLOBBook.marketBookId(marketId, true);
        curveId = _postBid(bookId, price, volume);
    }

    function _postAsk(bytes32 bookId, uint72 price, uint128 volume) internal returns (uint256 curveId) {
        bytes32 marketId = _marketIdForBook(bookId);
        vm.startPrank(maker);
        usdc.approve(address(diamond), volume);
        ICurveInventoryFacet(address(diamond)).splitInventory(marketId, volume);
        IERC1155(address(conditionalTokens)).setApprovalForAll(address(diamond), true);
        curveId = IBookOrderFacet(address(diamond))
            .postBookCurve(bookId, LibEveMarket.CurveSide.ASK, volume, price, price, 180, 0, type(uint8).max);
        vm.stopPrank();
    }

    function _postBid(bytes32 bookId, uint72 price, uint128 volume) internal returns (uint256 curveId) {
        uint128 quoteEscrow = _quoteFor(price, volume);
        vm.startPrank(maker);
        usdc.approve(address(diamond), quoteEscrow);
        curveId = IBookOrderFacet(address(diamond))
            .postBookCurve(bookId, LibEveMarket.CurveSide.BID, volume, price, price, 180, 0, type(uint8).max);
        vm.stopPrank();
    }

    function _splitToTaker(bytes32 marketId, uint128 amount) internal {
        vm.startPrank(taker);
        usdc.approve(address(diamond), amount);
        ICurveInventoryFacet(address(diamond)).splitInventory(marketId, amount);
        vm.stopPrank();
    }

    function _submitMarketBuy(bytes32 bookId, uint128 amountIn, DelayedOrderTypes.DelayedOrderRoute memory route)
        internal
        returns (uint256 orderId)
    {
        DelayedOrderTypes.SubmitDelayedOrderParams memory params = _submitParams(bookId, amountIn, route);
        params.kind = LibEveMarket.DelayedOrderKind.MarketBuy;
        vm.startPrank(taker);
        usdc.approve(address(diamond), amountIn);
        orderId = IDelayedOrderProcessingFacet(address(diamond)).submitDelayedOrder(params);
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
        orderId = IDelayedOrderProcessingFacet(address(diamond)).submitDelayedOrder(params);
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
        orderId = IDelayedOrderProcessingFacet(address(diamond)).submitDelayedOrder(params);
        vm.stopPrank();
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
        orderId = IDelayedOrderProcessingFacet(address(diamond)).submitDelayedOrder(params);
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

    function _route(uint256 curveId) internal view returns (DelayedOrderTypes.DelayedOrderRoute memory route) {
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        route.curveIds = new uint256[](1);
        route.expectedGenerations = new uint32[](1);
        route.expectedCommitments = new bytes32[](1);
        route.curveIds[0] = curveId;
        route.expectedGenerations[0] = generation;
        route.expectedCommitments[0] = commitment;
    }

    function _route(uint256 firstCurveId, uint256 secondCurveId)
        internal
        view
        returns (DelayedOrderTypes.DelayedOrderRoute memory route)
    {
        (uint32 firstGeneration, bytes32 firstCommitment) =
            ICurveViewFacet(address(diamond)).getCurveCommitment(firstCurveId);
        (uint32 secondGeneration, bytes32 secondCommitment) =
            ICurveViewFacet(address(diamond)).getCurveCommitment(secondCurveId);
        route.curveIds = new uint256[](2);
        route.expectedGenerations = new uint32[](2);
        route.expectedCommitments = new bytes32[](2);
        route.curveIds[0] = firstCurveId;
        route.curveIds[1] = secondCurveId;
        route.expectedGenerations[0] = firstGeneration;
        route.expectedGenerations[1] = secondGeneration;
        route.expectedCommitments[0] = firstCommitment;
        route.expectedCommitments[1] = secondCommitment;
    }

    function _emptyRoute() internal pure returns (DelayedOrderTypes.DelayedOrderRoute memory route) {
        route.curveIds = new uint256[](0);
        route.expectedGenerations = new uint32[](0);
        route.expectedCommitments = new bytes32[](0);
    }

    function _routes(DelayedOrderTypes.DelayedOrderRoute memory first)
        internal
        pure
        returns (DelayedOrderTypes.DelayedOrderRoute[] memory routes)
    {
        routes = new DelayedOrderTypes.DelayedOrderRoute[](1);
        routes[0] = first;
    }

    function _routes(
        DelayedOrderTypes.DelayedOrderRoute memory first,
        DelayedOrderTypes.DelayedOrderRoute memory second
    ) internal pure returns (DelayedOrderTypes.DelayedOrderRoute[] memory routes) {
        routes = new DelayedOrderTypes.DelayedOrderRoute[](2);
        routes[0] = first;
        routes[1] = second;
    }

    function _rollExecutable() internal {
        vm.roll(block.number + DELAY_BLOCKS);
    }

    function _deactivateCurve(uint256 curveId) internal {
        vm.prank(maker);
        ICurveLifecycleFacet(address(diamond)).cancelCurve(curveId);
    }

    function _marketIdForBook(bytes32 bookId) internal view returns (bytes32 marketId) {
        CurveCLOBTypes.BookInfo memory info = _bookInfo(bookId);
        marketId = info.marketId;
    }

    function _yesPositionId(bytes32 bookId) internal view returns (uint256 positionId) {
        bytes32 marketId = _bookInfo(bookId).marketId;
        (,,,, positionId,) = ITestStateFacet(address(diamond)).getStoredMarketCore(marketId);
    }

    function _baseCredit(address owner_, uint256 tokenId) internal view returns (uint128 amount) {
        amount = uint128(
            IDelayedOrderProcessingFacet(address(diamond))
            .getBaseCredit(owner_, uint8(LibEveMarket.BookAssetType.ERC1155), address(conditionalTokens), tokenId)
            .withdrawable
        );
    }

    function _quoteFor(uint72 price, uint128 volume) internal pure returns (uint128 quote) {
        quote = uint128((uint256(price) * uint256(volume)) / 1e9);
    }

    function _bookInfo(bytes32 bookId) internal view returns (CurveCLOBTypes.BookInfo memory info) {
        info = IBookAdminFacet(address(diamond)).getBookInfo(bookId);
    }

    function _delayedOrderSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](6);
        selectors[0] = IDelayedOrderProcessingFacet.submitDelayedOrder.selector;
        selectors[1] = IDelayedOrderProcessingFacet.processDelayedOrders.selector;
        selectors[2] = IDelayedOrderProcessingFacet.getDelayedOrder.selector;
        selectors[3] = IDelayedOrderProcessingFacet.getBookQueue.selector;
        selectors[4] = IDelayedOrderProcessingFacet.getQuoteCredit.selector;
        selectors[5] = DelayedOrderFacet.getBaseCredit.selector;
    }

    function _bookSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = IBookAdminFacet.getBookInfo.selector;
    }

    function _bookOrderSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = IBookOrderFacet.postBookCurve.selector;
    }

    function _bookTradeSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = IBookTradeFacet.fillBookBestFor.selector;
    }

    function _bookSellSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = IBookTradeFacet.sellBookBestFor.selector;
    }

    function _curveInventorySelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = ICurveInventoryFacet.splitInventory.selector;
    }

    function _curveLifecycleSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = ICurveLifecycleFacet.cancelCurve.selector;
    }

    function _curveViewSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = ICurveViewFacet.getCurveCommitment.selector;
        selectors[1] = ICurveViewFacet.getCurveInfo.selector;
    }
}
