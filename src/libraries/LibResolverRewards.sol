// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {Errors} from "./Errors.sol";
import {Events} from "./Events.sol";
import {LibEveMarket} from "./LibEveMarket.sol";
import {LibResolverJury} from "./LibResolverJury.sol";

library LibResolverRewards {
    using SafeERC20 for IERC20;

    function accrueTradingFee(address token, uint128 amount) internal {
        if (amount == 0) {
            return;
        }
        if (token == address(0)) {
            revert Errors.ZeroAddress();
        }

        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        uint64 epochId = jury.currentResolverEpoch;
        if (epochId == 0) {
            _transferToTreasury(token, amount);
            return;
        }

        LibResolverJury.ResolverEpoch storage epoch = jury.resolverEpochs[epochId];
        uint256 nextAmount = uint256(epoch.tradingRewardsAccrued[token]) + amount;
        if (nextAmount > type(uint128).max) {
            revert Errors.InvalidAmount(nextAmount);
        }
        epoch.tradingRewardsAccrued[token] = uint128(nextAmount);
    }

    function distributeSlashedStake(uint256 slashedIdentityId, address token, uint128 amount) internal {
        if (amount == 0) {
            return;
        }
        if (token == address(0)) {
            revert Errors.ZeroAddress();
        }

        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        uint64 epochId = jury.currentResolverEpoch;
        if (epochId == 0) {
            _transferToTreasury(token, amount);
            return;
        }

        LibResolverJury.ResolverEpoch storage epoch = jury.resolverEpochs[epochId];
        excludeFromEpoch(epochId, slashedIdentityId);
        uint256 recipientCount = epoch.compliantActiveCount;
        if (recipientCount == 0) {
            _transferToTreasury(token, amount);
            return;
        }

        uint256 perRecipient = uint256(amount) / recipientCount;
        if (perRecipient == 0) {
            _transferToTreasury(token, amount);
            return;
        }

        uint256 distributed;
        uint256 activeCount = epoch.activeSet.length;
        for (uint256 index; index < activeCount; ++index) {
            uint256 identityId = epoch.activeSet[index];
            if (epoch.rewardExcluded[identityId]) {
                continue;
            }

            distributed += perRecipient;
            _creditReward(jury, epochId, identityId, token, uint128(perRecipient));
        }

        uint256 remainder = uint256(amount) - distributed;
        if (remainder != 0) {
            _transferToTreasury(token, remainder);
        }
    }

    function excludeFromEpoch(uint64 epochId, uint256 identityId) internal {
        if (epochId == 0 || identityId == 0) {
            return;
        }

        LibResolverJury.ResolverEpoch storage epoch = LibResolverJury.store().resolverEpochs[epochId];
        if (epoch.activeIndex[identityId] == 0 || epoch.rewardExcluded[identityId]) {
            return;
        }

        epoch.rewardExcluded[identityId] = true;
        if (epoch.compliantActiveCount != 0) {
            epoch.compliantActiveCount -= 1;
        }
        emit Events.ResolverRewardExcluded(epochId, identityId);
    }

    function finalizeTradingRewards(uint64 epochId, address token) internal returns (uint128 amount) {
        if (token == address(0)) {
            revert Errors.ZeroAddress();
        }

        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        LibResolverJury.ResolverEpoch storage epoch = jury.resolverEpochs[epochId];
        if (epoch.epochId == 0 || block.timestamp < epoch.endTime) {
            revert Errors.ResolverEpochNotReady(epochId);
        }
        if (epoch.tradingRewardsFinalized[token]) {
            revert Errors.ResolverEpochAlreadyFinalized(epochId);
        }

        amount = epoch.tradingRewardsAccrued[token];
        epoch.tradingRewardsFinalized[token] = true;
        if (amount == 0) {
            emit Events.ResolverTradingRewardsFinalized(epochId, token, 0);
            return 0;
        }

        uint256 recipientCount = epoch.compliantActiveCount;
        if (recipientCount == 0) {
            _transferToTreasury(token, amount);
            emit Events.ResolverTradingRewardsFinalized(epochId, token, amount);
            return amount;
        }

        uint256 perRecipient = uint256(amount) / recipientCount;
        uint256 distributed;
        uint256 activeCount = epoch.activeSet.length;
        for (uint256 index; index < activeCount; ++index) {
            uint256 identityId = epoch.activeSet[index];
            if (epoch.rewardExcluded[identityId]) {
                continue;
            }

            distributed += perRecipient;
            _creditReward(jury, epochId, identityId, token, uint128(perRecipient));
        }

        uint256 remainder = uint256(amount) - distributed;
        if (remainder != 0) {
            _transferToTreasury(token, remainder);
        }
        emit Events.ResolverTradingRewardsFinalized(epochId, token, amount);
    }

    function claimable(uint256 identityId, address token)
        internal
        view
        returns (uint128 accrued, uint128 claimed, uint128 claimable_)
    {
        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        accrued = jury.resolverRewardsAccrued[identityId][token];
        claimed = jury.resolverRewardsClaimed[identityId][token];
        claimable_ = accrued - claimed;
    }

    function recordClaim(uint256 identityId, address token, uint128 amount) internal {
        if (amount == 0) {
            revert Errors.InvalidAmount(0);
        }
        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        jury.resolverRewardsClaimed[identityId][token] += amount;
    }

    function _creditReward(
        LibResolverJury.ResolverJuryStorage storage jury,
        uint64 epochId,
        uint256 identityId,
        address token,
        uint128 amount
    ) private {
        uint256 nextAmount = uint256(jury.resolverRewardsAccrued[identityId][token]) + amount;
        if (nextAmount > type(uint128).max) {
            revert Errors.InvalidAmount(nextAmount);
        }
        jury.resolverRewardsAccrued[identityId][token] = uint128(nextAmount);
        emit Events.ResolverRewardAccrued(epochId, identityId, token, amount);
    }

    function _transferToTreasury(address token, uint256 amount) private {
        address treasury = LibEveMarket.store().config.eveTreasury;
        if (treasury == address(0)) {
            revert Errors.ZeroAddress();
        }
        IERC20(token).safeTransfer(treasury, amount);
    }
}
