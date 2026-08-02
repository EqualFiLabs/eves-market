// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IBookAdminFacet} from "../../src/interfaces/IBookAdminFacet.sol";
import {IBookOrderFacet} from "../../src/interfaces/IBookOrderFacet.sol";
import {IBookTradeFacet} from "../../src/interfaces/IBookTradeFacet.sol";
import {IBookViewFacet} from "../../src/interfaces/IBookViewFacet.sol";
import {ICurveInventoryFacet} from "../../src/interfaces/ICurveInventoryFacet.sol";
import {ICurveLifecycleFacet} from "../../src/interfaces/ICurveLifecycleFacet.sol";
import {ICurveTradeFacet} from "../../src/interfaces/ICurveTradeFacet.sol";
import {ICurveViewFacet} from "../../src/interfaces/ICurveViewFacet.sol";
import {CurveCLOBTypes} from "../../src/types/CurveCLOBTypes.sol";
import {IMarketFactoryFacet} from "../../src/interfaces/IMarketFactoryFacet.sol";

import {CurveTradingFixture} from "../helpers/DiamondFixtures.sol";

contract TokenMintingPropertiesTest is CurveTradingFixture {
    function testFuzz_CompleteSetInventoryInvariant(
        uint128 makerSplitSeed,
        uint128 takerSplitSeed,
        uint128 makerMergeSeed
    ) public {
        (bytes32 marketId,,) = _createTradingMarket("complete-set", "curve", 7 days);

        uint128 makerSplit = uint128(bound(uint256(makerSplitSeed), 1, 100_000));
        uint128 takerSplit = uint128(bound(uint256(takerSplitSeed), 1, 100_000));

        _splitFrom(maker, marketId, makerSplit);
        _splitFrom(taker, marketId, takerSplit);
        _approvePositions(maker);

        uint128 makerMerge = uint128(bound(uint256(makerMergeSeed), 0, makerSplit));
        if (makerMerge != 0) {
            vm.prank(maker);
            ICurveInventoryFacet(address(diamond)).mergeInventory(marketId, makerMerge);
        }

        (,, uint256 yesPositionId, uint256 noPositionId) =
            IMarketFactoryFacet(address(diamond)).getMarketPositions(marketId);
        uint256 totalYes = conditionalTokens.balanceOf(maker, yesPositionId)
            + conditionalTokens.balanceOf(taker, yesPositionId)
            + conditionalTokens.balanceOf(address(diamond), yesPositionId);
        uint256 totalNo = conditionalTokens.balanceOf(maker, noPositionId)
            + conditionalTokens.balanceOf(taker, noPositionId)
            + conditionalTokens.balanceOf(address(diamond), noPositionId);
        uint256 ctfCollateral = conditionalTokens.collateralBalance(IERC20(address(collateralToken)));

        assertEq(totalYes, totalNo);
        assertEq(totalYes, ctfCollateral);
    }

    function testFuzz_MergeBurnsBalancedPairsAndReturnsCollateral(uint128 splitSeed, uint128 mergeSeed) public {
        (bytes32 marketId,,) = _createTradingMarket("merge-pairs", "curve", 7 days);

        uint128 splitAmount = uint128(bound(uint256(splitSeed), 2, 100_000));
        _splitFrom(maker, marketId, splitAmount);
        _approvePositions(maker);

        uint128 mergeAmount = uint128(bound(uint256(mergeSeed), 1, splitAmount));
        uint256 makerCollateralBefore = collateralToken.balanceOf(maker);

        vm.prank(maker);
        ICurveInventoryFacet(address(diamond)).mergeInventory(marketId, mergeAmount);

        (,, uint256 yesPositionId, uint256 noPositionId) =
            IMarketFactoryFacet(address(diamond)).getMarketPositions(marketId);

        assertEq(conditionalTokens.balanceOf(maker, yesPositionId), splitAmount - mergeAmount);
        assertEq(conditionalTokens.balanceOf(maker, noPositionId), splitAmount - mergeAmount);
        assertEq(collateralToken.balanceOf(maker), makerCollateralBefore + uint256(mergeAmount));
    }
}
