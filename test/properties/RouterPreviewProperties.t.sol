// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISEveUSDCLending} from "../../src/interfaces/ISEveUSDCLending.sol";

import {RouterTestBase} from "../helpers/RouterTestBase.sol";

contract RouterPreviewPropertiesTest is RouterTestBase {
    /// @dev Feature: maker-lending-router, Property 7: Preview Consistency
    function testFuzz_PreviewOnrampConsistency(uint128 usdcSeed, uint128 borrowSeed, uint32 durationSeed) public {
        uint256 usdcAmount = bound(uint256(usdcSeed), 2 * USDC_UNIT, 1_000_000e6);
        uint256 maxBorrow = _maxBorrowForUsdc(usdcAmount);
        vm.assume(maxBorrow >= USDC_UNIT);

        uint256 borrowAmount = _boundBorrow(uint256(borrowSeed), maxBorrow);
        uint256 durationSeconds = bound(uint256(durationSeed), DEFAULT_MIN_DURATION, DEFAULT_MAX_DURATION);

        (
            uint256 expectedVaultShares,
            uint128 expectedPositionShares,
            uint256 expectedOriginationFee,
            uint256 expectedDebt
        ) = router.previewOnramp(usdcAmount, borrowAmount, marketIdA);

        (uint256 loanId, uint128 positionSharesMinted) =
            _onramp(borrower, usdcAmount, borrowAmount, durationSeconds, marketIdA, routerReceiver);

        ISEveUSDCLending.Loan memory loan = _loanState(loanId);
        assertEq(uint256(loan.collateralShares), expectedVaultShares);
        assertEq(positionSharesMinted, expectedPositionShares);
        assertEq(uint256(loan.originationFeeCharged), expectedOriginationFee);
        assertEq(uint256(loan.debtPrincipal), expectedDebt);
    }

    /// @dev Feature: maker-lending-router, Property 7: Preview Consistency
    function testFuzz_PreviewOfframpToSharesConsistency(
        uint128 usdcSeed,
        uint128 borrowSeed,
        uint32 durationSeed,
        uint8 extraShareSeed
    ) public {
        uint256 usdcAmount = bound(uint256(usdcSeed), 2 * USDC_UNIT, 1_000_000e6);
        uint256 maxBorrow = _maxBorrowForUsdc(usdcAmount);
        vm.assume(maxBorrow >= USDC_UNIT);

        uint256 borrowAmount = _boundBorrow(uint256(borrowSeed), maxBorrow);
        uint256 durationSeconds = bound(uint256(durationSeed), DEFAULT_MIN_DURATION, DEFAULT_MAX_DURATION);

        (uint256 loanId, uint128 initialShares) =
            _onramp(borrower, usdcAmount, borrowAmount, durationSeconds, marketIdA, borrower);
        uint128 positionShareAmount = _prepareRepayInventory(
            borrower, marketIdA, loanId, initialShares, uint128(bound(uint256(extraShareSeed), 1, 25))
        );

        _approveRouterPositions(borrower);

        (uint256 expectedMergeOut, uint256 expectedRepayment, uint256 expectedExcess) =
            router.previewOfframpToShares(loanId, marketIdA, positionShareAmount);

        uint256 eveUSDCBefore = eveUSDC.balanceOf(borrower);
        _offrampToShares(borrower, loanId, marketIdA, positionShareAmount);

        assertEq(expectedMergeOut, uint256(positionShareAmount));
        assertEq(expectedRepayment, _loanDebt(loanId));
        assertEq(eveUSDC.balanceOf(borrower) - eveUSDCBefore, expectedExcess);
    }

    /// @dev Feature: maker-lending-router, Property 7: Preview Consistency
    function testFuzz_PreviewOfframpToUsdcConsistency(
        uint128 usdcSeed,
        uint128 borrowSeed,
        uint32 durationSeed,
        uint128 revenueSeed,
        uint8 extraShareSeed
    ) public {
        uint256 usdcAmount = bound(uint256(usdcSeed), 2 * USDC_UNIT, 1_000_000e6);
        uint256 maxBorrow = _maxBorrowForUsdc(usdcAmount);
        vm.assume(maxBorrow >= USDC_UNIT);

        uint256 borrowAmount = _boundBorrow(uint256(borrowSeed), maxBorrow);
        uint256 durationSeconds = bound(uint256(durationSeed), DEFAULT_MIN_DURATION, DEFAULT_MAX_DURATION);

        (uint256 loanId, uint128 initialShares) =
            _onramp(borrower, usdcAmount, borrowAmount, durationSeconds, marketIdA, borrower);
        uint128 positionShareAmount = _prepareRepayInventory(
            borrower, marketIdA, loanId, initialShares, uint128(bound(uint256(extraShareSeed), 1, 25))
        );

        _notifyRevenue(bound(uint256(revenueSeed), USDC_UNIT, 100_000e6));
        _approveRouterPositions(borrower);

        (
            uint256 expectedMergeOut,
            uint256 expectedRedeemedCollateral,
            uint256 expectedRepayment,
            uint256 expectedUsdcOut
        ) = router.previewOfframpToUSDC(loanId, marketIdA, positionShareAmount);

        uint256 receiverUsdcBefore = usdc.balanceOf(alternateReceiver);
        uint256 usdcOut = _offrampToUSDC(borrower, loanId, marketIdA, positionShareAmount, alternateReceiver);

        assertEq(expectedMergeOut, uint256(positionShareAmount));
        assertEq(expectedRepayment, _loanDebt(loanId));
        assertGt(expectedRedeemedCollateral, _loanCollateral(loanId));
        assertEq(usdcOut, expectedUsdcOut);
        assertEq(usdc.balanceOf(alternateReceiver) - receiverUsdcBefore, expectedUsdcOut);
    }
}
