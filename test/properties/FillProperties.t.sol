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
import {Errors} from "../../src/libraries/Errors.sol";
import {LibCurvePacking} from "../../src/libraries/LibCurvePacking.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {OwnershipFacet} from "../../src/facets/OwnershipFacet.sol";
import {FeeConfigFacet} from "../../src/facets/FeeConfigFacet.sol";

import {CurveTradingFixture, StateProbeFacet} from "../helpers/DiamondFixtures.sol";

contract FillPropertiesTest is CurveTradingFixture {
    uint256 internal constant PRICE_SCALE = 1_000_000_000;

    struct ConfiguredPredictionCase {
        bytes32 marketId;
        uint256 curveId;
        uint128 sharesTarget;
        uint128 expectedPrice;
        uint128 exactCollateralIn;
        uint32 generation;
        bytes32 commitment;
    }

    function testFuzz_FillArithmeticCorrectness(uint72 priceSeed, uint16 feeRateSeed, uint128 collateralSeed) public {
        uint72 price = uint72(bound(uint256(priceSeed), 1, 999_999_999));
        uint16 feeRate = uint16(bound(uint256(feeRateSeed), 0, 10_000));
        uint128 collateralIn = uint128(bound(uint256(collateralSeed), 1e6, 500_000e6));

        (uint256 curveId,) = _postFlatCurve(price, feeRate, 1_000_000e6);
        (uint128 sharesOut, uint128 fee, uint128 previewPrice,) =
            ICurveViewFacet(address(diamond)).previewCurveQuote(curveId, collateralIn);

        (uint128 expectedShares, uint128 expectedFee, uint128 expectedUsed) =
            _expectedQuote(collateralIn, 1_000_000e6, price, feeRate);

        assertEq(previewPrice, price);
        assertEq(sharesOut, expectedShares);
        assertEq(fee, expectedFee);
        assertLe(expectedUsed, collateralIn);

        uint128 grossCost = uint128((uint256(expectedShares) * price) / PRICE_SCALE);
        assertEq(expectedFee, _feeFor(grossCost, feeRate));
    }

    function testFuzz_FillStateMutationCorrectness(uint72 priceSeed, uint16 feeRateSeed, uint128 collateralSeed)
        public
    {
        uint72 price = uint72(bound(uint256(priceSeed), 50_000_000, 950_000_000));
        uint16 feeRate = uint16(bound(uint256(feeRateSeed), 0, 10_000));
        uint128 collateralIn = uint128(bound(uint256(collateralSeed), 1e6, 100_000e6));

        (uint256 curveId, bytes32 marketId) = _postFlatCurve(price, feeRate, 500_000e6);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        (uint128 previewShares, uint128 previewFee,,) =
            ICurveViewFacet(address(diamond)).previewCurveQuote(curveId, collateralIn);

        vm.prank(taker);
        collateralToken.approve(address(diamond), collateralIn);

        vm.prank(taker);
        uint128 sharesOut =
            ICurveTradeFacet(address(diamond)).fillCurve(curveId, collateralIn, 0, generation, commitment);

        _assertFilledState(marketId, curveId, price, previewShares, previewFee, sharesOut);
    }

    function testFuzz_ConfiguredPredictionFillUsesBookPricing(
        uint8 tickSizeSeed,
        uint16 denominatorSeed,
        uint16 tickSeed,
        uint8 shareUnitsSeed
    ) public {
        ConfiguredPredictionCase memory curve = _createConfiguredPredictionCase(
            uint128(bound(uint256(tickSizeSeed), 1, 100)),
            uint128(bound(uint256(denominatorSeed), 10, 10_000)),
            uint72(bound(uint256(tickSeed), 1, 1_000)),
            uint128(bound(uint256(shareUnitsSeed), 1, 100))
        );

        (uint128 previewShares, uint128 previewFee, uint128 previewPrice,) =
            ICurveViewFacet(address(diamond)).previewCurveQuote(curve.curveId, curve.exactCollateralIn);

        assertEq(previewShares, curve.sharesTarget);
        assertEq(previewFee, 0);
        assertEq(previewPrice, curve.expectedPrice);

        vm.prank(taker);
        collateralToken.approve(address(diamond), curve.exactCollateralIn);

        vm.prank(taker);
        uint128 sharesOut = ICurveTradeFacet(address(diamond))
            .fillCurve(curve.curveId, curve.exactCollateralIn, curve.sharesTarget, curve.generation, curve.commitment);

        (uint96 lastTradePrice, uint128 totalFeePool, uint128 totalQuoteVolume) =
            StateProbeFacet(address(diamond)).getStoredMarketTrading(curve.marketId);

        assertEq(sharesOut, curve.sharesTarget);
        assertEq(lastTradePrice, curve.expectedPrice);
        assertEq(totalFeePool, 0);
        assertEq(totalQuoteVolume, curve.exactCollateralIn);
    }

    function testFuzz_FrontRunningProtection(uint72 startPriceSeed, uint72 endPriceSeed) public {
        uint72 startPrice = uint72(bound(uint256(startPriceSeed), 100_000_000, 900_000_000));
        uint72 endPrice = uint72(bound(uint256(endPriceSeed), 100_000_000, 900_000_000));
        if (endPrice == startPrice) {
            endPrice = startPrice == 900_000_000 ? startPrice - 1 : startPrice + 1;
        }

        (bytes32 marketId,,) = _createTradingMarket("front-running", "properties", 7 days);
        _splitFrom(maker, marketId, 10_000e6);
        _approvePositions(maker);

        uint256 curveId = _postCurveFromMaker(marketId, true, 10_000e6, startPrice, endPrice, 240, 0);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        uint256 updatedPacked = uint256(LibCurvePacking.pack(endPrice, startPrice, 240, 0));

        vm.prank(maker);
        ICurveLifecycleFacet(address(diamond)).updateCurve(curveId, updatedPacked, generation);

        vm.prank(taker);
        collateralToken.approve(address(diamond), 1_000e6);

        vm.prank(taker);
        vm.expectRevert(abi.encodeWithSelector(Errors.GenerationMismatch.selector, generation, generation + 1));
        ICurveTradeFacet(address(diamond)).fillCurve(curveId, 1_000e6, 1, generation, commitment);

        (uint32 newGeneration,) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        vm.prank(taker);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.CommitmentMismatch.selector, commitment, keccak256(abi.encodePacked(updatedPacked))
            )
        );
        ICurveTradeFacet(address(diamond)).fillCurve(curveId, 1_000e6, 1, newGeneration, commitment);
    }

    function testFuzz_SlippageProtection(uint72 priceSeed, uint128 collateralSeed) public {
        uint72 price = uint72(bound(uint256(priceSeed), 100_000_000, 900_000_000));
        uint128 collateralIn = uint128(bound(uint256(collateralSeed), 1e6, 50_000e6));

        (uint256 curveId,) = _postFlatCurve(price, 0, 100_000e6);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        (uint128 previewShares,,,) = ICurveViewFacet(address(diamond)).previewCurveQuote(curveId, collateralIn);

        vm.prank(taker);
        collateralToken.approve(address(diamond), collateralIn);

        vm.prank(taker);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.SlippageExceeded.selector, previewShares, uint128(previewShares + 1))
        );
        ICurveTradeFacet(address(diamond)).fillCurve(curveId, collateralIn, previewShares + 1, generation, commitment);
    }

    function _postFlatCurve(uint72 price, uint16 feeRate, uint128 volume)
        internal
        returns (uint256 curveId, bytes32 marketId)
    {
        vm.prank(owner);
        FeeConfigFacet(address(diamond)).setOrderbookEntryFeeBps(feeRate);

        (marketId,,) = _createTradingMarket("fill-property", "curve", 7 days);
        _splitFrom(maker, marketId, volume);
        _approvePositions(maker);

        curveId = _postCurveFromMaker(marketId, true, volume, price, price, 240, 0);
    }

    function _createConfiguredPredictionCase(
        uint128 tickSize,
        uint128 priceDenominator,
        uint72 tick,
        uint128 shareUnits
    ) internal returns (ConfiguredPredictionCase memory curve) {
        uint128 volume = (shareUnits + 1) * priceDenominator;

        vm.prank(owner);
        FeeConfigFacet(address(diamond)).setOrderbookEntryFeeBps(0);

        (curve.marketId,,) = _createTradingMarket("configured-fill", "properties", 7 days);
        StateProbeFacet(address(diamond)).materializeMarketSideBookFixture(curve.marketId, true);
        bytes32 yesBookId = IBookAdminFacet(address(diamond)).getMarketSideBook(curve.marketId, true);
        StateProbeFacet(address(diamond))
            .setBookPricingFixture(
                yesBookId,
                uint256(uint8(LibEveMarket.BookPricingMode.PREDICTION_PAYOUT)),
                tickSize,
                priceDenominator,
                0,
                1_000
            );

        _splitFrom(maker, curve.marketId, volume);
        _approvePositions(maker);

        curve.curveId = _postCurveFromMaker(curve.marketId, true, volume, tick, tick, 240, 0);
        curve.sharesTarget = shareUnits * priceDenominator;
        curve.expectedPrice = uint128(uint256(tick) * tickSize);
        curve.exactCollateralIn = uint128((uint256(curve.sharesTarget) * curve.expectedPrice) / priceDenominator);
        (curve.generation, curve.commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curve.curveId);
    }

    function _expectedQuote(uint128 collateralIn, uint128 volume, uint72 price, uint16 feeRate)
        internal
        pure
        returns (uint128 sharesOut, uint128 fee, uint128 collateralUsed)
    {
        uint256 grossBudget = (uint256(collateralIn) * 10_000) / (10_000 + uint256(feeRate));
        uint256 rawShares = (grossBudget * PRICE_SCALE) / price;

        if (rawShares > volume) {
            rawShares = volume;
        }

        sharesOut = uint128(rawShares);
        uint128 grossCost = uint128((uint256(sharesOut) * price) / PRICE_SCALE);
        fee = _feeFor(grossCost, feeRate);
        collateralUsed = grossCost + fee;
    }

    function _feeFor(uint128 grossCost, uint16 feeRate) internal pure returns (uint128) {
        return uint128((uint256(grossCost) * feeRate) / 10_000);
    }

    function _assertFilledState(
        bytes32 marketId,
        uint256 curveId,
        uint72 price,
        uint128 previewShares,
        uint128 previewFee,
        uint128 sharesOut
    ) internal view {
        (uint96 lastTradePrice, uint128 totalFeePool, uint128 totalQuoteVolume) =
            StateProbeFacet(address(diamond)).getStoredMarketTrading(marketId);
        (uint128 makerQuoteVolume, uint128 makerFeesAccrued,) =
            StateProbeFacet(address(diamond)).getStoredMakerAccounting(marketId, maker);
        (uint128 creatorFeesEscrowed, uint128 protocolFeesAccrued,,) =
            StateProbeFacet(address(diamond)).getStoredMarketFees(marketId);
        (, uint128 remainingVolume,,,,,,) = StateProbeFacet(address(diamond)).getStoredCurve(curveId);

        assertEq(sharesOut, previewShares);
        assertEq(lastTradePrice, price);
        assertEq(totalFeePool, previewFee);
        uint128 expectedCollateralUsed = _grossCost(previewShares, price) + previewFee;

        assertEq(totalQuoteVolume, expectedCollateralUsed);
        assertEq(makerQuoteVolume, expectedCollateralUsed);
        assertEq(makerFeesAccrued + creatorFeesEscrowed + protocolFeesAccrued, previewFee);
        assertEq(remainingVolume, 500_000e6 - previewShares);
    }

    function _grossCost(uint128 sharesOut, uint128 price) internal pure returns (uint128) {
        return uint128((uint256(sharesOut) * price) / PRICE_SCALE);
    }
}
