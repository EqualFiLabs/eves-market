// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Errors} from "./Errors.sol";
import {IMultiOutcomeOrderbookFacet} from "../interfaces/IMultiOutcomeOrderbookFacet.sol";
import {LibEveMarket} from "./LibEveMarket.sol";

library LibMultiOutcome {
    bytes32 internal constant CONDITION_DOMAIN = keccak256("EVE_MULTI_OUTCOME_CONDITION");
    bytes32 internal constant POSITION_DOMAIN = keccak256("EVE_MULTI_OUTCOME_POSITION");
    uint8 internal constant MIN_OUTCOME_COUNT = 2;
    uint8 internal constant MAX_OUTCOME_COUNT = 16;
    uint8 internal constant OUTCOME_INVALID = type(uint8).max;
    uint256 internal constant MAX_OUTCOME_DISPLAY_BYTES = 256;
    uint256 internal constant MAX_OUTCOME_ICON_URL_BYTES = 512;

    function outcomesHash(string[] memory outcomes) internal pure returns (bytes32 hash_) {
        hash_ = keccak256(abi.encode(outcomes));
    }

    function conditionIdFor(bytes32 marketId, uint8 outcomeCount, bytes32 outcomesHash_)
        internal
        pure
        returns (bytes32 conditionId)
    {
        conditionId = keccak256(abi.encode(CONDITION_DOMAIN, marketId, outcomeCount, outcomesHash_));
    }

    function positionIdFor(bytes32 conditionId, uint8 outcome) internal pure returns (uint256 positionId) {
        positionId = uint256(keccak256(abi.encode(POSITION_DOMAIN, conditionId, outcome)));
    }

    function validateOutcomeCount(uint256 count) internal pure returns (uint8 outcomeCount) {
        if (count < MIN_OUTCOME_COUNT || count > MAX_OUTCOME_COUNT) {
            revert Errors.InvalidOutcomeCount(count);
        }
        outcomeCount = uint8(count);
    }

    function validateLabels(string[] memory outcomes) internal pure {
        uint256 length = outcomes.length;
        validateOutcomeCount(length);

        for (uint256 index; index < length; ++index) {
            if (bytes(outcomes[index]).length == 0) {
                revert Errors.MetadataFieldRequired("outcome");
            }
            for (uint256 other = index + 1; other < length; ++other) {
                if (keccak256(bytes(outcomes[index])) == keccak256(bytes(outcomes[other]))) {
                    revert Errors.DuplicateOutcomeLabel(index, other);
                }
            }
        }
    }

    function isValidResolution(uint8 outcome, uint8 outcomeCount) internal pure returns (bool) {
        return outcome < outcomeCount || outcome == OUTCOME_INVALID;
    }

    function requireMultiOutcome(LibEveMarket.EveMarketStorage storage state, bytes32 marketId)
        internal
        view
        returns (LibEveMarket.MultiOutcomeMarket storage multi)
    {
        multi = state.multiOutcomeMarkets[marketId];
        if (!multi.exists) {
            revert Errors.MultiOutcomeMarketNotFound(marketId);
        }
    }

    function requireUnresolvedMultiOutcome(LibEveMarket.EveMarketStorage storage state, bytes32 marketId)
        internal
        view
        returns (LibEveMarket.MultiOutcomeMarket storage multi)
    {
        multi = requireMultiOutcome(state, marketId);
        if (multi.resolved) {
            revert Errors.MultiOutcomeMarketResolved(marketId);
        }
    }

    function requireOutcome(LibEveMarket.MultiOutcomeMarket storage market, uint8 outcome) internal view {
        if (outcome >= market.outcomeCount) {
            revert Errors.InvalidOutcome(outcome);
        }
    }

    function validateOutcomeDisplayLength(uint256 outcomeLength, uint256 displayLength) internal pure {
        if (displayLength != 0 && displayLength != outcomeLength) {
            revert Errors.ArrayLengthMismatch(outcomeLength, displayLength);
        }
    }

    function validateOutcomeDisplay(
        IMultiOutcomeOrderbookFacet.OutcomeDisplayInput calldata display,
        string memory displayLabel
    ) internal pure {
        validateDisplayField("outcomeSlug", bytes(display.slug).length, MAX_OUTCOME_DISPLAY_BYTES);
        validateDisplayField("outcomeLabel", bytes(displayLabel).length, MAX_OUTCOME_DISPLAY_BYTES);
        validateDisplayField("outcomeAbbreviation", bytes(display.abbreviation).length, MAX_OUTCOME_DISPLAY_BYTES);
        validateDisplayField("outcomeIconUrl", bytes(display.iconUrl).length, MAX_OUTCOME_ICON_URL_BYTES);
        validateDisplayField("externalOutcomeId", bytes(display.externalOutcomeId).length, MAX_OUTCOME_DISPLAY_BYTES);
    }

    function validateDisplayField(string memory fieldName, uint256 length, uint256 maxLength) internal pure {
        if (length > maxLength) {
            revert Errors.MetadataFieldTooLong(fieldName, length, maxLength);
        }
    }
}
