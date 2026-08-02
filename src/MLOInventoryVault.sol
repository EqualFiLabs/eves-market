// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC1155Receiver} from "../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "../lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";

import {IGnosisConditionalTokens} from "./interfaces/IGnosisConditionalTokens.sol";

/// @notice Isolated custody for one MLO bucket/market retained CTF inventory.
contract MLOInventoryVault is IERC1155Receiver {
    using SafeERC20 for IERC20;

    uint256 internal constant YES_INDEX_SET = 1;
    uint256 internal constant NO_INDEX_SET = 2;

    error NotController(address caller);

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
}
