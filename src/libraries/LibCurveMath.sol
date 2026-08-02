// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ICurveProfile} from "../interfaces/ICurveProfile.sol";
import {Errors} from "./Errors.sol";
import {LibBookPricing} from "./LibBookPricing.sol";
import {LibCurvePacking} from "./LibCurvePacking.sol";
import {LibEveMarket} from "./LibEveMarket.sol";

library LibCurveMath {
    uint256 internal constant FEE_BPS_DENOMINATOR = 10_000;

    uint8 internal constant LINEAR_PROFILE_ID = 0;
    uint8 internal constant STEP_PROFILE_ID = 1;
    uint8 internal constant EXPONENTIAL_DECAY_PROFILE_ID = 2;

    function currentPrice(LibEveMarket.EveMarketStorage storage state, LibEveMarket.StoredCurve storage curve)
        internal
        view
        returns (uint128 price)
    {
        LibEveMarket.Book storage book = state.books[curve.bookId];
        uint128 tick = currentTick(state, curve);
        price = LibBookPricing.priceFromTick(book, curve.packed, tick);
    }

    function currentTick(LibEveMarket.EveMarketStorage storage state, LibEveMarket.StoredCurve storage curve)
        internal
        view
        returns (uint128 tick)
    {
        LibCurvePacking.CurveParams memory params = LibCurvePacking.unpack(curve.packed);
        uint64 startTime = curveStartTime(state, curve);
        uint64 duration = uint64(params.durationMinutes) * 60;
        uint64 currentTime = uint64(block.timestamp);

        if (params.profileId == LINEAR_PROFILE_ID) {
            return _linearTick(params.startPrice, params.endPrice, startTime, duration, currentTime);
        }
        if (params.profileId == STEP_PROFILE_ID) {
            return _stepTick(params.startPrice, params.endPrice, startTime, duration, currentTime);
        }
        if (params.profileId == EXPONENTIAL_DECAY_PROFILE_ID) {
            return _expDecayTick(params.startPrice, params.endPrice, startTime, duration, currentTime);
        }

        address profile = state.curveProfiles[params.profileId];
        if (profile == address(0)) {
            revert Errors.InvalidProfileId(params.profileId);
        }

        return ICurveProfile(profile)
            .computePrice(
                params.startPrice,
                params.endPrice,
                startTime,
                duration,
                currentTime,
                LibCurvePacking.extractCustomProfileParams(curve.packed)
            );
    }

    function quoteAsk(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.StoredCurve storage curve,
        uint128 collateralIn
    ) internal view returns (uint128 sharesOut, uint128 fee, uint128 price, uint128 collateralUsed) {
        price = currentPrice(state, curve);
        if (curve.remainingVolume == 0) {
            return (0, 0, price, 0);
        }

        if (price == 0) {
            return (curve.remainingVolume, 0, price, 0);
        }

        LibEveMarket.Book storage book = state.books[curve.bookId];
        uint256 grossBudget =
            (uint256(collateralIn) * FEE_BPS_DENOMINATOR) / (FEE_BPS_DENOMINATOR + uint256(book.feeConfig.entryFeeBps));
        uint256 shares = (grossBudget * uint256(book.priceDenominator)) / uint256(price);
        if (shares > curve.remainingVolume) {
            shares = curve.remainingVolume;
        }

        sharesOut = uint128(shares);
        if (sharesOut == 0) {
            return (0, 0, price, 0);
        }

        uint128 grossCost = LibBookPricing.grossCostFor(book, sharesOut, price);
        fee = feeFor(grossCost, book.feeConfig.entryFeeBps);
        collateralUsed = grossCost + fee;
    }

    function quoteBid(
        LibEveMarket.Book storage book,
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.StoredCurve storage curve,
        uint128 baseIn
    ) internal view returns (uint128 baseAmount, uint128 fee, uint128 price, uint128 collateralUsed) {
        if (baseIn == 0 || curve.remainingVolume == 0 || curve.quoteEscrowRemaining == 0) {
            return (0, 0, 0, 0);
        }

        price = currentPrice(state, curve);
        if (price == 0) {
            return (0, 0, 0, 0);
        }

        uint256 maxBaseByEscrow = uint256(LibBookPricing.baseForQuote(book, curve.quoteEscrowRemaining, price));
        uint256 clippedBase = baseIn;
        if (clippedBase > curve.remainingVolume) {
            clippedBase = curve.remainingVolume;
        }
        if (clippedBase > maxBaseByEscrow) {
            clippedBase = maxBaseByEscrow;
        }
        if (clippedBase == 0) {
            return (0, 0, price, 0);
        }

        baseAmount = uint128(clippedBase);
        collateralUsed = LibBookPricing.grossCostFor(book, baseAmount, price);
        fee = feeFor(collateralUsed, book.feeConfig.entryFeeBps);
    }

    function quoteEscrowRequired(LibEveMarket.Book storage book, uint128 volume, uint72 startTick, uint72 endTick)
        internal
        view
        returns (uint128 required)
    {
        uint128 startPrice = LibBookPricing.priceFromTick(book, startTick);
        uint128 endPrice = LibBookPricing.priceFromTick(book, endTick);
        uint128 maxPrice = startPrice > endPrice ? startPrice : endPrice;
        required = LibBookPricing.grossCostFor(book, volume, maxPrice);
    }

    function quoteEscrowRequiredForPacked(LibEveMarket.Book storage book, uint128 volume, uint256 packed)
        internal
        view
        returns (uint128 required)
    {
        LibCurvePacking.CurveParams memory params = LibCurvePacking.unpack(packed);
        uint128 startPrice = LibBookPricing.priceFromTick(book, packed, params.startPrice);
        uint128 endPrice = LibBookPricing.priceFromTick(book, packed, params.endPrice);
        uint128 maxPrice = startPrice > endPrice ? startPrice : endPrice;
        required = LibBookPricing.grossCostFor(book, volume, maxPrice);
    }

    function isExpired(LibEveMarket.EveMarketStorage storage state, LibEveMarket.StoredCurve storage curve)
        internal
        view
        returns (bool)
    {
        LibCurvePacking.CurveParams memory params = LibCurvePacking.unpack(curve.packed);
        return block.timestamp >= expiresAt(state, curve, params.durationMinutes);
    }

    function expiresAt(LibEveMarket.EveMarketStorage storage state, LibEveMarket.StoredCurve storage curve)
        internal
        view
        returns (uint64)
    {
        LibCurvePacking.CurveParams memory params = LibCurvePacking.unpack(curve.packed);
        return expiresAt(state, curve, params.durationMinutes);
    }

    function expiresAt(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.StoredCurve storage curve,
        uint24 durationMinutes
    ) internal view returns (uint64) {
        uint256 expiration = uint256(curveStartTime(state, curve)) + (uint256(durationMinutes) * 60);
        if (expiration > type(uint64).max) {
            return type(uint64).max;
        }
        return uint64(expiration);
    }

    function curveStartTime(LibEveMarket.EveMarketStorage storage state, LibEveMarket.StoredCurve storage curve)
        internal
        view
        returns (uint64 startTime)
    {
        startTime = curve.createdAt;
        LibEveMarket.Book storage book = state.books[curve.bookId];
        if (book.marketId != bytes32(0)) {
            uint64 tradingStartTime = state.markets[book.marketId].tradingStartTime;
            if (startTime < tradingStartTime) {
                startTime = tradingStartTime;
            }
        }
    }

    function curveCommitment(uint256 packed) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(packed));
    }

    function feeFor(uint128 grossCost, uint16 entryFeeBps) internal pure returns (uint128 fee) {
        fee = uint128((uint256(grossCost) * entryFeeBps) / FEE_BPS_DENOMINATOR);
    }

    function _linearTick(uint72 startTick, uint72 endTick, uint64 startTime, uint64 duration, uint64 currentTime)
        private
        pure
        returns (uint128)
    {
        if (currentTime <= startTime) {
            return startTick;
        }
        if (duration == 0 || currentTime >= startTime + duration) {
            return endTick;
        }

        uint256 elapsed = currentTime - startTime;
        if (endTick >= startTick) {
            return uint128(startTick + ((uint256(endTick - startTick) * elapsed) / duration));
        }

        return uint128(startTick - ((uint256(startTick - endTick) * elapsed) / duration));
    }

    function _stepTick(uint72 startTick, uint72 endTick, uint64 startTime, uint64 duration, uint64 currentTime)
        private
        pure
        returns (uint128)
    {
        if (currentTime <= startTime) {
            return startTick;
        }
        if (duration == 0 || currentTime >= startTime + duration) {
            return endTick;
        }

        return currentTime < startTime + (duration / 2) ? startTick : endTick;
    }

    function _expDecayTick(uint72 startTick, uint72 endTick, uint64 startTime, uint64 duration, uint64 currentTime)
        private
        pure
        returns (uint128)
    {
        if (currentTime <= startTime) {
            return startTick;
        }
        if (duration == 0 || currentTime >= startTime + duration) {
            return endTick;
        }

        uint256 elapsed = currentTime - startTime;
        uint256 remaining = duration - elapsed;
        uint256 factor = (remaining * 1e18) / duration;
        uint256 decayFactor = (factor * factor) / 1e18;

        if (startTick >= endTick) {
            return uint128(endTick + ((uint256(startTick - endTick) * decayFactor) / 1e18));
        }

        return uint128(endTick - ((uint256(endTick - startTick) * decayFactor) / 1e18));
    }
}
