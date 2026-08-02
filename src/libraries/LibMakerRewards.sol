// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Events} from "./Events.sol";
import {LibEveMarket} from "./LibEveMarket.sol";

library LibMakerRewards {
    uint256 internal constant BPS_DENOMINATOR = 10_000;

    function accrueMarketMakerReward(LibEveMarket.Market storage market, address maker, uint128 quoteVolume)
        internal
        returns (uint128 rewardAmount)
    {
        uint16 rewardRateBps = market.makerRewardRateBps;
        uint128 rewardsRemaining = market.makerRewardsRemaining;
        if (rewardRateBps == 0 || rewardsRemaining == 0 || quoteVolume == 0) {
            return 0;
        }

        uint256 computedReward = (uint256(quoteVolume) * uint256(rewardRateBps)) / BPS_DENOMINATOR;
        if (computedReward > rewardsRemaining) {
            computedReward = rewardsRemaining;
        }
        if (computedReward == 0) {
            return 0;
        }

        rewardAmount = uint128(computedReward);
        market.makerRewardsRemaining = rewardsRemaining - rewardAmount;
        market.makerRewardsClaimable[maker] += rewardAmount;

        emit Events.MarketMakerRewardAccrued(
            market.marketId, maker, quoteVolume, rewardAmount, market.makerRewardsRemaining
        );
    }
}
