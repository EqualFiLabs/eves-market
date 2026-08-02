// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ICurveInventoryFacet} from "../../src/interfaces/ICurveInventoryFacet.sol";
import {ICurveViewFacet} from "../../src/interfaces/ICurveViewFacet.sol";
import {IMarketFactoryFacet} from "../../src/interfaces/IMarketFactoryFacet.sol";
import {ISeniorCapitalFacet} from "../../src/interfaces/ISeniorCapitalFacet.sol";
import {ITradeRouter} from "../../src/interfaces/ITradeRouter.sol";
import {ICollateralTradeExecution} from "../../src/interfaces/ICollateralTradeExecution.sol";
import {CurveCLOBTypes} from "../../src/types/CurveCLOBTypes.sol";
import {MarketFactoryTypes} from "../../src/types/MarketFactoryTypes.sol";
import {CollateralTradeRouterFacet} from "../../src/facets/CollateralTradeRouterFacet.sol";
import {CollateralTradeRouterExactFacet} from "../../src/facets/CollateralTradeRouterExactFacet.sol";
import {CollateralTradeRouterSellFacet} from "../../src/facets/CollateralTradeRouterSellFacet.sol";
import {CollateralTradeRouterPreviewFacet} from "../../src/facets/CollateralTradeRouterPreviewFacet.sol";
import {StaticsDollarTradeRouterFacet} from "../../src/facets/StaticsDollarTradeRouterFacet.sol";
import {CollateralTradeExecutionFacet} from "../../src/facets/CollateralTradeExecutionFacet.sol";
import {FeeConfigFacet} from "../../src/facets/FeeConfigFacet.sol";
import {OwnershipFacet} from "../../src/facets/OwnershipFacet.sol";
import {SeniorCapitalFacet} from "../../src/facets/SeniorCapitalFacet.sol";
import {SeniorCapitalViewFacet} from "../../src/facets/SeniorCapitalViewFacet.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";

import {StaticsDollar} from "@statics/dollar/StaticsDollar.sol";
import {CoreGovernanceFacet} from "@statics/dollar/core/facets/CoreGovernanceFacet.sol";
import {IStaticsDollarCore} from "@statics/dollar/core/interfaces/IStaticsDollarCore.sol";
import {IStaticsDollarCoreTypes} from "@statics/dollar/interfaces/IStaticsDollarCoreTypes.sol";
import {IERC20Permit} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {ERC20Permit} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";

import {CollateralRouterFixture} from "../helpers/DiamondFixtures.sol";
import {StaticsDollarCoreFixture} from "../helpers/StaticsDollarCoreFixture.sol";
import {MockCollateral} from "../helpers/MockCollateral.sol";
import {MockUSDC} from "../helpers/MockUSDC.sol";
import {Errors} from "../../src/libraries/Errors.sol";

/// @dev Narrow fixture-only setter for installing the collateral denomination before
/// exercising the production Senior fee route. It does not mutate live liabilities.
contract RouterSeniorConfigFacet {
    function setMarginAsset(address asset) external {
        LibEveMarket.store().marginAsset = asset;
    }
}

