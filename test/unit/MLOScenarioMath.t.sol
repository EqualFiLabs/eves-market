// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "../../lib/forge-std/src/Test.sol";

import {LibMLOScenarioMath} from "../../src/libraries/LibMLOScenarioMath.sol";
import {MLOScenarioReference} from "../helpers/MLOScenarioReference.sol";

contract MLOScenarioMathHarness {
    function reservationCash(LibMLOScenarioMath.Side side, uint256 shares, uint256 price, uint256 denominator)
        external
        pure
        returns (uint256)
    {
        return LibMLOScenarioMath.reservationCash(side, shares, price, denominator);
    }

    function reservedLossVector(
        LibMLOScenarioMath.Side side,
        uint256 shares,
        uint256 price,
        uint256 denominator,
        uint256 outcomeIndex,
        uint256 outcomeCount
    ) external pure returns (int256[] memory) {
        return LibMLOScenarioMath.reservedLossVector(side, shares, price, denominator, outcomeIndex, outcomeCount);
    }

    function lossVector(
        LibMLOScenarioMath.Side side,
        uint256 shares,
        uint256 cashAmount,
        uint256 outcomeIndex,
        uint256 outcomeCount
    ) external pure returns (int256[] memory) {
        return LibMLOScenarioMath.lossVector(side, shares, cashAmount, outcomeIndex, outcomeCount);
    }

    function requiredMargin(int256[] memory losses, uint256 marginBps) external pure returns (uint256) {
        return LibMLOScenarioMath.requiredMargin(losses, marginBps);
    }

    function askSeniorRequirement(uint256 shares, uint256 price, uint256 denominator) external pure returns (uint256) {
        return LibMLOScenarioMath.askSeniorRequirement(shares, price, denominator);
    }

    function addUniformFunding(int256[] memory positionLosses, uint256 accruedUnpaidFunding)
        external
        pure
        returns (int256[] memory)
    {
        return LibMLOScenarioMath.addUniformFunding(positionLosses, accruedUnpaidFunding);
    }
}

