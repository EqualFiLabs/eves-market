// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IETHUSDOracle} from "../interfaces/IETHUSDOracle.sol";

contract MockETHUSDOracle is IETHUSDOracle {
    uint256 public priceWad;
    uint256 public updatedAt;
    uint256 public maxStaleness;
    bool public invalidPrice;
    bool public stalePrice;

    constructor(uint256 priceWad_, uint256 maxStaleness_) {
        priceWad = priceWad_;
        updatedAt = block.timestamp;
        maxStaleness = maxStaleness_;
    }

    function setPriceWad(uint256 priceWad_) external {
        priceWad = priceWad_;
    }

    function setUpdatedAt(uint256 updatedAt_) external {
        updatedAt = updatedAt_;
    }

    function setMaxStaleness(uint256 maxStaleness_) external {
        maxStaleness = maxStaleness_;
    }

    function setInvalidPrice(bool invalidPrice_) external {
        invalidPrice = invalidPrice_;
    }

    function setStalePrice(bool stalePrice_) external {
        stalePrice = stalePrice_;
    }

    function ethUsdPriceWad() external view returns (uint256) {
        if (invalidPrice || priceWad == 0) {
            revert InvalidPrice();
        }
        if (stalePrice || updatedAt == 0 || updatedAt > block.timestamp || block.timestamp - updatedAt > maxStaleness) {
            revert StalePrice(updatedAt, maxStaleness);
        }

        return priceWad;
    }
}
