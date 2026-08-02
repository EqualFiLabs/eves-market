// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {BookFacet} from "../../src/facets/BookFacet.sol";
import {CurveInventoryFacet} from "../../src/facets/CurveInventoryFacet.sol";
import {DelayedOrderFacet} from "../../src/facets/DelayedOrderFacet.sol";
import {IBookAdminFacet} from "../../src/interfaces/IBookAdminFacet.sol";
import {ICurveInventoryFacet} from "../../src/interfaces/ICurveInventoryFacet.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {LibCLOBBook} from "../../src/libraries/LibCLOBBook.sol";
import {LibDelayedOrder} from "../../src/libraries/LibDelayedOrder.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {DelayedOrderTypes} from "../../src/types/DelayedOrderTypes.sol";
import {MockUSDG} from "../helpers/MockUSDG.sol";
import {ITestStateFacet, TestBase} from "../helpers/TestBase.sol";

interface IDelayedOrderSubmissionFacet {
    function submitDelayedOrder(DelayedOrderTypes.SubmitDelayedOrderParams calldata params)
        external
        returns (uint256 orderId);

    function withdrawQuoteCredit(address token, uint128 amount) external;
    function getQuoteCredit(address owner, address token)
        external
        view
        returns (DelayedOrderTypes.CreditBalanceView memory credit);
    function getDelayedOrder(uint256 orderId) external view returns (DelayedOrderTypes.DelayedOrderView memory order);
    function getBookQueue(bytes32 bookId) external view returns (DelayedOrderTypes.BookQueueView memory queue);
    function getDelayedOrderIdBySequence(bytes32 bookId, uint64 sequence) external view returns (uint256 orderId);
}

interface IDelayedOrderSubmissionCreditSeederFacet {
    function creditQuoteFixture(address owner, address token, uint128 amount) external;
}

contract DelayedOrderSubmissionCreditSeederFacet {
    function creditQuoteFixture(address owner, address token, uint128 amount) external {
        LibDelayedOrder.creditQuote(owner, token, amount);
    }
}

