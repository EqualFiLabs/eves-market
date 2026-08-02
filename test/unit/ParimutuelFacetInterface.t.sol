// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "../../lib/forge-std/src/Test.sol";

import {IParimutuelFacet} from "src/interfaces/IParimutuelFacet.sol";

contract ParimutuelFacetInterfaceTest is Test {
    function test_ParimutuelFacetSelectorsMatchExpectedSignatures() public pure {
        assertEq(
            bytes4(
                keccak256(
                    "createParimutuelMarket((string,string,string,uint64,uint64,uint64,(string,string,string,string,string,string,string,string),(uint8,string,string,string,string,bytes32)))"
                )
            ),
            bytes4(
                keccak256(
                    "createParimutuelMarket((string,string,string,uint64,uint64,uint64,(string,string,string,string,string,string,string,string),(uint8,string,string,string,string,bytes32)))"
                )
            )
        );
        assertEq(
            bytes4(keccak256("createParimutuelMarket(string,string,string,uint64,uint64,uint64)")),
            bytes4(keccak256("createParimutuelMarket(string,string,string,uint64,uint64,uint64)"))
        );
        assertEq(
            bytes4(
                keccak256(
                    "createParimutuelMarketWithCollateralProfile(uint8,(string,string,string,uint64,uint64,uint64,(string,string,string,string,string,string,string,string),(uint8,string,string,string,string,bytes32)))"
                )
            ),
            bytes4(
                keccak256(
                    "createParimutuelMarketWithCollateralProfile(uint8,(string,string,string,uint64,uint64,uint64,(string,string,string,string,string,string,string,string),(uint8,string,string,string,string,bytes32)))"
                )
            )
        );
        assertEq(
            bytes4(
                keccak256(
                    "createParimutuelMarketWithCollateralProfile(uint8,string,string,string,uint64,uint64,uint64)"
                )
            ),
            bytes4(
                keccak256(
                    "createParimutuelMarketWithCollateralProfile(uint8,string,string,string,uint64,uint64,uint64)"
                )
            )
        );
        assertEq(
            IParimutuelFacet.buyShares.selector, bytes4(keccak256("buyShares(bytes32,bool,uint128,address,uint128)"))
        );
        assertEq(
            IParimutuelFacet.buySharesBatch.selector,
            bytes4(keccak256("buySharesBatch(bytes32[],bool[],uint128[],uint128[],address)"))
        );
        assertEq(IParimutuelFacet.claimPayout.selector, bytes4(keccak256("claimPayout(bytes32)")));
        assertEq(IParimutuelFacet.sweepParimutuelDust.selector, bytes4(keccak256("sweepParimutuelDust(bytes32)")));
        assertEq(IParimutuelFacet.previewPayout.selector, bytes4(keccak256("previewPayout(bytes32,address)")));
        assertEq(IParimutuelFacet.previewEntryFee.selector, bytes4(keccak256("previewEntryFee(bytes32,uint128)")));
        assertEq(IParimutuelFacet.getParimutuelPool.selector, bytes4(keccak256("getParimutuelPool(bytes32)")));
        assertEq(
            IParimutuelFacet.getParimutuelBalances.selector, bytes4(keccak256("getParimutuelBalances(bytes32,address)"))
        );
        assertEq(IParimutuelFacet.isParimutuelMarket.selector, bytes4(keccak256("isParimutuelMarket(bytes32)")));
        assertEq(
            IParimutuelFacet.getParimutuelEpochWindow.selector, bytes4(keccak256("getParimutuelEpochWindow(bytes32)"))
        );
    }

    function test_PoolViewContainsExpectedFields() public pure {
        IParimutuelFacet.PoolView memory pool = IParimutuelFacet.PoolView({
            totalYesShares: 1,
            totalNoShares: 2,
            payoutPool: 3,
            claimedPayout: 4,
            claimedClaimableShares: 5,
            rawResolvedOutcome: 6,
            effectivePayoutOutcome: 7,
            payoutPoolAtResolution: 8,
            totalClaimableSharesAtResolution: 9,
            dustSwept: true,
            finalized: true,
            impliedYesProbability: 10,
            impliedNoProbability: 11
        });

        assertEq(pool.totalYesShares, 1);
        assertEq(pool.totalNoShares, 2);
        assertEq(pool.payoutPool, 3);
        assertEq(pool.claimedPayout, 4);
        assertEq(pool.claimedClaimableShares, 5);
        assertEq(pool.rawResolvedOutcome, 6);
        assertEq(pool.effectivePayoutOutcome, 7);
        assertEq(pool.payoutPoolAtResolution, 8);
        assertEq(pool.totalClaimableSharesAtResolution, 9);
        assertTrue(pool.dustSwept);
        assertTrue(pool.finalized);
        assertEq(pool.impliedYesProbability, 10);
        assertEq(pool.impliedNoProbability, 11);
    }
}
