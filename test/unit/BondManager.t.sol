// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IOBRResolutionFacet} from "../../src/interfaces/IOBRResolutionFacet.sol";
import {Errors} from "../../src/libraries/Errors.sol";

import {ResolutionFixture, ResolutionHarnessFacet, StateProbeFacet} from "../helpers/DiamondFixtures.sol";

contract BondManagerTest is ResolutionFixture {
    function test_ReturnBondTransfersEscrowedBondTokenToWinner() public {
        (bytes32 marketId, uint64 expiryTime) = _createPendingMarket("Return bond", "resolution", 7 days);
        vm.warp(expiryTime + 24 hours);

        uint256 startingBondToken = eveToken.balanceOf(challengerOne);

        vm.prank(challengerOne);
        IOBRResolutionFacet(address(diamond)).openResolution(marketId, 2);

        ResolutionHarnessFacet(address(diamond)).harnessReturnBond(marketId, 0);

        uint256 bonded = StateProbeFacet(address(diamond)).getBondedTotals(challengerOne);
        uint128 marketBonded = StateProbeFacet(address(diamond)).getBondedForMarket(marketId, challengerOne);

        assertEq(eveToken.balanceOf(challengerOne), startingBondToken);
        assertEq(bonded, 0);
        assertEq(marketBonded, 0);
    }

    function test_SlashBondRoutesEscrowedBondTokenToTreasury() public {
        (bytes32 marketId, uint64 expiryTime) = _createPendingMarket("Slash bond", "resolution", 7 days);
        vm.warp(expiryTime + 24 hours);

        uint256 treasuryBondTokenBefore = eveToken.balanceOf(treasury);

        vm.prank(challengerOne);
        IOBRResolutionFacet(address(diamond)).openResolution(marketId, 3);

        ResolutionHarnessFacet(address(diamond)).harnessSlashBond(marketId, 0, treasury);

        uint256 bonded = StateProbeFacet(address(diamond)).getBondedTotals(challengerOne);
        uint128 marketBonded = StateProbeFacet(address(diamond)).getBondedForMarket(marketId, challengerOne);

        assertEq(eveToken.balanceOf(treasury), treasuryBondTokenBefore + 0.1 ether);
        assertEq(bonded, 0);
        assertEq(marketBonded, 0);
    }

    function test_SlashBondCanRetainEscrowedAssetsInDiamond() public {
        (bytes32 marketId, uint64 expiryTime) = _createPendingMarket("Retain slash", "resolution", 7 days);
        vm.warp(expiryTime + 24 hours);

        vm.prank(challengerOne);
        IOBRResolutionFacet(address(diamond)).openResolution(marketId, 1);

        uint256 diamondBondTokenBefore = eveToken.balanceOf(address(diamond));
        uint256 treasuryBondTokenBefore = eveToken.balanceOf(treasury);

        ResolutionHarnessFacet(address(diamond)).harnessSlashBond(marketId, 0, address(0));

        uint256 bonded = StateProbeFacet(address(diamond)).getBondedTotals(challengerOne);

        assertEq(eveToken.balanceOf(address(diamond)), diamondBondTokenBefore);
        assertEq(eveToken.balanceOf(treasury), treasuryBondTokenBefore);
        assertEq(bonded, 0);
    }

    function test_RevertWhen_ReturningMissingBond() public {
        bytes32 missingMarketId = keccak256("missing-bond");

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidResolutionIndex.selector, missingMarketId, 0));
        ResolutionHarnessFacet(address(diamond)).harnessReturnBond(missingMarketId, 0);
    }

    function test_RevertWhen_SlashingMissingBond() public {
        bytes32 missingMarketId = keccak256("missing-slash");

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidResolutionIndex.selector, missingMarketId, 0));
        ResolutionHarnessFacet(address(diamond)).harnessSlashBond(missingMarketId, 0, treasury);
    }
}
