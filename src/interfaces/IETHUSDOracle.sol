// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IETHUSDOracle {
    error InvalidPrice();
    error StalePrice(uint256 updatedAt, uint256 maxStaleness);

    function ethUsdPriceWad() external view returns (uint256 priceWad);
}
