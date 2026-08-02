// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "../../lib/forge-std/src/Test.sol";

import {MLOPredictionTypes} from "../../src/types/MLOPredictionTypes.sol";
import {MarginTypes} from "../../src/types/MarginTypes.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {LibMLOScenarioMath} from "../../src/libraries/LibMLOScenarioMath.sol";
import {LibMLOScenarioRisk} from "../../src/libraries/LibMLOScenarioRisk.sol";
import {MLOScenarioReference} from "../helpers/MLOScenarioReference.sol";

contract MLOScenarioRiskHarness {
    error InvalidHarnessInput();

    function configureBucket(bytes32 bucketId, bytes32 marketId) external {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        MarginTypes.MarginBucket storage marginBucket = state.marginBuckets[bucketId];
        marginBucket.exists = true;
        marginBucket.operator = address(this);
        marginBucket.riskDomainId = keccak256(abi.encodePacked(marketId));
        marginBucket.kind = MarginTypes.BucketKind.MLO;
        marginBucket.state = MarginTypes.BucketState.Healthy;
        marginBucket.marginAllocated = 1_000e18;
    }

    function addOpen(
        bytes32 bucketId,
        bytes32 marketId,
        uint256 outcomeIndex,
        uint256 outcomeCount,
        uint256 side,
        uint256 shares,
        uint256 price,
        uint256 denominator
    ) external {
        _validateInputs(outcomeIndex, outcomeCount, side);
        LibMLOScenarioRisk.addOpenReservation(
            LibEveMarket.store(),
            bucketId,
            marketId,
            uint8(outcomeIndex),
            uint8(outcomeCount),
            LibMLOScenarioMath.Side(side),
            shares,
            price,
            denominator
        );
    }

    function removeOpen(
        bytes32 bucketId,
        bytes32 marketId,
        uint256 outcomeIndex,
        uint256 outcomeCount,
        uint256 side,
        uint256 shares,
        uint256 price,
        uint256 denominator
    ) external {
        _validateInputs(outcomeIndex, outcomeCount, side);
        LibMLOScenarioRisk.removeOpenReservation(
            LibEveMarket.store(),
            bucketId,
            marketId,
            uint8(outcomeIndex),
            uint8(outcomeCount),
            LibMLOScenarioMath.Side(side),
            shares,
            price,
            denominator
        );
    }

    function fillReservation(
        bytes32 bucketId,
        bytes32 marketId,
        uint256 outcomeIndex,
        uint256 outcomeCount,
        uint256 side,
        uint256 oldShares,
        uint256 newShares,
        uint256 boundPrice,
        uint256 denominator,
        uint256 shares,
        uint256 cashAmount
    ) external {
        _validateInputs(outcomeIndex, outcomeCount, side);
        LibMLOScenarioRisk.replaceReservationAndAddPosition(
            LibEveMarket.store(),
            bucketId,
            marketId,
            uint8(outcomeIndex),
            uint8(outcomeCount),
            LibMLOScenarioMath.Side(side),
            oldShares,
            newShares,
            boundPrice,
            denominator,
            cashAmount,
            shares
        );
    }

    function setFunding(bytes32 bucketId, uint256 funding) external {
        LibEveMarket.store().marginBuckets[bucketId].fundingLiability = funding;
    }

    function configureMultiOutcomeBook(bytes32 bookId, bytes32 marketId, uint256 outcomeIndex, uint256 outcomeCount)
        external
    {
        _validateInputs(outcomeIndex, outcomeCount, 0);
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        state.multiOutcomeMarkets[marketId].exists = true;
        state.multiOutcomeMarkets[marketId].marketId = marketId;
        state.multiOutcomeMarkets[marketId].outcomeCount = uint8(outcomeCount);
        state.books[bookId].marketId = marketId;
        state.books[bookId].baseTokenId = outcomeIndex + 1;
        state.multiOutcomeBookIds[marketId][uint8(outcomeIndex)] = bookId;
        state.multiOutcomePositionIds[marketId][uint8(outcomeIndex)] = outcomeIndex + 1;
    }

    function context(bytes32 bookId) external view returns (bytes32 marketId, uint8 outcomeIndex, uint8 outcomeCount) {
        return LibMLOScenarioRisk.contextForBook(LibEveMarket.store(), bookId);
    }

    function exposure(bytes32 bucketId)
        external
        view
        returns (MLOPredictionTypes.MLOScenarioExposureView memory view_)
    {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        return
            LibMLOScenarioRisk.viewExposure(
                state, bucketId, state.marginBuckets[bucketId].fundingLiability, 10_000, 9_000
            );
    }

    function bucket(bytes32 bucketId) external view returns (MarginTypes.MarginBucket memory bucket_) {
        return LibEveMarket.store().marginBuckets[bucketId];
    }

    function _validateInputs(uint256 outcomeIndex, uint256 outcomeCount, uint256 side) private pure {
        if (side > 1) revert InvalidHarnessInput();
        LibMLOScenarioMath.validateOutcomeIndex(outcomeIndex, outcomeCount);
    }
}

