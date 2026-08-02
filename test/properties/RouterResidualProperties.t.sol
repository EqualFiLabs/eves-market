// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {RouterTestBase} from "../helpers/RouterTestBase.sol";

contract RouterResidualPropertiesTest is RouterTestBase {
    /// @dev Feature: maker-lending-router, Property 6: No Residual Balances Invariant
    function testFuzz_NoResidualBalancesInvariant(
        uint128 usdcSeed,
        uint128 borrowSeed,
        uint32 durationSeed,
        uint8 extraShareSeed,
        bool useUsdcPath,
        bool useSecondMarket
    ) public {
        uint256 usdcAmount = bound(uint256(usdcSeed), 2 * USDC_UNIT, 1_000_000e6);
        uint256 maxBorrow = _maxBorrowForUsdc(usdcAmount);
        vm.assume(maxBorrow >= USDC_UNIT);

        uint256 borrowAmount = _boundBorrow(uint256(borrowSeed), maxBorrow);
        uint256 durationSeconds = bound(uint256(durationSeed), DEFAULT_MIN_DURATION, DEFAULT_MAX_DURATION);

        (uint256 loanId, uint128 initialShares) =
            _onramp(borrower, usdcAmount, borrowAmount, durationSeconds, marketIdA, borrower);
        _assertRouterClean(marketIdA);

        bytes32 repayMarketId = _repayMarket(useSecondMarket);
        uint128 availableShares = useSecondMarket ? 0 : initialShares;
        uint128 extraShares = uint128(bound(uint256(extraShareSeed), 1, 25));
        uint128 positionShareAmount =
            _prepareRepayInventory(borrower, repayMarketId, loanId, availableShares, extraShares);

        _approveRouterPositions(borrower);

        if (useUsdcPath) {
            _notifyRevenue(USDC_UNIT);
            _offrampToUSDC(borrower, loanId, repayMarketId, positionShareAmount, alternateReceiver);
        } else {
            _offrampToShares(borrower, loanId, repayMarketId, positionShareAmount);
        }

        _assertRouterClean(marketIdA);
        _assertRouterClean(repayMarketId);
    }
}
