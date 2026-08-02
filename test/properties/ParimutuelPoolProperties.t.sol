// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IParimutuelFacet} from "../../src/interfaces/IParimutuelFacet.sol";

import {ResolutionHarnessFacet, StateProbeFacet} from "../helpers/DiamondFixtures.sol";
import {ParimutuelPropertiesBase} from "./ParimutuelPropertiesBase.t.sol";

contract ParimutuelPoolPropertiesTest is ParimutuelPropertiesBase {
    uint256 internal constant EPOCH_MULTIPLIER_SCALE = 10_000;

    // Feature: parimutuel-facet, Property 6: buy shares pool accounting
    function testFuzz_BuySharesMatchesEntryPreviewAcrossEpochs(
        uint128 amountSeed,
        uint16 entryFeeSeed,
        uint8 epochSeed,
        bool isYes
    ) public {
        uint128 amount = uint128(bound(uint256(amountSeed), 5, 1_000_000_000e6));
        uint16 entryFeeBps = uint16(bound(uint256(entryFeeSeed), 0, 5_000));
        uint8 expectedEpoch = uint8(bound(uint256(epochSeed), 0, 7));
        _setParimutuelFees(entryFeeBps, 1);
        (bytes32 marketId,,,) = _createParimutuelMarket("pool accounting");

        (, uint64 createdAt, uint64 expiryTime,,,,,) =
            StateProbeFacet(address(diamond)).getStoredMarketStatus(marketId);
        uint256 duration = uint256(expiryTime) - createdAt;
        vm.warp(createdAt + ((duration * expectedEpoch) / 8));

        IParimutuelFacet.EntryPreview memory preview =
            IParimutuelFacet(address(diamond)).previewParimutuelEntry(marketId, isYes, amount);
        uint128 sharesMinted = _buyShares(alice, marketId, isYes, amount, bob);

        IParimutuelFacet.PoolView memory afterPool = IParimutuelFacet(address(diamond)).getParimutuelPool(marketId);
        (uint256 bobYesShares, uint256 bobNoShares) = IParimutuelFacet(address(diamond)).getParimutuelBalances(marketId, bob);

        assertEq(preview.epoch, expectedEpoch);
        assertEq(sharesMinted, preview.sharesMinted);
        assertEq(afterPool.payoutPool, preview.netCollateral);
        assertEq(afterPool.payoutPool, preview.payoutPoolAfter);
        if (isYes) {
            assertEq(afterPool.totalYesShares, preview.totalYesSharesAfter);
            assertEq(afterPool.totalNoShares, preview.totalNoSharesAfter);
            assertEq(bobYesShares, preview.sharesMinted);
            assertEq(bobNoShares, 0);
        } else {
            assertEq(afterPool.totalYesShares, preview.totalYesSharesAfter);
            assertEq(afterPool.totalNoShares, preview.totalNoSharesAfter);
            assertEq(bobYesShares, 0);
            assertEq(bobNoShares, preview.sharesMinted);
        }

        uint256 expectedShares =
            (uint256(preview.netCollateral) * preview.multiplierBps) / EPOCH_MULTIPLIER_SCALE;
        assertEq(preview.sharesMinted, expectedShares);

        if (preview.multiplierBps > EPOCH_MULTIPLIER_SCALE) {
            assertGe(preview.sharesMinted, preview.netCollateral);
        } else if (preview.multiplierBps == EPOCH_MULTIPLIER_SCALE) {
            assertEq(preview.sharesMinted, preview.netCollateral);
        } else {
            assertLt(preview.sharesMinted, preview.netCollateral);
        }
    }

    // Feature: parimutuel-facet, Property 10: implied probability computation
    function testFuzz_ImpliedProbabilitiesSumToScale(uint128 yesSeed, uint128 noSeed) public {
        uint128 yesShares = uint128(bound(uint256(yesSeed), 0, 1_000_000_000e6));
        uint128 noShares = uint128(bound(uint256(noSeed), 0, 1_000_000_000e6));
        if (yesShares == 0 && noShares == 0) {
            yesShares = 1;
        }

        (bytes32 marketId,,,) = _createParimutuelMarket("implied probability");
        ResolutionHarnessFacet(address(diamond))
            .setParimutuelPool(marketId, yesShares, noShares, uint256(yesShares) + noShares, 0, 0, false);

        IParimutuelFacet.PoolView memory pool = IParimutuelFacet(address(diamond)).getParimutuelPool(marketId);

        assertApproxEqAbs(uint256(pool.impliedYesProbability) + pool.impliedNoProbability, 1e18, 1);
    }
}
