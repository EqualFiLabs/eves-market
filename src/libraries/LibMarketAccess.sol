// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Errors} from "./Errors.sol";
import {LibCLOBBook} from "./LibCLOBBook.sol";
import {LibCTF} from "./LibCTF.sol";
import {LibEveMarket} from "./LibEveMarket.sol";

library LibMarketAccess {
    function requireExistingMarket(LibEveMarket.EveMarketStorage storage state, bytes32 marketId)
        internal
        view
        returns (LibEveMarket.Market storage market)
    {
        market = state.markets[marketId];
        if (market.marketId != marketId) {
            revert Errors.MarketNotFound(marketId);
        }
    }

    function requireTradingMarket(LibEveMarket.EveMarketStorage storage state, bytes32 marketId)
        internal
        view
        returns (LibEveMarket.Market storage market)
    {
        market = requireExistingMarket(state, marketId);
        if (!canExecute(market)) {
            revert Errors.MarketNotTrading(marketId);
        }
    }

    function requirePostableMarket(LibEveMarket.EveMarketStorage storage state, bytes32 marketId)
        internal
        view
        returns (LibEveMarket.Market storage market)
    {
        market = requireExistingMarket(state, marketId);
        if (!canPostToMarket(market)) {
            revert Errors.MarketNotTrading(marketId);
        }
    }

    function canExecute(LibEveMarket.Market storage market) internal view returns (bool) {
        return LibCLOBBook.canExecuteMarketBook(market);
    }

    function canPostToMarket(LibEveMarket.Market storage market) internal view returns (bool) {
        return LibCLOBBook.canPostToMarketBook(market);
    }

    function requirePositionTokenType(LibEveMarket.Market storage market, LibEveMarket.PositionTokenType expected)
        internal
        view
    {
        if (market.positionTokenType != expected) {
            revert Errors.PositionTokenTypeMismatch(market.marketId, uint8(expected), uint8(market.positionTokenType));
        }
    }

    function validatePositionIds(LibEveMarket.Market storage market) internal view {
        if (market.positionTokenType != LibEveMarket.PositionTokenType.CTF) {
            return;
        }

        (uint256 yesPositionId, uint256 noPositionId) =
            LibCTF.derivePositionIds(market.positionToken, market.collateralToken, market.conditionId);
        if (yesPositionId != market.yesPositionId) {
            revert Errors.PositionIdMismatch(yesPositionId, market.yesPositionId);
        }
        if (noPositionId != market.noPositionId) {
            revert Errors.PositionIdMismatch(noPositionId, market.noPositionId);
        }
    }

    function positionIdsMatch(LibEveMarket.Market storage market) internal view returns (bool) {
        if (market.positionTokenType != LibEveMarket.PositionTokenType.CTF) {
            return true;
        }

        (uint256 yesPositionId, uint256 noPositionId) =
            LibCTF.derivePositionIds(market.positionToken, market.collateralToken, market.conditionId);
        return yesPositionId == market.yesPositionId && noPositionId == market.noPositionId;
    }
}
