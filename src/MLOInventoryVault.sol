// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC1155} from "../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";
import {IERC1155Receiver} from "../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "../lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";

import {IGnosisConditionalTokens} from "./interfaces/IGnosisConditionalTokens.sol";
import {IEvesNegRiskAdapter} from "./interfaces/IEvesNegRiskAdapter.sol";

/// @notice Isolated custody for one MLO bucket/market retained CTF inventory.
contract MLOInventoryVault is IERC1155Receiver {
    using SafeERC20 for IERC20;

    uint256 internal constant YES_INDEX_SET = 1;
    uint256 internal constant NO_INDEX_SET = 2;

    error NotController(address caller);
    error ArrayLengthMismatch(uint256 expected, uint256 actual);

    address public immutable controller;

    constructor(address controller_) {
        controller = controller_;
    }

    function redeemToController(address conditionalTokens, address collateralToken, bytes32 conditionId)
        external
        returns (uint256 collateralOut)
    {
        if (msg.sender != controller) {
            revert NotController(msg.sender);
        }

        IERC20 collateral = IERC20(collateralToken);
        uint256 balanceBefore = collateral.balanceOf(address(this));
        uint256[] memory indexSets = new uint256[](2);
        indexSets[0] = YES_INDEX_SET;
        indexSets[1] = NO_INDEX_SET;
        IGnosisConditionalTokens(conditionalTokens).redeemPositions(collateral, bytes32(0), conditionId, indexSets);
        collateralOut = collateral.balanceOf(address(this)) - balanceBefore;
        if (collateralOut != 0) {
            collateral.safeTransfer(controller, collateralOut);
        }
    }

    function transferPosition(address conditionalTokens, address receiver, uint256 positionId, uint256 amount)
        external
    {
        _enforceController();
        IERC1155(conditionalTokens).safeTransferFrom(address(this), receiver, positionId, amount, "");
    }

    function mergeToController(address conditionalTokens, address collateralToken, bytes32 conditionId, uint256 amount)
        external
        returns (uint256 collateralOut)
    {
        _enforceController();
        IERC20 collateral = IERC20(collateralToken);
        uint256 balanceBefore = collateral.balanceOf(address(this));
        uint256[] memory partition = new uint256[](2);
        partition[0] = YES_INDEX_SET;
        partition[1] = NO_INDEX_SET;
        IGnosisConditionalTokens(conditionalTokens)
            .mergePositions(collateral, bytes32(0), conditionId, partition, amount);
        collateralOut = collateral.balanceOf(address(this)) - balanceBefore;
        if (collateralOut != 0) collateral.safeTransfer(controller, collateralOut);
    }

    function mergeNegRiskToController(address adapter, bytes32 eventId, uint256 amount)
        external
        returns (uint256 collateralOut)
    {
        _enforceController();
        IEvesNegRiskAdapter negRisk = IEvesNegRiskAdapter(adapter);
        IERC20 collateral = IERC20(negRisk.collateralToken());
        IERC1155 positions = IERC1155(negRisk.conditionalTokens());
        uint256 balanceBefore = collateral.balanceOf(address(this));

        positions.setApprovalForAll(adapter, true);
        negRisk.mergeEvent(eventId, amount, address(this));
        positions.setApprovalForAll(adapter, false);

        collateralOut = collateral.balanceOf(address(this)) - balanceBefore;
        if (collateralOut != 0) collateral.safeTransfer(controller, collateralOut);
    }

    function redeemNegRiskToController(address adapter, bytes32 eventId, uint256[] calldata outcomeAmounts)
        external
        returns (uint256 collateralOut)
    {
        _enforceController();
        IEvesNegRiskAdapter negRisk = IEvesNegRiskAdapter(adapter);
        IEvesNegRiskAdapter.EventView memory eventView = negRisk.getEvent(eventId);
        if (outcomeAmounts.length != eventView.outcomeCount) {
            revert ArrayLengthMismatch(eventView.outcomeCount, outcomeAmounts.length);
        }

        IERC20 collateral = IERC20(negRisk.collateralToken());
        IERC1155 positions = IERC1155(negRisk.conditionalTokens());
        uint256 balanceBefore = collateral.balanceOf(address(this));
        positions.setApprovalForAll(adapter, true);

        uint256[] memory binaryAmounts = new uint256[](2);
        for (uint256 outcome; outcome < outcomeAmounts.length; ++outcome) {
            uint256 amount = outcomeAmounts[outcome];
            if (amount == 0) continue;
            binaryAmounts[0] = amount;
            negRisk.redeemPositions(negRisk.conditionIdFor(eventId, outcome), binaryAmounts, address(this));
        }

        positions.setApprovalForAll(adapter, false);
        collateralOut = collateral.balanceOf(address(this)) - balanceBefore;
        if (collateralOut != 0) collateral.safeTransfer(controller, collateralOut);
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC1155Receiver).interfaceId;
    }

    function _enforceController() private view {
        if (msg.sender != controller) revert NotController(msg.sender);
    }
}
