// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {RouterTestBase} from "../helpers/RouterTestBase.sol";

contract RouterOfframpPropertiesTest is RouterTestBase {
    /// @dev Feature: maker-lending-router, Property 4: Offramp-to-Shares Correctness and Excess Handling
    function testFuzz_OfframpToSharesCorrectnessAndExcessHandling(
        uint128 usdcSeed,
        uint128 borrowSeed,
        uint32 durationSeed,
        uint8 extraShareSeed,
        bool useSecondMarket
    ) public {
        uint256 usdcAmount = bound(uint256(usdcSeed), 2 * USDC_UNIT, 1_000_000e6);
        uint256 maxBorrow = _maxBorrowForUsdc(usdcAmount);
        vm.assume(maxBorrow >= USDC_UNIT);

        uint256 borrowAmount = _boundBorrow(uint256(borrowSeed), maxBorrow);
        uint256 durationSeconds = bound(uint256(durationSeed), DEFAULT_MIN_DURATION, DEFAULT_MAX_DURATION);
        uint128 extraShares = uint128(bound(uint256(extraShareSeed), 1, 25));

        (uint256 loanId, uint128 initialShares) =
            _onramp(borrower, usdcAmount, borrowAmount, durationSeconds, marketIdA, borrower);

        bytes32 repayMarketId = _repayMarket(useSecondMarket);
        uint128 availableShares = useSecondMarket ? 0 : initialShares;
        uint128 positionShareAmount =
            _prepareRepayInventory(borrower, repayMarketId, loanId, availableShares, extraShares);

        _approveRouterPositions(borrower);

        (,, uint256 expectedExcessEveUSDC) = router.previewOfframpToShares(loanId, repayMarketId, positionShareAmount);
        uint256 eveUSDCBefore = eveUSDC.balanceOf(borrower);
        uint256 collateralShares = _loanCollateral(loanId);

        _offrampToShares(borrower, loanId, repayMarketId, positionShareAmount);

        assertTrue(_loanState(loanId).repaid);
        assertEq(vault.balanceOf(borrower), collateralShares);
        assertEq(eveUSDC.balanceOf(borrower) - eveUSDCBefore, expectedExcessEveUSDC);
        _assertRouterClean(repayMarketId);
    }

    /// @dev Feature: maker-lending-router, Property 5: Offramp-to-USDC Correctness with Yield
    function testFuzz_OfframpToUsdcCorrectnessWithYield(
        uint128 usdcSeed,
        uint128 borrowSeed,
        uint32 durationSeed,
        uint128 revenueSeed,
        uint8 extraShareSeed,
        bool useSecondMarket
    ) public {
        uint256 usdcAmount = bound(uint256(usdcSeed), 2 * USDC_UNIT, 1_000_000e6);
        uint256 maxBorrow = _maxBorrowForUsdc(usdcAmount);
        vm.assume(maxBorrow >= USDC_UNIT);

        uint256 borrowAmount = _boundBorrow(uint256(borrowSeed), maxBorrow);
        uint256 durationSeconds = bound(uint256(durationSeed), DEFAULT_MIN_DURATION, DEFAULT_MAX_DURATION);
        uint256 revenueAmount = bound(uint256(revenueSeed), USDC_UNIT, 100_000e6);
        uint128 extraShares = uint128(bound(uint256(extraShareSeed), 1, 25));

        (uint256 loanId, uint128 initialShares) =
            _onramp(borrower, usdcAmount, borrowAmount, durationSeconds, marketIdA, borrower);

        bytes32 repayMarketId = _repayMarket(useSecondMarket);
        uint128 availableShares = useSecondMarket ? 0 : initialShares;
        uint128 positionShareAmount =
            _prepareRepayInventory(borrower, repayMarketId, loanId, availableShares, extraShares);

        _notifyRevenue(revenueAmount);
        _approveRouterPositions(borrower);

        (, uint256 expectedRedeemedCollateralEveUSDC,, uint256 expectedUsdcOut) =
            router.previewOfframpToUSDC(loanId, repayMarketId, positionShareAmount);

        uint256 receiverUsdcBefore = usdc.balanceOf(alternateReceiver);
        uint256 loanCollateral = _loanCollateral(loanId);

        uint256 usdcOut = _offrampToUSDC(borrower, loanId, repayMarketId, positionShareAmount, alternateReceiver);

        assertTrue(_loanState(loanId).repaid);
        assertEq(usdcOut, expectedUsdcOut);
        assertEq(usdc.balanceOf(alternateReceiver) - receiverUsdcBefore, expectedUsdcOut);
        assertGt(expectedRedeemedCollateralEveUSDC, loanCollateral);
        _assertRouterClean(repayMarketId);
    }
}
