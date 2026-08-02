// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

library LibFixedPointMath {
    function rpow(uint256 base, uint256 exp, uint256 scale) internal pure returns (uint256 result) {
        if (exp == 0) {
            return scale;
        }

        if (base == 0) {
            return 0;
        }

        uint256 halfScale = scale / 2;
        result = exp & 1 == 0 ? scale : base;

        for (exp >>= 1; exp != 0; exp >>= 1) {
            base = (base * base + halfScale) / scale;

            if (exp & 1 != 0) {
                result = (result * base + halfScale) / scale;
            }
        }
    }
}
