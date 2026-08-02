// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {LibEveMarket} from "./LibEveMarket.sol";
import {Errors} from "./Errors.sol";
import {LibSafeCast} from "./LibSafeCast.sol";

library LibParimutuel {
    bytes32 internal constant STORAGE_SLOT = bytes32(uint256(keccak256("eve.prediction.parimutuel.storage")) - 1);

    struct Pool {
        uint128 totalYesShares;
        uint128 totalNoShares;
        uint128 payoutPool;
        uint128 claimedPayout;
        uint128 claimedClaimableShares;
        LibEveMarket.MarketOutcome rawResolvedOutcome;
        LibEveMarket.MarketOutcome effectivePayoutOutcome;
        uint128 payoutPoolAtResolution;
        uint128 totalClaimableSharesAtResolution;
        bool dustSwept;
        bool finalized;
    }

    struct Storage {
        mapping(bytes32 => Pool) pools;
    }

    function store() internal pure returns (Storage storage storage_) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            storage_.slot := slot
        }
    }

    function effectivePayoutOutcome(Pool storage pool, LibEveMarket.MarketOutcome resolvedOutcome)
        internal
        view
        returns (LibEveMarket.MarketOutcome)
    {
        if (resolvedOutcome == LibEveMarket.MarketOutcome.Yes && pool.totalYesShares == 0) {
            return LibEveMarket.MarketOutcome.Invalid;
        }
        if (resolvedOutcome == LibEveMarket.MarketOutcome.No && pool.totalNoShares == 0) {
            return LibEveMarket.MarketOutcome.Invalid;
        }

        return resolvedOutcome;
    }

    function finalizePool(Pool storage pool, LibEveMarket.MarketOutcome rawResolvedOutcome)
        internal
        returns (LibEveMarket.MarketOutcome effectiveOutcome, uint128 totalClaimableShares)
    {
        effectiveOutcome = effectivePayoutOutcome(pool, rawResolvedOutcome);
        totalClaimableShares = claimableSharesForOutcome(pool, effectiveOutcome);

        pool.rawResolvedOutcome = rawResolvedOutcome;
        pool.effectivePayoutOutcome = effectiveOutcome;
        pool.payoutPoolAtResolution = pool.payoutPool;
        pool.totalClaimableSharesAtResolution = totalClaimableShares;
        pool.finalized = true;
    }

    function requireFinalized(Pool storage pool, bytes32 marketId) internal view {
        if (!pool.finalized) {
            revert Errors.ParimutuelPoolNotFinalized(marketId);
        }
    }

    function claimableSharesForOutcome(Pool storage pool, LibEveMarket.MarketOutcome payoutOutcome)
        internal
        view
        returns (uint128 claimableShares)
    {
        if (payoutOutcome == LibEveMarket.MarketOutcome.Yes) {
            return pool.totalYesShares;
        }
        if (payoutOutcome == LibEveMarket.MarketOutcome.No) {
            return pool.totalNoShares;
        }

        return LibSafeCast.toUint128(uint256(pool.totalYesShares) + pool.totalNoShares);
    }
}
