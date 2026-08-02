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
import {IFeeRouterFacet} from "../../src/interfaces/IFeeRouterFacet.sol";
import {IMarketFactoryFacet} from "../../src/interfaces/IMarketFactoryFacet.sol";
import {IMarketSettlementFacet} from "../../src/interfaces/IMarketSettlementFacet.sol";
import {IOBRResolutionFacet} from "../../src/interfaces/IOBRResolutionFacet.sol";

import {SettlementFeeFixture, StateProbeFacet} from "../helpers/DiamondFixtures.sol";

contract SettlementPropertiesTest is SettlementFeeFixture {
    function testFuzz_CTFRedemptionDeterminism(uint8 outcomeSeed, uint128 splitSeed) public {
        uint8 outcome = uint8(bound(uint256(outcomeSeed), 1, 3));
        uint128 splitAmount = uint128(bound(uint256(splitSeed), 2, 50_000));
        splitAmount -= splitAmount % 2;

        (bytes32 marketId,, uint64 expiryTime) = _createTradingMarket("redemption", "settlement", 7 days);
        _splitFrom(maker, marketId, splitAmount);
        _splitFrom(trader, marketId, splitAmount);

        uint256 noPositionId;
        (,,, noPositionId) = IMarketFactoryFacet(address(diamond)).getMarketPositions(marketId);

        vm.prank(maker);
        conditionalTokens.safeTransferFrom(maker, taker, noPositionId, splitAmount, "");

        _finalizeCreatorResolution(marketId, expiryTime, outcome);

        (, bytes32 conditionId, uint256[] memory bothIndexSets) =
            IMarketSettlementFacet(address(diamond)).getCTFRedemptionParams(marketId);

        uint256[] memory yesIndexSet = new uint256[](1);
        uint256[] memory noIndexSet = new uint256[](1);
        yesIndexSet[0] = 1;
        noIndexSet[0] = 2;

        uint256 makerCollateralBefore = collateralToken.balanceOf(maker);
        uint256 takerCollateralBefore = collateralToken.balanceOf(taker);
        uint256 traderCollateralBefore = collateralToken.balanceOf(trader);

        vm.prank(maker);
        conditionalTokens.redeemPositions(IERC20(address(collateralToken)), bytes32(0), conditionId, yesIndexSet);

        vm.prank(taker);
        conditionalTokens.redeemPositions(IERC20(address(collateralToken)), bytes32(0), conditionId, noIndexSet);

        vm.prank(trader);
        conditionalTokens.redeemPositions(IERC20(address(collateralToken)), bytes32(0), conditionId, bothIndexSets);

        (uint256 expectedMakerPayout, uint256 expectedTakerPayout) = _singleSidePayouts(outcome, splitAmount);

        assertEq(collateralToken.balanceOf(maker), makerCollateralBefore + expectedMakerPayout);
        assertEq(collateralToken.balanceOf(taker), takerCollateralBefore + expectedTakerPayout);
        assertEq(collateralToken.balanceOf(trader), traderCollateralBefore + splitAmount);
    }

    function testFuzz_FeeSplitInvariant(uint72 priceSeed, uint16 feeRateSeed, uint128 collateralSeed) public {
        uint72 price = uint72(bound(uint256(priceSeed), 50_000_000, 950_000_000));
        uint16 feeRate = uint16(bound(uint256(feeRateSeed), 1, 10_000));
        uint128 collateralIn = uint128(bound(uint256(collateralSeed), 50_000e6, 200_000e6));
        uint256 treasuryUsdcBefore = collateralToken.balanceOf(treasury);
        uint128 creationFee = StateProbeFacet(address(diamond)).marketCreationFee();

        (bytes32 marketId,, uint128 fee) =
            _createFilledMarketWithFee("fee-invariant", "settlement", 7 days, 500_000e6, price, feeRate, collateralIn);
        uint128 makerShare = _makerShare(fee);
        uint128 creatorShare = _creatorShare(fee);
        uint128 protocolShare = fee - makerShare - creatorShare;
        (uint128 storedCreatorFees, uint128 storedProtocolFees,,) =
            StateProbeFacet(address(diamond)).getStoredMarketFees(marketId);
        (, uint128 storedMakerFees,) = StateProbeFacet(address(diamond)).getStoredMakerAccounting(marketId, maker);

        assertEq(storedMakerFees, makerShare);
        assertEq(storedCreatorFees, creatorShare);
        assertEq(storedProtocolFees, protocolShare);
        assertEq(storedMakerFees + storedCreatorFees + storedProtocolFees, fee);
        assertEq(collateralToken.balanceOf(treasury), treasuryUsdcBefore + creationFee + protocolShare);
    }

    function testFuzz_MakerFeeProportionalityAndDoubleClaim(uint72 priceSeed, uint128 collateralSeed) public {
        uint72 price = uint72(bound(uint256(priceSeed), 100_000_000, 900_000_000));
        uint128 collateralIn = uint128(bound(uint256(collateralSeed), 10_000e6, 100_000e6));

        (bytes32 marketId,, uint128 fee) =
            _createFilledMarketWithFee("maker-proportional", "settlement", 7 days, 250_000e6, price, 500, collateralIn);
        uint128 makerShare = _makerShare(fee);
        uint256 makerBalanceBefore = collateralToken.balanceOf(maker);

        vm.prank(maker);
        IFeeRouterFacet(address(diamond)).claimMakerFees(marketId);
        vm.prank(maker);
        IFeeRouterFacet(address(diamond)).claimMakerFees(marketId);

        assertEq(collateralToken.balanceOf(maker), makerBalanceBefore + makerShare);

        (uint128 accrued, uint128 claimed, uint128 claimable) =
            IFeeRouterFacet(address(diamond)).previewMakerFees(marketId, maker);
        assertEq(accrued, makerShare);
        assertEq(claimed, makerShare);
        assertEq(claimable, 0);
    }

    function testFuzz_CreatorFeeEligibility(uint8 outcomeSeed, uint128 collateralSeed) public {
        uint8 outcome = uint8(bound(uint256(outcomeSeed), 1, 2));
        uint128 collateralIn = uint128(bound(uint256(collateralSeed), 10_000e6, 100_000e6));

        (bytes32 marketId, uint64 expiryTime, uint128 fee) = _createFilledMarketWithFee(
            "creator-eligible", "settlement", 7 days, 250_000e6, 500_000_000, 500, collateralIn
        );
        uint128 creatorShare = _creatorShare(fee);
        uint256 creatorBalanceBefore = collateralToken.balanceOf(creator);

        _finalizeCreatorResolution(marketId, expiryTime, outcome);

        vm.prank(creator);
        IFeeRouterFacet(address(diamond)).claimCreatorFees(marketId);

        assertEq(collateralToken.balanceOf(creator), creatorBalanceBefore + creatorShare);
    }

    function testFuzz_CreatorFeeForfeitureSplit(uint128 collateralSeed, bool creatorChallenged) public {
        uint128 collateralIn = uint128(bound(uint256(collateralSeed), 10_000e6, 100_000e6));
        (bytes32 marketId, uint64 expiryTime, uint128 fee) = _createFilledMarketWithFee(
            "creator-forfeit", "settlement", 7 days, 250_000e6, 500_000_000, 500, collateralIn
        );
        uint128 creatorShare = _creatorShare(fee);
        uint256 treasuryUsdcBefore = collateralToken.balanceOf(treasury);

        if (creatorChallenged) {
            uint128 challengerReward = creatorShare / 10;
            uint256 challengerUsdcBefore = collateralToken.balanceOf(challengerOne);

            _finalizeChallengedResolution(marketId, expiryTime, 1, 2);

            assertEq(collateralToken.balanceOf(challengerOne), challengerUsdcBefore + challengerReward);
            assertEq(collateralToken.balanceOf(treasury), treasuryUsdcBefore + creatorShare - challengerReward);
        } else {
            _expireMarket(marketId, expiryTime);
            vm.warp(expiryTime + 48 hours);
            IOBRResolutionFacet(address(diamond)).finalizeResolution(marketId);

            assertEq(collateralToken.balanceOf(treasury), treasuryUsdcBefore + creatorShare);
        }
    }

    function _makerShare(uint128 fee) internal pure returns (uint128) {
        return uint128((uint256(fee) * 8_500) / 10_000);
    }

    function _creatorShare(uint128 fee) internal pure returns (uint128) {
        return uint128((uint256(fee) * 500) / 10_000);
    }

    function _singleSidePayouts(uint8 outcome, uint128 splitAmount)
        internal
        pure
        returns (uint256 makerPayout, uint256 takerPayout)
    {
        if (outcome == 1) {
            return (splitAmount, 0);
        }
        if (outcome == 2) {
            return (0, splitAmount);
        }
        return (splitAmount / 2, splitAmount / 2);
    }
}
