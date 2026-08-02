// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {IMLOPredictionAdapterFacet} from "../interfaces/IMLOPredictionAdapterFacet.sol";
import {IQuoteEnvelopeFacet} from "../interfaces/IQuoteEnvelopeFacet.sol";
import {ISeniorCapitalPool} from "../interfaces/ISeniorCapitalPool.sol";
import {MLOInventoryVault} from "../MLOInventoryVault.sol";
import {MLOPredictionTypes} from "../types/MLOPredictionTypes.sol";
import {MarginTypes} from "../types/MarginTypes.sol";
import {ProductAdapterTypes} from "../types/ProductAdapterTypes.sol";
import {QuoteEnvelopeTypes} from "../types/QuoteEnvelopeTypes.sol";
import {Errors} from "./Errors.sol";
import {Events} from "./Events.sol";
import {LibBookPricing} from "./LibBookPricing.sol";
import {LibCurveMath} from "./LibCurveMath.sol";
import {LibCurvePacking} from "./LibCurvePacking.sol";
import {LibEveMarket} from "./LibEveMarket.sol";
import {LibMarginAccount} from "./LibMarginAccount.sol";
import {LibMarketAccess} from "./LibMarketAccess.sol";
import {LibProductAdapter} from "./LibProductAdapter.sol";
import {LibQuoteEnvelope} from "./LibQuoteEnvelope.sol";
import {LibRiskEngine} from "./LibRiskEngine.sol";

