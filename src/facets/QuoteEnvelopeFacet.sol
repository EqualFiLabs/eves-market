// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IQuoteEnvelopeFacet} from "../interfaces/IQuoteEnvelopeFacet.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibQuoteEnvelope} from "../libraries/LibQuoteEnvelope.sol";
import {LibReentrancy} from "../libraries/LibReentrancy.sol";
import {QuoteEnvelopeTypes} from "../types/QuoteEnvelopeTypes.sol";

contract QuoteEnvelopeFacet is IQuoteEnvelopeFacet {
    modifier nonReentrant() {
        LibReentrancy.enter();
        _;
        LibReentrancy.exit();
    }

    function createQuoteEnvelope(QuoteEnvelopeTypes.CreateQuoteEnvelopeParams calldata params)
        external
        nonReentrant
        returns (uint256 envelopeId)
    {
        envelopeId = LibQuoteEnvelope.createEnvelope(LibEveMarket.store(), params);
    }

    function updateQuoteEnvelope(uint256 envelopeId, QuoteEnvelopeTypes.QuoteEnvelopeUpdate calldata update)
        external
        returns (uint32 generation)
    {
        generation = LibQuoteEnvelope.updateEnvelope(LibEveMarket.store(), envelopeId, update);
    }

    function cancelQuoteEnvelope(uint256 envelopeId) external {
        LibQuoteEnvelope.cancelEnvelope(LibEveMarket.store(), envelopeId);
    }

    function cancelQuoteEnvelopes(uint256[] calldata envelopeIds) external {
        uint256 length = envelopeIds.length;
        for (uint256 index; index < length; ++index) {
            LibQuoteEnvelope.cancelEnvelope(LibEveMarket.store(), envelopeIds[index]);
        }
    }

    function getQuoteEnvelope(uint256 envelopeId)
        external
        view
        returns (QuoteEnvelopeTypes.QuoteEnvelopeView memory envelope)
    {
        envelope = LibQuoteEnvelope.viewEnvelope(LibEveMarket.store(), envelopeId);
    }

    function getOperatorQuoteEnvelopes(address operator) external view returns (uint256[] memory envelopeIds) {
        envelopeIds = LibEveMarket.store().operatorQuoteEnvelopeIds[operator];
    }

    function getBookQuoteEnvelopes(bytes32 bookId) external view returns (uint256[] memory envelopeIds) {
        envelopeIds = LibEveMarket.store().bookQuoteEnvelopeIds[bookId];
    }

    function previewQuoteEnvelopeRisk(QuoteEnvelopeTypes.CreateQuoteEnvelopeParams calldata params)
        external
        view
        returns (uint256 reservedRisk)
    {
        reservedRisk = LibQuoteEnvelope.previewRisk(LibEveMarket.store(), params);
    }

    function canUpdateQuoteEnvelope(uint256 envelopeId) external view returns (bool canUpdate) {
        canUpdate = LibQuoteEnvelope.canUpdate(LibEveMarket.store(), envelopeId);
    }
}
