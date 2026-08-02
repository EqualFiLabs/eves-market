// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/// @notice Deprecated vault-share lending interface retained for transition to the senior margin pool.
interface ISEveUSDCLending {
    struct Loan {
        address borrower;
        uint128 collateralShares;
        uint128 netBorrowed;
        uint128 debtPrincipal;
        uint128 originationFeeCharged;
        uint64 startTime;
        uint64 maturityTime;
        uint32 durationSeconds;
        uint32 gracePeriodSecondsSnapshot;
        uint16 originationFeeBpsSnapshot;
        uint16 extensionFeeBpsSnapshot;
        bool repaid;
        bool defaultResolved;
    }

    struct LendingConfig {
        uint16 maxLtvBps;
        uint16 originationFeeBps;
        uint16 extensionFeeBps;
        uint32 minDurationSeconds;
        uint32 maxDurationSeconds;
        uint32 gracePeriodSeconds;
    }

    error ZeroAmount();
    error InvalidDuration(uint256 durationSeconds, uint256 min, uint256 max);
    error BorrowAmountExceedsMaxDebt(uint256 requestedDebt, uint256 maxDebt);
    error LendingPaused();
    error LoanAlreadyRepaid(uint256 loanId);
    error LoanAlreadyDefaultResolved(uint256 loanId);
    error LoanNotDefaulted(uint256 loanId);
    error RepaymentWindowExpired(uint256 loanId);
    error DurationExceedsMax(uint256 newDuration, uint256 max);
    error NotBorrower(address caller, address borrower);
    error NotApprovedRouter(address caller);
    error NotAuthorized(address caller);
    error InvalidConfig();
    error InvalidFeeRecipientBps(uint256 feeRecipientBps);
    error ZeroAddress();
    error ContractHasNoCode(address account);

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
    event LendingConfigUpdated();
    event LendingFeeRecipientBpsSet(uint16 previousBps, uint16 newBps);
    event RouterApprovalSet(address indexed router, bool approved);
    event Paused();
    event Unpaused();

    function borrow(uint256 collateralShares, uint256 durationSeconds, uint256 borrowAmount, address recipient)
        external
        returns (uint256 loanId);

    function repay(uint256 loanId, bool redeemUnderlying, address recipient) external;

    function extend(uint256 loanId, uint256 additionalSeconds) external;

    function borrowFor(
        uint256 collateralShares,
        uint256 durationSeconds,
        uint256 borrowAmount,
        address recipient,
        address onBehalfOf
    ) external returns (uint256 loanId);

    function repayFor(uint256 loanId, bool redeemUnderlying, address recipient) external;

    function recoverDefaultedLoan(uint256 loanId) external;

    function setLendingConfig(
        uint16 maxLtvBps,
        uint16 originationFeeBps,
        uint16 extensionFeeBps,
        uint32 minDurationSeconds,
        uint32 maxDurationSeconds,
        uint32 gracePeriodSeconds
    ) external;

    function setApprovedRouter(address router, bool approved) external;

    function setLendingFeeRecipientBps(uint16 feeRecipientBps) external;

    function pause() external;

    function unpause() external;

    function previewBorrowTerms(uint256 collateralShares, uint256 borrowAmount)
        external
        view
        returns (uint256 debtPrincipal, uint256 originationFee);

    function getBorrowerLoanIds(address borrower) external view returns (uint256[] memory loanIds);

    function getActiveBorrowerLoanIds(address borrower) external view returns (uint256[] memory loanIds);

    function previewRequiredRepayment(uint256 loanId) external view returns (uint256 repaymentAmount);

    function loanState(uint256 loanId) external view returns (Loan memory);

    function isDefaulted(uint256 loanId) external view returns (bool);

    function maxBorrowForShares(uint256 collateralShares) external view returns (uint256 maxBorrow);

    function lendingFeeRecipientBps() external view returns (uint16);
}
