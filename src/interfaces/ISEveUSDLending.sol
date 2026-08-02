// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {ISEveUSDCLending} from "./ISEveUSDCLending.sol";

/// @notice Deprecated eveUSD lending interface retained for transition to the senior margin pool.
interface ISEveUSDLending is ISEveUSDCLending {
    function eveUSD() external view returns (IERC20);
}
