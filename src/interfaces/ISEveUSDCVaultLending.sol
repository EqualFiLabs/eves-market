// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface ISEveUSDCVaultLending {
    error NotLendingContract(address caller);

    event LendingContractSet(address indexed previousLending, address indexed newLending);

    function reportLoan(uint256 debtPrincipal) external;

    function reportRepayment(uint256 debtPrincipal) external;

    function reportDefault(uint256 debtPrincipal, uint256 recognizedLoss) external;

    function settleDefault(uint256 debtPrincipal, uint256 collateralShares)
        external
        returns (uint256 recoveredAssets, uint256 recognizedLoss);

    function disburseLoan(address recipient, uint256 borrowAmount, uint256 feeAmount) external;

    function setLendingContract(address lending) external;

    function outstandingPrincipal() external view returns (uint256);

    function recognizedLosses() external view returns (uint256);
}
