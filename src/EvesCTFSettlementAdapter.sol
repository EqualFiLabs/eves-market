// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC1155} from "../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";
import {ERC1155Holder} from "../lib/openzeppelin-contracts/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import {IGnosisConditionalTokens} from "./interfaces/IGnosisConditionalTokens.sol";
import {IEvesCTFSettlementAdapter} from "./interfaces/IEvesCTFSettlementAdapter.sol";

/// @notice Exact-amount custody boundary for canonical Gnosis CTF positions.
/// @dev CTF redemption consumes the caller's selected balances. Moving only the requested
///      amount here prevents a partial redemption from consuming pooled Diamond custody.
contract EvesCTFSettlementAdapter is IEvesCTFSettlementAdapter, ERC1155Holder, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error ZeroAmount();
    error ArrayLengthMismatch(uint256 expected, uint256 actual);
    error NonExactCollateralTransfer(uint256 expected, uint256 actual);

    IGnosisConditionalTokens public immutable ctf;
    IERC1155 public immutable positions;
    IERC20 public immutable collateral;

    constructor(address conditionalTokens_, address collateralToken_) {
        if (conditionalTokens_ == address(0) || collateralToken_ == address(0)) revert ZeroAddress();
        ctf = IGnosisConditionalTokens(conditionalTokens_);
        positions = IERC1155(conditionalTokens_);
        collateral = IERC20(collateralToken_);
    }

    function conditionalTokens() external view returns (address) {
        return address(ctf);
    }

    function collateralToken() external view returns (address) {
        return address(collateral);
    }

    function splitPosition(bytes32 conditionId, uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        uint256 balanceBefore = collateral.balanceOf(address(this));
        collateral.safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = collateral.balanceOf(address(this)) - balanceBefore;
        if (received != amount) revert NonExactCollateralTransfer(amount, received);
        collateral.forceApprove(address(ctf), amount);
        ctf.splitPosition(collateral, bytes32(0), conditionId, _binaryPartition(), amount);
        collateral.forceApprove(address(ctf), 0);
        positions.safeBatchTransferFrom(address(this), msg.sender, _positionPair(conditionId), _amountPair(amount), "");
    }

    function mergePositions(bytes32 conditionId, uint256 amount, address receiver) external nonReentrant {
        if (receiver == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        positions.safeBatchTransferFrom(msg.sender, address(this), _positionPair(conditionId), _amountPair(amount), "");
        ctf.mergePositions(collateral, bytes32(0), conditionId, _binaryPartition(), amount);
        _transferCollateralExact(receiver, amount);
    }

    function redeemPositions(bytes32 conditionId, uint256[] calldata amounts, address receiver)
        external
        nonReentrant
        returns (uint256 payout)
    {
        if (receiver == address(0)) revert ZeroAddress();
        if (amounts.length != 2) revert ArrayLengthMismatch(2, amounts.length);
        positions.safeBatchTransferFrom(msg.sender, address(this), _positionPair(conditionId), amounts, "");
        uint256 beforeBalance = collateral.balanceOf(address(this));
        ctf.redeemPositions(collateral, bytes32(0), conditionId, _binaryPartition());
        payout = collateral.balanceOf(address(this)) - beforeBalance;
        if (payout != 0) _transferCollateralExact(receiver, payout);
    }

    function _transferCollateralExact(address receiver, uint256 amount) private {
        uint256 receiverBefore = collateral.balanceOf(receiver);
        collateral.safeTransfer(receiver, amount);
        uint256 receiverAfter = collateral.balanceOf(receiver);
        uint256 received = receiverAfter >= receiverBefore ? receiverAfter - receiverBefore : 0;
        if (received != amount) revert NonExactCollateralTransfer(amount, received);
    }

    function _positionPair(bytes32 conditionId) private view returns (uint256[] memory positionIds) {
        positionIds = new uint256[](2);
        positionIds[0] = ctf.getPositionId(collateral, ctf.getCollectionId(bytes32(0), conditionId, 1));
        positionIds[1] = ctf.getPositionId(collateral, ctf.getCollectionId(bytes32(0), conditionId, 2));
    }

    function _binaryPartition() private pure returns (uint256[] memory partition) {
        partition = new uint256[](2);
        partition[0] = 1;
        partition[1] = 2;
    }

    function _amountPair(uint256 amount) private pure returns (uint256[] memory amounts) {
        amounts = new uint256[](2);
        amounts[0] = amount;
        amounts[1] = amount;
    }
}
