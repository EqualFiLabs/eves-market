// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {Errors} from "../libraries/Errors.sol";
import {Events} from "../libraries/Events.sol";
import {LibReentrancy} from "../libraries/LibReentrancy.sol";
import {LibResolverJury} from "../libraries/LibResolverJury.sol";
import {LibResolverRewards} from "../libraries/LibResolverRewards.sol";

contract ResolverRegistryRewardsFacet {
    using SafeERC20 for IERC20;

    modifier rewardsNonReentrant() {
        LibReentrancy.enter();
        _;
        LibReentrancy.exit();
    }

    function finalizeResolverTradingRewards(uint64 epochId, address token)
        external
        rewardsNonReentrant
        returns (uint128 amount)
    {
        amount = LibResolverRewards.finalizeTradingRewards(epochId, token);
    }

    function claimResolverRewards(address token) external rewardsNonReentrant returns (uint128 amount) {
        if (token == address(0)) {
            revert Errors.ZeroAddress();
        }

        LibResolverJury.ResolverJuryStorage storage jury = LibResolverJury.store();
        address identityContract = jury.eveIdentity;
        if (identityContract == address(0)) {
            revert Errors.ZeroAddress();
        }

        uint256 identityId = LibResolverJury.requireIdentityId(identityContract, msg.sender);
        (,, amount) = LibResolverRewards.claimable(identityId, token);
        LibResolverRewards.recordClaim(identityId, token, amount);
        IERC20(token).safeTransfer(msg.sender, amount);

        emit Events.ResolverRewardsClaimed(identityId, msg.sender, token, amount);
    }
}
