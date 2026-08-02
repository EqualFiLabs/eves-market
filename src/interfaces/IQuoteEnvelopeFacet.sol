// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {MarginTypes} from "../types/MarginTypes.sol";
import {QuoteEnvelopeTypes} from "../types/QuoteEnvelopeTypes.sol";

interface IQuoteEnvelopeFacet {
    error QuoteEnvelopeNotFound(uint256 envelopeId);
    error QuoteEnvelopeInactive(uint256 envelopeId);
    error QuoteEnvelopeExpired(uint256 envelopeId, uint64 expiresAt);
    error NotQuoteEnvelopeOperator(address caller, address operator);
    error QuoteEnvelopeBucketNotFound(bytes32 bucketId);
    error UnsupportedQuoteEnvelopeBook(bytes32 bookId);
    error QuoteEnvelopeRiskDomainMismatch(bytes32 bucketId, bytes32 expectedRiskDomain, bytes32 actualRiskDomain);
    error InvalidQuoteEnvelopeSide(uint8 side);
    error InvalidQuoteEnvelopeVolume(uint256 volume, uint256 maxVolume);
    error InvalidQuoteEnvelopePriceBounds(uint256 minPrice, uint256 maxPrice);
    error QuoteEnvelopePriceOutOfBounds(uint256 price, uint256 minPrice, uint256 maxPrice);
    error QuoteEnvelopeRiskIsZero();
    error QuoteEnvelopeBucketBlocked(bytes32 bucketId, MarginTypes.BucketState state);

    event QuoteEnvelopeCreated(
        uint256 indexed envelopeId,
        address indexed operator,
        bytes32 indexed bucketId,
        bytes32 bookId,
        LibEveMarket.CurveSide side,
        uint128 maxVolume,
        uint128 reservedRisk,
        uint64 expiresAt
    );
    event QuoteEnvelopeUpdated(
        uint256 indexed envelopeId, uint128 volume, uint128 startPrice, uint128 endPrice, uint32 generation
    );
    event QuoteEnvelopeCancelled(uint256 indexed envelopeId, uint128 releasedRisk, uint32 generation);

    function createQuoteEnvelope(QuoteEnvelopeTypes.CreateQuoteEnvelopeParams calldata params)
        external
        returns (uint256 envelopeId);

    function updateQuoteEnvelope(uint256 envelopeId, QuoteEnvelopeTypes.QuoteEnvelopeUpdate calldata update)
        external
        returns (uint32 generation);

    function cancelQuoteEnvelope(uint256 envelopeId) external;

    function cancelQuoteEnvelopes(uint256[] calldata envelopeIds) external;

    function getQuoteEnvelope(uint256 envelopeId)
        external
        view
        returns (QuoteEnvelopeTypes.QuoteEnvelopeView memory envelope);

    function getOperatorQuoteEnvelopes(address operator) external view returns (uint256[] memory envelopeIds);

    function getBookQuoteEnvelopes(bytes32 bookId) external view returns (uint256[] memory envelopeIds);

    function previewQuoteEnvelopeRisk(QuoteEnvelopeTypes.CreateQuoteEnvelopeParams calldata params)
        external
        view
        returns (uint256 reservedRisk);

    function canUpdateQuoteEnvelope(uint256 envelopeId) external view returns (bool canUpdate);
}
