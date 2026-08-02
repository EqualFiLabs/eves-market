// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {Errors} from "./Errors.sol";
import {LibEveMarket} from "./LibEveMarket.sol";

library LibNativeCollateral {
    using SafeERC20 for IERC20;

    function collectBacking(
        LibEveMarket.EveMarketStorage storage state,
        address collateralToken,
        address payer,
        uint256 amount
    ) internal {
        IERC20 token = IERC20(collateralToken);
        uint256 balanceBefore = token.balanceOf(address(this));
        token.safeTransferFrom(payer, address(this), amount);
        uint256 received = token.balanceOf(address(this)) - balanceBefore;
        if (received != amount) {
            revert Errors.NativeCollateralTransferMismatch(collateralToken, amount, received);
        }
        increaseLiability(state, collateralToken, amount);
    }

    function releaseBacking(
        LibEveMarket.EveMarketStorage storage state,
        address collateralToken,
        address receiver,
        uint256 amount
    ) internal {
        decreaseLiability(state, collateralToken, amount);
        IERC20(collateralToken).safeTransfer(receiver, amount);
        assertBacking(state, collateralToken);
    }

    function increaseLiability(LibEveMarket.EveMarketStorage storage state, address collateralToken, uint256 amount)
        internal
    {
        state.nativePositionCollateralLiability[collateralToken] += amount;
        assertBacking(state, collateralToken);
    }

    function decreaseLiability(LibEveMarket.EveMarketStorage storage state, address collateralToken, uint256 amount)
        internal
    {
        uint256 liability = state.nativePositionCollateralLiability[collateralToken];
        if (amount > liability) {
            revert Errors.NativeCollateralLiabilityInsufficient(collateralToken, liability, amount);
        }
        state.nativePositionCollateralLiability[collateralToken] = liability - amount;
    }

    function assertBacking(LibEveMarket.EveMarketStorage storage state, address collateralToken) internal view {
        uint256 balance = IERC20(collateralToken).balanceOf(address(this));
        uint256 liability = state.nativePositionCollateralLiability[collateralToken];
        if (balance < liability) {
            revert Errors.NativeCollateralBackingInsufficient(collateralToken, balance, liability);
        }
    }
}
