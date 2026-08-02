// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

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
import {LibCurvePacking} from "../../src/libraries/LibCurvePacking.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";

import {CurveTradingFixture, StateProbeFacet} from "../helpers/DiamondFixtures.sol";

contract CurveLifecyclePropertiesTest is CurveTradingFixture {
    function testFuzz_CurveUpdateGenerationGuard(uint72 startPriceSeed, uint72 endPriceSeed) public {
        uint72 startPrice = uint72(bound(uint256(startPriceSeed), 100_000_000, 900_000_000));
        uint72 endPrice = uint72(bound(uint256(endPriceSeed), 100_000_000, 900_000_000));

        (uint256 curveId,) = _postYesCurve(100_000e6);
        uint256 newPacked = LibCurvePacking.pack(startPrice, endPrice, 90, 0);

        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSelector(Errors.GenerationMismatch.selector, uint32(2), uint32(1)));
        ICurveLifecycleFacet(address(diamond)).updateCurve(curveId, newPacked, 2);
    }

    function testFuzz_CurveOwnerRestriction(uint128 volumeSeed) public {
        uint128 volume = uint128(bound(uint256(volumeSeed), 1, 100_000));
        (uint256 curveId,) = _postYesCurve(volume);

        vm.prank(taker);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotCurveOwner.selector, taker, maker));
        ICurveLifecycleFacet(address(diamond)).cancelCurve(curveId);
    }

    function testFuzz_CurveCancellationReturnsInventory(uint128 collateralSeed, uint128 fillCollateralSeed) public {
        uint128 collateralAmount = uint128(bound(uint256(collateralSeed), 10, 500_000));
        (uint256 curveId, bytes32 marketId) = _postYesCurve(collateralAmount);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        uint128 fillCollateral = uint128(bound(uint256(fillCollateralSeed), 1, uint256(collateralAmount / 2)));
        (uint128 previewShares,,,) = ICurveViewFacet(address(diamond)).previewCurveQuote(curveId, fillCollateral);

        vm.prank(taker);
        collateralToken.approve(address(diamond), fillCollateral);
        vm.prank(taker);
        ICurveTradeFacet(address(diamond)).fillCurve(curveId, fillCollateral, 0, generation, commitment);

        (,, uint256 yesPositionId,) = IMarketFactoryFacet(address(diamond)).getMarketPositions(marketId);
        uint256 makerBeforeCancel = conditionalTokens.balanceOf(maker, yesPositionId);

        vm.prank(maker);
        ICurveLifecycleFacet(address(diamond)).cancelCurve(curveId);

        assertEq(
            conditionalTokens.balanceOf(maker, yesPositionId), makerBeforeCancel + (collateralAmount - previewShares)
        );
    }

    function testFuzz_ExpiredCurveRejectsFills(uint24 durationSeed, uint128 collateralSeed) public {
        uint24 durationMinutes = uint24(bound(uint256(durationSeed), 1, 1_440));
        uint128 collateralIn = uint128(bound(uint256(collateralSeed), 1e6, 10_000e6));
        (bytes32 marketId,,) = _createTradingMarket("expired-curve", "curve", 30 days);

        _splitFrom(maker, marketId, 100_000e6);
        _approvePositions(maker);
        uint256 curveId = _postCurveFromMaker(marketId, true, 100_000e6, 500_000_000, 500_000_000, durationMinutes, 0);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        vm.warp(block.timestamp + durationMinutes * 1 minutes + 1);

        vm.prank(taker);
        collateralToken.approve(address(diamond), collateralIn);
        vm.prank(taker);
        vm.expectRevert(abi.encodeWithSelector(Errors.CurveExpired.selector, curveId));
        ICurveTradeFacet(address(diamond)).fillCurve(curveId, collateralIn, 0, generation, commitment);
    }

    function testFuzz_MakerEscrowRequirement(uint128 mintedSeed, uint128 postedSeed) public {
        uint128 minted = uint128(bound(uint256(mintedSeed), 1, 100_000));
        uint128 posted = uint128(bound(uint256(postedSeed), minted + 1, minted + 100_000));
        (bytes32 marketId,,) = _createTradingMarket("escrow-req", "curve", 7 days);

        _splitFrom(maker, marketId, minted);
        _approvePositions(maker);

        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSelector(Errors.InsufficientMakerEscrow.selector, posted, minted));
        ICurveLifecycleFacet(address(diamond))
            .postCurve(marketId, true, posted, 500_000_000, 500_000_000, 60, 0, LibEveMarket.PositionTokenType.CTF);
    }

    function _postYesCurve(uint128 volume) internal returns (uint256 curveId, bytes32 marketId) {
        (marketId,,) = _createTradingMarket("lifecycle", "curve", 7 days);
        _splitFrom(maker, marketId, volume);
        _approvePositions(maker);
        curveId = _postCurveFromMaker(marketId, true, volume, 500_000_000, 500_000_000, 180, 0);
    }
}
