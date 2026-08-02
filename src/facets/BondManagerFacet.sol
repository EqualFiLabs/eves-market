// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {IBondManagerFacet} from "../interfaces/IBondManagerFacet.sol";
import {IBondTokenGateFacet} from "../interfaces/IBondTokenGateFacet.sol";
import {Errors} from "../libraries/Errors.sol";
import {Events} from "../libraries/Events.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";

contract BondManagerFacet is IBondManagerFacet {
    using SafeERC20 for IERC20;

    function slashBond(bytes32 marketId, uint256 proposalIndex, address recipient) external returns (uint128 amount) {
        _enforceSelfCall();

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        (LibEveMarket.Resolution storage proposal, address loser) = _loadBondedProposal(state, marketId, proposalIndex);
        amount = proposal.bondAmount;

        if (amount == 0) {
            revert Errors.NoBondToSlash(marketId, loser);
        }

        proposal.bondAmount = 0;

        state.bondedByMarket[marketId][loser] -= amount;
        state.resolutionBonded[loser] -= amount;
        if (recipient != address(0)) {
            IERC20(_requireBondToken(state)).safeTransfer(recipient, amount);
        }

        emit Events.BondSlashed(marketId, loser, amount);
    }

    function returnBond(bytes32 marketId, uint256 proposalIndex) external returns (uint128 amount) {
        _enforceSelfCall();

        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        (LibEveMarket.Resolution storage proposal, address winner) = _loadBondedProposal(state, marketId, proposalIndex);
        amount = proposal.bondAmount;

        if (amount == 0) {
            revert Errors.NoBondToReturn(marketId, winner);
        }

        proposal.bondAmount = 0;
        state.bondedByMarket[marketId][winner] -= amount;
        IBondTokenGateFacet(address(this)).unlockResolutionBond(winner, amount);
    }

    function routeBond(address recipient, uint128 amount) external {
        _enforceSelfCall();
        if (recipient == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (amount == 0) {
            return;
        }

        IERC20(_requireBondToken(LibEveMarket.store())).safeTransfer(recipient, amount);
    }

    function _loadBondedProposal(LibEveMarket.EveMarketStorage storage state, bytes32 marketId, uint256 proposalIndex)
        internal
        view
        returns (LibEveMarket.Resolution storage proposal, address proposer)
    {
        LibEveMarket.Resolution[] storage history = state.resolutionHistory[marketId];
        if (proposalIndex >= history.length) {
            revert Errors.InvalidResolutionIndex(marketId, proposalIndex);
        }

        proposal = history[proposalIndex];
        proposer = proposal.proposer;
    }

    function _enforceSelfCall() internal view {
        if (msg.sender != address(this)) {
            revert Errors.InternalCallOnly(msg.sender);
        }
    }

    function _requireBondToken(LibEveMarket.EveMarketStorage storage state) internal view returns (address bondToken) {
        bondToken = state.config.bondToken;
        if (bondToken == address(0)) {
            revert Errors.ZeroAddress();
        }
    }
}