library LibMLOPredictionAdapter {
    using SafeERC20 for IERC20;

    function setSeniorCapitalPool(LibEveMarket.EveMarketStorage storage state, address pool) internal {
        if (pool == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (pool.code.length == 0) {
            revert IMLOPredictionAdapterFacet.InvalidSeniorCapitalPool(pool);
        }

        address previous = state.config.seniorCapitalPool;
        state.config.seniorCapitalPool = pool;
        emit IMLOPredictionAdapterFacet.SeniorCapitalPoolSet(previous, pool);
    }

    function createAskCurve(
        LibEveMarket.EveMarketStorage storage state,
        MLOPredictionTypes.CreateMLOAskCurveParams calldata params
    ) internal returns (uint256 curveId) {
        address seniorPool = requireSeniorPool(state);
        QuoteEnvelopeTypes.StoredQuoteEnvelope storage envelope = _requireEnvelope(state, params.envelopeId);
        _enforceEnvelopeOperator(envelope);
        _enforceEnvelopeActiveAndFresh(params.envelopeId, envelope);
        if (envelope.side != uint8(LibEveMarket.CurveSide.ASK)) {
            revert IMLOPredictionAdapterFacet.MLOUnsupportedCurveSide(envelope.side);
        }
        if (state.mloEnvelopeCurveIds[params.envelopeId] != 0) {
            revert IMLOPredictionAdapterFacet.MLOEnvelopeAlreadyBound(
                params.envelopeId, state.mloEnvelopeCurveIds[params.envelopeId] - 1
            );
        }

        LibEveMarket.Book storage book = state.books[envelope.bookId];
        LibEveMarket.Market storage market = _requireSupportedBook(state, book);
        _enforceSeniorAsset(seniorPool, market.collateralToken, envelope.bookId);

        uint256 packed = _packCurve(book, envelope.currentStartPrice, envelope.currentEndPrice, params.durationMinutes);
        curveId = state.nextCurveId++;
        LibEveMarket.StoredCurve storage curve = state.curves[curveId];
        curve.packed = packed;
        curve.remainingVolume = envelope.currentVolume;
        curve.createdAt = uint64(block.timestamp);
        curve.generation = 1;
        curve.active = true;
        curve.isYesSide = book.isYesSide;
        curve.curveSide = LibEveMarket.CurveSide.ASK;
        curve.maker = envelope.operator;
        curve.bookId = envelope.bookId;
        state.bookCurveIds[envelope.bookId].push(curveId);
        book.curveCount += 1;
        market.curveCount += 1;

        state.mloCurveEnvelopeIds[curveId] = params.envelopeId;
        state.mloEnvelopeCurveIds[params.envelopeId] = curveId + 1;
        state.mloCurveSeniorReserved[curveId] = envelope.maxVolume;
        state.mloCurveSeniorPools[curveId] = seniorPool;
        ISeniorCapitalPool(seniorPool).reserveCapitalForBucket(envelope.bucketId, envelope.maxVolume);

        LibProductAdapter.setAdapterCurveMetadata(
            state,
            curveId,
            ProductAdapterTypes.ProductAdapterKind.MLOPrediction,
            envelope.bucketId,
            state.marginBuckets[envelope.bucketId].riskDomainId,
            bytes32(params.envelopeId)
        );

        emit Events.CurvePosted(book.marketId, curveId, envelope.operator, book.isYesSide, packed);
        emit Events.BookCurvePosted(
            envelope.bookId,
            book.marketId,
            curveId,
            envelope.operator,
            book.isYesSide,
            uint8(LibEveMarket.CurveSide.ASK),
            packed
        );
        emit IMLOPredictionAdapterFacet.MLOAskCurveCreated(curveId, params.envelopeId, envelope.bucketId);
    }

    function updateAskCurve(
        LibEveMarket.EveMarketStorage storage state,
        MLOPredictionTypes.UpdateMLOAskCurveParams calldata params
    ) internal returns (uint32 curveGeneration) {
        LibEveMarket.StoredCurve storage curve = _requireMLOCurve(state, params.curveId);
        if (curve.generation != params.expectedCurveGeneration) {
            revert Errors.GenerationMismatch(params.expectedCurveGeneration, curve.generation);
        }

        uint256 envelopeId = _curveEnvelopeId(state, params.curveId);
        QuoteEnvelopeTypes.StoredQuoteEnvelope storage envelope = _requireEnvelope(state, envelopeId);
        if (envelope.generation != params.expectedEnvelopeGeneration) {
            revert IMLOPredictionAdapterFacet.MLOEnvelopeGenerationMismatch(
                params.expectedEnvelopeGeneration, envelope.generation
            );
        }
        _enforceEnvelopeOperator(envelope);

        LibQuoteEnvelope.updateEnvelope(state, envelopeId, params.envelopeUpdate);
        if (params.envelopeUpdate.volume > state.mloCurveSeniorReserved[params.curveId]) {
            revert IMLOPredictionAdapterFacet.MLOInsufficientSeniorReservation(
                params.envelopeUpdate.volume, state.mloCurveSeniorReserved[params.curveId]
            );
        }

        LibEveMarket.Book storage book = state.books[curve.bookId];
        curve.packed = _packCurve(
            book,
            params.envelopeUpdate.startPrice,
            params.envelopeUpdate.endPrice,
            LibCurvePacking.unpack(curve.packed).durationMinutes
        );
        curve.remainingVolume = params.envelopeUpdate.volume;
        curve.generation += 1;
        curveGeneration = curve.generation;

        emit Events.CurveUpdated(params.curveId, curve.packed, curve.generation);
        emit IMLOPredictionAdapterFacet.MLOAskCurveUpdated(params.curveId, envelopeId, curveGeneration);
    }

    function cancelAskCurve(LibEveMarket.EveMarketStorage storage state, uint256 curveId) internal {
        LibEveMarket.StoredCurve storage curve = _requireMLOCurve(state, curveId);
        uint256 envelopeId = _curveEnvelopeId(state, curveId);
        QuoteEnvelopeTypes.StoredQuoteEnvelope storage envelope = _requireEnvelope(state, envelopeId);
        _enforceEnvelopeOperator(envelope);

        uint256 seniorReleased = state.mloCurveSeniorReserved[curveId];
        uint128 riskReleased = envelope.reservedRisk;
        curve.active = false;
        curve.remainingVolume = 0;
        envelope.active = false;
        envelope.currentVolume = 0;
        envelope.reservedRisk = 0;
        curve.generation += 1;
        envelope.generation += 1;
        state.mloCurveSeniorReserved[curveId] = 0;

        if (riskReleased != 0) {
            LibRiskEngine.releaseOpenOrderRisk(state, envelope.bucketId, riskReleased);
        }
        if (seniorReleased != 0) {
            ISeniorCapitalPool(_curveSeniorPool(state, curveId))
                .releaseReservedCapitalForBucket(envelope.bucketId, seniorReleased);
        }

        emit Events.CurveCancelled(curveId);
        emit IQuoteEnvelopeFacet.QuoteEnvelopeCancelled(envelopeId, riskReleased, envelope.generation);
        emit IMLOPredictionAdapterFacet.MLOAskCurveCancelled(curveId, envelopeId, seniorReleased, riskReleased);
    }

    function viewAskCurve(LibEveMarket.EveMarketStorage storage state, uint256 curveId)
        internal
        view
        returns (MLOPredictionTypes.MLOAskCurveView memory view_)
    {
        LibEveMarket.StoredCurve storage curve = state.curves[curveId];
        uint256 envelopeId = state.mloCurveEnvelopeIds[curveId];
        if (envelopeId == 0) {
            revert IMLOPredictionAdapterFacet.MLOAdapterCurveNotFound(curveId);
        }
        QuoteEnvelopeTypes.StoredQuoteEnvelope storage envelope = state.quoteEnvelopes[envelopeId];
        LibEveMarket.Book storage book = state.books[curve.bookId];
        view_ = MLOPredictionTypes.MLOAskCurveView({
            curveId: curveId,
            envelopeId: envelopeId,
            bucketId: envelope.bucketId,
            bookId: curve.bookId,
            marketId: book.marketId,
            isYesSide: curve.isYesSide,
            operator: curve.maker,
            seniorPool: state.mloCurveSeniorPools[curveId],
            remainingVolume: curve.remainingVolume,
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
        inventory = MLOPredictionTypes.MLOInventoryView({
            bucketId: bucketId,
            marketId: marketId,
            vault: state.mloInventoryVaults[bucketId][marketId],
            yesInventory: state.mloBucketYesInventory[bucketId][marketId],
            noInventory: state.mloBucketNoInventory[bucketId][marketId],
            seniorDebt: state.mloBucketMarketSeniorDebt[bucketId][marketId],
            positionRisk: state.mloBucketMarketPositionRisk[bucketId][marketId]
        });
    }

    function settleInventory(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId, bytes32 marketId)
        internal
        returns (MLOPredictionTypes.MLOInventorySettlement memory settlement)
    {
        LibEveMarket.Market storage market = state.markets[marketId];
        if (market.marketId != marketId) {
            revert IMLOPredictionAdapterFacet.MLOInventoryNotFound(bucketId, marketId);
        }
        if (market.outcome == LibEveMarket.MarketOutcome.Unresolved) {
            revert IMLOPredictionAdapterFacet.MLOInventoryMarketUnresolved(marketId);
        }

        address vault = state.mloInventoryVaults[bucketId][marketId];
        uint256 seniorDebt = state.mloBucketMarketSeniorDebt[bucketId][marketId];
        uint256 positionRisk = state.mloBucketMarketPositionRisk[bucketId][marketId];
        if (vault == address(0) || (seniorDebt == 0 && positionRisk == 0)) {
            revert IMLOPredictionAdapterFacet.MLOInventoryNotFound(bucketId, marketId);
        }

        settlement.bucketId = bucketId;
        settlement.marketId = marketId;
        settlement.collateralOut = MLOInventoryVault(vault)
            .redeemToController(market.positionToken, market.collateralToken, market.conditionId);

        address seniorPool = state.mloBucketMarketSeniorPools[bucketId][marketId];
        if (seniorPool == address(0)) {
            revert IMLOPredictionAdapterFacet.SeniorCapitalPoolNotSet();
        }
        uint256 remainingDebt = seniorDebt;
        if (settlement.collateralOut != 0) {
            uint256 repayFromInventory =
                settlement.collateralOut < remainingDebt ? settlement.collateralOut : remainingDebt;
            if (repayFromInventory != 0) {
                _repaySenior(seniorPool, bucketId, market.collateralToken, repayFromInventory);
                remainingDebt -= repayFromInventory;
                settlement.seniorRepaid += repayFromInventory;
            }
        }

        if (remainingDebt != 0) {
            MarginTypes.MarginBucket storage bucket = state.marginBuckets[bucketId];
            uint256 marginAvailable = bucket.marginAllocated;
            settlement.marginUsed = remainingDebt < marginAvailable ? remainingDebt : marginAvailable;
            if (settlement.marginUsed != 0) {
                LibMarginAccount.recordLossTrusted(state, bucketId, settlement.marginUsed);
                _repaySenior(seniorPool, bucketId, market.collateralToken, settlement.marginUsed);
                remainingDebt -= settlement.marginUsed;
                settlement.seniorRepaid += settlement.marginUsed;
            }
        }

        if (remainingDebt != 0) {
            ISeniorCapitalPool(seniorPool).recordRealizedLossForBucket(bucketId, remainingDebt);
            settlement.seniorLoss = remainingDebt;
        }

        uint256 surplus = settlement.collateralOut > seniorDebt ? settlement.collateralOut - seniorDebt : 0;
        if (surplus != 0) {
            LibMarginAccount.recordProfitTrusted(state, bucketId, surplus);
            settlement.bucketProfit = surplus;
        }

        if (seniorDebt != 0) {
            LibRiskEngine.repayDebt(state, bucketId, seniorDebt);
        }
        if (positionRisk != 0) {
            LibRiskEngine.releasePositionRisk(state, bucketId, positionRisk);
        }

        state.mloBucketYesInventory[bucketId][marketId] = 0;
        state.mloBucketNoInventory[bucketId][marketId] = 0;
        state.mloInventoryVaults[bucketId][marketId] = address(0);
        state.mloBucketMarketSeniorDebt[bucketId][marketId] = 0;
        state.mloBucketMarketPositionRisk[bucketId][marketId] = 0;
        state.mloBucketMarketSeniorPools[bucketId][marketId] = address(0);

        emit IMLOPredictionAdapterFacet.MLOInventorySettled(
            bucketId,
            marketId,
            vault,
            settlement.collateralOut,
            settlement.seniorRepaid,
            settlement.marginUsed,
            settlement.seniorLoss,
            settlement.bucketProfit
        );
    }

    function requireSeniorPool(LibEveMarket.EveMarketStorage storage state) internal view returns (address pool) {
        pool = state.config.seniorCapitalPool;
        if (pool == address(0)) {
            revert IMLOPredictionAdapterFacet.SeniorCapitalPoolNotSet();
        }
    }

    function _curveSeniorPool(LibEveMarket.EveMarketStorage storage state, uint256 curveId)
        private
        view
        returns (address seniorPool)
    {
        seniorPool = state.mloCurveSeniorPools[curveId];
        if (seniorPool == address(0)) {
            revert IMLOPredictionAdapterFacet.SeniorCapitalPoolNotSet();
        }
    }

    function _repaySenior(address seniorPool, bytes32 bucketId, address collateralToken, uint256 assets) private {
        IERC20(collateralToken).forceApprove(seniorPool, assets);
        ISeniorCapitalPool(seniorPool).repayActiveExposureForBucket(bucketId, assets);
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
        LibBookPricing.validateTick(book, packed, uint128(startPrice));
        LibBookPricing.validateTick(book, packed, uint128(endPrice));
    }

    function _requireSupportedBook(LibEveMarket.EveMarketStorage storage state, LibEveMarket.Book storage book)
        private
        view
        returns (LibEveMarket.Market storage market)
    {
        if (
            book.marketId == bytes32(0) || book.assetType != LibEveMarket.BookAssetType.ERC1155
                || book.pricingMode != LibEveMarket.BookPricingMode.PREDICTION_PAYOUT
        ) {
            revert IMLOPredictionAdapterFacet.MLOUnsupportedBook(book.bookId);
        }
        market = LibMarketAccess.requireTradingMarket(state, book.marketId);
        LibMarketAccess.requirePositionTokenType(market, LibEveMarket.PositionTokenType.CTF);
        LibMarketAccess.validatePositionIds(market);
        if (book.quoteToken != market.collateralToken || book.baseToken != market.positionToken) {
            revert IMLOPredictionAdapterFacet.MLOUnsupportedBook(book.bookId);
        }
    }

    function _enforceSeniorAsset(address seniorPool, address expectedAsset, bytes32 bookId) private view {
        if (ISeniorCapitalPool(seniorPool).asset() != expectedAsset) {
            revert IMLOPredictionAdapterFacet.MLOUnsupportedBook(bookId);
        }
    }

    function _requireEnvelope(LibEveMarket.EveMarketStorage storage state, uint256 envelopeId)
        private
        view
        returns (QuoteEnvelopeTypes.StoredQuoteEnvelope storage envelope)
    {
        envelope = state.quoteEnvelopes[envelopeId];
        if (envelope.operator == address(0)) {
            revert IQuoteEnvelopeFacet.QuoteEnvelopeNotFound(envelopeId);
        }
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
        if (!curve.active) {
            revert Errors.CurveNotActive(curveId);
        }
    }

    function _curveEnvelopeId(LibEveMarket.EveMarketStorage storage state, uint256 curveId)
        private
        view
        returns (uint256 envelopeId)
    {
        envelopeId = state.mloCurveEnvelopeIds[curveId];
        if (envelopeId == 0) {
            revert IMLOPredictionAdapterFacet.MLOAdapterCurveNotFound(curveId);
        }
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
        if (!envelope.active) {
            revert IQuoteEnvelopeFacet.QuoteEnvelopeInactive(envelopeId);
        }
        if (block.timestamp >= envelope.expiresAt) {
            revert IQuoteEnvelopeFacet.QuoteEnvelopeExpired(envelopeId, envelope.expiresAt);
        }
    }
}
