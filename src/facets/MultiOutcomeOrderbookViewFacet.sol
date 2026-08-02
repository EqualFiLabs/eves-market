// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IMultiOutcomeOrderbookFacet} from "../interfaces/IMultiOutcomeOrderbookFacet.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibMultiOutcome} from "../libraries/LibMultiOutcome.sol";

contract MultiOutcomeOrderbookViewFacet {
    function getMultiOutcomeMarket(bytes32 marketId)
        external
        view
        returns (IMultiOutcomeOrderbookFacet.MultiOutcomeMarketView memory marketView)
    {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.MultiOutcomeMarket storage market = LibMultiOutcome.requireMultiOutcome(state, marketId);
        LibEveMarket.Market storage coreMarket = state.markets[marketId];

        marketView = IMultiOutcomeOrderbookFacet.MultiOutcomeMarketView({
            marketId: market.marketId,
            conditionId: market.conditionId,
            outcomesHash: market.outcomesHash,
            positionToken: coreMarket.positionToken,
            collateralToken: coreMarket.collateralToken,
            marketType: uint8(coreMarket.marketType),
            positionTokenType: uint8(coreMarket.positionTokenType),
            collateralProfileId: coreMarket.collateralProfileId,
            outcomeCount: market.outcomeCount,
            payoutUnit: coreMarket.payoutUnit,
            resolvedOutcome: market.resolvedOutcome,
            payoutDenominator: market.payoutDenominator,
            invalid: market.invalid,
            resolved: market.resolved
        });
    }

    function getMultiOutcomeOutcomes(bytes32 marketId) external view returns (string[] memory outcomes) {
        LibMultiOutcome.requireMultiOutcome(LibEveMarket.store(), marketId);
        outcomes = LibEveMarket.store().multiOutcomeLabels[marketId];
    }

    function getMultiOutcomeDisplay(bytes32 marketId, uint8 outcome)
        external
        view
        returns (IMultiOutcomeOrderbookFacet.OutcomeDisplayView memory displayView)
    {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.MultiOutcomeMarket storage multi = LibMultiOutcome.requireMultiOutcome(state, marketId);
        LibMultiOutcome.requireOutcome(multi, outcome);
        LibEveMarket.MultiOutcomeDisplay storage display = state.multiOutcomeDisplays[marketId][outcome];
        displayView = IMultiOutcomeOrderbookFacet.OutcomeDisplayView({
            slug: display.slug,
            displayLabel: display.displayLabel,
            abbreviation: display.abbreviation,
            iconUrl: display.iconUrl,
            externalRefHash: display.externalRefHash,
            exists: display.exists
        });
    }

    function getOutcomePositionId(bytes32 marketId, uint8 outcome) external view returns (uint256 positionId) {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.MultiOutcomeMarket storage market = LibMultiOutcome.requireMultiOutcome(state, marketId);
        LibMultiOutcome.requireOutcome(market, outcome);
        positionId = state.multiOutcomePositionIds[marketId][outcome];
    }

    function getOutcomeCTFPositions(bytes32 marketId, uint8 outcome)
        external
        view
        returns (IMultiOutcomeOrderbookFacet.OutcomeCTFPositionView memory positions)
    {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.MultiOutcomeMarket storage market = LibMultiOutcome.requireMultiOutcome(state, marketId);
        LibMultiOutcome.requireOutcome(market, outcome);
        positions = IMultiOutcomeOrderbookFacet.OutcomeCTFPositionView({
            questionId: state.multiOutcomeQuestionIds[marketId][outcome],
            conditionId: state.multiOutcomeConditionIds[marketId][outcome],
            yesPositionId: state.multiOutcomePositionIds[marketId][outcome],
            noPositionId: state.multiOutcomeNoPositionIds[marketId][outcome]
        });
    }

    function getMultiOutcomeBooks(bytes32 marketId) external view returns (bytes32[] memory bookIds) {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.MultiOutcomeMarket storage multi = LibMultiOutcome.requireMultiOutcome(state, marketId);
        bookIds = new bytes32[](multi.outcomeCount);

        for (uint8 outcome; outcome < multi.outcomeCount; ++outcome) {
            bookIds[outcome] = state.multiOutcomeBookIds[marketId][outcome];
        }
    }
}
