// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ICurveProfile} from "../../src/interfaces/ICurveProfile.sol";

contract MockCurveProfile is ICurveProfile {
    uint128 public fixedPrice;
    bool public useFixedPrice;

    function setFixedPrice(uint128 newFixedPrice) external {
        fixedPrice = newFixedPrice;
        useFixedPrice = true;
    }

    function clearFixedPrice() external {
        useFixedPrice = false;
    }

    function computePrice(
        uint128 startPrice,
        uint128 endPrice,
        uint64 startTime,
        uint64 duration,
        uint64 currentTime,
        bytes32
    ) external view returns (uint128 price) {
        if (useFixedPrice) {
            return fixedPrice;
        }

        if (currentTime <= startTime) {
            return startPrice;
        }

        if (duration == 0 || currentTime >= startTime + duration) {
            return endPrice;
        }

        uint128 elapsed = uint128(currentTime - startTime);

        if (endPrice >= startPrice) {
            return startPrice + uint128((uint256(endPrice - startPrice) * elapsed) / duration);
        }

        return startPrice - uint128((uint256(startPrice - endPrice) * elapsed) / duration);
    }
}
