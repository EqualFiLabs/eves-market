// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/// forge-config: default.invariant.runs = 12
/// forge-config: default.invariant.depth = 24

import {StdInvariant} from "../../lib/forge-std/src/StdInvariant.sol";
import {Test} from "../../lib/forge-std/src/Test.sol";
import {IERC1155} from "../../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";

import {BookFacet} from "../../src/facets/BookFacet.sol";
import {BookOrderFacet} from "../../src/facets/BookOrderFacet.sol";
import {BookTradeFacet} from "../../src/facets/BookTradeFacet.sol";
import {BookSellFacet} from "../../src/facets/BookSellFacet.sol";
import {CurveInventoryFacet} from "../../src/facets/CurveInventoryFacet.sol";
import {CurveLifecycleFacet} from "../../src/facets/CurveLifecycleFacet.sol";
import {CurveViewFacet} from "../../src/facets/CurveViewFacet.sol";
import {DelayedOrderFacet} from "../../src/facets/DelayedOrderFacet.sol";
import {IBookAdminFacet} from "../../src/interfaces/IBookAdminFacet.sol";
import {IBookOrderFacet} from "../../src/interfaces/IBookOrderFacet.sol";
import {IBookTradeFacet} from "../../src/interfaces/IBookTradeFacet.sol";
import {ICurveInventoryFacet} from "../../src/interfaces/ICurveInventoryFacet.sol";
import {ICurveLifecycleFacet} from "../../src/interfaces/ICurveLifecycleFacet.sol";
import {ICurveViewFacet} from "../../src/interfaces/ICurveViewFacet.sol";
import {LibCLOBBook} from "../../src/libraries/LibCLOBBook.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {CurveCLOBTypes} from "../../src/types/CurveCLOBTypes.sol";
import {DelayedOrderTypes} from "../../src/types/DelayedOrderTypes.sol";
import {ITestStateFacet, TestBase} from "../helpers/TestBase.sol";
import {MockConditionalTokens} from "../helpers/MockConditionalTokens.sol";
import {MockUSDC} from "../helpers/MockUSDC.sol";

interface IDelayedOrderInvariantFacet {
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
    function withdrawQuoteCredit(address token, uint128 amount) external;
    function getBaseCredit(address owner, uint8 assetType, address token, uint256 tokenId)
        external
        view
        returns (DelayedOrderTypes.CreditBalanceView memory credit);
    function withdrawBaseCredit(uint8 assetType, address token, uint256 tokenId, uint128 amount) external;
}

