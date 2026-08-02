// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {IStaticsDollar} from "@statics/dollar/interfaces/IStaticsDollar.sol";
import {IStaticsDollarCore} from "@statics/dollar/core/interfaces/IStaticsDollarCore.sol";

import {IEvesPositionManager} from "../interfaces/IEvesPositionManager.sol";
import {IMLOPredictionAdapterFacet} from "../interfaces/IMLOPredictionAdapterFacet.sol";
import {IMLOInsuranceFund} from "../interfaces/IMLOInsuranceFund.sol";
import {IMarginAccountFacet} from "../interfaces/IMarginAccountFacet.sol";
import {IQuoteEnvelopeFacet} from "../interfaces/IQuoteEnvelopeFacet.sol";
import {MLOInventoryVault} from "../MLOInventoryVault.sol";
import {MLOPredictionTypes} from "../types/MLOPredictionTypes.sol";
import {MarginTypes} from "../types/MarginTypes.sol";
import {ProductAdapterTypes} from "../types/ProductAdapterTypes.sol";
import {QuoteEnvelopeTypes} from "../types/QuoteEnvelopeTypes.sol";
import {Errors} from "./Errors.sol";
import {Events} from "./Events.sol";
import {LibBookPricing} from "./LibBookPricing.sol";
import {LibCLOBBook} from "./LibCLOBBook.sol";
import {LibCurvePacking} from "./LibCurvePacking.sol";
import {LibCurveIndex} from "./LibCurveIndex.sol";
import {LibCurveMath} from "./LibCurveMath.sol";
import {LibEveMarket} from "./LibEveMarket.sol";
import {LibMarginAccount} from "./LibMarginAccount.sol";
import {LibMarketAccess} from "./LibMarketAccess.sol";
import {LibMLOInventory} from "./LibMLOInventory.sol";
import {LibMLOFunding} from "./LibMLOFunding.sol";
import {LibMLOMarket} from "./LibMLOMarket.sol";
import {LibMLOScenarioMath} from "./LibMLOScenarioMath.sol";
import {LibMLOScenarioRisk} from "./LibMLOScenarioRisk.sol";
import {LibNativeCollateral} from "./LibNativeCollateral.sol";
import {LibProductAdapter} from "./LibProductAdapter.sol";
import {LibQuoteEnvelope} from "./LibQuoteEnvelope.sol";
import {LibRiskEngine} from "./LibRiskEngine.sol";
import {LibSeniorCapital} from "./LibSeniorCapital.sol";

