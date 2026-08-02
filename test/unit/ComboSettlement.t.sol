// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "../../lib/forge-std/src/Test.sol";

import {ComboSettlementFacet} from "../../src/facets/native/ComboSettlementFacet.sol";
import {IEvesPositionManager} from "../../src/interfaces/IEvesPositionManager.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {LibNativePosition} from "../../src/libraries/LibNativePosition.sol";
import {NativePositionTypes} from "../../src/types/NativePositionTypes.sol";
import {EvesPositionManager} from "../../src/tokens/EvesPositionManager.sol";

import {MockUSDC} from "../helpers/MockUSDC.sol";

contract ComboSettlementHarness is ComboSettlementFacet {
    function configure(address collateralToken, address positionManager) external {
        LibEveMarket.MarketConfig storage config = LibEveMarket.store().config;
        config.collateralToken = collateralToken;
        config.evesPositionManager = positionManager;
    }

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

    function mintPosition(address to, uint256 positionId, uint128 amount) external {
        IEvesPositionManager(LibEveMarket.store().config.evesPositionManager).mint(to, positionId, amount);
    }

    function resolveFixture(bytes32 marketId, LibEveMarket.MarketOutcome outcome) external {
        LibEveMarket.Market storage market = LibEveMarket.store().markets[marketId];
        market.state = LibEveMarket.MarketState.Resolved;
        market.outcome = outcome;
        market.resolutionTime = uint64(block.timestamp);
    }
}

