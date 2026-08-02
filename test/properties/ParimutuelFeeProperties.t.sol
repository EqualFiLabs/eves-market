// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {OwnershipFacet} from "../../src/facets/OwnershipFacet.sol";
import {FeeConfigFacet} from "../../src/facets/FeeConfigFacet.sol";
import {IParimutuelFacet} from "../../src/interfaces/IParimutuelFacet.sol";
import {ISeniorCapitalFacet} from "../../src/interfaces/ISeniorCapitalFacet.sol";
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
        bool hasSeniorPool,
        bool permissionlessEnabled
    ) public {
        uint128 amount = uint128(bound(uint256(amountSeed), 1, 1_000_000_000e6));
        uint16 entryFeeBps = uint16(bound(uint256(entryFeeSeed), 0, 9_999));
        uint16 creatorFeeBps = uint16(bound(uint256(creatorFeeSeed), 0, 10_000));
        uint16 protocolFeeBps = uint16(bound(uint256(protocolFeeSeed), 0, 10_000 - creatorFeeBps));
        uint16 seniorPoolFeeBps = uint16(10_000 - creatorFeeBps - protocolFeeBps);

        _setParimutuelFees(entryFeeBps, 1);

        vm.startPrank(owner);
        FeeConfigFacet(address(diamond)).setParimutuelFeeSplit(creatorFeeBps, protocolFeeBps, seniorPoolFeeBps, 0);
        vm.stopPrank();

        (bytes32 marketId,,,) = _createParimutuelMarket("fee exhaustiveness");

        vm.startPrank(owner);
        if (hasSeniorPool) {
            collateralToken.mint(owner, 1);
            collateralToken.approve(address(diamond), 1);
            ISeniorCapitalFacet(address(diamond)).depositSeniorCapital(1);
            vm.warp(block.timestamp + 24 hours);
            ISeniorCapitalFacet(address(diamond)).activateSeniorCapital();
        }
        OwnershipFacet(address(diamond)).setPermissionlessCreationEnabled(permissionlessEnabled);
        vm.stopPrank();

        (
            uint128 totalFee,
            uint128 creatorFee,
            uint128 protocolFee,
            uint128 seniorPoolFee,
            uint128 resolverFee,
            uint128 netShares
        ) = IParimutuelFacet(address(diamond)).previewEntryFee(marketId, amount);

        assertEq(uint256(creatorFee) + protocolFee + seniorPoolFee + resolverFee + netShares, amount);
        assertEq(uint256(creatorFee) + protocolFee + seniorPoolFee + resolverFee, totalFee);
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
