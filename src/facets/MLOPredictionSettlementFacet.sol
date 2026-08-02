// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {MLOPredictionTypes} from "../types/MLOPredictionTypes.sol";
import {IMLOPredictionAdapterFacet} from "../interfaces/IMLOPredictionAdapterFacet.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibMLOPredictionAdapter} from "../libraries/LibMLOPredictionAdapter.sol";
import {LibMLOAssetSettlement} from "../libraries/LibMLOAssetSettlement.sol";
import {LibMLOFunding} from "../libraries/LibMLOFunding.sol";
import {LibMLOAutoMerge} from "../libraries/LibMLOAutoMerge.sol";
import {LibMLOScenarioMath} from "../libraries/LibMLOScenarioMath.sol";
import {LibRiskEngine} from "../libraries/LibRiskEngine.sol";
import {LibReentrancy} from "../libraries/LibReentrancy.sol";
import {QuoteEnvelopeTypes} from "../types/QuoteEnvelopeTypes.sol";

contract MLOPredictionSettlementFacet {
    modifier nonReentrant() {
        LibReentrancy.enter();
        _;
        LibReentrancy.exit();
    }

    modifier onlySelf() {
        if (msg.sender != address(this)) revert IMLOPredictionAdapterFacet.MLOInternalOnly(msg.sender);
        _;
    }

    function settleMLOInventory(bytes32 bucketId, bytes32 marketId)
        external
        nonReentrant
        returns (MLOPredictionTypes.MLOInventorySettlement memory settlement)
    {
        settlement = LibMLOPredictionAdapter.settleInventory(LibEveMarket.store(), bucketId, marketId);
    }

    function mergeMLOCompleteSet(bytes32 bucketId, bytes32 marketId, uint256 amount)
        external
        nonReentrant
        returns (MLOPredictionTypes.MLOCompleteSetMerge memory result)
    {
        LibRiskEngine.synchronizeMLOState(LibEveMarket.store(), bucketId);
        result = LibMLOPredictionAdapter.mergeCompleteSet(LibEveMarket.store(), bucketId, marketId, amount);
    }

    function settleMLOFunding(bytes32 bucketId, uint256 maxAssets) external nonReentrant returns (uint256 paid) {
        LibRiskEngine.synchronizeMLOState(LibEveMarket.store(), bucketId);
        paid = LibMLOFunding.payFromMargin(LibEveMarket.store(), bucketId, maxAssets);
    }

    function mergeAvailableMLOCompleteSet(bytes32 bucketId, bytes32 marketId)
        external
        onlySelf
        returns (uint256 merged)
    {
        merged = LibMLOAutoMerge.mergeAvailable(LibEveMarket.store(), bucketId, marketId);
    }

    function executeMLOAskAssetSettlement(MLOPredictionTypes.MLOAskAssetSettlementParams calldata params)
        external
        onlySelf
    {
        LibMLOAssetSettlement.executeAsk(params);
    }

    function prepareMLOAskBacking(uint256 curveId, uint128 sharesOut, uint128 grossCost, uint128 price)
        external
        returns (MLOPredictionTypes.MLOAskBacking memory backing)
    {
        if (msg.sender != address(this)) revert IMLOPredictionAdapterFacet.MLOInternalOnly(msg.sender);
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        uint256 envelopeId = state.mloCurveEnvelopeIds[curveId];
        QuoteEnvelopeTypes.StoredQuoteEnvelope storage envelope = state.quoteEnvelopes[envelopeId];
        LibEveMarket.StoredCurve storage curve = state.curves[curveId];
        LibEveMarket.Book storage book = state.books[curve.bookId];

        uint256 inventoryReserved = state.mloCurveInventoryReserved[curveId];
        backing.inventoryUsed = uint128(uint256(sharesOut) < inventoryReserved ? sharesOut : inventoryReserved);
        backing.manufacturedShares = sharesOut - backing.inventoryUsed;
        uint128 splitContribution = backing.manufacturedShares == 0
            ? 0
            : uint128(
                LibMLOScenarioMath.reservationCash(
                    LibMLOScenarioMath.Side.ASK, backing.manufacturedShares, price, book.priceDenominator
                )
            );
        backing.seniorDeployed = backing.manufacturedShares - splitContribution;

        uint256 newRiskVolume = uint256(envelope.remainingRiskVolume) - sharesOut;
        uint256 inventoryRemaining = inventoryReserved - backing.inventoryUsed;
        uint256 targetSeniorRemaining = LibMLOScenarioMath.askSeniorRequirement(
            newRiskVolume - inventoryRemaining, envelope.minPrice, book.priceDenominator
        );
        uint256 seniorReserved = state.mloCurveSeniorReserved[curveId];
        uint256 requiredSenior = uint256(backing.seniorDeployed) + targetSeniorRemaining;
        if (requiredSenior > seniorReserved) {
            revert IMLOPredictionAdapterFacet.MLOInsufficientCurveBacking(requiredSenior, seniorReserved);
        }
        backing.seniorReleased = uint128(seniorReserved - requiredSenior);

        uint128 repaymentCash = grossCost - splitContribution;
        bytes32 bucketId = state.adapterCurveMetadata[curveId].bucketId;
        uint256 debtAfterDeployment = state.mloBucketMarketSeniorDebt[bucketId][book.marketId] + backing.seniorDeployed;
        LibRiskEngine.accrueConfiguredFunding(state, bucketId);
        backing.seniorRepaid =
            uint128(uint256(repaymentCash) < debtAfterDeployment ? repaymentCash : debtAfterDeployment);
        uint128 remaining = repaymentCash - backing.seniorRepaid;
        uint256 liability = state.marginBuckets[bucketId].fundingLiability;
        if (backing.seniorRepaid == debtAfterDeployment && state.marginBuckets[bucketId].fundingRemainderWad != 0) {
            liability += 1;
        }
        backing.fundingPaid = uint128(uint256(remaining) < liability ? remaining : liability);
        backing.bucketProfit = remaining - backing.fundingPaid;
    }

    function executeMLOBidAssetSettlement(MLOPredictionTypes.MLOBidAssetSettlementParams calldata params)
        external
        onlySelf
    {
        LibMLOAssetSettlement.executeBid(params);
    }
}
