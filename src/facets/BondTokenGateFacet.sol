// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {IBondTokenGateFacet} from "../interfaces/IBondTokenGateFacet.sol";
import {Errors} from "../libraries/Errors.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";

contract BondTokenGateFacet is IBondTokenGateFacet {
    using SafeERC20 for IERC20;

    function lockResolutionBond(address bonder, uint8 escalationLevel) external {
        _enforceSelfCall();

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        uint128 required = _bondForLevel(state.config, escalationLevel);
        if (required == 0) {
            return;
        }

        address bondToken = state.config.bondToken;
        if (bondToken == address(0)) {
            revert Errors.ZeroAddress();
        }

        IERC20(bondToken).safeTransferFrom(bonder, address(this), required);
        state.resolutionBonded[bonder] += required;
    }

    function unlockResolutionBond(address bonder, uint128 amount) external {
        _enforceSelfCall();

        if (amount == 0) {
            return;
        }

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        address bondToken = state.config.bondToken;
        if (bondToken == address(0)) {
            revert Errors.ZeroAddress();
        }

        state.resolutionBonded[bonder] -= amount;
        IERC20(bondToken).safeTransfer(bonder, amount);
    }

    function _bondForLevel(LibEveMarket.MarketConfig storage config, uint8 escalationLevel)
        internal
        view
        returns (uint128)
    {
        if (escalationLevel == 1) {
            return config.resolutionBondL1;
        }

        if (escalationLevel >= 2) {
            return config.resolutionBondL2;
        }

        return 0;
    }

    function _enforceSelfCall() internal view {
        if (msg.sender != address(this)) {
            revert Errors.InternalCallOnly(msg.sender);
        }
    }
}
