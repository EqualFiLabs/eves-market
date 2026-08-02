// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC1155} from "../../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";

import {DelayedOrderTypes} from "../types/DelayedOrderTypes.sol";
import {Errors} from "../libraries/Errors.sol";
import {LibCLOBBook} from "../libraries/LibCLOBBook.sol";
import {LibDelayedOrder} from "../libraries/LibDelayedOrder.sol";
import {LibDelayedOrderExecution} from "../libraries/LibDelayedOrderExecution.sol";
import {LibDelayedOrderFacet} from "../libraries/LibDelayedOrderFacet.sol";
import {LibDelayedOrderRoute} from "../libraries/LibDelayedOrderRoute.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibReentrancy} from "../libraries/LibReentrancy.sol";

contract DelayedOrderFacet is DelayedOrderTypes {
    using SafeERC20 for IERC20;

    modifier nonReentrant() {
        LibReentrancy.enter();
        _;
        LibReentrancy.exit();
    }

    function submitDelayedOrder(SubmitDelayedOrderParams calldata params)
        external
        nonReentrant
        returns (uint256 orderId)
    {
        if (!LibDelayedOrderFacet.isSupportedDelayedKind(params.kind)) {
            revert Errors.UnsupportedDelayedOrderKind(uint8(params.kind));
        }
        if (params.amountIn == 0) {
            revert Errors.InvalidAmount(0);
        }
        if (LibDelayedOrderFacet.isLimitOrder(params.kind)) {
            if (params.limitPrice == 0 || params.limitPrice > type(uint72).max) {
                revert Errors.InvalidAmount(params.limitPrice);
            }
        }
        if (LibEveMarket.store().config.delayedOrderProcessingMode == LibEveMarket.ProcessingMode.Paused) {
            revert Errors.DelayedOrderPaused();
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Book storage book = LibCLOBBook.requireBook(state, params.bookId);
        if (!book.delayedExecutionEnabled && !state.markets[book.marketId].delayedExecutionEnabled) {
            revert Errors.UnsupportedDelayedOrderBook(params.bookId);
        }
        LibDelayedOrderRoute.requireSupportedExecutableBook(book, params.bookId);
        _validateDelayedOrderGuards(state, book, params.kind, params.amountIn, params.curveIds.length);

        bytes32 hash =
            LibDelayedOrder.routeHash(params.curveIds, params.expectedGenerations, params.expectedCommitments);
        LibDelayedOrderFacet.SubmissionSchedule memory schedule = LibDelayedOrderFacet.submissionSchedule(state.config);

        if (LibDelayedOrderFacet.isBuyOrder(params.kind)) {
            _escrowQuoteCollateral(book.quoteToken, msg.sender, params.amountIn);
        } else {
            _escrowBase(book, msg.sender, params.amountIn);
        }

        uint64 sequence;
        (orderId, sequence) =
            LibDelayedOrderFacet.recordSubmittedOrder(params, msg.sender, book.marketId, schedule, hash);
        LibDelayedOrderFacet.emitSubmitted(orderId, sequence, params, msg.sender, hash);
    }

    function processDelayedOrders(bytes32 bookId, uint256 maxOrders, DelayedOrderRoute[] calldata routes)
        external
        nonReentrant
        returns (ProcessDelayedOrderResult memory result)
    {
        result = _processDelayedOrders(bookId, maxOrders, routes);
    }

    function processDelayedOrdersFrom(
        bytes32 bookId,
        uint64 expectedHeadSequence,
        uint256 maxOrders,
        DelayedOrderRoute[] calldata routes
    ) external nonReentrant returns (ProcessDelayedOrderResult memory result) {
        (uint64 head,) = LibDelayedOrder.queueBounds(bookId);
        if (head != expectedHeadSequence) {
            revert Errors.DelayedOrderHeadMismatch(bookId, expectedHeadSequence, head);
        }
        result = _processDelayedOrders(bookId, maxOrders, routes);
    }

    function expireDelayedOrders(bytes32 bookId, uint256 maxOrders)
        external
        nonReentrant
        returns (ProcessDelayedOrderResult memory result)
    {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        while (result.processedCount < maxOrders) {
            (uint64 sequence, uint256 orderId, bool hasHead) = LibDelayedOrderFacet.tryHeadOrder(bookId);
            if (!hasHead) {
                break;
            }

            LibEveMarket.DelayedOrder storage order = state.delayedOrders.orders[orderId];
            if (!LibDelayedOrder.isExpired(order, block.number)) {
                result.stoppedOrderId = orderId;
                break;
            }

            LibDelayedOrderExecution.expireHeadOrder(orderId, order, sequence);
            result.processedCount += 1;
        }
    }

    function _processDelayedOrders(bytes32 bookId, uint256 maxOrders, DelayedOrderRoute[] calldata routes)
        private
        returns (ProcessDelayedOrderResult memory result)
    {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.ProcessingMode mode = state.config.delayedOrderProcessingMode;
        if (mode == LibEveMarket.ProcessingMode.ProtocolOnly && !LibDelayedOrder.isProtocolProcessor(msg.sender)) {
            revert Errors.DelayedOrderProcessorNotAllowed(msg.sender);
        }

        uint256 routeIndex;
        while (result.processedCount < maxOrders) {
            (uint64 sequence, uint256 orderId, bool hasHead) = LibDelayedOrderFacet.tryHeadOrder(bookId);
            if (!hasHead) {
                break;
            }

            LibEveMarket.DelayedOrder storage order = state.delayedOrders.orders[orderId];
            if (block.number < order.executableBlock) {
                result.stoppedOrderId = orderId;
                break;
            }

            if (LibDelayedOrder.isExpired(order, block.number)) {
                LibDelayedOrderExecution.expireHeadOrder(orderId, order, sequence);
                result.processedCount += 1;
                continue;
            }

            if (mode == LibEveMarket.ProcessingMode.Paused) {
                result.stoppedOrderId = orderId;
                break;
            }
            if (routeIndex >= routes.length) {
                revert Errors.DelayedOrderRouteRequired(orderId);
            }
            LibDelayedOrderExecution.processExecutableOrder(state, orderId, order, routes[routeIndex]);
            routeIndex += 1;
            result.processedCount += 1;
        }
    }

    function withdrawQuoteCredit(address token, uint128 amount) external nonReentrant {
        LibDelayedOrder.withdrawQuoteCredit(msg.sender, token, amount);
    }

    function withdrawBaseCredit(uint8 assetType, address token, uint256 tokenId, uint128 amount) external nonReentrant {
        LibDelayedOrder.withdrawBaseCredit(msg.sender, LibEveMarket.BookAssetType(assetType), token, tokenId, amount);
    }

    function getQuoteCredit(address owner, address token) external view returns (CreditBalanceView memory credit) {
        uint256 withdrawable = LibDelayedOrder.quoteCredit(owner, token);
        credit = CreditBalanceView({
            owner: owner,
            assetType: LibDelayedOrder.CREDIT_ASSET_QUOTE,
            token: token,
            tokenId: 0,
            withdrawable: withdrawable,
            locked: LibDelayedOrderFacet.lockedQuote(owner, token),
            available: withdrawable
        });
    }

    function getBaseCredit(address owner, uint8 assetType, address token, uint256 tokenId)
        external
        view
        returns (CreditBalanceView memory credit)
    {
        uint256 withdrawable = LibDelayedOrder.baseCredit(owner, LibEveMarket.BookAssetType(assetType), token, tokenId);
        credit = CreditBalanceView({
            owner: owner,
            assetType: assetType == uint8(LibEveMarket.BookAssetType.ERC20)
                ? LibDelayedOrder.CREDIT_ASSET_BASE_ERC20
                : LibDelayedOrder.CREDIT_ASSET_BASE_ERC1155,
            token: token,
            tokenId: tokenId,
            withdrawable: withdrawable,
            locked: LibDelayedOrderFacet.lockedBase(owner, LibEveMarket.BookAssetType(assetType), token, tokenId),
            available: withdrawable
        });
    }

    function getDelayedOrder(uint256 orderId) external view returns (DelayedOrderView memory order) {
        order = LibDelayedOrder.delayedOrderView(orderId);
    }

    function getBookQueue(bytes32 bookId) external view returns (BookQueueView memory queue) {
        uint64 head;
        uint64 tail;
        (head, tail) = LibDelayedOrder.queueBounds(bookId);
        uint256 headOrderId;
        if (head < tail) {
            headOrderId = LibDelayedOrder.orderIdBySequence(bookId, head);
        }
        queue = BookQueueView({
            bookId: bookId, head: head, tail: tail, headOrderId: headOrderId, pendingCount: tail - head
        });
    }

    function getDelayedOrderHead(bytes32 bookId) external view returns (DelayedOrderHeadView memory headView) {
        uint64 head;
        uint64 tail;
        (head, tail) = LibDelayedOrder.queueBounds(bookId);
        headView.bookId = bookId;
        headView.head = head;
        headView.tail = tail;
        if (head >= tail) {
            headView.processState = DelayedOrderHeadState.Empty;
            return headView;
        }

        uint256 orderId = LibDelayedOrder.orderIdBySequence(bookId, head);
        LibEveMarket.DelayedOrder storage order = LibDelayedOrder.store().orders[orderId];
        headView.orderId = orderId;
        headView.status = order.status;
        headView.executableBlock = order.executableBlock;
        headView.expiryBlock = order.expiryBlock;
        headView.routeHash = order.routeHash;
        headView.processState = _headState(order);
    }

    function getDelayedOrderIdBySequence(bytes32 bookId, uint64 sequence) external view returns (uint256 orderId) {
        orderId = LibDelayedOrder.orderIdBySequence(bookId, sequence);
    }

    function isDelayedOrderSubmissionEnabled(bytes32 bookId) external view returns (bool enabled) {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Book storage book = LibCLOBBook.requireBook(state, bookId);
        enabled = book.delayedExecutionEnabled || state.markets[book.marketId].delayedExecutionEnabled;
    }

    function _validateDelayedOrderGuards(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.Book storage book,
        LibEveMarket.DelayedOrderKind kind,
        uint128 amountIn,
        uint256 routeLength
    ) private view {
        LibEveMarket.MarketConfig storage config = state.config;
        if (config.maxDelayedOrderRouteLength != 0 && routeLength > config.maxDelayedOrderRouteLength) {
            revert Errors.DelayedOrderRouteTooLong(routeLength, config.maxDelayedOrderRouteLength);
        }

        if (LibDelayedOrderFacet.isBuyOrder(kind)) {
            if (config.minDelayedOrderQuoteWad != 0) {
                uint256 normalized = _normalizedDelayedAmount(state, book, amountIn);
                if (normalized < config.minDelayedOrderQuoteWad) {
                    revert Errors.DelayedOrderQuoteBelowMinimum(normalized, config.minDelayedOrderQuoteWad);
                }
            }
        } else if (config.minDelayedOrderBaseWad != 0) {
            uint256 normalized = _normalizedDelayedAmount(state, book, amountIn);
            if (normalized < config.minDelayedOrderBaseWad) {
                revert Errors.DelayedOrderBaseBelowMinimum(normalized, config.minDelayedOrderBaseWad);
            }
        }
    }

    function _normalizedDelayedAmount(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.Book storage book,
        uint128 amountIn
    ) private view returns (uint256 normalized) {
        uint128 payoutUnit = state.markets[book.marketId].payoutUnit;
        if (payoutUnit == 0) {
            revert Errors.InvalidAmount(0);
        }
        normalized = (uint256(amountIn) * 1e18) / uint256(payoutUnit);
    }

    function _headState(LibEveMarket.DelayedOrder storage order) private view returns (DelayedOrderHeadState state_) {
        if (LibDelayedOrder.isExpired(order, block.number)) {
            return DelayedOrderHeadState.Expired;
        }
        if (block.number < order.executableBlock) {
            return DelayedOrderHeadState.Waiting;
        }
        if (LibEveMarket.store().config.delayedOrderProcessingMode == LibEveMarket.ProcessingMode.Paused) {
            return DelayedOrderHeadState.Paused;
        }
        return DelayedOrderHeadState.NeedsRoute;
    }

    function _escrowQuoteCollateral(address quoteToken, address owner, uint128 amount) private {
        uint128 creditDrawn = LibDelayedOrder.debitQuote(owner, quoteToken, amount);
        uint128 walletAmount = amount - creditDrawn;
        if (walletAmount != 0) {
            IERC20(quoteToken).safeTransferFrom(owner, address(this), walletAmount);
        }
    }

    function _escrowBase(LibEveMarket.Book storage book, address owner, uint128 amount) private {
        uint128 creditDrawn = LibDelayedOrder.debitBase(owner, book.assetType, book.baseToken, book.baseTokenId, amount);
        uint128 walletAmount = amount - creditDrawn;
        if (walletAmount == 0) {
            return;
        }
        if (book.assetType == LibEveMarket.BookAssetType.ERC20) {
            IERC20(book.baseToken).safeTransferFrom(owner, address(this), walletAmount);
            return;
        }
        if (book.assetType == LibEveMarket.BookAssetType.ERC1155) {
            IERC1155(book.baseToken).safeTransferFrom(owner, address(this), book.baseTokenId, walletAmount, "");
            return;
        }

        revert Errors.UnsupportedCreditAssetType(uint8(book.assetType));
    }
}
