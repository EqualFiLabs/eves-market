// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IMarketSettlementFacet} from "../../src/interfaces/IMarketSettlementFacet.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";

import {ResolutionHarnessFacet, SettlementFeeFixture, StateProbeFacet} from "../helpers/DiamondFixtures.sol";
import {MockConditionalTokens} from "../helpers/MockConditionalTokens.sol";

contract MarketSettlementParimutuelTest is SettlementFeeFixture {
    // Synthetic storage setup is limited to market typing, pool totals, and ERC-1155 balances for view isolation.

    function test_PreviewRedemptionReturnsParimutuelPayoutMath() public {
        (bytes32 marketId,, uint64 expiryTime) =
            _createTradingMarket("focused parimutuel redemption", "settlement-parimutuel", 7 days);
        MockConditionalTokens positionToken = _markParimutuelMarket(marketId);
        (uint256 yesPositionId, uint256 noPositionId) = _positionIds(marketId);

        positionToken.mintPosition(maker, yesPositionId, 250e6);
        positionToken.mintPosition(maker, noPositionId, 80e6);
        _setParimutuelPool(marketId, 1_000e6, 2_000e6, 6_000e6);
        _finalizeCreatorResolution(marketId, expiryTime, uint8(LibEveMarket.MarketOutcome.Yes));

        (uint256 claimableAmount, uint256 yesBalance, uint256 noBalance, uint8 outcome) =
            IMarketSettlementFacet(address(diamond)).previewRedemption(marketId, maker);

        assertEq(outcome, uint8(LibEveMarket.MarketOutcome.Yes));
        assertEq(yesBalance, 250e6);
        assertEq(noBalance, 80e6);
        assertEq(claimableAmount, 1_500e6);
    }

    function test_RevertWhen_GetRedemptionParamsForParimutuelMarket() public {
        (bytes32 marketId,, uint64 expiryTime) =
            _createTradingMarket("focused parimutuel params", "settlement-parimutuel", 7 days);

        _markParimutuelMarket(marketId);
        _setParimutuelPool(marketId, 100e6, 200e6, 300e6);
        _finalizeCreatorResolution(marketId, expiryTime, uint8(LibEveMarket.MarketOutcome.Yes));

        vm.expectRevert(_positionTokenTypeMismatch(marketId));
        IMarketSettlementFacet(address(diamond)).getCTFRedemptionParams(marketId);
    }

    function _markParimutuelMarket(bytes32 marketId) internal returns (MockConditionalTokens positionToken) {
        positionToken = new MockConditionalTokens();
        ResolutionHarnessFacet(address(diamond))
            .setMarketTypeAndPositionToken(
                marketId, uint256(uint8(LibEveMarket.MarketType.PARIMUTUEL)), address(positionToken)
            );
    }

    function _setParimutuelPool(bytes32 marketId, uint128 totalYesShares, uint128 totalNoShares, uint128 payoutPool)
        internal
    {
        ResolutionHarnessFacet(address(diamond))
            .setParimutuelPool(marketId, totalYesShares, totalNoShares, payoutPool, 0, 0, false);
    }

    function _positionIds(bytes32 marketId) internal view returns (uint256 yesPositionId, uint256 noPositionId) {
        (,,,, yesPositionId, noPositionId) = StateProbeFacet(address(diamond)).getStoredMarketCore(marketId);
    }

    function _positionTokenTypeMismatch(bytes32 marketId) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(
            Errors.PositionTokenTypeMismatch.selector,
            marketId,
            uint8(LibEveMarket.PositionTokenType.CTF),
            uint8(LibEveMarket.PositionTokenType.PARIMUTUEL)
        );
    }
}
