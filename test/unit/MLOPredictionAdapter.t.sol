// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {EveUSDC} from "../../src/EveUSDC.sol";
import {SeniorCapitalPool} from "../../src/SeniorCapitalPool.sol";
import {DelayedOrderFacet} from "../../src/facets/DelayedOrderFacet.sol";
import {CurveViewFacet} from "../../src/facets/CurveViewFacet.sol";
import {MarginAccountFacet} from "../../src/facets/MarginAccountFacet.sol";
import {MarkOracleFacet} from "../../src/facets/MarkOracleFacet.sol";
import {MLOPredictionAdapterFacet} from "../../src/facets/MLOPredictionAdapterFacet.sol";
import {MLOPredictionCurveFacet} from "../../src/facets/MLOPredictionCurveFacet.sol";
import {MLOPredictionSettlementFacet} from "../../src/facets/MLOPredictionSettlementFacet.sol";
import {MLOPredictionTradeFacet} from "../../src/facets/MLOPredictionTradeFacet.sol";
import {QuoteEnvelopeFacet} from "../../src/facets/QuoteEnvelopeFacet.sol";
import {IMarginAccountFacet} from "../../src/interfaces/IMarginAccountFacet.sol";
import {IMarkOracleFacet} from "../../src/interfaces/IMarkOracleFacet.sol";
import {IMLOPredictionAdapterFacet} from "../../src/interfaces/IMLOPredictionAdapterFacet.sol";
import {IQuoteEnvelopeFacet} from "../../src/interfaces/IQuoteEnvelopeFacet.sol";
import {ISeniorCapitalPool} from "../../src/interfaces/ISeniorCapitalPool.sol";
import {DelayedOrderTypes} from "../../src/types/DelayedOrderTypes.sol";
import {MLOPredictionTypes} from "../../src/types/MLOPredictionTypes.sol";
import {MarginTypes} from "../../src/types/MarginTypes.sol";
import {MarkOracleTypes} from "../../src/types/MarkOracleTypes.sol";
import {QuoteEnvelopeTypes} from "../../src/types/QuoteEnvelopeTypes.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {LibCLOBBook} from "../../src/libraries/LibCLOBBook.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {ITestStateFacet, TestBase} from "../helpers/TestBase.sol";

