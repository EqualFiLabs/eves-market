// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import {IMLOInsuranceFund} from "./interfaces/IMLOInsuranceFund.sol";

interface IMLOInsuranceGovernance {
    function owner() external view returns (address);
}

contract MLOInsuranceFund is IMLOInsuranceFund, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable override asset;
    address public immutable override governance;
    address public override riskManager;

    uint256 public override totalSponsored;
    uint256 public override totalFundingRevenue;
    uint256 public override totalProfitShare;
    uint256 public override totalDrawn;
    mapping(bytes32 => uint256) public override bucketFundingRevenue;
    mapping(bytes32 => uint256) public override bucketProfitShare;
    mapping(bytes32 => uint256) public override bucketDrawn;

    constructor(address asset_, address governance_, address riskManager_) {
        if (asset_ == address(0) || governance_ == address(0) || riskManager_ == address(0)) revert ZeroAddress();
        if (asset_.code.length == 0 || governance_.code.length == 0 || riskManager_.code.length == 0) {
            address missingCode =
                asset_.code.length == 0 ? asset_ : governance_.code.length == 0 ? governance_ : riskManager_;
            revert ContractHasNoCode(missingCode);
        }
        asset = asset_;
        governance = governance_;
        riskManager = riskManager_;
    }

    function owner() public view override returns (address) {
        return IMLOInsuranceGovernance(governance).owner();
    }

    function availableInsurance() external view override returns (uint256 assets) {
        assets = IERC20(asset).balanceOf(address(this));
    }

    function sponsor(uint256 assets) external override nonReentrant {
        _requireAmount(assets);
        _pullExact(msg.sender, assets);
        totalSponsored += assets;
        emit InsuranceSponsored(msg.sender, assets);
    }

    function notifyFundingRevenue(bytes32 bucketId, uint256 assets) external override nonReentrant {
        _enforceRiskManager();
        _requireAmount(assets);
        _pullExact(msg.sender, assets);
        totalFundingRevenue += assets;
        bucketFundingRevenue[bucketId] += assets;
        emit FundingRevenueReceived(bucketId, assets);
    }

    function notifyProfitShare(bytes32 bucketId, uint256 assets) external override nonReentrant {
        _enforceRiskManager();
        _requireAmount(assets);
        _pullExact(msg.sender, assets);
        totalProfitShare += assets;
        bucketProfitShare[bucketId] += assets;
        emit ProfitShareReceived(bucketId, assets);
    }

    function draw(bytes32 bucketId, address receiver, uint256 assets) external override nonReentrant {
        _enforceRiskManager();
        _requireAmount(assets);
        if (receiver == address(0)) revert ZeroAddress();
        uint256 available = IERC20(asset).balanceOf(address(this));
        if (assets > available) revert InsufficientInsurance(assets, available);
        totalDrawn += assets;
        bucketDrawn[bucketId] += assets;
        IERC20 token = IERC20(asset);
        uint256 receiverBefore = token.balanceOf(receiver);
        token.safeTransfer(receiver, assets);
        uint256 fundAfter = token.balanceOf(address(this));
        uint256 receiverAfter = token.balanceOf(receiver);
        uint256 debited = available >= fundAfter ? available - fundAfter : 0;
        uint256 credited = receiverAfter >= receiverBefore ? receiverAfter - receiverBefore : 0;
        if (debited != assets || credited != assets) revert NonExactTransfer(assets, debited, credited);
        emit InsuranceDrawn(bucketId, receiver, assets);
    }

    function setRiskManager(address newRiskManager) external override {
        if (msg.sender != owner()) revert NotOwner(msg.sender);
        if (newRiskManager == address(0)) revert ZeroAddress();
        if (newRiskManager.code.length == 0) revert ContractHasNoCode(newRiskManager);
        address previous = riskManager;
        riskManager = newRiskManager;
        emit RiskManagerSet(previous, newRiskManager);
    }

    function _enforceRiskManager() private view {
        if (msg.sender != riskManager) revert NotRiskManager(msg.sender);
    }

    function _requireAmount(uint256 assets) private pure {
        if (assets == 0) revert ZeroAmount();
    }

    function _pullExact(address from, uint256 assets) private {
        IERC20 token = IERC20(asset);
        uint256 balanceBefore = token.balanceOf(address(this));
        token.safeTransferFrom(from, address(this), assets);
        uint256 balanceAfter = token.balanceOf(address(this));
        uint256 credited = balanceAfter >= balanceBefore ? balanceAfter - balanceBefore : 0;
        if (credited != assets) revert NonExactTransfer(assets, assets, credited);
    }
}
