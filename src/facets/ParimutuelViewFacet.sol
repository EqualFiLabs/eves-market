// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC1155} from "../../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";

import {IParimutuelFacet} from "../interfaces/IParimutuelFacet.sol";
import {Errors} from "../libraries/Errors.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibFeeRouting} from "../libraries/LibFeeRouting.sol";
import {LibParimutuel} from "../libraries/LibParimutuel.sol";
import {LibSafeCast} from "../libraries/LibSafeCast.sol";

contract ParimutuelViewFacet {
    uint256 internal constant FEE_BPS_DENOMINATOR = 10_000;
    uint256 internal constant PROBABILITY_SCALE = 1e18;
    uint256 internal constant EPOCH_MULTIPLIER_SCALE = 10_000;
    uint256 internal constant EPOCH_COUNT = 8;

    struct EntryFeeBreakdown {
        uint128 totalFee;
        uint128 creatorFee;
        uint128 protocolFee;
        uint128 seniorPoolFee;
        uint128 resolverFee;
        uint128 netShares;
    }

    function previewPayout(bytes32 marketId, address user)
        external
        view
        returns (uint256 claimableAmount, uint256 userWinningShares, uint256 totalWinningShares, uint256 payoutPool)
    {
        LibEveMarket.Market storage market = _requireParimutuelMarket(LibEveMarket.store(), marketId);
        LibParimutuel.Pool storage pool = LibParimutuel.store().pools[marketId];

        payoutPool = pool.payoutPool;
        if (market.state != LibEveMarket.MarketState.Resolved) {
            return (0, 0, 0, payoutPool);
        }

        return _previewPayout(market, pool, user);
    }

    function previewEntryFee(bytes32 marketId, uint128 amount)
        external
        view
        returns (
            uint128 totalFee,
            uint128 creatorFee,
            uint128 protocolFee,
            uint128 seniorPoolFee,
            uint128 resolverFee,
            uint128 netShares
        )
    {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Market storage market = _requireParimutuelMarket(state, marketId);
        EntryFeeBreakdown memory fees = _entryFeeBreakdown(market, state.config, amount);
        totalFee = fees.totalFee;
        creatorFee = fees.creatorFee;
        protocolFee = fees.protocolFee;
        seniorPoolFee = fees.seniorPoolFee;
        resolverFee = fees.resolverFee;
        netShares = fees.netShares;
    }

    function previewParimutuelEntry(bytes32 marketId, bool isYes, uint128 amount)
        external
        view
        returns (IParimutuelFacet.EntryPreview memory preview)
    {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Market storage market = _requireParimutuelMarket(state, marketId);
        EntryFeeBreakdown memory fees = _entryFeeBreakdown(market, state.config, amount);
        LibParimutuel.Pool storage pool = LibParimutuel.store().pools[marketId];

        uint256 epoch = _currentEpoch(market.tradingStartTime, market.parimutuelEpochWindow);
        uint256 multiplierBps = _parimutuelMultiplierBps(epoch);
        uint256 computedShares = (uint256(fees.netShares) * multiplierBps) / EPOCH_MULTIPLIER_SCALE;
        uint128 sharesMinted = computedShares == 0 ? 0 : LibSafeCast.toUint128(computedShares);
        uint128 totalYesSharesAfter = pool.totalYesShares;
        uint128 totalNoSharesAfter = pool.totalNoShares;
        if (isYes) {
            totalYesSharesAfter = LibSafeCast.toUint128(uint256(totalYesSharesAfter) + sharesMinted);
        } else {
            totalNoSharesAfter = LibSafeCast.toUint128(uint256(totalNoSharesAfter) + sharesMinted);
        }

        preview = IParimutuelFacet.EntryPreview({
            amountIn: amount,
            totalFee: fees.totalFee,
            creatorFee: fees.creatorFee,
            protocolFee: fees.protocolFee,
            seniorPoolFee: fees.seniorPoolFee,
            resolverFee: fees.resolverFee,
            netCollateral: fees.netShares,
            sharesMinted: sharesMinted,
            multiplierBps: multiplierBps,
            epoch: epoch,
            effectiveBasisWad: sharesMinted == 0 ? type(uint256).max : (uint256(fees.netShares) * 1e18) / sharesMinted,
            totalYesSharesAfter: totalYesSharesAfter,
            totalNoSharesAfter: totalNoSharesAfter,
            payoutPoolAfter: LibSafeCast.toUint128(uint256(pool.payoutPool) + fees.netShares)
        });
    }

    function getParimutuelPool(bytes32 marketId) external view returns (IParimutuelFacet.PoolView memory pool) {
        _requireParimutuelMarket(LibEveMarket.store(), marketId);

        LibParimutuel.Pool storage storedPool = LibParimutuel.store().pools[marketId];
        (uint128 impliedYesProbability, uint128 impliedNoProbability) =
            _impliedProbabilities(storedPool.totalYesShares, storedPool.totalNoShares);

        pool = IParimutuelFacet.PoolView({
            totalYesShares: storedPool.totalYesShares,
            totalNoShares: storedPool.totalNoShares,
            payoutPool: storedPool.payoutPool,
            claimedPayout: storedPool.claimedPayout,
            claimedClaimableShares: storedPool.claimedClaimableShares,
            rawResolvedOutcome: uint8(storedPool.rawResolvedOutcome),
            effectivePayoutOutcome: uint8(storedPool.effectivePayoutOutcome),
            payoutPoolAtResolution: storedPool.payoutPoolAtResolution,
            totalClaimableSharesAtResolution: storedPool.totalClaimableSharesAtResolution,
            dustSwept: storedPool.dustSwept,
            finalized: storedPool.finalized,
            impliedYesProbability: impliedYesProbability,
            impliedNoProbability: impliedNoProbability
        });
    }

    function getParimutuelBalances(bytes32 marketId, address user)
        external
        view
        returns (uint256 yesShares, uint256 noShares)
    {
        LibEveMarket.Market storage market = _requireParimutuelMarket(LibEveMarket.store(), marketId);
        (yesShares, noShares) = _balances(market, user);
    }

    function isParimutuelMarket(bytes32 marketId) external view returns (bool) {
        LibEveMarket.Market storage market = LibEveMarket.store().markets[marketId];
        return market.marketId == marketId && market.marketType == LibEveMarket.MarketType.PARIMUTUEL;
    }

    function getParimutuelEpochWindow(bytes32 marketId) external view returns (uint64 epochWindow) {
        LibEveMarket.Market storage market = _requireParimutuelMarket(LibEveMarket.store(), marketId);
        epochWindow = market.parimutuelEpochWindow;
    }

    function getEpochMultiplier(bytes32 marketId) external view returns (uint256 multiplierBps, uint256 epoch) {
        LibEveMarket.Market storage market = _requireParimutuelMarket(LibEveMarket.store(), marketId);
        epoch = _currentEpoch(market.tradingStartTime, market.parimutuelEpochWindow);
        multiplierBps = _parimutuelMultiplierBps(epoch);
    }

    function getParimutuelEpochMultipliers() external view returns (uint16[8] memory multipliersBps) {
        LibEveMarket.MarketConfig storage config = LibEveMarket.store().config;
        for (uint256 index = 0; index < EPOCH_COUNT; ++index) {
            uint16 configured = config.parimutuelEpochMultipliersBps[index];
            multipliersBps[index] = configured == 0 ? _defaultParimutuelMultiplierBps(index) : configured;
        }
    }

    function _previewPayout(LibEveMarket.Market storage market, LibParimutuel.Pool storage pool, address user)
        private
        view
        returns (uint256 claimableAmount, uint256 userWinningShares, uint256 totalWinningShares, uint256 payoutPool)
    {
        LibParimutuel.requireFinalized(pool, market.marketId);
        LibEveMarket.MarketOutcome payoutOutcome = pool.effectivePayoutOutcome;
        payoutPool = pool.payoutPoolAtResolution;

        if (payoutOutcome == LibEveMarket.MarketOutcome.Yes) {
            userWinningShares = IERC1155(market.positionToken).balanceOf(user, market.yesPositionId);
            totalWinningShares = pool.totalClaimableSharesAtResolution;
            claimableAmount = (userWinningShares * payoutPool) / totalWinningShares;
        } else if (payoutOutcome == LibEveMarket.MarketOutcome.No) {
            userWinningShares = IERC1155(market.positionToken).balanceOf(user, market.noPositionId);
            totalWinningShares = pool.totalClaimableSharesAtResolution;
            claimableAmount = (userWinningShares * payoutPool) / totalWinningShares;
        } else {
            (uint256 yesShares, uint256 noShares) = _balances(market, user);
            userWinningShares = yesShares + noShares;
            totalWinningShares = pool.totalClaimableSharesAtResolution;
            if (totalWinningShares != 0) {
                claimableAmount = (userWinningShares * payoutPool) / totalWinningShares;
            }
        }
    }

    function _entryFeeBreakdown(
        LibEveMarket.Market storage market,
        LibEveMarket.MarketConfig storage config,
        uint128 amount
    ) private view returns (EntryFeeBreakdown memory fees) {
        LibEveMarket.ParimutuelFeeConfig storage feeConfig = market.parimutuelFeeConfig;
        if (
            uint256(feeConfig.creatorFeeBps) + feeConfig.protocolFeeBps + feeConfig.resolverFeeBps > FEE_BPS_DENOMINATOR
        ) {
            revert Errors.FeeSplitExceedsDenominator(feeConfig.creatorFeeBps, feeConfig.protocolFeeBps);
        }
        uint256 splitTotal = uint256(feeConfig.creatorFeeBps) + feeConfig.protocolFeeBps + feeConfig.seniorPoolFeeBps
            + feeConfig.resolverFeeBps;
        if (splitTotal != FEE_BPS_DENOMINATOR) {
            revert Errors.InvalidFeeSplit(splitTotal);
        }

        fees.totalFee = uint128((uint256(amount) * feeConfig.entryFeeBps) / FEE_BPS_DENOMINATOR);
        if (fees.totalFee >= amount) {
            revert Errors.FeeExceedsAmount(amount, fees.totalFee);
        }

        fees.creatorFee = uint128((uint256(fees.totalFee) * feeConfig.creatorFeeBps) / FEE_BPS_DENOMINATOR);
        fees.protocolFee = uint128((uint256(fees.totalFee) * feeConfig.protocolFeeBps) / FEE_BPS_DENOMINATOR);
        fees.resolverFee = uint128((uint256(fees.totalFee) * feeConfig.resolverFeeBps) / FEE_BPS_DENOMINATOR);
        uint128 rawSeniorPoolFee = fees.totalFee - fees.creatorFee - fees.protocolFee - fees.resolverFee;
        fees.netShares = amount - fees.totalFee;

        if (!config.permissionlessCreationEnabled) {
            fees.protocolFee += fees.creatorFee;
            fees.creatorFee = 0;
        }

        LibFeeRouting.SeniorPoolFeeRoute memory route =
            LibFeeRouting.previewSeniorPoolFeeRoute(market.collateralToken, rawSeniorPoolFee);
        fees.seniorPoolFee = uint128(route.seniorPoolAmount);
        fees.protocolFee += uint128(route.treasuryAmount);
    }

    function _requireParimutuelMarket(LibEveMarket.EveMarketStorage storage state, bytes32 marketId)
        private
        view
        returns (LibEveMarket.Market storage market)
    {
        market = state.markets[marketId];
        if (market.marketId != marketId) {
            revert Errors.MarketNotFound(marketId);
        }
        if (market.marketType != LibEveMarket.MarketType.PARIMUTUEL) {
            revert Errors.NotParimutuelMarket(marketId);
        }
    }

    function _balances(LibEveMarket.Market storage market, address user)
        private
        view
        returns (uint256 yesShares, uint256 noShares)
    {
        IERC1155 positionToken = IERC1155(market.positionToken);
        yesShares = positionToken.balanceOf(user, market.yesPositionId);
        noShares = positionToken.balanceOf(user, market.noPositionId);
    }

    function _impliedProbabilities(uint128 totalYesShares, uint128 totalNoShares)
        private
        pure
        returns (uint128 impliedYesProbability, uint128 impliedNoProbability)
    {
        uint256 totalShares = uint256(totalYesShares) + totalNoShares;
        if (totalShares == 0) {
            return (0, 0);
        }

        impliedYesProbability = uint128((uint256(totalYesShares) * PROBABILITY_SCALE) / totalShares);
        impliedNoProbability = uint128(PROBABILITY_SCALE - impliedYesProbability);
    }

    function _currentEpoch(uint64 tradingStartTime, uint64 epochWindow) private view returns (uint256 epoch) {
        uint256 elapsed = block.timestamp > tradingStartTime ? block.timestamp - tradingStartTime : 0;
        epoch = elapsed >= epochWindow ? EPOCH_COUNT - 1 : (elapsed * EPOCH_COUNT) / epochWindow;
    }

    function _parimutuelMultiplierBps(uint256 epoch) private view returns (uint16) {
        uint256 boundedEpoch = epoch >= EPOCH_COUNT ? EPOCH_COUNT - 1 : epoch;
        uint16 configured = LibEveMarket.store().config.parimutuelEpochMultipliersBps[boundedEpoch];

        return configured == 0 ? _defaultParimutuelMultiplierBps(boundedEpoch) : configured;
    }

    function _defaultParimutuelMultiplierBps(uint256 epoch) private pure returns (uint16) {
        if (epoch == 0) return 20_000;
        if (epoch == 1) return 15_000;
        if (epoch == 2) return 11_500;
        if (epoch == 3) return 10_000;
        if (epoch == 4) return 8_500;
        if (epoch == 5) return 7_000;
        if (epoch == 6) return 5_500;
        return 4_000;
    }
}
