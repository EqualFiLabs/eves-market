// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC1155} from "../../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";

import {BookFacet} from "../../src/facets/BookFacet.sol";
import {BookOrderFacet} from "../../src/facets/BookOrderFacet.sol";
import {BookTradeFacet} from "../../src/facets/BookTradeFacet.sol";
import {CurveInventoryFacet} from "../../src/facets/CurveInventoryFacet.sol";
import {DelayedOrderFacet} from "../../src/facets/DelayedOrderFacet.sol";
import {OwnershipFacet} from "../../src/facets/OwnershipFacet.sol";
import {IBookAdminFacet} from "../../src/interfaces/IBookAdminFacet.sol";
import {IBookOrderFacet} from "../../src/interfaces/IBookOrderFacet.sol";
import {IBookTradeFacet} from "../../src/interfaces/IBookTradeFacet.sol";
import {ICurveInventoryFacet} from "../../src/interfaces/ICurveInventoryFacet.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {Events} from "../../src/libraries/Events.sol";
import {LibCLOBBook} from "../../src/libraries/LibCLOBBook.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {CurveCLOBTypes} from "../../src/types/CurveCLOBTypes.sol";
import {DelayedOrderTypes} from "../../src/types/DelayedOrderTypes.sol";
import {MockUSDG} from "../helpers/MockUSDG.sol";
import {ITestStateFacet, TestBase} from "../helpers/TestBase.sol";

interface IDelayedOrderConfigFacet {
    function submitDelayedOrder(DelayedOrderTypes.SubmitDelayedOrderParams calldata params)
        external
        returns (uint256 orderId);

    function processDelayedOrders(
        bytes32 bookId,
        uint256 maxOrders,
        DelayedOrderTypes.DelayedOrderRoute[] calldata routes
    ) external returns (DelayedOrderTypes.ProcessDelayedOrderResult memory result);

    function getDelayedOrder(uint256 orderId) external view returns (DelayedOrderTypes.DelayedOrderView memory order);

    function isDelayedOrderSubmissionEnabled(bytes32 bookId) external view returns (bool enabled);
}

