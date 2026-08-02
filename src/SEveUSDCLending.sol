// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {SafeCast} from "../lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

import {ISEveUSDCLending} from "./interfaces/ISEveUSDCLending.sol";
import {ISEveUSDCVault} from "./interfaces/ISEveUSDCVault.sol";
import {ISEveUSDCVaultLending} from "./interfaces/ISEveUSDCVaultLending.sol";

/// @notice Deprecated vault-share lending module retained until the senior margin pool replacement lands.
contract SEveUSDCLending is ReentrancyGuard, ISEveUSDCLending {
    using SafeERC20 for IERC20;

    uint256 internal constant BPS_DENOMINATOR = 10_000;
    uint256 internal constant MAX_V1_LTV_BPS = 9_500;

    struct BorrowSnapshot {
        uint128 collateralShares;
        uint128 borrowAmount;
        uint128 debtPrincipal;
        uint128 originationFee;
        uint32 durationSeconds;
        uint64 startTime;
        uint64 maturityTime;
    }

    ISEveUSDCVault public immutable vault;
    IERC20 public immutable eveUSDC;
    address public immutable owner;

    LendingConfig public config;
    mapping(address => bool) public approvedRouters;
    bool public paused;
    uint16 public override lendingFeeRecipientBps;
    uint256 public nextLoanId;
    mapping(uint256 => Loan) public loans;
    mapping(address => uint256[]) internal borrowerLoanIds;
    uint256 public outstandingPrincipal;

    constructor(address vault_, address eveUSDC_, address owner_) {
        vault = ISEveUSDCVault(vault_);
        eveUSDC = IERC20(eveUSDC_);
        owner = owner_;
        nextLoanId = 1;
    }

    function borrow(uint256 collateralShares, uint256 durationSeconds, uint256 borrowAmount, address recipient)
        external
        override
        nonReentrant
        returns (uint256 loanId)
    {
        return _borrow(collateralShares, durationSeconds, borrowAmount, recipient, msg.sender, msg.sender);
    }

    function borrowFor(
        uint256 collateralShares,
        uint256 durationSeconds,
        uint256 borrowAmount,
        address recipient,
        address onBehalfOf
    ) external override nonReentrant returns (uint256 loanId) {
        _enforceApprovedRouter();
        return _borrow(collateralShares, durationSeconds, borrowAmount, recipient, onBehalfOf, msg.sender);
    }

    function repay(uint256 loanId, bool redeemUnderlying, address recipient) external override nonReentrant {
        Loan storage loan = _enforceActiveLoan(loanId);
        _enforceBorrower(loan, msg.sender);
        _repay(loanId, loan, msg.sender, redeemUnderlying, recipient);
    }

    function repayFor(uint256 loanId, bool redeemUnderlying, address recipient) external override nonReentrant {
        _enforceApprovedRouter();
        Loan storage loan = _enforceActiveLoan(loanId);
        _repay(loanId, loan, msg.sender, redeemUnderlying, recipient);
    }

    function extend(uint256 loanId, uint256 additionalSeconds) external override nonReentrant {
        _enforceNotPaused();

        if (additionalSeconds == 0) {
            revert ZeroAmount();
        }

        Loan storage loan = _enforceActiveLoan(loanId);
        _enforceBorrower(loan, msg.sender);

        if (block.timestamp >= loan.maturityTime) {
            revert RepaymentWindowExpired(loanId);
        }

        uint256 newDuration = uint256(loan.durationSeconds) + additionalSeconds;
        if (newDuration > config.maxDurationSeconds) {
            revert DurationExceedsMax(newDuration, config.maxDurationSeconds);
        }

        uint256 extensionFee =
            Math.mulDiv(uint256(loan.debtPrincipal), uint256(loan.extensionFeeBpsSnapshot), BPS_DENOMINATOR);

        loan.durationSeconds = SafeCast.toUint32(newDuration);
        loan.maturityTime = SafeCast.toUint64(uint256(loan.maturityTime) + additionalSeconds);

        if (extensionFee != 0) {
            _collectLendingFee(msg.sender, extensionFee);
        }

        emit LoanExtended(loanId, additionalSeconds, loan.maturityTime, SafeCast.toUint128(extensionFee));
    }

    function recoverDefaultedLoan(uint256 loanId) external override nonReentrant {
        Loan storage loan = _enforceActiveLoan(loanId);
        if (!isDefaulted(loanId)) {
            revert LoanNotDefaulted(loanId);
        }

        uint256 debtPrincipal = loan.debtPrincipal;
        uint128 collateralShares = loan.collateralShares;

        loan.defaultResolved = true;
        outstandingPrincipal -= debtPrincipal;

        (uint256 recovered, uint256 recognizedLoss) = _vaultLending().settleDefault(debtPrincipal, collateralShares);

        emit LoanDefaultRecovered(loanId, collateralShares, 0, recovered, recognizedLoss);
    }

    function setLendingConfig(
        uint16 maxLtvBps,
        uint16 originationFeeBps,
        uint16 extensionFeeBps,
        uint32 minDurationSeconds,
        uint32 maxDurationSeconds,
        uint32 gracePeriodSeconds
    ) external override {
        _enforceOwner();

        if (
            maxLtvBps > MAX_V1_LTV_BPS || originationFeeBps >= BPS_DENOMINATOR || extensionFeeBps > BPS_DENOMINATOR
                || minDurationSeconds > maxDurationSeconds
        ) {
            revert InvalidConfig();
        }

        config = LendingConfig({
            maxLtvBps: maxLtvBps,
            originationFeeBps: originationFeeBps,
            extensionFeeBps: extensionFeeBps,
            minDurationSeconds: minDurationSeconds,
            maxDurationSeconds: maxDurationSeconds,
            gracePeriodSeconds: gracePeriodSeconds
        });

        emit LendingConfigUpdated();
    }

    function setLendingFeeRecipientBps(uint16 feeRecipientBps) external override {
        _enforceOwner();
        if (feeRecipientBps > BPS_DENOMINATOR) {
            revert InvalidFeeRecipientBps(feeRecipientBps);
        }

        uint16 previousBps = lendingFeeRecipientBps;
        lendingFeeRecipientBps = feeRecipientBps;

        emit LendingFeeRecipientBpsSet(previousBps, feeRecipientBps);
    }

    function setApprovedRouter(address router, bool approved) external override {
        _enforceOwner();
        if (approved) {
            if (router == address(0)) {
                revert ZeroAddress();
            }
            if (router.code.length == 0) {
                revert ContractHasNoCode(router);
            }
        }
        approvedRouters[router] = approved;
        emit RouterApprovalSet(router, approved);
    }

    function pause() external override {
        _enforceOwner();
        paused = true;
        emit Paused();
    }

    function unpause() external override {
        _enforceOwner();
        paused = false;
        emit Unpaused();
    }

    function previewBorrowTerms(uint256, uint256 borrowAmount)
        external
        view
        override
        returns (uint256 debtPrincipal, uint256 originationFee)
    {
        debtPrincipal = borrowAmount;
        originationFee = Math.mulDiv(debtPrincipal, config.originationFeeBps, BPS_DENOMINATOR);
    }

    function getBorrowerLoanIds(address borrower) external view override returns (uint256[] memory loanIds) {
        return borrowerLoanIds[borrower];
    }

    function getActiveBorrowerLoanIds(address borrower) external view override returns (uint256[] memory loanIds) {
        uint256[] storage allLoanIds = borrowerLoanIds[borrower];
        uint256 activeCount;

        for (uint256 i = 0; i < allLoanIds.length; i++) {
            if (_isLoanActive(loans[allLoanIds[i]])) {
                activeCount++;
            }
        }

        loanIds = new uint256[](activeCount);
        uint256 cursor;

        for (uint256 i = 0; i < allLoanIds.length; i++) {
            uint256 loanId = allLoanIds[i];
            if (_isLoanActive(loans[loanId])) {
                loanIds[cursor] = loanId;
                cursor++;
            }
        }
    }

    function previewRequiredRepayment(uint256 loanId) external view override returns (uint256 repaymentAmount) {
        repaymentAmount = loans[loanId].debtPrincipal;
    }

    function loanState(uint256 loanId) external view override returns (Loan memory) {
        return loans[loanId];
    }

    function isDefaulted(uint256 loanId) public view override returns (bool) {
        return _isLoanDefaulted(loans[loanId]);
    }

    function maxBorrowForShares(uint256 collateralShares) public view override returns (uint256 maxBorrow) {
        uint256 collateralAssets = vault.convertToAssets(collateralShares);
        maxBorrow = Math.mulDiv(collateralAssets, config.maxLtvBps, BPS_DENOMINATOR);
    }

    function _borrow(
        uint256 collateralShares,
        uint256 durationSeconds,
        uint256 borrowAmount,
        address recipient,
        address borrower,
        address collateralSource
    ) internal returns (uint256 loanId) {
        _enforceNotPaused();

        if (collateralShares == 0 || borrowAmount == 0) {
            revert ZeroAmount();
        }
        if (durationSeconds < config.minDurationSeconds || durationSeconds > config.maxDurationSeconds) {
            revert InvalidDuration(durationSeconds, config.minDurationSeconds, config.maxDurationSeconds);
        }

        uint256 collateralAssets = vault.convertToAssets(collateralShares);
        uint256 maxDebt = Math.mulDiv(collateralAssets, config.maxLtvBps, BPS_DENOMINATOR);
        uint256 debtPrincipal = borrowAmount;
        uint256 originationFee = Math.mulDiv(debtPrincipal, config.originationFeeBps, BPS_DENOMINATOR);
        uint256 netBorrowed = debtPrincipal - originationFee;
        if (netBorrowed == 0) {
            revert ZeroAmount();
        }

        if (debtPrincipal > maxDebt) {
            revert BorrowAmountExceedsMaxDebt(debtPrincipal, maxDebt);
        }

        loanId = nextLoanId;
        nextLoanId = loanId + 1;
        outstandingPrincipal += debtPrincipal;

        BorrowSnapshot memory snapshot = BorrowSnapshot({
            collateralShares: SafeCast.toUint128(collateralShares),
            borrowAmount: SafeCast.toUint128(netBorrowed),
            debtPrincipal: SafeCast.toUint128(debtPrincipal),
            originationFee: SafeCast.toUint128(originationFee),
            durationSeconds: SafeCast.toUint32(durationSeconds),
            startTime: SafeCast.toUint64(block.timestamp),
            maturityTime: SafeCast.toUint64(block.timestamp + durationSeconds)
        });

        _recordLoan(loanId, borrower, snapshot);

        IERC20(address(vault)).safeTransferFrom(collateralSource, address(this), collateralShares);
        _vaultLending().reportLoan(debtPrincipal);
        _vaultLending().disburseLoan(recipient, netBorrowed, _feeRecipientShare(originationFee));
        _emitLoanCreated(loanId, borrower, snapshot, recipient);
    }

    function _collectLendingFee(address payer, uint256 feeAmount) internal {
        uint256 recipientShare = _feeRecipientShare(feeAmount);
        uint256 retainedShare = feeAmount - recipientShare;

        if (retainedShare != 0) {
            eveUSDC.safeTransferFrom(payer, address(vault), retainedShare);
        }
        if (recipientShare != 0) {
            eveUSDC.safeTransferFrom(payer, vault.feeRecipient(), recipientShare);
        }
    }

    function _feeRecipientShare(uint256 feeAmount) internal view returns (uint256) {
        return Math.mulDiv(feeAmount, lendingFeeRecipientBps, BPS_DENOMINATOR);
    }

    function _repay(uint256 loanId, Loan storage loan, address payer, bool redeemUnderlying, address recipient)
        internal
    {
        if (block.timestamp > uint256(loan.maturityTime) + uint256(loan.gracePeriodSecondsSnapshot)) {
            revert RepaymentWindowExpired(loanId);
        }

        uint256 debtPrincipal = loan.debtPrincipal;
        uint128 collateralShares = loan.collateralShares;
        address borrower = loan.borrower;

        loan.repaid = true;
        outstandingPrincipal -= debtPrincipal;

        eveUSDC.safeTransferFrom(payer, address(vault), debtPrincipal);
        _vaultLending().reportRepayment(debtPrincipal);

        uint256 eveUSDCReturnedFromCollateral;
        if (redeemUnderlying) {
            eveUSDCReturnedFromCollateral = vault.redeem(collateralShares, recipient, address(this));
        } else {
            IERC20(address(vault)).safeTransfer(borrower, collateralShares);
        }

        emit LoanRepaid(
            loanId,
            collateralShares == 0 ? 0 : SafeCast.toUint128(debtPrincipal),
            redeemUnderlying,
            eveUSDCReturnedFromCollateral
        );
    }

    function _vaultLending() internal view returns (ISEveUSDCVaultLending) {
        return ISEveUSDCVaultLending(address(vault));
    }

    function _recordLoan(uint256 loanId, address borrower, BorrowSnapshot memory snapshot) internal {
        loans[loanId] = Loan({
            borrower: borrower,
            collateralShares: snapshot.collateralShares,
            netBorrowed: snapshot.borrowAmount,
            debtPrincipal: snapshot.debtPrincipal,
            originationFeeCharged: snapshot.originationFee,
            startTime: snapshot.startTime,
            maturityTime: snapshot.maturityTime,
            durationSeconds: snapshot.durationSeconds,
            gracePeriodSecondsSnapshot: config.gracePeriodSeconds,
            originationFeeBpsSnapshot: config.originationFeeBps,
            extensionFeeBpsSnapshot: config.extensionFeeBps,
            repaid: false,
            defaultResolved: false
        });

        borrowerLoanIds[borrower].push(loanId);
    }

    function _emitLoanCreated(uint256 loanId, address borrower, BorrowSnapshot memory snapshot, address recipient)
        internal
    {
        emit LoanCreated(
            loanId,
            borrower,
            snapshot.collateralShares,
            snapshot.borrowAmount,
            snapshot.debtPrincipal,
            snapshot.originationFee,
            snapshot.maturityTime,
            recipient
        );
    }

    function _enforceActiveLoan(uint256 loanId) internal view returns (Loan storage loan) {
        loan = loans[loanId];
        if (loan.repaid) {
            revert LoanAlreadyRepaid(loanId);
        }
        if (loan.defaultResolved) {
            revert LoanAlreadyDefaultResolved(loanId);
        }
    }

    function _enforceBorrower(Loan storage loan, address caller) internal view {
        if (caller != loan.borrower) {
            revert NotBorrower(caller, loan.borrower);
        }
    }

    function _enforceOwner() internal view {
        if (msg.sender != owner) {
            revert NotAuthorized(msg.sender);
        }
    }

    function _enforceNotPaused() internal view {
        if (paused) {
            revert LendingPaused();
        }
    }

    function _enforceApprovedRouter() internal view {
        if (!approvedRouters[msg.sender]) {
            revert NotApprovedRouter(msg.sender);
        }
    }

    function _isLoanDefaulted(Loan storage loan) internal view returns (bool) {
        if (loan.borrower == address(0) || loan.repaid || loan.defaultResolved) {
            return false;
        }

        return block.timestamp > uint256(loan.maturityTime) + uint256(loan.gracePeriodSecondsSnapshot);
    }

    function _isLoanActive(Loan storage loan) internal view returns (bool) {
        return loan.borrower != address(0) && !loan.repaid && !loan.defaultResolved && !_isLoanDefaulted(loan);
    }
}
