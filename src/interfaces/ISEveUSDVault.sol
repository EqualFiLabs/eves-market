// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISEveUSDCVault} from "./ISEveUSDCVault.sol";

/// @notice Deprecated eveUSD staking vault interface retained for transition to the senior margin pool.
interface ISEveUSDVault is ISEveUSDCVault {}
