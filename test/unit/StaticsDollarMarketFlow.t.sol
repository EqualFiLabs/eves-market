// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {StaticsDollar} from "@statics/dollar/StaticsDollar.sol";
import {IStaticsDollarCore} from "@statics/dollar/core/interfaces/IStaticsDollarCore.sol";
import {IStaticsDollarCoreTypes} from "@statics/dollar/interfaces/IStaticsDollarCoreTypes.sol";

import {OwnershipFacet} from "../../src/facets/OwnershipFacet.sol";
import {ComboMarketFacet} from "../../src/facets/native/ComboMarketFacet.sol";
import {IComboMarketFacet} from "../../src/interfaces/IComboMarketFacet.sol";
import {ICurveInventoryFacet} from "../../src/interfaces/ICurveInventoryFacet.sol";
import {ICurveLifecycleFacet} from "../../src/interfaces/ICurveLifecycleFacet.sol";
import {ICurveTradeFacet} from "../../src/interfaces/ICurveTradeFacet.sol";
import {ICurveViewFacet} from "../../src/interfaces/ICurveViewFacet.sol";
import {IMarketFactoryFacet} from "../../src/interfaces/IMarketFactoryFacet.sol";
import {IMarketSettlementFacet} from "../../src/interfaces/IMarketSettlementFacet.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {LibMarketCreation} from "../../src/libraries/LibMarketCreation.sol";
import {EvesPositionManager} from "../../src/tokens/EvesPositionManager.sol";
import {MarketFactoryTypes} from "../../src/types/MarketFactoryTypes.sol";

import {SettlementFeeFixture, StateProbeFacet} from "../helpers/DiamondFixtures.sol";
import {StaticsDollarCoreFixture} from "../helpers/StaticsDollarCoreFixture.sol";
import {MockUSDG} from "../helpers/MockUSDG.sol";

