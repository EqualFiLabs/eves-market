// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {StdInvariant} from "../../lib/forge-std/src/StdInvariant.sol";
import {Test} from "../../lib/forge-std/src/Test.sol";

import {MLOPredictionTypes} from "../../src/types/MLOPredictionTypes.sol";
import {MarginTypes} from "../../src/types/MarginTypes.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {LibMLOScenarioMath} from "../../src/libraries/LibMLOScenarioMath.sol";
import {LibMLOScenarioRisk} from "../../src/libraries/LibMLOScenarioRisk.sol";
import {MLOScenarioReference} from "../helpers/MLOScenarioReference.sol";

contract MLOScenarioInvariantHarness {
    uint256 internal constant DENOMINATOR = 1e18;
    uint256 internal constant SLOT_COUNT = 4;

    struct Reservation {
        uint256 shares;
        uint256 price;
        uint8 outcomeIndex;
        bool active;
    }

    bytes32 public immutable bucketId;
    bytes32 public immutable marketId;
    Reservation[SLOT_COUNT] internal reservations;
    int256[3] internal expectedFilled;

    constructor(bytes32 bucketId_, bytes32 marketId_) {
        bucketId = bucketId_;
        marketId = marketId_;
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        MarginTypes.MarginBucket storage marginBucket = state.marginBuckets[bucketId_];
        marginBucket.exists = true;
        marginBucket.operator = address(this);
        marginBucket.riskDomainId = keccak256(abi.encodePacked(marketId_));
        marginBucket.kind = MarginTypes.BucketKind.MLO;
        marginBucket.state = MarginTypes.BucketState.Healthy;
        marginBucket.marginAllocated = 1_000_000e18;
    }

    function postAsk(uint256 outcomeSeed, uint256 sharesSeed, uint256 priceSeed) external {
        (bool found, uint256 slot) = _freeSlot();
        if (!found) return;

        uint256 shares = 1 + sharesSeed % 100e18;
        uint256 price = priceSeed % (DENOMINATOR + 1);
        uint8 outcomeIndex = uint8(outcomeSeed % 2);
        LibMLOScenarioRisk.addOpenReservation(
            LibEveMarket.store(),
            bucketId,
            marketId,
            outcomeIndex,
            2,
            LibMLOScenarioMath.Side.ASK,
            shares,
            price,
            DENOMINATOR
        );
        reservations[slot] = Reservation({shares: shares, price: price, outcomeIndex: outcomeIndex, active: true});
    }

    function fillAsk(uint256 slotSeed, uint256 sharesSeed, uint256 executionPriceSeed) external {
        uint256 slot = slotSeed % SLOT_COUNT;
        Reservation storage reservation = reservations[slot];
        if (!reservation.active) return;

        uint256 shares = 1 + sharesSeed % reservation.shares;
        uint256 executionPrice = executionPriceSeed % (DENOMINATOR + 1);
        uint256 cashAmount = MLOScenarioReference.askReservationCash(shares, executionPrice, DENOMINATOR);
        uint256 oldShares = reservation.shares;
        uint256 newShares = oldShares - shares;
        LibMLOScenarioRisk.replaceReservationAndAddPosition(
            LibEveMarket.store(),
            bucketId,
            marketId,
            reservation.outcomeIndex,
            2,
            LibMLOScenarioMath.Side.ASK,
            oldShares,
            newShares,
            reservation.price,
            DENOMINATOR,
            cashAmount,
            shares
        );

        int256[] memory filled = MLOScenarioReference.askVector(shares, cashAmount, reservation.outcomeIndex, 2);
        for (uint256 index; index < 3; ++index) {
            expectedFilled[index] += filled[index];
        }
        reservation.shares = newShares;
        if (newShares == 0) reservation.active = false;
    }

    function cancelAsk(uint256 slotSeed) external {
        Reservation storage reservation = reservations[slotSeed % SLOT_COUNT];
        if (!reservation.active) return;

        LibMLOScenarioRisk.removeOpenReservation(
            LibEveMarket.store(),
            bucketId,
            marketId,
            reservation.outcomeIndex,
            2,
            LibMLOScenarioMath.Side.ASK,
            reservation.shares,
            reservation.price,
            DENOMINATOR
        );
        reservation.active = false;
        reservation.shares = 0;
    }

    function exposure() external view returns (MLOPredictionTypes.MLOScenarioExposureView memory view_) {
        return LibMLOScenarioRisk.viewExposure(LibEveMarket.store(), bucketId, 0, 10_000, 9_000);
    }

    function expectedVectors() external view returns (int256[3] memory open, int256[3] memory filled) {
        filled = expectedFilled;
        for (uint256 slot; slot < SLOT_COUNT; ++slot) {
            Reservation memory reservation = reservations[slot];
            if (!reservation.active) continue;
            uint256 cashAmount =
                MLOScenarioReference.askReservationCash(reservation.shares, reservation.price, DENOMINATOR);
            int256[] memory losses =
                MLOScenarioReference.askVector(reservation.shares, cashAmount, reservation.outcomeIndex, 2);
            for (uint256 index; index < 3; ++index) {
                if (losses[index] > 0) open[index] += losses[index];
            }
        }
    }

    function _freeSlot() private view returns (bool found, uint256 slot) {
        for (; slot < SLOT_COUNT; ++slot) {
            if (!reservations[slot].active) return (true, slot);
        }
    }
}

/// @dev Synthetic library-state coverage is intentionally paired with live MLO fill tests.
contract MLOScenarioRiskProperties is StdInvariant, Test {
    MLOScenarioInvariantHarness internal handler;

    function setUp() public {
        handler = new MLOScenarioInvariantHarness(keccak256("scenario-bucket"), keccak256("scenario-market"));
        targetContract(address(handler));
    }

    function invariant_StoredVectorsMatchBoundedReferenceSequence() public view {
        MLOPredictionTypes.MLOScenarioExposureView memory actual = handler.exposure();
        (int256[3] memory expectedOpen, int256[3] memory expectedFilled) = handler.expectedVectors();
        if (!actual.initialized) return;

        for (uint256 index; index < 3; ++index) {
            assertEq(actual.openLosses[index], expectedOpen[index]);
            assertEq(actual.filledPositionLosses[index], expectedFilled[index]);
            assertEq(actual.aggregateLosses[index], expectedOpen[index] + expectedFilled[index]);
        }
    }
}
