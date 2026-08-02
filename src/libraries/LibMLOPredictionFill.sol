// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC1155} from "../../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";

import {IMLOPredictionAdapterFacet} from "../interfaces/IMLOPredictionAdapterFacet.sol";
import {IQuoteEnvelopeFacet} from "../interfaces/IQuoteEnvelopeFacet.sol";
import {ISeniorCapitalPool} from "../interfaces/ISeniorCapitalPool.sol";
import {MLOInventoryVault} from "../MLOInventoryVault.sol";
import {CurveCLOBTypes} from "../types/CurveCLOBTypes.sol";
import {MLOPredictionTypes} from "../types/MLOPredictionTypes.sol";
import {ProductAdapterTypes} from "../types/ProductAdapterTypes.sol";
import {QuoteEnvelopeTypes} from "../types/QuoteEnvelopeTypes.sol";
import {Errors} from "./Errors.sol";
import {Events} from "./Events.sol";
import {LibBookAccounting} from "./LibBookAccounting.sol";
import {LibBookPricing} from "./LibBookPricing.sol";
import {LibBuyExecution} from "./LibBuyExecution.sol";
import {LibCTF} from "./LibCTF.sol";
import {LibEveMarket} from "./LibEveMarket.sol";
import {LibMarkOracle} from "./LibMarkOracle.sol";
import {LibProductAdapter} from "./LibProductAdapter.sol";
import {LibRiskEngine} from "./LibRiskEngine.sol";

