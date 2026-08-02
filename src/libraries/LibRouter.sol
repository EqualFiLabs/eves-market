// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ITradeRouter} from "../interfaces/ITradeRouter.sol";
import {LibReentrancy} from "./LibReentrancy.sol";

library LibRouter {
    using SafeERC20 for IERC20;

    function enter() internal {
        LibReentrancy.enter();
    }

    function exit() internal {
        LibReentrancy.exit();
    }

    function requireReceiver(address receiver) internal pure {
        if (receiver == address(0)) {
            revert ITradeRouter.InvalidReceiver(receiver);
        }
    }

    function assertBalanceRestored(address token, uint256 expectedBalance) internal view {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance != expectedBalance) {
            revert ITradeRouter.ResidualRouterBalance(token, expectedBalance, balance);
        }
    }

    function adjustForSeniorExposure(uint256 expectedBalance, uint256 exposureBefore, uint256 exposureAfter)
        internal
        pure
        returns (uint256 adjusted)
    {
        if (exposureAfter >= exposureBefore) return expectedBalance - (exposureAfter - exposureBefore);
        adjusted = expectedBalance + (exposureBefore - exposureAfter);
    }

    function balanceDelta(address token, uint256 baseline) internal view returns (uint256 delta) {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > baseline) {
            delta = balance - baseline;
        }
    }

    function transferExact(address tokenAddress, address receiver, uint256 amount) internal {
        if (amount == 0) return;
        IERC20 token = IERC20(tokenAddress);
        uint256 receiverBefore = token.balanceOf(receiver);
        token.safeTransfer(receiver, amount);
        uint256 receiverAfter = token.balanceOf(receiver);
        uint256 received = receiverAfter >= receiverBefore ? receiverAfter - receiverBefore : 0;
        if (received != amount) revert ITradeRouter.NonExactRouterTransfer();
    }
}
