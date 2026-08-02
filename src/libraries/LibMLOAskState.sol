// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IMLOPredictionAdapterFacet} from "../interfaces/IMLOPredictionAdapterFacet.sol";
import {MLOPredictionTypes} from "../types/MLOPredictionTypes.sol";
import {QuoteEnvelopeTypes} from "../types/QuoteEnvelopeTypes.sol";
import {LibBookAccounting} from "./LibBookAccounting.sol";
import {LibEveMarket} from "./LibEveMarket.sol";
import {LibMarkOracle} from "./LibMarkOracle.sol";
import {LibMarginAccount} from "./LibMarginAccount.sol";
import {LibCurveIndex} from "./LibCurveIndex.sol";
import {LibMLOInventory} from "./LibMLOInventory.sol";
import {LibMLOScenarioMath} from "./LibMLOScenarioMath.sol";
import {LibMLOScenarioRisk} from "./LibMLOScenarioRisk.sol";
import {LibRiskEngine} from "./LibRiskEngine.sol";

library LibMLOAskState {
    function applyFill(
        LibEveMarket.EveMarketStorage storage state,
        MLOPredictionTypes.MLOAskFillStateParams calldata params
    ) internal {
        LibEveMarket.StoredCurve storage curve = state.curves[params.curveId];
        uint256 envelopeId = state.mloCurveEnvelopeIds[params.curveId];
        QuoteEnvelopeTypes.StoredQuoteEnvelope storage envelope = state.quoteEnvelopes[envelopeId];
        bytes32 bucketId = state.adapterCurveMetadata[params.curveId].bucketId;
        bytes32 bookId = curve.bookId;
        LibEveMarket.Book storage book = state.books[bookId];
        bytes32 marketId = book.marketId;

        LibCurveIndex.decreaseAskRemaining(state, params.curveId, params.sharesOut);
        envelope.currentVolume -= params.sharesOut;
        if (params.backing.inventoryUsed != 0) {
            LibMLOInventory.consumeCurveInventory(
                state, params.curveId, bucketId, marketId, envelope.outcomeIndex, params.backing.inventoryUsed
            );
        }
        uint256 seniorConsumed = uint256(params.backing.seniorDeployed) + params.backing.seniorReleased;
        if (seniorConsumed != 0) {
            state.mloCurveSeniorReserved[params.curveId] -= seniorConsumed;
            state.mloBucketMarketSeniorReserved[bucketId][marketId] -= seniorConsumed;
        }

        uint256 oldRiskVolume = envelope.remainingRiskVolume;
        uint256 newRiskVolume = oldRiskVolume - params.sharesOut;
        uint256 boundPrice = envelope.side == uint8(LibEveMarket.CurveSide.ASK) ? envelope.minPrice : envelope.maxPrice;
        LibMLOScenarioRisk.replaceOpenReservation(
            state,
            bucketId,
            marketId,
            envelope.outcomeIndex,
            envelope.outcomeCount,
            LibMLOScenarioMath.Side(envelope.side),
            oldRiskVolume,
            newRiskVolume,
            boundPrice,
            book.priceDenominator
        );
        envelope.remainingRiskVolume = uint128(newRiskVolume);
        envelope.reservedRisk = newRiskVolume == 0
            ? 0
            : uint128(
                LibMLOScenarioRisk.reservationRisk(
                    LibMLOScenarioMath.Side(envelope.side),
                    newRiskVolume,
                    boundPrice,
                    book.priceDenominator,
                    envelope.outcomeIndex,
                    envelope.outcomeCount
                )
            );

        uint256 seniorDebt = _applyDebt(state, bucketId, marketId, params.backing);
        if (params.backing.manufacturedShares != 0) {
            for (uint8 outcome; outcome < envelope.outcomeCount; ++outcome) {
                if (outcome != envelope.outcomeIndex) {
                    LibMLOInventory.addOutcome(state, bucketId, marketId, outcome, params.backing.manufacturedShares);
                }
            }
        }
        if (params.backing.bucketProfit != 0) {
            LibMarginAccount.recordProfitTrusted(state, bucketId, params.backing.bucketProfit);
        }
        LibMLOScenarioRisk.reconcilePosition(state, bucketId, marketId, seniorDebt, envelope.outcomeCount);
        LibRiskEngine.enforceScenarioInitialMarginAfter(state, bucketId, 0);

        LibBookAccounting.FeeShares memory fees = LibBookAccounting.feeSharesForBook(state, book, params.feePaid);
        LibBookAccounting.recordBookAndMarketFill(
            state, book, curve.maker, params.price, params.collateralUsed, params.feePaid, fees
        );
        LibMarkOracle.recordFill(state, book, params.price, params.sharesOut, params.collateralUsed - params.feePaid);
    }

    function _applyDebt(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bucketId,
        bytes32 marketId,
        MLOPredictionTypes.MLOAskBacking calldata backing
    ) private returns (uint256 seniorDebt) {
        seniorDebt = state.mloBucketMarketSeniorDebt[bucketId][marketId];
        if (backing.seniorDeployed != 0) {
            LibRiskEngine.recordDebtTrusted(state, bucketId, backing.seniorDeployed);
            seniorDebt += backing.seniorDeployed;
        }
        if (backing.seniorRepaid != 0) {
            LibRiskEngine.repayDebt(state, bucketId, backing.seniorRepaid);
            seniorDebt -= backing.seniorRepaid;
        }
        state.mloBucketMarketSeniorDebt[bucketId][marketId] = seniorDebt;
    }
}
