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

contract CurveProfilesTest is CurveTradingFixture {
    function test_LinearProfileInterpolatesAcrossDuration() public {
        uint256 curveId = _postProfileCurve(0, 200_000_000, 800_000_000, 100);
        uint256 startTime = vm.getBlockTimestamp();

        vm.warp(startTime + 25 minutes);
        (,, uint128 quarterPrice,) = ICurveViewFacet(address(diamond)).previewCurveQuote(curveId, 100e6);
        assertEq(quarterPrice, 350_000_000);

        vm.warp(startTime + 100 minutes);
        (,, uint128 endPrice,) = ICurveViewFacet(address(diamond)).previewCurveQuote(curveId, 100e6);
        assertEq(endPrice, 800_000_000);
    }

    function test_StepProfileJumpsAtMidpoint() public {
        uint256 curveId = _postProfileCurve(1, 300_000_000, 700_000_000, 80);

        vm.warp(block.timestamp + 39 minutes);
        (,, uint128 preMidpointPrice,) = ICurveViewFacet(address(diamond)).previewCurveQuote(curveId, 100e6);
        assertEq(preMidpointPrice, 300_000_000);

        vm.warp(block.timestamp + 1 minutes);
        (,, uint128 atMidpointPrice,) = ICurveViewFacet(address(diamond)).previewCurveQuote(curveId, 100e6);
        assertEq(atMidpointPrice, 700_000_000);
    }

    function test_ExponentialDecayProfileUsesSquaredRemainingFactor() public {
        uint256 curveId = _postProfileCurve(2, 900_000_000, 100_000_000, 100);
        uint256 startTime = vm.getBlockTimestamp();

        vm.warp(startTime + 25 minutes);
        (,, uint128 quarterPrice,) = ICurveViewFacet(address(diamond)).previewCurveQuote(curveId, 100e6);
        assertEq(quarterPrice, 550_000_000);

        vm.warp(startTime + 50 minutes);
        (,, uint128 halfPrice,) = ICurveViewFacet(address(diamond)).previewCurveQuote(curveId, 100e6);
        assertEq(halfPrice, 300_000_000);
    }

    function test_CustomProfileDelegatesToRegisteredContract() public {
        curveProfile.setFixedPrice(777_777_777);
        uint256 curveId = _postProfileCurve(3, 100_000_000, 900_000_000, 120);

        (,, uint128 delegatedPrice,) = ICurveViewFacet(address(diamond)).previewCurveQuote(curveId, 100e6);
        assertEq(delegatedPrice, 777_777_777);
    }

    function _postProfileCurve(uint8 profileId, uint72 startPrice, uint72 endPrice, uint24 durationMinutes)
        internal
        returns (uint256 curveId)
    {
        (bytes32 marketId,,) = _createTradingMarket("Profile market", "curve", 7 days);
        _splitFrom(maker, marketId, 1_000e6);
        _approvePositions(maker);

        curveId = _postCurveFromMaker(marketId, true, 500e6, startPrice, endPrice, durationMinutes, profileId);
    }
}
