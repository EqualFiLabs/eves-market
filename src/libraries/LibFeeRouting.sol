// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Math} from "../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

import {ISEveUSDCVault} from "../interfaces/ISEveUSDCVault.sol";

library LibFeeRouting {
    struct VaultFeeRoute {
        uint256 primaryAmount;
        uint256 secondaryAmount;
        uint256 treasuryAmount;
    }

    function canRouteVaultFee(address stakingVault, address token) internal view returns (bool) {
        (bool eligible,) = _vaultEligibility(stakingVault, token);
        return eligible;
    }

    function previewVaultFeeRoute(address primaryVault, address secondaryVault, address token, uint256 amount)
        internal
        view
        returns (VaultFeeRoute memory route)
    {
        if (amount == 0) {
            return route;
        }

        (bool primaryEligible, uint256 primarySupply) = _vaultEligibility(primaryVault, token);
        (bool secondaryEligible, uint256 secondarySupply) = _vaultEligibility(secondaryVault, token);

        if (primaryEligible && secondaryEligible) {
            uint256 totalSupply = primarySupply + secondarySupply;
            if (totalSupply == 0) {
                route.treasuryAmount = amount;
                return route;
            }

            route.primaryAmount = Math.mulDiv(amount, primarySupply, totalSupply);
            route.secondaryAmount = amount - route.primaryAmount;
            return route;
        }

        if (primaryEligible) {
            route.primaryAmount = amount;
            return route;
        }

        if (secondaryEligible) {
            route.secondaryAmount = amount;
            return route;
        }

        route.treasuryAmount = amount;
    }

    function _vaultEligibility(address vault, address token) internal view returns (bool eligible, uint256 supply) {
        if (vault == address(0)) {
            return (false, 0);
        }

        try ISEveUSDCVault(vault).isRewardTokenActive(token) returns (bool active) {
            if (!active) {
                return (false, 0);
            }
        } catch {
            return (false, 0);
        }

        try ISEveUSDCVault(vault).totalSupply() returns (uint256 totalSupply) {
            if (totalSupply == 0) {
                return (false, 0);
            }
            return (true, totalSupply);
        } catch {
            return (false, 0);
        }
    }
}