contract TradeRouterTest is CollateralRouterFixture, StaticsDollarCoreFixture {
    bytes32 internal constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    ITradeRouter internal tradeRouter;
    address internal alternateReceiver;

    function setUp() public override {
        super.setUp();
        _addFacet(address(new CollateralTradeRouterFacet()), _buySelectors());
        _addFacet(address(new CollateralTradeRouterExactFacet()), _exactBuySelectors());
        _addFacet(address(new CollateralTradeRouterSellFacet()), _sellSelectors());
        _addFacet(address(new CollateralTradeRouterPreviewFacet()), _previewSelectors());
        _addFacet(address(new StaticsDollarTradeRouterFacet()), _staticsDollarSelectors());
        _addFacet(address(new CollateralTradeExecutionFacet()), _collateralExecutionSelectors());
        _addFacet(address(new RouterSeniorConfigFacet()), _seniorConfigSelectors());
        _addFacet(address(new SeniorCapitalFacet()), _seniorMutationSelectors());
        _addFacet(address(new SeniorCapitalViewFacet()), _seniorViewSelectors());
        tradeRouter = ITradeRouter(address(diamond));
        alternateReceiver = makeAddr("trade-router-receiver");
    }

    function test_BuyWithCollateralExecutesAndRefundsUnusedAmount() public {
        (bytes32 marketId,) = _createTradingMarket("direct collateral", 7 days);
        _splitFromMaker(marketId, 10e18);
        _approvePositions(maker);
        uint256 curveId = _postCurveFromMaker(marketId, true, 6e18, DEFAULT_FLAT_PRICE, DEFAULT_FLAT_PRICE, 180);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        uint256 balanceBefore = routerCollateral.balanceOf(taker);
        vm.prank(taker);
        CurveCLOBTypes.FillBestResult memory result =
            tradeRouter.buyWithCollateral(_singleCurveBuyParams(marketId, curveId, generation, commitment, 5e18));

        (,, uint256 yesPositionId,) = IMarketFactoryFacet(address(diamond)).getMarketPositions(marketId);
        assertGt(result.sharesOut, 0);
        assertEq(routerCollateral.balanceOf(taker), balanceBefore - result.collateralUsed);
        assertEq(conditionalTokens.balanceOf(alternateReceiver, yesPositionId), result.sharesOut);
    }

    function test_BuyWithCollateralPermitConsumesExactAllowance() public {
        (address permitBuyer, uint256 permitBuyerKey) = makeAddrAndKey("collateralPermitBuyer");
        (bytes32 marketId,) = _createTradingMarket("direct permit collateral", 7 days);
        _splitFromMaker(marketId, 10e18);
        _approvePositions(maker);
        uint256 curveId = _postCurveFromMaker(marketId, true, 6e18, DEFAULT_FLAT_PRICE, DEFAULT_FLAT_PRICE, 180);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        CurveCLOBTypes.FillBestParams memory params =
            _singleCurveBuyParams(marketId, curveId, generation, commitment, 5e18);
        params.payer = permitBuyer;
        routerCollateral.mint(permitBuyer, params.maxCollateralIn);
        ITradeRouter.PermitSignature memory signature = _signPermit(
            IERC20Permit(address(routerCollateral)),
            permitBuyer,
            permitBuyerKey,
            params.maxCollateralIn,
            block.timestamp + 20 minutes
        );

        vm.prank(permitBuyer);
        CurveCLOBTypes.FillBestResult memory result = tradeRouter.buyWithCollateralWithPermit(params, signature);

        assertGt(result.sharesOut, 0);
        assertEq(routerCollateral.nonces(permitBuyer), 1);
        assertEq(routerCollateral.allowance(permitBuyer, address(diamond)), 0);
    }

    function test_BuyWithCollateralPermitRejectsAlreadyConsumedSignature() public {
        (address permitBuyer, uint256 permitBuyerKey) = makeAddrAndKey("consumedCollateralPermitBuyer");
        (bytes32 marketId,) = _createTradingMarket("consumed direct permit collateral", 7 days);
        _splitFromMaker(marketId, 10e18);
        _approvePositions(maker);
        uint256 curveId = _postCurveFromMaker(marketId, true, 6e18, DEFAULT_FLAT_PRICE, DEFAULT_FLAT_PRICE, 180);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        CurveCLOBTypes.FillBestParams memory params =
            _singleCurveBuyParams(marketId, curveId, generation, commitment, 5e18);
        params.payer = permitBuyer;
        routerCollateral.mint(permitBuyer, params.maxCollateralIn);
        ITradeRouter.PermitSignature memory signature = _signPermit(
            IERC20Permit(address(routerCollateral)),
            permitBuyer,
            permitBuyerKey,
            params.maxCollateralIn,
            block.timestamp + 20 minutes
        );

        vm.prank(alternateReceiver);
        routerCollateral.permit(
            permitBuyer,
            address(diamond),
            params.maxCollateralIn,
            signature.deadline,
            signature.v,
            signature.r,
            signature.s
        );
        vm.prank(permitBuyer);
        vm.expectPartialRevert(ERC20Permit.ERC2612InvalidSigner.selector);
        tradeRouter.buyWithCollateralWithPermit(params, signature);

        assertEq(routerCollateral.allowance(permitBuyer, address(diamond)), params.maxCollateralIn);
        assertEq(routerCollateral.balanceOf(permitBuyer), params.maxCollateralIn);
    }

    function test_BuyWithCollateralPermitRollsBackOnStaleRoute() public {
        (address permitBuyer, uint256 permitBuyerKey) = makeAddrAndKey("rollbackCollateralPermitBuyer");
        (bytes32 marketId,) = _createTradingMarket("rollback permit collateral", 7 days);
        _splitFromMaker(marketId, 10e18);
        _approvePositions(maker);
        uint256 curveId = _postCurveFromMaker(marketId, true, 6e18, DEFAULT_FLAT_PRICE, DEFAULT_FLAT_PRICE, 180);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        CurveCLOBTypes.FillBestParams memory params =
            _singleCurveBuyParams(marketId, curveId, generation, commitment, 5e18);
        params.payer = permitBuyer;
        params.expectedCommitments[0] = bytes32(0);
        routerCollateral.mint(permitBuyer, params.maxCollateralIn);
        ITradeRouter.PermitSignature memory signature = _signPermit(
            IERC20Permit(address(routerCollateral)),
            permitBuyer,
            permitBuyerKey,
            params.maxCollateralIn,
            block.timestamp + 20 minutes
        );

        vm.prank(permitBuyer);
        vm.expectRevert();
        tradeRouter.buyWithCollateralWithPermit(params, signature);

        assertEq(routerCollateral.nonces(permitBuyer), 0);
        assertEq(routerCollateral.allowance(permitBuyer, address(diamond)), 0);
        assertEq(routerCollateral.balanceOf(permitBuyer), params.maxCollateralIn);
    }

    function test_BuyWithCollateralExactExecutesCompleteRequestedAmount() public {
        (bytes32 marketId,) = _createTradingMarket("exact collateral", 7 days);
        _splitFromMaker(marketId, 10e18);
        _approvePositions(maker);
        uint256 curveId = _postCurveFromMaker(marketId, true, 10e18, DEFAULT_FLAT_PRICE, DEFAULT_FLAT_PRICE, 180);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        uint256 balanceBefore = routerCollateral.balanceOf(taker);
        vm.prank(taker);
        CurveCLOBTypes.FillBestResult memory result =
            tradeRouter.buyWithCollateralExact(_singleCurveBuyParams(marketId, curveId, generation, commitment, 5e18));

        assertEq(result.collateralUsed, 5e18);
        assertEq(result.unfilledCollateral, 0);
        assertEq(routerCollateral.balanceOf(taker), balanceBefore - 5e18);
    }

    function test_CollateralBuyVariantsRestoreBalancesWithRetainedSeniorFees() public {
        _activateSeniorCollateral(routerCollateral, owner, 10e18);
        vm.startPrank(owner);
        FeeConfigFacet(address(diamond)).setOrderbookEntryFeeBps(100);
        FeeConfigFacet(address(diamond)).setOrderbookFeeSplit(0, 0, 0, 10_000, 0);
        vm.stopPrank();

        (bytes32 partialMarket,) = _createTradingMarket("retained fee partial router", 7 days);
        _splitFromMaker(partialMarket, 10e18);
        _approvePositions(maker);
        uint256 partialCurve =
            _postCurveFromMaker(partialMarket, true, 10e18, DEFAULT_FLAT_PRICE, DEFAULT_FLAT_PRICE, 180);
        (uint32 partialGeneration, bytes32 partialCommitment) =
            ICurveViewFacet(address(diamond)).getCurveCommitment(partialCurve);
        vm.prank(taker);
        CurveCLOBTypes.FillBestResult memory partialResult = tradeRouter.buyWithCollateral(
            _singleCurveBuyParams(partialMarket, partialCurve, partialGeneration, partialCommitment, 5e18)
        );

        (bytes32 exactMarket,) = _createTradingMarket("retained fee exact router", 7 days);
        _splitFromMaker(exactMarket, 10e18);
        uint256 exactCurve = _postCurveFromMaker(exactMarket, true, 10e18, DEFAULT_FLAT_PRICE, DEFAULT_FLAT_PRICE, 180);
        (uint32 exactGeneration, bytes32 exactCommitment) =
            ICurveViewFacet(address(diamond)).getCurveCommitment(exactCurve);
        vm.prank(taker);
        CurveCLOBTypes.FillBestResult memory exactResult = tradeRouter.buyWithCollateralExact(
            _singleCurveBuyParams(exactMarket, exactCurve, exactGeneration, exactCommitment, 4.545e18)
        );

        assertGt(partialResult.feePaid, 0);
        assertGt(exactResult.feePaid, 0);
        assertEq(
            ISeniorCapitalFacet(address(diamond)).seniorCapitalState().feeReserve,
            partialResult.feePaid + exactResult.feePaid
        );
    }

    function test_RevertWhen_BuyWithCollateralExactCannotFillCompleteAmount() public {
        (bytes32 marketId,) = _createTradingMarket("insufficient exact collateral", 7 days);
        _splitFromMaker(marketId, 10e18);
        _approvePositions(maker);
        uint256 curveId = _postCurveFromMaker(marketId, true, 2e18, DEFAULT_FLAT_PRICE, DEFAULT_FLAT_PRICE, 180);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        uint256 takerBalanceBefore = routerCollateral.balanceOf(taker);
        uint256 makerBalanceBefore = routerCollateral.balanceOf(maker);
        vm.prank(taker);
        vm.expectRevert(abi.encodeWithSelector(ITradeRouter.ExactFillRequired.selector, uint128(4e18)));
        tradeRouter.buyWithCollateralExact(_singleCurveBuyParams(marketId, curveId, generation, commitment, 5e18));

        assertEq(routerCollateral.balanceOf(taker), takerBalanceBefore);
        assertEq(routerCollateral.balanceOf(maker), makerBalanceBefore);
    }

    function test_MintAndBuyWithUSDCMintsStaticsDollarThroughSharedGateway() public {
        MockUSDC launchUsdc = new MockUSDC();
        ActiveStaticsDollar memory active = _deployActiveStaticsDollar(owner, launchUsdc);
        IStaticsDollarCore launchCore = IStaticsDollarCore(active.deployment.core);
        StaticsDollar launchStaticsDollar = StaticsDollar(active.deployment.staticsDollar);

        vm.startPrank(owner);
        OwnershipFacet(address(diamond)).setCollateralToken(address(launchStaticsDollar));
        OwnershipFacet(address(diamond))
            .setStaticsDollarRail(active.deployment.core, active.profileId, address(launchUsdc));
        vm.stopPrank();

        launchUsdc.mint(maker, 20e6);
        IStaticsDollarCoreTypes.PeggedMintPreview memory makerPreview =
            launchCore.previewPeggedMint(active.profileId, 10e18);
        vm.startPrank(maker);
        launchUsdc.approve(active.deployment.core, makerPreview.totalCollateralIn);
        launchCore.mintPegged(active.profileId, 10e18, makerPreview.totalCollateralIn, maker);
        launchStaticsDollar.approve(address(diamond), type(uint256).max);
        vm.stopPrank();

        (bytes32 marketId,) = _createTradingMarket("staticsDollar launch rail", 7 days);
        vm.prank(maker);
        ICurveInventoryFacet(address(diamond)).splitInventory(marketId, 10e18);
        _approvePositions(maker);
        uint256 curveId = _postCurveFromMaker(marketId, true, 6e18, DEFAULT_FLAT_PRICE, DEFAULT_FLAT_PRICE, 180);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        launchUsdc.mint(taker, 6e6);
        vm.prank(taker);
        launchUsdc.approve(address(diamond), type(uint256).max);
        ITradeRouter.BuyWithUSDCParams memory request = ITradeRouter.BuyWithUSDCParams({
            order: _singleCurveBuyParams(marketId, curveId, generation, commitment, 5e18), maxUsdcIn: 5.002499e6
        });

        vm.prank(taker);
        vm.expectRevert(abi.encodeWithSelector(ITradeRouter.MaxUsdcExceeded.selector, 5.0025e6, 5.002499e6));
        tradeRouter.mintAndBuyWithUSDC(request);

        request.maxUsdcIn = 5.01e6;
        uint256 usdcBefore = launchUsdc.balanceOf(taker);
        vm.prank(taker);
        CurveCLOBTypes.FillBestResult memory result = tradeRouter.mintAndBuyWithUSDC(request);

        assertGt(result.sharesOut, 0);
        assertEq(launchUsdc.balanceOf(taker), usdcBefore - 5.0025e6);
        assertEq(launchStaticsDollar.balanceOf(taker), result.unfilledCollateral);
        assertEq(launchUsdc.allowance(address(diamond), active.deployment.diamond), 0);
    }

    function test_StaticsDollarBuyRouterRestoresBalanceWithRetainedSeniorFee() public {
        MockUSDC launchUsdc = new MockUSDC();
        ActiveStaticsDollar memory active = _deployActiveStaticsDollar(owner, launchUsdc);
        IStaticsDollarCore launchCore = IStaticsDollarCore(active.deployment.core);
        StaticsDollar launchStaticsDollar = StaticsDollar(active.deployment.staticsDollar);

        vm.startPrank(owner);
        OwnershipFacet(address(diamond)).setCollateralToken(address(launchStaticsDollar));
        OwnershipFacet(address(diamond))
            .setStaticsDollarRail(active.deployment.core, active.profileId, address(launchUsdc));
        FeeConfigFacet(address(diamond)).setOrderbookEntryFeeBps(100);
        FeeConfigFacet(address(diamond)).setOrderbookFeeSplit(0, 0, 0, 10_000, 0);
        vm.stopPrank();

        _mintStaticsDollar(launchCore, launchStaticsDollar, launchUsdc, active.profileId, owner, 10e18);
        _activateSeniorCollateral(launchStaticsDollar, owner, 1e18);
        _mintStaticsDollar(launchCore, launchStaticsDollar, launchUsdc, active.profileId, maker, 10e18);
        vm.prank(maker);
        launchStaticsDollar.approve(address(diamond), type(uint256).max);

        (bytes32 marketId,) = _createTradingMarket("staticsDollar retained Senior fee", 7 days);
        vm.prank(maker);
        ICurveInventoryFacet(address(diamond)).splitInventory(marketId, 10e18);
        _approvePositions(maker);
        uint256 curveId = _postCurveFromMaker(marketId, true, 6e18, DEFAULT_FLAT_PRICE, DEFAULT_FLAT_PRICE, 180);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        launchUsdc.mint(taker, 6e6);
        vm.prank(taker);
        launchUsdc.approve(address(diamond), type(uint256).max);
        ITradeRouter.BuyWithUSDCParams memory request = ITradeRouter.BuyWithUSDCParams({
            order: _singleCurveBuyParams(marketId, curveId, generation, commitment, 5e18), maxUsdcIn: 5.1e6
        });
        vm.prank(taker);
        CurveCLOBTypes.FillBestResult memory result = tradeRouter.mintAndBuyWithUSDC(request);

        assertGt(result.feePaid, 0);
        assertEq(ISeniorCapitalFacet(address(diamond)).seniorCapitalState().feeReserve, result.feePaid);
    }

    function test_MintAndBuyWithUSDCPermitConsumesExactAllowance() public {
        MockUSDC launchUsdc = new MockUSDC();
        ActiveStaticsDollar memory active = _deployActiveStaticsDollar(owner, launchUsdc);
        (address permitTaker, uint256 permitTakerKey) = makeAddrAndKey("permitTaker");
        (bytes32 marketId, uint256 curveId, uint32 generation, bytes32 commitment) =
            _prepareStaticsDollarMarket(active, launchUsdc, "permit staticsDollar launch rail");
        CurveCLOBTypes.FillBestParams memory order =
            _singleCurveBuyParams(marketId, curveId, generation, commitment, 5e18);
        order.payer = permitTaker;
        IStaticsDollarCoreTypes.PeggedMintPreview memory preview =
            IStaticsDollarCore(active.deployment.core).previewPeggedMint(active.profileId, order.maxCollateralIn);
        launchUsdc.mint(permitTaker, preview.totalCollateralIn);
        ITradeRouter.PermitSignature memory permitSignature = _signPermit(
            launchUsdc, permitTaker, permitTakerKey, preview.totalCollateralIn, block.timestamp + 20 minutes
        );

        vm.prank(permitTaker);
        CurveCLOBTypes.FillBestResult memory result = tradeRouter.mintAndBuyWithUSDCPermit(
            ITradeRouter.BuyWithUSDCParams({order: order, maxUsdcIn: preview.totalCollateralIn}), permitSignature
        );

        assertGt(result.sharesOut, 0);
        assertEq(launchUsdc.nonces(permitTaker), 1);
        assertEq(launchUsdc.allowance(permitTaker, address(diamond)), 0);
    }

    function test_MintAndBuyWithUSDCPermitRejectsAlreadyConsumedSignature() public {
        MockUSDC launchUsdc = new MockUSDC();
        ActiveStaticsDollar memory active = _deployActiveStaticsDollar(owner, launchUsdc);
        (address permitTaker, uint256 permitTakerKey) = makeAddrAndKey("frontrunPermitTaker");
        (bytes32 marketId, uint256 curveId, uint32 generation, bytes32 commitment) =
            _prepareStaticsDollarMarket(active, launchUsdc, "frontrun permit launch rail");
        CurveCLOBTypes.FillBestParams memory order =
            _singleCurveBuyParams(marketId, curveId, generation, commitment, 5e18);
        order.payer = permitTaker;
        IStaticsDollarCoreTypes.PeggedMintPreview memory preview =
            IStaticsDollarCore(active.deployment.core).previewPeggedMint(active.profileId, order.maxCollateralIn);
        launchUsdc.mint(permitTaker, preview.totalCollateralIn);
        ITradeRouter.PermitSignature memory permitSignature = _signPermit(
            launchUsdc, permitTaker, permitTakerKey, preview.totalCollateralIn, block.timestamp + 20 minutes
        );

        vm.prank(alternateReceiver);
        launchUsdc.permit(
            permitTaker,
            address(diamond),
            preview.totalCollateralIn,
            permitSignature.deadline,
            permitSignature.v,
            permitSignature.r,
            permitSignature.s
        );
        vm.prank(permitTaker);
        vm.expectPartialRevert(ERC20Permit.ERC2612InvalidSigner.selector);
        tradeRouter.mintAndBuyWithUSDCPermit(
            ITradeRouter.BuyWithUSDCParams({order: order, maxUsdcIn: preview.totalCollateralIn}), permitSignature
        );

        assertEq(launchUsdc.nonces(permitTaker), 1);
        assertEq(launchUsdc.allowance(permitTaker, address(diamond)), preview.totalCollateralIn);
        assertEq(launchUsdc.balanceOf(permitTaker), preview.totalCollateralIn);
    }

    function test_MintAndBuyWithUSDCPermitRollsBackOnStaleRoute() public {
        MockUSDC launchUsdc = new MockUSDC();
        ActiveStaticsDollar memory active = _deployActiveStaticsDollar(owner, launchUsdc);
        (address permitTaker, uint256 permitTakerKey) = makeAddrAndKey("rollbackPermitTaker");
        (bytes32 marketId, uint256 curveId, uint32 generation, bytes32 commitment) =
            _prepareStaticsDollarMarket(active, launchUsdc, "rollback permit launch rail");
        CurveCLOBTypes.FillBestParams memory order =
            _singleCurveBuyParams(marketId, curveId, generation, commitment, 5e18);
        order.payer = permitTaker;
        IStaticsDollarCoreTypes.PeggedMintPreview memory preview =
            IStaticsDollarCore(active.deployment.core).previewPeggedMint(active.profileId, order.maxCollateralIn);
        launchUsdc.mint(permitTaker, preview.totalCollateralIn);
        ITradeRouter.PermitSignature memory permitSignature = _signPermit(
            launchUsdc, permitTaker, permitTakerKey, preview.totalCollateralIn, block.timestamp + 20 minutes
        );
        order.expectedCommitments[0] = bytes32(0);

        vm.prank(permitTaker);
        vm.expectRevert();
        tradeRouter.mintAndBuyWithUSDCPermit(
            ITradeRouter.BuyWithUSDCParams({order: order, maxUsdcIn: preview.totalCollateralIn}), permitSignature
        );

        assertEq(launchUsdc.nonces(permitTaker), 0);
        assertEq(launchUsdc.allowance(permitTaker, address(diamond)), 0);
        assertEq(launchUsdc.balanceOf(permitTaker), preview.totalCollateralIn);
    }

    function test_StaticsDollarRailDoesNotCacheMutableProfileMode() public {
        MockUSDC launchUsdc = new MockUSDC();
        ActiveStaticsDollar memory active = _deployActiveStaticsDollar(owner, launchUsdc);
        vm.prank(owner);
        CoreGovernanceFacet(active.deployment.core).enterReduceOnly(active.profileId);

        vm.startPrank(owner);
        OwnershipFacet(address(diamond)).setCollateralToken(active.deployment.staticsDollar);
        OwnershipFacet(address(diamond))
            .setStaticsDollarRail(active.deployment.core, active.profileId, address(launchUsdc));
        vm.stopPrank();

        MarketFactoryTypes.MarketConfigView memory config = IMarketFactoryFacet(address(diamond)).getMarketConfig();
        assertEq(config.staticsDollarCore, active.deployment.core);
        assertEq(config.staticsDiamond, active.deployment.diamond);
        assertEq(config.peggedProfileId, active.profileId);
    }

    function test_RevertWhen_CollateralExecutionIsCalledExternally() public {
        CurveCLOBTypes.FillBestParams memory params;
        vm.prank(taker);
        vm.expectRevert(
            abi.encodeWithSelector(ICollateralTradeExecution.CollateralTradeExecutionUnauthorized.selector, taker)
        );
        ICollateralTradeExecution(address(diamond)).executeCollateralBuy(params, taker);
    }

    function test_RevertWhen_RouterTransferExecutionIsCalledExternally() public {
        vm.prank(taker);
        vm.expectRevert(abi.encodeWithSelector(ITradeRouter.RouterExecutionUnauthorized.selector, taker));
        tradeRouter.executeExactRouterTransfer(address(routerCollateral), taker, 1);
    }

    function test_RevertWhen_StaticsDollarRailUsesDifferentUsdc() public {
        MockUSDC launchUsdc = new MockUSDC();
        MockUSDC wrongUsdc = new MockUSDC();
        ActiveStaticsDollar memory active = _deployActiveStaticsDollar(owner, launchUsdc);

        vm.startPrank(owner);
        OwnershipFacet(address(diamond)).setCollateralToken(active.deployment.staticsDollar);
        vm.expectRevert(Errors.InvalidStaticsDollarRail.selector);
        OwnershipFacet(address(diamond))
            .setStaticsDollarRail(active.deployment.core, active.profileId, address(wrongUsdc));
        vm.stopPrank();
    }

    function _singleCurveBuyParams(
        bytes32 marketId,
        uint256 curveId,
        uint32 generation,
        bytes32 commitment,
        uint128 maxCollateralIn
    ) internal view returns (CurveCLOBTypes.FillBestParams memory params) {
        uint256[] memory curveIds = new uint256[](1);
        curveIds[0] = curveId;
        uint32[] memory generations = new uint32[](1);
        generations[0] = generation;
        bytes32[] memory commitments = new bytes32[](1);
        commitments[0] = commitment;
        params = CurveCLOBTypes.FillBestParams({
            marketId: marketId,
            isYesSide: true,
            maxCollateralIn: maxCollateralIn,
            minSharesOut: 0,
            maxAveragePrice: type(uint128).max,
            curveIds: curveIds,
            expectedGenerations: generations,
            expectedCommitments: commitments,
            payer: taker,
            receiver: alternateReceiver
        });
    }

    function _activateSeniorCollateral(StaticsDollar token, address provider, uint256 assets) internal {
        RouterSeniorConfigFacet(address(diamond)).setMarginAsset(address(token));
        vm.startPrank(provider);
        token.approve(address(diamond), assets);
        ISeniorCapitalFacet(address(diamond)).depositSeniorCapital(assets);
        vm.stopPrank();
        vm.warp(block.timestamp + 24 hours);
        vm.prank(provider);
        ISeniorCapitalFacet(address(diamond)).activateSeniorCapital();
    }

    function _activateSeniorCollateral(MockCollateral token, address provider, uint256 assets) internal {
        token.mint(provider, assets);
        RouterSeniorConfigFacet(address(diamond)).setMarginAsset(address(token));
        vm.startPrank(provider);
        token.approve(address(diamond), assets);
        ISeniorCapitalFacet(address(diamond)).depositSeniorCapital(assets);
        vm.stopPrank();
        vm.warp(block.timestamp + 24 hours);
        vm.prank(provider);
        ISeniorCapitalFacet(address(diamond)).activateSeniorCapital();
    }

    function _mintStaticsDollar(
        IStaticsDollarCore core,
        StaticsDollar token,
        MockUSDC usdc,
        uint256 profileId,
        address receiver,
        uint256 assets
    ) internal {
        IStaticsDollarCoreTypes.PeggedMintPreview memory preview = core.previewPeggedMint(profileId, assets);
        usdc.mint(receiver, preview.totalCollateralIn);
        vm.startPrank(receiver);
        usdc.approve(address(core), preview.totalCollateralIn);
        core.mintPegged(profileId, assets, preview.totalCollateralIn, receiver);
        vm.stopPrank();
        assertEq(token.balanceOf(receiver) >= assets, true);
    }

    function _prepareStaticsDollarMarket(ActiveStaticsDollar memory active, MockUSDC launchUsdc, string memory name)
        internal
        returns (bytes32 marketId, uint256 curveId, uint32 generation, bytes32 commitment)
    {
        StaticsDollar launchStaticsDollar = StaticsDollar(active.deployment.staticsDollar);
        vm.startPrank(owner);
        OwnershipFacet(address(diamond)).setCollateralToken(address(launchStaticsDollar));
        OwnershipFacet(address(diamond))
            .setStaticsDollarRail(active.deployment.core, active.profileId, address(launchUsdc));
        vm.stopPrank();
        _mintStaticsDollar(
            IStaticsDollarCore(active.deployment.core), launchStaticsDollar, launchUsdc, active.profileId, maker, 10e18
        );
        vm.prank(maker);
        launchStaticsDollar.approve(address(diamond), type(uint256).max);
        (marketId,) = _createTradingMarket(name, 7 days);
        vm.prank(maker);
        ICurveInventoryFacet(address(diamond)).splitInventory(marketId, 10e18);
        _approvePositions(maker);
        curveId = _postCurveFromMaker(marketId, true, 6e18, DEFAULT_FLAT_PRICE, DEFAULT_FLAT_PRICE, 180);
        (generation, commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
    }

    function _signPermit(IERC20Permit token, address signer, uint256 signerKey, uint256 amount, uint256 deadline)
        internal
        view
        returns (ITradeRouter.PermitSignature memory signature)
    {
        bytes32 structHash =
            keccak256(abi.encode(PERMIT_TYPEHASH, signer, address(diamond), amount, token.nonces(signer), deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
        (signature.v, signature.r, signature.s) = vm.sign(signerKey, digest);
        signature.deadline = deadline;
    }

    function _buySelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = ITradeRouter.buyWithCollateral.selector;
        selectors[1] = ITradeRouter.buyWithCollateralWithPermit.selector;
    }

    function _exactBuySelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = ITradeRouter.buyWithCollateralExact.selector;
    }

    function _sellSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = ITradeRouter.sellWithCollateral.selector;
    }

    function _previewSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = ITradeRouter.previewSellBest.selector;
        selectors[1] = ITradeRouter.executeExactRouterTransfer.selector;
    }

    function _staticsDollarSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = ITradeRouter.mintAndBuyWithUSDC.selector;
        selectors[1] = ITradeRouter.mintAndBuyWithUSDCPermit.selector;
    }

    function _collateralExecutionSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = ICollateralTradeExecution.executeCollateralBuy.selector;
    }

    function _seniorConfigSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = RouterSeniorConfigFacet.setMarginAsset.selector;
    }

    function _seniorMutationSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = ISeniorCapitalFacet.depositSeniorCapital.selector;
        selectors[1] = ISeniorCapitalFacet.activateSeniorCapital.selector;
    }

    function _seniorViewSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = ISeniorCapitalFacet.seniorCapitalState.selector;
        selectors[1] = ISeniorCapitalFacet.seniorCapitalAccount.selector;
    }
}
