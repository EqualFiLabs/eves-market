// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {ISeniorCapitalPool} from "../interfaces/ISeniorCapitalPool.sol";
import {IEvRiskStakingRewards} from "../interfaces/IEvRiskStakingRewards.sol";
import {Errors} from "./Errors.sol";
import {LibDelayedOrder} from "./LibDelayedOrder.sol";
import {LibEveMarket} from "./LibEveMarket.sol";
import {LibFeeRouting} from "./LibFeeRouting.sol";
import {LibMakerRewards} from "./LibMakerRewards.sol";
import {LibResolverRewards} from "./LibResolverRewards.sol";

library LibBookAccounting {
    using SafeERC20 for IERC20;

    uint256 internal constant FEE_BPS_DENOMINATOR = 10_000;

    struct FeeShares {
        uint128 makerFeeShare;
        uint128 creatorFeeShare;
        uint128 seniorPoolFeeShare;
        uint128 treasuryFeeShare;
        uint128 resolverFeeShare;
        uint128 evRiskFeeShare;
        uint128 processorFeeShare;
        address processor;
    }

    function feeSharesForBook(LibEveMarket.EveMarketStorage storage state, LibEveMarket.Book storage book, uint128 fee)
        internal
        view
        returns (FeeShares memory fees)
    {
        LibEveMarket.BookFeeConfig storage feeConfig = book.feeConfig;
        uint256 remainingFee = fee;

        fees.processor = LibDelayedOrder.activeProcessor();
        if (fees.processor != address(0) && state.config.delayedOrderProcessorFeeShareBps != 0) {
            fees.processorFeeShare =
                uint128((uint256(fee) * state.config.delayedOrderProcessorFeeShareBps) / FEE_BPS_DENOMINATOR);
            remainingFee = fee - fees.processorFeeShare;
        }

        fees.makerFeeShare = uint128((remainingFee * feeConfig.makerFeeBps) / FEE_BPS_DENOMINATOR);
        fees.creatorFeeShare = uint128((remainingFee * feeConfig.creatorFeeBps) / FEE_BPS_DENOMINATOR);
        uint128 rawSeniorPoolFeeShare = uint128((remainingFee * feeConfig.vaultFeeBps) / FEE_BPS_DENOMINATOR);
        fees.resolverFeeShare = uint128((remainingFee * feeConfig.resolverFeeBps) / FEE_BPS_DENOMINATOR);
        uint128 rawEvRiskFeeShare = uint128((remainingFee * feeConfig.evRiskFeeBps) / FEE_BPS_DENOMINATOR);
        fees.treasuryFeeShare = uint128(
            remainingFee - fees.makerFeeShare - fees.creatorFeeShare - rawSeniorPoolFeeShare - fees.resolverFeeShare
                - rawEvRiskFeeShare
        );

        if (!state.config.permissionlessCreationEnabled && book.marketId != bytes32(0)) {
            fees.treasuryFeeShare += fees.creatorFeeShare;
            fees.creatorFeeShare = 0;
        }

        LibFeeRouting.SeniorPoolFeeRoute memory route = LibFeeRouting.previewSeniorPoolFeeRoute(
            state.config.seniorCapitalPool, book.quoteToken, rawSeniorPoolFeeShare
        );
        fees.seniorPoolFeeShare = uint128(route.seniorPoolAmount);
        fees.treasuryFeeShare += uint128(route.treasuryAmount);

        LibFeeRouting.EvRiskFeeRoute memory evRiskRoute =
            LibFeeRouting.previewEvRiskFeeRoute(state.config.evRiskStakingRewards, rawEvRiskFeeShare);
        fees.evRiskFeeShare = uint128(evRiskRoute.evRiskAmount);
        fees.treasuryFeeShare += uint128(evRiskRoute.treasuryAmount);
    }

    function payBookQuoteFees(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.Book storage book,
        FeeShares memory fees
    ) internal {
        IERC20 quoteToken = IERC20(book.quoteToken);
        if (fees.treasuryFeeShare != 0) {
            quoteToken.safeTransfer(state.config.eveTreasury, fees.treasuryFeeShare);
        }
        if (fees.processorFeeShare != 0) {
            quoteToken.safeTransfer(fees.processor, fees.processorFeeShare);
        }
        if (fees.seniorPoolFeeShare != 0) {
            quoteToken.forceApprove(state.config.seniorCapitalPool, fees.seniorPoolFeeShare);
            ISeniorCapitalPool(state.config.seniorCapitalPool).notifyRevenue(book.quoteToken, fees.seniorPoolFeeShare);
        }
        if (fees.evRiskFeeShare != 0) {
            quoteToken.forceApprove(state.config.evRiskStakingRewards, fees.evRiskFeeShare);
            IEvRiskStakingRewards(state.config.evRiskStakingRewards).notifyReward(book.quoteToken, fees.evRiskFeeShare);
        }
        LibResolverRewards.accrueTradingFee(book.quoteToken, fees.resolverFeeShare);
    }

    function recordBookOnlyFill(
        LibEveMarket.Book storage book,
        address maker,
        uint128 price,
        uint128 quoteVolume,
        uint128 fee,
        FeeShares memory fees
    ) internal {
        if (price > type(uint96).max) revert Errors.InvalidAmount(price);
        book.lastTradePrice = uint96(price);
        book.totalFeePool += fee;
        book.totalQuoteVolume += quoteVolume;
        book.makerQuoteVolume[maker] += quoteVolume;
        book.makerFeesAccrued[maker] += fees.makerFeeShare;
        book.creatorFeesEscrowed += fees.creatorFeeShare;
        book.protocolFeesAccrued += fees.treasuryFeeShare;
    }

    function recordMarketOnlyFill(
        LibEveMarket.Market storage market,
        address maker,
        uint128 price,
        uint128 quoteVolume,
        uint128 fee,
        FeeShares memory fees
    ) internal {
        if (price > type(uint96).max) revert Errors.InvalidAmount(price);
        market.lastTradePrice = uint96(price);
        market.totalFeePool += fee;
        market.totalQuoteVolume += quoteVolume;
        market.makerQuoteVolume[maker] += quoteVolume;
        market.makerFeesAccrued[maker] += fees.makerFeeShare;
        market.creatorFeesEscrowed += fees.creatorFeeShare;
        market.protocolFeesAccrued += fees.treasuryFeeShare;
        LibMakerRewards.accrueMarketMakerReward(market, maker, quoteVolume);
    }

    function recordBookAndMarketFill(
        LibEveMarket.EveMarketStorage storage state,
        LibEveMarket.Book storage book,
        address maker,
        uint128 price,
        uint128 quoteVolume,
        uint128 fee,
        FeeShares memory fees
    ) internal {
        recordBookOnlyFill(book, maker, price, quoteVolume, fee, fees);
        if (book.marketId != bytes32(0) && state.markets[book.marketId].marketId != bytes32(0)) {
            recordMarketOnlyFill(state.markets[book.marketId], maker, price, quoteVolume, fee, fees);
        }
    }

    function retainedBuyFeeBalance(
        LibEveMarket.EveMarketStorage storage state,
        uint128 fee,
        LibEveMarket.BookFeeConfig storage feeConfig
    ) internal view returns (uint128 retainedFeeBalance) {
        uint128 makerFeeShare = uint128((uint256(fee) * feeConfig.makerFeeBps) / FEE_BPS_DENOMINATOR);
        uint128 creatorFeeShare = uint128((uint256(fee) * feeConfig.creatorFeeBps) / FEE_BPS_DENOMINATOR);
        uint128 resolverFeeShare = uint128((uint256(fee) * feeConfig.resolverFeeBps) / FEE_BPS_DENOMINATOR);

        if (!state.config.permissionlessCreationEnabled) {
            creatorFeeShare = 0;
        }

        retainedFeeBalance = makerFeeShare + creatorFeeShare + resolverFeeShare;
    }
}
