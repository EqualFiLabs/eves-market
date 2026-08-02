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

import {CurveTradingFixture} from "../helpers/DiamondFixtures.sol";

contract CurveProfilePropertiesTest is CurveTradingFixture {
    function testFuzz_LinearProfilePriceComputation(
        uint72 startPriceSeed,
        uint72 endPriceSeed,
        uint24 durationSeed,
        uint24 elapsedSeed
    ) public {
        uint72 startPrice = uint72(bound(uint256(startPriceSeed), 1, 1_000_000_000));
        uint72 endPrice = uint72(bound(uint256(endPriceSeed), 1, 1_000_000_000));
        uint24 durationMinutes = uint24(bound(uint256(durationSeed), 1, 1_440));
        uint24 elapsedMinutes = uint24(bound(uint256(elapsedSeed), 0, durationMinutes));

        uint256 curveId = _postProfileCurve(0, startPrice, endPrice, durationMinutes);
        vm.warp(block.timestamp + elapsedMinutes * 1 minutes);

        (,, uint128 price,) = ICurveViewFacet(address(diamond)).previewCurveQuote(curveId, 100e6);
        assertEq(price, _linearPrice(startPrice, endPrice, durationMinutes, elapsedMinutes));
    }

    function testFuzz_StepProfilePriceComputation(uint72 startPriceSeed, uint72 endPriceSeed, uint24 durationSeed)
        public
    {
        uint72 startPrice = uint72(bound(uint256(startPriceSeed), 1, 1_000_000_000));
        uint72 endPrice = uint72(bound(uint256(endPriceSeed), 1, 1_000_000_000));
        uint24 durationMinutes = uint24(bound(uint256(durationSeed), 2, 1_440));

        uint256 curveId = _postProfileCurve(1, startPrice, endPrice, durationMinutes);
        uint256 startTime = block.timestamp;
        vm.warp(startTime + (uint256(durationMinutes) * 60) / 2);

        (,, uint128 midpointPrice,) = ICurveViewFacet(address(diamond)).previewCurveQuote(curveId, 100e6);
        assertEq(midpointPrice, endPrice);
    }

    function testFuzz_ExponentialDecayMonotonicity(uint72 startPriceSeed, uint72 endPriceSeed, uint24 durationSeed)
        public
    {
        uint72 startPrice = uint72(bound(uint256(startPriceSeed), 100_000_000, 1_000_000_000));
        uint72 endPrice = uint72(bound(uint256(endPriceSeed), 1, startPrice));
        uint24 durationMinutes = uint24(bound(uint256(durationSeed), 4, 1_440));

        uint256 curveId = _postProfileCurve(2, startPrice, endPrice, durationMinutes);
        vm.warp(block.timestamp + (durationMinutes / 4) * 1 minutes);
        (,, uint128 firstPrice,) = ICurveViewFacet(address(diamond)).previewCurveQuote(curveId, 100e6);

        vm.warp(block.timestamp + (durationMinutes / 4) * 1 minutes);
        (,, uint128 secondPrice,) = ICurveViewFacet(address(diamond)).previewCurveQuote(curveId, 100e6);

        assertLe(secondPrice, firstPrice);
        assertLe(secondPrice, startPrice);
        assertGe(secondPrice, endPrice);
    }

    function testFuzz_CustomProfileDelegation(uint128 fixedPriceSeed) public {
        uint128 fixedPrice = uint128(bound(uint256(fixedPriceSeed), 1, 1_000_000_000));
        curveProfile.setFixedPrice(fixedPrice);

        uint256 curveId = _postProfileCurve(3, 100_000_000, 900_000_000, 120);
        (,, uint128 delegatedPrice,) = ICurveViewFacet(address(diamond)).previewCurveQuote(curveId, 100e6);

        assertEq(delegatedPrice, fixedPrice);
    }

    function _postProfileCurve(uint8 profileId, uint72 startPrice, uint72 endPrice, uint24 durationMinutes)
        internal
        returns (uint256 curveId)
    {
        (bytes32 marketId,,) = _createTradingMarket("profile-property", "curve", 7 days);
        _splitFrom(maker, marketId, 1_000e6);
        _approvePositions(maker);
        curveId = _postCurveFromMaker(marketId, true, 500e6, startPrice, endPrice, durationMinutes, profileId);
    }

    function _linearPrice(uint72 startPrice, uint72 endPrice, uint24 durationMinutes, uint24 elapsedMinutes)
        internal
        pure
        returns (uint128)
    {
        if (elapsedMinutes >= durationMinutes) {
            return endPrice;
        }
        if (endPrice >= startPrice) {
            return uint128(startPrice + ((uint256(endPrice - startPrice) * elapsedMinutes) / durationMinutes));
        }

        return uint128(startPrice - ((uint256(startPrice - endPrice) * elapsedMinutes) / durationMinutes));
    }
}
