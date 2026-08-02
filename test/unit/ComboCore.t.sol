// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "../../lib/forge-std/src/Test.sol";

import {ComboCoreFacet} from "../../src/facets/native/ComboCoreFacet.sol";
import {IComboCoreFacet} from "../../src/interfaces/IComboCoreFacet.sol";
import {IEvesPositionManager} from "../../src/interfaces/IEvesPositionManager.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {LibNativePosition} from "../../src/libraries/LibNativePosition.sol";
import {NativePositionTypes} from "../../src/types/NativePositionTypes.sol";
import {EvesPositionManager} from "../../src/tokens/EvesPositionManager.sol";

import {MockUSDC} from "../helpers/MockUSDC.sol";

contract ComboCoreHarness is ComboCoreFacet {
    function configure(address collateralToken, address positionManager) external {
        LibEveMarket.MarketConfig storage config = LibEveMarket.store().config;
        config.collateralToken = collateralToken;
        config.evesPositionManager = positionManager;
    }

    function seedCLOBMarket(bytes32 marketId, address collateralToken, LibEveMarket.MarketState state_) external {
        this.seedCLOBMarketWithWindow(marketId, collateralToken, state_, block.timestamp, block.timestamp + 30 days);
    }

    function seedCLOBMarketWithWindow(
        bytes32 marketId,
        address collateralToken,
        LibEveMarket.MarketState state_,
        uint256 tradingStartTime,
        uint256 expiryTime
    ) external {
        require(tradingStartTime <= type(uint64).max);
        require(expiryTime <= type(uint64).max);
        LibEveMarket.Market storage market = LibEveMarket.store().markets[marketId];
        market.marketId = marketId;
        market.marketType = LibEveMarket.MarketType.CLOB;
        market.positionTokenType = LibEveMarket.PositionTokenType.CTF;
        market.collateralToken = collateralToken;
        market.state = state_;
        market.outcome = LibEveMarket.MarketOutcome.Unresolved;
        market.tradingStartTime = uint64(tradingStartTime);
        market.expiryTime = uint64(expiryTime);
    }

    function prepareNativeBinaryFixture(bytes32 marketId)
        external
        returns (uint256 yesPositionId, uint256 noPositionId)
    {
        bytes32 conditionId = LibNativePosition.binaryConditionIdFor(marketId);
        yesPositionId = LibNativePosition.positionIdFor(
            LibNativePosition.MODULE_BINARY, conditionId, LibNativePosition.OUTCOME_YES
        );
        noPositionId =
            LibNativePosition.positionIdFor(LibNativePosition.MODULE_BINARY, conditionId, LibNativePosition.OUTCOME_NO);

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.NativeBinaryCondition storage binary = state.nativeBinaryConditions[marketId];
        binary.marketId = marketId;
        binary.conditionId = conditionId;
        binary.yesPositionId = yesPositionId;
        binary.noPositionId = noPositionId;
        binary.exists = true;

        state.nativePositionMetadata[yesPositionId] = LibEveMarket.NativePositionMetadata({
            moduleId: LibNativePosition.MODULE_BINARY,
            conditionId: conditionId,
            outcomeIndex: LibNativePosition.OUTCOME_YES,
            marketId: marketId,
            exists: true
        });
        state.nativePositionMetadata[noPositionId] = LibEveMarket.NativePositionMetadata({
            moduleId: LibNativePosition.MODULE_BINARY,
            conditionId: conditionId,
            outcomeIndex: LibNativePosition.OUTCOME_NO,
            marketId: marketId,
            exists: true
        });
    }

    function mintPosition(address to, uint256 positionId, uint128 amount) external {
        IEvesPositionManager(LibEveMarket.store().config.evesPositionManager).mint(to, positionId, amount);
    }
}