contract DelayedOrderSubmissionProperties is TestBase {
    uint64 internal constant PROTECTION_DELAY_BLOCKS = 3;
    uint64 internal constant EXECUTION_GRACE_BLOCKS = 11;
    uint24 internal constant RESTING_DURATION_MINUTES = 90;

    function setUp() public override {
        super.setUp();

        vm.startPrank(owner);
        diamond.registerFacet(address(new DelayedOrderFacet()), _delayedOrderSelectors());
        diamond.registerFacet(address(new DelayedOrderSubmissionCreditSeederFacet()), _creditSeederSelectors());
        diamond.registerFacet(address(new BookFacet()), _bookSelectors());
        diamond.registerFacet(address(new CurveInventoryFacet()), _curveInventorySelectors());
        ITestStateFacet(address(diamond))
            .setDelayedOrderConfigFixture(PROTECTION_DELAY_BLOCKS, EXECUTION_GRACE_BLOCKS, RESTING_DURATION_MINUTES);
        vm.stopPrank();
    }

    // Feature: live-delayed-taker-order, Property 1: Submission escrows exactly the order amount in the correct asset.
    function testFuzz_SubmissionEscrowsExactlyTheOrderAmount(uint128 amountIn) public {
        amountIn = uint128(bound(amountIn, 1, 1_000_000e6));
        bytes32 bookId = _createPredictionBook("delayed submit escrow");
        DelayedOrderTypes.SubmitDelayedOrderParams memory params = _buyParams(bookId, amountIn, 0);

        uint256 diamondBefore = usdc.balanceOf(address(diamond));
        uint256 takerBefore = usdc.balanceOf(taker);
        vm.roll(100);

        vm.startPrank(taker);
        usdc.approve(address(diamond), amountIn);
        uint256 orderId = IDelayedOrderSubmissionFacet(address(diamond)).submitDelayedOrder(params);
        vm.stopPrank();

        DelayedOrderTypes.DelayedOrderView memory order =
            IDelayedOrderSubmissionFacet(address(diamond)).getDelayedOrder(orderId);
        assertEq(usdc.balanceOf(address(diamond)), diamondBefore + amountIn);
        assertEq(usdc.balanceOf(taker), takerBefore - amountIn);
        assertEq(order.owner, taker);
        assertEq(order.bookId, bookId);
        assertEq(order.amountIn, amountIn);
        assertEq(order.remainingAmount, amountIn);
        assertEq(uint8(order.status), uint8(LibEveMarket.DelayedOrderStatus.Pending));
    }

    // Feature: live-delayed-taker-order, Property 2: Block schedule and resting duration follow configuration.
    function testFuzz_BlockScheduleFollowsConfiguration(uint128 amountIn, uint64 startBlock) public {
        amountIn = uint128(bound(amountIn, 1, 1_000_000e6));
        startBlock = uint64(bound(startBlock, 1, type(uint32).max));
        bytes32 bookId = _createPredictionBook("delayed schedule");

        vm.roll(startBlock);
        vm.startPrank(taker);
        usdc.approve(address(diamond), amountIn);
        uint256 orderId =
            IDelayedOrderSubmissionFacet(address(diamond)).submitDelayedOrder(_buyParams(bookId, amountIn, 1));
        vm.stopPrank();

        DelayedOrderTypes.DelayedOrderView memory order =
            IDelayedOrderSubmissionFacet(address(diamond)).getDelayedOrder(orderId);
        assertEq(order.submitBlock, startBlock);
        assertEq(order.executableBlock, startBlock + PROTECTION_DELAY_BLOCKS);
        assertEq(order.expiryBlock, startBlock + PROTECTION_DELAY_BLOCKS + EXECUTION_GRACE_BLOCKS);
    }

    // Feature: live-delayed-taker-order, Property 4: Monotonic sequence and tail append.
    function testFuzz_SubmissionAssignsMonotonicSequence(uint128 firstAmount, uint128 secondAmount) public {
        firstAmount = uint128(bound(firstAmount, 1, 500_000e6));
        secondAmount = uint128(bound(secondAmount, 1, 500_000e6));
        bytes32 bookId = _createPredictionBook("delayed sequence");

        vm.startPrank(taker);
        usdc.approve(address(diamond), uint256(firstAmount) + secondAmount);
        uint256 firstOrderId =
            IDelayedOrderSubmissionFacet(address(diamond)).submitDelayedOrder(_buyParams(bookId, firstAmount, 0));
        uint256 secondOrderId =
            IDelayedOrderSubmissionFacet(address(diamond)).submitDelayedOrder(_buyParams(bookId, secondAmount, 1));
        vm.stopPrank();

        DelayedOrderTypes.DelayedOrderView memory first =
            IDelayedOrderSubmissionFacet(address(diamond)).getDelayedOrder(firstOrderId);
        DelayedOrderTypes.DelayedOrderView memory second =
            IDelayedOrderSubmissionFacet(address(diamond)).getDelayedOrder(secondOrderId);
        DelayedOrderTypes.BookQueueView memory queue =
            IDelayedOrderSubmissionFacet(address(diamond)).getBookQueue(bookId);
        assertEq(first.sequence, 0);
        assertEq(second.sequence, 1);
        assertEq(queue.head, 0);
        assertEq(queue.tail, 2);
        assertEq(queue.headOrderId, firstOrderId);
        assertEq(queue.pendingCount, 2);
        assertEq(IDelayedOrderSubmissionFacet(address(diamond)).getDelayedOrderIdBySequence(bookId, 0), firstOrderId);
        assertEq(IDelayedOrderSubmissionFacet(address(diamond)).getDelayedOrderIdBySequence(bookId, 1), secondOrderId);
    }

    // Feature: live-delayed-taker-order, Property 24: Credit-first funding.
    function testFuzz_CreditFirstFunding(uint128 creditAmount, uint128 walletAmount) public {
        creditAmount = uint128(bound(creditAmount, 1, 500_000e6));
        walletAmount = uint128(bound(walletAmount, 1, 500_000e6));
        bytes32 bookId = _createPredictionBook("delayed credit first");
        uint128 amountIn = creditAmount + walletAmount;

        vm.prank(maker);
        usdc.transfer(address(diamond), creditAmount);
        IDelayedOrderSubmissionCreditSeederFacet(address(diamond))
            .creditQuoteFixture(taker, address(usdc), creditAmount);

        uint256 takerBefore = usdc.balanceOf(taker);
        uint256 diamondBefore = usdc.balanceOf(address(diamond));

        vm.startPrank(taker);
        usdc.approve(address(diamond), walletAmount);
        uint256 orderId =
            IDelayedOrderSubmissionFacet(address(diamond)).submitDelayedOrder(_buyParams(bookId, amountIn, 0));
        vm.stopPrank();

        DelayedOrderTypes.DelayedOrderView memory order =
            IDelayedOrderSubmissionFacet(address(diamond)).getDelayedOrder(orderId);
        assertEq(usdc.balanceOf(taker), takerBefore - walletAmount);
        assertEq(usdc.balanceOf(address(diamond)), diamondBefore + walletAmount);
        DelayedOrderTypes.CreditBalanceView memory credit =
            IDelayedOrderSubmissionFacet(address(diamond)).getQuoteCredit(taker, address(usdc));
        assertEq(credit.withdrawable, 0);
        assertEq(credit.locked, amountIn);
        assertEq(credit.available, 0);
        assertEq(order.remainingAmount, amountIn);
    }

    // Feature: live-delayed-taker-order, Property 25: Locked escrow cannot be withdrawn or reused.
    function testFuzz_LockedEscrowCannotBeWithdrawnOrReused(uint128 creditAmount) public {
        creditAmount = uint128(bound(creditAmount, 1, 500_000e6));
        bytes32 bookId = _createPredictionBook("delayed locked escrow");

        vm.prank(maker);
        usdc.transfer(address(diamond), creditAmount);
        IDelayedOrderSubmissionCreditSeederFacet(address(diamond))
            .creditQuoteFixture(taker, address(usdc), creditAmount);

        vm.prank(taker);
        IDelayedOrderSubmissionFacet(address(diamond)).submitDelayedOrder(_buyParams(bookId, creditAmount, 0));

        vm.prank(taker);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.InsufficientCredit.selector,
                taker,
                LibDelayedOrder.CREDIT_ASSET_QUOTE,
                address(usdc),
                uint256(0),
                creditAmount,
                uint128(0)
            )
        );
        IDelayedOrderSubmissionFacet(address(diamond)).withdrawQuoteCredit(address(usdc), creditAmount);

        vm.prank(taker);
        vm.expectRevert();
        IDelayedOrderSubmissionFacet(address(diamond)).submitDelayedOrder(_buyParams(bookId, creditAmount, 1));
    }

    function test_SubmitDelayedOrderRejectsZeroAmount() public {
        bytes32 bookId = _createPredictionBook("delayed zero");

        vm.prank(taker);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidAmount.selector, uint256(0)));
        IDelayedOrderSubmissionFacet(address(diamond)).submitDelayedOrder(_buyParams(bookId, 0, 0));
    }

    function test_SubmitDelayedOrderRejectsSpotBook() public {
        MockUSDG spotToken = new MockUSDG();
        bytes32 bookId = _createSpotBook(address(spotToken));

        vm.startPrank(taker);
        usdc.approve(address(diamond), 100e6);
        vm.expectRevert(abi.encodeWithSelector(Errors.UnsupportedDelayedOrderBook.selector, bookId));
        IDelayedOrderSubmissionFacet(address(diamond)).submitDelayedOrder(_buyParams(bookId, 100e6, 0));
        vm.stopPrank();
    }

    function test_SubmitDelayedOrderRejectsResolvedBook() public {
        bytes32 marketId;
        (marketId,) = _createMarketFixture("delayed resolved", uint64(block.timestamp + 1 days));
        ITestStateFacet(address(diamond)).materializeMarketSideBookFixture(marketId, true);
        bytes32 bookId = LibCLOBBook.marketBookId(marketId, true);
        ITestStateFacet(address(diamond)).resolveMarketFixture(marketId, uint8(LibEveMarket.MarketOutcome.Yes));

        vm.prank(taker);
        vm.expectRevert(abi.encodeWithSelector(Errors.BookNotActive.selector, bookId));
        IDelayedOrderSubmissionFacet(address(diamond)).submitDelayedOrder(_buyParams(bookId, 100e6, 0));
    }

    function test_SubmitDelayedOrderRecordsSellKindWithBaseEscrow() public {
        bytes32 marketId;
        (marketId,) = _createMarketFixture("delayed sell supported", uint64(block.timestamp + 1 days));
        ITestStateFacet(address(diamond)).materializeMarketSideBookFixture(marketId, true);
        bytes32 bookId = LibCLOBBook.marketBookId(marketId, true);
        (,,,, uint256 yesPositionId,) = ITestStateFacet(address(diamond)).getStoredMarketCore(marketId);
        DelayedOrderTypes.SubmitDelayedOrderParams memory params = _buyParams(bookId, 100e6, 0);
        params.kind = LibEveMarket.DelayedOrderKind.MarketSell;

        vm.startPrank(taker);
        usdc.approve(address(diamond), 100e6);
        ICurveInventoryFacet(address(diamond)).splitInventory(marketId, 100e6);
        conditionalTokens.setApprovalForAll(address(diamond), true);
        uint256 orderId = IDelayedOrderSubmissionFacet(address(diamond)).submitDelayedOrder(params);
        vm.stopPrank();

        DelayedOrderTypes.DelayedOrderView memory order =
            IDelayedOrderSubmissionFacet(address(diamond)).getDelayedOrder(orderId);
        assertEq(uint8(order.kind), uint8(LibEveMarket.DelayedOrderKind.MarketSell));
        assertEq(order.amountIn, 100e6);
        assertEq(conditionalTokens.balanceOf(address(diamond), yesPositionId), 100e6);
    }

    function _createPredictionBook(string memory question) internal returns (bytes32 bookId) {
        bytes32 marketId;
        (marketId,) = _createMarketFixture(question, uint64(block.timestamp + 1 days));
        ITestStateFacet(address(diamond)).materializeMarketSideBookFixture(marketId, true);
        bookId = LibCLOBBook.marketBookId(marketId, true);
    }

    function _createSpotBook(address spotToken) internal returns (bytes32 bookId) {
        vm.prank(maker);
        bookId = IBookAdminFacet(address(diamond))
            .createBook(
                LibEveMarket.BookAssetType.ERC20,
                LibEveMarket.BaseTransferMode.EXACT,
                spotToken,
                0,
                address(usdc),
                0,
                keccak256("delayed-spot-reject")
            );
    }

    function _buyParams(bytes32 bookId, uint128 amountIn, uint256 routeSalt)
        internal
        pure
        returns (DelayedOrderTypes.SubmitDelayedOrderParams memory params)
    {
        params.bookId = bookId;
        params.kind = LibEveMarket.DelayedOrderKind.MarketBuy;
        params.amountIn = amountIn;
        params.limitPrice = 0;
        params.minOut = 0;
        params.maxAveragePrice = 0;
        params.curveIds = new uint256[](1);
        params.expectedGenerations = new uint32[](1);
        params.expectedCommitments = new bytes32[](1);
        params.curveIds[0] = routeSalt + 1;
        params.expectedGenerations[0] = uint32(routeSalt + 1);
        params.expectedCommitments[0] = keccak256(abi.encode(routeSalt));
    }

    function _delayedOrderSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](8);
        selectors[0] = IDelayedOrderSubmissionFacet.submitDelayedOrder.selector;
        selectors[1] = IDelayedOrderSubmissionFacet.withdrawQuoteCredit.selector;
        selectors[2] = IDelayedOrderSubmissionFacet.getQuoteCredit.selector;
        selectors[3] = IDelayedOrderSubmissionFacet.getDelayedOrder.selector;
        selectors[4] = IDelayedOrderSubmissionFacet.getBookQueue.selector;
        selectors[5] = IDelayedOrderSubmissionFacet.getDelayedOrderIdBySequence.selector;
        selectors[6] = DelayedOrderFacet.withdrawBaseCredit.selector;
        selectors[7] = DelayedOrderFacet.getBaseCredit.selector;
    }

    function _creditSeederSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = IDelayedOrderSubmissionCreditSeederFacet.creditQuoteFixture.selector;
    }

    function _bookSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = IBookAdminFacet.createBook.selector;
    }

    function _curveInventorySelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = ICurveInventoryFacet.splitInventory.selector;
    }
}