contract MLOScenarioRiskTest is Test {
    uint256 internal constant DENOMINATOR = 1e18;
    bytes32 internal constant MARKET = keccak256("market-a");
    bytes32 internal constant OTHER_MARKET = keccak256("market-b");
    bytes32 internal constant BUCKET = keccak256("bucket-a");
    bytes32 internal constant OTHER_BUCKET = keccak256("bucket-b");

    MLOScenarioRiskHarness internal harness;

    function setUp() public {
        harness = new MLOScenarioRiskHarness();
        harness.configureBucket(BUCKET, MARKET);
        harness.configureBucket(OTHER_BUCKET, OTHER_MARKET);
    }

    function test_OpenProfitsAreClippedBeforeAggregation() public {
        harness.addOpen(BUCKET, MARKET, 0, 2, 0, 100e18, 0.4e18, DENOMINATOR);
        harness.addOpen(BUCKET, MARKET, 1, 2, 0, 100e18, 0.4e18, DENOMINATOR);

        MLOPredictionTypes.MLOScenarioExposureView memory view_ = harness.exposure(BUCKET);
        assertEq(view_.openLosses[0], 60e18);
        assertEq(view_.openLosses[1], 60e18);
        assertEq(view_.openLosses[2], 20e18);
        assertEq(harness.bucket(BUCKET).openOrderRisk, 60e18);
    }

    function test_FilledComplementaryOutcomesNetSignedLosses() public {
        harness.addOpen(BUCKET, MARKET, 0, 2, 0, 100e18, 0.4e18, DENOMINATOR);
        harness.addOpen(BUCKET, MARKET, 1, 2, 0, 100e18, 0.4e18, DENOMINATOR);
        harness.fillReservation(BUCKET, MARKET, 0, 2, 0, 100e18, 0, 0.4e18, DENOMINATOR, 100e18, 40e18);
        harness.fillReservation(BUCKET, MARKET, 1, 2, 0, 100e18, 0, 0.4e18, DENOMINATOR, 100e18, 40e18);

        MLOPredictionTypes.MLOScenarioExposureView memory view_ = harness.exposure(BUCKET);
        assertEq(view_.filledPositionLosses[0], 20e18);
        assertEq(view_.filledPositionLosses[1], 20e18);
        assertEq(view_.filledPositionLosses[2], 20e18);
        assertEq(harness.bucket(BUCKET).positionRisk, 20e18);
    }

    function test_RemovingRemainingReservationLeavesFilledLoss() public {
        harness.addOpen(BUCKET, MARKET, 0, 2, 0, 100e18, 0.4e18, DENOMINATOR);
        harness.fillReservation(BUCKET, MARKET, 0, 2, 0, 100e18, 70e18, 0.4e18, DENOMINATOR, 30e18, 12e18);
        harness.removeOpen(BUCKET, MARKET, 0, 2, 0, 70e18, 0.4e18, DENOMINATOR);

        MLOPredictionTypes.MLOScenarioExposureView memory view_ = harness.exposure(BUCKET);
        assertEq(view_.openLosses[0], 0);
        assertEq(view_.openLosses[1], 0);
        assertEq(view_.openLosses[2], 0);
        assertEq(view_.filledPositionLosses[0], 18e18);
        assertEq(view_.maximumRawLoss, 18e18);
    }

    function test_IndependentMarketBucketsRemainSeparateAndFundingIsUniform() public {
        harness.addOpen(BUCKET, MARKET, 0, 2, 0, 100e18, 0.4e18, DENOMINATOR);
        harness.addOpen(OTHER_BUCKET, OTHER_MARKET, 0, 2, 0, 100e18, 0.4e18, DENOMINATOR);
        harness.fillReservation(BUCKET, MARKET, 0, 2, 0, 100e18, 0, 0.4e18, DENOMINATOR, 100e18, 40e18);
        harness.fillReservation(OTHER_BUCKET, OTHER_MARKET, 0, 2, 0, 100e18, 0, 0.4e18, DENOMINATOR, 100e18, 40e18);
        harness.setFunding(BUCKET, 5e18);

        MLOPredictionTypes.MLOScenarioExposureView memory view_ = harness.exposure(BUCKET);
        assertEq(view_.effectiveLosses[0], 65e18);
        assertEq(view_.effectiveLosses[1], -35e18);
        assertEq(view_.effectiveLosses[2], 15e18);
        assertEq(view_.initialRequirement, 65e18);
        assertEq(view_.maintenanceRequirement, 58.5e18);
        assertTrue(BUCKET != OTHER_BUCKET);
    }

    function test_RevertWhen_FundingCannotBeRepresentedAsSignedLoss() public {
        harness.addOpen(BUCKET, MARKET, 0, 2, 0, 1, 0, DENOMINATOR);
        harness.setFunding(BUCKET, uint256(type(int256).max) + 1);

        vm.expectRevert(
            abi.encodeWithSelector(LibMLOScenarioRisk.ScenarioFundingOverflow.selector, uint256(type(int256).max) + 1)
        );
        harness.exposure(BUCKET);
    }

    function test_MultiOutcomeBookMapsToBoundedScenarioContext() public {
        bytes32 bookId = keccak256("four-way-outcome-three");
        harness.configureMultiOutcomeBook(bookId, MARKET, 3, 4);

        (bytes32 actualMarket, uint8 outcomeIndex, uint8 outcomeCount) = harness.context(bookId);
        assertEq(actualMarket, MARKET);
        assertEq(outcomeIndex, 3);
        assertEq(outcomeCount, 4);
    }

    function testFuzz_FilledAskMatchesIndependentReference(
        uint256 outcomeCount,
        uint256 outcomeIndex,
        uint256 shares,
        uint256 price
    ) public {
        outcomeCount = bound(outcomeCount, 2, 16);
        outcomeIndex = bound(outcomeIndex, 0, outcomeCount - 1);
        shares = bound(shares, 1, 1e24);
        price = bound(price, 0, DENOMINATOR);
        uint256 cashAmount = shares * price / DENOMINATOR;

        harness.addOpen(BUCKET, MARKET, outcomeIndex, outcomeCount, 0, shares, price, DENOMINATOR);
        harness.fillReservation(
            BUCKET, MARKET, outcomeIndex, outcomeCount, 0, shares, 0, price, DENOMINATOR, shares, cashAmount
        );

        int256[] memory expected = MLOScenarioReference.askVector(shares, cashAmount, outcomeIndex, outcomeCount);
        MLOPredictionTypes.MLOScenarioExposureView memory view_ = harness.exposure(BUCKET);
        for (uint256 index; index <= outcomeCount; ++index) {
            assertEq(view_.openLosses[index], 0);
            assertEq(view_.filledPositionLosses[index], expected[index]);
        }
        assertEq(view_.initialRequirement, MLOScenarioReference.margin(expected, 10_000));
    }
}
