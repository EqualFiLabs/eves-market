// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISeniorCapitalFacet} from "../interfaces/ISeniorCapitalFacet.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibSeniorCapital} from "../libraries/LibSeniorCapital.sol";

contract SeniorCapitalViewFacet {
    function seniorCapitalState() external view returns (ISeniorCapitalFacet.SeniorCapitalState memory stateView) {
        LibSeniorCapital.Storage storage state = LibSeniorCapital.s();
        LibSeniorCapital.Epoch storage epoch = state.epochs[state.currentEpoch];
        uint256 scale = epoch.scaleRay == 0 ? LibSeniorCapital.RAY : epoch.scaleRay;
        stateView = ISeniorCapitalFacet.SeniorCapitalState({
            asset: LibEveMarket.store().marginAsset,
            epoch: state.currentEpoch,
            activationDelay: LibSeniorCapital.ACTIVATION_DELAY,
            pendingPrincipal: state.pendingPrincipal,
            totalPrincipal: state.totalPrincipal,
            totalStored: state.totalStored,
            exitStored: state.totalExitStored,
            availableCapital: LibSeniorCapital.availableCapital(state),
            reservedCapital: state.reservedCapital,
            activeExposure: state.activeExposure,
            feeReserve: state.totalFeeReserve,
            realizedLosses: state.realizedLosses,
            fundingRevenue: state.fundingRevenue,
            scaleRay: scale,
            feeIndexRay: epoch.fees.accPerStoredRay,
            feeRemainderRay: epoch.fees.remainderRay,
            exitHead: state.exitHead,
            exitTail: state.exitTail,
            exitClaims: state.totalExitClaims
        });
    }

    function seniorCapitalAccount(address account)
        external
        view
        returns (ISeniorCapitalFacet.SeniorCapitalAccount memory accountView)
    {
        LibSeniorCapital.Storage storage state = LibSeniorCapital.s();
        LibSeniorCapital.Account storage stored = state.accounts[account];
        accountView = ISeniorCapitalFacet.SeniorCapitalAccount({
            epoch: stored.epoch,
            pendingSince: stored.pendingSince,
            pendingPrincipal: stored.pendingPrincipal,
            storedUnits: stored.stored,
            effectivePrincipal: LibSeniorCapital.effectiveFor(state, stored.epoch, stored.stored),
            accruedFees: stored.accruedFees,
            pendingFees: LibSeniorCapital.pendingFees(state, stored),
            activeExitId: stored.activeExitId
        });
    }

    function seniorCapitalExit(uint256 exitId)
        external
        view
        returns (ISeniorCapitalFacet.SeniorCapitalExit memory exitView)
    {
        LibSeniorCapital.Storage storage state = LibSeniorCapital.s();
        LibSeniorCapital.ExitRequest storage request = state.exits[exitId];
        exitView = ISeniorCapitalFacet.SeniorCapitalExit({
            exitId: exitId,
            owner: request.owner,
            receiver: request.receiver,
            epoch: request.epoch,
            storedUnits: request.stored,
            effectivePrincipal: LibSeniorCapital.effectiveFor(state, request.epoch, request.stored),
            accruedFees: request.accruedFees,
            pendingFees: LibSeniorCapital.pendingExitFees(state, request),
            cancelled: request.cancelled
        });
    }

    function seniorCapitalBucket(bytes32 bucketId)
        external
        view
        returns (ISeniorCapitalFacet.SeniorCapitalBucket memory bucketView)
    {
        LibSeniorCapital.Bucket storage bucket = LibSeniorCapital.s().buckets[bucketId];
        bucketView = ISeniorCapitalFacet.SeniorCapitalBucket({
            reservedCapital: bucket.reservedCapital,
            activeExposure: bucket.activeExposure,
            realizedLosses: bucket.realizedLosses,
            fundingRevenue: bucket.fundingRevenue,
            riskSnapshotVersion: bucket.riskSnapshotVersion,
            riskSnapshotEpoch: bucket.riskSnapshotEpoch,
            riskSnapshotStored: bucket.riskSnapshotStored,
            riskSnapshotSet: bucket.riskSnapshotSet
        });
    }

    function pendingSeniorCapitalFees(address account) external view returns (uint256 fees) {
        LibSeniorCapital.Storage storage state = LibSeniorCapital.s();
        fees = LibSeniorCapital.pendingFees(state, state.accounts[account]);
    }

    function claimableSeniorCapitalExit(address account) external view returns (uint256 assets) {
        assets = LibSeniorCapital.s().exitClaims[account];
    }
}
