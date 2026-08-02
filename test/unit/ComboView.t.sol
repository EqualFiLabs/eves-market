// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "../../lib/forge-std/src/Test.sol";

import {ComboViewFacet} from "../../src/facets/native/ComboViewFacet.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {LibNativePosition} from "../../src/libraries/LibNativePosition.sol";
import {NativePositionTypes} from "../../src/types/NativePositionTypes.sol";

import {MockUSDC} from "../helpers/MockUSDC.sol";

contract ComboViewHarness is ComboViewFacet {
    function seedBinaryLeg(bytes32 marketId, address collateralToken, uint8 outcomeIndex)
        external
        returns (uint256 positionId)
    {
        LibEveMarket.Market storage market = LibEveMarket.store().markets[marketId];
        market.marketId = marketId;
        market.marketType = LibEveMarket.MarketType.CLOB;
        market.collateralToken = collateralToken;
        market.state = LibEveMarket.MarketState.Trading;

        bytes32 conditionId = LibNativePosition.binaryConditionIdFor(marketId);
        positionId = LibNativePosition.positionIdFor(LibNativePosition.MODULE_BINARY, conditionId, outcomeIndex);
        LibEveMarket.store().nativePositionMetadata[positionId] = LibEveMarket.NativePositionMetadata({
            moduleId: LibNativePosition.MODULE_BINARY,
            conditionId: conditionId,
            outcomeIndex: outcomeIndex,
            marketId: marketId,
            exists: true
        });
    }

    function seedCombo(uint256[] calldata legs) external returns (bytes32 conditionId, uint256 yesId, uint256 noId) {
        uint256[] memory memoryLegs = new uint256[](legs.length);
        for (uint256 index; index < legs.length; ++index) {
            memoryLegs[index] = legs[index];
        }
        conditionId = LibNativePosition.comboConditionIdFor(memoryLegs);
        yesId = LibNativePosition.positionIdFor(
            LibNativePosition.MODULE_COMBINATORIAL, conditionId, LibNativePosition.OUTCOME_YES
        );
        noId = LibNativePosition.positionIdFor(
            LibNativePosition.MODULE_COMBINATORIAL, conditionId, LibNativePosition.OUTCOME_NO
        );

        LibEveMarket.ComboCondition storage condition = LibEveMarket.store().comboConditions[conditionId];
        condition.conditionId = conditionId;
        condition.legsHash = keccak256(abi.encode(memoryLegs));
        condition.legCount = uint16(legs.length);
        condition.preparedAt = uint64(block.timestamp);
        condition.exists = true;
        for (uint256 index; index < legs.length; ++index) {
            LibEveMarket.store().comboConditionLegs[conditionId].push(legs[index]);
        }

        LibEveMarket.store().nativePositionMetadata[yesId] = LibEveMarket.NativePositionMetadata({
            moduleId: LibNativePosition.MODULE_COMBINATORIAL,
            conditionId: conditionId,
            outcomeIndex: LibNativePosition.OUTCOME_YES,
            marketId: bytes32(0),
            exists: true
        });
        LibEveMarket.store().nativePositionMetadata[noId] = LibEveMarket.NativePositionMetadata({
            moduleId: LibNativePosition.MODULE_COMBINATORIAL,
            conditionId: conditionId,
            outcomeIndex: LibNativePosition.OUTCOME_NO,
            marketId: bytes32(0),
            exists: true
        });
    }

    function resolveFixture(bytes32 marketId, LibEveMarket.MarketOutcome outcome) external {
        LibEveMarket.Market storage market = LibEveMarket.store().markets[marketId];
        market.state = LibEveMarket.MarketState.Resolved;
        market.outcome = outcome;
        market.resolutionTime = uint64(block.timestamp);
    }
}

contract ComboViewTest is Test {
    ComboViewHarness internal viewFacet;
    MockUSDC internal collateral;

    bytes32 internal constant MARKET_A = bytes32(uint256(0xA));
    bytes32 internal constant MARKET_B = bytes32(uint256(0xB));
    uint128 internal constant AMOUNT = 100e6;

    uint256 internal aYes;
    uint256 internal bYes;
    bytes32 internal conditionId;
    uint256 internal comboYes;
    uint256 internal comboNo;

    function setUp() public {
        viewFacet = new ComboViewHarness();
        collateral = new MockUSDC();

        aYes = viewFacet.seedBinaryLeg(MARKET_A, address(collateral), LibNativePosition.OUTCOME_YES);
        bYes = viewFacet.seedBinaryLeg(MARKET_B, address(collateral), LibNativePosition.OUTCOME_YES);

        uint256[] memory legs = _sorted(aYes, bYes);
        (conditionId, comboYes, comboNo) = viewFacet.seedCombo(legs);
    }

    function test_GetNativePositionMetadataReturnsStoredTuple() public view {
        LibEveMarket.NativePositionMetadata memory metadata = viewFacet.getNativePositionMetadata(comboYes);

        assertTrue(metadata.exists);
        assertEq(metadata.moduleId, LibNativePosition.MODULE_COMBINATORIAL);
        assertEq(metadata.conditionId, conditionId);
        assertEq(metadata.outcomeIndex, LibNativePosition.OUTCOME_YES);
        assertEq(metadata.marketId, bytes32(0));
    }

    function test_RevertWhen_NativePositionMetadataMissing() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.NativePositionNotFound.selector, uint256(404)));
        viewFacet.getNativePositionMetadata(404);
    }

    function test_PreviewCompressionReturnsReducedPositionWithoutMutating() public {
        viewFacet.resolveFixture(MARKET_A, LibEveMarket.MarketOutcome.Yes);

        assertTrue(viewFacet.isComboCompressible(comboYes));
        NativePositionTypes.CompressionResult memory result = viewFacet.previewComboCompression(comboYes, AMOUNT);

        uint256[] memory reducedLegs = new uint256[](1);
        reducedLegs[0] = bYes;
        bytes32 reducedConditionId = LibNativePosition.comboConditionIdFor(reducedLegs);
        uint256 expectedReducedYes = LibNativePosition.positionIdFor(
            LibNativePosition.MODULE_COMBINATORIAL, reducedConditionId, LibNativePosition.OUTCOME_YES
        );

        assertEq(result.newPositionId, expectedReducedYes);
        assertEq(result.positionAmount, AMOUNT);
        assertEq(result.collateralOut, 0);
        vm.expectRevert(abi.encodeWithSelector(Errors.NativePositionNotFound.selector, expectedReducedYes));
        viewFacet.getNativePositionMetadata(expectedReducedYes);
    }

    function test_PreviewCompressionRevertsWhenNoLegResolved() public {
        assertFalse(viewFacet.isComboCompressible(comboYes));
        vm.expectRevert(abi.encodeWithSelector(Errors.ComboPositionNotCompressible.selector, comboYes));
        viewFacet.previewComboCompression(comboYes, AMOUNT);
    }

    function _sorted(uint256 first, uint256 second) internal pure returns (uint256[] memory legs) {
        legs = new uint256[](2);
        if (first < second) {
            legs[0] = first;
            legs[1] = second;
        } else {
            legs[0] = second;
            legs[1] = first;
        }
    }
}