contract DelayedOrderInvariantHandler is TestBase {
    uint72 internal constant HALF_PRICE = 500_000_000;
    uint72 internal constant LOW_PRICE = 400_000_000;
    uint72 internal constant HIGH_PRICE = 700_000_000;
    uint64 internal constant DELAY_BLOCKS = 3;
    uint64 internal constant GRACE_BLOCKS = 8;
    uint24 internal constant RESTING_MINUTES = 120;
    uint128 internal constant BASE_UNIT = 10e6;
    uint128 internal constant QUOTE_UNIT = 5e6;

    struct RouteSnapshot {
        uint256 curveId;
        uint32 generation;
        bytes32 commitment;
    }

    bytes32 public marketId;
    bytes32 public bookId;
    uint256 public yesPositionId;
    uint256 public noPositionId;
    uint256 public initialUsdcSupply;
    uint64 public lastRecordedHead;

    address[] internal actors;
    address internal processor;
    uint256[] internal orderIds;
    uint8[] internal lastTerminalStatus;
    mapping(uint256 orderId => RouteSnapshot route) internal orderRoute;
    uint256[] internal askCurveIds;
    uint256[] internal bidCurveIds;

    function setUp() public override {
        super.setUp();

        processor = makeAddr("delayed-invariant-processor");
        actors.push(maker);
        actors.push(taker);
        actors.push(makeAddr("delayed-invariant-alice"));
        actors.push(makeAddr("delayed-invariant-bob"));

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
            .setDelayedOrderProcessingFixture(uint8(LibEveMarket.ProcessingMode.Permissionless), 1_000);
        vm.stopPrank();

        (marketId,) = _createMarketFixture("Delayed invariant market", uint64(block.timestamp + 7 days));
        ITestStateFacet(address(diamond)).materializeMarketSideBookFixture(marketId, true);
        bookId = LibCLOBBook.marketBookId(marketId, true);
        (,,,, yesPositionId, noPositionId) = ITestStateFacet(address(diamond)).getStoredMarketCore(marketId);

        for (uint256 index; index < actors.length; ++index) {
            usdc.mint(actors[index], 2_000_000e6);
            vm.startPrank(actors[index]);
            usdc.approve(address(diamond), type(uint256).max);
            conditionalTokens.setApprovalForAll(address(diamond), true);
            vm.stopPrank();
        }

        _seedAsk(HALF_PRICE, 20 * BASE_UNIT);
        _seedAsk(HIGH_PRICE, 20 * BASE_UNIT);
        _seedBid(HALF_PRICE, 20 * BASE_UNIT);
        _seedBid(LOW_PRICE, 20 * BASE_UNIT);
        initialUsdcSupply = usdc.totalSupply();
        _recordHead();
    }

    function submitBuy(uint256 actorSeed, uint256 curveSeed, bool limitOrder, uint128 amountSeed) external {
        if (askCurveIds.length == 0) {
            return;
        }

        address actor = _actor(actorSeed);
        uint256 maxAmount = _min(usdc.balanceOf(actor), 4 * QUOTE_UNIT);
        if (maxAmount < QUOTE_UNIT) {
            return;
        }

        uint128 amount = uint128(bound(uint256(amountSeed), QUOTE_UNIT, maxAmount));
        DelayedOrderTypes.DelayedOrderRoute memory route = _route(askCurveIds[curveSeed % askCurveIds.length]);
        DelayedOrderTypes.SubmitDelayedOrderParams memory params = _submitParams(route, amount);
        params.kind = limitOrder ? LibEveMarket.DelayedOrderKind.LimitBuy : LibEveMarket.DelayedOrderKind.MarketBuy;
        if (limitOrder) {
            params.limitPrice = HALF_PRICE;
        }

        vm.prank(actor);
        try IDelayedOrderInvariantFacet(address(diamond)).submitDelayedOrder(params) returns (uint256 orderId) {
            _recordOrder(orderId, route);
        } catch {}
        _recordHead();
    }

    function submitSell(uint256 actorSeed, uint256 curveSeed, bool limitOrder, uint128 amountSeed) external {
        if (bidCurveIds.length == 0) {
            return;
        }

        address actor = _actor(actorSeed);
        uint256 available = conditionalTokens.balanceOf(actor, yesPositionId);
        if (available < BASE_UNIT) {
            uint256 maxSplit = _min(usdc.balanceOf(actor), 4 * BASE_UNIT);
            if (maxSplit >= BASE_UNIT) {
                uint128 splitAmount = uint128(bound(uint256(amountSeed), BASE_UNIT, maxSplit));
                vm.prank(actor);
                try ICurveInventoryFacet(address(diamond)).splitInventory(marketId, splitAmount) {} catch {}
                available = conditionalTokens.balanceOf(actor, yesPositionId);
            }
        }
        if (available < BASE_UNIT) {
            return;
        }

        uint128 amount = uint128(bound(uint256(amountSeed), BASE_UNIT, _min(available, 4 * BASE_UNIT)));
        DelayedOrderTypes.DelayedOrderRoute memory route = _route(bidCurveIds[curveSeed % bidCurveIds.length]);
        DelayedOrderTypes.SubmitDelayedOrderParams memory params = _submitParams(route, amount);
        params.kind = limitOrder ? LibEveMarket.DelayedOrderKind.LimitSell : LibEveMarket.DelayedOrderKind.MarketSell;
        if (limitOrder) {
            params.limitPrice = HALF_PRICE;
        }

        vm.prank(actor);
        try IDelayedOrderInvariantFacet(address(diamond)).submitDelayedOrder(params) returns (uint256 orderId) {
            _recordOrder(orderId, route);
        } catch {}
        _recordHead();
    }

    function processHead(uint256 maxOrdersSeed) external {
        uint256 routeCount = _processableRouteCount(uint256(bound(maxOrdersSeed, 1, 3)));
        if (routeCount == 0) {
            return;
        }

        DelayedOrderTypes.DelayedOrderRoute[] memory routes = new DelayedOrderTypes.DelayedOrderRoute[](routeCount);
        uint64 head = _queueHead();
        for (uint256 index; index < routeCount; ++index) {
            routes[index] = _storedRoute(orderIds[head + uint64(index)]);
        }

        vm.roll(block.number + DELAY_BLOCKS);
        vm.prank(processor);
        try IDelayedOrderInvariantFacet(address(diamond)).processDelayedOrders(bookId, routeCount, routes) {} catch {}
        _recordHead();
        _recordTerminalStatuses();
    }

    function expireHead(uint256 maxOrdersSeed) external {
        uint64 head = _queueHead();
        uint64 tail = _queueTail();
        if (head >= tail) {
            return;
        }

        uint256 maxOrders = bound(maxOrdersSeed, 1, 3);
        vm.roll(block.number + DELAY_BLOCKS + GRACE_BLOCKS + 1);
        vm.prank(processor);
        try IDelayedOrderInvariantFacet(address(diamond))
            .processDelayedOrders(bookId, maxOrders, new DelayedOrderTypes.DelayedOrderRoute[](0)) {}
            catch {}
        _recordHead();
        _recordTerminalStatuses();
    }

    function withdrawQuote(uint256 actorSeed, uint128 amountSeed) external {
        address actor = _actor(actorSeed);
        uint128 available =
            uint128(IDelayedOrderInvariantFacet(address(diamond)).getQuoteCredit(actor, address(usdc)).withdrawable);
        if (available == 0) {
            return;
        }

        uint128 amount = uint128(bound(uint256(amountSeed), 1, available));
        vm.prank(actor);
        try IDelayedOrderInvariantFacet(address(diamond)).withdrawQuoteCredit(address(usdc), amount) {} catch {}
        _recordHead();
    }

    function withdrawBase(uint256 actorSeed, uint128 amountSeed) external {
        address actor = _actor(actorSeed);
        uint128 available = _baseCredit(actor);
        if (available == 0) {
            return;
        }

        uint128 amount = uint128(bound(uint256(amountSeed), 1, available));
        vm.prank(actor);
        try IDelayedOrderInvariantFacet(address(diamond))
            .withdrawBaseCredit(
                uint8(LibEveMarket.BookAssetType.ERC1155), address(conditionalTokens), yesPositionId, amount
            ) {}
            catch {}
        _recordHead();
    }

    function orderCount() external view returns (uint256 count) {
        count = orderIds.length;
    }

    function orderIdAt(uint256 index) external view returns (uint256 orderId) {
        orderId = orderIds[index];
    }

    function trackedActorCount() external view returns (uint256 count) {
        count = actors.length;
    }

    function trackedActorAt(uint256 index) external view returns (address actor) {
        actor = actors[index];
    }

    function diamondAddress() external view returns (address diamond_) {
        diamond_ = address(diamond);
    }

    function creatorAddress() external view returns (address creator_) {
        creator_ = creator;
    }

    function treasuryAddress() external view returns (address treasury_) {
        treasury_ = treasury;
    }

    function usdcToken() external view returns (MockUSDC token) {
        token = usdc;
    }

    function ctfToken() external view returns (MockConditionalTokens token) {
        token = conditionalTokens;
    }

    function quoteCredit(address actor) external view returns (uint128 amount) {
        amount =
            uint128(IDelayedOrderInvariantFacet(address(diamond)).getQuoteCredit(actor, address(usdc)).withdrawable);
    }

    function baseCredit(address actor) external view returns (uint128 amount) {
        amount = _baseCredit(actor);
    }

    function assertTerminalStatusesStable() external view {
        for (uint256 index; index < orderIds.length; ++index) {
            uint8 previous = lastTerminalStatus[index];
            if (previous == 0) {
                continue;
            }
            DelayedOrderTypes.DelayedOrderView memory order =
                IDelayedOrderInvariantFacet(address(diamond)).getDelayedOrder(orderIds[index]);
            assertEq(uint8(order.status), previous);
        }
    }

    function _seedAsk(uint72 price, uint128 volume) internal {
        vm.startPrank(maker);
        ICurveInventoryFacet(address(diamond)).splitInventory(marketId, volume);
        uint256 curveId = IBookOrderFacet(address(diamond))
            .postBookCurve(bookId, LibEveMarket.CurveSide.ASK, volume, price, price, 180, 0, type(uint8).max);
        vm.stopPrank();
        askCurveIds.push(curveId);
    }

    function _seedBid(uint72 price, uint128 volume) internal {
        vm.startPrank(maker);
        uint256 curveId = IBookOrderFacet(address(diamond))
            .postBookCurve(bookId, LibEveMarket.CurveSide.BID, volume, price, price, 180, 0, type(uint8).max);
        vm.stopPrank();
        bidCurveIds.push(curveId);
    }

    function _submitParams(DelayedOrderTypes.DelayedOrderRoute memory route, uint128 amount)
        internal
        view
        returns (DelayedOrderTypes.SubmitDelayedOrderParams memory params)
    {
        params.bookId = bookId;
        params.amountIn = amount;
        params.maxAveragePrice = type(uint128).max;
        params.curveIds = route.curveIds;
        params.expectedGenerations = route.expectedGenerations;
        params.expectedCommitments = route.expectedCommitments;
    }

    function _recordOrder(uint256 orderId, DelayedOrderTypes.DelayedOrderRoute memory route) internal {
        orderIds.push(orderId);
        lastTerminalStatus.push(0);
        if (route.curveIds.length != 0) {
            orderRoute[orderId] = RouteSnapshot({
                curveId: route.curveIds[0],
                generation: route.expectedGenerations[0],
                commitment: route.expectedCommitments[0]
            });
        }
    }

    function _recordTerminalStatuses() internal {
        for (uint256 index; index < orderIds.length; ++index) {
            if (lastTerminalStatus[index] != 0) {
                continue;
            }
            DelayedOrderTypes.DelayedOrderView memory order =
                IDelayedOrderInvariantFacet(address(diamond)).getDelayedOrder(orderIds[index]);
            if (_isTerminal(order.status)) {
                lastTerminalStatus[index] = uint8(order.status);
            }
        }
    }

    function _recordHead() internal {
        uint64 head = _queueHead();
        assertGe(head, lastRecordedHead);
        lastRecordedHead = head;
    }

    function _processableRouteCount(uint256 requested) internal view returns (uint256 routeCount) {
        uint64 head = _queueHead();
        uint64 tail = _queueTail();
        if (head >= tail || block.number < _headOrder().executableBlock) {
            return 0;
        }

        uint256 pending = tail - head;
        routeCount = requested < pending ? requested : pending;
    }

    function _headOrder() internal view returns (DelayedOrderTypes.DelayedOrderView memory order) {
        uint64 head = _queueHead();
        order = IDelayedOrderInvariantFacet(address(diamond)).getDelayedOrder(orderIds[head]);
    }

    function _storedRoute(uint256 orderId) internal view returns (DelayedOrderTypes.DelayedOrderRoute memory route) {
        RouteSnapshot storage snapshot = orderRoute[orderId];
        if (snapshot.curveId == 0) {
            route.curveIds = new uint256[](0);
            route.expectedGenerations = new uint32[](0);
            route.expectedCommitments = new bytes32[](0);
            return route;
        }
        route.curveIds = new uint256[](1);
        route.expectedGenerations = new uint32[](1);
        route.expectedCommitments = new bytes32[](1);
        route.curveIds[0] = snapshot.curveId;
        route.expectedGenerations[0] = snapshot.generation;
        route.expectedCommitments[0] = snapshot.commitment;
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

    function _baseCredit(address actor) internal view returns (uint128 amount) {
        amount = uint128(
            IDelayedOrderInvariantFacet(address(diamond))
            .getBaseCredit(actor, uint8(LibEveMarket.BookAssetType.ERC1155), address(conditionalTokens), yesPositionId)
            .withdrawable
        );
    }

    function _queueHead() internal view returns (uint64 head) {
        head = IDelayedOrderInvariantFacet(address(diamond)).getBookQueue(bookId).head;
    }

    function _queueTail() internal view returns (uint64 tail) {
        tail = IDelayedOrderInvariantFacet(address(diamond)).getBookQueue(bookId).tail;
    }

    function _actor(uint256 seed) internal view returns (address actor) {
        actor = actors[seed % actors.length];
    }

    function _isTerminal(LibEveMarket.DelayedOrderStatus status) internal pure returns (bool terminal) {
        terminal = status == LibEveMarket.DelayedOrderStatus.Filled
            || status == LibEveMarket.DelayedOrderStatus.PartiallyFilled
            || status == LibEveMarket.DelayedOrderStatus.Resting || status == LibEveMarket.DelayedOrderStatus.Cancelled
            || status == LibEveMarket.DelayedOrderStatus.Expired || status == LibEveMarket.DelayedOrderStatus.Refunded;
    }

    function _min(uint256 left, uint256 right) internal pure returns (uint256 value) {
        value = left < right ? left : right;
    }

    function _delayedOrderSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](8);
        selectors[0] = IDelayedOrderInvariantFacet.submitDelayedOrder.selector;
        selectors[1] = IDelayedOrderInvariantFacet.processDelayedOrders.selector;
        selectors[2] = IDelayedOrderInvariantFacet.getDelayedOrder.selector;
        selectors[3] = IDelayedOrderInvariantFacet.getBookQueue.selector;
        selectors[4] = IDelayedOrderInvariantFacet.getQuoteCredit.selector;
        selectors[5] = IDelayedOrderInvariantFacet.withdrawQuoteCredit.selector;
        selectors[6] = IDelayedOrderInvariantFacet.getBaseCredit.selector;
        selectors[7] = IDelayedOrderInvariantFacet.withdrawBaseCredit.selector;
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

contract DelayedOrderInvariantsTest is StdInvariant, Test {
    DelayedOrderInvariantHandler internal handler;

    function setUp() public {
        handler = new DelayedOrderInvariantHandler();
        handler.setUp();
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = DelayedOrderInvariantHandler.submitBuy.selector;
        selectors[1] = DelayedOrderInvariantHandler.submitSell.selector;
        selectors[2] = DelayedOrderInvariantHandler.processHead.selector;
        selectors[3] = DelayedOrderInvariantHandler.expireHead.selector;
        selectors[4] = DelayedOrderInvariantHandler.withdrawQuote.selector;
        selectors[5] = DelayedOrderInvariantHandler.withdrawBase.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    // Feature: live-delayed-taker-order, Property 7: queue head never decreases.
    function invariant_QueueHeadNeverDecreases() public view {
        uint64 head = IDelayedOrderInvariantFacet(handler.diamondAddress()).getBookQueue(handler.bookId()).head;
        assertGe(head, handler.lastRecordedHead());
    }

    // Feature: live-delayed-taker-order, Property 25: locked escrow cannot be withdrawn or reused.
    function invariant_LockedEscrowRemainsBackedByDiamondBalances() public view {
        uint256 pendingQuote;
        uint256 pendingBase;
        uint256 quoteCredit;
        uint256 baseCredit;
        uint256 count = handler.orderCount();

        for (uint256 index; index < count; ++index) {
            DelayedOrderTypes.DelayedOrderView memory order =
                IDelayedOrderInvariantFacet(handler.diamondAddress()).getDelayedOrder(handler.orderIdAt(index));
            if (order.status == LibEveMarket.DelayedOrderStatus.Pending) {
                if (
                    order.kind == LibEveMarket.DelayedOrderKind.MarketBuy
                        || order.kind == LibEveMarket.DelayedOrderKind.LimitBuy
                ) {
                    pendingQuote += order.remainingAmount;
                } else {
                    pendingBase += order.remainingAmount;
                }
            }
        }

        for (uint256 index; index < handler.trackedActorCount(); ++index) {
            address actor = handler.trackedActorAt(index);
            quoteCredit += handler.quoteCredit(actor);
            baseCredit += handler.baseCredit(actor);
        }

        assertGe(handler.usdcToken().balanceOf(handler.diamondAddress()), pendingQuote + quoteCredit);
        assertGe(
            handler.ctfToken().balanceOf(handler.diamondAddress(), handler.yesPositionId()), pendingBase + baseCredit
        );
    }

    // Feature: live-delayed-taker-order, Property 31: each order reaches at most one terminal outcome.
    function invariant_OrdersReachAtMostOneTerminalOutcome() public view {
        handler.assertTerminalStatusesStable();
    }

    // Feature: live-delayed-taker-order, Property 33: global token conservation across lifecycles.
    function invariant_GlobalTokenConservationAcrossLifecycles() public view {
        MockUSDC usdc = handler.usdcToken();
        MockConditionalTokens ctf = handler.ctfToken();
        uint256 usdcTotal = usdc.balanceOf(handler.diamondAddress()) + usdc.balanceOf(address(ctf))
            + usdc.balanceOf(handler.creatorAddress()) + usdc.balanceOf(handler.treasuryAddress());
        uint256 yesTotal = ctf.balanceOf(handler.diamondAddress(), handler.yesPositionId());
        uint256 noTotal = ctf.balanceOf(handler.diamondAddress(), handler.noPositionId());

        for (uint256 index; index < handler.trackedActorCount(); ++index) {
            address actor = handler.trackedActorAt(index);
            usdcTotal += usdc.balanceOf(actor);
            yesTotal += ctf.balanceOf(actor, handler.yesPositionId());
            noTotal += ctf.balanceOf(actor, handler.noPositionId());
        }

        assertEq(usdcTotal, handler.initialUsdcSupply());
        assertEq(yesTotal, noTotal);
        assertEq(yesTotal, usdc.balanceOf(address(ctf)));
    }
}