contract ComboCoreTest is Test {
    ComboCoreHarness internal combo;
    EvesPositionManager internal positions;
    MockUSDC internal collateral;

    address internal trader = makeAddr("trader");

    bytes32 internal constant MARKET_A = bytes32(uint256(0xA));
    bytes32 internal constant MARKET_B = bytes32(uint256(0xB));
    bytes32 internal constant MARKET_C = bytes32(uint256(0xC));
    uint128 internal constant AMOUNT = 100e6;

    uint256 internal aYes;
    uint256 internal aNo;
    uint256 internal bYes;
    uint256 internal cYes;

    function setUp() public {
        combo = new ComboCoreHarness();
        positions = new EvesPositionManager(address(combo), "");
        collateral = new MockUSDC();

        combo.configure(address(collateral), address(positions));
        _seedMarket(MARKET_A);
        _seedMarket(MARKET_B);
        _seedMarket(MARKET_C);
        (aYes, aNo) = combo.prepareNativeBinaryFixture(MARKET_A);
        (bYes,) = combo.prepareNativeBinaryFixture(MARKET_B);
        (cYes,) = combo.prepareNativeBinaryFixture(MARKET_C);

        collateral.mint(trader, 1_000_000e6);
        vm.prank(trader);
        collateral.approve(address(combo), type(uint256).max);
    }

    function test_PrepareComboStoresCanonicalLegsAndPositions() public {
        uint256[] memory legsMemory = _sorted(aYes, bYes, cYes);

        (bytes32 conditionId, uint256 yesPositionId, uint256 noPositionId) = combo.prepareComboCondition(legsMemory);

        NativePositionTypes.ComboConditionView memory condition = combo.getComboCondition(conditionId);
        assertTrue(condition.exists);
        assertEq(condition.legCount, 3);
        assertEq(condition.legsHash, keccak256(abi.encode(legsMemory)));
        assertEq(
            yesPositionId,
            LibNativePosition.positionIdFor(
                LibNativePosition.MODULE_COMBINATORIAL, conditionId, LibNativePosition.OUTCOME_YES
            )
        );
        assertEq(
            noPositionId,
            LibNativePosition.positionIdFor(
                LibNativePosition.MODULE_COMBINATORIAL, conditionId, LibNativePosition.OUTCOME_NO
            )
        );

        uint256[] memory storedLegs = combo.getComboLegs(conditionId);
        assertEq(storedLegs.length, legsMemory.length);
        for (uint256 index; index < storedLegs.length; ++index) {
            assertEq(storedLegs[index], legsMemory[index]);
        }
    }

    function test_SplitAndMergeComboIsCollateralNeutral() public {
        uint256[] memory legs = _sorted(aYes, bYes);
        (bytes32 conditionId, uint256 yesPositionId, uint256 noPositionId) = combo.prepareComboCondition(legs);

        uint256 balanceBefore = collateral.balanceOf(trader);

        vm.prank(trader);
        combo.splitCombo(conditionId, AMOUNT, trader, trader);

        assertEq(collateral.balanceOf(trader), balanceBefore - AMOUNT);
        assertEq(collateral.balanceOf(address(combo)), AMOUNT);
        assertEq(positions.balanceOf(trader, yesPositionId), AMOUNT);
        assertEq(positions.balanceOf(trader, noPositionId), AMOUNT);

        vm.prank(trader);
        uint128 collateralOut = combo.mergeCombo(conditionId, AMOUNT, trader);

        assertEq(collateralOut, AMOUNT);
        assertEq(collateral.balanceOf(trader), balanceBefore);
        assertEq(collateral.balanceOf(address(combo)), 0);
        assertEq(positions.balanceOf(trader, yesPositionId), 0);
        assertEq(positions.balanceOf(trader, noPositionId), 0);
    }

    function test_RevertWhen_LegsAreNotCanonical() public {
        uint256[] memory legs = _sorted(aYes, bYes);
        uint256[] memory reversed = new uint256[](2);
        reversed[0] = legs[1];
        reversed[1] = legs[0];

        vm.expectRevert();
        combo.prepareComboCondition(reversed);
    }

    function test_RevertWhen_DuplicateUnderlyingCondition() public {
        uint256[] memory legs = _sorted(aYes, aNo);

        vm.expectRevert();
        combo.prepareComboCondition(legs);
    }

    function test_RevertWhen_LegMarketNotTrading() public {
        bytes32 scheduledMarket = bytes32(uint256(0xD));
        combo.seedCLOBMarket(scheduledMarket, address(collateral), LibEveMarket.MarketState.Scheduled);
        (uint256 scheduledYes,) = combo.prepareNativeBinaryFixture(scheduledMarket);
        uint256[] memory legs = _sorted(aYes, scheduledYes);

        vm.expectRevert();
        combo.prepareComboCondition(legs);
    }

    function test_RevertWhen_LegMarketHasNotStarted() public {
        bytes32 futureMarket = bytes32(uint256(0xE));
        combo.seedCLOBMarketWithWindow(
            futureMarket,
            address(collateral),
            LibEveMarket.MarketState.Trading,
            block.timestamp + 1 days,
            block.timestamp + 2 days
        );
        (uint256 futureYes,) = combo.prepareNativeBinaryFixture(futureMarket);
        uint256[] memory legs = _sorted(aYes, futureYes);

        vm.expectRevert(abi.encodeWithSelector(Errors.ComboLegMarketNotStarted.selector, futureMarket));
        combo.prepareComboCondition(legs);
    }

    function test_RevertWhen_LegMarketExpired() public {
        bytes32 expiredMarket = bytes32(uint256(0xF));
        combo.seedCLOBMarketWithWindow(
            expiredMarket,
            address(collateral),
            LibEveMarket.MarketState.Trading,
            block.timestamp,
            block.timestamp + 1 days
        );
        (uint256 expiredYes,) = combo.prepareNativeBinaryFixture(expiredMarket);
        uint256[] memory legs = _sorted(aYes, expiredYes);
        vm.warp(block.timestamp + 1 days);

        vm.expectRevert(abi.encodeWithSelector(Errors.ComboLegMarketNotStarted.selector, expiredMarket));
        combo.prepareComboCondition(legs);
    }

    function test_RevertWhen_SplittingComboAfterEarliestLegExpiry() public {
        bytes32 shortMarket = bytes32(uint256(0x10));
        combo.seedCLOBMarketWithWindow(
            shortMarket,
            address(collateral),
            LibEveMarket.MarketState.Trading,
            block.timestamp,
            block.timestamp + 1 days
        );
        (uint256 shortYes,) = combo.prepareNativeBinaryFixture(shortMarket);
        uint256[] memory legs = _sorted(aYes, shortYes);
        (bytes32 conditionId,,) = combo.prepareComboCondition(legs);
        vm.warp(block.timestamp + 1 days);

        vm.prank(trader);
        vm.expectRevert(abi.encodeWithSelector(Errors.ComboLegMarketNotStarted.selector, shortMarket));
        combo.splitCombo(conditionId, AMOUNT, trader, trader);
    }

    function test_RevertWhen_MoreThanFiftyLegs() public {
        uint256[] memory legs = new uint256[](51);
        for (uint256 index; index < legs.length; ++index) {
            legs[index] = index + 1;
        }

        vm.expectRevert(abi.encodeWithSelector(Errors.ComboLegCountInvalid.selector, uint256(51)));
        combo.prepareComboCondition(legs);
    }

    function test_PrepareComboSupportsFiftyLegBoundary() public {
        uint256[] memory legs = new uint256[](50);
        for (uint256 index; index < legs.length; ++index) {
            bytes32 marketId = bytes32(uint256(0x1000 + index));
            combo.seedCLOBMarket(marketId, address(collateral), LibEveMarket.MarketState.Trading);
            (legs[index],) = combo.prepareNativeBinaryFixture(marketId);
        }
        _sortInPlace(legs);

        (bytes32 conditionId, uint256 yesPositionId, uint256 noPositionId) = combo.prepareComboCondition(legs);

        NativePositionTypes.ComboConditionView memory condition = combo.getComboCondition(conditionId);
        assertTrue(condition.exists);
        assertEq(condition.legCount, 50);
        assertEq(
            yesPositionId,
            LibNativePosition.positionIdFor(
                LibNativePosition.MODULE_COMBINATORIAL, conditionId, LibNativePosition.OUTCOME_YES
            )
        );
        assertEq(
            noPositionId,
            LibNativePosition.positionIdFor(
                LibNativePosition.MODULE_COMBINATORIAL, conditionId, LibNativePosition.OUTCOME_NO
            )
        );

        uint256[] memory storedLegs = combo.getComboLegs(conditionId);
        assertEq(storedLegs.length, 50);
        for (uint256 index; index < storedLegs.length; ++index) {
            assertEq(storedLegs[index], legs[index]);
        }
    }

    function test_WrapAndUnwrapSingleLegComboYes() public {
        combo.mintPosition(trader, aYes, AMOUNT);

        uint256[] memory singleLeg = new uint256[](1);
        singleLeg[0] = aYes;
        bytes32 singleConditionId = LibNativePosition.comboConditionIdFor(singleLeg);
        uint256 expectedComboYes = LibNativePosition.positionIdFor(
            LibNativePosition.MODULE_COMBINATORIAL, singleConditionId, LibNativePosition.OUTCOME_YES
        );

        vm.prank(trader);
        uint256 comboPositionId = combo.wrapCombo(aYes, AMOUNT, trader);

        assertEq(comboPositionId, expectedComboYes);
        assertEq(positions.balanceOf(trader, aYes), 0);
        assertEq(positions.balanceOf(trader, comboPositionId), AMOUNT);

        vm.prank(trader);
        uint256 underlyingOut = combo.unwrapCombo(comboPositionId, AMOUNT, trader);

        assertEq(underlyingOut, aYes);
        assertEq(positions.balanceOf(trader, comboPositionId), 0);
        assertEq(positions.balanceOf(trader, aYes), AMOUNT);
    }

    function test_UnwrapSingleLegComboNoReturnsFlippedUnderlyingLeg() public {
        uint256[] memory singleLeg = new uint256[](1);
        singleLeg[0] = aYes;
        (bytes32 singleConditionId,, uint256 comboNo) = combo.prepareComboCondition(singleLeg);
        uint256 expectedComboNo = LibNativePosition.positionIdFor(
            LibNativePosition.MODULE_COMBINATORIAL, singleConditionId, LibNativePosition.OUTCOME_NO
        );
        assertEq(comboNo, expectedComboNo);

        combo.mintPosition(trader, comboNo, AMOUNT);

        vm.prank(trader);
        uint256 underlyingOut = combo.unwrapCombo(comboNo, AMOUNT, trader);

        assertEq(underlyingOut, aNo);
        assertEq(positions.balanceOf(trader, comboNo), 0);
        assertEq(positions.balanceOf(trader, aNo), AMOUNT);
    }

    function test_RevertWhen_UnwrapMultiLegCombo() public {
        uint256[] memory legs = _sorted(aYes, bYes);
        (, uint256 comboYes,) = combo.prepareComboCondition(legs);
        combo.mintPosition(trader, comboYes, AMOUNT);

        vm.prank(trader);
        vm.expectRevert(abi.encodeWithSelector(Errors.ComboSingleLegRequired.selector, uint256(2)));
        combo.unwrapCombo(comboYes, AMOUNT, trader);
    }

    function _seedMarket(bytes32 marketId) internal {
        combo.seedCLOBMarket(marketId, address(collateral), LibEveMarket.MarketState.Trading);
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

    function _sorted(uint256 first, uint256 second, uint256 third) internal pure returns (uint256[] memory legs) {
        legs = new uint256[](3);
        legs[0] = first;
        legs[1] = second;
        legs[2] = third;
        _sortInPlace(legs);
    }

    function _sortInPlace(uint256[] memory legs) internal pure {
        for (uint256 i; i < legs.length; ++i) {
            for (uint256 j = i + 1; j < legs.length; ++j) {
                if (legs[j] < legs[i]) {
                    uint256 tmp = legs[i];
                    legs[i] = legs[j];
                    legs[j] = tmp;
                }
            }
        }
    }
}
