// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IMarketFactoryFacet} from "../../src/interfaces/IMarketFactoryFacet.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {LibCurvePacking} from "../../src/libraries/LibCurvePacking.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";

import {MarketFactoryFixture, StateProbeFacet} from "../helpers/DiamondFixtures.sol";

contract MarketCreationPropertiesTest is MarketFactoryFixture {
    // Feature: eve-prediction-market, Property 3: market creation produces valid state
    function testFuzz_MarketCreationProducesValidState(bytes32 questionSeed, bytes32 categorySeed, uint64 durationSeed)
        public
    {
        string memory question = string.concat("Q-", vm.toString(uint256(questionSeed)));
        string memory category = string.concat("C-", vm.toString(uint256(categorySeed)));
        uint64 minDuration = StateProbeFacet(address(diamond)).minMarketDuration();
        uint64 maxDuration = StateProbeFacet(address(diamond)).maxMarketDuration();
        uint64 duration = uint64(bound(uint256(durationSeed), minDuration, maxDuration));
        uint64 expiryTime = uint64(block.timestamp) + duration;
        uint128 creationFee = StateProbeFacet(address(diamond)).marketCreationFee();
        uint128 creationBond = StateProbeFacet(address(diamond)).marketCreationBond();

        _approveCreator(creationFee);

        ExpectedMarketData memory expected = _expectedMarketData(question, category, expiryTime);

        vm.prank(creator);
        bytes32 marketId = IMarketFactoryFacet(address(diamond)).createMarket(question, category, DEFAULT_RESOLUTION_SOURCE, uint64(block.timestamp), expiryTime, 0, true);

        _assertValidCreatedMarket(marketId, expected, expiryTime, creationFee, creationBond);
    }

    // Feature: eve-prediction-market, Property 4: market creation duration bounds
    function testFuzz_MarketCreationDurationBounds(uint64 tooSoonSeed, uint64 tooLateSeed) public {
        string memory question = "duration-bounds";
        string memory category = "general";
        uint64 nowTimestamp = uint64(block.timestamp);
        uint64 minDuration = StateProbeFacet(address(diamond)).minMarketDuration();
        uint64 maxDuration = StateProbeFacet(address(diamond)).maxMarketDuration();
        uint128 creationFee = StateProbeFacet(address(diamond)).marketCreationFee();

        _approveCreator(uint256(creationFee) * 2);

        uint64 tooSoonExpiry = nowTimestamp + uint64(bound(uint256(tooSoonSeed), 1, minDuration - 1));
        vm.prank(creator);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.ExpiryTooSoon.selector, tooSoonExpiry, nowTimestamp + minDuration)
        );
        IMarketFactoryFacet(address(diamond)).createMarket(question, category, DEFAULT_RESOLUTION_SOURCE, uint64(block.timestamp), tooSoonExpiry, 0, true);

        uint64 tooLateExpiry = nowTimestamp + maxDuration + uint64(bound(uint256(tooLateSeed), 1, 30 days));
        vm.prank(creator);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.ExpiryTooLate.selector, tooLateExpiry, nowTimestamp + maxDuration)
        );
        IMarketFactoryFacet(address(diamond)).createMarket(question, category, DEFAULT_RESOLUTION_SOURCE, uint64(block.timestamp), tooLateExpiry, 0, true);
    }

    // Feature: eve-prediction-market, Property 5: market creation fee enforcement
    function testFuzz_MarketCreationFeeEnforcement(uint128 approvalSeed) public {
        string memory question = "fee-enforcement";
        string memory category = "general";
        uint64 expiryTime = uint64(block.timestamp + 4 days);
        uint128 creationFee = StateProbeFacet(address(diamond)).marketCreationFee();
        uint256 insufficientApproval = bound(uint256(approvalSeed), 0, creationFee - 1);

        _approveCreator(insufficientApproval);

        vm.prank(creator);
        vm.expectRevert(Errors.InsufficientCreationFeeOrReserve.selector);
        IMarketFactoryFacet(address(diamond)).createMarket(question, category, DEFAULT_RESOLUTION_SOURCE, uint64(block.timestamp), expiryTime, 0, true);
    }

    // Feature: eve-prediction-market, Property 5: creation bond enforcement
    function testFuzz_MarketCreationBondEnforcement(uint128 approvalSeed) public {
        string memory question = "bond-enforcement";
        string memory category = "general";
        uint64 expiryTime = uint64(block.timestamp + 4 days);
        uint128 creationFee = StateProbeFacet(address(diamond)).marketCreationFee();
        uint128 creationBond = StateProbeFacet(address(diamond)).marketCreationBond();
        uint256 insufficientApproval = bound(uint256(approvalSeed), 0, creationBond - 1);

        _approveCreatorWithEve(creationFee, insufficientApproval);

        vm.prank(creator);
        vm.expectRevert(Errors.InsufficientCreationBond.selector);
        IMarketFactoryFacet(address(diamond)).createMarket(question, category, DEFAULT_RESOLUTION_SOURCE, uint64(block.timestamp), expiryTime, 0, true);
    }

    // Feature: eve-prediction-market, Property 5: bootstrap liquidity funding enforcement
    function testFuzz_InitialLiquidityFundingEnforcement(uint128 shortfallSeed) public {
        string memory question = "bootstrap-enforcement";
        string memory category = "general";
        uint64 expiryTime = uint64(block.timestamp + 4 days);
        uint128 creationFee = StateProbeFacet(address(diamond)).marketCreationFee();
        uint128 initialVolume = 100;
        uint256 requiredApproval = uint256(creationFee) + uint256(initialVolume);
        uint256 shortfall = bound(uint256(shortfallSeed), 1, uint256(initialVolume));

        _approveCreator(requiredApproval - shortfall);

        vm.prank(creator);
        vm.expectRevert(Errors.InsufficientInitialLiquidityCollateral.selector);
        IMarketFactoryFacet(address(diamond)).createMarket(question, category, DEFAULT_RESOLUTION_SOURCE, uint64(block.timestamp), expiryTime, initialVolume, true);
    }

    // Feature: eve-prediction-market, Property 6: initial curve at 50/50
    function testFuzz_InitialCurveStartsAtFiftyFifty(uint128 rawInitialVolume, bool initialDirection) public {
        string memory question = "bootstrap-curve";
        string memory category = "general";
        uint64 expiryTime = uint64(block.timestamp + 9 days);
        uint128 initialVolume = uint128(bound(uint256(rawInitialVolume), 1, 1_000_000));
        uint128 creationFee = StateProbeFacet(address(diamond)).marketCreationFee();

        _approveCreator(uint256(creationFee) + uint256(initialVolume));

        vm.prank(creator);
        bytes32 marketId = IMarketFactoryFacet(address(diamond))
            .createMarket(question, category, DEFAULT_RESOLUTION_SOURCE, uint64(block.timestamp), expiryTime, initialVolume, initialDirection);

        _assertSeededCurveState(marketId, initialVolume, initialDirection);
        _assertBootstrapInventory(marketId, initialVolume, initialDirection);
    }

    function _assertSeededCurveState(bytes32 marketId, uint128 initialVolume, bool initialDirection) internal view {
        (, uint128 remainingVolume,, uint32 generation, bool active, bool isYesSide,, bytes32 curveMarketId) =
            StateProbeFacet(address(diamond)).getStoredCurve(0);
        (uint256 packed,,,,,,,) = StateProbeFacet(address(diamond)).getStoredCurve(0);
        LibCurvePacking.CurveParams memory params = LibCurvePacking.unpack(packed);

        assertEq(curveMarketId, marketId);
        assertEq(remainingVolume, initialVolume);
        assertEq(generation, 1);
        assertTrue(active);
        assertEq(isYesSide, initialDirection);
        assertEq(params.startPrice, 500_000_000);
        assertEq(params.endPrice, 500_000_000);
        assertEq(params.profileId, 0);
        assertEq(conditionalTokens.collateralBalance(IERC20(address(collateralToken))), initialVolume);
    }

    function _assertBootstrapInventory(bytes32 marketId, uint128 initialVolume, bool initialDirection) internal view {
        (bytes32 conditionId,, uint256 yesPositionId, uint256 noPositionId) =
            IMarketFactoryFacet(address(diamond)).getMarketPositions(marketId);

        if (initialDirection) {
            assertEq(conditionalTokens.balanceOf(address(diamond), yesPositionId), initialVolume);
            assertEq(conditionalTokens.balanceOf(creator, noPositionId), initialVolume);
        } else {
            assertEq(conditionalTokens.balanceOf(address(diamond), noPositionId), initialVolume);
            assertEq(conditionalTokens.balanceOf(creator, yesPositionId), initialVolume);
        }

        assertTrue(conditionId != bytes32(0));
    }

    function _assertValidCreatedMarket(
        bytes32 marketId,
        ExpectedMarketData memory expected,
        uint64 expiryTime,
        uint128 creationFee,
        uint128 creationBond
    ) internal view {
        (bytes32 conditionId, address collateralToken_, uint256 yesPositionId, uint256 noPositionId) =
            IMarketFactoryFacet(address(diamond)).getMarketPositions(marketId);

        assertEq(marketId, expected.marketId);
        assertEq(conditionId, expected.conditionId);
        assertEq(collateralToken_, address(collateralToken));
        assertEq(yesPositionId, expected.yesPositionId);
        assertEq(noPositionId, expected.noPositionId);
        (uint8 storedMarketType, address storedPositionToken) =
            StateProbeFacet(address(diamond)).getStoredMarketTypeAndPositionToken(marketId);
        assertEq(storedMarketType, uint8(LibEveMarket.MarketType.CLOB));
        assertEq(storedPositionToken, address(conditionalTokens));
        assertEq(collateralToken.balanceOf(treasury), creationFee);
        _assertStoredCreationState(marketId, expected.marketId, expiryTime, creationFee);
        _assertCreationBond(marketId, creationBond);
    }

    function _assertStoredCreationState(
        bytes32 marketId,
        bytes32 expectedMarketId,
        uint64 expiryTime,
        uint128 creationFee
    ) internal view {
        (
            bytes32 storedMarketId,,
            uint64 storedExpiryTime,,
            uint128 creationFeePaid,
            uint8 outcome,
            uint8 state,
            uint256 curveCount
        ) = StateProbeFacet(address(diamond)).getStoredMarketStatus(marketId);

        assertEq(storedMarketId, expectedMarketId);
        assertEq(storedExpiryTime, expiryTime);
        assertEq(creationFeePaid, creationFee);
        assertEq(outcome, 0);
        assertEq(state, uint8(LibEveMarket.MarketState.Trading));
        assertEq(curveCount, 0);
    }

    function _assertCreationBond(bytes32 marketId, uint128 creationBond) internal view {
        (uint128 storedCreationBondEve, bool creationBondReleased) =
            StateProbeFacet(address(diamond)).getStoredCreationBond(marketId);

        assertEq(storedCreationBondEve, creationBond);
        assertFalse(creationBondReleased);
    }
}
