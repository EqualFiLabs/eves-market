// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {LendingTestBase} from "../helpers/LendingTestBase.sol";
import {ISEveUSDCLending} from "../../src/interfaces/ISEveUSDCLending.sol";
import {ISEveUSDCVaultLending} from "../../src/interfaces/ISEveUSDCVaultLending.sol";

contract LendingAccessControlPropertiesTest is LendingTestBase {
    /// @dev Feature: seveusdc-maker-lending, Property 17: Vault Report and Disbursement Access Control
    function testFuzz_VaultReportAndDisbursementAccessControl(address caller, uint128 debtSeed, uint128 feeSeed)
        public
    {
        vm.assume(caller != address(0) && caller != address(lending));

        uint256 debtPrincipal = bound(uint256(debtSeed), 1, 1_000_000e6);
        uint256 feeAmount = bound(uint256(feeSeed), 0, debtPrincipal);

        vm.startPrank(caller);

        vm.expectRevert(abi.encodeWithSelector(ISEveUSDCVaultLending.NotLendingContract.selector, caller));
        vault.reportLoan(debtPrincipal);

        vm.expectRevert(abi.encodeWithSelector(ISEveUSDCVaultLending.NotLendingContract.selector, caller));
        vault.reportRepayment(debtPrincipal);

        vm.expectRevert(abi.encodeWithSelector(ISEveUSDCVaultLending.NotLendingContract.selector, caller));
        vault.reportDefault(debtPrincipal, feeAmount);

        vm.expectRevert(abi.encodeWithSelector(ISEveUSDCVaultLending.NotLendingContract.selector, caller));
        vault.disburseLoan(receiver, debtPrincipal - feeAmount, feeAmount);

        vm.stopPrank();
    }

    /// @dev Feature: seveusdc-maker-lending, Property 18: Router Delegation Access Control
    function testFuzz_RouterDelegationAccessControl(
        address caller,
        uint128 depositSeed,
        uint128 collateralSeed,
        uint128 borrowSeed
    ) public {
        vm.assume(caller != address(0) && caller != approvedRouter);

        uint256 depositAssets = bound(uint256(depositSeed), 100, 1_000_000e6);
        uint256 routerShares = _depositAndApproveShares(approvedRouter, depositAssets);
        uint256 collateralShares = bound(uint256(collateralSeed), 3, routerShares);
        uint256 borrowAmount = bound(uint256(borrowSeed), 1, lending.maxBorrowForShares(collateralShares));

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(ISEveUSDCLending.NotApprovedRouter.selector, caller));
        lending.borrowFor(collateralShares, 7 days, borrowAmount, delegatedRecipient, alice);

        _setApprovedRouter(approvedRouter, true);
        uint256 loanId =
            _delegatedBorrow(approvedRouter, collateralShares, 7 days, borrowAmount, delegatedRecipient, alice);

        _seedDebtAndApprove(approvedRouter, _loanDebt(loanId));

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(ISEveUSDCLending.NotApprovedRouter.selector, caller));
        lending.repayFor(loanId, false, delegatedRecipient);

        _delegatedRepay(approvedRouter, loanId, false, delegatedRecipient);
        assertTrue(lending.loanState(loanId).repaid);
    }

    /// @dev Feature: seveusdc-maker-lending, Property 19: Config Validation
    function testFuzz_ConfigValidation(address caller, uint16 ltvSeed, uint32 minSeed, uint32 maxSeed) public {
        vm.assume(caller != address(0) && caller != owner);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(ISEveUSDCLending.NotAuthorized.selector, caller));
        lending.setLendingConfig(DEFAULT_MAX_LTV_BPS, 0, 0, 1 days, 30 days, 1 days);

        vm.prank(owner);
        vm.expectRevert(ISEveUSDCLending.InvalidConfig.selector);
        lending.setLendingConfig(
            uint16(bound(uint256(ltvSeed), 9_501, type(uint16).max)), 0, 0, 1 days, 30 days, 1 days
        );

        vm.prank(owner);
        vm.expectRevert(ISEveUSDCLending.InvalidConfig.selector);
        lending.setLendingConfig(
            DEFAULT_MAX_LTV_BPS,
            0,
            0,
            uint32(bound(uint256(minSeed), 2 days, 10 days)),
            uint32(bound(uint256(maxSeed), 1 days, 1 days)),
            1 days
        );
    }
}
