// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {IEveUSDC} from "../interfaces/IEveUSDC.sol";
import {ITradeRouter} from "../interfaces/ITradeRouter.sol";
import {LibEveUSDCUnits} from "./LibEveUSDCUnits.sol";
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

    function balanceDelta(address token, uint256 baseline) internal view returns (uint256 delta) {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > baseline) {
            delta = balance - baseline;
        }
    }

    function unwrapConvertibleEveUSDC(address eveUSDC, uint256 amount, address receiver)
        internal
        returns (uint256 usdcOut)
    {
        uint256 convertible = LibEveUSDCUnits.convertibleEveUSDC(amount);
        uint256 dust = amount - convertible;
        if (convertible != 0) {
            usdcOut = IEveUSDC(eveUSDC).unwrap(convertible, receiver);
        }
        if (dust != 0) {
            IERC20(eveUSDC).safeTransfer(receiver, dust);
        }
    }
}