contract ComboSettlementTest is Test {
    ComboSettlementHarness internal settlement;
    EvesPositionManager internal positions;
    MockUSDC internal collateral;

    address internal trader = makeAddr("trader");

    bytes32 internal constant MARKET_A = bytes32(uint256(0xA));
    bytes32 internal constant MARKET_B = bytes32(uint256(0xB));
    uint128 internal constant AMOUNT = 100e6;

    uint256 internal aYes;
    uint256 internal bYes;
    bytes32 internal conditionId;
    uint256 internal comboYes;
    uint256 internal comboNo;

    function setUp() public {
        settlement = new ComboSettlementHarness();
        positions = new EvesPositionManager(address(settlement), "");
        collateral = new MockUSDC();
        settlement.configure(address(collateral), address(positions));

        aYes = settlement.seedBinaryLeg(MARKET_A, address(collateral), LibNativePosition.OUTCOME_YES);
        bYes = settlement.seedBinaryLeg(MARKET_B, address(collateral), LibNativePosition.OUTCOME_YES);

        uint256[] memory legs = _sorted(aYes, bYes);
        (conditionId, comboYes, comboNo) = settlement.seedCombo(legs);
        collateral.mint(address(settlement), 1_000_000e6);
    }

    function test_RedeemComboYesPaysFullWhenAllLegsWin() public {
        settlement.mintPosition(trader, comboYes, AMOUNT);
        settlement.resolveFixture(MARKET_A, LibEveMarket.MarketOutcome.Yes);
        settlement.resolveFixture(MARKET_B, LibEveMarket.MarketOutcome.Yes);

        uint256 balanceBefore = collateral.balanceOf(trader);

        vm.prank(trader);
        uint128 collateralOut = settlement.redeemCombo(comboYes, AMOUNT, trader);

        assertEq(collateralOut, AMOUNT);
        assertEq(collateral.balanceOf(trader), balanceBefore + AMOUNT);
        assertEq(positions.balanceOf(trader, comboYes), 0);
    }

    function test_RedeemComboYesBurnsForZeroWhenAnyLegLoses() public {
        settlement.mintPosition(trader, comboYes, AMOUNT);
        settlement.resolveFixture(MARKET_A, LibEveMarket.MarketOutcome.No);

        vm.prank(trader);
        uint128 collateralOut = settlement.redeemCombo(comboYes, AMOUNT, trader);

        assertEq(collateralOut, 0);
        assertEq(positions.balanceOf(trader, comboYes), 0);
    }

    function test_RedeemComboNoPaysFullWhenAnyLegLoses() public {
        settlement.mintPosition(trader, comboNo, AMOUNT);
        settlement.resolveFixture(MARKET_A, LibEveMarket.MarketOutcome.No);

        uint256 balanceBefore = collateral.balanceOf(trader);

        vm.prank(trader);
        uint128 collateralOut = settlement.redeemCombo(comboNo, AMOUNT, trader);

        assertEq(collateralOut, AMOUNT);
        assertEq(collateral.balanceOf(trader), balanceBefore + AMOUNT);
        assertEq(positions.balanceOf(trader, comboNo), 0);
    }

    function test_InvalidLegSplitsValueBetweenComboYesAndNo() public {
        settlement.mintPosition(trader, comboYes, AMOUNT);
        settlement.mintPosition(trader, comboNo, AMOUNT);
        settlement.resolveFixture(MARKET_A, LibEveMarket.MarketOutcome.Invalid);
        settlement.resolveFixture(MARKET_B, LibEveMarket.MarketOutcome.Yes);

        uint256 balanceBefore = collateral.balanceOf(trader);

        vm.startPrank(trader);
        uint128 yesOut = settlement.redeemCombo(comboYes, AMOUNT, trader);
        uint128 noOut = settlement.redeemCombo(comboNo, AMOUNT, trader);
        vm.stopPrank();

        assertEq(yesOut, AMOUNT / 2);
        assertEq(noOut, AMOUNT / 2);
        assertEq(collateral.balanceOf(trader), balanceBefore + AMOUNT);
    }

    function testFuzz_ComboYesAndNoRedemptionNeverOverpaysLockedCollateral(
        uint256 rawAmount,
        uint8 rawOutcomeA,
        uint8 rawOutcomeB
    ) public {
        uint128 amount = uint128(bound(rawAmount, 1, 1_000_000e6));
        LibEveMarket.MarketOutcome outcomeA = _binaryOutcome(rawOutcomeA);
        LibEveMarket.MarketOutcome outcomeB = _binaryOutcome(rawOutcomeB);

        settlement.mintPosition(trader, comboYes, amount);
        settlement.mintPosition(trader, comboNo, amount);
        settlement.resolveFixture(MARKET_A, outcomeA);
        settlement.resolveFixture(MARKET_B, outcomeB);

        uint256 balanceBefore = collateral.balanceOf(trader);

        vm.startPrank(trader);
        settlement.redeemCombo(comboYes, amount, trader);
        settlement.redeemCombo(comboNo, amount, trader);
        vm.stopPrank();

        assertLe(collateral.balanceOf(trader) - balanceBefore, amount);
        assertEq(positions.balanceOf(trader, comboYes), 0);
        assertEq(positions.balanceOf(trader, comboNo), 0);
    }

    function test_CompressComboYesRemovesWinningResolvedLeg() public {
        settlement.mintPosition(trader, comboYes, AMOUNT);
        settlement.resolveFixture(MARKET_A, LibEveMarket.MarketOutcome.Yes);

        uint256[] memory reducedLegs = new uint256[](1);
        reducedLegs[0] = bYes;
        bytes32 reducedConditionId = LibNativePosition.comboConditionIdFor(reducedLegs);
        uint256 reducedYes = LibNativePosition.positionIdFor(
            LibNativePosition.MODULE_COMBINATORIAL, reducedConditionId, LibNativePosition.OUTCOME_YES
        );

        vm.prank(trader);
        NativePositionTypes.CompressionResult memory result = settlement.compressCombo(comboYes, AMOUNT, trader);

        assertEq(result.newPositionId, reducedYes);
        assertEq(result.positionAmount, AMOUNT);
        assertEq(result.collateralOut, 0);
        assertEq(positions.balanceOf(trader, comboYes), 0);
        assertEq(positions.balanceOf(trader, reducedYes), AMOUNT);
    }

    function test_CompressComboNoPaysFullWhenResolvedLegLoses() public {
        settlement.mintPosition(trader, comboNo, AMOUNT);
        settlement.resolveFixture(MARKET_A, LibEveMarket.MarketOutcome.No);

        uint256 balanceBefore = collateral.balanceOf(trader);

        vm.prank(trader);
        NativePositionTypes.CompressionResult memory result = settlement.compressCombo(comboNo, AMOUNT, trader);

        assertEq(result.newPositionId, 0);
        assertEq(result.positionAmount, 0);
        assertEq(result.collateralOut, AMOUNT);
        assertEq(collateral.balanceOf(trader), balanceBefore + AMOUNT);
        assertEq(positions.balanceOf(trader, comboNo), 0);
    }

    function _binaryOutcome(uint8 rawOutcome) internal pure returns (LibEveMarket.MarketOutcome outcome) {
        uint8 normalized = (rawOutcome % 3) + 1;
        if (normalized == 1) return LibEveMarket.MarketOutcome.Yes;
        if (normalized == 2) return LibEveMarket.MarketOutcome.No;
        return LibEveMarket.MarketOutcome.Invalid;
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
