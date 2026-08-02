// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {SEveUSDCLending} from "../../src/SEveUSDCLending.sol";
import {ISEveUSDCLending} from "../../src/interfaces/ISEveUSDCLending.sol";

import {VaultTestBase} from "./VaultTestBase.sol";

contract ApprovedRouterHarness {}

abstract contract LendingTestBase is VaultTestBase {
    uint16 internal constant DEFAULT_MAX_LTV_BPS = 9_500;
    uint16 internal constant DEFAULT_ORIGINATION_FEE_BPS = 100;
    uint16 internal constant DEFAULT_EXTENSION_FEE_BPS = 50;
    uint16 internal constant DEFAULT_LENDING_FEE_RECIPIENT_BPS = 3_000;
    uint32 internal constant DEFAULT_MIN_DURATION = 1 days;
    uint32 internal constant DEFAULT_MAX_DURATION = 400 days;
    uint32 internal constant DEFAULT_GRACE_PERIOD = 1 days;

    SEveUSDCLending internal lending;
    address internal approvedRouter;
    address internal delegatedRecipient;

    function setUp() public virtual override {
        super.setUp();

        approvedRouter = address(new ApprovedRouterHarness());
        delegatedRecipient = makeAddr("delegated-recipient");

        lending = _deployLending();
        _setLendingContract(address(lending));
        _setDefaultLendingConfig();
    }

    function _deployLending() internal returns (SEveUSDCLending) {
        return new SEveUSDCLending(address(vault), address(eveUSDC), owner);
    }

    function _setDefaultLendingConfig() internal {
        _setLendingConfig(
            DEFAULT_MAX_LTV_BPS,
            DEFAULT_ORIGINATION_FEE_BPS,
            DEFAULT_EXTENSION_FEE_BPS,
            DEFAULT_MIN_DURATION,
            DEFAULT_MAX_DURATION,
            DEFAULT_GRACE_PERIOD
        );
        _setLendingFeeRecipientBps(DEFAULT_LENDING_FEE_RECIPIENT_BPS);
    }

    function _setLendingConfig(
        uint16 maxLtvBps,
        uint16 originationFeeBps,
        uint16 extensionFeeBps,
        uint32 minDurationSeconds,
        uint32 maxDurationSeconds,
        uint32 gracePeriodSeconds
    ) internal {
        vm.prank(owner);
        lending.setLendingConfig(
            maxLtvBps, originationFeeBps, extensionFeeBps, minDurationSeconds, maxDurationSeconds, gracePeriodSeconds
        );
    }

    function _setApprovedRouter(address router, bool approved) internal {
        vm.prank(owner);
        lending.setApprovedRouter(router, approved);
    }

    function _setLendingFeeRecipientBps(uint16 feeRecipientBps) internal {
        vm.prank(owner);
        lending.setLendingFeeRecipientBps(feeRecipientBps);
    }

    function _depositAndApproveShares(address account, uint256 assets) internal returns (uint256 shares) {
        shares = _depositSeeded(account, assets, account);

        vm.prank(account);
        vault.approve(address(lending), type(uint256).max);
    }

    function _seedDebtAndApprove(address payer, uint256 amount) internal {
        _seedEveUSDC(payer, amount);

        vm.prank(payer);
        eveUSDC.approve(address(lending), type(uint256).max);
    }

    function _directBorrow(
        address borrower,
        uint256 collateralShares,
        uint256 durationSeconds,
        uint256 borrowAmount,
        address recipient
    ) internal returns (uint256 loanId) {
        vm.prank(borrower);
        loanId = lending.borrow(collateralShares, durationSeconds, borrowAmount, recipient);
    }

    function _delegatedBorrow(
        address router,
        uint256 collateralShares,
        uint256 durationSeconds,
        uint256 borrowAmount,
        address recipient,
        address onBehalfOf
    ) internal returns (uint256 loanId) {
        vm.prank(router);
        loanId = lending.borrowFor(collateralShares, durationSeconds, borrowAmount, recipient, onBehalfOf);
    }

    function _directRepay(address borrower, uint256 loanId, bool redeemUnderlying, address recipient) internal {
        vm.prank(borrower);
        lending.repay(loanId, redeemUnderlying, recipient);
    }

    function _delegatedRepay(address router, uint256 loanId, bool redeemUnderlying, address recipient) internal {
        vm.prank(router);
        lending.repayFor(loanId, redeemUnderlying, recipient);
    }

    function _extendLoan(address borrower, uint256 loanId, uint256 additionalSeconds) internal {
        vm.prank(borrower);
        lending.extend(loanId, additionalSeconds);
    }

    function _recoverLoan(address caller, uint256 loanId) internal {
        vm.prank(caller);
        lending.recoverDefaultedLoan(loanId);
    }

    function _loanDebt(uint256 loanId) internal view returns (uint256) {
        return uint256(lending.loanState(loanId).debtPrincipal);
    }

    function _loanCollateral(uint256 loanId) internal view returns (uint256) {
        return uint256(lending.loanState(loanId).collateralShares);
    }

    function _loanExtensionFee(uint256 loanId) internal view returns (uint256) {
        ISEveUSDCLending.Loan memory loan = lending.loanState(loanId);
        return uint256(loan.debtPrincipal) * uint256(loan.extensionFeeBpsSnapshot) / 10_000;
    }

    function _netBorrowed(uint256 debtPrincipal, uint256 originationFee) internal pure returns (uint256) {
        return debtPrincipal - originationFee;
    }

    function _feeRecipientShare(uint256 feeAmount) internal view returns (uint256) {
        return feeAmount * lending.lendingFeeRecipientBps() / 10_000;
    }

    function _retainedFeeShare(uint256 feeAmount) internal view returns (uint256) {
        return feeAmount - _feeRecipientShare(feeAmount);
    }

    function _config() internal view returns (ISEveUSDCLending.LendingConfig memory cfg) {
        (
            cfg.maxLtvBps,
            cfg.originationFeeBps,
            cfg.extensionFeeBps,
            cfg.minDurationSeconds,
            cfg.maxDurationSeconds,
            cfg.gracePeriodSeconds
        ) = lending.config();
    }

    function _sumActiveCollateralShares() internal view returns (uint256 activeShares) {
        for (uint256 loanId = 1; loanId < lending.nextLoanId(); ++loanId) {
            ISEveUSDCLending.Loan memory loan = lending.loanState(loanId);
            if (!loan.repaid && !loan.defaultResolved) {
                activeShares += uint256(loan.collateralShares);
            }
        }
    }

    function _sumActiveDebtPrincipal() internal view returns (uint256 activeDebtPrincipal) {
        for (uint256 loanId = 1; loanId < lending.nextLoanId(); ++loanId) {
            ISEveUSDCLending.Loan memory loan = lending.loanState(loanId);
            if (!loan.repaid && !loan.defaultResolved) {
                activeDebtPrincipal += uint256(loan.debtPrincipal);
            }
        }
    }
}
