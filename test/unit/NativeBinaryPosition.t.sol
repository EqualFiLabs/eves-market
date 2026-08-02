// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "../../lib/forge-std/src/Test.sol";

import {INativeBinaryPositionFacet} from "../../src/interfaces/INativeBinaryPositionFacet.sol";
import {NativeBinaryPositionFacet} from "../../src/facets/native/NativeBinaryPositionFacet.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {LibNativePosition} from "../../src/libraries/LibNativePosition.sol";
import {EvesPositionManager} from "../../src/tokens/EvesPositionManager.sol";

import {MockUSDC} from "../helpers/MockUSDC.sol";

contract NativeBinaryHarness is NativeBinaryPositionFacet {
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

    function resolveFixture(bytes32 marketId, LibEveMarket.MarketOutcome outcome) external {
        LibEveMarket.Market storage market = LibEveMarket.store().markets[marketId];
        if (market.marketId != marketId) {
            revert Errors.MarketNotFound(marketId);
        }
        market.state = LibEveMarket.MarketState.Resolved;
        market.outcome = outcome;
        market.resolutionTime = uint64(block.timestamp);
    }
}

contract NativeBinaryPositionTest is Test {
    NativeBinaryHarness internal nativeBinary;
    EvesPositionManager internal positions;
    MockUSDC internal collateral;

    address internal trader = makeAddr("trader");
    address internal receiver = makeAddr("receiver");

    bytes32 internal constant MARKET_ID = bytes32(uint256(0xA11CE));
    uint128 internal constant AMOUNT = 100e6;

    function setUp() public {
        nativeBinary = new NativeBinaryHarness();
        positions = new EvesPositionManager(address(nativeBinary), "");
        collateral = new MockUSDC();

        nativeBinary.configure(address(collateral), address(positions));
        nativeBinary.seedCLOBMarket(MARKET_ID, address(collateral), LibEveMarket.MarketState.Trading);

        collateral.mint(trader, 1_000_000e6);
        vm.prank(trader);
        collateral.approve(address(nativeBinary), type(uint256).max);
    }

    function test_PrepareStoresDeterministicNativeBinaryPositions() public {
        INativeBinaryPositionFacet.BinaryPositionIds memory ids = nativeBinary.prepareNativeBinaryCondition(MARKET_ID);

        bytes32 expectedConditionId = LibNativePosition.binaryConditionIdFor(MARKET_ID);
        assertEq(ids.marketId, MARKET_ID);
        assertEq(ids.conditionId, expectedConditionId);
        assertEq(
            ids.yesPositionId,
            LibNativePosition.positionIdFor(
                LibNativePosition.MODULE_BINARY, expectedConditionId, LibNativePosition.OUTCOME_YES
            )
        );
        assertEq(
            ids.noPositionId,
            LibNativePosition.positionIdFor(
                LibNativePosition.MODULE_BINARY, expectedConditionId, LibNativePosition.OUTCOME_NO
            )
        );

        INativeBinaryPositionFacet.BinaryPositionIds memory stored = nativeBinary.getNativeBinaryCondition(MARKET_ID);
        assertEq(stored.yesPositionId, ids.yesPositionId);
        assertEq(stored.noPositionId, ids.noPositionId);
    }

    function test_SplitAndMergeNativeBinaryIsCollateralNeutral() public {
        uint256 balanceBefore = collateral.balanceOf(trader);

        vm.prank(trader);
        (uint256 yesPositionId, uint256 noPositionId) = nativeBinary.splitNativeBinary(MARKET_ID, AMOUNT, trader);

        assertEq(collateral.balanceOf(trader), balanceBefore - AMOUNT);
        assertEq(collateral.balanceOf(address(nativeBinary)), AMOUNT);
        assertEq(positions.balanceOf(trader, yesPositionId), AMOUNT);
        assertEq(positions.balanceOf(trader, noPositionId), AMOUNT);

        vm.prank(trader);
        uint128 collateralOut = nativeBinary.mergeNativeBinary(MARKET_ID, AMOUNT, trader);

        assertEq(collateralOut, AMOUNT);
        assertEq(collateral.balanceOf(trader), balanceBefore);
        assertEq(collateral.balanceOf(address(nativeBinary)), 0);
        assertEq(positions.balanceOf(trader, yesPositionId), 0);
        assertEq(positions.balanceOf(trader, noPositionId), 0);
    }

    function test_RedeemYesWinnerPaysYesAndBurnsNoForZero() public {
        vm.prank(trader);
        (uint256 yesPositionId, uint256 noPositionId) = nativeBinary.splitNativeBinary(MARKET_ID, AMOUNT, trader);
        nativeBinary.resolveFixture(MARKET_ID, LibEveMarket.MarketOutcome.Yes);

        uint256 balanceBefore = collateral.balanceOf(trader);

        vm.prank(trader);
        uint128 noOut = nativeBinary.redeemNativeBinary(MARKET_ID, LibNativePosition.OUTCOME_NO, AMOUNT, trader);
        assertEq(noOut, 0);
        assertEq(positions.balanceOf(trader, noPositionId), 0);
        assertEq(collateral.balanceOf(trader), balanceBefore);

        vm.prank(trader);
        uint128 yesOut = nativeBinary.redeemNativeBinary(MARKET_ID, LibNativePosition.OUTCOME_YES, AMOUNT, trader);
        assertEq(yesOut, AMOUNT);
        assertEq(positions.balanceOf(trader, yesPositionId), 0);
        assertEq(collateral.balanceOf(trader), balanceBefore + AMOUNT);
    }

    function test_RedeemNoWinnerPaysNo() public {
        vm.prank(trader);
        nativeBinary.splitNativeBinary(MARKET_ID, AMOUNT, trader);
        nativeBinary.resolveFixture(MARKET_ID, LibEveMarket.MarketOutcome.No);

        uint256 balanceBefore = collateral.balanceOf(trader);

        vm.prank(trader);
        uint128 noOut = nativeBinary.redeemNativeBinary(MARKET_ID, LibNativePosition.OUTCOME_NO, AMOUNT, trader);

        assertEq(noOut, AMOUNT);
        assertEq(collateral.balanceOf(trader), balanceBefore + AMOUNT);
    }

    function test_InvalidPaysHalfToEachSide() public {
        vm.prank(trader);
        nativeBinary.splitNativeBinary(MARKET_ID, AMOUNT, trader);
        nativeBinary.resolveFixture(MARKET_ID, LibEveMarket.MarketOutcome.Invalid);

        uint256 balanceBefore = collateral.balanceOf(trader);

        vm.prank(trader);
        uint128 yesOut = nativeBinary.redeemNativeBinary(MARKET_ID, LibNativePosition.OUTCOME_YES, AMOUNT, trader);
        vm.prank(trader);
        uint128 noOut = nativeBinary.redeemNativeBinary(MARKET_ID, LibNativePosition.OUTCOME_NO, AMOUNT, trader);

        assertEq(yesOut, AMOUNT / 2);
        assertEq(noOut, AMOUNT / 2);
        assertEq(collateral.balanceOf(trader), balanceBefore + AMOUNT);
    }

    function test_GetNativeBinaryPayoutReportsResolvedNumerator() public {
        INativeBinaryPositionFacet.BinaryPositionIds memory ids = nativeBinary.prepareNativeBinaryCondition(MARKET_ID);

        (bool unresolved, uint256 unresolvedNumerator) =
            nativeBinary.getNativeBinaryPayout(ids.conditionId, LibNativePosition.OUTCOME_YES);
        assertFalse(unresolved);
        assertEq(unresolvedNumerator, 0);

        nativeBinary.resolveFixture(MARKET_ID, LibEveMarket.MarketOutcome.Yes);
        (bool resolved, uint256 yesNumerator) =
            nativeBinary.getNativeBinaryPayout(ids.conditionId, LibNativePosition.OUTCOME_YES);
        (, uint256 noNumerator) = nativeBinary.getNativeBinaryPayout(ids.conditionId, LibNativePosition.OUTCOME_NO);

        assertTrue(resolved);
        assertEq(yesNumerator, LibNativePosition.RESULT_DENOMINATOR);
        assertEq(noNumerator, 0);
    }

    function test_RevertWhen_RedeemBeforeResolution() public {
        vm.prank(trader);
        nativeBinary.splitNativeBinary(MARKET_ID, AMOUNT, trader);

        vm.prank(trader);
        vm.expectRevert(abi.encodeWithSelector(Errors.MarketNotResolved.selector, MARKET_ID));
        nativeBinary.redeemNativeBinary(MARKET_ID, LibNativePosition.OUTCOME_YES, AMOUNT, trader);
    }

    function test_RevertWhen_SplitNonTradingMarket() public {
        bytes32 scheduledMarketId = bytes32(uint256(0xB0B));
        nativeBinary.seedCLOBMarketWithWindow(
            scheduledMarketId,
            address(collateral),
            LibEveMarket.MarketState.Scheduled,
            block.timestamp + 1 days,
            block.timestamp + 2 days
        );

        vm.prank(trader);
        vm.expectRevert(abi.encodeWithSelector(Errors.MarketNotTrading.selector, scheduledMarketId));
        nativeBinary.splitNativeBinary(scheduledMarketId, AMOUNT, trader);
    }

    function test_RevertWhen_SplitBeforeTradingWindow() public {
        bytes32 futureMarketId = bytes32(uint256(0xF00));
        nativeBinary.seedCLOBMarketWithWindow(
            futureMarketId,
            address(collateral),
            LibEveMarket.MarketState.Trading,
            block.timestamp + 1 days,
            block.timestamp + 2 days
        );

        vm.prank(trader);
        vm.expectRevert(abi.encodeWithSelector(Errors.MarketNotTrading.selector, futureMarketId));
        nativeBinary.splitNativeBinary(futureMarketId, AMOUNT, trader);
    }

    function test_SplitAfterExpiryBeforeResolution() public {
        bytes32 expiredMarketId = bytes32(uint256(0xF01));
        nativeBinary.seedCLOBMarketWithWindow(
            expiredMarketId,
            address(collateral),
            LibEveMarket.MarketState.Trading,
            block.timestamp,
            block.timestamp + 1 days
        );
        vm.warp(block.timestamp + 1 days);

        vm.prank(trader);
        (uint256 yesPositionId, uint256 noPositionId) = nativeBinary.splitNativeBinary(expiredMarketId, AMOUNT, trader);

        assertEq(positions.balanceOf(trader, yesPositionId), AMOUNT);
        assertEq(positions.balanceOf(trader, noPositionId), AMOUNT);
    }

    function test_RevertWhen_SplitAfterResolution() public {
        nativeBinary.resolveFixture(MARKET_ID, LibEveMarket.MarketOutcome.Yes);

        vm.prank(trader);
        vm.expectRevert(abi.encodeWithSelector(Errors.MarketNotTrading.selector, MARKET_ID));
        nativeBinary.splitNativeBinary(MARKET_ID, AMOUNT, trader);
    }

    function test_RevertWhen_UnsupportedOutcome() public {
        nativeBinary.prepareNativeBinaryCondition(MARKET_ID);
        nativeBinary.resolveFixture(MARKET_ID, LibEveMarket.MarketOutcome.Yes);

        vm.prank(trader);
        vm.expectRevert(abi.encodeWithSelector(Errors.NativeOutcomeUnsupported.selector, uint8(2)));
        nativeBinary.redeemNativeBinary(MARKET_ID, 2, AMOUNT, trader);
    }
}
