// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {MarginTypes} from "./MarginTypes.sol";

library QuoteEnvelopeTypes {
    struct CreateQuoteEnvelopeParams {
        bytes32 bucketId;
        bytes32 bookId;
        uint8 side;
        uint128 maxVolume;
        uint128 minPrice;
        uint128 maxPrice;
        uint128 initialVolume;
        uint128 initialStartPrice;
        uint128 initialEndPrice;
        uint64 expiresAt;
    }

    struct QuoteEnvelopeUpdate {
        uint128 volume;
        uint128 startPrice;
        uint128 endPrice;
    }

    struct StoredQuoteEnvelope {
        address operator;
        bytes32 bucketId;
        bytes32 bookId;
        uint8 side;
        uint128 maxVolume;
        uint128 currentVolume;
        uint128 minPrice;
        uint128 maxPrice;
        uint128 currentStartPrice;
        uint128 currentEndPrice;
        uint128 reservedRisk;
        uint64 expiresAt;
        uint32 generation;
        bool active;
    }

    struct QuoteEnvelopeView {
        uint256 envelopeId;
        address operator;
        bytes32 bucketId;
        bytes32 bookId;
        bytes32 riskDomainId;
        uint8 side;
        MarginTypes.BucketState bucketState;
        uint128 maxVolume;
        uint128 currentVolume;
        uint128 minPrice;
        uint128 maxPrice;
        uint128 currentStartPrice;
        uint128 currentEndPrice;
        uint128 reservedRisk;
        uint64 expiresAt;
        uint32 generation;
        bool active;
        bool canUpdate;
    }
}