contract DelayedOrderConfigTest is TestBase {
    uint72 internal constant HALF_PRICE = 500_000_000;
    uint128 internal constant QUOTE_AMOUNT = 50e6;
    bytes32 internal constant CONFIG_MARKET_ID = keccak256("delayed-config-market");
    address internal keeper;

    function setUp() public override {
        super.setUp();
        keeper = makeAddr("delayed-config-keeper");

        vm.startPrank(owner);
        diamond.registerFacet(address(new DelayedOrderFacet()), _delayedOrderSelectors());
        diamond.registerFacet(address(new OwnershipFacet()), _delayedOwnershipSelectors());
        diamond.registerFacet(address(new BookFacet()), _bookAdminSelectors());
        diamond.registerFacet(address(new BookOrderFacet()), _bookOrderSelectors());
        diamond.registerFacet(address(new BookTradeFacet()), _bookTradeSelectors());
        diamond.registerFacet(address(new CurveInventoryFacet()), _curveInventorySelectors());
        vm.stopPrank();

        vm.prank(taker);
        usdc.approve(address(diamond), type(uint256).max);
    }

    function test_OwnerSettersEmitAndApplyToNextSubmission() public {
        (bytes32 bookId, uint256 curveId) = _createEnabledBookWithAsk(CONFIG_MARKET_ID);
        DelayedOrderTypes.DelayedOrderRoute memory route = _route(curveId);

        vm.expectEmit(false, false, false, true);
        emit Events.ConfigUpdated("delayedProtectionBlocks", 0, 6);
        vm.expectEmit(false, false, false, true);
        emit Events.ConfigUpdated("delayedExecutionGraceBlocks", 0, 12);
        vm.expectEmit(false, false, false, true);
        emit Events.ConfigUpdated("delayedRestingMinutes", 0, 45);
        vm.prank(owner);
        OwnershipFacet(address(diamond)).setDelayedOrderConfig(6, 12, 45);

        vm.expectEmit(false, false, false, true);
        emit Events.ConfigUpdated("delayedOrderProcessingMode", 0, uint8(LibEveMarket.ProcessingMode.ProtocolOnly));
        vm.expectEmit(false, false, false, true);
        emit Events.ConfigUpdated("delayedOrderProcessorFeeShareBps", 0, 500);
        vm.prank(owner);
        OwnershipFacet(address(diamond)).setDelayedOrderProcessing(uint8(LibEveMarket.ProcessingMode.ProtocolOnly), 500);

        vm.prank(owner);
        OwnershipFacet(address(diamond)).setDelayedOrderProtocolProcessor(keeper, true);

        uint256 submitBlock = block.number;
        uint256 orderId = _submitMarketBuy(bookId, QUOTE_AMOUNT, route);
        DelayedOrderTypes.DelayedOrderView memory order =
            IDelayedOrderConfigFacet(address(diamond)).getDelayedOrder(orderId);
        assertEq(order.submitBlock, submitBlock);
        assertEq(order.executableBlock, submitBlock + 6);
        assertEq(order.expiryBlock, submitBlock + 18);

        vm.roll(order.executableBlock);
        vm.prank(keeper);
        IDelayedOrderConfigFacet(address(diamond)).processDelayedOrders(bookId, 1, _routes(route));

        order = IDelayedOrderConfigFacet(address(diamond)).getDelayedOrder(orderId);
        assertEq(uint8(order.status), uint8(LibEveMarket.DelayedOrderStatus.Filled));
    }

    function test_OwnerCanSetDelayedOrderGuards() public {
        vm.expectEmit(false, false, false, true);
        emit Events.ConfigUpdated("maxDelayedOrderRouteLength", 0, 64);
        vm.expectEmit(false, false, false, true);
        emit Events.ConfigUpdated("minDelayedOrderQuoteWad", 0, 1e18);
        vm.expectEmit(false, false, false, true);
        emit Events.ConfigUpdated("minDelayedOrderBaseWad", 0, 1e18);

        vm.prank(owner);
        OwnershipFacet(address(diamond)).setDelayedOrderGuards(64, 1e18, 1e18);
    }

    function test_DelayedSubmissionRequiresMarketOrBookEnablement() public {
        (bytes32 bookId, uint256 curveId) = _createEnabledBookWithAsk(keccak256("delayed-gated-market"));
        vm.startPrank(owner);
        OwnershipFacet(address(diamond)).setMarketDelayedExecution(_marketIdForBook(bookId), false);
        OwnershipFacet(address(diamond)).setBookDelayedExecution(bookId, false);
        vm.stopPrank();
        assertFalse(ITestStateFacet(address(diamond)).getMarketDelayedExecutionFixture(_marketIdForBook(bookId)));
        assertFalse(ITestStateFacet(address(diamond)).getBookDelayedExecutionFixture(bookId));
        assertFalse(IDelayedOrderConfigFacet(address(diamond)).isDelayedOrderSubmissionEnabled(bookId));
        DelayedOrderTypes.SubmitDelayedOrderParams memory params = _submitParams(bookId, QUOTE_AMOUNT, _route(curveId));

        vm.prank(taker);
        vm.expectRevert(abi.encodeWithSelector(Errors.UnsupportedDelayedOrderBook.selector, bookId));
        IDelayedOrderConfigFacet(address(diamond)).submitDelayedOrder(params);

        vm.prank(owner);
        OwnershipFacet(address(diamond)).setBookDelayedExecution(bookId, true);

        _submitMarketBuy(bookId, QUOTE_AMOUNT, _route(curveId));
    }

    function test_DelayedSubmissionRejectsSpotBooks() public {
        MockUSDG spotToken = new MockUSDG();
        bytes32 bookId = IBookAdminFacet(address(diamond))
            .createBook(
                LibEveMarket.BookAssetType.ERC20,
                LibEveMarket.BaseTransferMode.EXACT,
                address(spotToken),
                0,
                address(usdc),
                0,
                keccak256("delayed-config-spot-reject")
            );

        vm.prank(owner);
        OwnershipFacet(address(diamond)).setBookDelayedExecution(bookId, true);

        vm.prank(taker);
        vm.expectRevert(abi.encodeWithSelector(Errors.UnsupportedDelayedOrderBook.selector, bookId));
        IDelayedOrderConfigFacet(address(diamond))
            .submitDelayedOrder(_submitParams(bookId, QUOTE_AMOUNT, _emptyRoute()));
    }

    function _createEnabledBookWithAsk(bytes32 marketId) internal returns (bytes32 bookId, uint256 curveId) {
        ITestStateFacet(address(diamond))
            .createMarketFixture(marketId, "Delayed config market", creator, uint64(block.timestamp + 30 days));
        ITestStateFacet(address(diamond)).materializeMarketSideBookFixture(marketId, true);
        bookId = LibCLOBBook.marketBookId(marketId, true);
        vm.startPrank(maker);
        usdc.approve(address(diamond), 100e6);
        ICurveInventoryFacet(address(diamond)).splitInventory(marketId, 100e6);
        IERC1155(address(conditionalTokens)).setApprovalForAll(address(diamond), true);
        curveId = IBookOrderFacet(address(diamond))
            .postBookCurve(bookId, LibEveMarket.CurveSide.ASK, 100e6, HALF_PRICE, HALF_PRICE, 120, 0, type(uint8).max);
        vm.stopPrank();
    }

    function _submitMarketBuy(bytes32 bookId, uint128 amountIn, DelayedOrderTypes.DelayedOrderRoute memory route)
        internal
        returns (uint256 orderId)
    {
        vm.prank(taker);
        orderId = IDelayedOrderConfigFacet(address(diamond)).submitDelayedOrder(_submitParams(bookId, amountIn, route));
    }

    function _submitParams(bytes32 bookId, uint128 amountIn, DelayedOrderTypes.DelayedOrderRoute memory route)
        internal
        pure
        returns (DelayedOrderTypes.SubmitDelayedOrderParams memory params)
    {
        params.bookId = bookId;
        params.kind = LibEveMarket.DelayedOrderKind.MarketBuy;
        params.amountIn = amountIn;
        params.maxAveragePrice = type(uint128).max;
        params.curveIds = route.curveIds;
        params.expectedGenerations = route.expectedGenerations;
        params.expectedCommitments = route.expectedCommitments;
    }

    function _route(uint256 curveId) internal view returns (DelayedOrderTypes.DelayedOrderRoute memory route) {
        route.curveIds = new uint256[](1);
        route.expectedGenerations = new uint32[](1);
        route.expectedCommitments = new bytes32[](1);
        route.curveIds[0] = curveId;
        (, uint32 generation,,,,) = ITestStateFacet(address(diamond)).getStoredCurveState(curveId);
        route.expectedGenerations[0] = generation;
        route.expectedCommitments[0] =
            keccak256(abi.encodePacked(ITestStateFacet(address(diamond)).getStoredCurvePacked(curveId)));
    }

    function _emptyRoute() internal pure returns (DelayedOrderTypes.DelayedOrderRoute memory route) {
        route.curveIds = new uint256[](0);
        route.expectedGenerations = new uint32[](0);
        route.expectedCommitments = new bytes32[](0);
    }

    function _routes(DelayedOrderTypes.DelayedOrderRoute memory route)
        internal
        pure
        returns (DelayedOrderTypes.DelayedOrderRoute[] memory routes)
    {
        routes = new DelayedOrderTypes.DelayedOrderRoute[](1);
        routes[0] = route;
    }

    function _marketIdForBook(bytes32 bookId) internal view returns (bytes32 marketId) {
        CurveCLOBTypes.BookInfo memory info = IBookAdminFacet(address(diamond)).getBookInfo(bookId);
        marketId = info.marketId;
    }

    function _delayedOrderSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](5);
        selectors[0] = IDelayedOrderConfigFacet.submitDelayedOrder.selector;
        selectors[1] = IDelayedOrderConfigFacet.processDelayedOrders.selector;
        selectors[2] = IDelayedOrderConfigFacet.getDelayedOrder.selector;
        selectors[3] = DelayedOrderFacet.getQuoteCredit.selector;
        selectors[4] = IDelayedOrderConfigFacet.isDelayedOrderSubmissionEnabled.selector;
    }

    function _delayedOwnershipSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](6);
        selectors[0] = OwnershipFacet.setDelayedOrderConfig.selector;
        selectors[1] = OwnershipFacet.setDelayedOrderProcessing.selector;
        selectors[2] = OwnershipFacet.setDelayedOrderGuards.selector;
        selectors[3] = OwnershipFacet.setDelayedOrderProtocolProcessor.selector;
        selectors[4] = OwnershipFacet.setMarketDelayedExecution.selector;
        selectors[5] = OwnershipFacet.setBookDelayedExecution.selector;
    }

    function _bookAdminSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = IBookAdminFacet.createBook.selector;
        selectors[1] = IBookAdminFacet.getBookInfo.selector;
    }

    function _bookTradeSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = IBookTradeFacet.fillBookBestFor.selector;
    }

    function _bookOrderSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = IBookOrderFacet.postBookCurve.selector;
    }

    function _curveInventorySelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = ICurveInventoryFacet.splitInventory.selector;
    }
}
