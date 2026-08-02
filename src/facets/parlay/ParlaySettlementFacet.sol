// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {IParlayTicketToken} from "../../interfaces/IParlayTicketToken.sol";
import {Errors} from "../../libraries/Errors.sol";
import {Events} from "../../libraries/Events.sol";
import {LibParlay} from "../../libraries/LibParlay.sol";
import {ParlayBase} from "./ParlayBase.sol";

contract ParlaySettlementFacet is ParlayBase {
    using SafeERC20 for IERC20;

    function finalizeParlayTicketBucket(uint256 ticketId) external nonReentrant returns (uint128 payoutPerUnit) {
        LibParlay.Storage storage state = LibParlay.store();
        LibParlay.ParlayTicketBucket storage bucket = _requireBucket(state, ticketId);
        if (bucket.finalized) {
            revert Errors.ParlayAlreadyFinalized(ticketId);
        }

        (uint8 hits, uint8 misses, uint8 invalids) = _scoreTemplate(state, bucket.templateId);
        payoutPerUnit = _payoutForHits(state, bucket.templateId, hits);
        if (payoutPerUnit > bucket.maxPayoutPerUnit) {
            revert Errors.ParlayMaxPayoutMismatch(bucket.maxPayoutPerUnit, payoutPerUnit);
        }

        uint128 unitsOutstanding = bucket.unitsMinted - bucket.unitsClaimed;
        uint256 claimReserve = uint256(payoutPerUnit) * unitsOutstanding;
        uint256 escrowReturned = bucket.escrowRemaining - claimReserve;

        bucket.finalized = true;
        bucket.payoutPerUnit = payoutPerUnit;
        bucket.escrowRemaining = claimReserve;

        if (escrowReturned != 0) {
            _storedParlayCollateralToken(bucket.collateralToken).safeTransfer(bucket.underwriter, escrowReturned);
        }

        emit Events.ParlayTicketBucketFinalized(
            ticketId,
            bucket.underwriter,
            hits,
            misses,
            invalids,
            payoutPerUnit,
            unitsOutstanding,
            claimReserve,
            escrowReturned
        );
    }

    function claimParlayTicket(uint256 ticketId, uint128 units, address receiver)
        external
        nonReentrant
        returns (uint256 payout)
    {
        if (receiver == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (units == 0) {
            revert Errors.InvalidAmount(units);
        }

        LibParlay.ParlayTicketBucket storage bucket = _requireBucket(LibParlay.store(), ticketId);
        if (!bucket.finalized) {
            revert Errors.ParlayNotFinalized(ticketId);
        }

        payout = uint256(bucket.payoutPerUnit) * units;
        bucket.unitsClaimed += units;
        bucket.escrowRemaining -= payout;

        IParlayTicketToken(_requireConfig().ticketToken).burn(msg.sender, ticketId, units);
        if (payout != 0) {
            _storedParlayCollateralToken(bucket.collateralToken).safeTransfer(receiver, payout);
        }

        emit Events.ParlayTicketClaimed(ticketId, msg.sender, receiver, units, bucket.payoutPerUnit, payout);
    }
}
