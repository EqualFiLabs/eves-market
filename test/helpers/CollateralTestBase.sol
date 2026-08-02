// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "../../lib/forge-std/src/Test.sol";
import {MockCollateral} from "./MockCollateral.sol";

abstract contract CollateralTestBase is Test {
    MockCollateral internal collateral;

    address internal owner;
    address internal riskManager;
    address internal alice;
    address internal bob;

    function setUp() public virtual {
        owner = makeAddr("owner");
        riskManager = makeAddr("riskManager");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        collateral = new MockCollateral();
    }

    function _seedCollateral(address account, uint256 amount) internal {
        collateral.mint(account, amount);
    }
}