library LibMLOPredictionFill {
    using SafeERC20 for IERC20;

    struct SettlementContext {
        ProductAdapterTypes.AdapterCurveMetadata metadata;
        uint256 envelopeId;
        bytes32 bookId;
        bytes32 marketId;
        address maker;
        address quoteToken;
        address collateralToken;
        address positionToken;
        bytes32 conditionId;
        bytes32 resolutionId;
        uint256 baseTokenId;
        uint256 retainedTokenId;
        bool isYesSide;
        uint128 grossCost;
        uint128 openRiskConsumed;
        uint128 positionRiskAdded;
    }

    function fillAskCurve(LibEveMarket.EveMarketStorage storage state, MLOPredictionTypes.MLOFillRequest memory request)
        public
        returns (MLOPredictionTypes.FillResult memory result)
    {
        LibBuyExecution.Quote memory quote = LibBuyExecution.prepareExecution(
            state, request.curveId, request.collateralIn, request.expectedGeneration, request.expectedCommitment
        );
        if (quote.sharesOut < request.minSharesOut) {
            revert Errors.SlippageExceeded(quote.sharesOut, request.minSharesOut);
        }
        if (quote.sharesOut == 0) {
            result.fill.unfilledCollateral = request.collateralIn;
            return result;
        }

        result = _settleAskFill(state, request, quote);
    }

    function isExecutableMLOAsk(LibEveMarket.EveMarketStorage storage state, uint256 curveId)
        internal
        view
        returns (bool)
    {
        ProductAdapterTypes.AdapterCurveMetadata storage metadata = state.adapterCurveMetadata[curveId];
        if (
            metadata.backingKind != ProductAdapterTypes.CurveBackingKind.Adapter
                || metadata.adapterKind != ProductAdapterTypes.ProductAdapterKind.MLOPrediction || !metadata.active
        ) {
            return false;
        }
        uint256 envelopeId = state.mloCurveEnvelopeIds[curveId];
        QuoteEnvelopeTypes.StoredQuoteEnvelope storage envelope = state.quoteEnvelopes[envelopeId];
        LibEveMarket.StoredCurve storage curve = state.curves[curveId];
        return curve.active && curve.curveSide == LibEveMarket.CurveSide.ASK && envelope.active
            && block.timestamp < envelope.expiresAt && envelope.currentVolume != 0
            && state.mloCurveSeniorReserved[curveId] != 0
            && LibRiskEngine.canIncreaseRiskForBook(state, envelope.bucketId, envelope.bookId);
    }

    function _settleAskFill(
        LibEveMarket.EveMarketStorage storage state,
        MLOPredictionTypes.MLOFillRequest memory request,
        LibBuyExecution.Quote memory quote
    ) private returns (MLOPredictionTypes.FillResult memory result) {
        SettlementContext memory context = _settlementContext(state, request, quote);
        LibEveMarket.Book storage book = state.books[context.bookId];
        IERC20 quoteToken = IERC20(context.quoteToken);
        LibBookAccounting.FeeShares memory fees = LibBookAccounting.feeSharesForBook(state, book, quote.fee);

        if (quote.collateralUsed != 0 && !request.payerIsEscrowed) {
            quoteToken.safeTransferFrom(request.payer, address(this), quote.collateralUsed);
        }

        _writeFillState(state, request.curveId, context, quote);

        address seniorPool = _curveSeniorPool(state, request.curveId);
        ISeniorCapitalPool(seniorPool)
            .deployReservedCapitalForBucket(context.metadata.bucketId, address(this), quote.sharesOut);
        IERC20(context.collateralToken).forceApprove(context.positionToken, quote.sharesOut);
        LibCTF.prepareMarketCondition(context.positionToken, context.resolutionId);
        LibCTF.splitCollateral(context.positionToken, context.collateralToken, context.conditionId, quote.sharesOut);

        if (context.grossCost != 0) {
            quoteToken.forceApprove(seniorPool, context.grossCost);
            ISeniorCapitalPool(seniorPool).repayActiveExposureForBucket(context.metadata.bucketId, context.grossCost);
        }
        LibBookAccounting.payBookQuoteFees(state, book, fees);

        IERC1155(context.positionToken)
            .safeTransferFrom(
                address(this),
                _inventoryVault(state, context.metadata.bucketId, context.marketId),
                context.retainedTokenId,
                quote.sharesOut,
                ""
            );
        IERC1155(context.positionToken)
            .safeTransferFrom(address(this), request.receiver, context.baseTokenId, quote.sharesOut, "");

        result = MLOPredictionTypes.FillResult({
            fill: CurveCLOBTypes.FillBestResult({
                sharesOut: quote.sharesOut,
                collateralUsed: quote.collateralUsed,
                feePaid: quote.fee,
                averagePrice: LibBookPricing.averagePrice(book, quote.collateralUsed, quote.sharesOut),
                unfilledCollateral: request.collateralIn - quote.collateralUsed
            }),
            envelopeId: context.envelopeId,
            bucketId: context.metadata.bucketId,
            seniorDeployed: quote.sharesOut,
            seniorRepaid: context.grossCost,
            retainedInventory: quote.sharesOut
        });

        emit Events.CurveFilled(
            request.curveId, context.maker, request.receiver, quote.collateralUsed, quote.sharesOut, quote.fee
        );
        emit IMLOPredictionAdapterFacet.MLOAskCurveFilled(
            request.curveId,
            context.envelopeId,
            context.metadata.bucketId,
            request.receiver,
            quote.collateralUsed,
            quote.sharesOut,
            quote.fee,
            quote.sharesOut
        );
    }

    function _settlementContext(
        LibEveMarket.EveMarketStorage storage state,
        MLOPredictionTypes.MLOFillRequest memory request,
        LibBuyExecution.Quote memory quote
    ) private view returns (SettlementContext memory context) {
        ProductAdapterTypes.AdapterCurveMetadata memory metadata =
            LibProductAdapter.requireActiveAdapterCurve(state, request.curveId);
        if (metadata.adapterKind != ProductAdapterTypes.ProductAdapterKind.MLOPrediction) {
            revert Errors.InvalidProductAdapter(uint8(metadata.adapterKind));
        }

        uint256 envelopeId = _curveEnvelopeId(state, request.curveId);
        QuoteEnvelopeTypes.StoredQuoteEnvelope storage envelope = _requireEnvelope(state, envelopeId);
        LibEveMarket.StoredCurve storage curve = state.curves[request.curveId];
        LibEveMarket.Book storage book = state.books[curve.bookId];
        LibEveMarket.Market storage market = state.markets[book.marketId];

        if (curve.maker == request.payer) {
            revert Errors.SelfFillNotAllowed(request.curveId, curve.maker, request.payer);
        }
        if (!isExecutableMLOAsk(state, request.curveId)) {
            revert Errors.AdapterCurveInactive(request.curveId);
        }
        if (quote.sharesOut > envelope.currentVolume) {
            revert IQuoteEnvelopeFacet.InvalidQuoteEnvelopeVolume(quote.sharesOut, envelope.currentVolume);
        }
        if (quote.sharesOut > state.mloCurveSeniorReserved[request.curveId]) {
            revert IMLOPredictionAdapterFacet.MLOInsufficientSeniorReservation(
                quote.sharesOut, state.mloCurveSeniorReserved[request.curveId]
            );
        }

        uint128 grossCost = quote.collateralUsed - quote.fee;
        uint128 openRiskConsumed = _openRiskForFill(book.priceDenominator, envelope, quote.sharesOut);
        uint128 positionRiskAdded = uint128(uint256(quote.sharesOut) - grossCost);

        context = SettlementContext({
            metadata: metadata,
            envelopeId: envelopeId,
            bookId: curve.bookId,
            marketId: book.marketId,
            maker: curve.maker,
            quoteToken: book.quoteToken,
            collateralToken: market.collateralToken,
            positionToken: market.positionToken,
            conditionId: market.conditionId,
            resolutionId: market.resolutionId,
            baseTokenId: book.baseTokenId,
            retainedTokenId: book.isYesSide ? market.noPositionId : market.yesPositionId,
            isYesSide: book.isYesSide,
            grossCost: grossCost,
            openRiskConsumed: openRiskConsumed,
            positionRiskAdded: positionRiskAdded
        });
    }

    function _writeFillState(
        LibEveMarket.EveMarketStorage storage state,
        uint256 curveId,
        SettlementContext memory context,
        LibBuyExecution.Quote memory quote
    ) private {
        LibEveMarket.StoredCurve storage curve = state.curves[curveId];
        QuoteEnvelopeTypes.StoredQuoteEnvelope storage envelope = state.quoteEnvelopes[context.envelopeId];

        curve.remainingVolume -= quote.sharesOut;
        envelope.currentVolume -= quote.sharesOut;
        state.mloCurveSeniorReserved[curveId] -= quote.sharesOut;

        uint128 releasedOpenRisk = context.openRiskConsumed - context.positionRiskAdded;
        if (context.positionRiskAdded != 0) {
            LibRiskEngine.moveOpenOrderToPositionRisk(state, context.metadata.bucketId, context.positionRiskAdded);
            state.mloBucketMarketPositionRisk[context.metadata.bucketId][context.marketId] += context.positionRiskAdded;
        }
        if (releasedOpenRisk != 0) {
            LibRiskEngine.releaseOpenOrderRisk(state, context.metadata.bucketId, releasedOpenRisk);
        }
        envelope.reservedRisk -= context.openRiskConsumed;
        if (context.positionRiskAdded != 0) {
            LibRiskEngine.recordDebtTrusted(state, context.metadata.bucketId, context.positionRiskAdded);
            state.mloBucketMarketSeniorDebt[context.metadata.bucketId][context.marketId] += context.positionRiskAdded;
            _bindBucketMarketSeniorPool(
                state, context.metadata.bucketId, context.marketId, _curveSeniorPool(state, curveId)
            );
        }

        if (context.isYesSide) {
            state.mloBucketNoInventory[context.metadata.bucketId][context.marketId] += quote.sharesOut;
        } else {
            state.mloBucketYesInventory[context.metadata.bucketId][context.marketId] += quote.sharesOut;
        }

        LibEveMarket.Book storage book = state.books[context.bookId];
        LibBookAccounting.FeeShares memory fees = LibBookAccounting.feeSharesForBook(state, book, quote.fee);
        LibBookAccounting.recordBookAndMarketFill(
            state, book, curve.maker, quote.price, quote.collateralUsed, quote.fee, fees
        );
        LibMarkOracle.recordFill(state, book, quote.price, quote.sharesOut, context.grossCost);
    }

    function _openRiskForFill(
        uint128 priceDenominator,
        QuoteEnvelopeTypes.StoredQuoteEnvelope memory envelope,
        uint128 sharesOut
    ) private pure returns (uint128 openRisk) {
        uint128 complement = priceDenominator - envelope.minPrice;
        openRisk = uint128((uint256(sharesOut) * uint256(complement)) / uint256(priceDenominator));
        if (openRisk > envelope.reservedRisk) {
            openRisk = envelope.reservedRisk;
        }
    }

    function _inventoryVault(LibEveMarket.EveMarketStorage storage state, bytes32 bucketId, bytes32 marketId)
        private
        returns (address vault)
    {
        vault = state.mloInventoryVaults[bucketId][marketId];
        if (vault != address(0)) {
            return vault;
        }

        vault = address(new MLOInventoryVault(address(this)));
        state.mloInventoryVaults[bucketId][marketId] = vault;
        emit IMLOPredictionAdapterFacet.MLOInventoryVaultCreated(bucketId, marketId, vault);
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

    function _bindBucketMarketSeniorPool(
        LibEveMarket.EveMarketStorage storage state,
        bytes32 bucketId,
        bytes32 marketId,
        address seniorPool
    ) private {
        address existing = state.mloBucketMarketSeniorPools[bucketId][marketId];
        if (existing == address(0)) {
            state.mloBucketMarketSeniorPools[bucketId][marketId] = seniorPool;
            return;
        }
        if (existing != seniorPool) {
            revert IMLOPredictionAdapterFacet.MLOSeniorPoolMismatch(existing, seniorPool);
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
}
