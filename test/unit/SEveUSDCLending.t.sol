// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISEveUSDCLending} from "../../src/interfaces/ISEveUSDCLending.sol";

import {LendingTestBase} from "../helpers/LendingTestBase.sol";

contract SEveUSDCLendingTest is LendingTestBase {
    event LoanCreated(
        uint256 indexed loanId,
        address indexed borrower,
        uint128 collateralShares,
        uint128 netBorrowed,
        uint128 debtPrincipal,
        uint128 originationFeeCharged,
        uint64 maturityTime,
        address recipient
    );
    event LoanRepaid(
        uint256 indexed loanId, uint128 repaymentAmount, bool redeemUnderlying, uint256 eveUSDCReturnedFromCollateral
    );
    event LoanExtended(uint256 indexed loanId, uint256 additionalSeconds, uint64 newMaturityTime, uint128 extensionFee);
    event LoanDefaultRecovered(
        uint256 indexed loanId,
        uint128 sharesSeized,
        uint256 eveUSDCRecovered,
        uint256 eveUSDCRetainedInVault,
        uint256 recognizedLoss
    );
    event RouterApprovalSet(address indexed router, bool approved);
    event Paused();
    event Unpaused();

    function test_BasicLifecycleDepositBorrowRepayReturnsShares() public {
        uint256 depositAssets = 1_000e6;
        uint256 collateralShares = 400e6;
        uint256 borrowAmount = 300e6;
        uint256 durationSeconds = 7 days;

        uint256 aliceShares = _depositAndApproveShares(alice, depositAssets);
        uint256 expectedLoanId = lending.nextLoanId();
        (uint256 debtPrincipal, uint256 originationFee) = lending.previewBorrowTerms(collateralShares, borrowAmount);
        uint256 netBorrowed = _netBorrowed(debtPrincipal, originationFee);
        uint256 feeRecipientShare = _feeRecipientShare(originationFee);
        uint256 retainedFeeShare = _retainedFeeShare(originationFee);

        vm.expectEmit(true, true, false, true, address(lending));
        emit LoanCreated(
            expectedLoanId,
            alice,
            uint128(collateralShares),
            uint128(netBorrowed),
            uint128(debtPrincipal),
            uint128(originationFee),
            uint64(block.timestamp + durationSeconds),
            receiver
        );

        uint256 loanId = _directBorrow(alice, collateralShares, durationSeconds, borrowAmount, receiver);

        ISEveUSDCLending.Loan memory loan = lending.loanState(loanId);
        assertEq(loan.borrower, alice);
        assertEq(loan.collateralShares, collateralShares);
        assertEq(loan.netBorrowed, netBorrowed);
        assertEq(loan.debtPrincipal, debtPrincipal);
        assertEq(loan.originationFeeCharged, originationFee);
        assertEq(loan.durationSeconds, durationSeconds);
        assertEq(eveUSDC.balanceOf(receiver), netBorrowed);
        assertEq(eveUSDC.balanceOf(feeRecipient), feeRecipientShare);
        assertEq(vault.balanceOf(address(lending)), collateralShares);
        assertEq(vault.balanceOf(alice), aliceShares - collateralShares);
        assertEq(lending.outstandingPrincipal(), debtPrincipal);
        assertEq(vault.outstandingPrincipal(), debtPrincipal);
        assertEq(vault.totalAssets(), depositAssets + retainedFeeShare);

        _seedDebtAndApprove(alice, debtPrincipal);

        vm.expectEmit(true, false, false, true, address(lending));
        emit LoanRepaid(loanId, uint128(debtPrincipal), false, 0);

        _directRepay(alice, loanId, false, carol);

        loan = lending.loanState(loanId);
        assertTrue(loan.repaid);
        assertFalse(loan.defaultResolved);
        assertEq(lending.outstandingPrincipal(), 0);
        assertEq(vault.outstandingPrincipal(), 0);
        assertEq(vault.balanceOf(address(lending)), 0);
        assertEq(vault.balanceOf(alice), aliceShares);
        assertEq(vault.totalAssets(), depositAssets + retainedFeeShare);
    }

    function test_RepayCanRedeemUnderlyingToRecipient() public {
        uint256 collateralShares = 400e6;
        uint256 borrowAmount = 300e6;

        _depositAndApproveShares(alice, 1_000e6);
        uint256 loanId = _directBorrow(alice, collateralShares, 14 days, borrowAmount, alice);

        _notifyRevenue(100e6);

        ISEveUSDCLending.Loan memory loan = lending.loanState(loanId);
        uint256 expectedAssetsOut = vault.previewRedeem(collateralShares);

        _seedDebtAndApprove(alice, uint256(loan.debtPrincipal));

        uint256 receiverBefore = eveUSDC.balanceOf(receiver);

        vm.expectEmit(true, false, false, true, address(lending));
        emit LoanRepaid(loanId, loan.debtPrincipal, true, expectedAssetsOut);

        _directRepay(alice, loanId, true, receiver);

        assertEq(eveUSDC.balanceOf(receiver) - receiverBefore, expectedAssetsOut);
        assertEq(vault.balanceOf(address(lending)), 0);
        assertEq(vault.balanceOf(alice), 600e6);
        assertEq(lending.outstandingPrincipal(), 0);
    }

    function test_ApprovedRouterCanBorrowForBorrower() public {
        uint256 collateralShares = 300e6;
        uint256 borrowAmount = 200e6;
        uint256 durationSeconds = 10 days;

        _depositAndApproveShares(approvedRouter, 500e6);
        _setApprovedRouter(approvedRouter, true);

        uint256 expectedLoanId = lending.nextLoanId();
        (uint256 debtPrincipal, uint256 originationFee) = lending.previewBorrowTerms(collateralShares, borrowAmount);
        uint256 netBorrowed = _netBorrowed(debtPrincipal, originationFee);

        vm.expectEmit(true, true, false, true, address(lending));
        emit LoanCreated(
            expectedLoanId,
            alice,
            uint128(collateralShares),
            uint128(netBorrowed),
            uint128(debtPrincipal),
            uint128(originationFee),
            uint64(block.timestamp + durationSeconds),
            delegatedRecipient
        );

        uint256 loanId = _delegatedBorrow(
            approvedRouter, collateralShares, durationSeconds, borrowAmount, delegatedRecipient, alice
        );

        ISEveUSDCLending.Loan memory loan = lending.loanState(loanId);
        assertEq(loan.borrower, alice);
        assertEq(vault.balanceOf(address(lending)), collateralShares);
        assertEq(vault.balanceOf(approvedRouter), 200e6);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(eveUSDC.balanceOf(delegatedRecipient), netBorrowed);
    }

    function test_ApprovedRouterCanRepayForBorrowerAndReturnShares() public {
        uint256 collateralShares = 300e6;
        uint256 borrowAmount = 200e6;

        _depositAndApproveShares(approvedRouter, 500e6);
        _setApprovedRouter(approvedRouter, true);

        uint256 loanId = _delegatedBorrow(approvedRouter, collateralShares, 10 days, borrowAmount, receiver, alice);
        uint256 debtPrincipal = _loanDebt(loanId);

        _seedDebtAndApprove(approvedRouter, debtPrincipal);

        vm.expectEmit(true, false, false, true, address(lending));
        emit LoanRepaid(loanId, uint128(debtPrincipal), false, 0);

        _delegatedRepay(approvedRouter, loanId, false, receiver);

        ISEveUSDCLending.Loan memory loan = lending.loanState(loanId);
        assertTrue(loan.repaid);
        assertEq(vault.balanceOf(alice), collateralShares);
        assertEq(vault.balanceOf(address(lending)), 0);
        assertEq(lending.outstandingPrincipal(), 0);
    }

    function test_BorrowerLoanIndexTracksHistoryAndFiltersActiveLoans() public {
        _depositAndApproveShares(alice, 1_500e6);
        _depositAndApproveShares(bob, 800e6);
        _depositAndApproveShares(approvedRouter, 500e6);
        _setApprovedRouter(approvedRouter, true);

        uint256 aliceLoanOne = _directBorrow(alice, 300e6, 7 days, 200e6, alice);
        uint256 aliceLoanTwo = _directBorrow(alice, 250e6, 2 days, 150e6, alice);
        uint256 aliceDelegatedLoan = _delegatedBorrow(approvedRouter, 200e6, 10 days, 100e6, delegatedRecipient, alice);
        uint256 bobLoan = _directBorrow(bob, 200e6, 14 days, 100e6, bob);

        uint256[] memory aliceLoanIds = lending.getBorrowerLoanIds(alice);
        assertEq(aliceLoanIds.length, 3);
        assertEq(aliceLoanIds[0], aliceLoanOne);
        assertEq(aliceLoanIds[1], aliceLoanTwo);
        assertEq(aliceLoanIds[2], aliceDelegatedLoan);

        uint256[] memory bobLoanIds = lending.getBorrowerLoanIds(bob);
        assertEq(bobLoanIds.length, 1);
        assertEq(bobLoanIds[0], bobLoan);

        uint256[] memory initialActiveLoanIds = lending.getActiveBorrowerLoanIds(alice);
        assertEq(initialActiveLoanIds.length, 3);
        assertEq(initialActiveLoanIds[0], aliceLoanOne);
        assertEq(initialActiveLoanIds[1], aliceLoanTwo);
        assertEq(initialActiveLoanIds[2], aliceDelegatedLoan);

        _seedDebtAndApprove(alice, _loanDebt(aliceLoanOne));
        _directRepay(alice, aliceLoanOne, false, alice);

        vm.warp(block.timestamp + 4 days);

        uint256[] memory filteredActiveLoanIds = lending.getActiveBorrowerLoanIds(alice);
        assertEq(filteredActiveLoanIds.length, 1);
        assertEq(filteredActiveLoanIds[0], aliceDelegatedLoan);

        aliceLoanIds = lending.getBorrowerLoanIds(alice);
        assertEq(aliceLoanIds.length, 3);
        assertEq(aliceLoanIds[0], aliceLoanOne);
        assertEq(aliceLoanIds[1], aliceLoanTwo);
        assertEq(aliceLoanIds[2], aliceDelegatedLoan);
    }

    function test_ExtendWorksBeforeMaturityAndFailsAfterMaturity() public {
        uint256 collateralShares = 400e6;
        uint256 borrowAmount = 300e6;
        uint256 initialDuration = 7 days;
        uint256 additionalSeconds = 3 days;

        _depositAndApproveShares(alice, 1_000e6);
        uint256 loanId = _directBorrow(alice, collateralShares, initialDuration, borrowAmount, alice);

        ISEveUSDCLending.Loan memory loanBefore = lending.loanState(loanId);
        uint256 expectedExtensionFee = _loanExtensionFee(loanId);
        uint256 expectedRecipientShare = _feeRecipientShare(expectedExtensionFee);
        uint256 feeRecipientBefore = eveUSDC.balanceOf(feeRecipient);
        uint256 vaultAssetsBefore = vault.totalAssets();

        vm.prank(alice);
        eveUSDC.approve(address(lending), type(uint256).max);

        vm.expectEmit(true, false, false, true, address(lending));
        emit LoanExtended(
            loanId,
            additionalSeconds,
            uint64(uint256(loanBefore.maturityTime) + additionalSeconds),
            uint128(expectedExtensionFee)
        );

        _extendLoan(alice, loanId, additionalSeconds);

        ISEveUSDCLending.Loan memory loanAfter = lending.loanState(loanId);
        assertEq(loanAfter.durationSeconds, initialDuration + additionalSeconds);
        assertEq(loanAfter.maturityTime, loanBefore.maturityTime + additionalSeconds);
        assertEq(eveUSDC.balanceOf(feeRecipient) - feeRecipientBefore, expectedRecipientShare);
        assertEq(vault.totalAssets() - vaultAssetsBefore, expectedExtensionFee - expectedRecipientShare);

        vm.warp(loanAfter.maturityTime);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ISEveUSDCLending.RepaymentWindowExpired.selector, loanId));
        lending.extend(loanId, 1 days);
    }

    function test_DefaultRecoveryWithSurplusRetainsValueInVaultNav() public {
        vm.prank(owner);
        vault.setAumFeeBps(0);
        _setLendingConfig(9_500, 0, 0, 1 days, 30 days, 1 days);

        uint256 collateralShares = 200e6;
        uint256 borrowAmount = 150e6;

        _depositAndApproveShares(alice, 1_000e6);
        uint256 loanId = _directBorrow(alice, collateralShares, 2 days, borrowAmount, alice);

        _notifyRevenue(50e6);

        vm.warp(block.timestamp + 4 days);
        uint256 expectedRecovered = vault.previewRedeem(collateralShares);
        uint256 expectedTotalAssets = eveUSDC.balanceOf(address(vault));

        vm.expectEmit(true, false, false, true, address(lending));
        emit LoanDefaultRecovered(loanId, uint128(collateralShares), 0, expectedRecovered, 0);

        _recoverLoan(carol, loanId);

        ISEveUSDCLending.Loan memory loan = lending.loanState(loanId);
        assertTrue(loan.defaultResolved);
        assertEq(lending.outstandingPrincipal(), 0);
        assertEq(vault.outstandingPrincipal(), 0);
        assertEq(vault.recognizedLosses(), 0);
        assertEq(vault.balanceOf(address(lending)), 0);
        assertEq(vault.totalAssets(), expectedTotalAssets);
        assertGt(expectedRecovered, borrowAmount);
    }

    function test_DefaultRecoveryWithShortfallRecordsRecognizedLoss() public {
        vm.prank(owner);
        vault.setAumFeeBps(10_000);
        _setLendingConfig(9_500, 0, 0, 1 days, 400 days, 1 days);

        uint256 collateralShares = 200e6;
        uint256 borrowAmount = lending.maxBorrowForShares(collateralShares);
        uint256 durationSeconds = 365 days;

        _depositAndApproveShares(alice, 1_000e6);
        uint256 loanId = _directBorrow(alice, collateralShares, durationSeconds, borrowAmount, alice);

        vm.warp(block.timestamp + durationSeconds + 1 days + 1);

        uint256 debtPrincipal = _loanDebt(loanId);
        uint256 onHandBeforeRecovery = eveUSDC.balanceOf(address(vault));
        (uint256 previewFeeAssets,) = vault.previewAccruedAum();
        uint256 onHandAfterAccrual = onHandBeforeRecovery - previewFeeAssets;
        uint256 expectedRecovered = vault.previewRedeem(collateralShares);
        uint256 expectedLoss = debtPrincipal - expectedRecovered;
        uint256 expectedTotalAssets = onHandAfterAccrual - expectedLoss;

        assertGt(previewFeeAssets, 0);
        assertGt(expectedLoss, 0);

        vm.expectEmit(true, false, false, true, address(lending));
        emit LoanDefaultRecovered(loanId, uint128(collateralShares), 0, expectedRecovered, expectedLoss);

        _recoverLoan(carol, loanId);

        ISEveUSDCLending.Loan memory loan = lending.loanState(loanId);
        assertTrue(loan.defaultResolved);
        assertEq(lending.outstandingPrincipal(), 0);
        assertEq(vault.outstandingPrincipal(), 0);
        assertEq(vault.recognizedLosses(), expectedLoss);
        assertEq(vault.totalAssets(), expectedTotalAssets);
        assertEq(vault.totalAssets(), _managedAssets(vault));
    }

    function test_DefaultRecoveryUsesInternalAccountingWhenVaultIsIlliquid() public {
        vm.prank(owner);
        vault.setAumFeeBps(0);
        _setLendingConfig(9_500, 0, 0, 1 days, 30 days, 1 days);

        uint256 aliceCollateralShares = _depositAndApproveShares(alice, 1_000e6);
        uint256 bobCollateralShares = _depositAndApproveShares(bob, 1_000e6);
        uint256 aliceBorrowAmount = lending.maxBorrowForShares(aliceCollateralShares);
        uint256 bobBorrowAmount = lending.maxBorrowForShares(bobCollateralShares);

        uint256 aliceLoanId = _directBorrow(alice, aliceCollateralShares, 2 days, aliceBorrowAmount, alice);
        _directBorrow(bob, bobCollateralShares, 2 days, bobBorrowAmount, bob);

        vm.warp(block.timestamp + 4 days);

        uint256 idleAssets = eveUSDC.balanceOf(address(vault));
        uint256 expectedRecovered = vault.previewRedeem(aliceCollateralShares);
        uint256 bobDebt = bobBorrowAmount;

        assertLt(idleAssets, expectedRecovered);

        _recoverLoan(carol, aliceLoanId);

        ISEveUSDCLending.Loan memory loan = lending.loanState(aliceLoanId);
        assertTrue(loan.defaultResolved);
        assertEq(lending.outstandingPrincipal(), bobDebt);
        assertEq(vault.outstandingPrincipal(), bobDebt);
        assertEq(vault.recognizedLosses(), 0);
        assertEq(vault.balanceOf(address(lending)), bobCollateralShares);
        assertEq(vault.totalAssets(), idleAssets + bobDebt);
    }

    function test_PauseAllowsRepayAndRecoveryButBlocksBorrowAndExtend() public {
        _setLendingConfig(9_500, 0, 0, 1 days, 30 days, 1 days);

        _depositAndApproveShares(alice, 1_000e6);
        uint256 repayLoanId = _directBorrow(alice, 300e6, 7 days, 200e6, alice);
        uint256 defaultLoanId = _directBorrow(alice, 200e6, 2 days, 100e6, alice);

        vm.prank(owner);
        lending.pause();

        vm.prank(alice);
        vm.expectRevert(ISEveUSDCLending.LendingPaused.selector);
        lending.borrow(100e6, 7 days, 50e6, alice);

        vm.prank(alice);
        vm.expectRevert(ISEveUSDCLending.LendingPaused.selector);
        lending.extend(repayLoanId, 1 days);

        _seedDebtAndApprove(alice, _loanDebt(repayLoanId));
        _directRepay(alice, repayLoanId, false, alice);

        vm.warp(block.timestamp + 4 days);
        _recoverLoan(carol, defaultLoanId);

        assertTrue(lending.loanState(repayLoanId).repaid);
        assertTrue(lending.loanState(defaultLoanId).defaultResolved);
        assertEq(vault.balanceOf(address(lending)), 0);
    }

    function test_RouterAccessControlRevertsForUnapprovedDelegation() public {
        _depositAndApproveShares(approvedRouter, 500e6);

        vm.prank(approvedRouter);
        vm.expectRevert(abi.encodeWithSelector(ISEveUSDCLending.NotApprovedRouter.selector, approvedRouter));
        lending.borrowFor(300e6, 10 days, 200e6, delegatedRecipient, alice);

        _depositAndApproveShares(alice, 500e6);
        uint256 loanId = _directBorrow(alice, 200e6, 7 days, 100e6, alice);
        _seedDebtAndApprove(approvedRouter, _loanDebt(loanId));

        vm.prank(approvedRouter);
        vm.expectRevert(abi.encodeWithSelector(ISEveUSDCLending.NotApprovedRouter.selector, approvedRouter));
        lending.repayFor(loanId, false, receiver);
    }

    function test_AdminAndRouterEventsEmit() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, true, address(lending));
        emit RouterApprovalSet(approvedRouter, true);
        lending.setApprovedRouter(approvedRouter, true);

        vm.prank(owner);
        vm.expectEmit(false, false, false, true, address(lending));
        emit Paused();
        lending.pause();

        vm.prank(owner);
        vm.expectEmit(false, false, false, true, address(lending));
        emit Unpaused();
        lending.unpause();
    }

    function test_RevertWhen_ApprovedRouterIsZeroOrNonContract() public {
        address nonContractRouter = makeAddr("non-contract-router");

        vm.prank(owner);
        vm.expectRevert(ISEveUSDCLending.ZeroAddress.selector);
        lending.setApprovedRouter(address(0), true);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ISEveUSDCLending.ContractHasNoCode.selector, nonContractRouter));
        lending.setApprovedRouter(nonContractRouter, true);

        vm.prank(owner);
        lending.setApprovedRouter(address(0), false);
        assertFalse(lending.approvedRouters(address(0)));
    }
}
