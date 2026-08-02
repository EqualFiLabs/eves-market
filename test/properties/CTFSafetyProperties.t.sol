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
import {Errors} from "../../src/libraries/Errors.sol";

import {CurveTradingFixture, ResolutionHarnessFacet} from "../helpers/DiamondFixtures.sol";

contract CTFSafetyPropertiesTest is CurveTradingFixture {
    function testFuzz_SolvencyInvariantAcrossSplitAndFill(
        uint128 makerSplitSeed,
        uint128 takerSplitSeed,
        uint128 fillCollateralSeed
    ) public {
        (bytes32 marketId,,) = _createTradingMarket("solvency", "curve", 7 days);

        uint128 makerSplit = uint128(bound(uint256(makerSplitSeed), 10, 200_000));
        uint128 takerSplit = uint128(bound(uint256(takerSplitSeed), 1, 50_000));

        _splitFrom(maker, marketId, makerSplit);
        _splitFrom(taker, marketId, takerSplit);
        _approvePositions(maker);

        uint256 curveId = _postCurveFromMaker(marketId, true, makerSplit, 500_000_000, 500_000_000, 180, 0);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        uint128 fillCollateral = uint128(bound(uint256(fillCollateralSeed), 1, uint256(takerSplit)));
        vm.prank(taker);
        collateralToken.approve(address(diamond), fillCollateral);
        vm.prank(taker);
        ICurveTradeFacet(address(diamond)).fillCurve(curveId, fillCollateral, 0, generation, commitment);

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

    function testFuzz_CorruptMarketPositionIdsDoNotRedirectBookFills(uint128 collateralSeed) public {
        (bytes32 marketId,,) = _createTradingMarket("position-ids", "curve", 7 days);
        uint128 collateralAmount = uint128(bound(uint256(collateralSeed), 10, 100_000));
        uint128 rawCollateralAmount = collateralAmount;

        _splitFrom(maker, marketId, collateralAmount);
        _approvePositions(maker);

        uint256 curveId = _postCurveFromMaker(marketId, true, collateralAmount, 500_000_000, 500_000_000, 180, 0);
        (,, uint256 expectedYesPositionId,) = IMarketFactoryFacet(address(diamond)).getMarketPositions(marketId);
        ResolutionHarnessFacet(address(diamond)).setMarketPositionIds(marketId, 1, 2);

        vm.prank(maker);
        collateralToken.approve(address(diamond), rawCollateralAmount);
        vm.expectRevert(abi.encodeWithSelector(Errors.PositionIdMismatch.selector, expectedYesPositionId, uint256(1)));
        ICurveInventoryFacet(address(diamond)).splitInventory(marketId, rawCollateralAmount);

        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSelector(Errors.PositionIdMismatch.selector, expectedYesPositionId, uint256(1)));
        ICurveInventoryFacet(address(diamond)).mergeInventory(marketId, 1);

        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        vm.prank(taker);
        collateralToken.approve(address(diamond), 1);

        (uint128 expectedSharesOut,,,) = ICurveViewFacet(address(diamond)).previewCurveQuote(curveId, 1);
        uint256 takerBalanceBefore = conditionalTokens.balanceOf(taker, expectedYesPositionId);

        vm.prank(taker);
        uint128 sharesOut = ICurveTradeFacet(address(diamond)).fillCurve(curveId, 1, 0, generation, commitment);

        assertEq(sharesOut, expectedSharesOut);
        assertEq(conditionalTokens.balanceOf(taker, expectedYesPositionId), takerBalanceBefore + expectedSharesOut);
    }
}
