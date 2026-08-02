// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISEveUSDCVault} from "../../src/interfaces/ISEveUSDCVault.sol";
import {ISEveUSDCVaultLending} from "../../src/interfaces/ISEveUSDCVaultLending.sol";

import {VaultTestBase} from "../helpers/VaultTestBase.sol";

contract SEveUSDCVaultAccountingTest is VaultTestBase {
    event LendingContractSet(address indexed previousLending, address indexed newLending);

    function test_TotalAssetsReturnsManagedAssetsFormula() public {
        uint256 depositAssets = 1_000e6;
        uint256 debtPrincipal = 250e6;
        uint256 feeAmount = 10e6;
        uint256 borrowAmount = debtPrincipal - feeAmount;

        _depositSeeded(alice, depositAssets, alice);
        _setLendingContract(address(this));

        vault.reportLoan(debtPrincipal);
        vault.disburseLoan(receiver, borrowAmount, feeAmount);

        assertEq(vault.outstandingPrincipal(), debtPrincipal);
        assertEq(vault.recognizedLosses(), 0);
        assertEq(vault.totalAssets(), _managedAssets(vault));
        assertEq(vault.totalAssets(), depositAssets);
    }

    function test_ReportLoanRepaymentAndDefaultUpdateAccounting() public {
        _setLendingContract(address(this));

        vault.reportLoan(300e6);
        assertEq(vault.outstandingPrincipal(), 300e6);
        assertEq(vault.recognizedLosses(), 0);

        vault.reportRepayment(120e6);
        assertEq(vault.outstandingPrincipal(), 180e6);
        assertEq(vault.recognizedLosses(), 0);

        vault.reportDefault(180e6, 45e6);
        assertEq(vault.outstandingPrincipal(), 0);
        assertEq(vault.recognizedLosses(), 45e6);
    }

    function test_SettleDefaultBurnsCollateralSharesAndUpdatesAccounting() public {
        uint256 collateralShares = _depositSeeded(alice, 1_000e6, alice) / 4;
        uint256 debtPrincipal = 300e6;

        _setLendingContract(address(this));

        vm.prank(alice);
        vault.transfer(address(this), collateralShares);

        vault.reportLoan(debtPrincipal);
        vault.disburseLoan(receiver, debtPrincipal, 0);

        uint256 idleBefore = eveUSDC.balanceOf(address(vault));
        uint256 supplyBefore = vault.totalSupply();
        uint256 expectedRecovered = vault.previewRedeem(collateralShares);
        uint256 expectedLoss = debtPrincipal - expectedRecovered;

        (uint256 recoveredAssets, uint256 recognizedLoss) = vault.settleDefault(debtPrincipal, collateralShares);

        assertEq(recoveredAssets, expectedRecovered);
        assertEq(recognizedLoss, expectedLoss);
        assertEq(vault.balanceOf(address(this)), 0);
        assertEq(vault.totalSupply(), supplyBefore - collateralShares);
        assertEq(vault.outstandingPrincipal(), 0);
        assertEq(vault.recognizedLosses(), expectedLoss);
        assertEq(eveUSDC.balanceOf(address(vault)), idleBefore);
        assertEq(vault.totalAssets(), idleBefore - expectedLoss);
    }

    function test_DisburseLoanSendsBorrowAmountAndFeeCorrectly() public {
        uint256 depositAssets = 500e6;
        uint256 borrowAmount = 190e6;
        uint256 feeAmount = 10e6;

        _depositSeeded(alice, depositAssets, alice);
        _setLendingContract(address(this));

        uint256 receiverBefore = eveUSDC.balanceOf(receiver);
        uint256 feeRecipientBefore = eveUSDC.balanceOf(feeRecipient);

        vault.disburseLoan(receiver, borrowAmount, feeAmount);

        assertEq(eveUSDC.balanceOf(receiver) - receiverBefore, borrowAmount);
        assertEq(eveUSDC.balanceOf(feeRecipient) - feeRecipientBefore, feeAmount);
        assertEq(eveUSDC.balanceOf(address(vault)), depositAssets - borrowAmount - feeAmount);
    }

    function test_RevertWhen_UnauthorizedCallerUsesLendingHooks() public {
        _setLendingContract(address(this));

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ISEveUSDCVaultLending.NotLendingContract.selector, alice));
        vault.reportLoan(1);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ISEveUSDCVaultLending.NotLendingContract.selector, alice));
        vault.reportRepayment(1);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ISEveUSDCVaultLending.NotLendingContract.selector, alice));
        vault.reportDefault(1, 0);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ISEveUSDCVaultLending.NotLendingContract.selector, alice));
        vault.settleDefault(1, 1);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ISEveUSDCVaultLending.NotLendingContract.selector, alice));
        vault.disburseLoan(receiver, 1, 0);
    }

    function test_SetLendingContractIsOwnerOnlyAndEmits() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ISEveUSDCVault.NotOwner.selector, alice));
        vault.setLendingContract(address(this));

        vm.prank(owner);
        vm.expectEmit(true, true, false, true, address(vault));
        emit LendingContractSet(address(0), address(this));
        vault.setLendingContract(address(this));

        assertEq(vault.lendingContract(), address(this));
    }

    function test_RevertWhen_LendingContractIsZeroOrNonContract() public {
        vm.prank(owner);
        vm.expectRevert(ISEveUSDCVault.ZeroAddress.selector);
        vault.setLendingContract(address(0));

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ISEveUSDCVault.ContractHasNoCode.selector, carol));
        vault.setLendingContract(carol);
    }

    function test_DepositWithdrawRedeemAndAumAccrualStillWorkAfterUpgrade() public {
        uint256 aliceDeposit = 1_000e6;
        uint256 bobDeposit = 500e6;
        uint256 revenueAssets = 50e6;

        _setLendingContract(address(this));

        uint256 aliceShares = _depositSeeded(alice, aliceDeposit, alice);
        _depositSeeded(bob, bobDeposit, bob);

        vm.warp(block.timestamp + 5 days);

        uint256 feeRecipientBefore = eveUSDC.balanceOf(feeRecipient);
        uint256 accruedFee = vault.accrueAum();
        assertGt(accruedFee, 0);
        assertEq(eveUSDC.balanceOf(feeRecipient) - feeRecipientBefore, accruedFee);

        _notifyRevenue(revenueAssets);

        uint256 receiverBefore = eveUSDC.balanceOf(receiver);
        vm.prank(bob);
        uint256 sharesBurned = vault.withdraw(100e6, receiver, bob);
        assertGt(sharesBurned, 0);
        assertEq(eveUSDC.balanceOf(receiver) - receiverBefore, 100e6);

        uint256 carolBefore = eveUSDC.balanceOf(carol);
        vm.prank(alice);
        uint256 assetsOut = vault.redeem(aliceShares / 2, carol, alice);
        assertGt(assetsOut, 0);
        assertEq(eveUSDC.balanceOf(carol) - carolBefore, assetsOut);

        assertEq(vault.totalAssets(), _managedAssets(vault));
    }

    function test_AumAccrualBooksUnpaidFeesWhenVaultIsIlliquid() public {
        vault = _deployVault(10_000);

        uint256 depositAssets = 1_000e6;
        uint256 debtPrincipal = 990e6;

        _depositSeeded(alice, depositAssets, alice);
        _setLendingContract(address(this));

        vault.reportLoan(debtPrincipal);
        vault.disburseLoan(receiver, debtPrincipal, 0);

        uint256 idleBefore = eveUSDC.balanceOf(address(vault));
        vm.warp(block.timestamp + 30 days);

        (uint256 previewFee,) = vault.previewAccruedAum();
        uint256 feeRecipientBefore = eveUSDC.balanceOf(feeRecipient);

        assertGt(previewFee, idleBefore);

        uint256 accruedFee = vault.accrueAum();

        assertEq(accruedFee, previewFee);
        assertEq(eveUSDC.balanceOf(feeRecipient) - feeRecipientBefore, idleBefore);
        assertEq(vault.unpaidAumFees(), previewFee - idleBefore);
        assertEq(eveUSDC.balanceOf(address(vault)), 0);
        assertEq(vault.totalAssets(), depositAssets - previewFee);
        assertEq(vault.totalAssets(), _managedAssets(vault));
    }

    function test_DepositAndRevenueSettlePreviouslyUnpaidAumFees() public {
        vault = _deployVault(10_000);

        uint256 depositAssets = 1_000e6;
        uint256 debtPrincipal = 990e6;
        uint256 bobDeposit = 20e6;
        uint256 revenueAssets = 20e6;

        _depositSeeded(alice, depositAssets, alice);
        _setLendingContract(address(this));

        vault.reportLoan(debtPrincipal);
        vault.disburseLoan(receiver, debtPrincipal, 0);

        uint256 idleBefore = eveUSDC.balanceOf(address(vault));
        vm.warp(block.timestamp + 30 days);
        (uint256 previewFee,) = vault.previewAccruedAum();
        assertGt(previewFee, idleBefore);

        vault.accrueAum();
        uint256 unpaidAfterAccrual = vault.unpaidAumFees();
        assertGt(unpaidAfterAccrual, bobDeposit + revenueAssets);

        _depositSeeded(bob, bobDeposit, bob);
        assertEq(vault.unpaidAumFees(), unpaidAfterAccrual - bobDeposit);

        _notifyRevenue(revenueAssets);
        assertEq(vault.unpaidAumFees(), unpaidAfterAccrual - bobDeposit - revenueAssets);
        assertEq(vault.totalAssets(), depositAssets - previewFee + bobDeposit + revenueAssets);
        assertEq(vault.totalAssets(), _managedAssets(vault));
    }
}
