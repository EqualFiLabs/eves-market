// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "../../lib/forge-std/src/Test.sol";
import {Vm} from "../../lib/forge-std/src/Vm.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {LibDelayedOrder} from "../../src/libraries/LibDelayedOrder.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {MockConditionalTokens} from "../helpers/MockConditionalTokens.sol";
import {MockUSDG} from "../helpers/MockUSDG.sol";
import {ERC1155ReceiverHarness} from "../helpers/ERC1155ReceiverHarness.sol";

contract DelayedOrderMathHarness {
    function bidVolumeFromEscrow(uint128 quoteEscrow, uint128 limitPrice, uint128 priceDenominator)
        external
        pure
        returns (uint128 volume, uint128 dust)
    {
        return LibDelayedOrder.bidVolumeFromEscrow(quoteEscrow, limitPrice, priceDenominator);
    }

    function routeHash(
        uint256[] calldata curveIds,
        uint32[] calldata expectedGenerations,
        bytes32[] calldata expectedCommitments
    ) external pure returns (bytes32 hash) {
        hash = LibDelayedOrder.routeHash(curveIds, expectedGenerations, expectedCommitments);
    }
}

contract DelayedOrderCreditHarness is ERC1155ReceiverHarness {
    function creditQuote(address owner, address token, uint128 amount) external {
        LibDelayedOrder.creditQuote(owner, token, amount);
    }

    function creditBase(address owner, uint8 assetType, address token, uint256 tokenId, uint128 amount) external {
        LibDelayedOrder.creditBase(owner, LibEveMarket.BookAssetType(assetType), token, tokenId, amount);
    }

    function debitQuote(address owner, address token, uint128 amount) external returns (uint128 drawn) {
        drawn = LibDelayedOrder.debitQuote(owner, token, amount);
    }

    function debitBase(address owner, uint8 assetType, address token, uint256 tokenId, uint128 amount)
        external
        returns (uint128 drawn)
    {
        drawn = LibDelayedOrder.debitBase(owner, LibEveMarket.BookAssetType(assetType), token, tokenId, amount);
    }

    function withdrawQuoteCredit(address token, uint128 amount) external {
        LibDelayedOrder.withdrawQuoteCredit(msg.sender, token, amount);
    }

    function withdrawBaseCredit(uint8 assetType, address token, uint256 tokenId, uint128 amount) external {
        LibDelayedOrder.withdrawBaseCredit(msg.sender, LibEveMarket.BookAssetType(assetType), token, tokenId, amount);
    }

    function quoteCredit(address owner, address token) external view returns (uint128 amount) {
        amount = LibDelayedOrder.quoteCredit(owner, token);
    }

    function baseCredit(address owner, uint8 assetType, address token, uint256 tokenId)
        external
        view
        returns (uint128 amount)
    {
        amount = LibDelayedOrder.baseCredit(owner, LibEveMarket.BookAssetType(assetType), token, tokenId);
    }
}

contract DelayedOrderQueueHarness {
    function append(bytes32 bookId, uint256 orderId) external returns (uint64 sequence) {
        sequence = LibDelayedOrder.appendOrder(bookId, orderId);
    }

    function advance(bytes32 bookId) external returns (uint64 head) {
        head = LibDelayedOrder.advanceHead(bookId);
    }

    function orderIdBySequence(bytes32 bookId, uint64 sequence) external view returns (uint256 orderId) {
        orderId = LibDelayedOrder.orderIdBySequence(bookId, sequence);
    }

    function queueBounds(bytes32 bookId) external view returns (uint64 head, uint64 tail) {
        (head, tail) = LibDelayedOrder.queueBounds(bookId);
    }

    function setWindow(uint256 orderId, uint64 executableBlock, uint64 expiryBlock) external {
        LibEveMarket.DelayedOrder storage order = LibDelayedOrder.store().orders[orderId];
        order.owner = address(this);
        order.status = LibEveMarket.DelayedOrderStatus.Pending;
        order.executableBlock = executableBlock;
        order.expiryBlock = expiryBlock;
    }

    function setStatus(uint256 orderId, uint8 status) external {
        LibDelayedOrder.store().orders[orderId].status = LibEveMarket.DelayedOrderStatus(status);
    }

    function isExecutable(uint256 orderId, uint256 currentBlock) external view returns (bool executable) {
        executable = LibDelayedOrder.isExecutable(LibDelayedOrder.store().orders[orderId], currentBlock);
    }

    function isExpired(uint256 orderId, uint256 currentBlock) external view returns (bool expired) {
        expired = LibDelayedOrder.isExpired(LibDelayedOrder.store().orders[orderId], currentBlock);
    }
}

