// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IMultiOutcomeOrderbookFacet} from "../interfaces/IMultiOutcomeOrderbookFacet.sol";
import {LibCurveMath} from "../libraries/LibCurveMath.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibMultiOutcome} from "../libraries/LibMultiOutcome.sol";

contract MultiOutcomeOrderbookViewFacet {
    function getMultiOutcomeMarket(bytes32 marketId)
        external
        view
        returns (IMultiOutcomeOrderbookFacet.MultiOutcomeMarketView memory marketView)
    {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.MultiOutcomeMarket storage market = LibMultiOutcome.requireMultiOutcome(state, marketId);
        LibEveMarket.Market storage coreMarket = state.markets[marketId];

        marketView = IMultiOutcomeOrderbookFacet.MultiOutcomeMarketView({
            marketId: market.marketId,
            conditionId: market.conditionId,
            outcomesHash: market.outcomesHash,
            positionToken: coreMarket.positionToken,
            collateralToken: coreMarket.collateralToken,
            marketType: uint8(coreMarket.marketType),
            positionTokenType: uint8(coreMarket.positionTokenType),
            collateralProfileId: coreMarket.collateralProfileId,
            outcomeCount: market.outcomeCount,
            payoutUnit: coreMarket.payoutUnit,
            resolvedOutcome: market.resolvedOutcome,
            payoutDenominator: market.payoutDenominator,
            invalid: market.invalid,
            resolved: market.resolved
        });
    }

    function getMultiOutcomeOutcomes(bytes32 marketId) external view returns (string[] memory outcomes) {
        LibMultiOutcome.requireMultiOutcome(LibEveMarket.store(), marketId);
        outcomes = LibEveMarket.store().multiOutcomeLabels[marketId];
    }

    function getMultiOutcomeDisplay(bytes32 marketId, uint8 outcome)
        external
        view
        returns (IMultiOutcomeOrderbookFacet.OutcomeDisplayView memory displayView)
    {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.MultiOutcomeMarket storage multi = LibMultiOutcome.requireMultiOutcome(state, marketId);
        LibMultiOutcome.requireOutcome(multi, outcome);
        LibEveMarket.MultiOutcomeDisplay storage display = state.multiOutcomeDisplays[marketId][outcome];
        displayView = IMultiOutcomeOrderbookFacet.OutcomeDisplayView({
            slug: display.slug,
            displayLabel: display.displayLabel,
            abbreviation: display.abbreviation,
            iconUrl: display.iconUrl,
            externalRefHash: display.externalRefHash,
            exists: display.exists
        });
    }

    function getOutcomePositionId(bytes32 marketId, uint8 outcome) external view returns (uint256 positionId) {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.MultiOutcomeMarket storage market = LibMultiOutcome.requireMultiOutcome(state, marketId);
        LibMultiOutcome.requireOutcome(market, outcome);
        positionId = state.multiOutcomePositionIds[marketId][outcome];
    }

    function getMultiOutcomeBooks(bytes32 marketId) external view returns (bytes32[] memory bookIds) {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.MultiOutcomeMarket storage multi = LibMultiOutcome.requireMultiOutcome(state, marketId);
        bookIds = new bytes32[](multi.outcomeCount);

        for (uint8 outcome; outcome < multi.outcomeCount; ++outcome) {
            bookIds[outcome] = state.multiOutcomeBookIds[marketId][outcome];
        }
    }

    function getMultiOutcomeTopOfBook(bytes32 marketId)
        external
        view
        returns (
            uint128[] memory bestAskPrices,
            uint128[] memory bestBidPrices,
            uint128[] memory midpointPrices,
            uint128[] memory lastTradePrices
        )
    {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.MultiOutcomeMarket storage multi = LibMultiOutcome.requireMultiOutcome(state, marketId);
        bestAskPrices = new uint128[](multi.outcomeCount);
        bestBidPrices = new uint128[](multi.outcomeCount);
        midpointPrices = new uint128[](multi.outcomeCount);
        lastTradePrices = new uint128[](multi.outcomeCount);

        for (uint8 outcome; outcome < multi.outcomeCount; ++outcome) {
            bytes32 bookId = state.multiOutcomeBookIds[marketId][outcome];
            if (bookId == bytes32(0)) {
                continue;
            }
            LibEveMarket.Book storage book = state.books[bookId];
            if (book.bookId != bookId) {
                continue;
            }
            (bestAskPrices[outcome], bestBidPrices[outcome], midpointPrices[outcome], lastTradePrices[outcome]) =
                _bookTopOfBook(state, bookId, book.lastTradePrice);
        }
    }

    function _bookTopOfBook(LibEveMarket.EveMarketStorage storage state, bytes32 bookId, uint96 lastTradePrice)
        internal
        view
        returns (uint128 bestAskPrice, uint128 bestBidPrice, uint128 midpointPrice, uint128 lastTradePrice_)
    {
        uint256[] storage ids = state.bookCurveIds[bookId];
        for (uint256 index; index < ids.length; ++index) {
            LibEveMarket.StoredCurve storage curve = state.curves[ids[index]];
            if (!curve.active || curve.remainingVolume == 0) {
                continue;
            }
            uint128 price = LibCurveMath.currentPrice(state, curve);
            if (curve.curveSide == LibEveMarket.CurveSide.ASK) {
                if (bestAskPrice == 0 || price < bestAskPrice) bestAskPrice = price;
            } else if (price > bestBidPrice) {
                bestBidPrice = price;
            }
        }

        if (bestAskPrice != 0 && bestBidPrice != 0) {
            midpointPrice = (bestAskPrice + bestBidPrice) / 2;
        }
        lastTradePrice_ = uint128(lastTradePrice);
    }
}
