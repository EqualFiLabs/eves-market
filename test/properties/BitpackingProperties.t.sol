// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "../../lib/forge-std/src/Test.sol";

import {LibCurvePacking} from "src/libraries/LibCurvePacking.sol";

contract BitpackingPropertiesTest is Test {
    uint256 internal constant MAX_PRICE = 1_000_000_000;
    uint256 internal constant MAX_DURATION = (uint256(1) << 20) - 1;

    function testFuzz_BitpackedCurveEncodingRoundTrip(
        uint72 startPriceSeed,
        uint72 endPriceSeed,
        uint24 durationMinutesSeed,
        uint8 profileId
    ) public pure {
        uint72 startPrice = uint72(bound(uint256(startPriceSeed), 0, MAX_PRICE));
        uint72 endPrice = uint72(bound(uint256(endPriceSeed), 0, MAX_PRICE));
        uint24 durationMinutes = uint24(bound(uint256(durationMinutesSeed), 0, MAX_DURATION));

        uint256 packed = LibCurvePacking.pack(startPrice, endPrice, durationMinutes, profileId);
        LibCurvePacking.CurveParams memory unpacked = LibCurvePacking.unpack(packed);

        assertEq(uint256(unpacked.startPrice), uint256(startPrice));
        assertEq(uint256(unpacked.endPrice), uint256(endPrice));
        assertEq(uint256(unpacked.durationMinutes), uint256(durationMinutes));
        assertEq(uint256(unpacked.profileId), uint256(profileId));
        assertEq(packed >> 172, 0);
    }
}
