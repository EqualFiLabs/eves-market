// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {OwnershipFacet} from "../../src/facets/OwnershipFacet.sol";
import {IParimutuelFacet} from "../../src/interfaces/IParimutuelFacet.sol";
import {SEveUSDCVault} from "../../src/SEveUSDCVault.sol";
import {Errors} from "../../src/libraries/Errors.sol";

import {ResolutionHarnessFacet} from "../helpers/DiamondFixtures.sol";
import {ParimutuelPropertiesBase} from "./ParimutuelPropertiesBase.t.sol";

contract ParimutuelFeePropertiesTest is ParimutuelPropertiesBase {
    // Feature: parimutuel-facet, Property 1: fee split exhaustiveness
    function testFuzz_EntryFeeBreakdownIsExhaustive(
        uint128 amountSeed,
        uint16 entryFeeSeed,
        uint16 creatorFeeSeed,
        uint16 protocolFeeSeed,
        bool hasVault,
        bool permissionlessEnabled
    ) public {
        uint128 amount = uint128(bound(uint256(amountSeed), 1, 1_000_000_000e6));
        uint16 entryFeeBps = uint16(bound(uint256(entryFeeSeed), 0, 9_999));
        uint16 creatorFeeBps = uint16(bound(uint256(creatorFeeSeed), 0, 10_000));
        uint16 protocolFeeBps = uint16(bound(uint256(protocolFeeSeed), 0, 10_000 - creatorFeeBps));
        uint16 vaultFeeBps = uint16(10_000 - creatorFeeBps - protocolFeeBps);

        _setParimutuelFees(entryFeeBps, 1);

        vm.startPrank(owner);
        OwnershipFacet(address(diamond)).setParimutuelFeeSplit(creatorFeeBps, protocolFeeBps, vaultFeeBps);
        vm.stopPrank();

        (bytes32 marketId,,,) = _createParimutuelMarket("fee exhaustiveness");

        vm.startPrank(owner);
        address stakingVault = hasVault
            ? address(new SEveUSDCVault(address(collateralToken), owner, treasury, 0, address(diamond)))
            : address(0);
        OwnershipFacet(address(diamond)).setStakingVault(stakingVault);
        OwnershipFacet(address(diamond)).setPermissionlessCreationEnabled(permissionlessEnabled);
        vm.stopPrank();

        (uint128 totalFee, uint128 creatorFee, uint128 protocolFee, uint128 vaultFee, uint128 netShares) =
            IParimutuelFacet(address(diamond)).previewEntryFee(marketId, amount);

        assertEq(uint256(creatorFee) + protocolFee + vaultFee + netShares, amount);
        assertEq(uint256(creatorFee) + protocolFee + vaultFee, totalFee);
    }

    // Feature: parimutuel-facet, Property 1: invalid creator/protocol split rejects
    function testFuzz_InvalidCreatorProtocolEntryFeeSplitReverts(uint128 amountSeed, uint16 creatorFeeSeed) public {
        uint128 amount = uint128(bound(uint256(amountSeed), 1, 1_000_000_000e6));
        uint16 creatorFeeBps = uint16(bound(uint256(creatorFeeSeed), 1, 10_000));
        uint16 protocolFeeBps = uint16(bound(uint256(creatorFeeSeed), 10_001 - creatorFeeBps, 10_000));

        ResolutionHarnessFacet(address(diamond)).setFeeSplitConfig(0, creatorFeeBps, protocolFeeBps, 0);
        (bytes32 marketId,,,) = _createParimutuelMarket("invalid fee split");

        vm.expectRevert(
            abi.encodeWithSelector(Errors.FeeSplitExceedsDenominator.selector, creatorFeeBps, protocolFeeBps)
        );
        IParimutuelFacet(address(diamond)).previewEntryFee(marketId, amount);
    }
}