contract DelayedOrderProperties is Test {
    bytes32 internal constant USER_CREDIT_CHANGED_TOPIC =
        keccak256("UserCreditChanged(address,uint8,address,uint256,int256)");

    DelayedOrderMathHarness internal mathHarness;
    DelayedOrderCreditHarness internal creditHarness;
    DelayedOrderQueueHarness internal queueHarness;
    MockUSDG internal usdc;
    MockConditionalTokens internal conditionalTokens;
    address internal owner;

    function setUp() public {
        mathHarness = new DelayedOrderMathHarness();
        creditHarness = new DelayedOrderCreditHarness();
        queueHarness = new DelayedOrderQueueHarness();
        usdc = new MockUSDG();
        conditionalTokens = new MockConditionalTokens();
        owner = makeAddr("credit-owner");
    }

    // Feature: live-delayed-taker-order, Property 19: BID flat-curve volume derivation conserves escrow.
    function testFuzz_BidFlatCurveVolumeDerivationConservesEscrow(
        uint128 quoteEscrow,
        uint128 limitPrice,
        uint128 priceDenominator
    ) public view {
        priceDenominator = uint128(bound(priceDenominator, 1, 1_000_000_000));
        limitPrice = uint128(bound(limitPrice, 1, priceDenominator));
        uint256 maxEscrow = (uint256(type(uint128).max) * uint256(limitPrice)) / uint256(priceDenominator);
        quoteEscrow = uint128(bound(quoteEscrow, 0, maxEscrow));

        (uint128 volume, uint128 dust) = mathHarness.bidVolumeFromEscrow(quoteEscrow, limitPrice, priceDenominator);

        uint256 representedEscrow = (uint256(volume) * uint256(limitPrice)) / uint256(priceDenominator);
        assertLe(representedEscrow, quoteEscrow);
        assertEq(dust, uint256(quoteEscrow) - representedEscrow);
    }

    function test_BidVolumeFromEscrowRejectsZeroLimitPrice() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidAmount.selector, uint256(0)));
        mathHarness.bidVolumeFromEscrow(1, 0, 1);
    }

    function test_BidVolumeFromEscrowRejectsZeroPriceDenominator() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidAmount.selector, uint256(0)));
        mathHarness.bidVolumeFromEscrow(1, 1, 0);
    }

    // Feature: live-delayed-taker-order, Property 3: Route hash round-trip.
    function testFuzz_RouteHashRoundTrip(
        uint256 curveA,
        uint256 curveB,
        uint32 generationA,
        uint32 generationB,
        bytes32 commitmentA,
        bytes32 commitmentB
    ) public view {
        uint256[] memory curveIds = new uint256[](2);
        uint32[] memory generations = new uint32[](2);
        bytes32[] memory commitments = new bytes32[](2);
        curveIds[0] = curveA;
        curveIds[1] = curveB;
        generations[0] = generationA;
        generations[1] = generationB;
        commitments[0] = commitmentA;
        commitments[1] = commitmentB;

        bytes32 actual = mathHarness.routeHash(curveIds, generations, commitments);

        assertEq(actual, keccak256(abi.encode(curveIds, generations, commitments)));
    }

    function test_RouteHashRejectsGenerationLengthMismatch() public {
        uint256[] memory curveIds = new uint256[](2);
        uint32[] memory generations = new uint32[](1);
        bytes32[] memory commitments = new bytes32[](2);

        vm.expectRevert(abi.encodeWithSelector(Errors.ArrayLengthMismatch.selector, uint256(2), uint256(1)));
        mathHarness.routeHash(curveIds, generations, commitments);
    }

    function test_RouteHashRejectsCommitmentLengthMismatch() public {
        uint256[] memory curveIds = new uint256[](2);
        uint32[] memory generations = new uint32[](2);
        bytes32[] memory commitments = new bytes32[](1);

        vm.expectRevert(abi.encodeWithSelector(Errors.ArrayLengthMismatch.selector, uint256(2), uint256(1)));
        mathHarness.routeHash(curveIds, generations, commitments);
    }

    // Feature: live-delayed-taker-order, Property 4: Monotonic sequence and tail append.
    function testFuzz_MonotonicSequenceAndTailAppend(bytes32 bookId, uint256 firstOrderId, uint256 secondOrderId)
        public
    {
        vm.assume(bookId != bytes32(0));
        firstOrderId = bound(firstOrderId, 1, type(uint128).max);
        secondOrderId = bound(secondOrderId, 1, type(uint128).max);
        vm.assume(firstOrderId != secondOrderId);

        uint64 firstSequence = queueHarness.append(bookId, firstOrderId);
        uint64 secondSequence = queueHarness.append(bookId, secondOrderId);
        (uint64 head, uint64 tail) = queueHarness.queueBounds(bookId);

        assertEq(firstSequence, 0);
        assertEq(secondSequence, 1);
        assertEq(head, 0);
        assertEq(tail, 2);
        assertEq(queueHarness.orderIdBySequence(bookId, firstSequence), firstOrderId);
        assertEq(queueHarness.orderIdBySequence(bookId, secondSequence), secondOrderId);
        assertEq(queueHarness.advance(bookId), 1);
        (head, tail) = queueHarness.queueBounds(bookId);
        assertEq(head, 1);
        assertEq(tail, 2);
    }

    // Feature: live-delayed-taker-order, Property 5: Executable window predicate.
    function testFuzz_ExecutableWindowPredicate(uint64 executableBlock, uint64 graceBlocks, uint64 deltaBlock) public {
        graceBlocks = uint64(bound(graceBlocks, 0, type(uint32).max));
        executableBlock = uint64(bound(executableBlock, 1, type(uint64).max - graceBlocks));
        uint64 expiryBlock = executableBlock + graceBlocks;
        uint64 currentBlock = uint64(bound(deltaBlock, 0, uint256(expiryBlock) + 1));

        queueHarness.setWindow(1, executableBlock, expiryBlock);

        bool expectedExecutable = currentBlock >= executableBlock && currentBlock <= expiryBlock;
        bool expectedExpired = currentBlock > expiryBlock;
        assertEq(queueHarness.isExecutable(1, currentBlock), expectedExecutable);
        assertEq(queueHarness.isExpired(1, currentBlock), expectedExpired);

        queueHarness.setStatus(1, uint8(LibEveMarket.DelayedOrderStatus.Cancelled));
        assertFalse(queueHarness.isExecutable(1, currentBlock));
        assertFalse(queueHarness.isExpired(1, currentBlock));
    }

    // Feature: live-delayed-taker-order, Property 22: Credit conservation on release.
    function testFuzz_CreditConservationOnRelease(uint128 quoteAmount, uint128 baseAmount, uint256 tokenId) public {
        quoteAmount = uint128(bound(quoteAmount, 1, type(uint96).max));
        baseAmount = uint128(bound(baseAmount, 1, type(uint96).max));

        creditHarness.creditQuote(owner, address(usdc), quoteAmount);
        creditHarness.creditBase(
            owner, uint8(LibEveMarket.BookAssetType.ERC1155), address(conditionalTokens), tokenId, baseAmount
        );

        assertEq(creditHarness.quoteCredit(owner, address(usdc)), quoteAmount);
        assertEq(
            creditHarness.baseCredit(
                owner, uint8(LibEveMarket.BookAssetType.ERC1155), address(conditionalTokens), tokenId
            ),
            baseAmount
        );
    }

    // Feature: live-delayed-taker-order, Property 23: Credit withdrawal round-trip.
    function testFuzz_CreditWithdrawalRoundTrip(uint128 quoteAmount, uint128 baseAmount, uint256 tokenId) public {
        quoteAmount = uint128(bound(quoteAmount, 1, type(uint96).max));
        baseAmount = uint128(bound(baseAmount, 1, type(uint96).max));

        usdc.mint(address(creditHarness), quoteAmount);
        conditionalTokens.mintPosition(address(creditHarness), tokenId, baseAmount);
        creditHarness.creditQuote(owner, address(usdc), quoteAmount);
        creditHarness.creditBase(
            owner, uint8(LibEveMarket.BookAssetType.ERC1155), address(conditionalTokens), tokenId, baseAmount
        );

        vm.startPrank(owner);
        creditHarness.withdrawQuoteCredit(address(usdc), quoteAmount);
        creditHarness.withdrawBaseCredit(
            uint8(LibEveMarket.BookAssetType.ERC1155), address(conditionalTokens), tokenId, baseAmount
        );
        vm.stopPrank();

        assertEq(usdc.balanceOf(owner), quoteAmount);
        assertEq(conditionalTokens.balanceOf(owner, tokenId), baseAmount);
        assertEq(creditHarness.quoteCredit(owner, address(usdc)), 0);
        assertEq(
            creditHarness.baseCredit(
                owner, uint8(LibEveMarket.BookAssetType.ERC1155), address(conditionalTokens), tokenId
            ),
            0
        );
    }

    // Feature: live-delayed-taker-order, Property 26: Credit-change events reconcile balances.
    function testFuzz_CreditChangeEventsReconcileBalances(uint128 released, uint128 requestedDebit) public {
        released = uint128(bound(released, 1, type(uint96).max));
        requestedDebit = uint128(bound(requestedDebit, 0, type(uint96).max));

        vm.recordLogs();
        creditHarness.creditQuote(owner, address(usdc), released);
        uint128 drawn = creditHarness.debitQuote(owner, address(usdc), requestedDebit);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        int256 eventDeltaSum;
        for (uint256 index; index < entries.length; ++index) {
            if (entries[index].topics[0] != USER_CREDIT_CHANGED_TOPIC) {
                continue;
            }
            (, int256 delta) = abi.decode(entries[index].data, (uint256, int256));
            eventDeltaSum += delta;
        }

        uint128 finalCredit = creditHarness.quoteCredit(owner, address(usdc));
        assertEq(finalCredit, released - drawn);
        assertEq(eventDeltaSum, int256(uint256(finalCredit)));
    }
}
