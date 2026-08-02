// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {DelayedOrderTypes} from "../types/DelayedOrderTypes.sol";
import {Errors} from "./Errors.sol";
import {LibBookPricing} from "./LibBookPricing.sol";
import {LibCLOBBook} from "./LibCLOBBook.sol";
import {LibCurveMath} from "./LibCurveMath.sol";
import {LibEveMarket} from "./LibEveMarket.sol";
import {LibMLOPredictionFill} from "./LibMLOPredictionFill.sol";
import {LibMLORecovery} from "./LibMLORecovery.sol";
import {LibProductAdapter} from "./LibProductAdapter.sol";

library LibDelayedOrderRoute {
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

    function requireSupportedExecutableBook(LibEveMarket.Book storage book, bytes32 bookId) public view {
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

    function prepareValidAskRoute(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.DelayedOrder storage order,
        LibEveMarket.Book storage book,
        DelayedOrderTypes.DelayedOrderRoute calldata route
    ) public returns (PreparedRoute memory prepared) {
        for (uint256 index; index < route.curveIds.length; ++index) {
            LibMLORecovery.maintainCurve(state, route.curveIds[index]);
        }
        uint256 validCount;
        bool hasLimit = order.kind == LibEveMarket.DelayedOrderKind.LimitBuy;
        for (uint256 index; index < route.curveIds.length; ++index) {
            if (isValidAskRouteEntry(state, order, book, route, index, hasLimit)) {
                validCount += 1;
            }
        }

        prepared.curveIds = new uint256[](validCount);
        prepared.expectedGenerations = new uint32[](validCount);
        prepared.expectedCommitments = new bytes32[](validCount);
        uint256 writeIndex;
        for (uint256 index; index < route.curveIds.length; ++index) {
            if (!isValidAskRouteEntry(state, order, book, route, index, hasLimit)) {
                continue;
            }
            prepared.curveIds[writeIndex] = route.curveIds[index];
            prepared.expectedGenerations[writeIndex] = route.expectedGenerations[index];
            prepared.expectedCommitments[writeIndex] = route.expectedCommitments[index];
            writeIndex += 1;
        }
    }

    function isValidAskRouteEntry(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.DelayedOrder storage order,
        LibEveMarket.Book storage book,
        DelayedOrderTypes.DelayedOrderRoute calldata route,
        uint256 index,
        bool hasLimit
    ) public view returns (bool) {
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
        if (!LibProductAdapter.isEscrowBackedCurve(state, route.curveIds[index])) {
            return LibMLOPredictionFill.isExecutableMLOAsk(state, route.curveIds[index]);
        }
        return book.bookId == order.bookId && LibCLOBBook.canExecute(book);
    }

    function prepareValidBidRoute(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.DelayedOrder storage order,
        LibEveMarket.Book storage book,
        DelayedOrderTypes.DelayedOrderRoute calldata route
    ) public returns (PreparedRoute memory prepared) {
        for (uint256 index; index < route.curveIds.length; ++index) {
            LibMLORecovery.maintainCurve(state, route.curveIds[index]);
        }
        uint256 validCount;
        bool hasLimit = order.kind == LibEveMarket.DelayedOrderKind.LimitSell;
        for (uint256 index; index < route.curveIds.length; ++index) {
            if (isValidBidRouteEntry(state, order, book, route, index, hasLimit)) {
                validCount += 1;
            }
        }

        prepared.curveIds = new uint256[](validCount);
        prepared.expectedGenerations = new uint32[](validCount);
        prepared.expectedCommitments = new bytes32[](validCount);
        uint256 writeIndex;
        for (uint256 index; index < route.curveIds.length; ++index) {
            if (!isValidBidRouteEntry(state, order, book, route, index, hasLimit)) {
                continue;
            }
            prepared.curveIds[writeIndex] = route.curveIds[index];
            prepared.expectedGenerations[writeIndex] = route.expectedGenerations[index];
            prepared.expectedCommitments[writeIndex] = route.expectedCommitments[index];
            writeIndex += 1;
        }
    }

    function isValidBidRouteEntry(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.DelayedOrder storage order,
        LibEveMarket.Book storage book,
        DelayedOrderTypes.DelayedOrderRoute calldata route,
        uint256 index,
        bool hasLimit
    ) public view returns (bool) {
        LibEveMarket.StoredCurve storage curve = state.curves[route.curveIds[index]];
        if (
            curve.bookId != order.bookId || !curve.active || curve.curveSide != LibEveMarket.CurveSide.BID
                || curve.remainingVolume == 0 || curve.maker == order.owner
                || route.expectedGenerations[index] != curve.generation
                || route.expectedCommitments[index] != LibCurveMath.curveCommitment(curve.packed)
                || LibCurveMath.isExpired(state, curve)
        ) {
            return false;
        }
        if (LibProductAdapter.isEscrowBackedCurve(state, route.curveIds[index])
                ? curve.quoteEscrowRemaining == 0
                : state.mloCurveSeniorReserved[route.curveIds[index]] == 0) return false;
        if (hasLimit && LibCurveMath.currentPrice(state, curve) < order.limitPrice) {
            return false;
        }
        return book.bookId == order.bookId && LibCLOBBook.canExecute(book);
    }

    function previewFill(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.Book storage book,
        uint128 maxQuoteIn,
        PreparedRoute memory prepared,
        uint128 maxAveragePrice
    ) public view returns (FillPreview memory preview) {
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

    function previewSell(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.Book storage book,
        uint128 maxBaseIn,
        PreparedRoute memory prepared,
        uint128 minCurvePrice
    ) public view returns (SellPreview memory preview) {
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
            if (LibProductAdapter.isEscrowBackedCurve(state, prepared.curveIds[index])) {
                uint256 maxSharesByEscrow =
                    (uint256(curve.quoteEscrowRemaining) * uint256(book.priceDenominator)) / uint256(price);
                if (shares > maxSharesByEscrow) shares = maxSharesByEscrow;
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
}
