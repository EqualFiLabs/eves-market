// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {LibEveMarket} from "./LibEveMarket.sol";
import {LibSeniorCapital} from "./LibSeniorCapital.sol";

library LibFeeRouting {
    uint256 internal constant FEE_BPS_DENOMINATOR = 10_000;

    struct SeniorPoolFeeRoute {
        uint256 seniorPoolAmount;
        uint256 treasuryAmount;
    }

    function canRouteSeniorPoolFee(address token) internal view returns (bool) {
        return token != address(0) && token == LibEveMarket.store().marginAsset && LibSeniorCapital.s().totalStored != 0;
    }

    function previewSeniorPoolFeeRoute(address token, uint256 amount)
        internal
        view
        returns (SeniorPoolFeeRoute memory route)
    {
        if (amount == 0) {
            return route;
        }

        if (canRouteSeniorPoolFee(token)) {
            route.seniorPoolAmount = amount;
            return route;
        }

        route.treasuryAmount = amount;
    }
}
