// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test, console2} from "../../lib/forge-std/src/Test.sol";

import {IBookAdminFacet} from "../../src/interfaces/IBookAdminFacet.sol";
import {IBookOrderFacet} from "../../src/interfaces/IBookOrderFacet.sol";
import {IBookTradeFacet} from "../../src/interfaces/IBookTradeFacet.sol";
import {IBookViewFacet} from "../../src/interfaces/IBookViewFacet.sol";
import {ICurveInventoryFacet} from "../../src/interfaces/ICurveInventoryFacet.sol";
import {ICurveLifecycleFacet} from "../../src/interfaces/ICurveLifecycleFacet.sol";
import {ICurveTradeFacet} from "../../src/interfaces/ICurveTradeFacet.sol";
import {ICurveViewFacet} from "../../src/interfaces/ICurveViewFacet.sol";
import {CurveCLOBTypes} from "../../src/types/CurveCLOBTypes.sol";
import {LibCurvePacking} from "../../src/libraries/LibCurvePacking.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";

import {CurveTradingFixture} from "../helpers/DiamondFixtures.sol";

contract CurveCLOBGasTest is CurveTradingFixture {
    uint256 internal constant BATCH_SIZE = 4;

    function test_Gas_PostCurveSingleVsBatch() public {
        (bytes32 marketId,,) = _createTradingMarket("Gas batch post", "curve", 7 days);
        _splitFrom(maker, marketId, 10_000e6);
        _approvePositions(maker);

        vm.pauseGasMetering();
        vm.resumeGasMetering();

        vm.prank(maker);
        ICurveLifecycleFacet(address(diamond))
            .postCurve(marketId, true, 1_000, 400_000_000, 500_000_000, 120, 0, LibEveMarket.PositionTokenType.CTF);

        uint256 singleGas = vm.lastCallGas().gasTotalUsed;

        vm.pauseGasMetering();
        _splitFrom(maker, marketId, 10_000e6);
        _approvePositions(maker);
        CurveCLOBTypes.CurveCreationParams[] memory params = _buildCreationParams(BATCH_SIZE);
        vm.resumeGasMetering();

        vm.prank(maker);
        ICurveLifecycleFacet(address(diamond)).postCurvesBatch(marketId, LibEveMarket.PositionTokenType.CTF, params);

        uint256 batchGas = vm.lastCallGas().gasTotalUsed;
        uint256 averageGas = batchGas / BATCH_SIZE;

        console2.log("post.single", singleGas);
        console2.log("post.batch.total", batchGas);
        console2.log("post.batch.average", averageGas);
    }

    function test_Gas_UpdateCurveSingleVsBatchAverage() public {
        (bytes32 marketId,,) = _createTradingMarket("Gas batch update", "curve", 7 days);
        _splitFrom(maker, marketId, 20_000e6);
        _approvePositions(maker);

        uint256[] memory curveIds = new uint256[](BATCH_SIZE + 1);
        for (uint256 index = 0; index < curveIds.length; ++index) {
            curveIds[index] = _postCurveFromMaker(marketId, true, 1_000, 400_000_000, 500_000_000, 120, 0);
        }

        uint256 singlePacked = LibCurvePacking.pack(420_000_000, 520_000_000, 180, 0);

        vm.pauseGasMetering();
        vm.resumeGasMetering();

        vm.prank(maker);
        ICurveLifecycleFacet(address(diamond)).updateCurve(curveIds[0], singlePacked, 1);

        uint256 singleGas = vm.lastCallGas().gasTotalUsed;

        CurveCLOBTypes.CurveUpdateParams[] memory params = new CurveCLOBTypes.CurveUpdateParams[](BATCH_SIZE);
        for (uint256 index = 0; index < BATCH_SIZE; ++index) {
            params[index] = CurveCLOBTypes.CurveUpdateParams({
                curveId: curveIds[index + 1],
                newPacked: LibCurvePacking.pack(
                    uint72(430_000_000 + (index * 10_000_000)),
                    uint72(530_000_000 + (index * 10_000_000)),
                    uint24(180 + (index * 10)),
                    0
                ),
                expectedGeneration: 1
            });
        }

        vm.pauseGasMetering();
        vm.resumeGasMetering();

        vm.prank(maker);
        ICurveLifecycleFacet(address(diamond)).updateCurvesBatch(params);

        uint256 batchGas = vm.lastCallGas().gasTotalUsed;
        uint256 averageGas = batchGas / BATCH_SIZE;

        console2.log("update.single", singleGas);
        console2.log("update.batch.total", batchGas);
        console2.log("update.batch.average", averageGas);
    }

    function test_Gas_CancelCurveSingleVsBatch() public {
        (bytes32 marketId,,) = _createTradingMarket("Gas batch cancel", "curve", 7 days);
        _splitFrom(maker, marketId, 20_000e6);
        _approvePositions(maker);

        uint256[] memory curveIds = new uint256[](BATCH_SIZE + 1);
        for (uint256 index = 0; index < curveIds.length; ++index) {
            curveIds[index] = _postCurveFromMaker(marketId, index % 2 == 0, 1_000, 400_000_000, 500_000_000, 120, 0);
        }

        vm.pauseGasMetering();
        vm.resumeGasMetering();

        vm.prank(maker);
        ICurveLifecycleFacet(address(diamond)).cancelCurve(curveIds[0]);

        uint256 singleGas = vm.lastCallGas().gasTotalUsed;

        uint256[] memory batchIds = new uint256[](BATCH_SIZE);
        for (uint256 index = 0; index < BATCH_SIZE; ++index) {
            batchIds[index] = curveIds[index + 1];
        }

        vm.pauseGasMetering();
        vm.resumeGasMetering();

        vm.prank(maker);
        ICurveLifecycleFacet(address(diamond)).cancelCurvesBatch(batchIds);

        uint256 batchGas = vm.lastCallGas().gasTotalUsed;
        uint256 averageGas = batchGas / BATCH_SIZE;

        console2.log("cancel.single", singleGas);
        console2.log("cancel.batch.total", batchGas);
        console2.log("cancel.batch.average", averageGas);
    }

    function _buildCreationParams(uint256 length)
        internal
        pure
        returns (CurveCLOBTypes.CurveCreationParams[] memory params)
    {
        params = new CurveCLOBTypes.CurveCreationParams[](length);

        for (uint256 index = 0; index < length; ++index) {
            params[index] = CurveCLOBTypes.CurveCreationParams({
                isYesSide: index % 2 == 0,
                volume: 1_000,
                startPrice: uint72(400_000_000 + (index * 10_000_000)),
                endPrice: uint72(500_000_000 + (index * 10_000_000)),
                durationMinutes: uint24(120 + (index * 15)),
                profileId: uint8(index % 2),
                tickPresetId: 0
            });
        }
    }
}
