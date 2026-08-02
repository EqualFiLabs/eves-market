// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC1155} from "../../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";

import {IGnosisConditionalTokens} from "../interfaces/IGnosisConditionalTokens.sol";
import {IMarketSettlementFacet} from "../interfaces/IMarketSettlementFacet.sol";
import {Errors} from "../libraries/Errors.sol";
import {LibEveMarket} from "../libraries/LibEveMarket.sol";
import {LibParimutuel} from "../libraries/LibParimutuel.sol";

contract MarketSettlementFacet is IMarketSettlementFacet {
    uint256 internal constant YES_INDEX_SET = 1;
    uint256 internal constant NO_INDEX_SET = 2;

    function getCTFRedemptionParams(bytes32 marketId)
        external
        view
        returns (address collateralToken, bytes32 conditionId, uint256[] memory indexSets)
    {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Market storage market = state.markets[marketId];

        if (market.marketId != marketId) {
            revert Errors.MarketNotFound(marketId);
        }
        if (market.state != LibEveMarket.MarketState.Resolved) {
            revert Errors.MarketNotResolved(marketId);
        }
        _requireCTFPositionMarket(market);
        if (IGnosisConditionalTokens(market.positionToken).payoutDenominator(market.conditionId) == 0) {
            revert Errors.InvalidRedemptionParams(marketId);
        }

        collateralToken = market.collateralToken;
        conditionId = market.conditionId;
        indexSets = new uint256[](2);
        indexSets[0] = YES_INDEX_SET;
        indexSets[1] = NO_INDEX_SET;
    }

    function previewCTFRedemption(bytes32 marketId, address user)
        external
        view
        returns (uint256 claimableAmount, uint256 yesBalance, uint256 noBalance, uint8 outcome)
    {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Market storage market = state.markets[marketId];

        if (market.marketId != marketId) {
            revert Errors.MarketNotFound(marketId);
        }
        if (market.state != LibEveMarket.MarketState.Resolved) {
            revert Errors.MarketNotResolved(marketId);
        }

        _requireCTFPositionMarket(market);
        IGnosisConditionalTokens ctf = IGnosisConditionalTokens(market.positionToken);
        if (ctf.payoutDenominator(market.conditionId) == 0) {
            revert Errors.InvalidRedemptionParams(marketId);
        }

        yesBalance = ctf.balanceOf(user, market.yesPositionId);
        noBalance = ctf.balanceOf(user, market.noPositionId);
        outcome = uint8(market.outcome);

        if (outcome == uint8(LibEveMarket.MarketOutcome.Yes)) {
            claimableAmount = yesBalance;
        } else if (outcome == uint8(LibEveMarket.MarketOutcome.No)) {
            claimableAmount = noBalance;
        } else if (outcome == uint8(LibEveMarket.MarketOutcome.Invalid)) {
            claimableAmount = (yesBalance + noBalance) / 2;
        }
    }

    function previewParimutuelPayout(bytes32 marketId, address user)
        external
        view
        returns (uint256 claimableAmount, uint256 yesBalance, uint256 noBalance, uint8 outcome)
    {
        LibEveMarket.EveMarketStorage storage state = LibEveMarket.store();
        LibEveMarket.Market storage market = state.markets[marketId];

        if (market.marketId != marketId) {
            revert Errors.MarketNotFound(marketId);
        }
        if (market.state != LibEveMarket.MarketState.Resolved) {
            revert Errors.MarketNotResolved(marketId);
        }
        if (market.marketType != LibEveMarket.MarketType.PARIMUTUEL) {
            revert Errors.NotParimutuelMarket(marketId);
        }

        return _previewParimutuelRedemption(market, marketId, user);
    }

    function previewRedemption(bytes32 marketId, address user)
        external
        view
        returns (uint256 claimableAmount, uint256 yesBalance, uint256 noBalance, uint8 outcome)
    {
        LibEveMarket.Market storage market = LibEveMarket.store().markets[marketId];
        if (market.marketId != marketId) {
            revert Errors.MarketNotFound(marketId);
        }
        if (market.marketType == LibEveMarket.MarketType.PARIMUTUEL) {
            return this.previewParimutuelPayout(marketId, user);
        }

        return this.previewCTFRedemption(marketId, user);
    }

    function _previewParimutuelRedemption(LibEveMarket.Market storage market, bytes32 marketId, address user)
        internal
        view
        returns (uint256 claimableAmount, uint256 yesBalance, uint256 noBalance, uint8 outcome)
    {
        IERC1155 positionToken = IERC1155(market.positionToken);
        yesBalance = positionToken.balanceOf(user, market.yesPositionId);
        noBalance = positionToken.balanceOf(user, market.noPositionId);
        outcome = uint8(market.outcome);

        LibParimutuel.Pool storage pool = LibParimutuel.store().pools[marketId];
        LibParimutuel.requireFinalized(pool, marketId);
        LibEveMarket.MarketOutcome effectiveOutcome = pool.effectivePayoutOutcome;

        if (effectiveOutcome == LibEveMarket.MarketOutcome.Yes) {
            claimableAmount = (yesBalance * pool.payoutPoolAtResolution) / pool.totalClaimableSharesAtResolution;
        } else if (effectiveOutcome == LibEveMarket.MarketOutcome.No) {
            claimableAmount = (noBalance * pool.payoutPoolAtResolution) / pool.totalClaimableSharesAtResolution;
        } else if (effectiveOutcome == LibEveMarket.MarketOutcome.Invalid) {
            uint256 claimableShares = yesBalance + noBalance;
            if (pool.totalClaimableSharesAtResolution != 0) {
                claimableAmount =
                    (claimableShares * pool.payoutPoolAtResolution) / pool.totalClaimableSharesAtResolution;
            }
        }
    }

    function _requireCTFPositionMarket(LibEveMarket.Market storage market) internal view {
        if (market.positionTokenType != LibEveMarket.PositionTokenType.CTF) {
            revert Errors.PositionTokenTypeMismatch(
                market.marketId, uint8(LibEveMarket.PositionTokenType.CTF), uint8(market.positionTokenType)
            );
        }
    }
}
