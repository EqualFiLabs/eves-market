// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20Metadata} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {SEveUSDCVault} from "./SEveUSDCVault.sol";
import {ISEveUSDVault} from "./interfaces/ISEveUSDVault.sol";

/// @notice Deprecated experimental eveUSD staking vault retained until the senior margin pool replacement lands.
contract SEveUSDVault is SEveUSDCVault, ISEveUSDVault {
    constructor(address eveUSD_, address owner_, address feeRecipient_, uint16 aumFeeBps_, address revenueNotifier_)
        SEveUSDCVault(eveUSD_, owner_, feeRecipient_, aumFeeBps_, revenueNotifier_)
    {}

    function name() public pure override(ERC20, IERC20Metadata) returns (string memory) {
        return "sEVEUSD";
    }

    function symbol() public pure override(ERC20, IERC20Metadata) returns (string memory) {
        return "sEVEUSD";
    }
}