contract StaticsDollarMarketFlowTest is SettlementFeeFixture, StaticsDollarCoreFixture {
    uint8 internal constant STATICS_DOLLAR_PROFILE_ID = 2;
    uint128 internal constant STATICS_DOLLAR_PAYOUT_UNIT = 1 ether;
    uint72 internal constant HALF_PRICE = 500_000_000;

    StaticsDollar internal staticsDollar;
    IStaticsDollarCore internal core;
    MockUSDG internal usdc;
    uint256 internal usdcProfileId;
    EvesPositionManager internal comboPositions;

    function setUp() public override {
        super.setUp();

        usdc = new MockUSDG();
        ActiveStaticsDollar memory active = _deployActiveStaticsDollar(owner, usdc);
        core = IStaticsDollarCore(active.deployment.core);
        staticsDollar = StaticsDollar(active.deployment.staticsDollar);
        usdcProfileId = active.profileId;
        comboPositions = new EvesPositionManager(address(diamond), "");

        _addFacet(address(ownershipFacet), _evesPositionManagerSelector());
        _addFacet(address(new ComboMarketFacet()), _comboMarketSelectors());
        _registerStaticsDollarProfile();
    }

    function test_StaticsDollarProfileRegistersWithExpectedCollateralMetadata() public view {
        MarketFactoryTypes.CollateralProfileView memory profile =
            IMarketFactoryFacet(address(diamond)).getCollateralProfile(STATICS_DOLLAR_PROFILE_ID);

        assertEq(profile.collateralToken, address(staticsDollar));
        assertEq(profile.wrapperToken, address(0));
        assertEq(profile.payoutUnit, STATICS_DOLLAR_PAYOUT_UNIT);
        assertEq(profile.marketCreationFee, 0);
        assertTrue(profile.enabled);
    }

    function test_StaticsDollarProfileMarketTradesResolvesAndRedeems() public {
        (bytes32 marketId, uint64 expiryTime) = _createStaticsDollarMarket("Will staticsDollar launch flow settle?");
        _fundStaticsDollar(maker, 1_000e18);
        _fundStaticsDollar(taker, 1_000e18);

        uint128 makerInventory = 500e18;
        uint128 takerCollateral = 250e18;

        vm.startPrank(maker);
        staticsDollar.approve(address(diamond), makerInventory);
        uint128 sharesMinted = ICurveInventoryFacet(address(diamond)).splitInventory(marketId, makerInventory);
        conditionalTokens.setApprovalForAll(address(diamond), true);
        uint256 curveId = ICurveLifecycleFacet(address(diamond))
            .postCurve(
                marketId, true, makerInventory, HALF_PRICE, HALF_PRICE, 180, 0, LibEveMarket.PositionTokenType.CTF
            );
        vm.stopPrank();

        assertEq(sharesMinted, makerInventory);

        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        (uint128 previewShares,,,) = ICurveViewFacet(address(diamond)).previewCurveQuote(curveId, takerCollateral);

        vm.startPrank(taker);
        staticsDollar.approve(address(diamond), takerCollateral);
        uint128 sharesOut = ICurveTradeFacet(address(diamond))
            .fillCurve(curveId, takerCollateral, previewShares, generation, commitment);
        vm.stopPrank();

        assertEq(sharesOut, previewShares);

        _finalizeCreatorResolution(marketId, expiryTime, uint8(LibEveMarket.MarketOutcome.Yes));

        (address redemptionCollateral, bytes32 conditionId, uint256[] memory indexSets) =
            IMarketSettlementFacet(address(diamond)).getCTFRedemptionParams(marketId);
        uint256 takerBalanceBefore = staticsDollar.balanceOf(taker);

        vm.prank(taker);
        conditionalTokens.redeemPositions(IERC20(redemptionCollateral), bytes32(0), conditionId, indexSets);

        assertEq(redemptionCollateral, address(staticsDollar));
        assertEq(staticsDollar.balanceOf(taker), takerBalanceBefore + sharesOut);
    }

    function test_RevertWhen_StaticsDollarAndDefaultCollateralAreCombined() public {
        (bytes32 defaultMarketId,,) =
            _createTradingMarket("Will default collateral combo leg win?", "statics-dollar", 7 days);
        (bytes32 staticsDollarMarketId,) = _createStaticsDollarMarket("Will staticsDollar combo leg win?");

        vm.prank(owner);
        OwnershipFacet(address(diamond)).setEvesPositionManager(address(comboPositions));

        vm.prank(creator);
        vm.expectPartialRevert(Errors.ComboCollateralMismatch.selector);
        IComboMarketFacet(address(diamond)).createComboMarket(_pair(defaultMarketId, staticsDollarMarketId), _yesLegs());
    }

    function _registerStaticsDollarProfile() internal {
        vm.startPrank(owner);
        OwnershipFacet(address(diamond))
            .setCollateralProfile(
                STATICS_DOLLAR_PROFILE_ID, address(staticsDollar), address(0), STATICS_DOLLAR_PAYOUT_UNIT, 0, true
            );
        vm.stopPrank();
    }

    function _createStaticsDollarMarket(string memory question) internal returns (bytes32 marketId, uint64 expiryTime) {
        uint64 tradingStartTime = uint64(block.timestamp);
        expiryTime = tradingStartTime + 7 days;

        vm.prank(creator);
        marketId = IMarketFactoryFacet(address(diamond))
            .createMarketWithCollateralProfile(
                STATICS_DOLLAR_PROFILE_ID,
                question,
                "statics-dollar",
                DEFAULT_RESOLUTION_SOURCE,
                tradingStartTime,
                expiryTime,
                0,
                true
            );

        bytes32 expectedMarketId = LibMarketCreation.profileMarketIdFor(
            question,
            "statics-dollar",
            tradingStartTime,
            expiryTime,
            address(staticsDollar),
            STATICS_DOLLAR_PROFILE_ID,
            STATICS_DOLLAR_PAYOUT_UNIT,
            LibEveMarket.MarketType.CLOB,
            LibEveMarket.PositionTokenType.CTF
        );
        assertEq(marketId, expectedMarketId);

        (address storedCollateral,,,,,) = StateProbeFacet(address(diamond)).getStoredMarketCore(marketId);
        assertEq(storedCollateral, address(staticsDollar));
    }

    function _fundStaticsDollar(address account, uint256 amount) internal {
        IStaticsDollarCoreTypes.PeggedMintPreview memory preview = core.previewPeggedMint(usdcProfileId, amount);
        usdc.mint(account, preview.totalCollateralIn);
        vm.startPrank(account);
        usdc.approve(address(core), preview.totalCollateralIn);
        core.mintPegged(usdcProfileId, amount, preview.totalCollateralIn, account);
        vm.stopPrank();
    }

    function _pair(bytes32 first, bytes32 second) internal pure returns (bytes32[] memory marketIds) {
        marketIds = new bytes32[](2);
        marketIds[0] = first;
        marketIds[1] = second;
    }

    function _yesLegs() internal pure returns (bool[] memory yesLegs) {
        yesLegs = new bool[](2);
        yesLegs[0] = true;
        yesLegs[1] = true;
    }

    function _evesPositionManagerSelector() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = OwnershipFacet.setEvesPositionManager.selector;
    }

    function _comboMarketSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = IComboMarketFacet.createComboMarket.selector;
        selectors[1] = IComboMarketFacet.computeComboBookId.selector;
        selectors[2] = IComboMarketFacet.getComboMarket.selector;
        selectors[3] = IComboMarketFacet.getComboBook.selector;
    }
}
