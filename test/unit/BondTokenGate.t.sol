// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ResolutionFixture, ResolutionHarnessFacet, StateProbeFacet} from "../helpers/DiamondFixtures.sol";

contract BondTokenGateTest is ResolutionFixture {
    function test_LockResolutionBondPullsLevelOneAmount() public {
        uint256 userBalanceBefore = eveToken.balanceOf(challengerOne);

        ResolutionHarnessFacet(address(diamond)).harnessLockResolutionBond(challengerOne, 1);

        uint256 bonded = StateProbeFacet(address(diamond)).getBondedTotals(challengerOne);

        assertEq(bonded, 0.1 ether);
        assertEq(eveToken.balanceOf(challengerOne), userBalanceBefore - 0.1 ether);
        assertEq(eveToken.balanceOf(address(diamond)), 0.1 ether);
    }

    function test_LockResolutionBondPullsLevelTwoAmount() public {
        uint256 userBalanceBefore = eveToken.balanceOf(challengerTwo);

        ResolutionHarnessFacet(address(diamond)).harnessLockResolutionBond(challengerTwo, 2);

        uint256 bonded = StateProbeFacet(address(diamond)).getBondedTotals(challengerTwo);

        assertEq(bonded, 0.5 ether);
        assertEq(eveToken.balanceOf(challengerTwo), userBalanceBefore - 0.5 ether);
        assertEq(eveToken.balanceOf(address(diamond)), 0.5 ether);
    }

    function test_UnlockResolutionBondReturnsLockedTokens() public {
        uint256 userBalanceBefore = eveToken.balanceOf(challengerOne);

        ResolutionHarnessFacet(address(diamond)).harnessLockResolutionBond(challengerOne, 1);
        ResolutionHarnessFacet(address(diamond)).harnessUnlockResolutionBond(challengerOne, 0.1 ether);

        uint256 bonded = StateProbeFacet(address(diamond)).getBondedTotals(challengerOne);

        assertEq(bonded, 0);
        assertEq(eveToken.balanceOf(challengerOne), userBalanceBefore);
        assertEq(eveToken.balanceOf(address(diamond)), 0);
    }
}
