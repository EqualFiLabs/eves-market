// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IParimutuelFacet} from "../../src/interfaces/IParimutuelFacet.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";

import {ParimutuelPropertiesBase} from "./ParimutuelPropertiesBase.t.sol";

contract ParimutuelPayoutPropertiesTest is ParimutuelPropertiesBase {
    // Feature: parimutuel-facet, Property 7: payout claim correctness
    function testFuzz_WinningPayoutMatchesProRataMathAndBurnsWinningShares(
        uint128 userWinningSeed,
        uint128 otherWinningSeed,
        uint128 losingSeed,
        bool yesOutcome
    ) public {
        uint128 userWinningShares = uint128(bound(uint256(userWinningSeed), 1, 1_000_000_000e6));
        uint128 otherWinningShares = uint128(bound(uint256(otherWinningSeed), 1, 1_000_000_000e6));
        uint128 losingShares = uint128(bound(uint256(losingSeed), 0, 1_000_000_000e6));

        _setParimutuelFees(0, 1);
        (bytes32 marketId, uint64 expiryTime, uint256 yesPositionId, uint256 noPositionId) =
            _createParimutuelMarket("winning payout property");

        // 0% fee, epoch 0 (2x): shares = amount * 2
        uint128 userActualShares = userWinningShares * 2;
        uint128 otherActualShares = otherWinningShares * 2;

        uint256 winningPositionId = yesOutcome ? yesPositionId : noPositionId;
        _buyShares(alice, marketId, yesOutcome, userWinningShares, alice);
        _buyShares(carol, marketId, yesOutcome, otherWinningShares, carol);
        if (losingShares != 0) {
            _buyShares(bob, marketId, !yesOutcome, losingShares, bob);
        }

        LibEveMarket.MarketOutcome outcome = yesOutcome ? LibEveMarket.MarketOutcome.Yes : LibEveMarket.MarketOutcome.No;
        _resolveParimutuelMarket(marketId, expiryTime, outcome);

        IParimutuelFacet.PoolView memory poolBefore = IParimutuelFacet(address(diamond)).getParimutuelPool(marketId);
        uint256 expectedPayout =
            (uint256(userActualShares) * poolBefore.payoutPool) / (userActualShares + otherActualShares);

        vm.prank(alice);
        uint128 payout = IParimutuelFacet(address(diamond)).claimPayout(marketId);

        IParimutuelFacet.PoolView memory poolAfter = IParimutuelFacet(address(diamond)).getParimutuelPool(marketId);

        assertEq(payout, expectedPayout);
        assertEq(shareToken.balanceOf(alice, winningPositionId), 0);
        assertEq(poolAfter.claimedPayout, expectedPayout);
        assertEq(poolAfter.claimedClaimableShares, userActualShares);
        assertLe(poolAfter.claimedPayout, poolAfter.payoutPool);
    }

    // Feature: parimutuel-facet, Property 7: INVALID payout pro-rata refund semantics
    function testFuzz_InvalidOutcomeRefundsProRataAndBurnsBothSides(uint128 yesSeed, uint128 noSeed) public {
        uint128 yesShares = uint128(bound(uint256(yesSeed), 0, 1_000_000_000e6));
        uint128 noShares = uint128(bound(uint256(noSeed), 0, 1_000_000_000e6));
        if (yesShares == 0 && noShares == 0) {
            yesShares = 1;
        }

        _setParimutuelFees(0, 1);
        (bytes32 marketId, uint64 expiryTime, uint256 yesPositionId, uint256 noPositionId) =
            _createParimutuelMarket("invalid refund property");

        if (yesShares != 0) {
            _buyShares(alice, marketId, true, yesShares, alice);
        }
        if (noShares != 0) {
            _buyShares(alice, marketId, false, noShares, alice);
        }

        _resolveParimutuelMarket(marketId, expiryTime, LibEveMarket.MarketOutcome.Invalid);

        // Alice is the only participant, so she gets the full pool back (= her total collateral)
        vm.prank(alice);
        uint128 payout = IParimutuelFacet(address(diamond)).claimPayout(marketId);

        assertEq(payout, uint256(yesShares) + noShares);
        assertEq(shareToken.balanceOf(alice, yesPositionId), 0);
        assertEq(shareToken.balanceOf(alice, noPositionId), 0);
    }

    // Feature: parimutuel-facet, Property 8: payout pool solvency invariant
    function testFuzz_ClaimedPayoutNeverExceedsPool(
        uint128 firstWinnerSeed,
        uint128 secondWinnerSeed,
        uint128 loserSeed
    ) public {
        uint128 firstWinner = uint128(bound(uint256(firstWinnerSeed), 1, 1_000_000_000e6));
        uint128 secondWinner = uint128(bound(uint256(secondWinnerSeed), 1, 1_000_000_000e6));
        uint128 loser = uint128(bound(uint256(loserSeed), 0, 1_000_000_000e6));

        _setParimutuelFees(0, 1);
        (bytes32 marketId, uint64 expiryTime,,) = _createParimutuelMarket("solvency property");

        _buyShares(alice, marketId, true, firstWinner, alice);
        _buyShares(carol, marketId, true, secondWinner, carol);
        if (loser != 0) {
            _buyShares(bob, marketId, false, loser, bob);
        }

        _resolveParimutuelMarket(marketId, expiryTime, LibEveMarket.MarketOutcome.Yes);

        vm.prank(alice);
        IParimutuelFacet(address(diamond)).claimPayout(marketId);
        IParimutuelFacet.PoolView memory afterFirstClaim =
            IParimutuelFacet(address(diamond)).getParimutuelPool(marketId);
        assertLe(afterFirstClaim.claimedPayout, afterFirstClaim.payoutPool);

        vm.prank(carol);
        IParimutuelFacet(address(diamond)).claimPayout(marketId);
        IParimutuelFacet.PoolView memory afterSecondClaim =
            IParimutuelFacet(address(diamond)).getParimutuelPool(marketId);
        assertLe(afterSecondClaim.claimedPayout, afterSecondClaim.payoutPool);
    }

    // Feature: parimutuel-facet, Property 8a: dust never sweeps unclaimed payouts
    function testFuzz_DustSweepRequiresAllClaimableSharesBurned(
        uint128 firstWinnerSeed,
        uint128 secondWinnerSeed,
        uint128 loserSeed
    ) public {
        uint128 firstWinner = uint128(bound(uint256(firstWinnerSeed), 1, 1_000_000_000e6));
        uint128 secondWinner = uint128(bound(uint256(secondWinnerSeed), 1, 1_000_000_000e6));
        uint128 loser = uint128(bound(uint256(loserSeed), 0, 1_000_000_000e6));

        _setParimutuelFees(0, 1);
        (bytes32 marketId, uint64 expiryTime,,) = _createParimutuelMarket("dust property");

        _buyShares(alice, marketId, true, firstWinner, alice);
        _buyShares(carol, marketId, true, secondWinner, carol);
        if (loser != 0) {
            _buyShares(bob, marketId, false, loser, bob);
        }

        _resolveParimutuelMarket(marketId, expiryTime, LibEveMarket.MarketOutcome.Yes);

        vm.prank(alice);
        IParimutuelFacet(address(diamond)).claimPayout(marketId);

        // carol's remaining shares = secondWinner * 2 (epoch 0, 2x multiplier)
        vm.expectRevert(abi.encodeWithSelector(Errors.ClaimableSharesRemain.selector, marketId, secondWinner * 2));
        IParimutuelFacet(address(diamond)).sweepParimutuelDust(marketId);

        vm.prank(carol);
        IParimutuelFacet(address(diamond)).claimPayout(marketId);

        IParimutuelFacet.PoolView memory beforeSweep = IParimutuelFacet(address(diamond)).getParimutuelPool(marketId);
        uint128 expectedSwept = beforeSweep.payoutPool - beforeSweep.claimedPayout;
        uint256 diamondBalanceBefore = collateralToken.balanceOf(address(diamond));

        uint128 swept = IParimutuelFacet(address(diamond)).sweepParimutuelDust(marketId);

        assertEq(swept, expectedSwept);
        assertEq(diamondBalanceBefore - collateralToken.balanceOf(address(diamond)), expectedSwept);
    }
}
