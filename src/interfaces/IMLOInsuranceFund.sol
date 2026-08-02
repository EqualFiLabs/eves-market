// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IMLOInsuranceFund {
    error ZeroAddress();
    error ZeroAmount();
    error NotOwner(address caller);
    error NotRiskManager(address caller);
    error ContractHasNoCode(address account);
    error InsufficientInsurance(uint256 requested, uint256 available);
    error NonExactTransfer(uint256 expected, uint256 debited, uint256 credited);

    event InsuranceSponsored(address indexed sponsor, uint256 assets);
    event FundingRevenueReceived(bytes32 indexed bucketId, uint256 assets);
    event ProfitShareReceived(bytes32 indexed bucketId, uint256 assets);
    event InsuranceDrawn(bytes32 indexed bucketId, address indexed receiver, uint256 assets);
    event RiskManagerSet(address indexed previousRiskManager, address indexed newRiskManager);

    function asset() external view returns (address);
    function governance() external view returns (address);
    function owner() external view returns (address);
    function riskManager() external view returns (address);
    function availableInsurance() external view returns (uint256 assets);
    function totalSponsored() external view returns (uint256 assets);
    function totalFundingRevenue() external view returns (uint256 assets);
    function totalProfitShare() external view returns (uint256 assets);
    function totalDrawn() external view returns (uint256 assets);
    function bucketFundingRevenue(bytes32 bucketId) external view returns (uint256 assets);
    function bucketProfitShare(bytes32 bucketId) external view returns (uint256 assets);
    function bucketDrawn(bytes32 bucketId) external view returns (uint256 assets);
    function sponsor(uint256 assets) external;
    function notifyFundingRevenue(bytes32 bucketId, uint256 assets) external;
    function notifyProfitShare(bytes32 bucketId, uint256 assets) external;
    function draw(bytes32 bucketId, address receiver, uint256 assets) external;
    function setRiskManager(address newRiskManager) external;
}
