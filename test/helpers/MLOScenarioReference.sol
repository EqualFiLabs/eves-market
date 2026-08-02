// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/// @notice Deliberately straightforward reference formulas for MLO scenario tests.
/// @dev This helper is independent from LibMLOScenarioMath by design.
library MLOScenarioReference {
    uint256 internal constant BPS_DENOMINATOR = 10_000;

    function askReservationCash(uint256 shares, uint256 price, uint256 denominator) internal pure returns (uint256) {
        uint256 product = shares * price;
        return product / denominator + (product % denominator == 0 ? 0 : 1);
    }

    function bidReservationCash(uint256 shares, uint256 price, uint256 denominator) internal pure returns (uint256) {
        uint256 product = shares * price;
        return product / denominator + (product % denominator == 0 ? 0 : 1);
    }

    function askVector(uint256 shares, uint256 grossProceeds, uint256 outcomeIndex, uint256 outcomeCount)
        internal
        pure
        returns (int256[] memory losses)
    {
        losses = new int256[](outcomeCount + 1);
        uint256 debt = shares - grossProceeds;
        for (uint256 i; i < outcomeCount; ++i) {
            uint256 payout = i == outcomeIndex ? 0 : shares;
            losses[i] = _difference(debt, payout);
        }
        losses[outcomeCount] = _difference(debt, (outcomeCount - 1) * (shares / outcomeCount));
    }

    function bidVector(uint256 shares, uint256 grossPayment, uint256 outcomeIndex, uint256 outcomeCount)
        internal
        pure
        returns (int256[] memory losses)
    {
        losses = new int256[](outcomeCount + 1);
        for (uint256 i; i < outcomeCount; ++i) {
            uint256 payout = i == outcomeIndex ? shares : 0;
            losses[i] = _difference(grossPayment, payout);
        }
        losses[outcomeCount] = _difference(grossPayment, shares / outcomeCount);
    }

    function margin(int256[] memory losses, uint256 marginBps) internal pure returns (uint256 requirement) {
        int256 maximumLoss;
        for (uint256 i; i < losses.length; ++i) {
            if (losses[i] > maximumLoss) {
                maximumLoss = losses[i];
            }
        }
        if (maximumLoss <= 0 || marginBps == 0) {
            return 0;
        }
        uint256 numerator = uint256(maximumLoss) * marginBps;
        requirement = numerator / BPS_DENOMINATOR;
        if (numerator % BPS_DENOMINATOR != 0) {
            ++requirement;
        }
    }

    function addUniformFunding(int256[] memory positionLosses, uint256 accruedUnpaidFunding)
        internal
        pure
        returns (int256[] memory effectiveLosses)
    {
        effectiveLosses = new int256[](positionLosses.length);
        for (uint256 i; i < positionLosses.length; ++i) {
            effectiveLosses[i] = positionLosses[i] + int256(accruedUnpaidFunding);
        }
    }

    function _difference(uint256 left, uint256 right) private pure returns (int256) {
        if (left >= right) {
            return int256(left - right);
        }
        return -int256(right - left);
    }
}
