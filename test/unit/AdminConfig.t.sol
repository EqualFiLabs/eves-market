// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IConditionalTokens} from "../../src/interfaces/IConditionalTokens.sol";
import {IGnosisConditionalTokens} from "../../src/interfaces/IGnosisConditionalTokens.sol";
import {IParimutuelShareToken} from "../../src/interfaces/IParimutuelShareToken.sol";
import {OwnershipFacet} from "../../src/facets/OwnershipFacet.sol";
import {FeeConfigFacet} from "../../src/facets/FeeConfigFacet.sol";
import {IMarketFactoryFacet} from "../../src/interfaces/IMarketFactoryFacet.sol";
import {ParimutuelShareToken} from "../../src/tokens/ParimutuelShareToken.sol";
import {Errors} from "../../src/libraries/Errors.sol";

import {SettlementFeeFixture, StateProbeFacet} from "../helpers/DiamondFixtures.sol";
import {MockConditionalTokens} from "../helpers/MockConditionalTokens.sol";
import {MockUSDG} from "../helpers/MockUSDG.sol";
import {MarketFactoryTypes} from "../../src/types/MarketFactoryTypes.sol";

contract EmptyContract {}

contract AdminConfigTest is SettlementFeeFixture {
    event OrderbookEntryFeeBpsSet(uint16 previousEntryFeeBps, uint16 newEntryFeeBps);
    event SpotTradeFeeBpsSet(uint16 previousTradeFeeBps, uint16 newTradeFeeBps);
    event OrderbookFeeSplitSet(
        uint16 makerFeeBps, uint16 creatorFeeBps, uint16 protocolFeeBps, uint16 seniorPoolFeeBps, uint16 resolverFeeBps
    );
    event SpotFeeSplitSet(uint16 makerFeeBps, uint16 protocolFeeBps, uint16 seniorPoolFeeBps, uint16 resolverFeeBps);
    event MarketCreationFeeSet(uint128 previousMarketCreationFee, uint128 newMarketCreationFee);
    event SpotBookCreationFeeSet(uint128 previousSpotBookCreationFee, uint128 newSpotBookCreationFee);
    event DefaultConditionalTokensSet(
        address indexed previousDefaultConditionalTokens, address indexed newDefaultConditionalTokens
    );
    event CollateralTokenSet(address indexed previousCollateralToken, address indexed newCollateralToken);
    event CollateralProfileSet(
        uint8 indexed profileId,
        address indexed collateralToken,
        address indexed wrapperToken,
        uint128 payoutUnit,
        uint128 marketCreationFee,
        bool enabled
    );
    event CollateralProfileEnabledSet(uint8 indexed profileId, bool previousEnabled, bool newEnabled);
    event CollateralProfilePayoutUnitSet(uint8 indexed profileId, uint128 previousPayoutUnit, uint128 newPayoutUnit);
    event CollateralProfileMarketCreationFeeSet(
        uint8 indexed profileId, uint128 previousMarketCreationFee, uint128 newMarketCreationFee
    );
    event CollateralProfileParimutuelCreationSeedAmountSet(
        uint8 indexed profileId, uint128 previousParimutuelCreationSeedAmount, uint128 newParimutuelCreationSeedAmount
    );
    event CollateralProfileParimutuelMinEntrySet(
        uint8 indexed profileId, uint128 previousParimutuelMinEntry, uint128 newParimutuelMinEntry
    );
    event CollateralProfileParlayUnderwritingFeeSet(
        uint8 indexed profileId, uint128 previousParlayUnderwritingFee, uint128 newParlayUnderwritingFee
    );
    event PermissionlessCreationSet(bool previousEnabled, bool newEnabled);

    function test_AdminSettersRejectMissingCodeAndWrongInterfaces() public {
        address eoa = makeAddr("admin-eoa");
        address empty = address(new EmptyContract());
        ParimutuelShareToken wrongDiamondShareToken = new ParimutuelShareToken(makeAddr("wrong-diamond"), "");

        vm.startPrank(owner);

        vm.expectRevert(abi.encodeWithSelector(Errors.ContractHasNoCode.selector, eoa));
        OwnershipFacet(address(diamond)).setCollateralToken(eoa);

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.InvalidContractInterface.selector, empty, IGnosisConditionalTokens.getConditionId.selector
            )
        );
        OwnershipFacet(address(diamond)).setDefaultConditionalTokens(empty);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidContractInterface.selector, empty, IERC20.totalSupply.selector)
        );
        OwnershipFacet(address(diamond)).setEveToken(empty);

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.InvalidContractInterface.selector,
                address(wrongDiamondShareToken),
                IParimutuelShareToken.diamond.selector
            )
        );
        OwnershipFacet(address(diamond)).setParimutuelConfig(address(wrongDiamondShareToken), 250, 1);

        vm.stopPrank();
    }

    function test_AdminCanConfigureCollateralProfileAndViewIt() public {
        uint8 profileId = 1;
        MockUSDG profileCollateral = new MockUSDG();
        MockUSDG wrapperToken = new MockUSDG();
        uint128 payoutUnit = 0.0005 ether;
        uint128 marketCreationFee = 0.002 ether;

        vm.startPrank(owner);

        vm.expectEmit(true, true, true, true, address(diamond));
        emit CollateralProfileSet(
            profileId, address(profileCollateral), address(wrapperToken), payoutUnit, marketCreationFee, true
        );
        OwnershipFacet(address(diamond))
            .setCollateralProfile(
                profileId, address(profileCollateral), address(wrapperToken), payoutUnit, marketCreationFee, true
            );

        MarketFactoryTypes.CollateralProfileView memory profile =
            IMarketFactoryFacet(address(diamond)).getCollateralProfile(profileId);
        assertEq(profile.collateralToken, address(profileCollateral));
        assertEq(profile.wrapperToken, address(wrapperToken));
        assertEq(profile.payoutUnit, payoutUnit);
        assertEq(profile.marketCreationFee, marketCreationFee);
        assertTrue(profile.enabled);

        vm.expectEmit(true, false, false, true, address(diamond));
        emit CollateralProfilePayoutUnitSet(profileId, payoutUnit, 0.001 ether);
        OwnershipFacet(address(diamond)).setCollateralProfilePayoutUnit(profileId, 0.001 ether);

        vm.expectEmit(true, false, false, true, address(diamond));
        emit CollateralProfileMarketCreationFeeSet(profileId, marketCreationFee, 0.003 ether);
        OwnershipFacet(address(diamond)).setCollateralProfileMarketCreationFee(profileId, 0.003 ether);

        vm.expectEmit(true, false, false, true, address(diamond));
        emit CollateralProfileParimutuelCreationSeedAmountSet(profileId, 0, 0.004 ether);
        OwnershipFacet(address(diamond)).setCollateralProfileParimutuelCreationSeedAmount(profileId, 0.004 ether);

        vm.expectEmit(true, false, false, true, address(diamond));
        emit CollateralProfileParimutuelMinEntrySet(profileId, 0, 0.0001 ether);
        OwnershipFacet(address(diamond)).setCollateralProfileParimutuelMinEntry(profileId, 0.0001 ether);

        vm.expectEmit(true, false, false, true, address(diamond));
        emit CollateralProfileParlayUnderwritingFeeSet(profileId, 0, 0.0002 ether);
        OwnershipFacet(address(diamond)).setCollateralProfileParlayUnderwritingFee(profileId, 0.0002 ether);

        vm.expectEmit(true, false, false, true, address(diamond));
        emit CollateralProfileEnabledSet(profileId, true, false);
        OwnershipFacet(address(diamond)).setCollateralProfileEnabled(profileId, false);

        profile = IMarketFactoryFacet(address(diamond)).getCollateralProfile(profileId);
        assertEq(profile.payoutUnit, 0.001 ether);
        assertEq(profile.marketCreationFee, 0.003 ether);
        assertFalse(profile.enabled);

        (uint128 parimutuelSeed, uint128 parimutuelMinEntry) =
            IMarketFactoryFacet(address(diamond)).getCollateralProfileParimutuelConfig(profileId);
        assertEq(parimutuelSeed, 0.004 ether);
        assertEq(parimutuelMinEntry, 0.0001 ether);
        assertEq(
            IMarketFactoryFacet(address(diamond)).getCollateralProfileParlayUnderwritingFee(profileId), 0.0002 ether
        );

        vm.stopPrank();
    }

    function test_AdminCollateralProfileRejectsInvalidConfig() public {
        uint8 profileId = 2;
        address eoa = makeAddr("profile-eoa");
        MockUSDG profileCollateral = new MockUSDG();

        vm.startPrank(owner);

        vm.expectRevert(Errors.ZeroAddress.selector);
        OwnershipFacet(address(diamond)).setCollateralProfile(profileId, address(0), address(0), 1, 0, true);

        vm.expectRevert(abi.encodeWithSelector(Errors.ContractHasNoCode.selector, eoa));
        OwnershipFacet(address(diamond)).setCollateralProfile(profileId, eoa, address(0), 1, 0, true);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidAmount.selector, 0));
        OwnershipFacet(address(diamond))
            .setCollateralProfile(profileId, address(profileCollateral), address(0), 0, 0, true);

        vm.expectRevert(abi.encodeWithSelector(Errors.CollateralProfileNotFound.selector, profileId));
        OwnershipFacet(address(diamond)).setCollateralProfileEnabled(profileId, true);

        vm.expectRevert(abi.encodeWithSelector(Errors.CollateralProfileNotFound.selector, profileId));
        OwnershipFacet(address(diamond)).setCollateralProfileMarketCreationFee(profileId, 1);

        vm.expectRevert(abi.encodeWithSelector(Errors.CollateralProfileNotFound.selector, profileId));
        OwnershipFacet(address(diamond)).setCollateralProfileParimutuelCreationSeedAmount(profileId, 1);

        vm.expectRevert(abi.encodeWithSelector(Errors.CollateralProfileNotFound.selector, profileId));
        OwnershipFacet(address(diamond)).setCollateralProfileParimutuelMinEntry(profileId, 1);

        vm.expectRevert(abi.encodeWithSelector(Errors.CollateralProfileNotFound.selector, profileId));
        OwnershipFacet(address(diamond)).setCollateralProfileParlayUnderwritingFee(profileId, 1);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidAmount.selector, 0));
        OwnershipFacet(address(diamond)).setCollateralProfilePayoutUnit(profileId, 0);

        OwnershipFacet(address(diamond))
            .setCollateralProfile(profileId, address(profileCollateral), address(0), 1, 0, true);

        uint256 tooLarge = uint256(type(uint128).max) + 1;
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidAmount.selector, tooLarge));
        OwnershipFacet(address(diamond)).setCollateralProfileParimutuelCreationSeedAmount(profileId, tooLarge);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidAmount.selector, tooLarge));
        OwnershipFacet(address(diamond)).setCollateralProfileParimutuelMinEntry(profileId, tooLarge);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidAmount.selector, tooLarge));
        OwnershipFacet(address(diamond)).setCollateralProfileParlayUnderwritingFee(profileId, tooLarge);

        vm.stopPrank();
    }

    function test_AdminSettersAcceptValidatedContractsAndEmitEvents() public {
        MockConditionalTokens newConditionalTokens = new MockConditionalTokens();
        MockUSDG newCollateralToken = new MockUSDG();
        uint16 previousFeeRate = 0;
        uint16 newFeeRate = 250;
        uint16 newSpotFeeRate = 75;
        uint128 previousCreationFee = 50e6;
        uint128 newCreationFee = 75e6;
        uint128 newSpotBookCreationFee = 250e6;

        vm.startPrank(owner);

        vm.expectEmit(false, false, false, true, address(diamond));
        emit OrderbookEntryFeeBpsSet(previousFeeRate, newFeeRate);
        FeeConfigFacet(address(diamond)).setOrderbookEntryFeeBps(newFeeRate);

        vm.expectEmit(false, false, false, true, address(diamond));
        emit OrderbookEntryFeeBpsSet(newFeeRate, 125);
        FeeConfigFacet(address(diamond)).setOrderbookEntryFeeBps(125);
        assertEq(StateProbeFacet(address(diamond)).orderbookEntryFeeBps(), 125);

        vm.expectEmit(false, false, false, true, address(diamond));
        emit SpotTradeFeeBpsSet(0, newSpotFeeRate);
        FeeConfigFacet(address(diamond)).setSpotTradeFeeBps(newSpotFeeRate);
        assertEq(StateProbeFacet(address(diamond)).spotTradeFeeBps(), newSpotFeeRate);

        vm.expectEmit(false, false, false, true, address(diamond));
        emit OrderbookFeeSplitSet(8_500, 400, 1_000, 100, 0);
        FeeConfigFacet(address(diamond)).setOrderbookFeeSplit(8_500, 400, 1_000, 100, 0);

        vm.expectEmit(false, false, false, true, address(diamond));
        emit SpotFeeSplitSet(8_000, 1_900, 100, 0);
        FeeConfigFacet(address(diamond)).setSpotFeeSplit(8_000, 1_900, 100, 0);

        MarketFactoryTypes.MarketConfigView memory configView = IMarketFactoryFacet(address(diamond)).getMarketConfig();
        assertEq(configView.orderbookFeeConfig.makerFeeBps, 8_500);
        assertEq(configView.orderbookFeeConfig.creatorFeeBps, 400);
        assertEq(configView.orderbookFeeConfig.protocolFeeBps, 1_000);
        assertEq(configView.orderbookFeeConfig.seniorPoolFeeBps, 100);
        assertEq(configView.orderbookFeeConfig.resolverFeeBps, 0);
        assertEq(configView.spotFeeConfig.tradeFeeBps, newSpotFeeRate);
        assertEq(configView.spotFeeConfig.makerFeeBps, 8_000);
        assertEq(configView.spotFeeConfig.protocolFeeBps, 1_900);
        assertEq(configView.spotFeeConfig.seniorPoolFeeBps, 100);
        assertEq(configView.spotFeeConfig.resolverFeeBps, 0);

        vm.expectEmit(false, false, false, true, address(diamond));
        emit MarketCreationFeeSet(previousCreationFee, newCreationFee);
        OwnershipFacet(address(diamond)).setMarketCreationFee(newCreationFee);

        vm.expectEmit(false, false, false, true, address(diamond));
        emit SpotBookCreationFeeSet(0, newSpotBookCreationFee);
        OwnershipFacet(address(diamond)).setSpotBookCreationFee(newSpotBookCreationFee);
        assertEq(StateProbeFacet(address(diamond)).spotBookCreationFee(), newSpotBookCreationFee);

        vm.expectEmit(true, true, false, true, address(diamond));
        emit DefaultConditionalTokensSet(address(conditionalTokens), address(newConditionalTokens));
        OwnershipFacet(address(diamond)).setDefaultConditionalTokens(address(newConditionalTokens));

        vm.expectEmit(true, true, false, true, address(diamond));
        emit CollateralTokenSet(address(collateralToken), address(newCollateralToken));
        OwnershipFacet(address(diamond)).setCollateralToken(address(newCollateralToken));

        vm.expectEmit(false, false, false, true, address(diamond));
        emit PermissionlessCreationSet(true, false);
        OwnershipFacet(address(diamond)).setPermissionlessCreationEnabled(false);

        vm.stopPrank();
    }

    function test_AdminResolutionParametersRejectUnsafeBounds() public {
        vm.startPrank(owner);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidAmount.selector, 0));
        OwnershipFacet(address(diamond)).setDisputeWindow(0);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidAmount.selector, 0));
        OwnershipFacet(address(diamond)).setCreatorSettleGrace(0);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidAmount.selector, 0));
        OwnershipFacet(address(diamond)).setOpenResolutionTimeout(0);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidAmount.selector, 0));
        OwnershipFacet(address(diamond)).setMaxEscalation(0);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidAmount.selector, 4));
        OwnershipFacet(address(diamond)).setMaxEscalation(4);

        vm.stopPrank();
    }
}