library LibMLOPredictionAdapter {
    using SafeERC20 for IERC20;

    bytes32 private constant STATICS_DOLLAR_KIND = keccak256("STATICS_DOLLAR_TOKEN_V1");

    function createCurve(
        LibEveMarket.EveMarketStorage storage state,
        MLOPredictionTypes.CreateMLOCurveParams calldata params
    ) internal returns (uint256 curveId) {
        curveId = _createCurve(state, params.envelopeId, params.durationMinutes, true);
    }

    function postCurve(
        LibEveMarket.EveMarketStorage storage state,
        MLOPredictionTypes.PostMLOCurveParams calldata params
    ) internal returns (uint256 envelopeId, uint256 curveId) {
        LibRiskEngine.synchronizeMLOState(state, params.envelope.bucketId);
        envelopeId = LibQuoteEnvelope.createEnvelope(state, params.envelope);
        curveId = _createCurve(state, envelopeId, params.durationMinutes, false);
    }

    function postCurvesBatch(
        LibEveMarket.EveMarketStorage storage state,
        MLOPredictionTypes.PostMLOCurveParams[] calldata params
    ) internal returns (MLOPredictionTypes.MLOCurveIds[] memory ids) {
        uint256 length = params.length;
        if (length == 0) revert IMLOPredictionAdapterFacet.MLOEmptyBatch();
        ids = new MLOPredictionTypes.MLOCurveIds[](length);

        bytes32 synchronizedBucketId;
        bool hasSynchronizedBucket;
        for (uint256 index; index < length; ++index) {
            MLOPredictionTypes.PostMLOCurveParams calldata post = params[index];
            bytes32 bucketId = post.envelope.bucketId;
            if (!hasSynchronizedBucket || bucketId != synchronizedBucketId) {
                LibRiskEngine.synchronizeMLOState(state, bucketId);
                synchronizedBucketId = bucketId;
                hasSynchronizedBucket = true;
            }
            uint256 envelopeId = LibQuoteEnvelope.createEnvelope(state, post.envelope);
            uint256 curveId = _createCurve(state, envelopeId, post.durationMinutes, false);
            ids[index] = MLOPredictionTypes.MLOCurveIds({envelopeId: envelopeId, curveId: curveId});
        }
    }

    function _createCurve(
        LibEveMarket.EveMarketStorage storage state,
        uint256 envelopeId,
        uint24 durationMinutes,
        bool synchronize
    ) private returns (uint256 curveId) {
        _enforceCanonicalMLOConfig(state);
        QuoteEnvelopeTypes.StoredQuoteEnvelope storage envelope = _requireEnvelope(state, envelopeId);
        if (synchronize) LibRiskEngine.synchronizeMLOState(state, envelope.bucketId);
        _enforceEnvelopeOperator(envelope);
        _enforceEnvelopeActiveAndFresh(envelopeId, envelope);
        if (state.mloEnvelopeCurveIds[envelopeId] != 0) {
            revert IMLOPredictionAdapterFacet.MLOEnvelopeAlreadyBound(
                envelopeId, state.mloEnvelopeCurveIds[envelopeId] - 1
            );
        }

        LibEveMarket.Book storage book = state.books[envelope.bookId];
        LibEveMarket.Market storage market = _requireSupportedBook(state, book);
        _enforceSeniorAsset(state, market.collateralToken, envelope.bookId);
        _enforceCurveExpiry(book, market, envelope, durationMinutes, block.timestamp);

        uint256 packed = _packCurve(book, envelope.currentStartPrice, envelope.currentEndPrice, durationMinutes);
        curveId = state.nextCurveId++;
        LibEveMarket.StoredCurve storage curve = state.curves[curveId];
        curve.packed = packed;
        curve.remainingVolume = envelope.currentVolume;
        curve.createdAt = uint64(block.timestamp);
        curve.generation = 1;
        curve.active = true;
        curve.isYesSide = envelope.outcomeIndex == 0;
        curve.curveSide = LibEveMarket.CurveSide(envelope.side);
        curve.maker = envelope.operator;
        curve.bookId = envelope.bookId;
        state.bookCurveIds[envelope.bookId].push(curveId);
        LibCurveIndex.registerCreatedCurve(state, curveId);
        book.curveCount += 1;
        market.curveCount += 1;

        state.mloCurveEnvelopeIds[curveId] = envelopeId;
        state.mloEnvelopeCurveIds[envelopeId] = curveId + 1;
        uint256 inventoryReserved;
        uint256 seniorReserved;
        if (curve.curveSide == LibEveMarket.CurveSide.ASK) {
            inventoryReserved = LibMLOInventory.reserveForCurve(
                state, curveId, envelope.bucketId, book.marketId, envelope.outcomeIndex, envelope.remainingRiskVolume
            );
            seniorReserved = LibMLOScenarioMath.askSeniorRequirement(
                uint256(envelope.remainingRiskVolume) - inventoryReserved, envelope.minPrice, book.priceDenominator
            );
        } else if (curve.curveSide == LibEveMarket.CurveSide.BID) {
            seniorReserved = _bidReservation(envelope.remainingRiskVolume, envelope.maxPrice, book.priceDenominator);
        } else {
            revert IMLOPredictionAdapterFacet.MLOUnsupportedCurveSide(envelope.side);
        }
        state.mloCurveSeniorReserved[curveId] = seniorReserved;
        if (seniorReserved != 0) {
            state.mloBucketMarketSeniorReserved[envelope.bucketId][book.marketId] += seniorReserved;
            LibSeniorCapital.reserveCapital(LibSeniorCapital.s(), envelope.bucketId, seniorReserved);
        }

        LibProductAdapter.setAdapterCurveMetadata(
            state,
            curveId,
            ProductAdapterTypes.ProductAdapterKind.MLOPrediction,
            envelope.bucketId,
            state.marginBuckets[envelope.bucketId].riskDomainId,
            bytes32(envelopeId)
        );

        emit Events.CurvePosted(book.marketId, curveId, envelope.operator, curve.isYesSide, packed);
        emit Events.BookCurvePosted(
            envelope.bookId, book.marketId, curveId, envelope.operator, curve.isYesSide, envelope.side, packed
        );
        emit IMLOPredictionAdapterFacet.MLOCurveCreated(
            curveId, envelopeId, envelope.bucketId, envelope.side, envelope.outcomeIndex
        );
        if (curve.curveSide == LibEveMarket.CurveSide.ASK) {
            emit IMLOPredictionAdapterFacet.MLOAskCurveRebalanced(
                curveId, envelope.bucketId, inventoryReserved, seniorReserved
            );
        }
    }

    function updateCurve(
        LibEveMarket.EveMarketStorage storage state,
        MLOPredictionTypes.UpdateMLOCurveParams calldata params
    ) internal returns (uint32 curveGeneration) {
        curveGeneration = _updateCurve(state, params, false, true);
    }

    function updateCurveFromNow(
        LibEveMarket.EveMarketStorage storage state,
        MLOPredictionTypes.UpdateMLOCurveParams calldata params
    ) internal returns (uint32 curveGeneration) {
        curveGeneration = _updateCurve(state, params, true, true);
    }

    function updateCurvesBatch(
        LibEveMarket.EveMarketStorage storage state,
        MLOPredictionTypes.UpdateMLOCurveParams[] calldata params,
        bool resetStartTime
    ) internal returns (uint32[] memory curveGenerations) {
        uint256 length = params.length;
        if (length == 0) revert IMLOPredictionAdapterFacet.MLOEmptyBatch();
        curveGenerations = new uint32[](length);

        bytes32 synchronizedBucketId;
        bool hasSynchronizedBucket;
        for (uint256 index; index < length; ++index) {
            uint256 curveId = params[index].curveId;
            uint256 envelopeId = _curveEnvelopeId(state, curveId);
            bytes32 bucketId = _requireEnvelope(state, envelopeId).bucketId;
            if (!hasSynchronizedBucket || bucketId != synchronizedBucketId) {
                LibRiskEngine.synchronizeMLOState(state, bucketId);
                synchronizedBucketId = bucketId;
                hasSynchronizedBucket = true;
            }
            curveGenerations[index] = _updateCurve(state, params[index], resetStartTime, false);
        }
    }

    function _updateCurve(
        LibEveMarket.EveMarketStorage storage state,
        MLOPredictionTypes.UpdateMLOCurveParams calldata params,
        bool resetStartTime,
        bool synchronize
    ) private returns (uint32 curveGeneration) {
        LibEveMarket.StoredCurve storage curve = _requireMLOCurve(state, params.curveId);
        if (curve.generation != params.expectedCurveGeneration) {
            revert Errors.GenerationMismatch(params.expectedCurveGeneration, curve.generation);
        }
        uint256 envelopeId = _curveEnvelopeId(state, params.curveId);
        QuoteEnvelopeTypes.StoredQuoteEnvelope storage envelope = _requireEnvelope(state, envelopeId);
        if (synchronize) LibRiskEngine.synchronizeMLOState(state, envelope.bucketId);
        if (envelope.generation != params.expectedEnvelopeGeneration) {
            revert IMLOPredictionAdapterFacet.MLOEnvelopeGenerationMismatch(
                params.expectedEnvelopeGeneration, envelope.generation
            );
        }
        _enforceEnvelopeOperator(envelope);
        if (LibCurveMath.isExpired(state, curve)) revert Errors.CurveExpired(params.curveId);
        LibQuoteEnvelope.validateUpdate(state, envelopeId, params.envelopeUpdate, true);

        uint128 previousRiskVolume = envelope.remainingRiskVolume;
        uint128 newRiskVolume = params.envelopeUpdate.volume;
        LibEveMarket.Book storage book = state.books[curve.bookId];
        LibEveMarket.Market storage market = state.markets[envelope.marketId];
        if (!_isExecutableMLOBook(book, market)) {
            bool strictReduction = newRiskVolume < previousRiskVolume;
            bool pricesUnchanged = params.envelopeUpdate.startPrice == envelope.currentStartPrice
                && params.envelopeUpdate.endPrice == envelope.currentEndPrice;
            if (!strictReduction || !pricesUnchanged || resetStartTime) {
                revert Errors.MarketNotTrading(envelope.marketId);
            }
        }
        if (resetStartTime) {
            _enforceCurveExpiry(
                book, market, envelope, LibCurvePacking.unpack(curve.packed).durationMinutes, block.timestamp
            );
        }
        if (newRiskVolume > previousRiskVolume) {
            MarginTypes.MarginBucket storage bucket = state.marginBuckets[envelope.bucketId];
            LibRiskEngine.enforceCanIncreaseRiskForBook(state, envelope.bucketId, bucket, envelope.bookId);
        }
        if (newRiskVolume != previousRiskVolume) {
            LibQuoteEnvelope.resizeReservation(state, envelopeId, newRiskVolume);
            if (newRiskVolume > previousRiskVolume) {
                LibRiskEngine.enforceScenarioInitialMarginAfter(state, envelope.bucketId, 0);
            }
            _resizeCurveBacking(state, params.curveId, curve, envelope, previousRiskVolume, newRiskVolume);
        }
        LibQuoteEnvelope.applyUpdate(state, envelopeId, params.envelopeUpdate);

        curve.packed = _packCurve(
            book,
            params.envelopeUpdate.startPrice,
            params.envelopeUpdate.endPrice,
            LibCurvePacking.unpack(curve.packed).durationMinutes
        );
        LibCurveIndex.setRemaining(state, params.curveId, params.envelopeUpdate.volume);
        uint64 createdAt;
        if (resetStartTime) {
            createdAt = uint64(block.timestamp);
            curve.createdAt = createdAt;
        }
        curve.generation += 1;
        curveGeneration = curve.generation;
        emit Events.CurveUpdated(params.curveId, curve.packed, curveGeneration);
        if (resetStartTime) {
            emit Events.CurveUpdatedFromNow(params.curveId, curve.packed, curveGeneration, createdAt);
        }
        emit IMLOPredictionAdapterFacet.MLOCurveUpdated(params.curveId, envelopeId, curveGeneration);
        if (newRiskVolume != previousRiskVolume) {
            emit IMLOPredictionAdapterFacet.MLOCurveReservationResized(
                params.curveId,
                envelopeId,
                previousRiskVolume,
                newRiskVolume,
                state.mloCurveInventoryReserved[params.curveId],
                state.mloCurveSeniorReserved[params.curveId]
            );
        }
    }

    function _resizeCurveBacking(
        LibEveMarket.EveMarketStorage storage state,
        uint256 curveId,
        LibEveMarket.StoredCurve storage curve,
        QuoteEnvelopeTypes.StoredQuoteEnvelope storage envelope,
        uint256 previousRiskVolume,
        uint256 newRiskVolume
    ) private {
        if (curve.curveSide == LibEveMarket.CurveSide.ASK) {
            uint256 inventoryReserved = state.mloCurveInventoryReserved[curveId];
            if (newRiskVolume < previousRiskVolume) {
                if (inventoryReserved > newRiskVolume) {
                    uint256 inventoryReduction = inventoryReserved - newRiskVolume;
                    LibMLOInventory.releaseCurveInventoryAmount(
                        state, curveId, envelope.bucketId, envelope.marketId, envelope.outcomeIndex, inventoryReduction
                    );
                    inventoryReserved = newRiskVolume;
                }
            } else {
                uint256 inventoryAdded = LibMLOInventory.reserveForCurve(
                    state,
                    curveId,
                    envelope.bucketId,
                    envelope.marketId,
                    envelope.outcomeIndex,
                    newRiskVolume - previousRiskVolume
                );
                inventoryReserved += inventoryAdded;
            }
            uint256 targetSenior = LibMLOScenarioMath.askSeniorRequirement(
                newRiskVolume - inventoryReserved, envelope.minPrice, state.books[curve.bookId].priceDenominator
            );
            _setSeniorReservation(state, curveId, envelope.bucketId, envelope.marketId, targetSenior);
            return;
        }

        uint256 targetBidSenior =
            _bidReservation(newRiskVolume, envelope.maxPrice, state.books[curve.bookId].priceDenominator);
        _setSeniorReservation(state, curveId, envelope.bucketId, envelope.marketId, targetBidSenior);
    }

    function _setSeniorReservation(
        LibEveMarket.EveMarketStorage storage state,
        uint256 curveId,
        bytes32 bucketId,
        bytes32 marketId,
        uint256 targetSenior
    ) private {
        uint256 currentSenior = state.mloCurveSeniorReserved[curveId];
        if (targetSenior < currentSenior) {
            _decreaseSeniorReservation(state, curveId, bucketId, marketId, currentSenior - targetSenior);
        } else if (targetSenior > currentSenior) {
            _increaseSeniorReservation(state, curveId, bucketId, marketId, targetSenior - currentSenior);
        }
    }

    function _increaseSeniorReservation(
        LibEveMarket.EveMarketStorage storage state,
        uint256 curveId,
        bytes32 bucketId,
        bytes32 marketId,
        uint256 assets
    ) private {
        state.mloCurveSeniorReserved[curveId] += assets;
        state.mloBucketMarketSeniorReserved[bucketId][marketId] += assets;
        LibSeniorCapital.reserveCapital(LibSeniorCapital.s(), bucketId, assets);
    }

    function _decreaseSeniorReservation(
        LibEveMarket.EveMarketStorage storage state,
        uint256 curveId,
        bytes32 bucketId,
        bytes32 marketId,
        uint256 assets
    ) private {
        state.mloCurveSeniorReserved[curveId] -= assets;
        state.mloBucketMarketSeniorReserved[bucketId][marketId] -= assets;
        LibSeniorCapital.releaseReservedCapital(LibSeniorCapital.s(), bucketId, assets);
    }

    function cancelCurve(LibEveMarket.EveMarketStorage storage state, uint256 curveId) internal {
        uint256 envelopeId = _curveEnvelopeId(state, curveId);
        LibRiskEngine.synchronizeMLOState(state, state.quoteEnvelopes[envelopeId].bucketId);
        _cancelCurve(state, curveId, true);
    }

    function cleanupCurve(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId, uint256 curveId)
        internal
        returns (uint256 inventoryReleased, uint256 seniorReleased, uint256 riskReleased, bool cleaned)
    {
        ProductAdapterTypes.AdapterCurveMetadata storage metadata = state.adapterCurveMetadata[curveId];
        if (
            metadata.adapterKind != ProductAdapterTypes.ProductAdapterKind.MLOPrediction
                || metadata.bucketId != bucketId
        ) {
            revert IMLOPredictionAdapterFacet.MLORecoveryCurveMismatch(curveId, bucketId, metadata.bucketId);
        }
        LibEveMarket.StoredCurve storage curve = state.curves[curveId];
        if (!curve.active) return (0, 0, 0, false);
        if (!isCurveCleanupAllowed(state, bucketId, curveId)) {
            revert IMLOPredictionAdapterFacet.MLOCurveCleanupNotAllowed(curveId, bucketId);
        }
        (inventoryReleased, seniorReleased, riskReleased) = _cancelCurve(state, curveId, false);
        cleaned = true;
    }

    function isCurveCleanupAllowed(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId, uint256 curveId)
        internal
        view
        returns (bool allowed)
    {
        LibEveMarket.StoredCurve storage curve = state.curves[curveId];
        if (!curve.active) return false;
        QuoteEnvelopeTypes.StoredQuoteEnvelope storage envelope =
            state.quoteEnvelopes[state.mloCurveEnvelopeIds[curveId]];
        if (state.marginBuckets[bucketId].state == MarginTypes.BucketState.Recovering) return true;
        if (block.timestamp >= envelope.expiresAt || block.timestamp >= LibCurveMath.expiresAt(state, curve)) {
            return true;
        }
        LibEveMarket.Market storage market = state.markets[envelope.marketId];
        if (block.timestamp >= market.expiryTime) return true;
        return market.state == LibEveMarket.MarketState.Pending || market.state == LibEveMarket.MarketState.Disputed
            || market.state == LibEveMarket.MarketState.Resolved;
    }

    function _cancelCurve(LibEveMarket.EveMarketStorage storage state, uint256 curveId, bool enforceOperator)
        private
        returns (uint256 inventoryReleased, uint256 seniorReleased, uint256 riskReleased)
    {
        LibEveMarket.StoredCurve storage curve = _requireMLOCurve(state, curveId);
        uint256 envelopeId = _curveEnvelopeId(state, curveId);
        QuoteEnvelopeTypes.StoredQuoteEnvelope storage envelope = _requireEnvelope(state, envelopeId);
        if (enforceOperator) _enforceEnvelopeOperator(envelope);

        inventoryReleased = LibMLOInventory.releaseCurveInventory(
            state, curveId, envelope.bucketId, envelope.marketId, envelope.outcomeIndex
        );
        seniorReleased = state.mloCurveSeniorReserved[curveId];
        riskReleased = envelope.reservedRisk;
        uint128 remainingRiskVolume = envelope.remainingRiskVolume;
        LibCurveIndex.deactivate(state, curveId);
        envelope.active = false;
        envelope.currentVolume = 0;
        envelope.reservedRisk = 0;
        envelope.remainingRiskVolume = 0;
        curve.generation += 1;
        envelope.generation += 1;
        state.mloCurveSeniorReserved[curveId] = 0;
        if (seniorReleased != 0) {
            state.mloBucketMarketSeniorReserved[envelope.bucketId][envelope.marketId] -= seniorReleased;
        }
        if (remainingRiskVolume != 0) {
            LibMLOScenarioRisk.removeOpenReservation(
                state,
                envelope.bucketId,
                envelope.marketId,
                envelope.outcomeIndex,
                envelope.outcomeCount,
                LibMLOScenarioMath.Side(envelope.side),
                remainingRiskVolume,
                envelope.side == uint8(LibEveMarket.CurveSide.ASK) ? envelope.minPrice : envelope.maxPrice,
                state.books[envelope.bookId].priceDenominator
            );
        }
        if (seniorReleased != 0) {
            LibSeniorCapital.releaseReservedCapital(LibSeniorCapital.s(), envelope.bucketId, seniorReleased);
        }
        emit Events.CurveCancelled(curveId);
        emit IQuoteEnvelopeFacet.QuoteEnvelopeCancelled(envelopeId, uint128(riskReleased), envelope.generation);
        emit IMLOPredictionAdapterFacet.MLOCurveCancelled(
            curveId, envelopeId, inventoryReleased, seniorReleased, riskReleased
        );
    }

    function rebalanceAskCurve(LibEveMarket.EveMarketStorage storage state, uint256 curveId)
        internal
        returns (uint256 inventoryReserved, uint256 seniorReserved)
    {
        LibEveMarket.StoredCurve storage curve = _requireMLOCurve(state, curveId);
        if (curve.curveSide != LibEveMarket.CurveSide.ASK) {
            revert IMLOPredictionAdapterFacet.MLOUnsupportedCurveSide(uint8(curve.curveSide));
        }
        QuoteEnvelopeTypes.StoredQuoteEnvelope storage envelope =
            _requireEnvelope(state, _curveEnvelopeId(state, curveId));
        LibRiskEngine.synchronizeMLOState(state, envelope.bucketId);
        uint256 inventoryBefore = state.mloCurveInventoryReserved[curveId];
        uint256 unbackedShares = uint256(envelope.remainingRiskVolume) - inventoryBefore;
        LibMLOInventory.rebalanceCurve(
            state, curveId, envelope.bucketId, envelope.marketId, envelope.outcomeIndex, unbackedShares
        );
        inventoryReserved = state.mloCurveInventoryReserved[curveId];
        seniorReserved = LibMLOScenarioMath.askSeniorRequirement(
            uint256(envelope.remainingRiskVolume) - inventoryReserved,
            envelope.minPrice,
            state.books[curve.bookId].priceDenominator
        );
        _setSeniorReservation(state, curveId, envelope.bucketId, envelope.marketId, seniorReserved);
        emit IMLOPredictionAdapterFacet.MLOAskCurveRebalanced(
            curveId, envelope.bucketId, inventoryReserved, seniorReserved
        );
    }

    function viewCurve(LibEveMarket.EveMarketStorage storage state, uint256 curveId)
        internal
        view
        returns (MLOPredictionTypes.MLOCurveView memory view_)
    {
        LibEveMarket.StoredCurve storage curve = state.curves[curveId];
        uint256 envelopeId = state.mloCurveEnvelopeIds[curveId];
        if (envelopeId == 0) revert IMLOPredictionAdapterFacet.MLOAdapterCurveNotFound(curveId);
        QuoteEnvelopeTypes.StoredQuoteEnvelope storage envelope = state.quoteEnvelopes[envelopeId];
        view_ = MLOPredictionTypes.MLOCurveView({
            curveId: curveId,
            envelopeId: envelopeId,
            bucketId: envelope.bucketId,
            bookId: curve.bookId,
            marketId: envelope.marketId,
            side: uint8(curve.curveSide),
            outcomeIndex: envelope.outcomeIndex,
            outcomeCount: envelope.outcomeCount,
            operator: curve.maker,
            remainingVolume: curve.remainingVolume,
            inventoryReserved: state.mloCurveInventoryReserved[curveId],
            seniorReserved: state.mloCurveSeniorReserved[curveId],
            active: curve.active,
            envelopeActive: envelope.active,
            curveGeneration: curve.generation,
            envelopeGeneration: envelope.generation
        });
    }

    function viewInventory(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId, bytes32 marketId)
        internal
        view
        returns (MLOPredictionTypes.MLOInventoryView memory inventory)
    {
        uint8 count = LibMLOMarket.outcomeCount(state, marketId);
        uint256[] memory amounts = new uint256[](count);
        uint256[] memory reserved = new uint256[](count);
        uint256[] memory available = new uint256[](count);
        for (uint8 outcome; outcome < count; ++outcome) {
            amounts[outcome] = state.mloBucketOutcomeInventory[bucketId][marketId][outcome];
            reserved[outcome] = state.mloBucketOutcomeInventoryReserved[bucketId][marketId][outcome];
            available[outcome] = amounts[outcome] > reserved[outcome] ? amounts[outcome] - reserved[outcome] : 0;
        }
        inventory = MLOPredictionTypes.MLOInventoryView({
            bucketId: bucketId,
            marketId: marketId,
            vault: state.mloInventoryVaults[bucketId][marketId],
            outcomeCount: count,
            inventory: amounts,
            reserved: reserved,
            available: available,
            seniorDebt: state.mloBucketMarketSeniorDebt[bucketId][marketId],
            seniorReserved: state.mloBucketMarketSeniorReserved[bucketId][marketId],
            positionRisk: state.mloBucketMarketPositionRisk[bucketId][marketId]
        });
    }

    function viewScenarioExposure(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId)
        internal
        view
        returns (MLOPredictionTypes.MLOScenarioExposureView memory exposure)
    {
        MarginTypes.MarginBucket storage bucket = LibRiskEngine.requireBucket(state, bucketId);
        MarginTypes.RiskParams memory params = LibRiskEngine.riskParamsForBucket(state, bucket);
        uint256 funding = bucket.fundingLiability + LibRiskEngine.pendingConfiguredFunding(state, bucket);
        exposure = LibMLOScenarioRisk.viewExposure(
            state, bucketId, funding, params.initialMarginBps, params.maintenanceMarginBps
        );
    }

    function viewFunding(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId)
        internal
        view
        returns (MLOPredictionTypes.MLOFundingView memory funding)
    {
        MarginTypes.MarginBucket storage bucket = LibRiskEngine.requireBucket(state, bucketId);
        MarginTypes.FundingConfig memory config = state.marginRiskDomainFundingConfigs[bucket.riskDomainId];
        uint256 currentIndex = config.cumulativeIndexWad;
        if (config.mode == MarginTypes.FundingMode.BorrowRate && block.timestamp > config.lastUpdatedAt) {
            currentIndex += uint256(config.ratePerSecondWad) * (block.timestamp - config.lastUpdatedAt);
        }
        funding = MLOPredictionTypes.MLOFundingView({
            ratePerSecondWad: config.ratePerSecondWad,
            cumulativeIndexWad: currentIndex,
            accrued: bucket.fundingAccrued,
            paid: bucket.fundingPaid,
            liability: bucket.fundingLiability,
            pending: LibRiskEngine.pendingConfiguredFunding(state, bucket),
            remainderWad: bucket.fundingRemainderWad
        });
    }

    function mergeCompleteSet(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bucketId,
        bytes32 marketId,
        uint256 amount
    ) internal returns (MLOPredictionTypes.MLOCompleteSetMerge memory result) {
        LibEveMarket.Market storage market = _requireInventoryMarket(state, bucketId, marketId, false);
        address vault = state.mloInventoryVaults[bucketId][marketId];
        uint8 count = LibMLOMarket.outcomeCount(state, marketId);
        LibMLOInventory.removeCompleteSet(state, bucketId, marketId, count, amount);

        uint256 collateralOut;
        if (market.positionTokenType == LibEveMarket.PositionTokenType.CTF) {
            uint256 balanceBefore = IERC20(market.collateralToken).balanceOf(address(this));
            LibEveMarket.MultiOutcomeMarket storage multi = state.multiOutcomeMarkets[marketId];
            if (multi.exists) {
                MLOInventoryVault(vault).mergeNegRiskToController(multi.adapter, multi.conditionId, amount);
            } else {
                MLOInventoryVault(vault)
                    .mergeToController(market.positionToken, market.collateralToken, market.conditionId, amount);
            }
            collateralOut = IERC20(market.collateralToken).balanceOf(address(this)) - balanceBefore;
            if (collateralOut != amount) {
                revert IMLOPredictionAdapterFacet.MLOMergeCollateralMismatch(amount, collateralOut);
            }
        } else {
            uint256[] memory ids = LibMLOMarket.positionIds(state, market);
            uint256[] memory amounts = new uint256[](count);
            for (uint8 outcome; outcome < count; ++outcome) {
                amounts[outcome] = amount;
            }
            IEvesPositionManager(market.positionToken).batchBurn(vault, ids, amounts);
            LibNativeCollateral.decreaseLiability(state, market.collateralToken, amount);
            collateralOut = amount;
        }

        (uint256 seniorRepaid, uint256 fundingPaid, uint256 bucketProfit) =
            _applyInventoryProceeds(state, bucketId, marketId, market.collateralToken, collateralOut);
        LibMLOScenarioRisk.reconcilePosition(
            state, bucketId, marketId, state.mloBucketMarketSeniorDebt[bucketId][marketId], count
        );
        if (
            LibMLOInventory.isEmpty(state, bucketId, marketId, count)
                && state.mloBucketMarketSeniorDebt[bucketId][marketId] == 0
        ) state.mloInventoryVaults[bucketId][marketId] = address(0);

        result = MLOPredictionTypes.MLOCompleteSetMerge({
            bucketId: bucketId,
            marketId: marketId,
            amount: amount,
            collateralOut: collateralOut,
            seniorRepaid: seniorRepaid,
            bucketProfit: bucketProfit,
            fundingPaid: fundingPaid
        });
        emit IMLOPredictionAdapterFacet.MLOCompleteSetMerged(
            bucketId, marketId, vault, amount, collateralOut, seniorRepaid, bucketProfit, fundingPaid
        );
    }

    function settleInventory(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId, bytes32 marketId)
        internal
        returns (MLOPredictionTypes.MLOInventorySettlement memory settlement)
    {
        MarginTypes.MarginBucket storage existingBucket = state.marginBuckets[bucketId];
        if (
            existingBucket.exists && existingBucket.state == MarginTypes.BucketState.Closed
                && state.mloScenarioExposures[bucketId].marketId == marketId
                && state.mloInventoryVaults[bucketId][marketId] == address(0)
        ) {
            settlement.bucketId = bucketId;
            settlement.marketId = marketId;
            return settlement;
        }
        LibEveMarket.Market storage market = _requireInventoryMarket(state, bucketId, marketId, true);
        uint8 count = LibMLOMarket.outcomeCount(state, marketId);
        LibMLOInventory.requireNoReservations(state, bucketId, marketId, count);
        address vault = state.mloInventoryVaults[bucketId][marketId];
        uint256 seniorDebt = state.mloBucketMarketSeniorDebt[bucketId][marketId];
        uint256 positionRisk = state.mloBucketMarketPositionRisk[bucketId][marketId];

        settlement.bucketId = bucketId;
        settlement.marketId = marketId;
        if (market.positionTokenType == LibEveMarket.PositionTokenType.CTF) {
            LibEveMarket.MultiOutcomeMarket storage multi = state.multiOutcomeMarkets[marketId];
            if (multi.exists) {
                uint256[] memory amounts = new uint256[](count);
                for (uint8 outcome; outcome < count; ++outcome) {
                    amounts[outcome] = state.mloBucketOutcomeInventory[bucketId][marketId][outcome];
                }
                settlement.collateralOut =
                    MLOInventoryVault(vault).redeemNegRiskToController(multi.adapter, multi.conditionId, amounts);
            } else {
                settlement.collateralOut = MLOInventoryVault(vault)
                    .redeemToController(market.positionToken, market.collateralToken, market.conditionId);
            }
        } else {
            settlement.collateralOut = LibMLOMarket.resolutionPayout(state, bucketId, market);
            uint256[] memory ids = LibMLOMarket.positionIds(state, market);
            uint256[] memory amounts = new uint256[](count);
            for (uint8 outcome; outcome < count; ++outcome) {
                amounts[outcome] = state.mloBucketOutcomeInventory[bucketId][marketId][outcome];
            }
            IEvesPositionManager(market.positionToken).batchBurn(vault, ids, amounts);
            LibNativeCollateral.decreaseLiability(state, market.collateralToken, settlement.collateralOut);
        }

        LibRiskEngine.accrueConfiguredFunding(state, bucketId);
        uint256 remainingDebt = seniorDebt;
        uint256 repayFromInventory = settlement.collateralOut < remainingDebt ? settlement.collateralOut : remainingDebt;
        if (repayFromInventory != 0) {
            _repaySenior(bucketId, repayFromInventory);
            remainingDebt -= repayFromInventory;
            settlement.seniorRepaid = repayFromInventory;
        }
        if (remainingDebt != 0) {
            uint256 marginAvailable = state.marginBuckets[bucketId].marginAllocated;
            settlement.marginUsed = remainingDebt < marginAvailable ? remainingDebt : marginAvailable;
            if (settlement.marginUsed != 0) {
                LibMarginAccount.recordLossTrusted(state, bucketId, settlement.marginUsed);
                _repaySenior(bucketId, settlement.marginUsed);
                remainingDebt -= settlement.marginUsed;
                settlement.seniorRepaid += settlement.marginUsed;
            }
        }
        if (remainingDebt != 0) {
            address insuranceFund = state.mloInsuranceFund;
            if (insuranceFund == address(0)) {
                revert IMLOPredictionAdapterFacet.InvalidMLOInsuranceFund(insuranceFund);
            }
            uint256 availableInsurance = IMLOInsuranceFund(insuranceFund).availableInsurance();
            settlement.insuranceDraw = remainingDebt < availableInsurance ? remainingDebt : availableInsurance;
            if (settlement.insuranceDraw != 0) {
                IMLOInsuranceFund(insuranceFund).draw(bucketId, address(this), settlement.insuranceDraw);
                _repaySenior(bucketId, settlement.insuranceDraw);
                remainingDebt -= settlement.insuranceDraw;
                settlement.seniorRepaid += settlement.insuranceDraw;
            }
        }
        if (remainingDebt != 0) {
            LibSeniorCapital.recordRealizedLoss(LibSeniorCapital.s(), bucketId, remainingDebt);
            settlement.seniorLoss = remainingDebt;
        }
        if (seniorDebt != 0) LibRiskEngine.repayDebt(state, bucketId, seniorDebt);
        uint256 surplusInventory = settlement.collateralOut > seniorDebt ? settlement.collateralOut - seniorDebt : 0;
        if (surplusInventory != 0) {
            settlement.fundingPaid =
                LibMLOFunding.payFromProceeds(state, bucketId, market.collateralToken, surplusInventory);
            surplusInventory -= settlement.fundingPaid;
        }
        if (state.marginBuckets[bucketId].fundingLiability != 0) {
            settlement.fundingMarginUsed = LibMLOFunding.payFromMargin(state, bucketId, type(uint256).max);
            settlement.fundingPaid += settlement.fundingMarginUsed;
        }
        settlement.fundingWrittenOff = LibRiskEngine.writeOffFunding(state, bucketId);
        if (settlement.fundingWrittenOff != 0) {
            emit IMLOPredictionAdapterFacet.MLOFundingWrittenOff(bucketId, settlement.fundingWrittenOff);
        }
        if (surplusInventory != 0) {
            settlement.bucketProfit = surplusInventory;
            LibMarginAccount.recordProfitTrusted(state, bucketId, settlement.bucketProfit);
        }
        if (LibRiskEngine.isScenarioManaged(state, bucketId)) {
            LibMLOScenarioRisk.clearFilledPosition(state, bucketId);
        } else if (positionRisk != 0) {
            LibRiskEngine.releasePositionRisk(state, bucketId, positionRisk);
        }
        for (uint8 outcome; outcome < count; ++outcome) {
            state.mloBucketOutcomeInventory[bucketId][marketId][outcome] = 0;
        }
        state.mloInventoryVaults[bucketId][marketId] = address(0);
        state.mloBucketMarketSeniorDebt[bucketId][marketId] = 0;
        state.mloBucketMarketPositionRisk[bucketId][marketId] = 0;
        MarginTypes.MarginBucket storage bucket = state.marginBuckets[bucketId];
        MarginTypes.BucketState previousState = bucket.state;
        bucket.state = MarginTypes.BucketState.Closed;
        emit IMarginAccountFacet.BucketStateSet(bucketId, previousState, MarginTypes.BucketState.Closed);
        emit IMLOPredictionAdapterFacet.MLOInventorySettled(
            bucketId,
            marketId,
            vault,
            settlement.collateralOut,
            settlement.seniorRepaid,
            settlement.marginUsed,
            settlement.fundingMarginUsed,
            settlement.seniorLoss,
            settlement.bucketProfit,
            settlement.fundingPaid
        );
        emit IMLOPredictionAdapterFacet.MLOBucketClosed(
            bucketId, settlement.insuranceDraw, settlement.seniorLoss, settlement.fundingWrittenOff
        );
    }

    function bidReservation(uint256 volume, uint256 price, uint256 denominator) internal pure returns (uint256) {
        return _bidReservation(volume, price, denominator);
    }

    function _applyInventoryProceeds(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bucketId,
        bytes32 marketId,
        address collateralToken,
        uint256 collateralOut
    ) private returns (uint256 seniorRepaid, uint256 fundingPaid, uint256 bucketProfit) {
        LibRiskEngine.accrueConfiguredFunding(state, bucketId);
        uint256 seniorDebt = state.mloBucketMarketSeniorDebt[bucketId][marketId];
        seniorRepaid = collateralOut < seniorDebt ? collateralOut : seniorDebt;
        if (seniorRepaid != 0) {
            _repaySenior(bucketId, seniorRepaid);
            state.mloBucketMarketSeniorDebt[bucketId][marketId] = seniorDebt - seniorRepaid;
            LibRiskEngine.repayDebt(state, bucketId, seniorRepaid);
        }
        uint256 remaining = collateralOut - seniorRepaid;
        fundingPaid = LibMLOFunding.payFromProceeds(state, bucketId, collateralToken, remaining);
        bucketProfit = remaining - fundingPaid;
        if (bucketProfit != 0) LibMarginAccount.recordProfitTrusted(state, bucketId, bucketProfit);
    }

    function _requireInventoryMarket(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bucketId,
        bytes32 marketId,
        bool requireResolved
    ) private view returns (LibEveMarket.Market storage market) {
        market = state.markets[marketId];
        if (market.marketId != marketId || state.mloInventoryVaults[bucketId][marketId] == address(0)) {
            revert IMLOPredictionAdapterFacet.MLOInventoryNotFound(bucketId, marketId);
        }
        bool resolved = LibMLOMarket.isResolved(state, market);
        if (requireResolved && !resolved) revert IMLOPredictionAdapterFacet.MLOInventoryMarketUnresolved(marketId);
        if (!requireResolved && resolved) revert IMLOPredictionAdapterFacet.MLOInventoryMarketResolved(marketId);
    }

    function _repaySenior(bytes32 bucketId, uint256 assets) private {
        LibSeniorCapital.repayActiveExposure(LibSeniorCapital.s(), bucketId, assets);
    }

    function _bidReservation(uint256 volume, uint256 price, uint256 denominator)
        private
        pure
        returns (uint256 reservation)
    {
        reservation = Math.mulDiv(volume, price, denominator, Math.Rounding.Ceil);
    }

    function _packCurve(LibEveMarket.Book storage book, uint128 startPrice, uint128 endPrice, uint24 durationMinutes)
        private
        view
        returns (uint256 packed)
    {
        if (startPrice > type(uint72).max || endPrice > type(uint72).max) {
            revert Errors.InvalidAmount(startPrice > type(uint72).max ? startPrice : endPrice);
        }
        uint8 tickPresetId = LibBookPricing.resolveCurveTickPreset(book, LibCurvePacking.DEFAULT_TICK_PRESET_SENTINEL);
        packed =
            LibCurvePacking.pack(uint72(startPrice), uint72(endPrice), durationMinutes, 0, tickPresetId, bytes32(0));
        LibBookPricing.validateTick(book, packed, startPrice);
        LibBookPricing.validateTick(book, packed, endPrice);
    }

    function _enforceCurveExpiry(
        LibEveMarket.Book storage book,
        LibEveMarket.Market storage market,
        QuoteEnvelopeTypes.StoredQuoteEnvelope storage envelope,
        uint24 durationMinutes,
        uint256 startTime
    ) private view {
        uint256 proposedExpiry = startTime + (uint256(durationMinutes) * 60);
        uint64 marketDeadline = book.expiryTime < market.expiryTime ? book.expiryTime : market.expiryTime;
        uint64 maximumExpiry = envelope.expiresAt < marketDeadline ? envelope.expiresAt : marketDeadline;
        if (proposedExpiry > maximumExpiry) {
            revert Errors.ExpiryTooLate(
                proposedExpiry > type(uint64).max ? type(uint64).max : uint64(proposedExpiry), maximumExpiry
            );
        }
    }

    function _isExecutableMLOBook(LibEveMarket.Book storage book, LibEveMarket.Market storage market)
        private
        view
        returns (bool)
    {
        return book.active && book.lifecycle == LibEveMarket.BookLifecycle.ACTIVE && block.timestamp < book.expiryTime
            && block.timestamp < market.expiryTime && LibCLOBBook.canExecuteMarketBook(market);
    }

    function _requireSupportedBook(LibEveMarket.EveMarketStorage storage state, LibEveMarket.Book storage book)
        private
        view
        returns (LibEveMarket.Market storage market)
    {
        if (
            book.marketId == bytes32(0) || book.assetType != LibEveMarket.BookAssetType.ERC1155
                || book.pricingMode != LibEveMarket.BookPricingMode.PREDICTION_PAYOUT
        ) revert IMLOPredictionAdapterFacet.MLOUnsupportedBook(book.bookId);
        market = LibMarketAccess.requireTradingMarket(state, book.marketId);
        (, uint8 outcomeIndex, uint8 outcomeCount) = LibMLOScenarioRisk.contextForBook(state, book.bookId);
        if (outcomeCount != LibMLOMarket.outcomeCount(state, book.marketId)) {
            revert IMLOPredictionAdapterFacet.MLOUnsupportedBook(book.bookId);
        }
        if (book.quoteToken != market.collateralToken) {
            revert IMLOPredictionAdapterFacet.MLOUnsupportedBook(book.bookId);
        }
        if (book.baseToken != market.positionToken) {
            revert IMLOPredictionAdapterFacet.MLOUnsupportedBook(book.bookId);
        }
        uint256 expectedPositionId = LibMLOMarket.positionId(state, market, outcomeIndex);
        if (book.baseTokenId != expectedPositionId) {
            revert IMLOPredictionAdapterFacet.MLOUnsupportedBook(book.bookId);
        }
        if (
            market.positionTokenType != LibEveMarket.PositionTokenType.CTF
                && market.positionTokenType != LibEveMarket.PositionTokenType.EVES_POSITION
        ) revert IMLOPredictionAdapterFacet.MLOUnsupportedBook(book.bookId);
    }

    function _enforceSeniorAsset(LibEveMarket.EveMarketStorage storage state, address expectedAsset, bytes32 bookId)
        private
        view
    {
        if (state.marginAsset != expectedAsset) {
            revert IMLOPredictionAdapterFacet.MLOUnsupportedBook(bookId);
        }
    }

    function _enforceCanonicalMLOConfig(LibEveMarket.EveMarketStorage storage state) private view {
        address asset = state.marginAsset;
        address insuranceFund = state.mloInsuranceFund;
        if (asset == address(0) || asset.code.length == 0) {
            revert IMLOPredictionAdapterFacet.InvalidMLOCollateral(asset);
        }
        if (insuranceFund == address(0) || insuranceFund.code.length == 0) {
            revert IMLOPredictionAdapterFacet.InvalidMLOInsuranceFund(insuranceFund);
        }

        bytes32 kind;
        address core;
        try IStaticsDollar(asset).coreTokenKind() returns (bytes32 tokenKind) {
            kind = tokenKind;
        } catch {
            revert IMLOPredictionAdapterFacet.InvalidMLOCollateral(asset);
        }
        try IStaticsDollar(asset).pool() returns (address pool_) {
            core = pool_;
        } catch {
            revert IMLOPredictionAdapterFacet.InvalidMLOCollateral(asset);
        }
        if (kind != STATICS_DOLLAR_KIND || core == address(0) || core.code.length == 0) {
            revert IMLOPredictionAdapterFacet.InvalidMLOCollateral(asset);
        }
        address configuredCore = state.config.staticsDollarCore;
        if (configuredCore != core) {
            revert IMLOPredictionAdapterFacet.InvalidMLOCollateral(asset);
        }
        try IStaticsDollarCore(core).staticsDollar() returns (address canonicalAsset) {
            if (canonicalAsset != asset) revert IMLOPredictionAdapterFacet.InvalidMLOCollateral(asset);
        } catch {
            revert IMLOPredictionAdapterFacet.InvalidMLOCollateral(asset);
        }

        IMLOInsuranceFund fund = IMLOInsuranceFund(insuranceFund);
        if (fund.asset() != asset || fund.governance() != address(this) || fund.riskManager() != address(this)) {
            revert IMLOPredictionAdapterFacet.InvalidMLOInsuranceFund(insuranceFund);
        }
    }

    function _requireEnvelope(LibEveMarket.EveMarketStorage storage state, uint256 envelopeId)
        private
        view
        returns (QuoteEnvelopeTypes.StoredQuoteEnvelope storage envelope)
    {
        envelope = state.quoteEnvelopes[envelopeId];
        if (envelope.operator == address(0)) revert IQuoteEnvelopeFacet.QuoteEnvelopeNotFound(envelopeId);
    }

    function _requireMLOCurve(LibEveMarket.EveMarketStorage storage state, uint256 curveId)
        private
        view
        returns (LibEveMarket.StoredCurve storage curve)
    {
        curve = state.curves[curveId];
        if (state.mloCurveEnvelopeIds[curveId] == 0) {
            revert IMLOPredictionAdapterFacet.MLOAdapterCurveNotFound(curveId);
        }
        if (!curve.active) revert Errors.CurveNotActive(curveId);
    }

    function _curveEnvelopeId(LibEveMarket.EveMarketStorage storage state, uint256 curveId)
        private
        view
        returns (uint256 envelopeId)
    {
        envelopeId = state.mloCurveEnvelopeIds[curveId];
        if (envelopeId == 0) revert IMLOPredictionAdapterFacet.MLOAdapterCurveNotFound(curveId);
    }

    function _enforceEnvelopeOperator(QuoteEnvelopeTypes.StoredQuoteEnvelope storage envelope) private view {
        if (msg.sender != envelope.operator) {
            revert IQuoteEnvelopeFacet.NotQuoteEnvelopeOperator(msg.sender, envelope.operator);
        }
    }

    function _enforceEnvelopeActiveAndFresh(uint256 envelopeId, QuoteEnvelopeTypes.StoredQuoteEnvelope storage envelope)
        private
        view
    {
        if (!envelope.active) revert IQuoteEnvelopeFacet.QuoteEnvelopeInactive(envelopeId);
        if (block.timestamp >= envelope.expiresAt) {
            revert IQuoteEnvelopeFacet.QuoteEnvelopeExpired(envelopeId, envelope.expiresAt);
        }
    }
}
