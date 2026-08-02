// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Math} from "../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

/// @notice Pure scenario accounting for senior-backed prediction-market quotes.
/// @dev All token amounts use the launch asset's internal accounting units.
library LibMLOScenarioMath {
    uint256 internal constant MIN_OUTCOMES = 2;
    uint256 internal constant MAX_OUTCOMES = 16;
    uint256 internal constant MAX_SUPPORTED_VALUE = type(uint128).max;
    uint256 internal constant BPS_DENOMINATOR = 10_000;

    enum Side {
        ASK,
        BID
    }

    error InvalidOutcomeCount(uint256 outcomeCount);
    error InvalidOutcomeIndex(uint256 outcomeIndex, uint256 outcomeCount);
    error InvalidShares(uint256 shares);
    error InvalidCash(uint256 cashAmount, uint256 shares);
    error InvalidDenominator(uint256 denominator);
    error InvalidPrice(uint256 price, uint256 denominator);
    error InvalidVectorLength(uint256 length);
    error InvalidMarginBps(uint256 marginBps);
    error InvalidFunding(uint256 accruedUnpaidFunding);
    error EffectiveLossOverflow(uint256 index);

    function validateOutcomeCount(uint256 outcomeCount) internal pure {
        if (outcomeCount < MIN_OUTCOMES || outcomeCount > MAX_OUTCOMES) {
            revert InvalidOutcomeCount(outcomeCount);
        }
    }

    function validateOutcomeIndex(uint256 outcomeIndex, uint256 outcomeCount) internal pure {
        validateOutcomeCount(outcomeCount);
        if (outcomeIndex >= outcomeCount) {
            revert InvalidOutcomeIndex(outcomeIndex, outcomeCount);
        }
    }

    function validateShares(uint256 shares) internal pure {
        if (shares == 0 || shares > MAX_SUPPORTED_VALUE) {
            revert InvalidShares(shares);
        }
    }

    /// @dev Zero cash is valid at a zero price; it is not valid above the share amount.
    function validateCash(uint256 cashAmount, uint256 shares) internal pure {
        if (cashAmount > MAX_SUPPORTED_VALUE || cashAmount > shares) {
            revert InvalidCash(cashAmount, shares);
        }
    }

    function validatePrice(uint256 price, uint256 denominator) internal pure {
        if (denominator == 0 || denominator > MAX_SUPPORTED_VALUE) {
            revert InvalidDenominator(denominator);
        }
        if (price > MAX_SUPPORTED_VALUE || price > denominator) {
            revert InvalidPrice(price, denominator);
        }
    }

    /// @notice Returns the conservative cash bound for a quote reservation.
    /// @dev MLO ASK execution ceils proceeds, making aggregate net backing safe under fragmented fills.
    ///      BID reservations ceil payment at the maximum price.
    function reservationCash(Side, uint256 shares, uint256 price, uint256 denominator)
        internal
        pure
        returns (uint256 cashAmount)
    {
        validateShares(shares);
        validatePrice(price, denominator);

        // Validation bounds both operands to uint128, so the product cannot
        // overflow uint256 and does not require the 512-bit mulDiv path.
        uint256 product = shares * price;
        cashAmount = product / denominator;
        if (product % denominator != 0) ++cashAmount;
    }

    /// @notice Returns the net Senior collateral required for unbacked ASK shares.
    function askSeniorRequirement(uint256 shares, uint256 price, uint256 denominator)
        internal
        pure
        returns (uint256 requirement)
    {
        validatePrice(price, denominator);
        if (shares == 0) return 0;
        requirement = shares - reservationCash(Side.ASK, shares, price, denominator);
    }

    /// @notice Computes a reservation vector directly from its conservative price bound.
    function reservedLossVector(
        Side side,
        uint256 shares,
        uint256 price,
        uint256 denominator,
        uint256 outcomeIndex,
        uint256 outcomeCount
    ) internal pure returns (int256[] memory losses) {
        uint256 cashAmount = reservationCash(side, shares, price, denominator);
        return lossVector(side, shares, cashAmount, outcomeIndex, outcomeCount);
    }

    /// @notice Computes signed scenario losses from executed gross proceeds or payment.
    /// @dev Positive values require collateral; negative values are scenario profit.
    function lossVector(Side side, uint256 shares, uint256 cashAmount, uint256 outcomeIndex, uint256 outcomeCount)
        internal
        pure
        returns (int256[] memory losses)
    {
        validateShares(shares);
        validateCash(cashAmount, shares);
        validateOutcomeIndex(outcomeIndex, outcomeCount);

        losses = new int256[](outcomeCount + 1);
        uint256 debt;
        if (side == Side.ASK) {
            debt = shares - cashAmount;
            for (uint256 i; i < outcomeCount; ++i) {
                uint256 retainedPayout = i == outcomeIndex ? 0 : shares;
                losses[i] = _signedDifference(debt, retainedPayout);
            }
        } else {
            debt = cashAmount;
            for (uint256 i; i < outcomeCount; ++i) {
                uint256 inventoryPayout = i == outcomeIndex ? shares : 0;
                losses[i] = _signedDifference(debt, inventoryPayout);
            }
        }

        uint256 invalidPayout = side == Side.ASK ? (outcomeCount - 1) * (shares / outcomeCount) : shares / outcomeCount;
        losses[outcomeCount] = _signedDifference(debt, invalidPayout);
    }

    /// @notice Computes a rounded-up margin requirement from an aggregate vector.
    function requiredMargin(int256[] memory aggregateLosses, uint256 marginBps)
        internal
        pure
        returns (uint256 requirement)
    {
        uint256 length = aggregateLosses.length;
        _validateVectorLength(length);
        if (marginBps > BPS_DENOMINATOR) {
            revert InvalidMarginBps(marginBps);
        }

        int256 maximumLoss;
        for (uint256 i; i < length; ++i) {
            if (aggregateLosses[i] > maximumLoss) {
                maximumLoss = aggregateLosses[i];
            }
        }
        if (maximumLoss <= 0 || marginBps == 0) {
            return 0;
        }

        requirement = Math.mulDiv(uint256(maximumLoss), marginBps, BPS_DENOMINATOR, Math.Rounding.Ceil);
    }

    /// @notice Adds accrued unpaid funding uniformly to every scenario loss.
    /// @dev Funding remains a separate liability; this returns the effective margin vector.
    function addUniformFunding(int256[] memory positionLosses, uint256 accruedUnpaidFunding)
        internal
        pure
        returns (int256[] memory effectiveLosses)
    {
        _validateVectorLength(positionLosses.length);
        if (accruedUnpaidFunding > MAX_SUPPORTED_VALUE) {
            revert InvalidFunding(accruedUnpaidFunding);
        }

        int256 funding = int256(accruedUnpaidFunding);
        effectiveLosses = new int256[](positionLosses.length);
        for (uint256 i; i < positionLosses.length; ++i) {
            if (positionLosses[i] > type(int256).max - funding) {
                revert EffectiveLossOverflow(i);
            }
            effectiveLosses[i] = positionLosses[i] + funding;
        }
    }

    function _validateVectorLength(uint256 length) private pure {
        if (length < MIN_OUTCOMES + 1 || length > MAX_OUTCOMES + 1) {
            revert InvalidVectorLength(length);
        }
    }

    function _signedDifference(uint256 left, uint256 right) private pure returns (int256 difference) {
        if (left >= right) {
            return int256(left - right);
        }
        return -int256(right - left);
    }
}
