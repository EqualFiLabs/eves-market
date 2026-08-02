// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {SEveUSDCLending} from "./SEveUSDCLending.sol";
import {ISEveUSDLending} from "./interfaces/ISEveUSDLending.sol";

/// @notice Deprecated eveUSD lending wrapper retained until the senior margin pool replacement lands.
contract SEveUSDLending is SEveUSDCLending, ISEveUSDLending {
    constructor(address vault_, address eveUSD_, address owner_) SEveUSDCLending(vault_, eveUSD_, owner_) {}

    function eveUSD() external view returns (IERC20) {
        return eveUSDC;
    }
}
