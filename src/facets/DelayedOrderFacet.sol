// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC1155} from "../../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";

import {CurveCLOBTypes} from "../types/CurveCLOBTypes.sol";
import {DelayedOrderTypes} from "../types/DelayedOrderTypes.sol";
import {Errors} from "../libraries/Errors.sol";
import {Events} from "../libraries/Events.sol";
import {LibBookPricing} from "../libraries/LibBookPricing.sol";
import {LibBuyExecution} from "../libraries/LibBuyExecution.sol";
import {LibCLOBBook} from "../libraries/LibCLOBBook.sol";
import {LibCurveMath} from "../libraries/LibCurveMath.sol";
import {LibCurveStorage} from "../libraries/LibCurveStorage.sol";
import {LibDelayedOrder} from "../libraries/LibDelayedOrder.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibReentrancy} from "../libraries/LibReentrancy.sol";
import {LibSellExecution} from "../libraries/LibSellExecution.sol";

contract DelayedOrderFacet is DelayedOrderTypes {
    using SafeERC20 for IERC20;

    struct SubmissionSchedule {
        uint64 submitBlock;
        uint64 executableBlock;
        uint64 expiryBlock;
    }

    struct PreparedRoute {
        uint256[] curveIds;
        uint32[] expectedGenerations;
        bytes32[] expectedCommitments;
    }

    struct FillPreview {
        uint128 sharesOut;
        uint128 collateralUsed;
        uint128 feePaid;
        uint128 averagePrice;
        uint128 unfilledCollateral;
    }

    struct SellPreview {
        uint128 baseSold;
        uint128 quoteOut;
        uint128 feePaid;
        uint128 averagePrice;
        uint128 unfilledBase;
    }

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
        if (!_isSupportedDelayedKind(params.kind)) {
            revert Errors.UnsupportedDelayedOrderKind(uint8(params.kind));
        }
        if (params.amountIn == 0) {
            revert Errors.InvalidAmount(0);
        }
        if (_isLimitOrder(params.kind)) {
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
        _requireSupportedExecutableBook(book, params.bookId);

        bytes32 hash =
            LibDelayedOrder.routeHash(params.curveIds, params.expectedGenerations, params.expectedCommitments);
        SubmissionSchedule memory schedule = _submissionSchedule(state.config);

        if (_isBuyOrder(params.kind)) {
            _escrowQuoteCollateral(book.quoteToken, msg.sender, params.amountIn);
        } else {
            _escrowBase(book, msg.sender, params.amountIn);
        }

        uint64 sequence;
        (orderId, sequence) = _recordSubmittedOrder(params, book.marketId, schedule, hash);
        _emitSubmitted(orderId, sequence, params, hash);
    }

    function processDelayedOrders(bytes32 bookId, uint256 maxOrders, DelayedOrderRoute[] calldata routes)
        external
        nonReentrant
        returns (ProcessDelayedOrderResult memory result)
    {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.ProcessingMode mode = state.config.delayedOrderProcessingMode;
        if (mode == LibEveMarket.ProcessingMode.ProtocolOnly && !LibDelayedOrder.isProtocolProcessor(msg.sender)) {
            revert Errors.DelayedOrderProcessorNotAllowed(msg.sender);
        }

        uint256 routeIndex;
        while (result.processedCount < maxOrders) {
            (uint64 sequence, uint256 orderId, bool hasHead) = _tryHeadOrder(bookId);
            if (!hasHead) {
                break;
            }

            LibEveMarket.DelayedOrder storage order = state.delayedOrders.orders[orderId];
            if (block.number < order.executableBlock) {
                result.stoppedOrderId = orderId;
                break;
            }

            if (LibDelayedOrder.isExpired(order, block.number)) {
                _expireHeadOrder(orderId, order, sequence);
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
            _processExecutableOrder(state, orderId, order, routes[routeIndex]);
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
            locked: _lockedQuote(owner, token),
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
            locked: _lockedBase(owner, LibEveMarket.BookAssetType(assetType), token, tokenId),
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

    function getDelayedOrderIdBySequence(bytes32 bookId, uint64 sequence) external view returns (uint256 orderId) {
        orderId = LibDelayedOrder.orderIdBySequence(bookId, sequence);
    }

    function isDelayedOrderSubmissionEnabled(bytes32 bookId) external view returns (bool enabled) {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Book storage book = LibCLOBBook.requireBook(state, bookId);
        enabled = book.delayedExecutionEnabled || state.markets[book.marketId].delayedExecutionEnabled;
    }

    function _requireSupportedExecutableBook(LibEveMarket.Book storage book, bytes32 bookId) private view {
        if (
            book.marketId == bytes32(0) || book.pricingMode != LibEveMarket.BookPricingMode.PREDICTION_PAYOUT
                || book.assetType != LibEveMarket.BookAssetType.ERC1155
        ) {
            revert Errors.UnsupportedDelayedOrderBook(bookId);
        }
        if (!LibCLOBBook.canExecute(book)) {
            revert Errors.BookNotActive(bookId);
        }
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

    function _processExecutableOrder(
        LibEveMarket.EveMarketStorage storage state,
        uint256 orderId,
        LibEveMarket.DelayedOrder storage order,
        DelayedOrderRoute calldata route
    ) private {
        bytes32 actualRouteHash = LibDelayedOrder.routeHash(
            route.curveIds, route.expectedGenerations, route.expectedCommitments
        );
        if (actualRouteHash != order.routeHash) {
            revert Errors.DelayedOrderRouteMismatch(orderId, order.routeHash, actualRouteHash);
        }

        LibEveMarket.Book storage book = state.books[order.bookId];
        if (order.kind == LibEveMarket.DelayedOrderKind.MarketBuy) {
            PreparedRoute memory prepared = _prepareValidAskRoute(state, order, book, route);
            _processMarketBuy(state, orderId, order, book, prepared);
            return;
        }
        if (order.kind == LibEveMarket.DelayedOrderKind.LimitBuy) {
            PreparedRoute memory prepared = _prepareValidAskRoute(state, order, book, route);
            _processLimitBuy(state, orderId, order, book, prepared);
            return;
        }
        if (order.kind == LibEveMarket.DelayedOrderKind.MarketSell) {
            PreparedRoute memory prepared = _prepareValidBidRoute(state, order, book, route);
            _processMarketSell(state, orderId, order, book, prepared);
            return;
        }
        if (order.kind == LibEveMarket.DelayedOrderKind.LimitSell) {
            PreparedRoute memory prepared = _prepareValidBidRoute(state, order, book, route);
            _processLimitSell(state, orderId, order, book, prepared);
            return;
        }

        revert Errors.UnsupportedDelayedOrderKind(uint8(order.kind));
    }

    function _processMarketBuy(
        LibEveMarket.EveMarketStorage storage state,
        uint256 orderId,
        LibEveMarket.DelayedOrder storage order,
        LibEveMarket.Book storage book,
        PreparedRoute memory prepared
    ) private {
        if (prepared.curveIds.length == 0) {
            _cancelBuy(orderId, order, book, 0, 0, 0);
            return;
        }

        uint128 maxAveragePrice = order.maxAveragePrice == 0 ? type(uint128).max : order.maxAveragePrice;
        FillPreview memory preview = _previewFill(state, book, order.remainingAmount, prepared, maxAveragePrice);
        if (preview.sharesOut < order.minOut || preview.averagePrice > maxAveragePrice) {
            _cancelBuy(orderId, order, book, 0, 0, 0);
            return;
        }

        CurveCLOBTypes.FillBestResult memory fill =
            _executeDelayedBuyFill(order, prepared, order.minOut, maxAveragePrice);
        uint128 creditedQuote = fill.unfilledCollateral;
        if (creditedQuote != 0) {
            LibDelayedOrder.creditQuote(order.owner, book.quoteToken, creditedQuote);
        }

        order.remainingAmount = 0;
        order.status = creditedQuote == 0
            ? LibEveMarket.DelayedOrderStatus.Filled
            : LibEveMarket.DelayedOrderStatus.PartiallyFilled;
        LibDelayedOrder.advanceHead(order.bookId);
        _emitProcessed(
            orderId, order, msg.sender, fill.collateralUsed, fill.sharesOut, creditedQuote, 0, 0, fill.feePaid
        );
    }

    function _processLimitBuy(
        LibEveMarket.EveMarketStorage storage state,
        uint256 orderId,
        LibEveMarket.DelayedOrder storage order,
        LibEveMarket.Book storage book,
        PreparedRoute memory prepared
    ) private {
        CurveCLOBTypes.FillBestResult memory fill;
        if (prepared.curveIds.length != 0) {
            FillPreview memory preview = _previewFill(state, book, order.remainingAmount, prepared, order.limitPrice);
            if (preview.sharesOut != 0 && preview.averagePrice <= order.limitPrice) {
                fill = _executeDelayedBuyFill(order, prepared, 0, order.limitPrice);
            }
        }

        uint128 remainingQuote =
            fill.unfilledCollateral == 0 && fill.collateralUsed == 0 ? order.remainingAmount : fill.unfilledCollateral;
        (uint256 restingCurveId, uint128 creditedQuote) = _restLimitBuyRemainder(state, order, book, remainingQuote);
        order.remainingAmount = 0;
        order.restingCurveId = restingCurveId;
        if (restingCurveId != 0) {
            order.status = LibEveMarket.DelayedOrderStatus.Resting;
        } else if (fill.sharesOut != 0 && remainingQuote == 0) {
            order.status = LibEveMarket.DelayedOrderStatus.Filled;
        } else if (fill.sharesOut != 0) {
            order.status = LibEveMarket.DelayedOrderStatus.PartiallyFilled;
        } else {
            order.status = LibEveMarket.DelayedOrderStatus.Cancelled;
        }
        LibDelayedOrder.advanceHead(order.bookId);
        _emitProcessed(
            orderId,
            order,
            msg.sender,
            fill.collateralUsed,
            fill.sharesOut,
            creditedQuote,
            0,
            restingCurveId,
            fill.feePaid
        );
    }

    function _processMarketSell(
        LibEveMarket.EveMarketStorage storage state,
        uint256 orderId,
        LibEveMarket.DelayedOrder storage order,
        LibEveMarket.Book storage book,
        PreparedRoute memory prepared
    ) private {
        if (prepared.curveIds.length == 0) {
            _cancelSell(orderId, order, book, 0, 0, 0);
            return;
        }

        SellPreview memory preview = _previewSell(state, book, order.remainingAmount, prepared, 0);
        if (preview.quoteOut < order.minOut) {
            _cancelSell(orderId, order, book, 0, 0, 0);
            return;
        }

        CurveCLOBTypes.SellBookResult memory sell = _executeDelayedSellFill(order, prepared, order.minOut);
        uint128 creditedBase = sell.unfilledBase;
        if (creditedBase != 0) {
            _creditBase(order.owner, book, creditedBase);
        }

        order.remainingAmount = 0;
        order.status = creditedBase == 0
            ? LibEveMarket.DelayedOrderStatus.Filled
            : LibEveMarket.DelayedOrderStatus.PartiallyFilled;
        LibDelayedOrder.advanceHead(order.bookId);
        _emitProcessed(orderId, order, msg.sender, sell.baseSold, sell.quoteOut, 0, creditedBase, 0, sell.feePaid);
    }

    function _processLimitSell(
        LibEveMarket.EveMarketStorage storage state,
        uint256 orderId,
        LibEveMarket.DelayedOrder storage order,
        LibEveMarket.Book storage book,
        PreparedRoute memory prepared
    ) private {
        CurveCLOBTypes.SellBookResult memory sell;
        if (prepared.curveIds.length != 0) {
            SellPreview memory preview = _previewSell(state, book, order.remainingAmount, prepared, order.limitPrice);
            if (preview.baseSold != 0) {
                sell = _executeDelayedSellFill(order, prepared, 0);
            }
        }

        uint128 remainingBase = sell.unfilledBase == 0 && sell.baseSold == 0 ? order.remainingAmount : sell.unfilledBase;
        uint256 restingCurveId = _restLimitSellRemainder(state, order, remainingBase);
        order.remainingAmount = 0;
        order.restingCurveId = restingCurveId;
        if (restingCurveId != 0) {
            order.status = LibEveMarket.DelayedOrderStatus.Resting;
        } else if (sell.baseSold != 0 && remainingBase == 0) {
            order.status = LibEveMarket.DelayedOrderStatus.Filled;
        } else if (sell.baseSold != 0) {
            order.status = LibEveMarket.DelayedOrderStatus.PartiallyFilled;
        } else {
            order.status = LibEveMarket.DelayedOrderStatus.Cancelled;
        }
        LibDelayedOrder.advanceHead(order.bookId);
        _emitProcessed(orderId, order, msg.sender, sell.baseSold, sell.quoteOut, 0, 0, restingCurveId, sell.feePaid);
    }

    function _executeDelayedBuyFill(
        LibEveMarket.DelayedOrder storage order,
        PreparedRoute memory prepared,
        uint128 minBaseOut,
        uint128 maxAveragePrice
    ) private returns (CurveCLOBTypes.FillBestResult memory fill) {
        LibDelayedOrder.setActiveProcessor(msg.sender);
        fill = LibBuyExecution.fillBookBest(
            CurveCLOBTypes.FillBookParams({
                bookId: order.bookId,
                maxQuoteIn: order.remainingAmount,
                minBaseOut: minBaseOut,
                maxAveragePrice: maxAveragePrice,
                curveIds: prepared.curveIds,
                expectedGenerations: prepared.expectedGenerations,
                expectedCommitments: prepared.expectedCommitments,
                payer: address(this),
                receiver: order.owner
            }),
            LibBuyExecution.FillMode.BestAsk
        );
        LibDelayedOrder.setActiveProcessor(address(0));
    }

    function _executeDelayedSellFill(
        LibEveMarket.DelayedOrder storage order,
        PreparedRoute memory prepared,
        uint128 minQuoteOut
    ) private returns (CurveCLOBTypes.SellBookResult memory sell) {
        LibDelayedOrder.setActiveProcessor(msg.sender);
        sell = LibSellExecution.sellBookBest(
            CurveCLOBTypes.SellBookParams({
                bookId: order.bookId,
                maxBaseIn: order.remainingAmount,
                minQuoteOut: minQuoteOut,
                curveIds: prepared.curveIds,
                expectedGenerations: prepared.expectedGenerations,
                expectedCommitments: prepared.expectedCommitments,
                receiver: order.owner
            }),
            CurveCLOBTypes.SellExecutionContext({
                source: address(this), seller: order.owner, receiver: order.owner, useEscrowedBase: true
            })
        );
        LibDelayedOrder.setActiveProcessor(address(0));
    }

    function _restLimitBuyRemainder(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.DelayedOrder storage order,
        LibEveMarket.Book storage book,
        uint128 remainingQuote
    ) private returns (uint256 restingCurveId, uint128 creditedQuote) {
        if (remainingQuote == 0) {
            return (0, 0);
        }

        (uint128 volume, uint128 dust) =
            LibDelayedOrder.bidVolumeFromEscrow(remainingQuote, order.limitPrice, book.priceDenominator);
        creditedQuote = dust;
        uint128 quoteEscrow = remainingQuote - dust;
        if (volume == 0 || quoteEscrow == 0) {
            LibDelayedOrder.creditQuote(order.owner, book.quoteToken, remainingQuote);
            return (0, remainingQuote);
        }

        if (dust != 0) {
            LibDelayedOrder.creditQuote(order.owner, book.quoteToken, dust);
        }
        restingCurveId = LibCurveStorage.createFlatCurveFromEscrow(
            state,
            LibCurveStorage.FlatCurveFromEscrowParams({
                bookId: order.bookId,
                maker: order.owner,
                curveSide: LibEveMarket.CurveSide.BID,
                volume: volume,
                quoteEscrow: quoteEscrow,
                price: uint72(order.limitPrice),
                durationMinutes: state.config.delayedOrderRestingDurationMinutes
            })
        );
    }

    function _cancelBuy(
        uint256 orderId,
        LibEveMarket.DelayedOrder storage order,
        LibEveMarket.Book storage book,
        uint128 filledIn,
        uint128 filledOut,
        uint128 feePaid
    ) private {
        uint128 creditedQuote = order.remainingAmount;
        if (creditedQuote != 0) {
            LibDelayedOrder.creditQuote(order.owner, book.quoteToken, creditedQuote);
        }
        order.remainingAmount = 0;
        order.status = LibEveMarket.DelayedOrderStatus.Cancelled;
        LibDelayedOrder.advanceHead(order.bookId);
        _emitProcessed(orderId, order, msg.sender, filledIn, filledOut, creditedQuote, 0, 0, feePaid);
    }

    function _restLimitSellRemainder(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.DelayedOrder storage order,
        uint128 remainingBase
    ) private returns (uint256 restingCurveId) {
        if (remainingBase == 0) {
            return 0;
        }

        restingCurveId = LibCurveStorage.createFlatCurveFromEscrow(
            state,
            LibCurveStorage.FlatCurveFromEscrowParams({
                bookId: order.bookId,
                maker: order.owner,
                curveSide: LibEveMarket.CurveSide.ASK,
                volume: remainingBase,
                quoteEscrow: 0,
                price: uint72(order.limitPrice),
                durationMinutes: state.config.delayedOrderRestingDurationMinutes
            })
        );
    }

    function _cancelSell(
        uint256 orderId,
        LibEveMarket.DelayedOrder storage order,
        LibEveMarket.Book storage book,
        uint128 filledIn,
        uint128 filledOut,
        uint128 feePaid
    ) private {
        uint128 creditedBase = order.remainingAmount;
        if (creditedBase != 0) {
            _creditBase(order.owner, book, creditedBase);
        }
        order.remainingAmount = 0;
        order.status = LibEveMarket.DelayedOrderStatus.Cancelled;
        LibDelayedOrder.advanceHead(order.bookId);
        _emitProcessed(orderId, order, msg.sender, filledIn, filledOut, 0, creditedBase, 0, feePaid);
    }

    function _expireHeadOrder(uint256 orderId, LibEveMarket.DelayedOrder storage order, uint64 sequence) private {
        if (order.sequence != sequence) {
            revert Errors.InvalidAmount(sequence);
        }

        LibEveMarket.Book storage book = LibEveMarket.store().books[order.bookId];
        uint128 creditedQuote;
        uint128 creditedBase;
        if (_isBuyOrder(order.kind)) {
            creditedQuote = order.remainingAmount;
            if (creditedQuote != 0) {
                LibDelayedOrder.creditQuote(order.owner, book.quoteToken, creditedQuote);
            }
        } else {
            creditedBase = order.remainingAmount;
            if (creditedBase != 0) {
                _creditBase(order.owner, book, creditedBase);
            }
        }
        order.remainingAmount = 0;
        order.status = LibEveMarket.DelayedOrderStatus.Expired;
        LibDelayedOrder.advanceHead(order.bookId);
        emit Events.DelayedOrderExpired(orderId, order.bookId, order.owner, creditedQuote, creditedBase);
        _emitProcessed(orderId, order, msg.sender, 0, 0, creditedQuote, creditedBase, 0, 0);
    }

    function _prepareValidAskRoute(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.DelayedOrder storage order,
        LibEveMarket.Book storage book,
        DelayedOrderRoute calldata route
    ) private view returns (PreparedRoute memory prepared) {
        uint256 validCount;
        bool hasLimit = order.kind == LibEveMarket.DelayedOrderKind.LimitBuy;
        for (uint256 index; index < route.curveIds.length; ++index) {
            if (_isValidAskRouteEntry(state, order, book, route, index, hasLimit)) {
                validCount += 1;
            }
        }

        prepared.curveIds = new uint256[](validCount);
        prepared.expectedGenerations = new uint32[](validCount);
        prepared.expectedCommitments = new bytes32[](validCount);
        uint256 writeIndex;
        for (uint256 index; index < route.curveIds.length; ++index) {
            if (!_isValidAskRouteEntry(state, order, book, route, index, hasLimit)) {
                continue;
            }
            prepared.curveIds[writeIndex] = route.curveIds[index];
            prepared.expectedGenerations[writeIndex] = route.expectedGenerations[index];
            prepared.expectedCommitments[writeIndex] = route.expectedCommitments[index];
            writeIndex += 1;
        }
    }

    function _isValidAskRouteEntry(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.DelayedOrder storage order,
        LibEveMarket.Book storage book,
        DelayedOrderRoute calldata route,
        uint256 index,
        bool hasLimit
    ) private view returns (bool) {
        LibEveMarket.StoredCurve storage curve = state.curves[route.curveIds[index]];
        if (
            curve.bookId != order.bookId || !curve.active || curve.curveSide != LibEveMarket.CurveSide.ASK
                || curve.remainingVolume == 0 || curve.maker == order.owner
                || route.expectedGenerations[index] != curve.generation
                || route.expectedCommitments[index] != LibCurveMath.curveCommitment(curve.packed)
                || LibCurveMath.isExpired(state, curve)
        ) {
            return false;
        }
        if (hasLimit && LibCurveMath.currentPrice(state, curve) > order.limitPrice) {
            return false;
        }
        return book.bookId == order.bookId && LibCLOBBook.canExecute(book);
    }

    function _prepareValidBidRoute(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.DelayedOrder storage order,
        LibEveMarket.Book storage book,
        DelayedOrderRoute calldata route
    ) private view returns (PreparedRoute memory prepared) {
        uint256 validCount;
        bool hasLimit = order.kind == LibEveMarket.DelayedOrderKind.LimitSell;
        for (uint256 index; index < route.curveIds.length; ++index) {
            if (_isValidBidRouteEntry(state, order, book, route, index, hasLimit)) {
                validCount += 1;
            }
        }

        prepared.curveIds = new uint256[](validCount);
        prepared.expectedGenerations = new uint32[](validCount);
        prepared.expectedCommitments = new bytes32[](validCount);
        uint256 writeIndex;
        for (uint256 index; index < route.curveIds.length; ++index) {
            if (!_isValidBidRouteEntry(state, order, book, route, index, hasLimit)) {
                continue;
            }
            prepared.curveIds[writeIndex] = route.curveIds[index];
            prepared.expectedGenerations[writeIndex] = route.expectedGenerations[index];
            prepared.expectedCommitments[writeIndex] = route.expectedCommitments[index];
            writeIndex += 1;
        }
    }

    function _isValidBidRouteEntry(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.DelayedOrder storage order,
        LibEveMarket.Book storage book,
        DelayedOrderRoute calldata route,
        uint256 index,
        bool hasLimit
    ) private view returns (bool) {
        LibEveMarket.StoredCurve storage curve = state.curves[route.curveIds[index]];
        if (
            curve.bookId != order.bookId || !curve.active || curve.curveSide != LibEveMarket.CurveSide.BID
                || curve.remainingVolume == 0 || curve.quoteEscrowRemaining == 0 || curve.maker == order.owner
                || route.expectedGenerations[index] != curve.generation
                || route.expectedCommitments[index] != LibCurveMath.curveCommitment(curve.packed)
                || LibCurveMath.isExpired(state, curve)
        ) {
            return false;
        }
        if (hasLimit && LibCurveMath.currentPrice(state, curve) < order.limitPrice) {
            return false;
        }
        return book.bookId == order.bookId && LibCLOBBook.canExecute(book);
    }

    function _previewFill(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.Book storage book,
        uint128 maxQuoteIn,
        PreparedRoute memory prepared,
        uint128 maxAveragePrice
    ) private view returns (FillPreview memory preview) {
        preview.unfilledCollateral = maxQuoteIn;
        for (uint256 index; index < prepared.curveIds.length && preview.unfilledCollateral != 0; ++index) {
            LibEveMarket.StoredCurve storage curve = state.curves[prepared.curveIds[index]];
            (uint128 sharesOut, uint128 feePaid,, uint128 collateralUsed) =
                LibCurveMath.quoteAsk(state, curve, preview.unfilledCollateral);
            if (sharesOut == 0) {
                continue;
            }
            preview.sharesOut += sharesOut;
            preview.feePaid += feePaid;
            preview.collateralUsed += collateralUsed;
            preview.unfilledCollateral -= collateralUsed;
        }
        if (preview.sharesOut != 0) {
            preview.averagePrice = LibBookPricing.averagePrice(book, preview.collateralUsed, preview.sharesOut);
        }
        if (preview.averagePrice > maxAveragePrice) {
            preview.sharesOut = 0;
        }
    }

    function _previewSell(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.Book storage book,
        uint128 maxBaseIn,
        PreparedRoute memory prepared,
        uint128 minCurvePrice
    ) private view returns (SellPreview memory preview) {
        preview.unfilledBase = maxBaseIn;
        for (uint256 index; index < prepared.curveIds.length && preview.unfilledBase != 0; ++index) {
            LibEveMarket.StoredCurve storage curve = state.curves[prepared.curveIds[index]];
            uint128 price = LibCurveMath.currentPrice(state, curve);
            if (price == 0 || price < minCurvePrice) {
                continue;
            }

            uint256 shares = preview.unfilledBase;
            if (shares > curve.remainingVolume) {
                shares = curve.remainingVolume;
            }
            uint256 maxSharesByEscrow =
                (uint256(curve.quoteEscrowRemaining) * uint256(book.priceDenominator)) / uint256(price);
            if (shares > maxSharesByEscrow) {
                shares = maxSharesByEscrow;
            }
            if (shares == 0) {
                continue;
            }

            uint128 sharesOut = uint128(shares);
            uint128 grossCost = LibBookPricing.grossCostFor(book, sharesOut, price);
            uint128 fee = uint128((uint256(grossCost) * uint256(book.feeConfig.entryFeeBps)) / 10_000);
            if (fee > grossCost) {
                continue;
            }

            preview.baseSold += sharesOut;
            preview.feePaid += fee;
            preview.quoteOut += grossCost - fee;
            preview.unfilledBase -= sharesOut;
        }
        if (preview.baseSold != 0) {
            preview.averagePrice = LibBookPricing.averagePrice(book, preview.quoteOut, preview.baseSold);
        }
    }

    function _tryHeadOrder(bytes32 bookId) private view returns (uint64 sequence, uint256 orderId, bool hasHead) {
        (uint64 head, uint64 tail) = LibDelayedOrder.queueBounds(bookId);
        if (head >= tail) {
            return (head, 0, false);
        }
        sequence = head;
        orderId = LibDelayedOrder.orderIdBySequence(bookId, head);
        hasHead = orderId != 0;
    }

    function _emitProcessed(
        uint256 orderId,
        LibEveMarket.DelayedOrder storage order,
        address processor,
        uint128 filledIn,
        uint128 filledOut,
        uint128 creditedQuote,
        uint128 creditedBase,
        uint256 restingCurveId,
        uint128 feePaid
    ) private {
        uint128 processorReward;
        if (feePaid != 0 && LibEveMarket.store().config.delayedOrderProcessorFeeShareBps != 0) {
            processorReward =
                uint128((uint256(feePaid) * LibEveMarket.store().config.delayedOrderProcessorFeeShareBps) / 10_000);
        }
        emit Events.DelayedOrderProcessed(
            orderId,
            order.bookId,
            order.owner,
            processor,
            uint8(order.status),
            filledIn,
            filledOut,
            creditedQuote,
            creditedBase,
            processorReward,
            restingCurveId
        );
    }

    function _creditBase(address owner, LibEveMarket.Book storage book, uint128 amount) private {
        LibDelayedOrder.creditBase(owner, book.assetType, book.baseToken, book.baseTokenId, amount);
    }

    function _lockedQuote(address owner, address token) private view returns (uint256 locked) {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        uint256 nextOrderId = state.delayedOrders.nextOrderId;
        for (uint256 orderId = 1; orderId <= nextOrderId; ++orderId) {
            LibEveMarket.DelayedOrder storage order = state.delayedOrders.orders[orderId];
            if (
                order.owner == owner && order.status == LibEveMarket.DelayedOrderStatus.Pending
                    && _isBuyOrder(order.kind) && state.books[order.bookId].quoteToken == token
            ) {
                locked += order.remainingAmount;
            }
        }
    }

    function _lockedBase(address owner, LibEveMarket.BookAssetType assetType, address token, uint256 tokenId)
        private
        view
        returns (uint256 locked)
    {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        uint256 nextOrderId = state.delayedOrders.nextOrderId;
        for (uint256 orderId = 1; orderId <= nextOrderId; ++orderId) {
            LibEveMarket.DelayedOrder storage order = state.delayedOrders.orders[orderId];
            LibEveMarket.Book storage book = state.books[order.bookId];
            if (
                order.owner == owner && order.status == LibEveMarket.DelayedOrderStatus.Pending
                    && !_isBuyOrder(order.kind) && book.assetType == assetType && book.baseToken == token
                    && book.baseTokenId == tokenId
            ) {
                locked += order.remainingAmount;
            }
        }
    }

    function _isSupportedDelayedKind(LibEveMarket.DelayedOrderKind kind) private pure returns (bool supported) {
        supported = kind == LibEveMarket.DelayedOrderKind.MarketBuy || kind == LibEveMarket.DelayedOrderKind.LimitBuy
            || kind == LibEveMarket.DelayedOrderKind.MarketSell || kind == LibEveMarket.DelayedOrderKind.LimitSell;
    }

    function _isBuyOrder(LibEveMarket.DelayedOrderKind kind) private pure returns (bool buyOrder) {
        buyOrder = kind == LibEveMarket.DelayedOrderKind.MarketBuy || kind == LibEveMarket.DelayedOrderKind.LimitBuy;
    }

    function _isLimitOrder(LibEveMarket.DelayedOrderKind kind) private pure returns (bool limitOrder) {
        limitOrder = kind == LibEveMarket.DelayedOrderKind.LimitBuy || kind == LibEveMarket.DelayedOrderKind.LimitSell;
    }

    function _recordSubmittedOrder(
        SubmitDelayedOrderParams calldata params,
        bytes32 marketId,
        SubmissionSchedule memory schedule,
        bytes32 hash
    ) private returns (uint256 orderId, uint64 sequence) {
        (orderId, sequence) = LibDelayedOrder.recordSubmittedOrder(
            msg.sender,
            params.bookId,
            marketId,
            params.kind,
            params.amountIn,
            params.limitPrice,
            params.minOut,
            params.maxAveragePrice,
            schedule.submitBlock,
            schedule.executableBlock,
            schedule.expiryBlock,
            hash
        );
    }

    function _emitSubmitted(uint256 orderId, uint64 sequence, SubmitDelayedOrderParams calldata params, bytes32 hash)
        private
    {
        emit Events.DelayedOrderSubmitted(
            orderId,
            params.bookId,
            msg.sender,
            uint8(params.kind),
            params.amountIn,
            params.limitPrice,
            sequence,
            hash,
            params.curveIds,
            params.expectedGenerations,
            params.expectedCommitments
        );
    }

    function _submissionSchedule(LibEveMarket.MarketConfig storage config)
        private
        view
        returns (SubmissionSchedule memory schedule)
    {
        schedule.submitBlock = _currentBlock();
        schedule.executableBlock = schedule.submitBlock + config.delayedOrderProtectionDelayBlocks;
        schedule.expiryBlock = schedule.executableBlock + config.delayedOrderExecutionGraceBlocks;
    }

    function _currentBlock() private view returns (uint64 currentBlock) {
        if (block.number > type(uint64).max) {
            revert Errors.InvalidAmount(block.number);
        }
        currentBlock = uint64(block.number);
    }
}
