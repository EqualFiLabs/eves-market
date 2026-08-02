// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {RouterTestBase} from "../helpers/RouterTestBase.sol";

contract RouterOnrampPropertiesTest is RouterTestBase {
    /// @dev Feature: maker-lending-router, Property 3: Onramp Atomicity and Position Delivery
    function testFuzz_OnrampAtomicityAndPositionDelivery(
        uint128 usdcSeed,
        uint128 borrowSeed,
        uint32 durationSeed,
        bool useSecondMarket
    ) public {
        uint256 usdcAmount = bound(uint256(usdcSeed), 2 * USDC_UNIT, 1_000_000e6);
        uint256 maxBorrow = _maxBorrowForUsdc(usdcAmount);
        vm.assume(maxBorrow >= USDC_UNIT);

        uint256 borrowAmount = _boundBorrow(uint256(borrowSeed), maxBorrow);
        uint256 durationSeconds = bound(uint256(durationSeed), DEFAULT_MIN_DURATION, DEFAULT_MAX_DURATION);
        bytes32 marketId = _repayMarket(useSecondMarket);

        uint256 expectedVaultShares = vault.previewDeposit(usdcAmount * USDC_TO_EVEUSDC_SCALE);
        _seedUsdcAndApproveRouter(borrower, usdcAmount);
        uint256 borrowerUsdcBefore = usdc.balanceOf(borrower);

        vm.prank(borrower);
        (uint256 loanId, uint128 positionSharesMinted) =
            router.onramp(usdcAmount, borrowAmount, durationSeconds, marketId, routerReceiver);

        (uint256 yesBalance, uint256 noBalance) = _positionBalances(routerReceiver, marketId);

        assertEq(borrowerUsdcBefore - usdc.balanceOf(borrower), usdcAmount);
        assertEq(_loanBorrower(loanId), borrower);
        assertEq(_loanCollateral(loanId), expectedVaultShares);
        assertEq(positionSharesMinted, _loanState(loanId).netBorrowed);
        assertEq(yesBalance, positionSharesMinted);
        assertEq(noBalance, positionSharesMinted);
        _assertRouterClean(marketId);
    }
}
