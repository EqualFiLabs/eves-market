// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface ICurveProfile {
    function computePrice(
        uint128 startPrice,
        uint128 endPrice,
        uint64 startTime,
        uint64 duration,
        uint64 currentTime,
        bytes32 profileParams
    ) external view returns (uint128 price);
}
