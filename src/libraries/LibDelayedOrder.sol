// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC1155} from "../../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";

import {Errors} from "./Errors.sol";
import {Events} from "./Events.sol";
import {LibEveMarket} from "./LibEveMarket.sol";
import {LibSafeCast} from "./LibSafeCast.sol";
import {DelayedOrderTypes} from "../types/DelayedOrderTypes.sol";

library LibDelayedOrder {
    using SafeERC20 for IERC20;

    uint8 internal constant CREDIT_ASSET_QUOTE = 0;
    uint8 internal constant CREDIT_ASSET_BASE_ERC20 = 1;
    uint8 internal constant CREDIT_ASSET_BASE_ERC1155 = 2;

    function store() internal view returns (LibEveMarket.DelayedOrderStorage storage storage_) {
        storage_ = LibEveMarket.store().delayedOrders;
    }

    function bidVolumeFromEscrow(uint128 quoteEscrow, uint128 limitPrice, uint128 priceDenominator)
        internal
        pure
        returns (uint128 volume, uint128 dust)
    {
        if (limitPrice == 0 || priceDenominator == 0) {
            revert Errors.InvalidAmount(0);
        }

        volume = LibSafeCast.toUint128((uint256(quoteEscrow) * uint256(priceDenominator)) / uint256(limitPrice));
        uint256 representedEscrow = (uint256(volume) * uint256(limitPrice)) / uint256(priceDenominator);
        dust = uint128(uint256(quoteEscrow) - representedEscrow);
    }

    function routeHash(
        uint256[] calldata curveIds,
        uint32[] calldata expectedGenerations,
        bytes32[] calldata expectedCommitments
    ) internal pure returns (bytes32 hash) {
        if (curveIds.length != expectedGenerations.length) {
            revert Errors.ArrayLengthMismatch(curveIds.length, expectedGenerations.length);
        }
        if (curveIds.length != expectedCommitments.length) {
            revert Errors.ArrayLengthMismatch(curveIds.length, expectedCommitments.length);
        }

        hash = keccak256(abi.encode(curveIds, expectedGenerations, expectedCommitments));
    }

    function routeHashMemory(
        uint256[] memory curveIds,
        uint32[] memory expectedGenerations,
        bytes32[] memory expectedCommitments
    ) internal pure returns (bytes32 hash) {
        if (curveIds.length != expectedGenerations.length) {
            revert Errors.ArrayLengthMismatch(curveIds.length, expectedGenerations.length);
        }
        if (curveIds.length != expectedCommitments.length) {
            revert Errors.ArrayLengthMismatch(curveIds.length, expectedCommitments.length);
        }

        hash = keccak256(abi.encode(curveIds, expectedGenerations, expectedCommitments));
    }

    function isExecutable(LibEveMarket.DelayedOrder storage order, uint256 currentBlock)
        internal
        view
        returns (bool executable)
    {
        executable = order.status == LibEveMarket.DelayedOrderStatus.Pending && currentBlock >= order.executableBlock
            && currentBlock <= order.expiryBlock;
    }

    function isExpired(LibEveMarket.DelayedOrder storage order, uint256 currentBlock)
        internal
        view
        returns (bool expired)
    {
        expired = order.status == LibEveMarket.DelayedOrderStatus.Pending && currentBlock > order.expiryBlock;
    }

    function nextOrderId() internal returns (uint256 orderId) {
        LibEveMarket.DelayedOrderStorage storage storage_ = store();
        orderId = storage_.nextOrderId + 1;
        storage_.nextOrderId = orderId;
    }

    function appendOrder(bytes32 bookId, uint256 orderId) internal returns (uint64 sequence) {
        if (bookId == bytes32(0) || orderId == 0) {
            revert Errors.InvalidAmount(orderId);
        }

        LibEveMarket.DelayedOrderStorage storage storage_ = store();
        LibEveMarket.DelayedOrderQueue storage queue = storage_.queues[bookId];
        sequence = queue.tail;
        storage_.orderBySequence[bookId][sequence] = orderId;
        queue.tail = sequence + 1;
    }

    function advanceHead(bytes32 bookId) internal returns (uint64 head) {
        LibEveMarket.DelayedOrderQueue storage queue = store().queues[bookId];
        if (queue.head >= queue.tail) {
            revert Errors.DelayedOrderQueueEmpty(bookId);
        }

        head = queue.head + 1;
        queue.head = head;
    }

    function headOrderId(bytes32 bookId) internal view returns (uint64 sequence, uint256 orderId) {
        LibEveMarket.DelayedOrderStorage storage storage_ = store();
        LibEveMarket.DelayedOrderQueue storage queue = storage_.queues[bookId];
        if (queue.head >= queue.tail) {
            revert Errors.DelayedOrderQueueEmpty(bookId);
        }

        sequence = queue.head;
        orderId = storage_.orderBySequence[bookId][sequence];
    }

    function orderIdBySequence(bytes32 bookId, uint64 sequence) internal view returns (uint256 orderId) {
        orderId = store().orderBySequence[bookId][sequence];
    }

    function setProtocolProcessor(address processor, bool allowed) internal {
        if (processor == address(0)) {
            revert Errors.ZeroAddress();
        }
        store().protocolProcessors[processor] = allowed;
    }

    function isProtocolProcessor(address processor) internal view returns (bool allowed) {
        allowed = store().protocolProcessors[processor];
    }

    function setActiveProcessor(address processor) internal {
        store().activeProcessor = processor;
    }

    function activeProcessor() internal view returns (address processor) {
        processor = store().activeProcessor;
    }

    function queueBounds(bytes32 bookId) internal view returns (uint64 head, uint64 tail) {
        LibEveMarket.DelayedOrderQueue storage queue = store().queues[bookId];
        head = queue.head;
        tail = queue.tail;
    }

    function delayedOrderView(uint256 orderId) internal view returns (DelayedOrderTypes.DelayedOrderView memory view_) {
        LibEveMarket.DelayedOrder storage order = store().orders[orderId];
        if (order.owner == address(0)) {
            revert Errors.DelayedOrderNotFound(orderId);
        }

        view_ = DelayedOrderTypes.DelayedOrderView({
            orderId: orderId,
            owner: order.owner,
            bookId: order.bookId,
            marketId: order.marketId,
            kind: order.kind,
            status: order.status,
            amountIn: order.amountIn,
            remainingAmount: order.remainingAmount,
            limitPrice: order.limitPrice,
            minOut: order.minOut,
            maxAveragePrice: order.maxAveragePrice,
            submitBlock: order.submitBlock,
            executableBlock: order.executableBlock,
            expiryBlock: order.expiryBlock,
            sequence: order.sequence,
            routeHash: order.routeHash,
            restingCurveId: order.restingCurveId,
            executable: isExecutable(order, block.number),
            expired: isExpired(order, block.number)
        });
    }

    function recordSubmittedOrder(
        address owner,
        bytes32 bookId,
        bytes32 marketId,
        LibEveMarket.DelayedOrderKind kind,
        uint128 amountIn,
        uint128 limitPrice,
        uint128 minOut,
        uint128 maxAveragePrice,
        uint64 submitBlock,
        uint64 executableBlock,
        uint64 expiryBlock,
        bytes32 hash
    ) internal returns (uint256 orderId, uint64 sequence) {
        orderId = nextOrderId();
        sequence = appendOrder(bookId, orderId);

        LibEveMarket.DelayedOrder storage order = store().orders[orderId];
        order.owner = owner;
        order.bookId = bookId;
        order.marketId = marketId;
        order.kind = kind;
        order.status = LibEveMarket.DelayedOrderStatus.Pending;
        order.amountIn = amountIn;
        order.remainingAmount = amountIn;
        order.limitPrice = limitPrice;
        order.minOut = minOut;
        order.maxAveragePrice = maxAveragePrice;
        order.submitBlock = submitBlock;
        order.executableBlock = executableBlock;
        order.expiryBlock = expiryBlock;
        order.sequence = sequence;
        order.routeHash = hash;
    }

    function quoteCredit(address owner, address token) internal view returns (uint128 amount) {
        amount = store().quoteCredit[owner][token];
    }

    function baseCredit(address owner, LibEveMarket.BookAssetType assetType, address token, uint256 tokenId)
        internal
        view
        returns (uint128 amount)
    {
        LibEveMarket.DelayedOrderStorage storage storage_ = store();
        if (assetType == LibEveMarket.BookAssetType.ERC20) {
            amount = storage_.baseERC20Credit[owner][token];
        } else if (assetType == LibEveMarket.BookAssetType.ERC1155) {
            amount = storage_.baseERC1155Credit[owner][token][tokenId];
        } else {
            revert Errors.UnsupportedCreditAssetType(uint8(assetType));
        }
    }

    function creditQuote(address owner, address token, uint128 amount) internal {
        if (amount == 0) {
            return;
        }
        _requireCreditAccount(owner, token);

        store().quoteCredit[owner][token] += amount;
        emit Events.UserCreditChanged(owner, CREDIT_ASSET_QUOTE, token, 0, int256(uint256(amount)));
    }

    function creditBase(
        address owner,
        LibEveMarket.BookAssetType assetType,
        address token,
        uint256 tokenId,
        uint128 amount
    ) internal {
        if (amount == 0) {
            return;
        }
        _requireCreditAccount(owner, token);

        LibEveMarket.DelayedOrderStorage storage storage_ = store();
        if (assetType == LibEveMarket.BookAssetType.ERC20) {
            if (tokenId != 0) {
                revert Errors.InvalidAmount(tokenId);
            }
            storage_.baseERC20Credit[owner][token] += amount;
            emit Events.UserCreditChanged(owner, CREDIT_ASSET_BASE_ERC20, token, 0, int256(uint256(amount)));
            return;
        }
        if (assetType == LibEveMarket.BookAssetType.ERC1155) {
            storage_.baseERC1155Credit[owner][token][tokenId] += amount;
            emit Events.UserCreditChanged(owner, CREDIT_ASSET_BASE_ERC1155, token, tokenId, int256(uint256(amount)));
            return;
        }

        revert Errors.UnsupportedCreditAssetType(uint8(assetType));
    }

    function debitQuote(address owner, address token, uint128 amount) internal returns (uint128 drawn) {
        if (amount == 0) {
            return 0;
        }
        _requireCreditAccount(owner, token);

        LibEveMarket.DelayedOrderStorage storage storage_ = store();
        uint128 available = storage_.quoteCredit[owner][token];
        drawn = amount < available ? amount : available;
        if (drawn == 0) {
            return 0;
        }

        storage_.quoteCredit[owner][token] = available - drawn;
        emit Events.UserCreditChanged(owner, CREDIT_ASSET_QUOTE, token, 0, -int256(uint256(drawn)));
    }

    function debitBase(
        address owner,
        LibEveMarket.BookAssetType assetType,
        address token,
        uint256 tokenId,
        uint128 amount
    ) internal returns (uint128 drawn) {
        if (amount == 0) {
            return 0;
        }
        _requireCreditAccount(owner, token);

        LibEveMarket.DelayedOrderStorage storage storage_ = store();
        if (assetType == LibEveMarket.BookAssetType.ERC20) {
            if (tokenId != 0) {
                revert Errors.InvalidAmount(tokenId);
            }
            uint128 available = storage_.baseERC20Credit[owner][token];
            drawn = amount < available ? amount : available;
            if (drawn != 0) {
                storage_.baseERC20Credit[owner][token] = available - drawn;
                emit Events.UserCreditChanged(owner, CREDIT_ASSET_BASE_ERC20, token, 0, -int256(uint256(drawn)));
            }
            return drawn;
        }
        if (assetType == LibEveMarket.BookAssetType.ERC1155) {
            uint128 available = storage_.baseERC1155Credit[owner][token][tokenId];
            drawn = amount < available ? amount : available;
            if (drawn != 0) {
                storage_.baseERC1155Credit[owner][token][tokenId] = available - drawn;
                emit Events.UserCreditChanged(owner, CREDIT_ASSET_BASE_ERC1155, token, tokenId, -int256(uint256(drawn)));
            }
            return drawn;
        }

        revert Errors.UnsupportedCreditAssetType(uint8(assetType));
    }

    function withdrawQuoteCredit(address owner, address token, uint128 amount) internal {
        _debitQuoteExact(owner, token, amount);
        IERC20(token).safeTransfer(owner, amount);
    }

    function withdrawBaseCredit(
        address owner,
        LibEveMarket.BookAssetType assetType,
        address token,
        uint256 tokenId,
        uint128 amount
    ) internal {
        _debitBaseExact(owner, assetType, token, tokenId, amount);
        if (assetType == LibEveMarket.BookAssetType.ERC20) {
            IERC20(token).safeTransfer(owner, amount);
        } else if (assetType == LibEveMarket.BookAssetType.ERC1155) {
            IERC1155(token).safeTransferFrom(address(this), owner, tokenId, amount, "");
        } else {
            revert Errors.UnsupportedCreditAssetType(uint8(assetType));
        }
    }

    function _debitQuoteExact(address owner, address token, uint128 amount) private {
        if (amount == 0) {
            revert Errors.InvalidAmount(0);
        }
        _requireCreditAccount(owner, token);

        LibEveMarket.DelayedOrderStorage storage storage_ = store();
        uint128 available = storage_.quoteCredit[owner][token];
        if (available < amount) {
            revert Errors.InsufficientCredit(owner, CREDIT_ASSET_QUOTE, token, 0, amount, available);
        }

        storage_.quoteCredit[owner][token] = available - amount;
        emit Events.UserCreditChanged(owner, CREDIT_ASSET_QUOTE, token, 0, -int256(uint256(amount)));
    }

    function _debitBaseExact(
        address owner,
        LibEveMarket.BookAssetType assetType,
        address token,
        uint256 tokenId,
        uint128 amount
    ) private {
        if (amount == 0) {
            revert Errors.InvalidAmount(0);
        }
        _requireCreditAccount(owner, token);

        LibEveMarket.DelayedOrderStorage storage storage_ = store();
        if (assetType == LibEveMarket.BookAssetType.ERC20) {
            if (tokenId != 0) {
                revert Errors.InvalidAmount(tokenId);
            }
            uint128 available = storage_.baseERC20Credit[owner][token];
            if (available < amount) {
                revert Errors.InsufficientCredit(owner, CREDIT_ASSET_BASE_ERC20, token, 0, amount, available);
            }
            storage_.baseERC20Credit[owner][token] = available - amount;
            emit Events.UserCreditChanged(owner, CREDIT_ASSET_BASE_ERC20, token, 0, -int256(uint256(amount)));
            return;
        }
        if (assetType == LibEveMarket.BookAssetType.ERC1155) {
            uint128 available = storage_.baseERC1155Credit[owner][token][tokenId];
            if (available < amount) {
                revert Errors.InsufficientCredit(owner, CREDIT_ASSET_BASE_ERC1155, token, tokenId, amount, available);
            }
            storage_.baseERC1155Credit[owner][token][tokenId] = available - amount;
            emit Events.UserCreditChanged(owner, CREDIT_ASSET_BASE_ERC1155, token, tokenId, -int256(uint256(amount)));
            return;
        }

        revert Errors.UnsupportedCreditAssetType(uint8(assetType));
    }

    function _requireCreditAccount(address owner, address token) private pure {
        if (owner == address(0) || token == address(0)) {
            revert Errors.ZeroAddress();
        }
    }
}
