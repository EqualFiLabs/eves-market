// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IUsdOracle} from "./IUsdOracle.sol";

interface IETHUSDOracle is IUsdOracle {

    function ethUsdPriceWad() external view returns (uint256 priceWad);
}
