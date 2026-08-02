// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IMLOPredictionAdapterFacet} from "../interfaces/IMLOPredictionAdapterFacet.sol";
import {IQuoteEnvelopeFacet} from "../interfaces/IQuoteEnvelopeFacet.sol";
import {MLOInventoryVault} from "../MLOInventoryVault.sol";
import {CurveCLOBTypes} from "../types/CurveCLOBTypes.sol";
import {MLOPredictionTypes} from "../types/MLOPredictionTypes.sol";
import {ProductAdapterTypes} from "../types/ProductAdapterTypes.sol";
import {QuoteEnvelopeTypes} from "../types/QuoteEnvelopeTypes.sol";
import {Errors} from "./Errors.sol";
import {Events} from "./Events.sol";
import {LibBookAccess} from "./LibBookAccess.sol";
import {LibBookAccounting} from "./LibBookAccounting.sol";
import {LibBookPricing} from "./LibBookPricing.sol";
import {LibCLOBBook} from "./LibCLOBBook.sol";
import {LibCurveMath} from "./LibCurveMath.sol";
import {LibEveMarket} from "./LibEveMarket.sol";
import {LibMarkOracle} from "./LibMarkOracle.sol";
import {LibMLOInventory} from "./LibMLOInventory.sol";
import {LibMLOPredictionAdapter} from "./LibMLOPredictionAdapter.sol";
import {LibCurveIndex} from "./LibCurveIndex.sol";
import {LibMLOScenarioMath} from "./LibMLOScenarioMath.sol";
import {LibMLOScenarioRisk} from "./LibMLOScenarioRisk.sol";
import {LibProductAdapter} from "./LibProductAdapter.sol";
import {LibRiskEngine} from "./LibRiskEngine.sol";

