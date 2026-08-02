// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC1155} from "../../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";

import {Errors} from "./Errors.sol";
import {LibEveMarket} from "./LibEveMarket.sol";
import {LibSafeCast} from "./LibSafeCast.sol";

library LibCurveEscrow {
    using SafeERC20 for IERC20;

    function escrowPostedInventory(LibEveMarket.Book storage book, address maker, uint128 volume)
        internal
        returns (uint128 actualVolume)
    {
        if (volume == 0) {
            return 0;
        }

        if (book.assetType == LibEveMarket.BookAssetType.ERC20) {
            actualVolume = transferBaseERC20From(book, maker, address(this), volume);
            return actualVolume;
        }

        escrowPostedInventory(IERC1155(book.baseToken), maker, book.baseTokenId, volume);
        actualVolume = volume;
    }

    function escrowPostedInventory(IERC1155 positionToken, address maker, uint256 positionId, uint128 volume)
        internal
    {
        if (volume == 0) {
            return;
        }

        uint256 makerBalance = positionToken.balanceOf(maker, positionId);
        if (makerBalance < volume) {
            revert Errors.InsufficientMakerEscrow(volume, uint128(makerBalance));
        }

        positionToken.safeTransferFrom(maker, address(this), positionId, volume, "");
    }

    function transferBaseFromEscrow(LibEveMarket.Book storage book, address receiver, uint128 amount)
        internal
        returns (uint128 actualAmount)
    {
        if (amount == 0) {
            return 0;
        }

        if (book.assetType == LibEveMarket.BookAssetType.ERC20) {
            return transferBaseERC20(book, receiver, amount);
        }

        IERC1155(book.baseToken).safeTransferFrom(address(this), receiver, book.baseTokenId, amount, "");
        actualAmount = amount;
    }

    function transferBaseFromSeller(
        LibEveMarket.Book storage book,
        address seller,
        address receiver,
        uint128 amount
    ) internal returns (uint128 actualAmount) {
        if (amount == 0) {
            return 0;
        }

        if (book.assetType == LibEveMarket.BookAssetType.ERC20) {
            return transferBaseERC20From(book, seller, receiver, amount);
        }

        IERC1155(book.baseToken).safeTransferFrom(seller, receiver, book.baseTokenId, amount, "");
        actualAmount = amount;
    }

    function transferBaseERC20From(LibEveMarket.Book storage book, address from, address to, uint128 amount)
        internal
        returns (uint128 actualAmount)
    {
        uint256 balanceBefore = IERC20(book.baseToken).balanceOf(to);
        IERC20(book.baseToken).safeTransferFrom(from, to, amount);
        actualAmount = checkedBaseDelta(book, to, amount, balanceBefore);
    }

    function transferBaseERC20(LibEveMarket.Book storage book, address to, uint128 amount)
        internal
        returns (uint128 actualAmount)
    {
        uint256 balanceBefore = IERC20(book.baseToken).balanceOf(to);
        IERC20(book.baseToken).safeTransfer(to, amount);
        actualAmount = checkedBaseDelta(book, to, amount, balanceBefore);
    }

    function transferCachedBaseERC20(
        address baseToken,
        LibEveMarket.BaseTransferMode baseTransferMode,
        address receiver,
        uint128 amount
    ) internal {
        uint256 balanceBefore = IERC20(baseToken).balanceOf(receiver);
        IERC20(baseToken).safeTransfer(receiver, amount);
        uint256 delta = IERC20(baseToken).balanceOf(receiver) - balanceBefore;
        if (baseTransferMode == LibEveMarket.BaseTransferMode.EXACT) {
            if (delta != amount) {
                revert Errors.BaseTransferDeltaMismatch(baseToken, amount, delta);
            }
        } else if (delta == 0 || delta > amount) {
            revert Errors.BaseTransferDeltaMismatch(baseToken, amount, delta);
        }
    }

    function transferExactERC20From(address token, address from, address to, uint128 amount) internal {
        if (amount == 0) {
            return;
        }

        uint256 balanceBefore = IERC20(token).balanceOf(to);
        IERC20(token).safeTransferFrom(from, to, amount);
        uint256 delta = IERC20(token).balanceOf(to) - balanceBefore;
        if (delta != amount) {
            revert Errors.BaseTransferDeltaMismatch(token, amount, delta);
        }
    }

    function checkedBaseDelta(
        LibEveMarket.Book storage book,
        address receiver,
        uint128 expected,
        uint256 balanceBefore
    ) internal view returns (uint128 actualAmount) {
        uint256 delta = IERC20(book.baseToken).balanceOf(receiver) - balanceBefore;
        if (book.baseTransferMode == LibEveMarket.BaseTransferMode.EXACT) {
            if (delta != expected) {
                revert Errors.BaseTransferDeltaMismatch(book.baseToken, expected, delta);
            }
        } else if (delta == 0 || delta > expected) {
            revert Errors.BaseTransferDeltaMismatch(book.baseToken, expected, delta);
        }

        actualAmount = LibSafeCast.toUint128(delta);
    }
}
