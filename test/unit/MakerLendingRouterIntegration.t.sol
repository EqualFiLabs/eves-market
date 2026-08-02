// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {RouterTestBase} from "../helpers/RouterTestBase.sol";

contract MakerLendingRouterIntegrationTest is RouterTestBase {
    function test_FullLifecycleOnrampToOfframpToShares() public {
        uint256 usdcAmount = 800e6;
        uint256 borrowAmount = 300e6;
        uint256 expectedShares = vault.previewDeposit(usdcAmount * USDC_TO_EVEUSDC_SCALE);

        (uint256 loanId, uint128 initialShares) =
            _onramp(borrower, usdcAmount, borrowAmount, 14 days, marketIdA, borrower);
        uint128 positionShareAmount = _prepareRepayInventory(borrower, marketIdA, loanId, initialShares, 2);
        _approveRouterPositions(borrower);

        uint256 borrowerSharesBefore = vault.balanceOf(borrower);
        _offrampToShares(borrower, loanId, marketIdA, positionShareAmount);

        assertTrue(_loanState(loanId).repaid);
        assertEq(vault.balanceOf(borrower) - borrowerSharesBefore, expectedShares);
        _assertRouterClean(marketIdA);
    }

    function test_FullLifecycleOnrampToOfframpToUsdc() public {
        uint256 usdcAmount = 900e6;
        uint256 borrowAmount = 400e6;

        (uint256 loanId, uint128 initialShares) =
            _onramp(borrower, usdcAmount, borrowAmount, 21 days, marketIdA, borrower);
        uint128 positionShareAmount = _prepareRepayInventory(borrower, marketIdA, loanId, initialShares, 3);
        _approveRouterPositions(borrower);

        uint256 receiverBefore = usdc.balanceOf(alternateReceiver);
        uint256 usdcOut = _offrampToUSDC(borrower, loanId, marketIdA, positionShareAmount, alternateReceiver);

        assertTrue(_loanState(loanId).repaid);
        assertEq(usdc.balanceOf(alternateReceiver) - receiverBefore, usdcOut);
        _assertRouterClean(marketIdA);
    }

    function test_YieldCaptureLifecycle() public {
        uint256 usdcAmount = 1_000e6;
        uint256 borrowAmount = 400e6;
        uint256 revenueAmount = 120e18;

        (uint256 loanId, uint128 initialShares) =
            _onramp(borrower, usdcAmount, borrowAmount, 30 days, marketIdA, borrower);
        uint128 positionShareAmount = _prepareRepayInventory(borrower, marketIdA, loanId, initialShares, 4);
        _approveRouterPositions(borrower);
        _notifyRevenue(revenueAmount);

        uint256 receiverBefore = usdc.balanceOf(alternateReceiver);
        uint256 usdcOut = _offrampToUSDC(borrower, loanId, marketIdA, positionShareAmount, alternateReceiver);

        assertTrue(_loanState(loanId).repaid);
        assertEq(usdc.balanceOf(alternateReceiver) - receiverBefore, usdcOut);
        assertGt(usdcOut, usdcAmount);
        _assertRouterClean(marketIdA);
    }

    function test_OnrampThroughMarketAAndRepayThroughMarketB() public {
        uint256 usdcAmount = 700e6;
        uint256 borrowAmount = 300e6;

        (uint256 loanId, uint128 initialShares) =
            _onramp(borrower, usdcAmount, borrowAmount, 10 days, marketIdA, borrower);
        uint128 positionShareAmount = _prepareRepayInventory(borrower, marketIdB, loanId, 0, 1);
        _approveRouterPositions(borrower);

        (uint256 marketAYesBefore, uint256 marketANoBefore) = _positionBalances(borrower, marketIdA);
        assertEq(marketAYesBefore, initialShares);
        assertEq(marketANoBefore, initialShares);

        _offrampToShares(borrower, loanId, marketIdB, positionShareAmount);

        (uint256 marketAYesAfter, uint256 marketANoAfter) = _positionBalances(borrower, marketIdA);
        (uint256 marketBYesAfter, uint256 marketBNoAfter) = _positionBalances(borrower, marketIdB);

        assertTrue(_loanState(loanId).repaid);
        assertEq(marketAYesAfter, marketAYesBefore);
        assertEq(marketANoAfter, marketANoBefore);
        assertEq(marketBYesAfter, 0);
        assertEq(marketBNoAfter, 0);
        _assertRouterClean(marketIdB);
    }
}
