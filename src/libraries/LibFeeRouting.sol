// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISEveUSDCVault} from "../interfaces/ISEveUSDCVault.sol";

library LibFeeRouting {
    function canRouteVaultFee(address stakingVault, address token) internal view returns (bool) {
        if (stakingVault == address(0)) {
            return false;
        }

        try ISEveUSDCVault(stakingVault).isRewardTokenActive(token) returns (bool active) {
            return active;
        } catch {
            return false;
        }
    }
}
