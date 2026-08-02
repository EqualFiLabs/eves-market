// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {MarketFactoryTypes} from "../types/MarketFactoryTypes.sol";

interface IMultiOutcomeOrderbookFacet is MarketFactoryTypes {
    struct OutcomeDisplayInput {
        string slug;
        string displayLabel;
        string abbreviation;
        string iconUrl;
        string externalOutcomeId;
    }

    struct CreateMultiOutcomeMarketParams {
        string question;
        string category;
        string resolutionSource;
        uint64 tradingStartTime;
        uint64 expiryTime;
        string[] outcomes;
        MarketDisplayInput display;
        ExternalMarketRefInput externalRef;
        OutcomeDisplayInput[] outcomeDisplay;
    }

    struct MultiOutcomeMarketView {
        bytes32 marketId;
        bytes32 conditionId;
        bytes32 outcomesHash;
        address positionToken;
        address collateralToken;
        uint8 marketType;
        uint8 positionTokenType;
        uint8 collateralProfileId;
        uint8 outcomeCount;
        uint128 payoutUnit;
        uint8 resolvedOutcome;
        uint256 payoutDenominator;
        bool invalid;
        bool resolved;
    }

    struct OutcomeDisplayView {
        string slug;
        string displayLabel;
        string abbreviation;
        string iconUrl;
        bytes32 externalRefHash;
        bool exists;
    }

    struct OutcomeCTFPositionView {
        bytes32 questionId;
        bytes32 conditionId;
        uint256 yesPositionId;
        uint256 noPositionId;
    }

    function createMultiOutcomeMarket(CreateMultiOutcomeMarketParams calldata params)
        external
        returns (bytes32 marketId);

    function createMultiOutcomeMarketWithCollateralProfile(
        uint8 profileId,
        CreateMultiOutcomeMarketParams calldata params
    ) external returns (bytes32 marketId);

    function getMultiOutcomeMarket(bytes32 marketId) external view returns (MultiOutcomeMarketView memory market);

    function getMultiOutcomeOutcomes(bytes32 marketId) external view returns (string[] memory outcomes);

    function getMultiOutcomeDisplay(bytes32 marketId, uint8 outcome)
        external
        view
        returns (OutcomeDisplayView memory display);

    function getOutcomePositionId(bytes32 marketId, uint8 outcome) external view returns (uint256 positionId);

    function getOutcomeCTFPositions(bytes32 marketId, uint8 outcome)
        external
        view
        returns (OutcomeCTFPositionView memory positions);

    function getMultiOutcomeBooks(bytes32 marketId) external view returns (bytes32[] memory bookIds);

    function splitOutcomeSet(bytes32 marketId, uint128 amount, address receiver)
        external
        returns (uint256[] memory positionIds);

    function mergeOutcomeSet(bytes32 marketId, uint128 amount, address receiver)
        external
        returns (uint128 collateralOut);

    function redeemOutcome(bytes32 marketId, uint8 outcome, uint128 amount, address receiver)
        external
        returns (uint128 collateralOut);
}
