// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Errors} from "../../libraries/Errors.sol";
import {Events} from "../../libraries/Events.sol";
import {LibDiamond} from "../../libraries/LibDiamond.sol";
import {LibParlay} from "../../libraries/LibParlay.sol";
import {ParlayTypes} from "../../types/ParlayTypes.sol";
import {ParlayBase} from "./ParlayBase.sol";

contract ParlayAdminFacet is ParlayBase {
    function setParlayConfig(
        address ticketToken,
        address feeRecipient,
        uint128 underwritingFee,
        uint16 vaultFeeBps,
        uint16 feeRecipientBps
    ) external {
        LibDiamond.enforceIsContractOwner();
        if (feeRecipient == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (uint256(vaultFeeBps) + feeRecipientBps != LibParlay.BPS_DENOMINATOR) {
            revert Errors.InvalidFeeSplit(uint256(vaultFeeBps) + feeRecipientBps);
        }
        _enforceParlayTicketToken(ticketToken);

        LibParlay.Config storage config = LibParlay.store().config;
        config.ticketToken = ticketToken;
        config.feeRecipient = feeRecipient;
        config.underwritingFee = underwritingFee;
        config.vaultFeeBps = vaultFeeBps;
        config.feeRecipientBps = feeRecipientBps;

        emit Events.ParlayConfigSet(ticketToken, feeRecipient, underwritingFee, vaultFeeBps, feeRecipientBps);
    }

    function getParlayConfig() external view returns (ParlayTypes.ParlayConfigView memory configView) {
        LibParlay.Config storage config = LibParlay.store().config;
        configView = ParlayTypes.ParlayConfigView({
            ticketToken: config.ticketToken,
            feeRecipient: config.feeRecipient,
            underwritingFee: config.underwritingFee,
            vaultFeeBps: config.vaultFeeBps,
            feeRecipientBps: config.feeRecipientBps
        });
    }

    function emitStrategyCreated(
        bytes32 strategyId,
        bytes32[] calldata directMarketIds,
        uint8[] calldata directOutcomes,
        uint256[] calldata parlayTemplateIds,
        string calldata metadataHint
    ) external {
        if (directMarketIds.length != directOutcomes.length) {
            revert Errors.ArrayLengthMismatch(directMarketIds.length, directOutcomes.length);
        }

        emit Events.StrategyCreated(
            strategyId, msg.sender, directMarketIds, directOutcomes, parlayTemplateIds, metadataHint
        );
    }
}
