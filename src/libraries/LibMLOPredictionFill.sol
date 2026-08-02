// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {IMLOPredictionAdapterFacet} from "../interfaces/IMLOPredictionAdapterFacet.sol";
import {IQuoteEnvelopeFacet} from "../interfaces/IQuoteEnvelopeFacet.sol";
import {MLOInventoryVault} from "../MLOInventoryVault.sol";
import {CurveCLOBTypes} from "../types/CurveCLOBTypes.sol";
import {MLOPredictionTypes} from "../types/MLOPredictionTypes.sol";
import {ProductAdapterTypes} from "../types/ProductAdapterTypes.sol";
import {QuoteEnvelopeTypes} from "../types/QuoteEnvelopeTypes.sol";
import {Errors} from "./Errors.sol";
import {Events} from "./Events.sol";
import {LibBookPricing} from "./LibBookPricing.sol";
import {LibBuyExecution} from "./LibBuyExecution.sol";
import {LibEveMarket} from "./LibEveMarket.sol";
import {LibMLOMarket} from "./LibMLOMarket.sol";
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
        uint256[] retainedTokenIds;
        uint8 positionTokenType;
        uint128 grossCost;
        uint128 inventoryUsed;
        uint128 manufacturedShares;
        uint128 seniorDeployed;
        uint128 seniorReleased;
        uint128 seniorRepaid;
        uint128 fundingPaid;
        uint128 bucketProfit;
        uint8 outcomeIndex;
        uint8 outcomeCount;
    }

    function fillAskCurve(
        LibEveMarket.EveMarketStorage storage state,
        MLOPredictionTypes.MLOAskFillRequest memory request
    ) internal returns (MLOPredictionTypes.MLOAskFillResult memory result) {
        uint256 envelopeId = state.mloCurveEnvelopeIds[request.curveId];
        if (envelopeId != 0) {
            IMLOPredictionAdapterFacet(address(this))
                .synchronizeMLOBucketState(state.quoteEnvelopes[envelopeId].bucketId);
        }
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
            && LibRiskEngine.canIncreaseRiskForBook(state, envelope.bucketId, envelope.bookId);
    }

    function _settleAskFill(
        LibEveMarket.EveMarketStorage storage state,
        MLOPredictionTypes.MLOAskFillRequest memory request,
        LibBuyExecution.Quote memory quote
    ) private returns (MLOPredictionTypes.MLOAskFillResult memory result) {
        SettlementContext memory context = _settlementContext(state, request, quote);
        LibEveMarket.Book storage book = state.books[context.bookId];
        IERC20 quoteToken = IERC20(context.quoteToken);

        if (quote.collateralUsed != 0 && !request.fundingIsEscrowed) {
            uint256 balanceBefore = quoteToken.balanceOf(address(this));
            quoteToken.safeTransferFrom(request.fundingSource, address(this), quote.collateralUsed);
            uint256 received = quoteToken.balanceOf(address(this)) - balanceBefore;
            if (received != quote.collateralUsed) {
                revert IMLOPredictionAdapterFacet.MLOCollateralNonExactTransfer(quote.collateralUsed, received);
            }
        }

        IMLOPredictionAdapterFacet(address(this))
            .applyMLOAskFillState(
                MLOPredictionTypes.MLOAskFillStateParams({
                    curveId: request.curveId,
                    sharesOut: quote.sharesOut,
                    price: quote.price,
                    collateralUsed: quote.collateralUsed,
                    feePaid: quote.fee,
                    backing: MLOPredictionTypes.MLOAskBacking({
                        inventoryUsed: context.inventoryUsed,
                        manufacturedShares: context.manufacturedShares,
                        seniorDeployed: context.seniorDeployed,
                        seniorReleased: context.seniorReleased,
                        seniorRepaid: context.seniorRepaid,
                        fundingPaid: context.fundingPaid,
                        bucketProfit: context.bucketProfit
                    })
                })
            );

        address vault = state.mloInventoryVaults[context.metadata.bucketId][context.marketId];
        if (context.manufacturedShares != 0) {
            vault = _inventoryVault(state, context.metadata.bucketId, context.marketId);
        }
        IMLOPredictionAdapterFacet(address(this))
            .executeMLOAskAssetSettlement(
                MLOPredictionTypes.MLOAskAssetSettlementParams({
                    collateralToken: context.collateralToken,
                    positionToken: context.positionToken,
                    inventoryVault: vault,
                    receiver: request.receiver,
                    bucketId: context.metadata.bucketId,
                    bookId: context.bookId,
                    conditionId: context.conditionId,
                    resolutionId: context.resolutionId,
                    soldPositionId: context.baseTokenId,
                    retainedPositionIds: context.retainedTokenIds,
                    positionTokenType: context.positionTokenType,
                    inventoryUsed: context.inventoryUsed,
                    manufacturedShares: context.manufacturedShares,
                    seniorDeployed: context.seniorDeployed,
                    seniorReleased: context.seniorReleased,
                    seniorRepaid: context.seniorRepaid,
                    fundingPaid: context.fundingPaid,
                    feePaid: quote.fee
                })
            );
        IMLOPredictionAdapterFacet(address(this))
            .mergeAvailableMLOCompleteSet(context.metadata.bucketId, context.marketId);

        result = MLOPredictionTypes.MLOAskFillResult({
            fill: CurveCLOBTypes.FillBestResult({
                sharesOut: quote.sharesOut,
                collateralUsed: quote.collateralUsed,
                feePaid: quote.fee,
                averagePrice: LibBookPricing.averagePrice(book, quote.collateralUsed, quote.sharesOut),
                unfilledCollateral: request.collateralIn - quote.collateralUsed
            }),
            envelopeId: context.envelopeId,
            bucketId: context.metadata.bucketId,
            seniorDeployed: context.seniorDeployed,
            seniorReleased: context.seniorReleased,
            seniorRepaid: context.seniorRepaid,
            inventoryUsed: context.inventoryUsed,
            retainedInventory: context.manufacturedShares,
            makerProfit: context.bucketProfit
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
            context.inventoryUsed,
            context.seniorDeployed,
            context.seniorReleased,
            context.seniorRepaid,
            context.manufacturedShares,
            context.bucketProfit
        );
    }

    function _settlementContext(
        LibEveMarket.EveMarketStorage storage state,
        MLOPredictionTypes.MLOAskFillRequest memory request,
        LibBuyExecution.Quote memory quote
    ) private returns (SettlementContext memory context) {
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

        if (curve.maker == request.taker) {
            revert Errors.SelfFillNotAllowed(request.curveId, curve.maker, request.taker);
        }
        if (!isExecutableMLOAsk(state, request.curveId)) {
            revert Errors.AdapterCurveInactive(request.curveId);
        }
        if (quote.sharesOut > envelope.currentVolume) {
            revert IQuoteEnvelopeFacet.InvalidQuoteEnvelopeVolume(quote.sharesOut, envelope.currentVolume);
        }
        uint128 grossCost = quote.collateralUsed - quote.fee;
        MLOPredictionTypes.MLOAskBacking memory backing = IMLOPredictionAdapterFacet(address(this))
            .prepareMLOAskBacking(request.curveId, quote.sharesOut, grossCost, quote.price);

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
            retainedTokenIds: _retainedPositionIds(state, market, envelope.outcomeIndex, envelope.outcomeCount),
            positionTokenType: uint8(market.positionTokenType),
            grossCost: grossCost,
            inventoryUsed: backing.inventoryUsed,
            manufacturedShares: backing.manufacturedShares,
            seniorDeployed: backing.seniorDeployed,
            seniorReleased: backing.seniorReleased,
            seniorRepaid: backing.seniorRepaid,
            fundingPaid: backing.fundingPaid,
            bucketProfit: backing.bucketProfit,
            outcomeIndex: envelope.outcomeIndex,
            outcomeCount: envelope.outcomeCount
        });
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

    function _retainedPositionIds(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.Market storage market,
        uint8 soldOutcome,
        uint8 outcomeCount
    ) private view returns (uint256[] memory retainedIds) {
        retainedIds = new uint256[](outcomeCount - 1);
        uint256 writeIndex;
        for (uint8 outcome; outcome < outcomeCount; ++outcome) {
            if (outcome == soldOutcome) continue;
            retainedIds[writeIndex++] = LibMLOMarket.positionId(state, market, outcome);
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