contract MLOPredictionAdapterTest is TestBase {
    uint128 internal constant PRICE_DENOMINATOR = 1_000_000_000;
    uint128 internal constant FORTY_CENTS = 400_000_000;
    uint128 internal constant SIXTY_CENTS = 600_000_000;
    uint128 internal constant ONE_HUNDRED_SHARES = 100e18;

    EveUSDC internal eveUSDC;
    SeniorCapitalPool internal seniorPool;
    bytes32 internal marketId;
    bytes32 internal yesBookId;
    bytes32 internal bucketId;
    uint64 internal marketExpiry;

    function setUp() public override {
        super.setUp();

        eveUSDC = new EveUSDC(address(usdc), makeAddr("onramp"), makeAddr("offramp"));
        seniorPool = new SeniorCapitalPool(address(eveUSDC), owner, address(diamond));

        vm.startPrank(owner);
        diamond.registerFacet(address(new MarginAccountFacet()), _marginSelectors());
        diamond.registerFacet(address(new QuoteEnvelopeFacet()), _quoteEnvelopeSelectors());
        diamond.registerFacet(address(new MLOPredictionAdapterFacet()), _mloAdapterSelectors());
        diamond.registerFacet(address(new MLOPredictionCurveFacet()), _mloCurveSelectors());
        diamond.registerFacet(address(new MLOPredictionTradeFacet()), _mloTradeSelectors());
        diamond.registerFacet(address(new MLOPredictionSettlementFacet()), _mloSettlementSelectors());
        diamond.registerFacet(address(new CurveViewFacet()), _curveViewSelectors());
        diamond.registerFacet(address(new DelayedOrderFacet()), _delayedOrderSelectors());
        diamond.registerFacet(address(new MarkOracleFacet()), _markOracleSelectors());
        IMarginAccountFacet(address(diamond)).setMarginAsset(address(eveUSDC));
        IMarginAccountFacet(address(diamond)).setMarginRiskManager(address(diamond));
        IMLOPredictionAdapterFacet(address(diamond)).setSeniorCapitalPool(address(seniorPool));
        ITestStateFacet(address(diamond))
            .configure(address(conditionalTokens), address(eveUSDC), address(eveToken), treasury);
        ITestStateFacet(address(diamond)).setDelayedOrderConfigFixture(1, 10, 120);
        ITestStateFacet(address(diamond))
            .setDelayedOrderProcessingFixture(uint8(LibEveMarket.ProcessingMode.Permissionless), 0);
        vm.stopPrank();

        marketExpiry = _expiry(7 days);
        (marketId,) = _createMarketFixture("Can MLO-backed asks fill?", marketExpiry);
        ITestStateFacet(address(diamond)).materializeMarketSideBookFixture(marketId, true);
        yesBookId = LibCLOBBook.marketBookId(marketId, true);

        _fundSeniorPool(creator, 1_000e18);
        _depositAndAllocate(maker, 300e18);
        _wrapEveUSDC(taker, 500e6);
    }

    function test_DirectMLOAskFillUsesSeniorCapitalAndRetainsOppositeInventory() public {
        uint256 envelopeId = _createEnvelope();
        uint256 curveId = _createMLOAskCurve(envelopeId);
        (uint32 generation, bytes32 commitment) = CurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        vm.startPrank(taker);
        eveUSDC.approve(address(diamond), 25e18);
        MLOPredictionTypes.FillResult memory result = IMLOPredictionAdapterFacet(address(diamond))
            .fillMLOAskCurve(
                MLOPredictionTypes.FillMLOAskCurveParams({
                    curveId: curveId,
                    collateralIn: 25e18,
                    minSharesOut: 1,
                    expectedGeneration: generation,
                    expectedCommitment: commitment,
                    receiver: taker
                })
            );
        vm.stopPrank();

        assertGt(result.fill.sharesOut, 0);
        assertEq(
            result.fill.averagePrice,
            uint128((uint256(result.fill.collateralUsed) * PRICE_DENOMINATOR) / result.fill.sharesOut)
        );
        assertEq(conditionalTokens.balanceOf(taker, _yesPositionId()), result.fill.sharesOut);

        MLOPredictionTypes.MLOInventoryView memory inventory =
            IMLOPredictionAdapterFacet(address(diamond)).getMLOInventory(bucketId, marketId);
        assertEq(inventory.noInventory, result.fill.sharesOut);
        assertEq(inventory.yesInventory, 0);
        assertEq(conditionalTokens.balanceOf(inventory.vault, _noPositionId()), result.fill.sharesOut);

        ISeniorCapitalPool.PoolBucketAccounting memory accounting = seniorPool.bucketAccounting(bucketId);
        uint256 grossCost = result.fill.collateralUsed - result.fill.feePaid;
        assertEq(accounting.activeExposure, uint256(result.fill.sharesOut) - grossCost);
        assertEq(accounting.reservedCapital, ONE_HUNDRED_SHARES - result.fill.sharesOut);

        MarginTypes.MarginBucket memory bucket = IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId);
        assertEq(bucket.vaultDebt, accounting.activeExposure);
        assertGt(bucket.positionRisk, 0);

        MLOPredictionTypes.MLOAskCurveView memory curve =
            IMLOPredictionAdapterFacet(address(diamond)).getMLOAskCurve(curveId);
        assertEq(curve.seniorPool, address(seniorPool));
        assertEq(curve.seniorReserved, ONE_HUNDRED_SHARES - result.fill.sharesOut);
        assertEq(curve.remainingVolume, 50e18 - result.fill.sharesOut);
    }

    function test_MLOFillConsumesPreReservedRiskWithoutSecondGrossMarginCheck() public {
        address tightMaker = makeAddr("tight-maker");
        _wrapEveUSDC(tightMaker, 60e6);
        bytes32 riskDomain = IMarginAccountFacet(address(diamond)).riskDomainForMarketBook(marketId, yesBookId);
        vm.startPrank(tightMaker);
        eveUSDC.approve(address(diamond), 60e18);
        IMarginAccountFacet(address(diamond)).depositMargin(60e18, tightMaker);
        bytes32 tightBucketId = IMarginAccountFacet(address(diamond)).allocateBucketMargin(riskDomain, 60e18);
        uint256 envelopeId = IQuoteEnvelopeFacet(address(diamond))
            .createQuoteEnvelope(
                QuoteEnvelopeTypes.CreateQuoteEnvelopeParams({
                    bucketId: tightBucketId,
                    bookId: yesBookId,
                    side: uint8(LibEveMarket.CurveSide.ASK),
                    maxVolume: ONE_HUNDRED_SHARES,
                    minPrice: FORTY_CENTS,
                    maxPrice: SIXTY_CENTS,
                    initialVolume: 50e18,
                    initialStartPrice: FORTY_CENTS,
                    initialEndPrice: FORTY_CENTS,
                    expiresAt: uint64(block.timestamp + 1 hours)
                })
            );
        uint256 curveId = IMLOPredictionAdapterFacet(address(diamond))
            .createMLOAskCurve(
                MLOPredictionTypes.CreateMLOAskCurveParams({envelopeId: envelopeId, durationMinutes: 120})
            );
        vm.stopPrank();

        (uint32 generation, bytes32 commitment) = CurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        vm.startPrank(taker);
        eveUSDC.approve(address(diamond), 25e18);
        MLOPredictionTypes.FillResult memory result = IMLOPredictionAdapterFacet(address(diamond))
            .fillMLOAskCurve(
                MLOPredictionTypes.FillMLOAskCurveParams({
                    curveId: curveId,
                    collateralIn: 25e18,
                    minSharesOut: 50e18,
                    expectedGeneration: generation,
                    expectedCommitment: commitment,
                    receiver: taker
                })
            );
        vm.stopPrank();

        assertEq(result.fill.sharesOut, 50e18);
        MarginTypes.MarginBucket memory bucket = IMarginAccountFacet(address(diamond)).getMarginBucket(tightBucketId);
        assertEq(bucket.openOrderRisk, 30e18);
        assertEq(bucket.positionRisk, 30e18);
        assertEq(bucket.vaultDebt, 30e18);
    }

    function test_DelayedMLOAskFillUsesSameSettlementPath() public {
        uint256 envelopeId = _createEnvelope();
        uint256 curveId = _createMLOAskCurve(envelopeId);
        DelayedOrderTypes.DelayedOrderRoute memory route = _route(curveId);

        uint256 orderId = _submitMarketBuy(yesBookId, 20e18, route);
        vm.roll(block.number + 1);
        DelayedOrderTypes.ProcessDelayedOrderResult memory processed =
            DelayedOrderFacet(address(diamond)).processDelayedOrders(yesBookId, 1, _singleRoute(route));

        assertEq(processed.processedCount, 1);
        assertEq(
            uint8(DelayedOrderFacet(address(diamond)).getDelayedOrder(orderId).status),
            uint8(LibEveMarket.DelayedOrderStatus.Filled)
        );
        assertGt(conditionalTokens.balanceOf(taker, _yesPositionId()), 0);

        MLOPredictionTypes.MLOInventoryView memory inventory =
            IMLOPredictionAdapterFacet(address(diamond)).getMLOInventory(bucketId, marketId);
        assertEq(inventory.noInventory, conditionalTokens.balanceOf(taker, _yesPositionId()));
    }

    function test_DelayedMLOAskFillUsesEscrowAfterTakerApprovalRevoked() public {
        uint256 envelopeId = _createEnvelope();
        uint256 curveId = _createMLOAskCurve(envelopeId);
        DelayedOrderTypes.DelayedOrderRoute memory route = _route(curveId);

        _submitMarketBuy(yesBookId, 20e18, route);
        vm.prank(taker);
        eveUSDC.approve(address(diamond), 0);

        vm.roll(block.number + 1);
        DelayedOrderTypes.ProcessDelayedOrderResult memory processed =
            DelayedOrderFacet(address(diamond)).processDelayedOrders(yesBookId, 1, _singleRoute(route));

        assertEq(processed.processedCount, 1);
        assertGt(conditionalTokens.balanceOf(taker, _yesPositionId()), 0);
        assertEq(eveUSDC.allowance(taker, address(diamond)), 0);
    }

    function test_RevertWhen_DiamondCallerCannotBypassMLOFillFunding() public {
        uint256 envelopeId = _createEnvelope();
        uint256 curveId = _createMLOAskCurve(envelopeId);
        (uint32 generation, bytes32 commitment) = CurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        _wrapEveUSDC(address(diamond), 25e6);

        vm.prank(address(diamond));
        vm.expectRevert();
        IMLOPredictionAdapterFacet(address(diamond))
            .fillMLOAskCurve(
                MLOPredictionTypes.FillMLOAskCurveParams({
                    curveId: curveId,
                    collateralIn: 25e18,
                    minSharesOut: 1,
                    expectedGeneration: generation,
                    expectedCommitment: commitment,
                    receiver: taker
                })
            );
    }

    function test_DelayedMLOBuyCancelsWhenBucketBecomesReduceOnlyBeforeExecution() public {
        uint256 envelopeId = _createEnvelope();
        uint256 curveId = _createMLOAskCurve(envelopeId);
        DelayedOrderTypes.DelayedOrderRoute memory route = _route(curveId);
        uint256 orderId = _submitMarketBuy(yesBookId, 20e18, route);

        vm.prank(address(diamond));
        IMarginAccountFacet(address(diamond)).setBucketState(bucketId, MarginTypes.BucketState.ReduceOnly);
        vm.roll(block.number + 1);
        DelayedOrderTypes.ProcessDelayedOrderResult memory processed =
            DelayedOrderFacet(address(diamond)).processDelayedOrders(yesBookId, 1, _singleRoute(route));

        assertEq(processed.processedCount, 1);
        assertEq(
            uint8(DelayedOrderFacet(address(diamond)).getDelayedOrder(orderId).status),
            uint8(LibEveMarket.DelayedOrderStatus.Cancelled)
        );
        assertEq(DelayedOrderFacet(address(diamond)).getQuoteCredit(taker, address(eveUSDC)).withdrawable, 20e18);
    }

    function test_ExistingMLOCurveUsesOriginalSeniorPoolAfterDefaultPoolChanges() public {
        uint256 envelopeId = _createEnvelope();
        uint256 oldCurveId = _createMLOAskCurve(envelopeId);
        SeniorCapitalPool newPool = new SeniorCapitalPool(address(eveUSDC), owner, address(diamond));
        _fundSeniorPool(address(newPool), creator, 1_000e18);

        vm.prank(owner);
        IMLOPredictionAdapterFacet(address(diamond)).setSeniorCapitalPool(address(newPool));

        (uint32 generation, bytes32 commitment) = CurveViewFacet(address(diamond)).getCurveCommitment(oldCurveId);
        vm.startPrank(taker);
        eveUSDC.approve(address(diamond), 25e18);
        IMLOPredictionAdapterFacet(address(diamond))
            .fillMLOAskCurve(
                MLOPredictionTypes.FillMLOAskCurveParams({
                    curveId: oldCurveId,
                    collateralIn: 25e18,
                    minSharesOut: 1,
                    expectedGeneration: generation,
                    expectedCommitment: commitment,
                    receiver: taker
                })
            );
        vm.stopPrank();

        assertGt(seniorPool.bucketAccounting(bucketId).activeExposure, 0);
        assertEq(newPool.bucketAccounting(bucketId).activeExposure, 0);

        uint256 newEnvelopeId = _createEnvelope();
        uint256 newCurveId = _createMLOAskCurve(newEnvelopeId);
        assertEq(IMLOPredictionAdapterFacet(address(diamond)).getMLOAskCurve(newCurveId).seniorPool, address(newPool));
        assertGt(newPool.bucketAccounting(bucketId).reservedCapital, 0);
    }

    function test_SettleWinningMLOInventoryRepaysSeniorAndCreditsBucketProfit() public {
        MLOPredictionTypes.FillResult memory fill = _fillDefaultMLOAsk();
        uint256 seniorDebt = fill.seniorDeployed - fill.seniorRepaid;

        _resolveMarket(uint8(LibEveMarket.MarketOutcome.No));
        MLOPredictionTypes.MLOInventorySettlement memory settlement =
            IMLOPredictionAdapterFacet(address(diamond)).settleMLOInventory(bucketId, marketId);

        assertEq(settlement.seniorRepaid, seniorDebt);
        assertEq(settlement.seniorLoss, 0);
        assertEq(settlement.bucketProfit, fill.fill.sharesOut - seniorDebt);
        assertEq(seniorPool.bucketAccounting(bucketId).activeExposure, 0);

        MarginTypes.MarginBucket memory bucket = IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId);
        assertEq(bucket.vaultDebt, 0);
        assertEq(bucket.positionRisk, 0);
        assertEq(bucket.realizedProfits, settlement.bucketProfit);
        MLOPredictionTypes.MLOInventoryView memory inventory =
            IMLOPredictionAdapterFacet(address(diamond)).getMLOInventory(bucketId, marketId);
        assertEq(inventory.vault, address(0));
        assertEq(inventory.noInventory, 0);
    }

    function test_SettleLosingMLOInventoryUsesBucketMarginBeforeSeniorLoss() public {
        MLOPredictionTypes.FillResult memory fill = _fillDefaultMLOAsk();
        uint256 seniorDebt = fill.seniorDeployed - fill.seniorRepaid;
        uint256 marginBefore = IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId).marginAllocated;

        _resolveMarket(uint8(LibEveMarket.MarketOutcome.Yes));
        MLOPredictionTypes.MLOInventorySettlement memory settlement =
            IMLOPredictionAdapterFacet(address(diamond)).settleMLOInventory(bucketId, marketId);

        assertEq(settlement.collateralOut, 0);
        assertEq(settlement.marginUsed, seniorDebt);
        assertEq(settlement.seniorLoss, 0);
        assertEq(seniorPool.bucketAccounting(bucketId).activeExposure, 0);

        MarginTypes.MarginBucket memory bucket = IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId);
        assertEq(bucket.marginAllocated, marginBefore - seniorDebt);
        assertEq(bucket.vaultDebt, 0);
        assertEq(bucket.positionRisk, 0);
        assertEq(bucket.realizedLosses, seniorDebt);
        assertEq(IMLOPredictionAdapterFacet(address(diamond)).getMLOInventory(bucketId, marketId).vault, address(0));
    }

    function test_CancelMLOAskCurveReleasesUnusedSeniorAndRisk() public {
        uint256 envelopeId = _createEnvelope();
        uint256 curveId = _createMLOAskCurve(envelopeId);

        vm.expectRevert(abi.encodeWithSelector(Errors.QuoteEnvelopeBoundToAdapterCurve.selector, envelopeId, curveId));
        vm.prank(maker);
        IQuoteEnvelopeFacet(address(diamond)).cancelQuoteEnvelope(envelopeId);

        vm.prank(maker);
        IMLOPredictionAdapterFacet(address(diamond)).cancelMLOAskCurve(curveId);

        assertEq(seniorPool.bucketAccounting(bucketId).reservedCapital, 0);
        MarginTypes.MarginBucket memory bucket = IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId);
        assertEq(bucket.openOrderRisk, 0);
        assertEq(bucket.positionRisk, 0);
    }

    function test_RevertWhen_BucketIsReduceOnlyDuringMLOFill() public {
        uint256 envelopeId = _createEnvelope();
        uint256 curveId = _createMLOAskCurve(envelopeId);
        (uint32 generation, bytes32 commitment) = CurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        vm.prank(address(diamond));
        IMarginAccountFacet(address(diamond)).setBucketState(bucketId, MarginTypes.BucketState.ReduceOnly);

        vm.startPrank(taker);
        eveUSDC.approve(address(diamond), 25e18);
        vm.expectRevert(abi.encodeWithSelector(Errors.AdapterCurveInactive.selector, curveId));
        IMLOPredictionAdapterFacet(address(diamond))
            .fillMLOAskCurve(
                MLOPredictionTypes.FillMLOAskCurveParams({
                    curveId: curveId,
                    collateralIn: 25e18,
                    minSharesOut: 1,
                    expectedGeneration: generation,
                    expectedCommitment: commitment,
                    receiver: taker
                })
            );
        vm.stopPrank();
    }

    function test_RevertWhen_OracleBlocksMLOFill() public {
        bytes32 riskDomain = IMarginAccountFacet(address(diamond)).riskDomainForMarketBook(marketId, yesBookId);
        vm.startPrank(owner);
        IMarginAccountFacet(address(diamond))
            .setRiskDomainOracleConfig(riskDomain, MarginTypes.RiskDomainOracleKind.BookMark, yesBookId);
        IMarkOracleFacet(address(diamond)).setMarkOracleManualState(yesBookId, MarkOracleTypes.OracleState.Paused);
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(
                IMarginAccountFacet.RiskDomainOracleBlocked.selector,
                riskDomain,
                yesBookId,
                MarginTypes.RiskDomainOracleKind.BookMark,
                uint8(MarkOracleTypes.OracleState.Paused)
            )
        );
        _createEnvelope();
    }

    function _createEnvelope() internal returns (uint256 envelopeId) {
        vm.prank(maker);
        envelopeId = IQuoteEnvelopeFacet(address(diamond)).createQuoteEnvelope(_defaultEnvelope());
    }

    function _createMLOAskCurve(uint256 envelopeId) internal returns (uint256 curveId) {
        vm.prank(maker);
        curveId = IMLOPredictionAdapterFacet(address(diamond))
            .createMLOAskCurve(
                MLOPredictionTypes.CreateMLOAskCurveParams({envelopeId: envelopeId, durationMinutes: 120})
            );
    }

    function _defaultEnvelope() internal view returns (QuoteEnvelopeTypes.CreateQuoteEnvelopeParams memory params) {
        params = QuoteEnvelopeTypes.CreateQuoteEnvelopeParams({
            bucketId: bucketId,
            bookId: yesBookId,
            side: uint8(LibEveMarket.CurveSide.ASK),
            maxVolume: ONE_HUNDRED_SHARES,
            minPrice: FORTY_CENTS,
            maxPrice: SIXTY_CENTS,
            initialVolume: 50e18,
            initialStartPrice: FORTY_CENTS,
            initialEndPrice: FORTY_CENTS,
            expiresAt: uint64(block.timestamp + 1 hours)
        });
    }

    function _depositAndAllocate(address operator, uint256 assets) internal {
        _wrapEveUSDC(operator, assets / 1e12);
        bytes32 riskDomain = IMarginAccountFacet(address(diamond)).riskDomainForMarketBook(marketId, yesBookId);
        vm.startPrank(operator);
        eveUSDC.approve(address(diamond), assets);
        IMarginAccountFacet(address(diamond)).depositMargin(assets, operator);
        bucketId = IMarginAccountFacet(address(diamond)).allocateBucketMargin(riskDomain, assets);
        vm.stopPrank();
    }

    function _fundSeniorPool(address account, uint256 assets) internal {
        _fundSeniorPool(address(seniorPool), account, assets);
    }

    function _fundSeniorPool(address pool, address account, uint256 assets) internal {
        _wrapEveUSDC(account, assets / 1e12);
        vm.startPrank(account);
        eveUSDC.approve(pool, assets);
        SeniorCapitalPool(pool).deposit(assets, account);
        vm.stopPrank();
    }

    function _fillDefaultMLOAsk() internal returns (MLOPredictionTypes.FillResult memory result) {
        uint256 envelopeId = _createEnvelope();
        uint256 curveId = _createMLOAskCurve(envelopeId);
        (uint32 generation, bytes32 commitment) = CurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        vm.startPrank(taker);
        eveUSDC.approve(address(diamond), 25e18);
        result = IMLOPredictionAdapterFacet(address(diamond))
            .fillMLOAskCurve(
                MLOPredictionTypes.FillMLOAskCurveParams({
                    curveId: curveId,
                    collateralIn: 25e18,
                    minSharesOut: 1,
                    expectedGeneration: generation,
                    expectedCommitment: commitment,
                    receiver: taker
                })
            );
        vm.stopPrank();
    }

    function _resolveMarket(uint8 outcome) internal {
        ITestStateFacet(address(diamond)).resolveMarketFixture(marketId, outcome);
    }

    function _wrapEveUSDC(address account, uint256 usdcAmount) internal {
        usdc.mint(account, usdcAmount);
        vm.startPrank(account);
        usdc.approve(address(eveUSDC), usdcAmount);
        eveUSDC.wrap(usdcAmount, account);
        vm.stopPrank();
    }

    function _submitMarketBuy(bytes32 bookId, uint128 amountIn, DelayedOrderTypes.DelayedOrderRoute memory route)
        internal
        returns (uint256 orderId)
    {
        vm.startPrank(taker);
        eveUSDC.approve(address(diamond), amountIn);
        orderId = DelayedOrderFacet(address(diamond))
            .submitDelayedOrder(
                DelayedOrderTypes.SubmitDelayedOrderParams({
                    bookId: bookId,
                    kind: LibEveMarket.DelayedOrderKind.MarketBuy,
                    amountIn: amountIn,
                    limitPrice: 0,
                    minOut: 1,
                    maxAveragePrice: PRICE_DENOMINATOR,
                    curveIds: route.curveIds,
                    expectedGenerations: route.expectedGenerations,
                    expectedCommitments: route.expectedCommitments
                })
            );
        vm.stopPrank();
    }

    function _route(uint256 curveId) internal view returns (DelayedOrderTypes.DelayedOrderRoute memory route) {
        (uint32 generation, bytes32 commitment) = CurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        route.curveIds = new uint256[](1);
        route.expectedGenerations = new uint32[](1);
        route.expectedCommitments = new bytes32[](1);
        route.curveIds[0] = curveId;
        route.expectedGenerations[0] = generation;
        route.expectedCommitments[0] = commitment;
    }

    function _singleRoute(DelayedOrderTypes.DelayedOrderRoute memory route)
        internal
        pure
        returns (DelayedOrderTypes.DelayedOrderRoute[] memory routes)
    {
        routes = new DelayedOrderTypes.DelayedOrderRoute[](1);
        routes[0] = route;
    }

    function _yesPositionId() internal view returns (uint256) {
        (,,,, uint256 yesPositionId,,,,,) = ITestStateFacet(address(diamond)).getStoredMarket(marketId);
        return yesPositionId;
    }

    function _noPositionId() internal view returns (uint256) {
        (,,,,, uint256 noPositionId,,,,) = ITestStateFacet(address(diamond)).getStoredMarket(marketId);
        return noPositionId;
    }

    function _expiry(uint256 duration) internal view returns (uint64) {
        return uint64(block.timestamp + duration);
    }

    function _marginSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](38);
        selectors[0] = IMarginAccountFacet.marginConfig.selector;
        selectors[1] = IMarginAccountFacet.depositMargin.selector;
        selectors[2] = IMarginAccountFacet.withdrawMargin.selector;
        selectors[3] = IMarginAccountFacet.allocateBucketMargin.selector;
        selectors[4] = IMarginAccountFacet.releaseBucketMargin.selector;
        selectors[5] = IMarginAccountFacet.getMarginAccount.selector;
        selectors[6] = IMarginAccountFacet.getMarginBucket.selector;
        selectors[7] = IMarginAccountFacet.bucketIdFor.selector;
        selectors[8] = IMarginAccountFacet.riskDomainForBook.selector;
        selectors[9] = IMarginAccountFacet.riskDomainForMarketBook.selector;
        selectors[10] = IMarginAccountFacet.canBucketIncreaseRisk.selector;
        selectors[11] = IMarginAccountFacet.setMarginAsset.selector;
        selectors[12] = IMarginAccountFacet.setMarginRiskManager.selector;
        selectors[13] = IMarginAccountFacet.setWarningRiskIncreaseAllowed.selector;
        selectors[14] = IMarginAccountFacet.reserveBucketRisk.selector;
        selectors[15] = IMarginAccountFacet.releaseReservedBucketRisk.selector;
        selectors[16] = IMarginAccountFacet.activateReservedBucketRisk.selector;
        selectors[17] = IMarginAccountFacet.releaseActiveBucketRisk.selector;
        selectors[18] = IMarginAccountFacet.recordBucketProfit.selector;
        selectors[19] = IMarginAccountFacet.recordBucketLoss.selector;
        selectors[20] = IMarginAccountFacet.setBucketState.selector;
        selectors[21] = IMarginAccountFacet.allocateBucketMarginWithKind.selector;
        selectors[22] = IMarginAccountFacet.getBucketRisk.selector;
        selectors[23] = IMarginAccountFacet.bucketLockedRisk.selector;
        selectors[24] = IMarginAccountFacet.canBucketIncreaseRiskForBook.selector;
        selectors[25] = IMarginAccountFacet.riskDomainOracleConfig.selector;
        selectors[26] = IMarginAccountFacet.setRiskDomainOracleConfig.selector;
        selectors[27] = IMarginAccountFacet.increaseOpenOrderRisk.selector;
        selectors[28] = IMarginAccountFacet.releaseOpenOrderRisk.selector;
        selectors[29] = IMarginAccountFacet.moveOpenOrderToPositionRisk.selector;
        selectors[30] = IMarginAccountFacet.releasePositionRisk.selector;
        selectors[31] = IMarginAccountFacet.recordBucketDebt.selector;
        selectors[32] = IMarginAccountFacet.repayBucketDebt.selector;
        selectors[33] = IMarginAccountFacet.accrueBucketFunding.selector;
        selectors[34] = IMarginAccountFacet.settleBucketFunding.selector;
        selectors[35] = IMarginAccountFacet.recordBucketUnrealizedPnl.selector;
        selectors[36] = IMarginAccountFacet.recordBucketRecoveryPnl.selector;
        selectors[37] = IMarginAccountFacet.recordBucketBadDebt.selector;
    }

    function _quoteEnvelopeSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](9);
        selectors[0] = IQuoteEnvelopeFacet.createQuoteEnvelope.selector;
        selectors[1] = IQuoteEnvelopeFacet.updateQuoteEnvelope.selector;
        selectors[2] = IQuoteEnvelopeFacet.cancelQuoteEnvelope.selector;
        selectors[3] = IQuoteEnvelopeFacet.cancelQuoteEnvelopes.selector;
        selectors[4] = IQuoteEnvelopeFacet.getQuoteEnvelope.selector;
        selectors[5] = IQuoteEnvelopeFacet.getOperatorQuoteEnvelopes.selector;
        selectors[6] = IQuoteEnvelopeFacet.getBookQuoteEnvelopes.selector;
        selectors[7] = IQuoteEnvelopeFacet.previewQuoteEnvelopeRisk.selector;
        selectors[8] = IQuoteEnvelopeFacet.canUpdateQuoteEnvelope.selector;
    }

    function _mloAdapterSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = IMLOPredictionAdapterFacet.setSeniorCapitalPool.selector;
        selectors[1] = IMLOPredictionAdapterFacet.seniorCapitalPool.selector;
        selectors[2] = IMLOPredictionAdapterFacet.getMLOAskCurve.selector;
        selectors[3] = IMLOPredictionAdapterFacet.getMLOInventory.selector;
    }

    function _mloCurveSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = IMLOPredictionAdapterFacet.createMLOAskCurve.selector;
        selectors[1] = IMLOPredictionAdapterFacet.updateMLOAskCurve.selector;
        selectors[2] = IMLOPredictionAdapterFacet.cancelMLOAskCurve.selector;
    }

    function _mloTradeSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = IMLOPredictionAdapterFacet.fillMLOAskCurve.selector;
    }

    function _mloSettlementSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = IMLOPredictionAdapterFacet.settleMLOInventory.selector;
    }

    function _curveViewSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = CurveViewFacet.getCurveCommitment.selector;
        selectors[1] = CurveViewFacet.getCurveInfo.selector;
    }

    function _delayedOrderSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](8);
        selectors[0] = DelayedOrderFacet.submitDelayedOrder.selector;
        selectors[1] = DelayedOrderFacet.processDelayedOrders.selector;
        selectors[2] = DelayedOrderFacet.withdrawQuoteCredit.selector;
        selectors[3] = DelayedOrderFacet.withdrawBaseCredit.selector;
        selectors[4] = DelayedOrderFacet.getQuoteCredit.selector;
        selectors[5] = DelayedOrderFacet.getBaseCredit.selector;
        selectors[6] = DelayedOrderFacet.getDelayedOrder.selector;
        selectors[7] = DelayedOrderFacet.getBookQueue.selector;
    }

    function _markOracleSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](9);
        selectors[0] = IMarkOracleFacet.getMarkOracle.selector;
        selectors[1] = IMarkOracleFacet.getMarkObservation.selector;
        selectors[2] = IMarkOracleFacet.consultTwap.selector;
        selectors[3] = IMarkOracleFacet.consultVwap.selector;
        selectors[4] = IMarkOracleFacet.oracleState.selector;
        selectors[5] = IMarkOracleFacet.markOracleConfig.selector;
        selectors[6] = IMarkOracleFacet.setMarkOracleThresholds.selector;
        selectors[7] = IMarkOracleFacet.clearMarkOracleManualState.selector;
        selectors[8] = IMarkOracleFacet.setMarkOracleManualState.selector;
    }
}
