// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {OwnershipFacet} from "../../src/facets/OwnershipFacet.sol";
import {VaultFeeRoutingFixture} from "../helpers/VaultFeeRoutingFixture.sol";

contract FeeRoutingPropertiesTest is VaultFeeRoutingFixture {
    function testFuzz_TradeFeeRevenueRoutesBetweenVaultAndTreasury(uint16 vaultFeeBpsSeed, uint128 collateralSeed)
        public
    {
        // Vault fee is bounded to [0, 1000] (max 10% of total fee to vault)
        uint16 vaultFeeBps = uint16(bound(uint256(vaultFeeBpsSeed), 0, 1_000));
        uint128 collateralIn = uint128(bound(uint256(collateralSeed), 1_000e6, 4_200e6));

        // 4-way split: maker 85%, creator 5%, protocol (10% - vault%), vault%
        uint16 protocolBps = uint16(1_000 - vaultFeeBps);

        _depositStake(1_000e6);

        vm.startPrank(owner);
        OwnershipFacet(address(diamond)).setStakingVault(address(vault));
        OwnershipFacet(address(diamond)).setOrderbookFeeSplit(8_500, 500, protocolBps, vaultFeeBps);
        vm.stopPrank();

        (bytes32 marketId,) = _createTradingMarket("vault-routing-property", 7 days);
        _splitFromMaker(marketId, DEFAULT_MAKER_INVENTORY);
        _approvePositions(maker);

        uint256 curveId =
            _postCurveFromMaker(marketId, true, DEFAULT_MAKER_INVENTORY, DEFAULT_FLAT_PRICE, DEFAULT_FLAT_PRICE, 180);

        uint256 treasuryBalanceBefore = eveUSDC.balanceOf(treasury);
        uint256 vaultAssetsBefore = vault.totalAssets();
        uint256 vaultSupplyBefore = vault.totalSupply();

        (, uint128 fee,) = _fillCurveFromTaker(curveId, collateralIn);
        uint128 expectedVaultShare = _vaultShare(fee, vaultFeeBps);
        uint128 expectedTreasuryShare = _treasuryShare(fee, vaultFeeBps);

        (, uint128 protocolFeesAccrued,,) = _storedMarketFees(marketId);

        assertEq(eveUSDC.balanceOf(treasury) - treasuryBalanceBefore, expectedTreasuryShare);
        assertEq(vault.totalAssets() - vaultAssetsBefore, expectedVaultShare);
        assertEq(vault.totalSupply(), vaultSupplyBefore);
        assertEq(protocolFeesAccrued, expectedTreasuryShare);
    }
}
