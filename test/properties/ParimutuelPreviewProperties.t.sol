// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IParimutuelFacet} from "../../src/interfaces/IParimutuelFacet.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";

import {ParimutuelPropertiesBase} from "./ParimutuelPropertiesBase.t.sol";

contract ParimutuelPreviewPropertiesTest is ParimutuelPropertiesBase {
    // Feature: parimutuel-facet, Property 9: payout preview consistency
    function testFuzz_PreviewPayoutMatchesClaimPayout(
        uint8 outcomeSeed,
        uint128 userYesSeed,
        uint128 userNoSeed,
        uint128 otherYesSeed,
        uint128 otherNoSeed
    ) public {
        LibEveMarket.MarketOutcome outcome = LibEveMarket.MarketOutcome(bound(uint256(outcomeSeed), 1, 3));
        uint128 userYes = uint128(bound(uint256(userYesSeed), 0, 1_000_000_000e6));
        uint128 userNo = uint128(bound(uint256(userNoSeed), 0, 1_000_000_000e6));
        uint128 otherYes = uint128(bound(uint256(otherYesSeed), 0, 1_000_000_000e6));
        uint128 otherNo = uint128(bound(uint256(otherNoSeed), 0, 1_000_000_000e6));

        if (outcome == LibEveMarket.MarketOutcome.Yes && userYes == 0) {
            userYes = 1;
        } else if (outcome == LibEveMarket.MarketOutcome.No && userNo == 0) {
            userNo = 1;
        } else if (outcome == LibEveMarket.MarketOutcome.Invalid && userYes == 0 && userNo == 0) {
            userYes = 1;
        }

        (bytes32 marketId, uint64 expiryTime,,) = _createParimutuelMarket("preview property");
        _setParimutuelFees(0, 1);

        if (userYes != 0) {
            _buyShares(alice, marketId, true, userYes, alice);
        }
        if (userNo != 0) {
            _buyShares(alice, marketId, false, userNo, alice);
        }
        if (otherYes != 0) {
            _buyShares(bob, marketId, true, otherYes, bob);
        }
        if (otherNo != 0) {
            _buyShares(carol, marketId, false, otherNo, carol);
        }

        _resolveParimutuelMarket(marketId, expiryTime, outcome);

        (uint256 previewAmount,,,) = IParimutuelFacet(address(diamond)).previewPayout(marketId, alice);

        vm.prank(alice);
        uint128 actualPayout = IParimutuelFacet(address(diamond)).claimPayout(marketId);

        assertEq(actualPayout, previewAmount);
    }
}
