// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISeniorCapitalPool} from "../interfaces/ISeniorCapitalPool.sol";

library LibFeeRouting {
    struct SeniorPoolFeeRoute {
        uint256 seniorPoolAmount;
        uint256 treasuryAmount;
    }

    struct EvRiskFeeRoute {
        uint256 evRiskAmount;
        uint256 treasuryAmount;
    }

    function canRouteSeniorPoolFee(address seniorCapitalPool, address token) internal view returns (bool) {
        (bool eligible,) = _seniorPoolEligibility(seniorCapitalPool, token);
        return eligible;
    }

    function previewSeniorPoolFeeRoute(address seniorCapitalPool, address token, uint256 amount)
        internal
        view
        returns (SeniorPoolFeeRoute memory route)
    {
        if (amount == 0) {
            return route;
        }

        (bool eligible,) = _seniorPoolEligibility(seniorCapitalPool, token);
        if (eligible) {
            route.seniorPoolAmount = amount;
            return route;
        }

        route.treasuryAmount = amount;
    }

    function previewEvRiskFeeRoute(address evRiskStakingRewards, uint256 amount)
        internal
        pure
        returns (EvRiskFeeRoute memory route)
    {
        if (amount == 0) {
            return route;
        }
        if (evRiskStakingRewards == address(0)) {
            route.treasuryAmount = amount;
            return route;
        }
        route.evRiskAmount = amount;
    }

    function _seniorPoolEligibility(address seniorCapitalPool, address token)
        internal
        view
        returns (bool eligible, uint256 supply)
    {
        if (seniorCapitalPool == address(0)) {
            return (false, 0);
        }

        try ISeniorCapitalPool(seniorCapitalPool).asset() returns (address asset) {
            if (asset != token) {
                return (false, 0);
            }
        } catch {
            return (false, 0);
        }

        try ISeniorCapitalPool(seniorCapitalPool).totalSupply() returns (uint256 totalSupply) {
            if (totalSupply == 0) {
                return (false, 0);
            }
            return (true, totalSupply);
        } catch {
            return (false, 0);
        }
    }
}