library LibMLOPredictionBidFill {
    struct BidQuote {
        uint128 sharesIn;
        uint128 grossPayment;
        uint128 feePaid;
        uint128 collateralOut;
        uint128 price;
    }

    struct BidContext {
        uint256 envelopeId;
        bytes32 bucketId;
        bytes32 marketId;
        bytes32 bookId;
        address collateralToken;
        address positionToken;
        uint256 positionId;
        uint8 outcomeIndex;
        uint8 outcomeCount;
        uint128 boundConsumed;
        uint128 seniorReleased;
    }

    function fillBidCurve(
        LibEveMarket.EveMarketStorage storage state,
        MLOPredictionTypes.MLOBidFillRequest memory request
    ) internal returns (MLOPredictionTypes.MLOBidFillResult memory result) {
        uint256 envelopeId = state.mloCurveEnvelopeIds[request.curveId];
        if (envelopeId != 0) {
            IMLOPredictionAdapterFacet(address(this))
                .synchronizeMLOBucketState(state.quoteEnvelopes[envelopeId].bucketId);
        }
        (BidContext memory context, BidQuote memory quote) = _prepare(state, request);
        if (quote.collateralOut < request.minCollateralOut) {
            revert Errors.SlippageExceeded(quote.collateralOut, request.minCollateralOut);
        }
        if (quote.sharesIn == 0) {
            result.fill.unfilledBase = request.sharesIn;
            return result;
        }

        address vault = _inventoryVault(state, context.bucketId, context.marketId);
        _writeState(state, request.curveId, context, quote);
        IMLOPredictionAdapterFacet(address(this))
            .executeMLOBidAssetSettlement(
                MLOPredictionTypes.MLOBidAssetSettlementParams({
                    collateralToken: context.collateralToken,
                    positionToken: context.positionToken,
                    inventoryVault: vault,
                    source: request.source,
                    receiver: request.receiver,
                    bucketId: context.bucketId,
                    bookId: context.bookId,
                    positionId: context.positionId,
                    sharesIn: quote.sharesIn,
                    grossPayment: quote.grossPayment,
                    collateralOut: quote.collateralOut,
                    feePaid: quote.feePaid,
                    seniorReleased: context.seniorReleased
                })
            );
        IMLOPredictionAdapterFacet(address(this)).mergeAvailableMLOCompleteSet(context.bucketId, context.marketId);

        result = MLOPredictionTypes.MLOBidFillResult({
            fill: CurveCLOBTypes.SellBookResult({
                baseSold: quote.sharesIn,
                quoteOut: quote.collateralOut,
                feePaid: quote.feePaid,
                averagePrice: LibBookPricing.averagePrice(
                    state.books[context.bookId], quote.collateralOut, quote.sharesIn
                ),
                unfilledBase: request.sharesIn - quote.sharesIn
            }),
            envelopeId: context.envelopeId,
            bucketId: context.bucketId,
            seniorDeployed: quote.grossPayment,
            seniorReleased: context.seniorReleased,
            inventoryReceived: quote.sharesIn
        });

        emit Events.CurveFilled(
            request.curveId,
            state.curves[request.curveId].maker,
            request.seller,
            quote.grossPayment,
            quote.sharesIn,
            quote.feePaid
        );
        emit IMLOPredictionAdapterFacet.MLOBidCurveFilled(
            request.curveId,
            context.envelopeId,
            context.bucketId,
            request.seller,
            request.receiver,
            quote.sharesIn,
            quote.collateralOut,
            quote.feePaid,
            quote.grossPayment,
            context.seniorReleased,
            quote.sharesIn
        );
    }

    function isExecutableMLOBid(LibEveMarket.EveMarketStorage storage state, uint256 curveId)
        internal
        view
        returns (bool)
    {
        ProductAdapterTypes.AdapterCurveMetadata storage metadata = state.adapterCurveMetadata[curveId];
        if (
            metadata.backingKind != ProductAdapterTypes.CurveBackingKind.Adapter
                || metadata.adapterKind != ProductAdapterTypes.ProductAdapterKind.MLOPrediction || !metadata.active
        ) return false;
        uint256 envelopeId = state.mloCurveEnvelopeIds[curveId];
        QuoteEnvelopeTypes.StoredQuoteEnvelope storage envelope = state.quoteEnvelopes[envelopeId];
        LibEveMarket.StoredCurve storage curve = state.curves[curveId];
        return curve.active && curve.curveSide == LibEveMarket.CurveSide.BID && envelope.active
            && block.timestamp < envelope.expiresAt && envelope.currentVolume != 0
            && state.mloCurveSeniorReserved[curveId] != 0
            && LibRiskEngine.canIncreaseRiskForBook(state, envelope.bucketId, envelope.bookId);
    }

    function _prepare(LibEveMarket.EveMarketStorage storage state, MLOPredictionTypes.MLOBidFillRequest memory request)
        private
        view
        returns (BidContext memory context, BidQuote memory quote)
    {
        ProductAdapterTypes.AdapterCurveMetadata memory metadata =
            LibProductAdapter.requireActiveAdapterCurve(state, request.curveId);
        if (metadata.adapterKind != ProductAdapterTypes.ProductAdapterKind.MLOPrediction) {
            revert Errors.InvalidProductAdapter(uint8(metadata.adapterKind));
        }
        LibEveMarket.StoredCurve storage curve = state.curves[request.curveId];
        if (curve.maker == request.seller) {
            revert Errors.SelfFillNotAllowed(request.curveId, curve.maker, request.seller);
        }
        if (!isExecutableMLOBid(state, request.curveId)) revert Errors.AdapterCurveInactive(request.curveId);
        if (curve.generation != request.expectedGeneration) {
            revert Errors.GenerationMismatch(request.expectedGeneration, curve.generation);
        }
        bytes32 commitment = LibCurveMath.curveCommitment(curve.packed);
        if (commitment != request.expectedCommitment) {
            revert Errors.CommitmentMismatch(request.expectedCommitment, commitment);
        }
        LibEveMarket.Book storage book = LibBookAccess.requireExecutableBook(state, curve.bookId);
        if (!LibCLOBBook.canExecute(book)) revert Errors.MarketNotTrading(book.marketId);
        QuoteEnvelopeTypes.StoredQuoteEnvelope storage envelope =
            state.quoteEnvelopes[state.mloCurveEnvelopeIds[request.curveId]];
        quote.price = LibCurveMath.currentPrice(state, curve);
        uint256 shares = request.sharesIn < curve.remainingVolume ? request.sharesIn : curve.remainingVolume;
        quote.sharesIn = uint128(shares);
        quote.grossPayment = LibBookPricing.grossCostFor(book, quote.sharesIn, quote.price);
        quote.feePaid = LibCurveMath.feeFor(quote.grossPayment, book.feeConfig.entryFeeBps);
        if (quote.feePaid > quote.grossPayment) {
            revert Errors.InvalidAmount(quote.feePaid);
        }
        quote.collateralOut = quote.grossPayment - quote.feePaid;
        if (quote.sharesIn > envelope.currentVolume) {
            revert IQuoteEnvelopeFacet.InvalidQuoteEnvelopeVolume(quote.sharesIn, envelope.currentVolume);
        }
        uint256 oldRiskVolume = envelope.remainingRiskVolume;
        uint256 newRiskVolume = oldRiskVolume - quote.sharesIn;
        uint256 oldBound =
            LibMLOPredictionAdapter.bidReservation(oldRiskVolume, envelope.maxPrice, book.priceDenominator);
        uint256 newBound =
            LibMLOPredictionAdapter.bidReservation(newRiskVolume, envelope.maxPrice, book.priceDenominator);
        uint256 boundConsumed = oldBound - newBound;
        uint256 seniorReserved = state.mloCurveSeniorReserved[request.curveId];
        if (boundConsumed > seniorReserved || quote.grossPayment > boundConsumed) {
            revert IMLOPredictionAdapterFacet.MLOInsufficientCurveBacking(boundConsumed, seniorReserved);
        }
        LibEveMarket.Market storage market = state.markets[book.marketId];
        context = BidContext({
            envelopeId: state.mloCurveEnvelopeIds[request.curveId],
            bucketId: metadata.bucketId,
            marketId: book.marketId,
            bookId: book.bookId,
            collateralToken: market.collateralToken,
            positionToken: market.positionToken,
            positionId: book.baseTokenId,
            outcomeIndex: envelope.outcomeIndex,
            outcomeCount: envelope.outcomeCount,
            boundConsumed: uint128(boundConsumed),
            seniorReleased: uint128(boundConsumed - quote.grossPayment)
        });
    }

    function _writeState(
        LibEveMarket.EveMarketStorage storage state,
        uint256 curveId,
        BidContext memory context,
        BidQuote memory quote
    ) private {
        LibEveMarket.StoredCurve storage curve = state.curves[curveId];
        QuoteEnvelopeTypes.StoredQuoteEnvelope storage envelope = state.quoteEnvelopes[context.envelopeId];
        LibCurveIndex.decreaseBidRemaining(state, curveId, quote.sharesIn);
        envelope.currentVolume -= quote.sharesIn;
        state.mloCurveSeniorReserved[curveId] -= context.boundConsumed;
        state.mloBucketMarketSeniorReserved[context.bucketId][context.marketId] -= context.boundConsumed;

        LibRiskEngine.accrueConfiguredFunding(state, context.bucketId);
        uint256 oldRiskVolume = envelope.remainingRiskVolume;
        uint256 newRiskVolume = oldRiskVolume - quote.sharesIn;
        LibMLOScenarioRisk.replaceOpenReservation(
            state,
            context.bucketId,
            context.marketId,
            context.outcomeIndex,
            context.outcomeCount,
            LibMLOScenarioMath.Side.BID,
            oldRiskVolume,
            newRiskVolume,
            envelope.maxPrice,
            state.books[context.bookId].priceDenominator
        );
        envelope.remainingRiskVolume = uint128(newRiskVolume);
        envelope.reservedRisk = newRiskVolume == 0
            ? 0
            : uint128(
                LibMLOScenarioRisk.reservationRisk(
                    LibMLOScenarioMath.Side.BID,
                    newRiskVolume,
                    envelope.maxPrice,
                    state.books[context.bookId].priceDenominator,
                    context.outcomeIndex,
                    context.outcomeCount
                )
            );

        if (quote.grossPayment != 0) {
            LibRiskEngine.recordDebtTrusted(state, context.bucketId, quote.grossPayment);
            state.mloBucketMarketSeniorDebt[context.bucketId][context.marketId] += quote.grossPayment;
        }
        LibMLOInventory.addOutcome(state, context.bucketId, context.marketId, context.outcomeIndex, quote.sharesIn);
        LibMLOScenarioRisk.reconcilePosition(
            state,
            context.bucketId,
            context.marketId,
            state.mloBucketMarketSeniorDebt[context.bucketId][context.marketId],
            context.outcomeCount
        );
        LibRiskEngine.enforceScenarioInitialMarginAfter(state, context.bucketId, 0);

        LibEveMarket.Book storage book = state.books[context.bookId];
        LibBookAccounting.FeeShares memory fees = LibBookAccounting.feeSharesForBook(state, book, quote.feePaid);
        LibBookAccounting.recordBookAndMarketFill(
            state, book, curve.maker, quote.price, quote.grossPayment, quote.feePaid, fees
        );
        LibMarkOracle.recordFill(state, book, quote.price, quote.sharesIn, quote.grossPayment);
    }

    function _inventoryVault(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId, bytes32 marketId)
        private
        returns (address vault)
    {
        vault = state.mloInventoryVaults[bucketId][marketId];
        if (vault != address(0)) return vault;
        vault = address(new MLOInventoryVault(address(this)));
        state.mloInventoryVaults[bucketId][marketId] = vault;
        emit IMLOPredictionAdapterFacet.MLOInventoryVaultCreated(bucketId, marketId, vault);
    }
}