contract MLOScenarioMathTest is Test {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant DENOMINATOR = WAD;
    uint256 internal constant MAX_VALUE = type(uint128).max;

    MLOScenarioMathHarness internal harness;

    function setUp() public {
        harness = new MLOScenarioMathHarness();
    }

    function test_BinaryAskExample() public view {
        int256[] memory actual =
            harness.reservedLossVector(LibMLOScenarioMath.Side.ASK, 100 * WAD, 40 * WAD / 100, DENOMINATOR, 0, 2);
        _assertVector(actual, _values(int256(60 * WAD), -int256(40 * WAD), int256(10 * WAD)));
        assertEq(harness.requiredMargin(actual, 10_000), 60 * WAD);
    }

    function test_BinaryBidExample() public view {
        int256[] memory actual =
            harness.reservedLossVector(LibMLOScenarioMath.Side.BID, 100 * WAD, 40 * WAD / 100, DENOMINATOR, 0, 2);
        _assertVector(actual, _values(-int256(60 * WAD), int256(40 * WAD), -int256(10 * WAD)));
        assertEq(harness.requiredMargin(actual, 10_000), 40 * WAD);
    }

    function test_FourWayAskExample() public view {
        int256[] memory actual =
            harness.reservedLossVector(LibMLOScenarioMath.Side.ASK, 100 * WAD, 20 * WAD / 100, DENOMINATOR, 0, 4);
        _assertVector(
            actual, _values(int256(80 * WAD), -int256(20 * WAD), -int256(20 * WAD), -int256(20 * WAD), int256(5 * WAD))
        );
    }

    function test_FourWayBidExample() public view {
        int256[] memory actual =
            harness.reservedLossVector(LibMLOScenarioMath.Side.BID, 100 * WAD, 20 * WAD / 100, DENOMINATOR, 0, 4);
        _assertVector(
            actual, _values(-int256(80 * WAD), int256(20 * WAD), int256(20 * WAD), int256(20 * WAD), -int256(5 * WAD))
        );
    }

    function test_PartialFillAndReservationCancellation() public view {
        int256[] memory filled = harness.lossVector(LibMLOScenarioMath.Side.ASK, 30 * WAD, 13.5e18, 0, 2);
        int256[] memory reservation =
            harness.reservedLossVector(LibMLOScenarioMath.Side.ASK, 70 * WAD, 40 * WAD / 100, DENOMINATOR, 0, 2);
        int256[] memory combined = _add(filled, reservation);

        _assertVector(combined, _values(int256(58.5e18), -int256(41.5e18), int256(8.5e18)));
        _assertVector(filled, _values(int256(16.5e18), -int256(13.5e18), int256(1.5e18)));
    }

    function testFuzz_AskReservationMatchesReference(
        uint256 outcomeCount,
        uint256 outcomeIndex,
        uint256 shares,
        uint256 price,
        uint256 denominator
    ) public view {
        outcomeCount = bound(outcomeCount, 2, 16);
        outcomeIndex = bound(outcomeIndex, 0, outcomeCount - 1);
        shares = bound(shares, 1, MAX_VALUE);
        denominator = bound(denominator, 1, MAX_VALUE);
        price = bound(price, 0, denominator);

        uint256 cash = harness.reservationCash(LibMLOScenarioMath.Side.ASK, shares, price, denominator);
        assertEq(cash, MLOScenarioReference.askReservationCash(shares, price, denominator));
        int256[] memory actual =
            harness.lossVector(LibMLOScenarioMath.Side.ASK, shares, cash, outcomeIndex, outcomeCount);
        int256[] memory expected = MLOScenarioReference.askVector(shares, cash, outcomeIndex, outcomeCount);
        _assertVector(actual, expected);
    }

    function testFuzz_BidReservationMatchesReference(
        uint256 outcomeCount,
        uint256 outcomeIndex,
        uint256 shares,
        uint256 price,
        uint256 denominator
    ) public view {
        outcomeCount = bound(outcomeCount, 2, 16);
        outcomeIndex = bound(outcomeIndex, 0, outcomeCount - 1);
        shares = bound(shares, 1, MAX_VALUE);
        denominator = bound(denominator, 1, MAX_VALUE);
        price = bound(price, 0, denominator);

        uint256 cash = harness.reservationCash(LibMLOScenarioMath.Side.BID, shares, price, denominator);
        assertEq(cash, MLOScenarioReference.bidReservationCash(shares, price, denominator));
        int256[] memory actual =
            harness.lossVector(LibMLOScenarioMath.Side.BID, shares, cash, outcomeIndex, outcomeCount);
        int256[] memory expected = MLOScenarioReference.bidVector(shares, cash, outcomeIndex, outcomeCount);
        _assertVector(actual, expected);
    }

    function testFuzz_ExecutedAskMatchesReference(
        uint256 outcomeCount,
        uint256 outcomeIndex,
        uint256 shares,
        uint256 cashAmount
    ) public view {
        outcomeCount = bound(outcomeCount, 2, 16);
        outcomeIndex = bound(outcomeIndex, 0, outcomeCount - 1);
        shares = bound(shares, 1, MAX_VALUE);
        cashAmount = bound(cashAmount, 0, shares);

        int256[] memory actual =
            harness.lossVector(LibMLOScenarioMath.Side.ASK, shares, cashAmount, outcomeIndex, outcomeCount);
        int256[] memory expected = MLOScenarioReference.askVector(shares, cashAmount, outcomeIndex, outcomeCount);
        _assertVector(actual, expected);
    }

    function testFuzz_ExecutedBidMatchesReference(
        uint256 outcomeCount,
        uint256 outcomeIndex,
        uint256 shares,
        uint256 cashAmount
    ) public view {
        outcomeCount = bound(outcomeCount, 2, 16);
        outcomeIndex = bound(outcomeIndex, 0, outcomeCount - 1);
        shares = bound(shares, 1, MAX_VALUE);
        cashAmount = bound(cashAmount, 0, shares);

        int256[] memory actual =
            harness.lossVector(LibMLOScenarioMath.Side.BID, shares, cashAmount, outcomeIndex, outcomeCount);
        int256[] memory expected = MLOScenarioReference.bidVector(shares, cashAmount, outcomeIndex, outcomeCount);
        _assertVector(actual, expected);
    }

    function testFuzz_RequiredMarginMatchesReference(
        uint256 outcomeCount,
        uint256 shares,
        uint256 price,
        uint256 denominator,
        uint256 marginBps
    ) public view {
        outcomeCount = bound(outcomeCount, 2, 16);
        shares = bound(shares, 1, MAX_VALUE);
        denominator = bound(denominator, 1, MAX_VALUE);
        price = bound(price, 0, denominator);
        marginBps = bound(marginBps, 0, 10_000);

        int256[] memory vector =
            harness.reservedLossVector(LibMLOScenarioMath.Side.ASK, shares, price, denominator, 0, outcomeCount);
        assertEq(harness.requiredMargin(vector, marginBps), MLOScenarioReference.margin(vector, marginBps));
    }

    function test_MinimumUnitRounding() public view {
        assertEq(harness.reservationCash(LibMLOScenarioMath.Side.ASK, 1, 1, 3), 1);
        assertEq(harness.reservationCash(LibMLOScenarioMath.Side.BID, 1, 1, 3), 1);
        assertEq(harness.askSeniorRequirement(1, 1, 3), 0);
    }

    function testFuzz_FragmentedAskRequirementsStayWithinWholeReservation(
        uint256 sharesSeed,
        uint256 firstFillSeed,
        uint256 minimumPriceSeed,
        uint256 firstPriceSeed,
        uint256 secondPriceSeed,
        uint256 denominatorSeed
    ) public view {
        uint256 denominator = bound(denominatorSeed, 1, type(uint64).max);
        uint256 shares = bound(sharesSeed, 2, type(uint64).max);
        uint256 firstFill = bound(firstFillSeed, 1, shares - 1);
        uint256 secondFill = shares - firstFill;
        uint256 minimumPrice = bound(minimumPriceSeed, 0, denominator);
        uint256 firstPrice = bound(firstPriceSeed, minimumPrice, denominator);
        uint256 secondPrice = bound(secondPriceSeed, minimumPrice, denominator);

        uint256 wholeRequirement = harness.askSeniorRequirement(shares, minimumPrice, denominator);
        uint256 fragmentedRequirement = harness.askSeniorRequirement(firstFill, firstPrice, denominator)
            + harness.askSeniorRequirement(secondFill, secondPrice, denominator);
        assertLe(fragmentedRequirement, wholeRequirement);
    }

    function test_InvalidResolutionRemainderDustIsLoss() public view {
        int256[] memory actual = harness.lossVector(LibMLOScenarioMath.Side.ASK, 5, 2, 0, 3);
        _assertVector(actual, _values(3, -2, -2, 1));
    }

    function test_ZeroAndFullPriceBounds() public view {
        assertEq(harness.reservationCash(LibMLOScenarioMath.Side.ASK, 7, 0, 10), 0);
        assertEq(harness.reservationCash(LibMLOScenarioMath.Side.ASK, 7, 10, 10), 7);
        assertEq(harness.reservationCash(LibMLOScenarioMath.Side.BID, 7, 0, 10), 0);
        assertEq(harness.reservationCash(LibMLOScenarioMath.Side.BID, 7, 10, 10), 7);
    }

    function test_Uint128MaximumSupportedValues() public view {
        int256[] memory ask =
            harness.reservedLossVector(LibMLOScenarioMath.Side.ASK, MAX_VALUE, MAX_VALUE, MAX_VALUE, 15, 16);
        int256[] memory bid =
            harness.reservedLossVector(LibMLOScenarioMath.Side.BID, MAX_VALUE, MAX_VALUE, MAX_VALUE, 15, 16);
        _assertVector(ask, MLOScenarioReference.askVector(MAX_VALUE, MAX_VALUE, 15, 16));
        _assertVector(bid, MLOScenarioReference.bidVector(MAX_VALUE, MAX_VALUE, 15, 16));
    }

    function test_MaximumLossMarginIsNotGrossNotionalAtFortyCents() public view {
        int256[] memory ask =
            harness.reservedLossVector(LibMLOScenarioMath.Side.ASK, 100 * WAD, 40 * WAD / 100, DENOMINATOR, 0, 2);
        int256[] memory bid =
            harness.reservedLossVector(LibMLOScenarioMath.Side.BID, 100 * WAD, 40 * WAD / 100, DENOMINATOR, 0, 2);
        assertLt(harness.requiredMargin(ask, 10_000), 100 * WAD);
        assertLt(harness.requiredMargin(bid, 10_000), 100 * WAD);
    }

    function test_MaximumLossMarginEqualsNotionalOnlyWhenMaximumLossIsNotional() public view {
        int256[] memory ask = harness.lossVector(LibMLOScenarioMath.Side.ASK, 100 * WAD, 0, 0, 2);
        int256[] memory bid = harness.lossVector(LibMLOScenarioMath.Side.BID, 100 * WAD, 100 * WAD, 0, 2);
        assertEq(harness.requiredMargin(ask, 10_000), 100 * WAD);
        assertEq(harness.requiredMargin(bid, 10_000), 100 * WAD);
    }

    function test_UniformFundingChangesMarginAcrossEveryScenario() public view {
        int256[] memory positionLosses = _values(int256(60 * WAD), -int256(40 * WAD), int256(10 * WAD));
        int256[] memory effectiveLosses = harness.addUniformFunding(positionLosses, 5 * WAD);
        int256[] memory expected = MLOScenarioReference.addUniformFunding(positionLosses, 5 * WAD);

        _assertVector(effectiveLosses, expected);
        _assertVector(effectiveLosses, _values(int256(65 * WAD), -int256(35 * WAD), int256(15 * WAD)));
        assertEq(harness.requiredMargin(effectiveLosses, 10_000), 65 * WAD);

        int256[] memory afterPayment = harness.addUniformFunding(positionLosses, 3 * WAD);
        _assertVector(afterPayment, _values(int256(63 * WAD), -int256(37 * WAD), int256(13 * WAD)));
    }

    function test_AllNegativeVectorRequiresZeroMargin() public view {
        assertEq(harness.requiredMargin(_values(-1, -2, -3), 10_000), 0);
        assertEq(harness.requiredMargin(_values(type(int256).min, -1, type(int256).min), 10_000), 0);
    }

    function test_RevertOnInvalidInputs() public {
        vm.expectRevert(abi.encodeWithSelector(LibMLOScenarioMath.InvalidOutcomeCount.selector, 1));
        harness.lossVector(LibMLOScenarioMath.Side.ASK, 1, 0, 0, 1);

        vm.expectRevert(abi.encodeWithSelector(LibMLOScenarioMath.InvalidOutcomeCount.selector, 17));
        harness.lossVector(LibMLOScenarioMath.Side.ASK, 1, 0, 0, 17);

        vm.expectRevert(abi.encodeWithSelector(LibMLOScenarioMath.InvalidOutcomeIndex.selector, 2, 2));
        harness.lossVector(LibMLOScenarioMath.Side.ASK, 1, 0, 2, 2);

        vm.expectRevert(abi.encodeWithSelector(LibMLOScenarioMath.InvalidShares.selector, 0));
        harness.lossVector(LibMLOScenarioMath.Side.ASK, 0, 0, 0, 2);

        vm.expectRevert(abi.encodeWithSelector(LibMLOScenarioMath.InvalidCash.selector, 2, 1));
        harness.lossVector(LibMLOScenarioMath.Side.ASK, 1, 2, 0, 2);

        vm.expectRevert(abi.encodeWithSelector(LibMLOScenarioMath.InvalidDenominator.selector, 0));
        harness.reservationCash(LibMLOScenarioMath.Side.ASK, 1, 0, 0);

        vm.expectRevert(abi.encodeWithSelector(LibMLOScenarioMath.InvalidPrice.selector, 11, 10));
        harness.reservationCash(LibMLOScenarioMath.Side.ASK, 1, 11, 10);

        int256[] memory losses = _values(1, 0, 0);
        vm.expectRevert(abi.encodeWithSelector(LibMLOScenarioMath.InvalidMarginBps.selector, 10_001));
        harness.requiredMargin(losses, 10_001);

        int256[] memory shortVector = new int256[](2);
        vm.expectRevert(abi.encodeWithSelector(LibMLOScenarioMath.InvalidVectorLength.selector, 2));
        harness.requiredMargin(shortVector, 10_000);

        vm.expectRevert(abi.encodeWithSelector(LibMLOScenarioMath.InvalidShares.selector, MAX_VALUE + 1));
        harness.lossVector(LibMLOScenarioMath.Side.ASK, MAX_VALUE + 1, 0, 0, 2);

        vm.expectRevert(abi.encodeWithSelector(LibMLOScenarioMath.InvalidDenominator.selector, MAX_VALUE + 1));
        harness.reservationCash(LibMLOScenarioMath.Side.ASK, 1, 0, MAX_VALUE + 1);
    }

    function test_RoundUpMargin() public view {
        int256[] memory losses = _values(1, -1, 0);
        assertEq(harness.requiredMargin(losses, 9_000), 1);
    }

    function _values(int256 a, int256 b, int256 c) internal pure returns (int256[] memory values) {
        values = new int256[](3);
        values[0] = a;
        values[1] = b;
        values[2] = c;
    }

    function _values(int256 a, int256 b, int256 c, int256 d, int256 e) internal pure returns (int256[] memory values) {
        values = new int256[](5);
        values[0] = a;
        values[1] = b;
        values[2] = c;
        values[3] = d;
        values[4] = e;
    }

    function _values(int256 a, int256 b, int256 c, int256 d) internal pure returns (int256[] memory values) {
        values = new int256[](4);
        values[0] = a;
        values[1] = b;
        values[2] = c;
        values[3] = d;
    }

    function _add(int256[] memory left, int256[] memory right) internal pure returns (int256[] memory result) {
        result = new int256[](left.length);
        for (uint256 i; i < left.length; ++i) {
            result[i] = left[i] + right[i];
        }
    }

    function _assertVector(int256[] memory actual, int256[] memory expected) internal pure {
        assertEq(actual.length, expected.length);
        for (uint256 i; i < actual.length; ++i) {
            assertEq(actual[i], expected[i]);
        }
    }
}
