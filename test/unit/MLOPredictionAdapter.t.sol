// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {MockCollateral} from "../helpers/MockCollateral.sol";
import {MLOInventoryVault} from "../../src/MLOInventoryVault.sol";
import {MLOInsuranceFund} from "../../src/MLOInsuranceFund.sol";
import {EvesNegRiskAdapter} from "../../src/EvesNegRiskAdapter.sol";
import {DelayedOrderFacet} from "../../src/facets/DelayedOrderFacet.sol";
import {BookTradeFacet} from "../../src/facets/BookTradeFacet.sol";
import {BookSellFacet} from "../../src/facets/BookSellFacet.sol";
import {BookOrderFacet} from "../../src/facets/BookOrderFacet.sol";
import {CurveViewFacet} from "../../src/facets/CurveViewFacet.sol";
import {DiamondCutFacet} from "../../src/facets/DiamondCutFacet.sol";
import {MarginAccountFacet} from "../../src/facets/MarginAccountFacet.sol";
import {MarkOracleFacet} from "../../src/facets/MarkOracleFacet.sol";
import {MarketFactoryFacet} from "../../src/facets/MarketFactoryFacet.sol";
import {MLOPredictionAdapterFacet} from "../../src/facets/MLOPredictionAdapterFacet.sol";
import {MLOPredictionAskRouteFacet} from "../../src/facets/MLOPredictionAskRouteFacet.sol";
import {MLOPredictionBidTradeFacet} from "../../src/facets/MLOPredictionBidTradeFacet.sol";
import {MLOPredictionCurveFacet} from "../../src/facets/MLOPredictionCurveFacet.sol";
import {MLOPredictionPostFacet} from "../../src/facets/MLOPredictionPostFacet.sol";
import {MLOPredictionRecoveryFacet} from "../../src/facets/MLOPredictionRecoveryFacet.sol";
import {MLOProfitShareFacet} from "../../src/facets/MLOProfitShareFacet.sol";
import {MLOPredictionSettlementFacet} from "../../src/facets/MLOPredictionSettlementFacet.sol";
import {MLOPredictionTradeFacet} from "../../src/facets/MLOPredictionTradeFacet.sol";
import {MLOPredictionUpdateFacet} from "../../src/facets/MLOPredictionUpdateFacet.sol";
import {SeniorCapitalFacet} from "../../src/facets/SeniorCapitalFacet.sol";
import {SeniorCapitalViewFacet} from "../../src/facets/SeniorCapitalViewFacet.sol";
import {MultiOutcomeOrderbookFacet} from "../../src/facets/MultiOutcomeOrderbookFacet.sol";
import {MultiOutcomeOrderbookViewFacet} from "../../src/facets/MultiOutcomeOrderbookViewFacet.sol";
import {OwnershipFacet} from "../../src/facets/OwnershipFacet.sol";
import {NegRiskConfigFacet} from "../../src/facets/NegRiskConfigFacet.sol";
import {OBRResolutionFacet} from "../../src/facets/OBRResolutionFacet.sol";
import {QuoteEnvelopeFacet} from "../../src/facets/QuoteEnvelopeFacet.sol";
import {TradeRouterBookFacet} from "../../src/facets/TradeRouterBookFacet.sol";
import {TradeRouterBookSellFacet} from "../../src/facets/TradeRouterBookSellFacet.sol";
import {IBookOrderFacet} from "../../src/interfaces/IBookOrderFacet.sol";
import {IBookTradeFacet} from "../../src/interfaces/IBookTradeFacet.sol";
import {IMarkOracleFacet} from "../../src/interfaces/IMarkOracleFacet.sol";
import {IMarketFactoryFacet} from "../../src/interfaces/IMarketFactoryFacet.sol";
import {IMarginAccountFacet as IProductionMarginAccountFacet} from "../../src/interfaces/IMarginAccountFacet.sol";
import {IMLOPredictionAdapterFacet} from "../../src/interfaces/IMLOPredictionAdapterFacet.sol";
import {IMLOProfitShareFacet} from "../../src/interfaces/IMLOProfitShareFacet.sol";
import {IMultiOutcomeOrderbookFacet} from "../../src/interfaces/IMultiOutcomeOrderbookFacet.sol";
import {IOBRResolutionFacet} from "../../src/interfaces/IOBRResolutionFacet.sol";
import {IQuoteEnvelopeFacet} from "../../src/interfaces/IQuoteEnvelopeFacet.sol";
import {ISeniorCapitalFacet} from "../../src/interfaces/ISeniorCapitalFacet.sol";
import {ITradeRouter} from "../../src/interfaces/ITradeRouter.sol";
import {ITradeRouterBook} from "../../src/interfaces/ITradeRouterBook.sol";
import {DelayedOrderTypes} from "../../src/types/DelayedOrderTypes.sol";
import {CurveCLOBTypes} from "../../src/types/CurveCLOBTypes.sol";
import {MLOPredictionTypes} from "../../src/types/MLOPredictionTypes.sol";
import {MLOProfitShareTypes} from "../../src/types/MLOProfitShareTypes.sol";
import {MarginTypes} from "../../src/types/MarginTypes.sol";
import {MarkOracleTypes} from "../../src/types/MarkOracleTypes.sol";
import {QuoteEnvelopeTypes} from "../../src/types/QuoteEnvelopeTypes.sol";
import {MarketFactoryTypes} from "../../src/types/MarketFactoryTypes.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {LibCLOBBook} from "../../src/libraries/LibCLOBBook.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {ITestStateFacet, TestBase} from "../helpers/TestBase.sol";
import {
    IMarginTestFacet as IMarginAccountFacet,
    MarginAccountingHarnessFacet,
    MarginAccountingHarnessSelectors
} from "../helpers/MarginAccountingHarnessFacet.sol";

contract MLOPredictionAdapterTest is TestBase {
    uint256 internal constant EIP170_MAX_CODE_SIZE = 24_576;
    uint128 internal constant PRICE_DENOMINATOR = 1_000_000_000;
    uint128 internal constant FORTY_CENTS = 400_000_000;
    uint128 internal constant SIXTY_CENTS = 600_000_000;
    uint128 internal constant ONE_HUNDRED_SHARES = 100e18;

    MockCollateral internal collateral;
    MLOInsuranceFund internal insuranceFund;
    EvesNegRiskAdapter internal negRiskAdapter;
    bytes32 internal marketId;
    bytes32 internal yesBookId;
    bytes32 internal noBookId;
    bytes32 internal bucketId;
    uint64 internal marketExpiry;

    function setUp() public override {
        super.setUp();

        collateral = new MockCollateral();
        insuranceFund = new MLOInsuranceFund(address(collateral), address(diamond), address(diamond));
        negRiskAdapter = new EvesNegRiskAdapter(address(conditionalTokens), address(collateral), address(diamond));

        vm.startPrank(owner);
        diamond.registerFacet(address(new DiamondCutFacet()), _diamondCutSelectors());
        diamond.registerFacet(address(new MarginAccountFacet()), _marginSelectors());
        diamond.registerFacet(address(new MarginAccountingHarnessFacet()), MarginAccountingHarnessSelectors.harness());
        diamond.registerFacet(address(new QuoteEnvelopeFacet()), _quoteEnvelopeSelectors());
        diamond.registerFacet(address(new MLOPredictionAdapterFacet()), _mloAdapterSelectors());
        diamond.registerFacet(address(new MLOPredictionCurveFacet()), _mloCurveSelectors());
        diamond.registerFacet(address(new MLOPredictionPostFacet()), _mloPostSelectors());
        diamond.registerFacet(address(new MLOPredictionUpdateFacet()), _mloUpdateSelectors());
        diamond.registerFacet(address(new MLOPredictionTradeFacet()), _mloTradeSelectors());
        diamond.registerFacet(address(new MLOPredictionAskRouteFacet()), _mloAskRouteSelectors());
        diamond.registerFacet(address(new MLOPredictionBidTradeFacet()), _mloBidTradeSelectors());
        diamond.registerFacet(address(new MLOPredictionSettlementFacet()), _mloSettlementSelectors());
        diamond.registerFacet(address(new MLOPredictionRecoveryFacet()), _mloRecoverySelectors());
        diamond.registerFacet(address(new MLOProfitShareFacet()), _mloProfitShareSelectors());
        diamond.registerFacet(address(new CurveViewFacet()), _curveViewSelectors());
        diamond.registerFacet(address(new DelayedOrderFacet()), _delayedOrderSelectors());
        diamond.registerFacet(address(new BookTradeFacet()), _bookTradeSelectors());
        diamond.registerFacet(address(new BookSellFacet()), _bookSellSelectors());
        diamond.registerFacet(address(new BookOrderFacet()), _bookOrderSelectors());
        diamond.registerFacet(address(new MarkOracleFacet()), _markOracleSelectors());
        diamond.registerFacet(address(new OwnershipFacet()), _ownershipSelectors());
        diamond.registerFacet(address(new NegRiskConfigFacet()), _negRiskConfigSelectors());
        diamond.registerFacet(address(new MultiOutcomeOrderbookFacet()), _multiOutcomeSelectors());
        diamond.registerFacet(address(new MultiOutcomeOrderbookViewFacet()), _multiOutcomeViewSelectors());
        diamond.registerFacet(address(new TradeRouterBookFacet()), _tradeRouterBookSelectors());
        diamond.registerFacet(address(new TradeRouterBookSellFacet()), _tradeRouterBookSellSelectors());
        diamond.registerFacet(address(new OBRResolutionFacet()), _mloResolutionSelectors());
        diamond.registerFacet(address(new MarketFactoryFacet()), _marketStateSelectors());
        diamond.registerFacet(address(new SeniorCapitalFacet()), _seniorCapitalSelectors());
        diamond.registerFacet(address(new SeniorCapitalViewFacet()), _seniorCapitalViewSelectors());
        IMarginAccountFacet(address(diamond)).setMarginAsset(address(collateral));
        IMLOPredictionAdapterFacet(address(diamond)).setMLORecoveryConfig(address(insuranceFund), 5_000, 32);
        IMLOProfitShareFacet(address(diamond)).initializeMLOProfitSplit(7_500, 2_000, 500);
        ITestStateFacet(address(diamond))
            .configure(address(conditionalTokens), address(collateral), address(eveToken), treasury);
        ITestStateFacet(address(diamond)).setStaticsDollarCoreFixture(address(collateral));
        NegRiskConfigFacet(address(diamond)).setNegRiskAdapter(address(negRiskAdapter));
        ITestStateFacet(address(diamond)).setDelayedOrderConfigFixture(1, 10, 120);
        ITestStateFacet(address(diamond))
            .setDelayedOrderProcessingFixture(uint8(LibEveMarket.ProcessingMode.Permissionless), 0);
        OwnershipFacet(address(diamond)).setMarketCreationBond(0);
        vm.stopPrank();

        marketExpiry = _expiry(7 days);
        (marketId,) = _createMarketFixture("Can MLO-backed asks fill?", marketExpiry);
        ITestStateFacet(address(diamond)).materializeMarketSideBookFixture(marketId, true);
        ITestStateFacet(address(diamond)).materializeMarketSideBookFixture(marketId, false);
        yesBookId = LibCLOBBook.marketBookId(marketId, true);
        noBookId = LibCLOBBook.marketBookId(marketId, false);

        _fundSeniorPool(creator, 1_000e18);
        _depositAndAllocate(maker, 300e18);
        _fundCollateral(taker, 500e6);
    }

    function _diamondCutSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](10);
        selectors[0] = DiamondCutFacet.diamondCut.selector;
        selectors[1] = DiamondCutFacet.freezeFacet.selector;
        selectors[2] = DiamondCutFacet.isSelectorFrozen.selector;
        selectors[3] = DiamondCutFacet.scheduleGovernanceOperation.selector;
        selectors[4] = DiamondCutFacet.cancelGovernanceOperation.selector;
        selectors[5] = DiamondCutFacet.finalizeGovernanceDelay.selector;
        selectors[6] = DiamondCutFacet.governanceOperationId.selector;
        selectors[7] = DiamondCutFacet.governanceOperationReadyAt.selector;
        selectors[8] = DiamondCutFacet.governanceDelay.selector;
        selectors[9] = DiamondCutFacet.governanceDelayFinalized.selector;
    }

    function test_DirectMLOAskFillUsesSeniorCapitalAndRetainsOppositeInventory() public {
        uint256 envelopeId = _createEnvelope();
        uint256 curveId = _createMLOCurve(envelopeId);
        (uint32 generation, bytes32 commitment) = CurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        vm.startPrank(taker);
        collateral.approve(address(diamond), 25e18);
        MLOPredictionTypes.MLOAskFillResult memory result = IMLOPredictionAdapterFacet(address(diamond))
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
        assertEq(inventory.inventory[1], result.fill.sharesOut);
        assertEq(inventory.inventory[0], 0);
        assertEq(inventory.reserved[1], 0);
        assertEq(inventory.seniorDebt, result.seniorDeployed - result.seniorRepaid);
        assertEq(inventory.seniorReserved, 50e18 - result.fill.sharesOut);
        assertEq(conditionalTokens.balanceOf(inventory.vault, _noPositionId()), result.fill.sharesOut);

        ISeniorCapitalFacet.SeniorCapitalBucket memory accounting = _seniorBucket(bucketId);
        uint256 grossCost = result.fill.collateralUsed - result.fill.feePaid;
        assertEq(accounting.activeExposure, uint256(result.fill.sharesOut) - grossCost);
        assertEq(accounting.reservedCapital, 50e18 - result.fill.sharesOut);

        MarginTypes.MarginBucket memory bucket = IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId);
        assertEq(bucket.vaultDebt, accounting.activeExposure);
        assertGt(bucket.positionRisk, 0);

        MLOPredictionTypes.MLOScenarioExposureView memory exposure =
            IMLOPredictionAdapterFacet(address(diamond)).getMLOScenarioExposure(bucketId);
        uint256 scenarioGrossCost = result.fill.collateralUsed - result.fill.feePaid;
        int256 debt = int256(uint256(result.fill.sharesOut) - scenarioGrossCost);
        assertEq(exposure.marketId, marketId);
        assertEq(exposure.outcomeCount, 2);
        assertEq(exposure.openLosses[0], 0);
        assertEq(exposure.openLosses[1], 0);
        assertEq(exposure.openLosses[2], 0);
        assertEq(exposure.filledPositionLosses[0], debt);
        assertEq(exposure.filledPositionLosses[1], -int256(scenarioGrossCost));
        assertEq(exposure.filledPositionLosses[2], debt - int256(uint256(result.fill.sharesOut) / 2));
        assertEq(exposure.maximumRawLoss, int256(30e18));
        assertEq(exposure.initialRequirement, 30e18);
        assertEq(IMarginAccountFacet(address(diamond)).bucketHealth(bucketId).exposure, 30e18);

        MLOPredictionTypes.MLOCurveView memory curve = IMLOPredictionAdapterFacet(address(diamond)).getMLOCurve(curveId);
        assertEq(curve.inventoryReserved, 0);
        assertEq(curve.seniorReserved, 50e18 - result.fill.sharesOut);
        assertEq(curve.remainingVolume, 50e18 - result.fill.sharesOut);
    }

    function test_AtomicMLOPostCreatesEnvelopeAndCurveWithInitialBacking() public {
        MLOPredictionTypes.PostMLOCurveParams memory params = _postMLOParams(yesBookId);
        uint256 snapshotId = vm.snapshotState();

        vm.prank(maker);
        uint256 separateEnvelopeId = IQuoteEnvelopeFacet(address(diamond)).createQuoteEnvelope(params.envelope);
        uint256 separateGas = vm.lastCallGas().gasTotalUsed;
        vm.prank(maker);
        IMLOPredictionAdapterFacet(address(diamond))
            .createMLOCurve(
                MLOPredictionTypes.CreateMLOCurveParams({
                    envelopeId: separateEnvelopeId, durationMinutes: params.durationMinutes
                })
            );
        separateGas += vm.lastCallGas().gasTotalUsed;

        assertTrue(vm.revertToState(snapshotId));

        vm.prank(maker);
        (uint256 envelopeId, uint256 curveId) = IMLOPredictionAdapterFacet(address(diamond)).postMLOCurve(params);
        uint256 atomicGas = vm.lastCallGas().gasTotalUsed;

        MLOPredictionTypes.MLOCurveView memory curve = IMLOPredictionAdapterFacet(address(diamond)).getMLOCurve(curveId);
        QuoteEnvelopeTypes.QuoteEnvelopeView memory envelope =
            IQuoteEnvelopeFacet(address(diamond)).getQuoteEnvelope(envelopeId);
        assertEq(curve.envelopeId, envelopeId);
        assertEq(curve.remainingVolume, 50e18);
        assertEq(curve.seniorReserved, 30e18);
        assertEq(envelope.remainingRiskVolume, 50e18);
        assertEq(envelope.reservedRisk, 30e18);
        assertFalse(envelope.canUpdate);
        assertEq(_seniorBucket(bucketId).reservedCapital, 30e18);
        assertLt(atomicGas, separateGas);
        emit log_named_uint("MLO separate create gas", separateGas);
        emit log_named_uint("MLO atomic post gas", atomicGas);
    }

    function test_AtomicMLOPostBatchCreatesBothOutcomeQuotes() public {
        MLOPredictionTypes.PostMLOCurveParams[] memory params = new MLOPredictionTypes.PostMLOCurveParams[](2);
        params[0] = _postMLOParams(yesBookId);
        params[1] = _postMLOParams(noBookId);
        uint256 snapshotId = vm.snapshotState();

        uint256 separateGas;
        for (uint256 index; index < params.length; ++index) {
            vm.prank(maker);
            IMLOPredictionAdapterFacet(address(diamond)).postMLOCurve(params[index]);
            separateGas += vm.lastCallGas().gasTotalUsed;
        }

        assertTrue(vm.revertToState(snapshotId));

        vm.prank(maker);
        MLOPredictionTypes.MLOCurveIds[] memory ids =
            IMLOPredictionAdapterFacet(address(diamond)).postMLOCurvesBatch(params);
        uint256 batchGas = vm.lastCallGas().gasTotalUsed;

        assertEq(ids.length, 2);
        assertEq(IMLOPredictionAdapterFacet(address(diamond)).getMLOCurve(ids[0].curveId).envelopeId, ids[0].envelopeId);
        assertEq(IMLOPredictionAdapterFacet(address(diamond)).getMLOCurve(ids[1].curveId).envelopeId, ids[1].envelopeId);
        assertEq(_seniorBucket(bucketId).reservedCapital, 60e18);
        assertEq(
            IMLOPredictionAdapterFacet(address(diamond)).getMLOScenarioExposure(bucketId).initialRequirement, 30e18
        );
        assertLt(batchGas, separateGas);
        emit log_named_uint("MLO two atomic posts gas", separateGas);
        emit log_named_uint("MLO batch post gas", batchGas);
    }

    function test_RevertWhen_MLOPostOrUpdateBatchIsEmpty() public {
        MLOPredictionTypes.PostMLOCurveParams[] memory posts = new MLOPredictionTypes.PostMLOCurveParams[](0);
        vm.expectRevert(IMLOPredictionAdapterFacet.MLOEmptyBatch.selector);
        IMLOPredictionAdapterFacet(address(diamond)).postMLOCurvesBatch(posts);

        MLOPredictionTypes.UpdateMLOCurveParams[] memory updates = new MLOPredictionTypes.UpdateMLOCurveParams[](0);
        vm.expectRevert(IMLOPredictionAdapterFacet.MLOEmptyBatch.selector);
        IMLOPredictionAdapterFacet(address(diamond)).updateMLOCurvesBatch(updates);
    }

    function test_MLOUpdateReleasesAndReacquiresRiskAndSeniorCapital() public {
        uint256 curveId = _createMLOCurve(_createEnvelope());
        assertEq(ITestStateFacet(address(diamond)).getActiveBookCurveIdsFixture(yesBookId).length, 1);
        assertEq(ITestStateFacet(address(diamond)).getBookMakerAskExposureFixture(yesBookId, maker), 50e18);

        _updateMLOCurve(curveId, 20e18, FORTY_CENTS, FORTY_CENTS, false);
        _assertMLOReservation(curveId, 20e18, 0, 12e18, 12e18);
        assertEq(ITestStateFacet(address(diamond)).getBookMakerAskExposureFixture(yesBookId, maker), 20e18);

        _updateMLOCurve(curveId, 0, FORTY_CENTS, FORTY_CENTS, false);
        _assertMLOReservation(curveId, 0, 0, 0, 0);
        assertEq(ITestStateFacet(address(diamond)).getActiveBookCurveIdsFixture(yesBookId).length, 0);
        assertEq(ITestStateFacet(address(diamond)).getBookMakerAskExposureFixture(yesBookId, maker), 0);

        _updateMLOCurve(curveId, 80e18, FORTY_CENTS, FORTY_CENTS, false);
        _assertMLOReservation(curveId, 80e18, 0, 48e18, 48e18);
        uint256[] memory activeIds = ITestStateFacet(address(diamond)).getActiveBookCurveIdsFixture(yesBookId);
        assertEq(activeIds.length, 1);
        assertEq(activeIds[0], curveId);
        assertEq(ITestStateFacet(address(diamond)).getBookMakerAskExposureFixture(yesBookId, maker), 80e18);
    }

    function test_MLOUpdateUsesInventoryBeforeReacquiringSeniorCapital() public {
        _fillDefaultMLOAsk();
        uint256 curveId = _createMLOCurve(_createEnvelopeForBook(noBookId));
        _assertMLOReservation(curveId, 50e18, 50e18, 0, 30e18);

        _updateMLOCurve(curveId, 20e18, FORTY_CENTS, FORTY_CENTS, false);
        _assertMLOReservation(curveId, 20e18, 20e18, 0, 12e18);

        _updateMLOCurve(curveId, 80e18, FORTY_CENTS, FORTY_CENTS, false);
        _assertMLOReservation(curveId, 80e18, 50e18, 18e18, 48e18);

        _updateMLOCurve(curveId, 0, FORTY_CENTS, FORTY_CENTS, false);
        _assertMLOReservation(curveId, 0, 0, 0, 0);
    }

    function test_MLOBidUpdateResizesCollateralReservation() public {
        uint256 curveId = _createMLOCurve(_createBidEnvelopeForBook(yesBookId));
        _assertMLOReservation(curveId, 50e18, 0, 30e18, 30e18);

        _updateMLOCurve(curveId, 20e18, FORTY_CENTS, FORTY_CENTS, false);
        _assertMLOReservation(curveId, 20e18, 0, 12e18, 12e18);

        _updateMLOCurve(curveId, 0, FORTY_CENTS, FORTY_CENTS, false);
        _assertMLOReservation(curveId, 0, 0, 0, 0);

        _updateMLOCurve(curveId, 80e18, FORTY_CENTS, FORTY_CENTS, false);
        _assertMLOReservation(curveId, 80e18, 0, 48e18, 48e18);
    }

    function test_MLOUpdateCanReplenishCapacityAfterFill() public {
        uint256 curveId = _createMLOCurve(_createEnvelope());
        _fillCurve(curveId, 25e18, 50e18);
        _assertMLOReservation(curveId, 0, 0, 0, 0);
        assertEq(ITestStateFacet(address(diamond)).getActiveBookCurveIdsFixture(yesBookId).length, 0);
        assertEq(ITestStateFacet(address(diamond)).getBookMakerAskExposureFixture(yesBookId, maker), 0);

        _updateMLOCurve(curveId, 50e18, FORTY_CENTS, FORTY_CENTS, false);
        _assertMLOReservation(curveId, 50e18, 0, 30e18, 30e18);
        assertEq(ITestStateFacet(address(diamond)).getActiveBookCurveIdsFixture(yesBookId).length, 1);
        assertEq(ITestStateFacet(address(diamond)).getBookMakerAskExposureFixture(yesBookId, maker), 50e18);
        ISeniorCapitalFacet.SeniorCapitalBucket memory accounting = _seniorBucket(bucketId);
        assertEq(accounting.activeExposure, 30e18);
        assertEq(accounting.reservedCapital, 30e18);
        assertEq(
            IMLOPredictionAdapterFacet(address(diamond)).getMLOScenarioExposure(bucketId).initialRequirement, 60e18
        );
    }

    function test_MLOUpdateReductionSucceedsBelowInitialMargin() public {
        uint256 curveId = _createMLOCurve(_createEnvelope());
        IMarginAccountFacet(address(diamond)).recordBucketLoss(bucketId, 272e18);
        assertEq(
            IMLOPredictionAdapterFacet(address(diamond)).synchronizeMLOBucketState(bucketId),
            uint8(MarginTypes.BucketState.ReduceOnly)
        );

        _updateMLOCurve(curveId, 20e18, FORTY_CENTS, FORTY_CENTS, false);
        _assertMLOReservation(curveId, 20e18, 0, 12e18, 12e18);
    }

    function test_MLOUpdateFromNowRestartsCurveClock() public {
        QuoteEnvelopeTypes.CreateQuoteEnvelopeParams memory envelope = _defaultEnvelope();
        envelope.initialEndPrice = SIXTY_CENTS;
        envelope.expiresAt = uint64(block.timestamp + 3 hours);
        vm.startPrank(maker);
        uint256 envelopeId = IQuoteEnvelopeFacet(address(diamond)).createQuoteEnvelope(envelope);
        uint256 curveId = IMLOPredictionAdapterFacet(address(diamond))
            .createMLOCurve(MLOPredictionTypes.CreateMLOCurveParams({envelopeId: envelopeId, durationMinutes: 120}));
        vm.stopPrank();

        vm.warp(block.timestamp + 60 minutes);
        assertEq(CurveViewFacet(address(diamond)).getCurveInfo(curveId).currentPrice, 500_000_000);

        _updateMLOCurve(curveId, 50e18, 450_000_000, 550_000_000, true);
        assertEq(CurveViewFacet(address(diamond)).getCurveInfo(curveId).currentPrice, 450_000_000);
    }

    function test_RevertWhen_EnvelopeOutlivesMarket() public {
        QuoteEnvelopeTypes.CreateQuoteEnvelopeParams memory envelope = _defaultEnvelope();
        envelope.expiresAt = marketExpiry + 1;

        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSelector(Errors.ExpiryTooLate.selector, marketExpiry + 1, marketExpiry));
        IQuoteEnvelopeFacet(address(diamond)).createQuoteEnvelope(envelope);

        vm.expectRevert(abi.encodeWithSelector(Errors.ExpiryTooLate.selector, marketExpiry + 1, marketExpiry));
        IQuoteEnvelopeFacet(address(diamond)).previewQuoteEnvelopeRisk(envelope);
    }

    function test_RevertWhen_MLOCurveOutlivesEnvelope() public {
        QuoteEnvelopeTypes.CreateQuoteEnvelopeParams memory envelope = _defaultEnvelope();
        envelope.expiresAt = uint64(block.timestamp + 60 minutes);
        vm.prank(maker);
        uint256 envelopeId = IQuoteEnvelopeFacet(address(diamond)).createQuoteEnvelope(envelope);

        vm.prank(maker);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.ExpiryTooLate.selector, uint64(block.timestamp + 120 minutes), envelope.expiresAt
            )
        );
        IMLOPredictionAdapterFacet(address(diamond))
            .createMLOCurve(MLOPredictionTypes.CreateMLOCurveParams({envelopeId: envelopeId, durationMinutes: 120}));
    }

    function test_RevertWhen_MLOClockResetOutlivesEnvelope() public {
        uint256 curveId = _createMLOCurve(_createEnvelope());
        vm.warp(block.timestamp + 61 minutes);
        MLOPredictionTypes.UpdateMLOCurveParams memory update =
            _mloUpdateParams(curveId, 50e18, FORTY_CENTS, FORTY_CENTS);
        uint256 envelopeId = IMLOPredictionAdapterFacet(address(diamond)).getMLOCurve(curveId).envelopeId;
        QuoteEnvelopeTypes.QuoteEnvelopeView memory envelope =
            IQuoteEnvelopeFacet(address(diamond)).getQuoteEnvelope(envelopeId);

        vm.prank(maker);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.ExpiryTooLate.selector, uint64(block.timestamp + 120 minutes), envelope.expiresAt
            )
        );
        IMLOPredictionAdapterFacet(address(diamond)).updateMLOCurveFromNow(update);
    }

    function test_RevertWhen_ExpiredMLOCurveIsUpdated() public {
        uint256 curveId = _createMLOCurve(_createEnvelope());
        vm.warp(block.timestamp + 120 minutes);
        MLOPredictionTypes.UpdateMLOCurveParams memory update =
            _mloUpdateParams(curveId, 20e18, FORTY_CENTS, FORTY_CENTS);

        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSelector(Errors.CurveExpired.selector, curveId));
        IMLOPredictionAdapterFacet(address(diamond)).updateMLOCurveFromNow(update);
    }

    function test_NonExecutableMLOUpdatesAreStrictlyReductionOnly() public {
        uint256 askCurveId = _createMLOCurve(_createEnvelope());
        uint256 bidCurveId = _createMLOCurve(_createBidEnvelopeForBook(yesBookId));
        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarketEarly(marketId, uint8(LibEveMarket.MarketOutcome.No));

        MLOPredictionTypes.UpdateMLOCurveParams memory reprice =
            _mloUpdateParams(askCurveId, 50e18, 450_000_000, 450_000_000);
        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSelector(Errors.MarketNotTrading.selector, marketId));
        IMLOPredictionAdapterFacet(address(diamond)).updateMLOCurve(reprice);

        MLOPredictionTypes.UpdateMLOCurveParams memory replenish =
            _mloUpdateParams(askCurveId, 60e18, FORTY_CENTS, FORTY_CENTS);
        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSelector(Errors.MarketNotTrading.selector, marketId));
        IMLOPredictionAdapterFacet(address(diamond)).updateMLOCurve(replenish);

        MLOPredictionTypes.UpdateMLOCurveParams memory reset =
            _mloUpdateParams(askCurveId, 20e18, FORTY_CENTS, FORTY_CENTS);
        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSelector(Errors.MarketNotTrading.selector, marketId));
        IMLOPredictionAdapterFacet(address(diamond)).updateMLOCurveFromNow(reset);

        _updateMLOCurve(askCurveId, 20e18, FORTY_CENTS, FORTY_CENTS, false);
        _updateMLOCurve(bidCurveId, 20e18, FORTY_CENTS, FORTY_CENTS, false);
        assertEq(IMLOPredictionAdapterFacet(address(diamond)).getMLOCurve(askCurveId).remainingVolume, 20e18);
        assertEq(IMLOPredictionAdapterFacet(address(diamond)).getMLOCurve(bidCurveId).remainingVolume, 20e18);

        vm.prank(maker);
        IMLOPredictionAdapterFacet(address(diamond)).cancelMLOCurve(askCurveId);
        vm.prank(maker);
        IMLOPredictionAdapterFacet(address(diamond)).cancelMLOCurve(bidCurveId);
        assertEq(_seniorBucket(bucketId).reservedCapital, 0);
    }

    function test_NonExecutableMLOUpdateBatchRevertsAtomically() public {
        uint256 firstCurveId = _createMLOCurve(_createEnvelope());
        uint256 secondCurveId = _createMLOCurve(_createEnvelope());
        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarketEarly(marketId, uint8(LibEveMarket.MarketOutcome.No));

        MLOPredictionTypes.UpdateMLOCurveParams[] memory updates = new MLOPredictionTypes.UpdateMLOCurveParams[](2);
        updates[0] = _mloUpdateParams(firstCurveId, 20e18, FORTY_CENTS, FORTY_CENTS);
        updates[1] = _mloUpdateParams(secondCurveId, 20e18, 450_000_000, 450_000_000);

        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSelector(Errors.MarketNotTrading.selector, marketId));
        IMLOPredictionAdapterFacet(address(diamond)).updateMLOCurvesBatch(updates);

        assertEq(IMLOPredictionAdapterFacet(address(diamond)).getMLOCurve(firstCurveId).remainingVolume, 50e18);
        assertEq(IMLOPredictionAdapterFacet(address(diamond)).getMLOCurve(secondCurveId).remainingVolume, 50e18);
    }

    function test_MLOUpdateBatchIsCheaperThanSeparateUpdates() public {
        uint256[] memory curveIds = new uint256[](4);
        for (uint256 index; index < curveIds.length; ++index) {
            curveIds[index] = _createMLOCurve(_createEnvelope());
        }
        MLOPredictionTypes.UpdateMLOCurveParams[] memory updates = _mloUpdates(curveIds, 50e18);
        uint256 snapshotId = vm.snapshotState();

        uint256 separateGas;
        for (uint256 index; index < updates.length; ++index) {
            vm.prank(maker);
            IMLOPredictionAdapterFacet(address(diamond)).updateMLOCurve(updates[index]);
            separateGas += vm.lastCallGas().gasTotalUsed;
        }

        assertTrue(vm.revertToState(snapshotId));
        vm.prank(maker);
        uint32[] memory generations = IMLOPredictionAdapterFacet(address(diamond)).updateMLOCurvesBatch(updates);
        uint256 batchGas = vm.lastCallGas().gasTotalUsed;

        assertEq(generations.length, updates.length);
        assertLt(batchGas, separateGas);
        emit log_named_uint("MLO four separate updates gas", separateGas);
        emit log_named_uint("MLO four-update batch gas", batchGas);
    }

    function test_MLORiskReductionBatchIsCheaperThanSeparateUpdates() public {
        uint256[] memory curveIds = new uint256[](4);
        for (uint256 index; index < curveIds.length; ++index) {
            curveIds[index] = _createMLOCurve(_createEnvelope());
        }
        MLOPredictionTypes.UpdateMLOCurveParams[] memory updates = _mloUpdates(curveIds, 20e18);
        uint256 snapshotId = vm.snapshotState();

        uint256 separateGas;
        for (uint256 index; index < updates.length; ++index) {
            vm.prank(maker);
            IMLOPredictionAdapterFacet(address(diamond)).updateMLOCurve(updates[index]);
            separateGas += vm.lastCallGas().gasTotalUsed;
        }

        assertTrue(vm.revertToState(snapshotId));
        vm.prank(maker);
        IMLOPredictionAdapterFacet(address(diamond)).updateMLOCurvesBatch(updates);
        uint256 batchGas = vm.lastCallGas().gasTotalUsed;

        assertEq(_seniorBucket(bucketId).reservedCapital, 48e18);
        assertEq(
            IMLOPredictionAdapterFacet(address(diamond)).getMLOScenarioExposure(bucketId).initialRequirement, 48e18
        );
        assertLt(batchGas, separateGas);
        emit log_named_uint("MLO four separate reductions gas", separateGas);
        emit log_named_uint("MLO four-reduction batch gas", batchGas);
    }

    function test_MLOUpdateGasProfile() public {
        uint256 curveId = _createMLOCurve(_createEnvelope());
        uint256 snapshotId = vm.snapshotState();

        _updateMLOCurve(curveId, 50e18, 450_000_000, 450_000_000, false);
        uint256 priceOnlyGas = vm.lastCallGas().gasTotalUsed;

        assertTrue(vm.revertToState(snapshotId));
        _updateMLOCurve(curveId, 20e18, FORTY_CENTS, FORTY_CENTS, false);
        uint256 reductionGas = vm.lastCallGas().gasTotalUsed;
        _updateMLOCurve(curveId, 50e18, FORTY_CENTS, FORTY_CENTS, false);
        uint256 increaseGas = vm.lastCallGas().gasTotalUsed;

        assertGt(priceOnlyGas, 0);
        assertGt(reductionGas, priceOnlyGas);
        assertGt(increaseGas, reductionGas);
        emit log_named_uint("MLO price-only update gas", priceOnlyGas);
        emit log_named_uint("MLO risk-reducing update gas", reductionGas);
        emit log_named_uint("MLO risk-increasing update gas", increaseGas);
    }

    function test_BoundEnvelopeRejectsDirectUpdate() public {
        uint256 envelopeId = _createEnvelope();
        uint256 curveId = _createMLOCurve(envelopeId);
        vm.expectRevert(abi.encodeWithSelector(Errors.QuoteEnvelopeBoundToAdapterCurve.selector, envelopeId, curveId));
        vm.prank(maker);
        IQuoteEnvelopeFacet(address(diamond))
            .updateQuoteEnvelope(
                envelopeId,
                QuoteEnvelopeTypes.QuoteEnvelopeUpdate({volume: 20e18, startPrice: FORTY_CENTS, endPrice: FORTY_CENTS})
            );
    }

    function testFuzz_MLOUpdateKeepsBackingAndRiskAligned(uint256 volumeSeed) public {
        uint128 volume = uint128(bound(volumeSeed, 0, ONE_HUNDRED_SHARES));
        uint256 curveId = _createMLOCurve(_createEnvelope());

        _updateMLOCurve(curveId, volume, FORTY_CENTS, FORTY_CENTS, false);

        uint256 netSenior = uint256(volume) * 6 / 10;
        _assertMLOReservation(curveId, volume, 0, netSenior, netSenior);
    }

    function test_MLOPhaseFourFacetsRemainDeployable() public {
        uint256 adapterSize = address(new MLOPredictionAdapterFacet()).code.length;
        uint256 curveSize = address(new MLOPredictionCurveFacet()).code.length;
        uint256 postSize = address(new MLOPredictionPostFacet()).code.length;
        uint256 updateSize = address(new MLOPredictionUpdateFacet()).code.length;
        uint256 tradeSize = address(new MLOPredictionTradeFacet()).code.length;
        uint256 askRouteSize = address(new MLOPredictionAskRouteFacet()).code.length;
        emit log_named_uint("MLO adapter facet size", adapterSize);
        emit log_named_uint("MLO curve facet size", curveSize);
        emit log_named_uint("MLO post facet size", postSize);
        emit log_named_uint("MLO update facet size", updateSize);
        emit log_named_uint("MLO trade facet size", tradeSize);
        emit log_named_uint("MLO ask route facet size", askRouteSize);
        assertLe(adapterSize, EIP170_MAX_CODE_SIZE);
        assertLe(curveSize, EIP170_MAX_CODE_SIZE);
        assertLe(postSize, EIP170_MAX_CODE_SIZE);
        assertLe(updateSize, EIP170_MAX_CODE_SIZE);
        assertLe(tradeSize, EIP170_MAX_CODE_SIZE);
        assertLe(askRouteSize, EIP170_MAX_CODE_SIZE);
        assertLe(address(new MLOPredictionBidTradeFacet()).code.length, EIP170_MAX_CODE_SIZE);
        assertLe(address(new MLOPredictionSettlementFacet()).code.length, EIP170_MAX_CODE_SIZE);
        assertLe(address(new MLOPredictionRecoveryFacet()).code.length, EIP170_MAX_CODE_SIZE);
        assertLe(address(new TradeRouterBookFacet()).code.length, EIP170_MAX_CODE_SIZE);
        assertLe(address(new TradeRouterBookSellFacet()).code.length, EIP170_MAX_CODE_SIZE);
    }

    function test_RevertWhen_FeeChargingCollateralShortsMLOAskFunding() public {
        uint256 curveId = _createMLOCurve(_createEnvelope());
        (uint32 generation, bytes32 commitment) = CurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        collateral.setTransferFeeBps(100);

        vm.startPrank(taker);
        collateral.approve(address(diamond), 25e18);
        vm.expectRevert(
            abi.encodeWithSelector(IMLOPredictionAdapterFacet.MLOCollateralNonExactTransfer.selector, 20e18, 19.8e18)
        );
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

        assertEq(IMLOPredictionAdapterFacet(address(diamond)).getMLOCurve(curveId).remainingVolume, 50e18);
    }

    function test_MLORecoveryConfigRequiresOwnerAndValidBounds() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.NotContractOwner.selector, taker));
        vm.prank(taker);
        IMLOPredictionAdapterFacet(address(diamond)).setMLORecoveryConfig(address(insuranceFund), 5_000, 32);

        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(IMLOPredictionAdapterFacet.InvalidMLOFundingSplit.selector, 10_001));
        IMLOPredictionAdapterFacet(address(diamond)).setMLORecoveryConfig(address(insuranceFund), 10_001, 32);

        vm.expectRevert(abi.encodeWithSelector(IMLOPredictionAdapterFacet.MLOCleanupBatchTooLarge.selector, 65, 64));
        IMLOPredictionAdapterFacet(address(diamond)).setMLORecoveryConfig(address(insuranceFund), 5_000, 65);

        MLOInsuranceFund wrongAssetFund = new MLOInsuranceFund(address(usdc), address(diamond), address(diamond));
        vm.expectRevert(
            abi.encodeWithSelector(IMLOPredictionAdapterFacet.InvalidMLOInsuranceFund.selector, address(wrongAssetFund))
        );
        IMLOPredictionAdapterFacet(address(diamond)).setMLORecoveryConfig(address(wrongAssetFund), 5_000, 32);
        vm.stopPrank();
    }

    function test_RevertWhen_InsuranceAuthorityDriftsBeforeMLOPost() public {
        uint256 envelopeId = _createEnvelope();
        vm.prank(owner);
        insuranceFund.setRiskManager(address(negRiskAdapter));

        vm.expectRevert(
            abi.encodeWithSelector(IMLOPredictionAdapterFacet.InvalidMLOInsuranceFund.selector, address(insuranceFund))
        );
        _createMLOCurve(envelopeId);
    }

    function test_RevertWhen_CanonicalCoreBindingIsUnsetBeforeMLOPost() public {
        uint256 envelopeId = _createEnvelope();
        ITestStateFacet(address(diamond)).setStaticsDollarCoreFixture(address(0));

        vm.expectRevert(
            abi.encodeWithSelector(IMLOPredictionAdapterFacet.InvalidMLOCollateral.selector, address(collateral))
        );
        _createMLOCurve(envelopeId);
    }

    function test_FinalizedGovernanceDelaysRecoveryConfiguration() public {
        vm.prank(owner);
        DiamondCutFacet(address(diamond)).finalizeGovernanceDelay(owner);
        bytes memory callData = abi.encodeCall(
            IMLOPredictionAdapterFacet.setMLORecoveryConfig, (address(insuranceFund), uint16(6_000), uint16(32))
        );
        bytes32 operationId = DiamondCutFacet(address(diamond)).governanceOperationId(callData);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Errors.GovernanceOperationNotScheduled.selector, operationId));
        IMLOPredictionAdapterFacet(address(diamond)).setMLORecoveryConfig(address(insuranceFund), 6_000, 32);

        vm.prank(owner);
        (, uint64 readyAt) = DiamondCutFacet(address(diamond)).scheduleGovernanceOperation(callData);
        vm.warp(readyAt);
        vm.prank(owner);
        IMLOPredictionAdapterFacet(address(diamond)).setMLORecoveryConfig(address(insuranceFund), 6_000, 32);
        assertEq(IMLOPredictionAdapterFacet(address(diamond)).mloRecoveryConfig().seniorFundingBps, 6_000);
    }

    function test_DirectMLOAskFillRoutesNonzeroFeeThroughSettlementHelper() public {
        vm.prank(owner);
        ITestStateFacet(address(diamond)).setOrderbookFeeConfigFixture(100, 0, 0, 10_000, 0);
        (marketId,) = _createMarketFixture("Does the MLO settlement helper route fees?", marketExpiry);
        ITestStateFacet(address(diamond)).materializeMarketSideBookFixture(marketId, true);
        ITestStateFacet(address(diamond)).materializeMarketSideBookFixture(marketId, false);
        yesBookId = LibCLOBBook.marketBookId(marketId, true);
        noBookId = LibCLOBBook.marketBookId(marketId, false);
        _depositAndAllocate(maker, 100e18);
        uint256 treasuryBefore = collateral.balanceOf(treasury);

        MLOPredictionTypes.MLOAskFillResult memory result = _fillDefaultMLOAsk();

        assertGt(result.fill.feePaid, 0);
        assertEq(collateral.balanceOf(treasury), treasuryBefore + result.fill.feePaid);
    }

    function test_FullPriceAtomicMLOAskNeedsNoSeniorCapital() public {
        QuoteEnvelopeTypes.CreateQuoteEnvelopeParams memory params = _defaultEnvelope();
        params.maxVolume = 1;
        params.initialVolume = 1;
        params.minPrice = PRICE_DENOMINATOR;
        params.maxPrice = PRICE_DENOMINATOR;
        params.initialStartPrice = PRICE_DENOMINATOR;
        params.initialEndPrice = PRICE_DENOMINATOR;

        vm.prank(maker);
        uint256 envelopeId = IQuoteEnvelopeFacet(address(diamond)).createQuoteEnvelope(params);
        uint256 curveId = _createMLOCurve(envelopeId);
        assertEq(IMLOPredictionAdapterFacet(address(diamond)).getMLOCurve(curveId).seniorReserved, 0);
        assertEq(_seniorBucket(bucketId).reservedCapital, 0);

        MLOPredictionTypes.MLOAskFillResult memory fill = _fillCurve(curveId, 1, 1);
        assertEq(fill.fill.sharesOut, 1);
        assertEq(fill.fill.collateralUsed, 1);
        assertEq(fill.seniorDeployed, 0);
        assertEq(fill.seniorReleased, 0);
        assertEq(fill.retainedInventory, 1);
        assertEq(_seniorBucket(bucketId).activeExposure, 0);
        assertEq(conditionalTokens.balanceOf(taker, _yesPositionId()), 1);
    }

    function test_FragmentedMLOAskFillsConserveFundingAndReleaseSurplus() public {
        uint256 curveId = _createMLOCurve(_createEnvelopeWithVolumes(yesBookId, 5, 5));
        assertEq(IMLOPredictionAdapterFacet(address(diamond)).getMLOCurve(curveId).seniorReserved, 3);

        uint256 totalGross;
        uint256 totalSeniorDeployed;
        uint256 totalSeniorReleased;
        uint256 totalShares;
        for (uint256 index; index < 3; ++index) {
            MLOPredictionTypes.MLOAskFillResult memory fill = _fillCurve(curveId, 1, 1);
            totalGross += fill.fill.collateralUsed - fill.fill.feePaid;
            totalSeniorDeployed += fill.seniorDeployed;
            totalSeniorReleased += fill.seniorReleased;
            totalShares += fill.fill.sharesOut;
        }

        assertEq(totalShares, 5);
        assertEq(totalGross, 3);
        assertEq(totalSeniorDeployed, 2);
        assertEq(totalSeniorReleased, 1);
        assertEq(totalGross + totalSeniorDeployed, totalShares);
        assertEq(_seniorBucket(bucketId).activeExposure, 2);
        assertEq(_seniorBucket(bucketId).reservedCapital, 0);
        assertEq(conditionalTokens.balanceOf(taker, _yesPositionId()), 5);
    }

    function test_NearOneMLOAskReservesOnlyNetSeniorDeficit() public {
        uint128 volume = 50e18;
        uint128 price = PRICE_DENOMINATOR - 1;
        QuoteEnvelopeTypes.CreateQuoteEnvelopeParams memory params = _defaultEnvelope();
        params.maxVolume = volume;
        params.initialVolume = volume;
        params.minPrice = price;
        params.maxPrice = price;
        params.initialStartPrice = price;
        params.initialEndPrice = price;
        uint256 availableBefore = _seniorState().availableCapital;

        vm.prank(maker);
        uint256 envelopeId = IQuoteEnvelopeFacet(address(diamond)).createQuoteEnvelope(params);
        uint256 curveId = _createMLOCurve(envelopeId);

        uint256 expectedSenior = 50e9;
        assertEq(IMLOPredictionAdapterFacet(address(diamond)).getMLOCurve(curveId).seniorReserved, expectedSenior);
        assertEq(_seniorBucket(bucketId).reservedCapital, expectedSenior);
        assertEq(availableBefore - _seniorState().availableCapital, expectedSenior);
    }

    function test_DirectMLOBidFillPaysSellerAndReceivesInventory() public {
        _mintCompleteSet(taker, 50e18);
        uint256 curveId = _createMLOCurve(_createBidEnvelopeForBook(yesBookId));
        (uint32 generation, bytes32 commitment) = CurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        uint256 sellerBalanceBefore = collateral.balanceOf(taker);

        vm.startPrank(taker);
        conditionalTokens.setApprovalForAll(address(diamond), true);
        MLOPredictionTypes.MLOBidFillResult memory result = IMLOPredictionAdapterFacet(address(diamond))
            .fillMLOBidCurve(
                MLOPredictionTypes.FillMLOBidCurveParams({
                    curveId: curveId,
                    sharesIn: 50e18,
                    minCollateralOut: 20e18,
                    expectedGeneration: generation,
                    expectedCommitment: commitment,
                    receiver: taker
                })
            );
        vm.stopPrank();

        assertEq(result.fill.baseSold, 50e18);
        assertEq(result.fill.quoteOut, 20e18);
        assertEq(result.seniorDeployed, 20e18);
        assertEq(result.seniorReleased, 10e18);
        assertEq(collateral.balanceOf(taker), sellerBalanceBefore + 20e18);

        MLOPredictionTypes.MLOInventoryView memory inventory =
            IMLOPredictionAdapterFacet(address(diamond)).getMLOInventory(bucketId, marketId);
        assertEq(inventory.inventory[0], 50e18);
        assertEq(inventory.seniorDebt, 20e18);
        assertEq(inventory.seniorReserved, 0);
        assertEq(conditionalTokens.balanceOf(inventory.vault, _yesPositionId()), 50e18);
        assertEq(_seniorBucket(bucketId).activeExposure, 20e18);
        assertEq(_seniorBucket(bucketId).reservedCapital, 0);

        vm.prank(maker);
        IMLOPredictionAdapterFacet(address(diamond)).cancelMLOCurve(curveId);
        assertEq(_seniorBucket(bucketId).reservedCapital, 0);
    }

    function test_RevertWhen_FeeChargingCollateralShortsMLOBidReceiver() public {
        _mintCompleteSet(taker, 50e18);
        uint256 curveId = _createMLOCurve(_createBidEnvelopeForBook(yesBookId));
        (uint32 generation, bytes32 commitment) = CurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        collateral.setTransferFeeBps(100);

        vm.startPrank(taker);
        conditionalTokens.setApprovalForAll(address(diamond), true);
        vm.expectRevert(
            abi.encodeWithSelector(IMLOPredictionAdapterFacet.MLOCollateralNonExactTransfer.selector, 20e18, 19.8e18)
        );
        IMLOPredictionAdapterFacet(address(diamond))
            .fillMLOBidCurve(
                MLOPredictionTypes.FillMLOBidCurveParams({
                    curveId: curveId,
                    sharesIn: 50e18,
                    minCollateralOut: 20e18,
                    expectedGeneration: generation,
                    expectedCommitment: commitment,
                    receiver: taker
                })
            );
        vm.stopPrank();

        assertEq(conditionalTokens.balanceOf(taker, _yesPositionId()), 50e18);
        assertEq(IMLOPredictionAdapterFacet(address(diamond)).getMLOCurve(curveId).remainingVolume, 50e18);
    }

    function test_DirectMLOBidFillRoutesNonzeroFeeThroughSettlementHelper() public {
        vm.prank(owner);
        ITestStateFacet(address(diamond)).setOrderbookFeeConfigFixture(100, 0, 0, 10_000, 0);
        (marketId,) = _createMarketFixture("Does the MLO bid settlement route fees?", marketExpiry);
        ITestStateFacet(address(diamond)).materializeMarketSideBookFixture(marketId, true);
        ITestStateFacet(address(diamond)).materializeMarketSideBookFixture(marketId, false);
        yesBookId = LibCLOBBook.marketBookId(marketId, true);
        noBookId = LibCLOBBook.marketBookId(marketId, false);
        _depositAndAllocate(maker, 100e18);
        _mintCompleteSet(taker, 50e18);
        uint256 curveId = _createMLOCurve(_createBidEnvelopeForBook(yesBookId));
        (uint32 generation, bytes32 commitment) = CurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        uint256 treasuryBefore = collateral.balanceOf(treasury);

        vm.startPrank(taker);
        conditionalTokens.setApprovalForAll(address(diamond), true);
        MLOPredictionTypes.MLOBidFillResult memory result = IMLOPredictionAdapterFacet(address(diamond))
            .fillMLOBidCurve(
                MLOPredictionTypes.FillMLOBidCurveParams({
                    curveId: curveId,
                    sharesIn: 50e18,
                    minCollateralOut: 1,
                    expectedGeneration: generation,
                    expectedCommitment: commitment,
                    receiver: taker
                })
            );
        vm.stopPrank();

        assertGt(result.fill.feePaid, 0);
        assertEq(collateral.balanceOf(treasury), treasuryBefore + result.fill.feePaid);
        assertEq(result.fill.quoteOut + result.fill.feePaid, result.seniorDeployed);
    }

    function test_BookRoutesDispatchMLOAskAndBidCurves() public {
        uint256 askCurveId = _createMLOCurve(_createEnvelope());
        (uint32 askGeneration, bytes32 askCommitment) = CurveViewFacet(address(diamond)).getCurveCommitment(askCurveId);
        vm.startPrank(taker);
        collateral.approve(address(diamond), 25e18);
        CurveCLOBTypes.FillBestResult memory buy = IBookTradeFacet(address(diamond))
            .fillBookBest(
                CurveCLOBTypes.FillBookParams({
                    bookId: yesBookId,
                    maxQuoteIn: 25e18,
                    minBaseOut: 50e18,
                    maxAveragePrice: FORTY_CENTS,
                    curveIds: _singleUint(askCurveId),
                    expectedGenerations: _singleUint32(askGeneration),
                    expectedCommitments: _singleBytes32(askCommitment),
                    payer: address(0),
                    receiver: taker
                })
            );
        vm.stopPrank();
        assertEq(buy.sharesOut, 50e18);

        uint256 bidCurveId = _createMLOCurve(_createBidEnvelopeForBook(yesBookId));
        (uint32 bidGeneration, bytes32 bidCommitment) = CurveViewFacet(address(diamond)).getCurveCommitment(bidCurveId);
        vm.startPrank(taker);
        conditionalTokens.setApprovalForAll(address(diamond), true);
        CurveCLOBTypes.SellBookResult memory sell = IBookTradeFacet(address(diamond))
            .sellBookBest(
                CurveCLOBTypes.SellBookParams({
                    bookId: yesBookId,
                    maxBaseIn: 50e18,
                    minQuoteOut: 20e18,
                    curveIds: _singleUint(bidCurveId),
                    expectedGenerations: _singleUint32(bidGeneration),
                    expectedCommitments: _singleBytes32(bidCommitment),
                    receiver: taker
                })
            );
        vm.stopPrank();
        assertEq(sell.baseSold, 50e18);
        assertEq(sell.quoteOut, 20e18);
    }

    function test_BookRouteLazilyCleansExpiredMLOCurve() public {
        uint256 curveId = _createMLOCurve(_createEnvelope());
        (uint32 generation, bytes32 commitment) = CurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        assertGt(_seniorBucket(bucketId).reservedCapital, 0);

        vm.warp(block.timestamp + 2 hours);
        vm.prank(taker);
        CurveCLOBTypes.FillBestResult memory result = IBookTradeFacet(address(diamond))
            .fillBookBest(
                CurveCLOBTypes.FillBookParams({
                    bookId: yesBookId,
                    maxQuoteIn: 25e18,
                    minBaseOut: 0,
                    maxAveragePrice: PRICE_DENOMINATOR,
                    curveIds: _singleUint(curveId),
                    expectedGenerations: _singleUint32(generation),
                    expectedCommitments: _singleBytes32(commitment),
                    payer: address(0),
                    receiver: taker
                })
            );

        assertEq(result.sharesOut, 0);
        assertEq(result.unfilledCollateral, 25e18);
        assertEq(_seniorBucket(bucketId).reservedCapital, 0);
        assertFalse(IMLOPredictionAdapterFacet(address(diamond)).getMLOCurve(curveId).active);
    }

    function test_BookRoutePriceOrdersEscrowAndMLOAskCurves() public {
        _fundCollateral(maker, 20e6);
        _mintCompleteSet(maker, 20e18);
        vm.startPrank(maker);
        conditionalTokens.setApprovalForAll(address(diamond), true);
        uint256 escrowCurveId = IBookOrderFacet(address(diamond))
            .postBookCurve(yesBookId, LibEveMarket.CurveSide.ASK, 20e18, 300_000_000, 300_000_000, 120, 0, 0);
        vm.stopPrank();
        uint256 mloCurveId = _createMLOCurve(_createEnvelopeForBook(yesBookId));
        (uint32 escrowGeneration, bytes32 escrowCommitment) =
            CurveViewFacet(address(diamond)).getCurveCommitment(escrowCurveId);
        (uint32 mloGeneration, bytes32 mloCommitment) = CurveViewFacet(address(diamond)).getCurveCommitment(mloCurveId);

        uint256[] memory curveIds = new uint256[](2);
        curveIds[0] = mloCurveId;
        curveIds[1] = escrowCurveId;
        uint32[] memory generations = new uint32[](2);
        generations[0] = mloGeneration;
        generations[1] = escrowGeneration;
        bytes32[] memory commitments = new bytes32[](2);
        commitments[0] = mloCommitment;
        commitments[1] = escrowCommitment;

        vm.startPrank(taker);
        collateral.approve(address(diamond), 26e18);
        CurveCLOBTypes.FillBestResult memory result = ITradeRouterBook(address(diamond))
            .buyBookWithCollateral(
                CurveCLOBTypes.FillBookParams({
                    bookId: yesBookId,
                    maxQuoteIn: 26e18,
                    minBaseOut: 70e18,
                    maxAveragePrice: FORTY_CENTS,
                    curveIds: curveIds,
                    expectedGenerations: generations,
                    expectedCommitments: commitments,
                    payer: address(0),
                    receiver: taker
                })
            );
        vm.stopPrank();

        assertEq(result.sharesOut, 70e18);
        assertEq(result.collateralUsed, 26e18);
        assertEq(CurveViewFacet(address(diamond)).getCurveInfo(escrowCurveId).remainingVolume, 0);
        assertEq(CurveViewFacet(address(diamond)).getCurveInfo(mloCurveId).remainingVolume, 0);
        MLOPredictionTypes.MLOInventoryView memory inventory =
            IMLOPredictionAdapterFacet(address(diamond)).getMLOInventory(bucketId, marketId);
        assertEq(inventory.inventory[1], 50e18);
    }

    function test_DelayedMLOBidFillUsesEscrowedOutcomeAfterApprovalRevoked() public {
        _mintCompleteSet(taker, 50e18);
        uint256 curveId = _createMLOCurve(_createBidEnvelopeForBook(yesBookId));
        DelayedOrderTypes.DelayedOrderRoute memory route = _route(curveId);
        uint256 balanceBefore = collateral.balanceOf(taker);

        vm.startPrank(taker);
        conditionalTokens.setApprovalForAll(address(diamond), true);
        uint256 orderId = DelayedOrderFacet(address(diamond))
            .submitDelayedOrder(
                DelayedOrderTypes.SubmitDelayedOrderParams({
                    bookId: yesBookId,
                    kind: LibEveMarket.DelayedOrderKind.MarketSell,
                    amountIn: 50e18,
                    limitPrice: 0,
                    minOut: 20e18,
                    maxAveragePrice: 0,
                    curveIds: route.curveIds,
                    expectedGenerations: route.expectedGenerations,
                    expectedCommitments: route.expectedCommitments
                })
            );
        conditionalTokens.setApprovalForAll(address(diamond), false);
        vm.stopPrank();

        vm.roll(block.number + 1);
        DelayedOrderTypes.ProcessDelayedOrderResult memory processed =
            DelayedOrderFacet(address(diamond)).processDelayedOrders(yesBookId, 1, _singleRoute(route));

        assertEq(processed.processedCount, 1);
        assertEq(
            uint8(DelayedOrderFacet(address(diamond)).getDelayedOrder(orderId).status),
            uint8(LibEveMarket.DelayedOrderStatus.Filled)
        );
        assertEq(collateral.balanceOf(taker), balanceBefore + 20e18);
        MLOPredictionTypes.MLOInventoryView memory inventory =
            IMLOPredictionAdapterFacet(address(diamond)).getMLOInventory(bucketId, marketId);
        assertEq(conditionalTokens.balanceOf(inventory.vault, _yesPositionId()), 50e18);
    }

    function test_DelayedMLOBidCancelsAndCreditsBaseAfterGenerationChanges() public {
        _mintCompleteSet(taker, 50e18);
        uint256 envelopeId = _createBidEnvelopeForBook(yesBookId);
        uint256 curveId = _createMLOCurve(envelopeId);
        DelayedOrderTypes.DelayedOrderRoute memory staleRoute = _route(curveId);

        vm.startPrank(taker);
        conditionalTokens.setApprovalForAll(address(diamond), true);
        uint256 orderId = DelayedOrderFacet(address(diamond))
            .submitDelayedOrder(
                DelayedOrderTypes.SubmitDelayedOrderParams({
                    bookId: yesBookId,
                    kind: LibEveMarket.DelayedOrderKind.MarketSell,
                    amountIn: 50e18,
                    limitPrice: 0,
                    minOut: 1,
                    maxAveragePrice: 0,
                    curveIds: staleRoute.curveIds,
                    expectedGenerations: staleRoute.expectedGenerations,
                    expectedCommitments: staleRoute.expectedCommitments
                })
            );
        vm.stopPrank();

        QuoteEnvelopeTypes.QuoteEnvelopeView memory envelope =
            IQuoteEnvelopeFacet(address(diamond)).getQuoteEnvelope(envelopeId);
        vm.prank(maker);
        IMLOPredictionAdapterFacet(address(diamond))
            .updateMLOCurve(
                MLOPredictionTypes.UpdateMLOCurveParams({
                    curveId: curveId,
                    envelopeUpdate: QuoteEnvelopeTypes.QuoteEnvelopeUpdate({
                        volume: envelope.currentVolume,
                        startPrice: envelope.currentStartPrice,
                        endPrice: envelope.currentEndPrice
                    }),
                    expectedCurveGeneration: staleRoute.expectedGenerations[0],
                    expectedEnvelopeGeneration: envelope.generation
                })
            );

        vm.roll(block.number + 1);
        DelayedOrderTypes.ProcessDelayedOrderResult memory processed =
            DelayedOrderFacet(address(diamond)).processDelayedOrders(yesBookId, 1, _singleRoute(staleRoute));

        assertEq(processed.processedCount, 1);
        assertEq(
            uint8(DelayedOrderFacet(address(diamond)).getDelayedOrder(orderId).status),
            uint8(LibEveMarket.DelayedOrderStatus.Cancelled)
        );
        assertEq(
            DelayedOrderFacet(address(diamond))
            .getBaseCredit(
                taker, uint8(LibEveMarket.BookAssetType.ERC1155), address(conditionalTokens), _yesPositionId()
            )
            .withdrawable,
            50e18
        );
    }

    function test_NativeThreeOutcomeBidsAutoMergeCompleteSetAndRepaySenior() public {
        _activateNativeThreeOutcomeMarket();
        uint256[] memory positionIds = _mintNativeCompleteSet(taker, 50e18);
        vm.prank(taker);
        conditionalTokens.setApprovalForAll(address(diamond), true);

        for (uint8 outcome; outcome < 3; ++outcome) {
            bytes32 bookId = LibCLOBBook.multiOutcomeBookId(marketId, outcome);
            uint256 curveId = _createMLOCurve(_createBidEnvelopeForBook(bookId));
            (uint32 generation, bytes32 commitment) = CurveViewFacet(address(diamond)).getCurveCommitment(curveId);
            vm.startPrank(taker);
            IMLOPredictionAdapterFacet(address(diamond))
                .fillMLOBidCurve(
                    MLOPredictionTypes.FillMLOBidCurveParams({
                        curveId: curveId,
                        sharesIn: 50e18,
                        minCollateralOut: 20e18,
                        expectedGeneration: generation,
                        expectedCommitment: commitment,
                        receiver: taker
                    })
                );
            vm.stopPrank();
        }

        MLOPredictionTypes.MLOInventoryView memory inventory =
            IMLOPredictionAdapterFacet(address(diamond)).getMLOInventory(bucketId, marketId);
        assertEq(inventory.outcomeCount, 3);
        assertEq(inventory.inventory[0], 0);
        assertEq(inventory.inventory[1], 0);
        assertEq(inventory.inventory[2], 0);
        assertEq(inventory.seniorDebt, 10e18);
        assertEq(_seniorBucket(bucketId).activeExposure, 10e18);
        assertEq(conditionalTokens.balanceOf(inventory.vault, positionIds[2]), 0);
    }

    function test_NativeThreeOutcomeAskMintsSoldAndComplementaryPositions() public {
        _activateNativeThreeOutcomeMarket();
        uint256 curveId = _createMLOCurve(_createEnvelopeForBook(yesBookId));
        MLOPredictionTypes.MLOAskFillResult memory fill = _fillCurve(curveId, 25e18, 50e18);
        MLOPredictionTypes.MLOInventoryView memory inventory =
            IMLOPredictionAdapterFacet(address(diamond)).getMLOInventory(bucketId, marketId);
        uint256 soldPositionId = IMultiOutcomeOrderbookFacet(address(diamond)).getOutcomePositionId(marketId, 0);
        assertEq(fill.seniorDeployed, 30e18);
        assertEq(conditionalTokens.balanceOf(taker, soldPositionId), 50e18);
        assertEq(inventory.inventory[0], 0);
        assertEq(inventory.inventory[1], 50e18);
        assertEq(inventory.inventory[2], 50e18);
        assertEq(inventory.outcomeCount, 3);
    }

    function test_NativeSixteenOutcomeAskMintsEveryComplementaryPosition() public {
        _activateNativeMarket(16);
        uint256 curveId = _createMLOCurve(_createEnvelopeForBook(yesBookId));
        MLOPredictionTypes.MLOAskFillResult memory fill = _fillCurve(curveId, 25e18, 50e18);
        MLOPredictionTypes.MLOInventoryView memory inventory =
            IMLOPredictionAdapterFacet(address(diamond)).getMLOInventory(bucketId, marketId);

        assertEq(fill.seniorDeployed, 30e18);
        assertEq(inventory.outcomeCount, 16);
        assertEq(inventory.inventory[0], 0);
        for (uint8 outcome = 1; outcome < 16; ++outcome) {
            assertEq(inventory.inventory[outcome], 50e18);
        }
    }

    function test_NativeThreeOutcomeWinningSettlementRepaysDebtAndCreditsProfit() public {
        _activateNativeThreeOutcomeMarket();
        uint256 curveId = _createMLOCurve(_createEnvelopeForBook(yesBookId));
        _fillCurve(curveId, 25e18, 50e18);
        vm.prank(maker);
        IMLOPredictionAdapterFacet(address(diamond)).cancelMLOCurve(curveId);
        _resolveNativeMarket(1);

        MLOPredictionTypes.MLOInventorySettlement memory settlement =
            IMLOPredictionAdapterFacet(address(diamond)).settleMLOInventory(bucketId, marketId);
        assertEq(settlement.collateralOut, 50e18);
        assertEq(settlement.seniorRepaid, 30e18);
        assertEq(settlement.bucketProfit, 20e18);
        assertEq(_seniorBucket(bucketId).activeExposure, 0);
    }

    function test_NativeSettlementIgnoresDonatedVaultInventory() public {
        _activateNativeThreeOutcomeMarket();
        uint256 curveId = _createMLOCurve(_createEnvelopeForBook(yesBookId));
        _fillCurve(curveId, 25e18, 50e18);
        vm.prank(maker);
        IMLOPredictionAdapterFacet(address(diamond)).cancelMLOCurve(curveId);

        address vault = IMLOPredictionAdapterFacet(address(diamond)).getMLOInventory(bucketId, marketId).vault;
        address donor = makeAddr("inventory-donor");
        _fundCollateral(donor, 1e6);
        uint256[] memory donatedPositionIds = _mintNativeCompleteSet(donor, 1e18);
        vm.prank(donor);
        conditionalTokens.safeTransferFrom(donor, vault, donatedPositionIds[1], 1e18, "");

        _resolveNativeMarket(1);
        MLOPredictionTypes.MLOInventorySettlement memory settlement =
            IMLOPredictionAdapterFacet(address(diamond)).settleMLOInventory(bucketId, marketId);

        assertEq(settlement.collateralOut, 50e18);
        assertEq(settlement.seniorRepaid, 30e18);
        assertEq(settlement.bucketProfit, 20e18);
        assertEq(conditionalTokens.balanceOf(vault, donatedPositionIds[1]), 1e18);
    }

    function test_NativeThreeOutcomeInvalidSettlementUsesPerOutcomeFloor() public {
        _activateNativeThreeOutcomeMarket();
        uint256 curveId = _createMLOCurve(_createEnvelopeForBook(yesBookId));
        _fillCurve(curveId, 25e18, 50e18);
        vm.prank(maker);
        IMLOPredictionAdapterFacet(address(diamond)).cancelMLOCurve(curveId);
        _resolveNativeMarket(type(uint8).max);

        MLOPredictionTypes.MLOInventorySettlement memory settlement =
            IMLOPredictionAdapterFacet(address(diamond)).settleMLOInventory(bucketId, marketId);
        uint256 expectedPayout = uint256(50e18) / 3 + uint256(50e18) / 3;
        assertEq(settlement.collateralOut, expectedPayout);
        assertEq(settlement.seniorRepaid, 30e18);
        assertEq(settlement.bucketProfit, expectedPayout - 30e18);
    }

    function test_NativeBookConvenienceRoutersBuyAndSellMLOCurves() public {
        _activateNativeThreeOutcomeMarket();
        uint256 askCurveId = _createMLOCurve(_createEnvelopeForBook(yesBookId));
        (uint32 askGeneration, bytes32 askCommitment) = CurveViewFacet(address(diamond)).getCurveCommitment(askCurveId);
        vm.startPrank(taker);
        collateral.approve(address(diamond), 25e18);
        CurveCLOBTypes.FillBestResult memory bought = ITradeRouterBook(address(diamond))
            .buyBookWithCollateral(
                CurveCLOBTypes.FillBookParams({
                    bookId: yesBookId,
                    maxQuoteIn: 25e18,
                    minBaseOut: 50e18,
                    maxAveragePrice: FORTY_CENTS,
                    curveIds: _singleUint(askCurveId),
                    expectedGenerations: _singleUint32(askGeneration),
                    expectedCommitments: _singleBytes32(askCommitment),
                    payer: address(0),
                    receiver: taker
                })
            );
        vm.stopPrank();
        assertEq(bought.sharesOut, 50e18);

        uint256 bidCurveId = _createMLOCurve(_createBidEnvelopeForBook(yesBookId));
        (uint32 bidGeneration, bytes32 bidCommitment) = CurveViewFacet(address(diamond)).getCurveCommitment(bidCurveId);
        uint256 balanceBefore = collateral.balanceOf(taker);
        vm.startPrank(taker);
        conditionalTokens.setApprovalForAll(address(diamond), true);
        CurveCLOBTypes.SellBookResult memory sold = ITradeRouterBook(address(diamond))
            .sellBookWithCollateral(
                CurveCLOBTypes.SellBookParams({
                    bookId: yesBookId,
                    maxBaseIn: 50e18,
                    minQuoteOut: 20e18,
                    curveIds: _singleUint(bidCurveId),
                    expectedGenerations: _singleUint32(bidGeneration),
                    expectedCommitments: _singleBytes32(bidCommitment),
                    receiver: taker
                })
            );
        vm.stopPrank();
        assertEq(sold.quoteOut, 20e18);
        assertEq(collateral.balanceOf(taker), balanceBefore + 20e18);
    }

    function test_RevertWhen_FeeChargingCollateralShortsMLOBookSellReceiver() public {
        _mintCompleteSet(taker, 50e18);
        uint256 bidCurveId = _createMLOCurve(_createBidEnvelopeForBook(yesBookId));
        (uint32 bidGeneration, bytes32 bidCommitment) = CurveViewFacet(address(diamond)).getCurveCommitment(bidCurveId);
        collateral.setTransferFeeBps(100);
        vm.startPrank(taker);
        conditionalTokens.setApprovalForAll(address(diamond), true);
        vm.expectRevert(ITradeRouter.NonExactRouterTransfer.selector);
        ITradeRouterBook(address(diamond))
            .sellBookWithCollateral(
                CurveCLOBTypes.SellBookParams({
                    bookId: yesBookId,
                    maxBaseIn: 50e18,
                    minQuoteOut: 20e18,
                    curveIds: _singleUint(bidCurveId),
                    expectedGenerations: _singleUint32(bidGeneration),
                    expectedCommitments: _singleBytes32(bidCommitment),
                    receiver: taker
                })
            );
        vm.stopPrank();

        assertEq(conditionalTokens.balanceOf(taker, _yesPositionId()), 50e18);
    }

    function test_MLOFillConsumesPreReservedRiskWithoutSecondGrossMarginCheck() public {
        address tightMaker = makeAddr("tight-maker");
        _fundCollateral(tightMaker, 60e6);
        bytes32 riskDomain = IMarginAccountFacet(address(diamond)).riskDomainForMarket(marketId);
        vm.startPrank(tightMaker);
        collateral.approve(address(diamond), 60e18);
        IMarginAccountFacet(address(diamond)).depositMargin(60e18, tightMaker);
        bytes32 tightBucketId = IMarginAccountFacet(address(diamond)).allocateBucketMargin(riskDomain, 60e18, 1);
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
                    expiresAt: uint64(block.timestamp + 3 hours)
                })
            );
        uint256 curveId = IMLOPredictionAdapterFacet(address(diamond))
            .createMLOCurve(MLOPredictionTypes.CreateMLOCurveParams({envelopeId: envelopeId, durationMinutes: 120}));
        vm.stopPrank();

        (uint32 generation, bytes32 commitment) = CurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        vm.startPrank(taker);
        collateral.approve(address(diamond), 25e18);
        MLOPredictionTypes.MLOAskFillResult memory result = IMLOPredictionAdapterFacet(address(diamond))
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
        assertEq(bucket.openOrderRisk, 0);
        assertEq(bucket.positionRisk, 30e18);
        assertEq(bucket.vaultDebt, 30e18);
    }

    function test_DelayedMLOAskFillUsesSameSettlementPath() public {
        uint256 envelopeId = _createEnvelope();
        uint256 curveId = _createMLOCurve(envelopeId);
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
        assertEq(inventory.inventory[1], conditionalTokens.balanceOf(taker, _yesPositionId()));
    }

    function test_DelayedMLOAskFillUsesEscrowAfterTakerApprovalRevoked() public {
        uint256 envelopeId = _createEnvelope();
        uint256 curveId = _createMLOCurve(envelopeId);
        DelayedOrderTypes.DelayedOrderRoute memory route = _route(curveId);

        _submitMarketBuy(yesBookId, 20e18, route);
        vm.prank(taker);
        collateral.approve(address(diamond), 0);

        vm.roll(block.number + 1);
        DelayedOrderTypes.ProcessDelayedOrderResult memory processed =
            DelayedOrderFacet(address(diamond)).processDelayedOrders(yesBookId, 1, _singleRoute(route));

        assertEq(processed.processedCount, 1);
        assertGt(conditionalTokens.balanceOf(taker, _yesPositionId()), 0);
        assertEq(collateral.allowance(taker, address(diamond)), 0);
    }

    function test_RevertWhen_DiamondCallerCannotBypassMLOFillFunding() public {
        uint256 envelopeId = _createEnvelope();
        uint256 curveId = _createMLOCurve(envelopeId);
        (uint32 generation, bytes32 commitment) = CurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        _fundCollateral(address(diamond), 25e6);

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
        uint256 curveId = _createMLOCurve(envelopeId);
        DelayedOrderTypes.DelayedOrderRoute memory route = _route(curveId);
        uint256 orderId = _submitMarketBuy(yesBookId, 20e18, route);

        IMarginAccountFacet(address(diamond)).recordBucketLoss(bucketId, 272e18);
        vm.roll(block.number + 1);
        DelayedOrderTypes.ProcessDelayedOrderResult memory processed =
            DelayedOrderFacet(address(diamond)).processDelayedOrders(yesBookId, 1, _singleRoute(route));

        assertEq(processed.processedCount, 1);
        assertEq(
            uint8(DelayedOrderFacet(address(diamond)).getDelayedOrder(orderId).status),
            uint8(LibEveMarket.DelayedOrderStatus.Cancelled)
        );
        assertEq(DelayedOrderFacet(address(diamond)).getQuoteCredit(taker, address(collateral)).withdrawable, 20e18);
    }

    function test_MLOCurvesUseDiamondSeniorCapital() public {
        uint256 envelopeId = _createEnvelope();
        uint256 curveId = _createMLOCurve(envelopeId);
        (uint32 generation, bytes32 commitment) = CurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        vm.startPrank(taker);
        collateral.approve(address(diamond), 25e18);
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

        assertGt(_seniorBucket(bucketId).activeExposure, 0);
    }

    function test_SettleWinningMLOInventoryRepaysSeniorAndCreditsBucketProfit() public {
        MLOPredictionTypes.MLOAskFillResult memory fill = _fillDefaultMLOAsk();
        uint256 seniorDebt = fill.seniorDeployed - fill.seniorRepaid;

        _resolveMarket(uint8(LibEveMarket.MarketOutcome.No));
        MLOPredictionTypes.MLOInventorySettlement memory settlement =
            IMLOPredictionAdapterFacet(address(diamond)).settleMLOInventory(bucketId, marketId);

        assertEq(settlement.seniorRepaid, seniorDebt);
        assertEq(settlement.seniorLoss, 0);
        assertEq(settlement.bucketProfit, fill.fill.sharesOut - seniorDebt);
        assertEq(_seniorBucket(bucketId).activeExposure, 0);

        MarginTypes.MarginBucket memory bucket = IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId);
        assertEq(bucket.vaultDebt, 0);
        assertEq(bucket.positionRisk, 0);
        assertEq(bucket.realizedProfits, settlement.bucketProfit);
        MLOPredictionTypes.MLOInventoryView memory inventory =
            IMLOPredictionAdapterFacet(address(diamond)).getMLOInventory(bucketId, marketId);
        assertEq(inventory.vault, address(0));
        assertEq(inventory.inventory[1], 0);

        uint256 grossRelease = bucket.marginAllocated;
        uint256 expectedInsuranceShare = settlement.bucketProfit * 500 / 10_000;
        uint256 expectedNonMaker = settlement.bucketProfit * 2_500 / 10_000;
        uint256 expectedSeniorShare = expectedNonMaker - expectedInsuranceShare;
        MLOProfitShareTypes.BucketRewardView memory reward =
            IMLOProfitShareFacet(address(diamond)).mloBucketProfitReward(bucketId, creator);
        assertEq(reward.accountClaimable, expectedSeniorShare);
        assertEq(insuranceFund.totalProfitShare(), expectedInsuranceShare);
        vm.prank(maker);
        MLOProfitShareTypes.ProfitRelease memory release =
            IMarginAccountFacet(address(diamond)).releaseBucketMargin(bucketId, grossRelease);

        assertEq(release.profitRecognized, settlement.bucketProfit - expectedNonMaker);
        assertEq(release.seniorShare, 0);
        assertEq(release.insuranceShare, 0);
        vm.prank(creator);
        assertEq(
            IMLOProfitShareFacet(address(diamond)).claimMLOBucketProfitReward(bucketId, creator), expectedSeniorShare
        );
        assertEq(IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId).marginAllocated, 0);
    }

    function test_WinningSettlementPaysPrincipalThenFundingThenProfit() public {
        MLOPredictionTypes.MLOAskFillResult memory fill = _fillDefaultMLOAsk();
        uint256 seniorDebt = fill.seniorDeployed - fill.seniorRepaid;
        bytes32 riskDomain = IMarginAccountFacet(address(diamond)).riskDomainForMarket(marketId);
        vm.prank(owner);
        IMarginAccountFacet(address(diamond))
            .setRiskDomainFundingConfig(riskDomain, MarginTypes.FundingMode.BorrowRate, 1e15);
        vm.warp(block.timestamp + 10);
        uint256 expectedFunding = seniorDebt * 1e15 * 10 / 1e18;

        _resolveMarket(uint8(LibEveMarket.MarketOutcome.No));
        MLOPredictionTypes.MLOInventorySettlement memory settlement =
            IMLOPredictionAdapterFacet(address(diamond)).settleMLOInventory(bucketId, marketId);

        assertEq(settlement.seniorRepaid, seniorDebt);
        assertEq(settlement.fundingPaid, expectedFunding);
        assertEq(settlement.fundingMarginUsed, 0);
        assertEq(settlement.bucketProfit, fill.fill.sharesOut - seniorDebt - expectedFunding);
        assertEq(_seniorBucket(bucketId).fundingRevenue, expectedFunding / 2);
        assertEq(insuranceFund.bucketFundingRevenue(bucketId), expectedFunding - expectedFunding / 2);
        MarginTypes.MarginBucket memory bucket = IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId);
        assertEq(bucket.fundingLiability, 0);
        assertEq(bucket.fundingPaid, expectedFunding);
    }

    function test_SettleLosingMLOInventoryUsesBucketMarginBeforeSeniorLoss() public {
        MLOPredictionTypes.MLOAskFillResult memory fill = _fillDefaultMLOAsk();
        uint256 seniorDebt = fill.seniorDeployed - fill.seniorRepaid;
        uint256 marginBefore = IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId).marginAllocated;

        _resolveMarket(uint8(LibEveMarket.MarketOutcome.Yes));
        MLOPredictionTypes.MLOInventorySettlement memory settlement =
            IMLOPredictionAdapterFacet(address(diamond)).settleMLOInventory(bucketId, marketId);

        assertEq(settlement.collateralOut, 0);
        assertEq(settlement.marginUsed, seniorDebt);
        assertEq(settlement.seniorLoss, 0);
        assertEq(_seniorBucket(bucketId).activeExposure, 0);

        MarginTypes.MarginBucket memory bucket = IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId);
        assertEq(bucket.marginAllocated, marginBefore - seniorDebt);
        assertEq(bucket.vaultDebt, 0);
        assertEq(bucket.positionRisk, 0);
        assertEq(bucket.realizedLosses, seniorDebt);
        assertEq(IMLOPredictionAdapterFacet(address(diamond)).getMLOInventory(bucketId, marketId).vault, address(0));
    }

    function test_CancelMLOAskCurveReleasesUnusedSeniorAndRisk() public {
        uint256 envelopeId = _createEnvelope();
        uint256 curveId = _createMLOCurve(envelopeId);

        vm.expectRevert(abi.encodeWithSelector(Errors.QuoteEnvelopeBoundToAdapterCurve.selector, envelopeId, curveId));
        vm.prank(maker);
        IQuoteEnvelopeFacet(address(diamond)).cancelQuoteEnvelope(envelopeId);

        vm.prank(maker);
        IMLOPredictionAdapterFacet(address(diamond)).cancelMLOCurve(curveId);

        assertEq(_seniorBucket(bucketId).reservedCapital, 0);
        MarginTypes.MarginBucket memory bucket = IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId);
        assertEq(bucket.openOrderRisk, 0);
        assertEq(bucket.positionRisk, 0);
    }

    function test_PartialFillAndCancellationKeepFilledScenarioLoss() public {
        uint256 envelopeId = _createEnvelope();
        uint256 curveId = _createMLOCurve(envelopeId);
        (uint32 generation, bytes32 commitment) = CurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        vm.startPrank(taker);
        collateral.approve(address(diamond), 25e18);
        MLOPredictionTypes.MLOAskFillResult memory result = IMLOPredictionAdapterFacet(address(diamond))
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

        MLOPredictionTypes.MLOScenarioExposureView memory beforeCancel =
            IMLOPredictionAdapterFacet(address(diamond)).getMLOScenarioExposure(bucketId);
        vm.prank(maker);
        IMLOPredictionAdapterFacet(address(diamond)).cancelMLOCurve(curveId);

        MLOPredictionTypes.MLOScenarioExposureView memory afterCancel =
            IMLOPredictionAdapterFacet(address(diamond)).getMLOScenarioExposure(bucketId);
        assertEq(afterCancel.openLosses[0], 0);
        assertEq(afterCancel.openLosses[1], 0);
        assertEq(afterCancel.openLosses[2], 0);
        assertEq(afterCancel.filledPositionLosses[0], beforeCancel.filledPositionLosses[0]);
        assertEq(afterCancel.filledPositionLosses[1], beforeCancel.filledPositionLosses[1]);
        assertEq(afterCancel.filledPositionLosses[2], beforeCancel.filledPositionLosses[2]);
        assertGt(uint256(afterCancel.maximumSignedLoss), 0);
        assertGt(result.fill.sharesOut, 0);
    }

    function test_ComplementaryOutcomeFillsNetOnlyAfterExecution() public {
        uint256 yesEnvelopeId = _createEnvelopeForBook(yesBookId);
        uint256 noEnvelopeId = _createEnvelopeForBook(noBookId);
        MLOPredictionTypes.MLOScenarioExposureView memory reserved =
            IMLOPredictionAdapterFacet(address(diamond)).getMLOScenarioExposure(bucketId);
        assertEq(reserved.openLosses[0], 30e18);
        assertEq(reserved.openLosses[1], 30e18);
        assertEq(reserved.openLosses[2], 10e18);
        assertEq(reserved.initialRequirement, 30e18);

        uint256 yesCurveId = _createMLOCurve(yesEnvelopeId);
        uint256 noCurveId = _createMLOCurve(noEnvelopeId);
        _fillCurve(yesCurveId, 25e18, 50e18);
        _fillCurve(noCurveId, 25e18, 50e18);

        MLOPredictionTypes.MLOScenarioExposureView memory filled =
            IMLOPredictionAdapterFacet(address(diamond)).getMLOScenarioExposure(bucketId);
        assertEq(filled.filledPositionLosses[0], 10e18);
        assertEq(filled.filledPositionLosses[1], 10e18);
        assertEq(filled.filledPositionLosses[2], 10e18);
        assertEq(filled.openLosses[0], 0);
        assertEq(filled.openLosses[1], 0);
        assertEq(filled.openLosses[2], 0);
        assertEq(filled.initialRequirement, 10e18);
        assertEq(conditionalTokens.balanceOf(taker, _yesPositionId()), 50e18);
        assertEq(conditionalTokens.balanceOf(taker, _noPositionId()), 50e18);
    }

    function test_ControlledCounterpartyCannotExternalizeComplementaryAskLoss() public {
        uint256 makerMarginBefore = IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId).marginAllocated;
        uint256 takerCollateralBefore = collateral.balanceOf(taker);
        uint256 seniorAssetsBefore = _seniorTotalAssets();
        uint256 seniorLossesBefore = _seniorState().realizedLosses;
        uint256 insuranceDrawnBefore = insuranceFund.totalDrawn();

        uint256 yesCurveId = _createMLOCurve(_createEnvelopeForBook(yesBookId));
        uint256 noCurveId = _createMLOCurve(_createEnvelopeForBook(noBookId));
        _fillCurve(yesCurveId, 25e18, 50e18);
        _fillCurve(noCurveId, 25e18, 50e18);

        assertEq(conditionalTokens.balanceOf(taker, _yesPositionId()), 50e18);
        assertEq(conditionalTokens.balanceOf(taker, _noPositionId()), 50e18);
        _mergeCompleteSet(taker, 50e18);
        assertEq(collateral.balanceOf(taker), takerCollateralBefore + 10e18);
        assertEq(_seniorBucket(bucketId).activeExposure, 10e18);

        _resolveMarket(uint8(LibEveMarket.MarketOutcome.Yes));
        MLOPredictionTypes.MLOInventorySettlement memory settlement =
            IMLOPredictionAdapterFacet(address(diamond)).settleMLOInventory(bucketId, marketId);

        assertEq(settlement.marginUsed, 10e18);
        assertEq(settlement.insuranceDraw, 0);
        assertEq(settlement.seniorLoss, 0);
        assertEq(_seniorBucket(bucketId).activeExposure, 0);
        assertEq(_seniorTotalAssets(), seniorAssetsBefore);
        assertEq(_seniorState().realizedLosses, seniorLossesBefore);
        assertEq(insuranceFund.totalDrawn(), insuranceDrawnBefore);
        assertEq(
            IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId).marginAllocated, makerMarginBefore - 10e18
        );
    }

    function test_ControlledCounterpartyCannotExternalizeComplementaryBidLoss() public {
        uint256 makerMarginBefore = IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId).marginAllocated;
        uint256 takerCollateralBefore = collateral.balanceOf(taker);
        uint256 seniorAssetsBefore = _seniorTotalAssets();
        uint256 seniorLossesBefore = _seniorState().realizedLosses;
        uint256 insuranceDrawnBefore = insuranceFund.totalDrawn();

        _mintCompleteSet(taker, 50e18);
        uint256 yesCurveId = _createMLOCurve(_createBidEnvelopeForBookAtPrice(yesBookId, SIXTY_CENTS));
        uint256 noCurveId = _createMLOCurve(_createBidEnvelopeForBookAtPrice(noBookId, SIXTY_CENTS));
        _fillBidCurve(yesCurveId, 50e18, 30e18);
        _fillBidCurve(noCurveId, 50e18, 30e18);

        assertEq(collateral.balanceOf(taker), takerCollateralBefore + 10e18);
        assertEq(_seniorBucket(bucketId).activeExposure, 10e18);

        _resolveMarket(uint8(LibEveMarket.MarketOutcome.Yes));
        MLOPredictionTypes.MLOInventorySettlement memory settlement =
            IMLOPredictionAdapterFacet(address(diamond)).settleMLOInventory(bucketId, marketId);

        assertEq(settlement.marginUsed, 10e18);
        assertEq(settlement.insuranceDraw, 0);
        assertEq(settlement.seniorLoss, 0);
        assertEq(_seniorBucket(bucketId).activeExposure, 0);
        assertEq(_seniorTotalAssets(), seniorAssetsBefore);
        assertEq(_seniorState().realizedLosses, seniorLossesBefore);
        assertEq(insuranceFund.totalDrawn(), insuranceDrawnBefore);
        assertEq(
            IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId).marginAllocated, makerMarginBefore - 10e18
        );
    }

    function test_InventoryBackedAskAvoidsNewSeniorDeployment() public {
        _fillDefaultMLOAsk();
        uint256 noCurveId = _createMLOCurve(_createEnvelopeForBook(noBookId));

        MLOPredictionTypes.MLOCurveView memory beforeFill =
            IMLOPredictionAdapterFacet(address(diamond)).getMLOCurve(noCurveId);
        assertEq(beforeFill.inventoryReserved, 50e18);
        assertEq(beforeFill.seniorReserved, 0);

        MLOPredictionTypes.MLOAskFillResult memory fill = _fillCurve(noCurveId, 25e18, 50e18);
        assertEq(fill.inventoryUsed, 50e18);
        assertEq(fill.seniorDeployed, 0);
        assertEq(fill.seniorRepaid, 20e18);
        assertEq(fill.retainedInventory, 0);

        MLOPredictionTypes.MLOInventoryView memory inventory =
            IMLOPredictionAdapterFacet(address(diamond)).getMLOInventory(bucketId, marketId);
        assertEq(inventory.inventory[0], 0);
        assertEq(inventory.inventory[1], 0);
        assertEq(inventory.reserved[1], 0);
        assertEq(inventory.seniorDebt, 10e18);
        assertEq(_seniorBucket(bucketId).activeExposure, 10e18);
        assertEq(conditionalTokens.balanceOf(taker, _noPositionId()), 50e18);
    }

    function test_MixedInventoryAndSeniorFillUsesOnlyCapitalDeficit() public {
        _fillDefaultMLOAsk();
        uint256 noCurveId = _createMLOCurve(_createEnvelopeWithVolumes(noBookId, 100e18, 100e18));

        MLOPredictionTypes.MLOAskFillResult memory fill = _fillCurve(noCurveId, 50e18, 100e18);
        assertEq(fill.inventoryUsed, 50e18);
        assertEq(fill.seniorDeployed, 30e18);
        assertEq(fill.seniorRepaid, 20e18);
        assertEq(fill.retainedInventory, 50e18);

        MLOPredictionTypes.MLOInventoryView memory inventory =
            IMLOPredictionAdapterFacet(address(diamond)).getMLOInventory(bucketId, marketId);
        assertEq(inventory.inventory[0], 50e18);
        assertEq(inventory.inventory[1], 0);
        assertEq(inventory.seniorDebt, 40e18);
        assertEq(_seniorBucket(bucketId).activeExposure, 40e18);
        assertEq(conditionalTokens.balanceOf(inventory.vault, _yesPositionId()), 50e18);
    }

    function test_InventorySaleProceedsAboveDebtCreditMakerMargin() public {
        _fillDefaultMLOAsk();
        uint256 marginBefore = IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId).marginAllocated;
        QuoteEnvelopeTypes.CreateQuoteEnvelopeParams memory params = _defaultEnvelope();
        params.bookId = noBookId;
        params.minPrice = 800_000_000;
        params.maxPrice = 800_000_000;
        params.initialStartPrice = 800_000_000;
        params.initialEndPrice = 800_000_000;
        vm.prank(maker);
        uint256 envelopeId = IQuoteEnvelopeFacet(address(diamond)).createQuoteEnvelope(params);
        uint256 curveId = _createMLOCurve(envelopeId);

        MLOPredictionTypes.MLOAskFillResult memory fill = _fillCurve(curveId, 45e18, 50e18);
        assertEq(fill.inventoryUsed, 50e18);
        assertEq(fill.seniorDeployed, 0);
        assertEq(fill.seniorRepaid, 30e18);
        assertEq(fill.makerProfit, 10e18);
        assertEq(_seniorBucket(bucketId).activeExposure, 0);
        assertEq(IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId).vaultDebt, 0);
        assertEq(IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId).marginAllocated, marginBefore + 7.5e18);
        assertEq(IMLOProfitShareFacet(address(diamond)).mloBucketProfitReward(bucketId, creator).accountClaimable, 2e18);
        assertEq(insuranceFund.totalProfitShare(), 0.5e18);
    }

    function test_MultipleCurvesCannotDoublePledgeInventoryAndCanRebalance() public {
        _fillDefaultMLOAsk();
        uint256 firstCurveId = _createMLOCurve(_createEnvelopeForBook(noBookId));
        uint256 secondCurveId = _createMLOCurve(_createEnvelopeForBook(noBookId));

        assertEq(IMLOPredictionAdapterFacet(address(diamond)).getMLOCurve(firstCurveId).inventoryReserved, 50e18);
        assertEq(IMLOPredictionAdapterFacet(address(diamond)).getMLOCurve(secondCurveId).inventoryReserved, 0);
        MLOPredictionTypes.MLOInventoryView memory inventory =
            IMLOPredictionAdapterFacet(address(diamond)).getMLOInventory(bucketId, marketId);
        assertEq(inventory.inventory[1], 50e18);
        assertEq(inventory.reserved[1], 50e18);
        assertEq(inventory.available[1], 0);

        IMLOPredictionAdapterFacet(address(diamond)).rebalanceMLOAskCurve(secondCurveId);
        assertEq(IMLOPredictionAdapterFacet(address(diamond)).getMLOCurve(secondCurveId).inventoryReserved, 0);

        vm.prank(maker);
        IMLOPredictionAdapterFacet(address(diamond)).cancelMLOCurve(firstCurveId);
        IMLOPredictionAdapterFacet(address(diamond)).rebalanceMLOAskCurve(secondCurveId);

        MLOPredictionTypes.MLOCurveView memory rebalanced =
            IMLOPredictionAdapterFacet(address(diamond)).getMLOCurve(secondCurveId);
        assertEq(rebalanced.inventoryReserved, 50e18);
        assertEq(rebalanced.seniorReserved, 0);
        inventory = IMLOPredictionAdapterFacet(address(diamond)).getMLOInventory(bucketId, marketId);
        assertEq(inventory.reserved[1], 50e18);
        assertEq(inventory.seniorReserved, _seniorBucket(bucketId).reservedCapital);
    }

    function test_CompleteSetAutoMergeRepaysSeniorDebtExactlyOnce() public {
        uint256 yesCurveId = _createMLOCurve(_createEnvelopeForBook(yesBookId));
        uint256 noCurveId = _createMLOCurve(_createEnvelopeForBook(noBookId));
        _fillCurve(yesCurveId, 25e18, 50e18);
        _fillCurve(noCurveId, 25e18, 50e18);

        MLOPredictionTypes.MLOInventoryView memory inventory =
            IMLOPredictionAdapterFacet(address(diamond)).getMLOInventory(bucketId, marketId);
        assertEq(inventory.inventory[0], 0);
        assertEq(inventory.inventory[1], 0);
        assertEq(inventory.seniorDebt, 10e18);
        assertEq(_seniorBucket(bucketId).activeExposure, 10e18);
        assertEq(IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId).vaultDebt, 10e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMLOPredictionAdapterFacet.MLOInsufficientUnreservedInventory.selector, bucketId, marketId, 50e18, 0
            )
        );
        IMLOPredictionAdapterFacet(address(diamond)).mergeMLOCompleteSet(bucketId, marketId, 50e18);

        MLOPredictionTypes.MLOScenarioExposureView memory exposure =
            IMLOPredictionAdapterFacet(address(diamond)).getMLOScenarioExposure(bucketId);
        assertEq(exposure.filledPositionLosses[0], 10e18);
        assertEq(exposure.filledPositionLosses[1], 10e18);
        assertEq(exposure.filledPositionLosses[2], 10e18);
    }

    function test_RevertWhen_NonControllerMovesVaultInventory() public {
        _fillDefaultMLOAsk();
        address vault = IMLOPredictionAdapterFacet(address(diamond)).getMLOInventory(bucketId, marketId).vault;
        uint256 noPositionId = _noPositionId();

        vm.expectRevert(abi.encodeWithSelector(MLOInventoryVault.NotController.selector, taker));
        vm.prank(taker);
        MLOInventoryVault(vault).transferPosition(address(conditionalTokens), taker, noPositionId, 1);
    }

    function test_RevertWhen_NonControllerMergesVaultInventory() public {
        _fillDefaultMLOAsk();
        address vault = IMLOPredictionAdapterFacet(address(diamond)).getMLOInventory(bucketId, marketId).vault;

        vm.expectRevert(abi.encodeWithSelector(MLOInventoryVault.NotController.selector, taker));
        vm.prank(taker);
        MLOInventoryVault(vault).mergeToController(address(conditionalTokens), address(collateral), bytes32(0), 1);
    }

    function test_RevertWhen_NonControllerUsesNegRiskVaultSettlement() public {
        _activateNativeThreeOutcomeMarket();
        uint256 curveId = _createMLOCurve(_createEnvelopeForBook(yesBookId));
        _fillCurve(curveId, 25e18, 50e18);
        address vault = IMLOPredictionAdapterFacet(address(diamond)).getMLOInventory(bucketId, marketId).vault;

        vm.expectRevert(abi.encodeWithSelector(MLOInventoryVault.NotController.selector, taker));
        vm.prank(taker);
        MLOInventoryVault(vault).mergeNegRiskToController(address(negRiskAdapter), bytes32(0), 1);

        vm.expectRevert(abi.encodeWithSelector(MLOInventoryVault.NotController.selector, taker));
        vm.prank(taker);
        MLOInventoryVault(vault).redeemNegRiskToController(address(negRiskAdapter), bytes32(0), new uint256[](3));
    }

    function test_RevertWhen_ExternalCallerInvokesInternalAssetSettlement() public {
        vm.expectRevert(abi.encodeWithSelector(IMLOPredictionAdapterFacet.MLOInternalOnly.selector, address(this)));
        IMLOPredictionAdapterFacet(address(diamond))
            .executeMLOAskAssetSettlement(
                MLOPredictionTypes.MLOAskAssetSettlementParams({
                    collateralToken: address(0),
                    positionToken: address(0),
                    inventoryVault: address(0),
                    receiver: address(0),
                    bucketId: bytes32(0),
                    bookId: bytes32(0),
                    conditionId: bytes32(0),
                    resolutionId: bytes32(0),
                    soldPositionId: 0,
                    retainedPositionIds: new uint256[](0),
                    positionTokenType: 0,
                    inventoryUsed: 0,
                    manufacturedShares: 0,
                    seniorDeployed: 0,
                    seniorReleased: 0,
                    seniorRepaid: 0,
                    fundingPaid: 0,
                    feePaid: 0
                })
            );
    }

    function test_RevertWhen_ExternalCallerInvokesInternalAskAccounting() public {
        vm.expectRevert(abi.encodeWithSelector(IMLOPredictionAdapterFacet.MLOInternalOnly.selector, address(this)));
        IMLOPredictionAdapterFacet(address(diamond)).prepareMLOAskBacking(0, 0, 0, 0);

        vm.expectRevert(abi.encodeWithSelector(IMLOPredictionAdapterFacet.MLOInternalOnly.selector, address(this)));
        IMLOPredictionAdapterFacet(address(diamond))
            .applyMLOAskFillState(
                MLOPredictionTypes.MLOAskFillStateParams({
                    curveId: 0,
                    sharesOut: 0,
                    price: 0,
                    collateralUsed: 0,
                    feePaid: 0,
                    backing: MLOPredictionTypes.MLOAskBacking({
                        inventoryUsed: 0,
                        manufacturedShares: 0,
                        seniorDeployed: 0,
                        seniorReleased: 0,
                        seniorRepaid: 0,
                        fundingPaid: 0,
                        bucketProfit: 0
                    })
                })
            );
    }

    function test_ReservedInventoryMustBeReleasedBeforeResolutionSettlement() public {
        _fillDefaultMLOAsk();
        uint256 noCurveId = _createMLOCurve(_createEnvelopeForBook(noBookId));
        _resolveMarket(uint8(LibEveMarket.MarketOutcome.No));

        vm.expectRevert(
            abi.encodeWithSelector(
                IMLOPredictionAdapterFacet.MLOInventoryReserved.selector, bucketId, marketId, 1, 50e18
            )
        );
        IMLOPredictionAdapterFacet(address(diamond)).settleMLOInventory(bucketId, marketId);

        vm.prank(taker);
        IMLOPredictionAdapterFacet(address(diamond)).cleanupMLOCurves(bucketId, _singleUint(noCurveId));
        MLOPredictionTypes.MLOInventorySettlement memory first =
            IMLOPredictionAdapterFacet(address(diamond)).settleMLOInventory(bucketId, marketId);
        MLOPredictionTypes.MLOInventorySettlement memory retry =
            IMLOPredictionAdapterFacet(address(diamond)).settleMLOInventory(bucketId, marketId);
        assertGt(first.seniorRepaid, 0);
        assertEq(retry.seniorRepaid, 0);
        assertEq(retry.bucketId, bucketId);
        assertEq(retry.marketId, marketId);
        assertEq(_seniorBucket(bucketId).activeExposure, 0);
    }

    function testFuzz_InventoryReservationAndCancellationReconcile(uint256 maxVolumeSeed) public {
        _fillDefaultMLOAsk();
        uint128 maxVolume = uint128(bound(maxVolumeSeed, 1, 100e18));
        uint128 initialVolume = maxVolume < 50e18 ? maxVolume : 50e18;
        uint256 curveId = _createMLOCurve(_createEnvelopeWithVolumes(noBookId, maxVolume, initialVolume));

        uint256 expectedInventory = initialVolume;
        MLOPredictionTypes.MLOCurveView memory curve = IMLOPredictionAdapterFacet(address(diamond)).getMLOCurve(curveId);
        assertEq(curve.inventoryReserved, expectedInventory);
        assertEq(curve.inventoryReserved + curve.seniorReserved, initialVolume);
        assertLe(IMLOPredictionAdapterFacet(address(diamond)).getMLOInventory(bucketId, marketId).reserved[1], 50e18);

        vm.prank(maker);
        IMLOPredictionAdapterFacet(address(diamond)).cancelMLOCurve(curveId);
        assertEq(IMLOPredictionAdapterFacet(address(diamond)).getMLOInventory(bucketId, marketId).reserved[1], 0);
    }

    function test_UnderMarginedMakerCanCancelToReduceRisk() public {
        address tightMaker = makeAddr("cancel-maker");
        _fundCollateral(tightMaker, 31e6);
        bytes32 riskDomain = IMarginAccountFacet(address(diamond)).riskDomainForMarket(marketId);
        vm.startPrank(tightMaker);
        collateral.approve(address(diamond), 31e18);
        IMarginAccountFacet(address(diamond)).depositMargin(31e18, tightMaker);
        bytes32 tightBucketId = IMarginAccountFacet(address(diamond)).allocateBucketMargin(riskDomain, 31e18, 1);
        QuoteEnvelopeTypes.CreateQuoteEnvelopeParams memory params = _defaultEnvelope();
        params.bucketId = tightBucketId;
        uint256 envelopeId = IQuoteEnvelopeFacet(address(diamond)).createQuoteEnvelope(params);
        uint256 curveId = IMLOPredictionAdapterFacet(address(diamond))
            .createMLOCurve(MLOPredictionTypes.CreateMLOCurveParams({envelopeId: envelopeId, durationMinutes: 120}));
        vm.stopPrank();

        vm.prank(owner);
        IMarginAccountFacet(address(diamond))
            .setRiskDomainFundingConfig(riskDomain, MarginTypes.FundingMode.BorrowRate, 1e18);
        _fillCurve(curveId, 1e18, 1);
        vm.warp(block.timestamp + 1);
        IMarginAccountFacet(address(diamond)).accrueBucketFundingNow(tightBucketId);
        assertEq(
            uint8(IMarginAccountFacet(address(diamond)).bucketHealth(tightBucketId).status),
            uint8(MarginTypes.BucketHealthStatus.BelowInitial)
        );

        vm.prank(tightMaker);
        IMLOPredictionAdapterFacet(address(diamond)).cancelMLOCurve(curveId);

        MLOPredictionTypes.MLOScenarioExposureView memory exposure =
            IMLOPredictionAdapterFacet(address(diamond)).getMLOScenarioExposure(tightBucketId);
        assertEq(exposure.openLosses[0], 0);
        assertEq(exposure.openLosses[1], 0);
        assertEq(exposure.openLosses[2], 0);
        assertEq(_seniorBucket(tightBucketId).reservedCapital, 0);
    }

    function test_HealthyActiveCurveCannotBePermissionlesslyCleaned() public {
        uint256 curveId = _createMLOCurve(_createEnvelope());
        uint256[] memory curveIds = _singleUint(curveId);

        vm.prank(taker);
        vm.expectRevert(
            abi.encodeWithSelector(IMLOPredictionAdapterFacet.MLOCurveCleanupNotAllowed.selector, curveId, bucketId)
        );
        IMLOPredictionAdapterFacet(address(diamond)).cleanupMLOCurves(bucketId, curveIds);
    }

    function test_ExpiredCurveCleanupIsPermissionlessAndIdempotent() public {
        uint256 curveId = _createMLOCurve(_createEnvelope());
        vm.warp(block.timestamp + 2 hours);
        uint256[] memory curveIds = new uint256[](2);
        curveIds[0] = curveId;
        curveIds[1] = curveId;

        vm.prank(taker);
        MLOPredictionTypes.MLOCurveCleanupResult memory result =
            IMLOPredictionAdapterFacet(address(diamond)).cleanupMLOCurves(bucketId, curveIds);

        assertEq(result.cleaned, 1);
        assertEq(result.seniorReleased, 30e18);
        assertEq(_seniorBucket(bucketId).reservedCapital, 0);
    }

    function test_EarlySettlementAllowsPermissionlessCurveCleanup() public {
        uint256 curveId = _createMLOCurve(_createEnvelope());
        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarketEarly(marketId, uint8(LibEveMarket.MarketOutcome.No));

        vm.prank(taker);
        MLOPredictionTypes.MLOCurveCleanupResult memory cleanup =
            IMLOPredictionAdapterFacet(address(diamond)).cleanupMLOCurves(bucketId, _singleUint(curveId));

        assertEq(cleanup.cleaned, 1);
        assertEq(cleanup.seniorReleased, 30e18);
        assertEq(_seniorBucket(bucketId).reservedCapital, 0);
    }

    function test_MarketExpiryKeeperCleanupRestoresSeniorAndPreservesFilledExposure() public {
        marketExpiry = uint64(block.timestamp + 7 days);
        _fundCollateral(creator, 2e6);
        vm.startPrank(creator);
        collateral.approve(address(diamond), type(uint256).max);
        marketId = IMarketFactoryFacet(address(diamond))
            .createMarket(
                "Does the real MLO expiry flow settle?",
                "MLO launch",
                "Production resolution path",
                uint64(block.timestamp),
                marketExpiry,
                1e18,
                true
            );
        vm.stopPrank();
        yesBookId = LibCLOBBook.marketBookId(marketId, true);
        _depositAndAllocate(maker, 300e18);

        QuoteEnvelopeTypes.CreateQuoteEnvelopeParams memory envelope = _defaultEnvelope();
        envelope.expiresAt = marketExpiry;
        vm.prank(maker);
        uint256 envelopeId = IQuoteEnvelopeFacet(address(diamond)).createQuoteEnvelope(envelope);
        uint24 durationMinutes = uint24((marketExpiry - block.timestamp) / 60);
        vm.prank(maker);
        uint256 curveId = IMLOPredictionAdapterFacet(address(diamond))
            .createMLOCurve(
                MLOPredictionTypes.CreateMLOCurveParams({envelopeId: envelopeId, durationMinutes: durationMinutes})
            );
        MLOPredictionTypes.MLOAskFillResult memory fill = _fillCurve(curveId, 10e18, 1);

        ISeniorCapitalFacet.SeniorCapitalBucket memory accountingBefore = _seniorBucket(bucketId);
        uint256 availableBefore = _seniorState().availableCapital;
        uint256 totalAssetsBefore = _seniorTotalAssets();
        MLOPredictionTypes.MLOInventoryView memory inventoryBefore =
            IMLOPredictionAdapterFacet(address(diamond)).getMLOInventory(bucketId, marketId);
        MLOPredictionTypes.MLOScenarioExposureView memory exposureBefore =
            IMLOPredictionAdapterFacet(address(diamond)).getMLOScenarioExposure(bucketId);
        assertGt(accountingBefore.activeExposure, 0);
        assertGt(accountingBefore.reservedCapital, 0);
        assertGt(fill.fill.sharesOut, 0);

        vm.warp(marketExpiry);
        assertEq(
            MarketFactoryFacet(address(diamond)).syncMarketState(marketId), uint8(LibEveMarket.MarketState.Pending)
        );
        vm.prank(taker);
        MLOPredictionTypes.MLOCurveCleanupResult memory cleanup =
            IMLOPredictionAdapterFacet(address(diamond)).cleanupMLOCurves(bucketId, _singleUint(curveId));

        ISeniorCapitalFacet.SeniorCapitalBucket memory accountingAfter = _seniorBucket(bucketId);
        MLOPredictionTypes.MLOInventoryView memory inventoryAfter =
            IMLOPredictionAdapterFacet(address(diamond)).getMLOInventory(bucketId, marketId);
        MLOPredictionTypes.MLOScenarioExposureView memory exposureAfter =
            IMLOPredictionAdapterFacet(address(diamond)).getMLOScenarioExposure(bucketId);
        assertEq(cleanup.cleaned, 1);
        assertEq(cleanup.seniorReleased, accountingBefore.reservedCapital);
        assertEq(accountingAfter.reservedCapital, 0);
        assertEq(accountingAfter.activeExposure, accountingBefore.activeExposure);
        assertEq(_seniorState().availableCapital, availableBefore + accountingBefore.reservedCapital);
        assertEq(_seniorTotalAssets(), totalAssetsBefore);
        assertEq(inventoryAfter.inventory, inventoryBefore.inventory);
        assertEq(inventoryAfter.seniorDebt, inventoryBefore.seniorDebt);
        assertEq(inventoryAfter.seniorReserved, 0);
        assertEq(exposureAfter.filledPositionLosses, exposureBefore.filledPositionLosses);
        for (uint256 index; index < exposureAfter.openLosses.length; ++index) {
            assertEq(exposureAfter.openLosses[index], 0);
        }

        vm.prank(owner);
        IOBRResolutionFacet(address(diamond)).adminFinalizeResolution(marketId, uint8(LibEveMarket.MarketOutcome.No));
        IMLOPredictionAdapterFacet(address(diamond)).settleMLOInventory(bucketId, marketId);
        assertEq(_seniorBucket(bucketId).activeExposure, 0);
        assertEq(_seniorBucket(bucketId).reservedCapital, 0);
    }

    function test_BelowInitialBucketEntersReduceOnlyAndCanBeCured() public {
        _fillDefaultMLOAsk();
        bytes32 riskDomain = IMarginAccountFacet(address(diamond)).riskDomainForMarket(marketId);
        vm.prank(owner);
        IMarginAccountFacet(address(diamond))
            .setRiskDomainFundingConfig(riskDomain, MarginTypes.FundingMode.BorrowRate, 1e18);
        vm.warp(block.timestamp + 10);

        uint8 reducedState = IMLOPredictionAdapterFacet(address(diamond)).synchronizeMLOBucketState(bucketId);
        assertEq(reducedState, uint8(MarginTypes.BucketState.ReduceOnly));

        _fundCollateral(maker, 30e6);
        vm.startPrank(maker);
        collateral.approve(address(diamond), 30e18);
        IMarginAccountFacet(address(diamond)).depositMargin(30e18, maker);
        IMarginAccountFacet(address(diamond)).allocateBucketMargin(riskDomain, 30e18, 1);
        vm.stopPrank();

        uint8 healthyState = IMLOPredictionAdapterFacet(address(diamond)).synchronizeMLOBucketState(bucketId);
        assertEq(healthyState, uint8(MarginTypes.BucketState.Healthy));
    }

    function test_BelowMaintenanceRecoveryAllowsPermissionlessBoundedCleanup() public {
        uint256 curveId = _createMLOCurve(_createEnvelope());
        MLOPredictionTypes.MLOAskFillResult memory fill = _fillCurve(curveId, 10e18, 1);
        bytes32 riskDomain = IMarginAccountFacet(address(diamond)).riskDomainForMarket(marketId);
        vm.prank(owner);
        IMarginAccountFacet(address(diamond))
            .setRiskDomainFundingConfig(riskDomain, MarginTypes.FundingMode.BorrowRate, 1e18);
        vm.warp(block.timestamp + 22);

        uint8 recoveryState = IMLOPredictionAdapterFacet(address(diamond)).synchronizeMLOBucketState(bucketId);
        assertEq(recoveryState, uint8(MarginTypes.BucketState.Recovering));

        uint256[] memory curveIds = new uint256[](2);
        curveIds[0] = curveId;
        curveIds[1] = curveId;
        vm.prank(taker);
        MLOPredictionTypes.MLOCurveCleanupResult memory result =
            IMLOPredictionAdapterFacet(address(diamond)).cleanupMLOCurves(bucketId, curveIds);

        assertEq(result.cleaned, 1);
        assertGt(result.seniorReleased, 0);
        assertEq(_seniorBucket(bucketId).reservedCapital, 0);
        MLOPredictionTypes.MLOInventoryView memory inventory =
            IMLOPredictionAdapterFacet(address(diamond)).getMLOInventory(bucketId, marketId);
        assertEq(inventory.inventory[1], fill.fill.sharesOut);
        assertEq(conditionalTokens.balanceOf(inventory.vault, _noPositionId()), fill.fill.sharesOut);
    }

    function test_RecoveryInsuranceCoversPrincipalAndWritesOffUnpaidFunding() public {
        vm.prank(maker);
        IMarginAccountFacet(address(diamond)).releaseBucketMargin(bucketId, 240e18);
        MLOPredictionTypes.MLOAskFillResult memory fill = _fillDefaultMLOAsk();
        uint256 seniorDebt = fill.seniorDeployed - fill.seniorRepaid;
        bytes32 riskDomain = IMarginAccountFacet(address(diamond)).riskDomainForMarket(marketId);
        vm.prank(owner);
        IMarginAccountFacet(address(diamond))
            .setRiskDomainFundingConfig(riskDomain, MarginTypes.FundingMode.BorrowRate, 1e18);
        vm.prank(owner);
        IMLOPredictionAdapterFacet(address(diamond)).setMLORecoveryConfig(address(insuranceFund), 10_000, 32);
        vm.warp(block.timestamp + 2);
        IMLOPredictionAdapterFacet(address(diamond)).settleMLOFunding(bucketId, 40e18);
        _sponsorInsurance(10e18);

        _resolveMarket(uint8(LibEveMarket.MarketOutcome.Yes));
        MLOPredictionTypes.MLOInventorySettlement memory settlement =
            IMLOPredictionAdapterFacet(address(diamond)).settleMLOInventory(bucketId, marketId);

        assertEq(settlement.marginUsed, 20e18);
        assertEq(settlement.insuranceDraw, seniorDebt - 20e18);
        assertEq(settlement.seniorLoss, 0);
        assertEq(settlement.fundingWrittenOff, 20e18);
        assertEq(insuranceFund.bucketDrawn(bucketId), seniorDebt - 20e18);
        MarginTypes.MarginBucket memory bucket = IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId);
        assertEq(bucket.fundingLiability, 0);
        assertEq(bucket.fundingBadDebt, 20e18);
        assertEq(uint8(bucket.state), uint8(MarginTypes.BucketState.Closed));
    }

    function test_PartialInsuranceExhaustionRecordsOnlyResidualSeniorLoss() public {
        vm.prank(maker);
        IMarginAccountFacet(address(diamond)).releaseBucketMargin(bucketId, 240e18);
        MLOPredictionTypes.MLOAskFillResult memory fill = _fillDefaultMLOAsk();
        uint256 seniorDebt = fill.seniorDeployed - fill.seniorRepaid;
        bytes32 riskDomain = IMarginAccountFacet(address(diamond)).riskDomainForMarket(marketId);
        vm.prank(owner);
        IMarginAccountFacet(address(diamond))
            .setRiskDomainFundingConfig(riskDomain, MarginTypes.FundingMode.BorrowRate, 1e18);
        vm.prank(owner);
        IMLOPredictionAdapterFacet(address(diamond)).setMLORecoveryConfig(address(insuranceFund), 10_000, 32);
        vm.warp(block.timestamp + 2);
        IMLOPredictionAdapterFacet(address(diamond)).settleMLOFunding(bucketId, 40e18);
        _sponsorInsurance(5e18);

        _resolveMarket(uint8(LibEveMarket.MarketOutcome.Yes));
        MLOPredictionTypes.MLOInventorySettlement memory settlement =
            IMLOPredictionAdapterFacet(address(diamond)).settleMLOInventory(bucketId, marketId);

        assertEq(settlement.marginUsed, 20e18);
        assertEq(settlement.insuranceDraw, 5e18);
        assertEq(settlement.seniorLoss, seniorDebt - 25e18);
        assertEq(_seniorState().realizedLosses, seniorDebt - 25e18);
    }

    function test_ScenarioViewUsesConfiguredMarginsAndPendingFunding() public {
        _fillDefaultMLOAsk();
        bytes32 riskDomain = IMarginAccountFacet(address(diamond)).riskDomainForMarket(marketId);
        vm.startPrank(owner);
        IMarginAccountFacet(address(diamond))
            .setRiskDomainRiskParams(riskDomain, MarginTypes.BucketKind.MLO, 10_000, 7_000);
        IMarginAccountFacet(address(diamond))
            .setRiskDomainFundingConfig(riskDomain, MarginTypes.FundingMode.BorrowRate, 0.01e18);
        vm.stopPrank();
        vm.warp(block.timestamp + 10);

        MLOPredictionTypes.MLOScenarioExposureView memory exposure =
            IMLOPredictionAdapterFacet(address(diamond)).getMLOScenarioExposure(bucketId);
        assertEq(exposure.funding, 3e18);
        assertEq(exposure.maximumEffectiveLoss, 33e18);
        assertEq(exposure.initialRequirement, 33e18);
        assertEq(exposure.maintenanceRequirement, 23.1e18);
        assertEq(IMarginAccountFacet(address(diamond)).bucketHealth(bucketId).exposure, 33e18);
    }

    function test_PermissionlessFundingSweepMovesMakerMarginToSeniorPool() public {
        MLOPredictionTypes.MLOAskFillResult memory fill = _fillDefaultMLOAsk();
        bytes32 riskDomain = IMarginAccountFacet(address(diamond)).riskDomainForMarket(marketId);
        vm.prank(owner);
        IMarginAccountFacet(address(diamond))
            .setRiskDomainFundingConfig(riskDomain, MarginTypes.FundingMode.BorrowRate, 1e15);

        vm.warp(block.timestamp + 10);
        MLOPredictionTypes.MLOFundingView memory preview =
            IMLOPredictionAdapterFacet(address(diamond)).previewMLOFunding(bucketId);
        uint256 expected = (fill.seniorDeployed - fill.seniorRepaid) * 1e15 * 10 / 1e18;
        assertEq(preview.pending, expected);

        uint256 poolAssetsBefore = _seniorTotalAssets();
        uint256 marginBefore = IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId).marginAllocated;
        vm.prank(taker);
        uint256 paid = IMLOPredictionAdapterFacet(address(diamond)).settleMLOFunding(bucketId, type(uint256).max);

        MarginTypes.MarginBucket memory bucket = IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId);
        assertEq(paid, expected);
        assertEq(bucket.marginAllocated, marginBefore - expected);
        assertEq(bucket.fundingLiability, 0);
        assertEq(bucket.fundingPaid, expected);
        assertEq(_seniorState().fundingRevenue, expected / 2);
        assertEq(_seniorBucket(bucketId).fundingRevenue, expected / 2);
        assertEq(insuranceFund.bucketFundingRevenue(bucketId), expected - expected / 2);
        assertEq(_seniorTotalAssets(), poolAssetsBefore + expected / 2);
    }

    function test_RevertWhen_BucketIsReduceOnlyDuringMLOFill() public {
        uint256 envelopeId = _createEnvelope();
        uint256 curveId = _createMLOCurve(envelopeId);
        (uint32 generation, bytes32 commitment) = CurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        IMarginAccountFacet(address(diamond)).recordBucketLoss(bucketId, 272e18);

        vm.startPrank(taker);
        collateral.approve(address(diamond), 25e18);
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
        bytes32 riskDomain = IMarginAccountFacet(address(diamond)).riskDomainForMarket(marketId);
        vm.startPrank(owner);
        IMarginAccountFacet(address(diamond))
            .setRiskDomainOracleConfig(riskDomain, MarginTypes.RiskDomainOracleKind.BookMark, yesBookId);
        IMarkOracleFacet(address(diamond)).setMarkOracleManualState(yesBookId, MarkOracleTypes.OracleState.Paused);
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(
                IProductionMarginAccountFacet.RiskDomainOracleBlocked.selector,
                riskDomain,
                yesBookId,
                MarginTypes.RiskDomainOracleKind.BookMark,
                uint8(MarkOracleTypes.OracleState.Paused)
            )
        );
        _createEnvelope();
    }

    function test_MLOFillOracleStateMatrix() public {
        uint256 curveId = _createMLOCurve(_createEnvelope());
        bytes32 riskDomain = IMarginAccountFacet(address(diamond)).riskDomainForMarket(marketId);
        _fillCurve(curveId, 1e18, 1);
        vm.startPrank(owner);
        IMarkOracleFacet(address(diamond)).setMarkOracleThresholds(10, 20);
        IMarginAccountFacet(address(diamond))
            .setRiskDomainOracleConfig(riskDomain, MarginTypes.RiskDomainOracleKind.BookMark, yesBookId);
        vm.stopPrank();

        assertGt(_fillCurve(curveId, 1e18, 1).fill.sharesOut, 0);
        vm.warp(block.timestamp + 11);
        assertEq(
            uint8(IMarkOracleFacet(address(diamond)).oracleState(yesBookId)), uint8(MarkOracleTypes.OracleState.Caution)
        );
        _assertMLOAskBlockedByOracleState(curveId);
        vm.warp(block.timestamp + 10);
        assertEq(
            uint8(IMarkOracleFacet(address(diamond)).oracleState(yesBookId)), uint8(MarkOracleTypes.OracleState.Stale)
        );
        _assertMLOAskBlockedByOracleState(curveId);
        vm.prank(owner);
        IMarkOracleFacet(address(diamond)).setMarkOracleManualState(yesBookId, MarkOracleTypes.OracleState.Paused);
        _assertMLOAskBlockedByOracleState(curveId);
        vm.prank(owner);
        IMarkOracleFacet(address(diamond))
            .setMarkOracleManualState(yesBookId, MarkOracleTypes.OracleState.ResolutionOnly);
        _assertMLOAskBlockedByOracleState(curveId);
    }

    function _postMLOParams(bytes32 bookId)
        internal
        view
        returns (MLOPredictionTypes.PostMLOCurveParams memory params)
    {
        QuoteEnvelopeTypes.CreateQuoteEnvelopeParams memory envelope = _defaultEnvelope();
        envelope.bookId = bookId;
        params = MLOPredictionTypes.PostMLOCurveParams({envelope: envelope, durationMinutes: 120});
    }

    function _updateMLOCurve(uint256 curveId, uint128 volume, uint128 startPrice, uint128 endPrice, bool resetStartTime)
        internal
        returns (uint32 generation)
    {
        MLOPredictionTypes.UpdateMLOCurveParams memory params = _mloUpdateParams(curveId, volume, startPrice, endPrice);
        vm.prank(maker);
        if (resetStartTime) {
            generation = IMLOPredictionAdapterFacet(address(diamond)).updateMLOCurveFromNow(params);
        } else {
            generation = IMLOPredictionAdapterFacet(address(diamond)).updateMLOCurve(params);
        }
    }

    function _mloUpdateParams(uint256 curveId, uint128 volume, uint128 startPrice, uint128 endPrice)
        internal
        view
        returns (MLOPredictionTypes.UpdateMLOCurveParams memory params)
    {
        MLOPredictionTypes.MLOCurveView memory curve = IMLOPredictionAdapterFacet(address(diamond)).getMLOCurve(curveId);
        params = MLOPredictionTypes.UpdateMLOCurveParams({
            curveId: curveId,
            envelopeUpdate: QuoteEnvelopeTypes.QuoteEnvelopeUpdate({
                volume: volume, startPrice: startPrice, endPrice: endPrice
            }),
            expectedCurveGeneration: curve.curveGeneration,
            expectedEnvelopeGeneration: curve.envelopeGeneration
        });
    }

    function _mloUpdates(uint256[] memory curveIds, uint128 volume)
        internal
        pure
        returns (MLOPredictionTypes.UpdateMLOCurveParams[] memory updates)
    {
        updates = new MLOPredictionTypes.UpdateMLOCurveParams[](curveIds.length);
        for (uint256 index; index < curveIds.length; ++index) {
            updates[index] = MLOPredictionTypes.UpdateMLOCurveParams({
                curveId: curveIds[index],
                envelopeUpdate: QuoteEnvelopeTypes.QuoteEnvelopeUpdate({
                    volume: volume, startPrice: 500_000_000, endPrice: 500_000_000
                }),
                expectedCurveGeneration: 1,
                expectedEnvelopeGeneration: 1
            });
        }
    }

    function _assertMLOReservation(
        uint256 curveId,
        uint256 riskVolume,
        uint256 inventoryReserved,
        uint256 seniorReserved,
        uint256 reservedRisk
    ) internal view {
        MLOPredictionTypes.MLOCurveView memory curve = IMLOPredictionAdapterFacet(address(diamond)).getMLOCurve(curveId);
        QuoteEnvelopeTypes.QuoteEnvelopeView memory envelope =
            IQuoteEnvelopeFacet(address(diamond)).getQuoteEnvelope(curve.envelopeId);
        assertEq(curve.remainingVolume, riskVolume);
        assertEq(curve.inventoryReserved, inventoryReserved);
        assertEq(curve.seniorReserved, seniorReserved);
        assertEq(envelope.currentVolume, riskVolume);
        assertEq(envelope.remainingRiskVolume, riskVolume);
        assertEq(envelope.reservedRisk, reservedRisk);
        assertEq(_seniorBucket(bucketId).reservedCapital, seniorReserved);
    }

    function _createEnvelope() internal returns (uint256 envelopeId) {
        envelopeId = _createEnvelopeForBook(yesBookId);
    }

    function _createEnvelopeForBook(bytes32 bookId) internal returns (uint256 envelopeId) {
        envelopeId = _createEnvelopeWithVolumes(bookId, ONE_HUNDRED_SHARES, 50e18);
    }

    function _createBidEnvelopeForBook(bytes32 bookId) internal returns (uint256 envelopeId) {
        QuoteEnvelopeTypes.CreateQuoteEnvelopeParams memory params = _defaultEnvelope();
        params.bookId = bookId;
        params.side = uint8(LibEveMarket.CurveSide.BID);
        vm.prank(maker);
        envelopeId = IQuoteEnvelopeFacet(address(diamond)).createQuoteEnvelope(params);
    }

    function _createBidEnvelopeForBookAtPrice(bytes32 bookId, uint128 price) internal returns (uint256 envelopeId) {
        QuoteEnvelopeTypes.CreateQuoteEnvelopeParams memory params = _defaultEnvelope();
        params.bookId = bookId;
        params.side = uint8(LibEveMarket.CurveSide.BID);
        params.minPrice = price;
        params.maxPrice = price;
        params.initialStartPrice = price;
        params.initialEndPrice = price;
        vm.prank(maker);
        envelopeId = IQuoteEnvelopeFacet(address(diamond)).createQuoteEnvelope(params);
    }

    function _activateNativeThreeOutcomeMarket() internal {
        _activateNativeMarket(3);
    }

    function _activateNativeMarket(uint8 outcomeCount) internal {
        string[] memory outcomes = new string[](outcomeCount);
        for (uint8 outcome; outcome < outcomeCount; ++outcome) {
            outcomes[outcome] = string.concat("Outcome ", vm.toString(uint256(outcome)));
        }
        MarketFactoryTypes.MarketDisplayInput memory display;
        MarketFactoryTypes.ExternalMarketRefInput memory externalRef;
        marketExpiry = uint64(block.timestamp + 7 days);
        _fundCollateral(creator, 1e6);
        vm.startPrank(creator);
        collateral.approve(address(diamond), type(uint256).max);
        eveToken.approve(address(diamond), type(uint256).max);
        marketId = IMultiOutcomeOrderbookFacet(address(diamond))
            .createMultiOutcomeMarket(
                IMultiOutcomeOrderbookFacet.CreateMultiOutcomeMarketParams({
                    question: "Who wins the native MLO test?",
                    category: "Testing",
                    resolutionSource: "Fixture",
                    tradingStartTime: uint64(block.timestamp),
                    expiryTime: marketExpiry,
                    outcomes: outcomes,
                    display: display,
                    externalRef: externalRef,
                    outcomeDisplay: new IMultiOutcomeOrderbookFacet.OutcomeDisplayInput[](0)
                })
            );
        vm.stopPrank();
        yesBookId = LibCLOBBook.multiOutcomeBookId(marketId, 0);
        noBookId = LibCLOBBook.multiOutcomeBookId(marketId, 1);
        _depositAndAllocate(maker, 300e18);
    }

    function _resolveNativeMarket(uint8 outcome) internal {
        vm.warp(marketExpiry);
        vm.prank(owner);
        IOBRResolutionFacet(address(diamond)).adminFinalizeResolution(marketId, outcome);
    }

    function _assertMLOAskBlockedByOracleState(uint256 curveId) internal {
        (uint32 generation, bytes32 commitment) = CurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        vm.startPrank(taker);
        collateral.approve(address(diamond), 25e18);
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

    function _mintNativeCompleteSet(address account, uint128 amount) internal returns (uint256[] memory positionIds) {
        vm.startPrank(account);
        collateral.approve(address(diamond), amount);
        positionIds = IMultiOutcomeOrderbookFacet(address(diamond)).splitOutcomeSet(marketId, amount, account);
        vm.stopPrank();
    }

    function _createEnvelopeWithVolumes(bytes32 bookId, uint128 maxVolume, uint128 initialVolume)
        internal
        returns (uint256 envelopeId)
    {
        QuoteEnvelopeTypes.CreateQuoteEnvelopeParams memory params = _defaultEnvelope();
        params.bookId = bookId;
        params.maxVolume = maxVolume;
        params.initialVolume = initialVolume;
        vm.prank(maker);
        envelopeId = IQuoteEnvelopeFacet(address(diamond)).createQuoteEnvelope(params);
    }

    function _createMLOCurve(uint256 envelopeId) internal returns (uint256 curveId) {
        vm.prank(maker);
        curveId = IMLOPredictionAdapterFacet(address(diamond))
            .createMLOCurve(MLOPredictionTypes.CreateMLOCurveParams({envelopeId: envelopeId, durationMinutes: 120}));
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
            expiresAt: uint64(block.timestamp + 3 hours)
        });
    }

    function _depositAndAllocate(address operator, uint256 assets) internal {
        _fundCollateral(operator, assets / 1e12);
        bytes32 riskDomain = IMarginAccountFacet(address(diamond)).riskDomainForMarket(marketId);
        vm.startPrank(operator);
        collateral.approve(address(diamond), assets);
        IMarginAccountFacet(address(diamond)).depositMargin(assets, operator);
        bucketId = IMarginAccountFacet(address(diamond)).allocateBucketMargin(riskDomain, assets, 1);
        vm.stopPrank();
    }

    function _fundSeniorPool(address account, uint256 assets) internal {
        _fundCollateral(account, assets / 1e12);
        vm.startPrank(account);
        collateral.approve(address(diamond), assets);
        ISeniorCapitalFacet(address(diamond)).depositSeniorCapital(assets);
        vm.warp(block.timestamp + 24 hours);
        ISeniorCapitalFacet(address(diamond)).activateSeniorCapital();
        vm.stopPrank();
    }

    function _mintCompleteSet(address account, uint128 amount) internal {
        (,,, bytes32 conditionId,,,,,,) = ITestStateFacet(address(diamond)).getStoredMarket(marketId);
        uint256[] memory partition = new uint256[](2);
        partition[0] = 1;
        partition[1] = 2;
        vm.startPrank(account);
        collateral.approve(address(conditionalTokens), amount);
        conditionalTokens.splitPosition(IERC20(address(collateral)), bytes32(0), conditionId, partition, amount);
        vm.stopPrank();
    }

    function _mergeCompleteSet(address account, uint128 amount) internal {
        (,,, bytes32 conditionId,,,,,,) = ITestStateFacet(address(diamond)).getStoredMarket(marketId);
        uint256[] memory partition = new uint256[](2);
        partition[0] = 1;
        partition[1] = 2;
        vm.prank(account);
        conditionalTokens.mergePositions(IERC20(address(collateral)), bytes32(0), conditionId, partition, amount);
    }

    function _singleUint(uint256 value) internal pure returns (uint256[] memory values) {
        values = new uint256[](1);
        values[0] = value;
    }

    function _singleUint32(uint32 value) internal pure returns (uint32[] memory values) {
        values = new uint32[](1);
        values[0] = value;
    }

    function _singleBytes32(bytes32 value) internal pure returns (bytes32[] memory values) {
        values = new bytes32[](1);
        values[0] = value;
    }

    function _seniorState() internal view returns (ISeniorCapitalFacet.SeniorCapitalState memory) {
        return ISeniorCapitalFacet(address(diamond)).seniorCapitalState();
    }

    function _seniorBucket(bytes32 seniorBucketId)
        internal
        view
        returns (ISeniorCapitalFacet.SeniorCapitalBucket memory)
    {
        return ISeniorCapitalFacet(address(diamond)).seniorCapitalBucket(seniorBucketId);
    }

    function _seniorTotalAssets() internal view returns (uint256) {
        ISeniorCapitalFacet.SeniorCapitalState memory state = _seniorState();
        return state.totalPrincipal + state.feeReserve;
    }

    function _sponsorInsurance(uint256 assets) internal {
        _fundCollateral(creator, assets / 1e12);
        vm.startPrank(creator);
        collateral.approve(address(insuranceFund), assets);
        insuranceFund.sponsor(assets);
        vm.stopPrank();
    }

    function _fillDefaultMLOAsk() internal returns (MLOPredictionTypes.MLOAskFillResult memory result) {
        uint256 envelopeId = _createEnvelope();
        uint256 curveId = _createMLOCurve(envelopeId);
        (uint32 generation, bytes32 commitment) = CurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        vm.startPrank(taker);
        collateral.approve(address(diamond), 25e18);
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

    function _fillCurve(uint256 curveId, uint128 collateralIn, uint128 minSharesOut)
        internal
        returns (MLOPredictionTypes.MLOAskFillResult memory result)
    {
        (uint32 generation, bytes32 commitment) = CurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        vm.startPrank(taker);
        collateral.approve(address(diamond), collateralIn);
        result = IMLOPredictionAdapterFacet(address(diamond))
            .fillMLOAskCurve(
                MLOPredictionTypes.FillMLOAskCurveParams({
                    curveId: curveId,
                    collateralIn: collateralIn,
                    minSharesOut: minSharesOut,
                    expectedGeneration: generation,
                    expectedCommitment: commitment,
                    receiver: taker
                })
            );
        vm.stopPrank();
    }

    function _fillBidCurve(uint256 curveId, uint128 sharesIn, uint128 minCollateralOut)
        internal
        returns (MLOPredictionTypes.MLOBidFillResult memory result)
    {
        (uint32 generation, bytes32 commitment) = CurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        vm.startPrank(taker);
        conditionalTokens.setApprovalForAll(address(diamond), true);
        result = IMLOPredictionAdapterFacet(address(diamond))
            .fillMLOBidCurve(
                MLOPredictionTypes.FillMLOBidCurveParams({
                    curveId: curveId,
                    sharesIn: sharesIn,
                    minCollateralOut: minCollateralOut,
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

    function _fundCollateral(address account, uint256 usdcAmount) internal {
        collateral.mint(account, usdcAmount * 1e12);
    }

    function _submitMarketBuy(bytes32 bookId, uint128 amountIn, DelayedOrderTypes.DelayedOrderRoute memory route)
        internal
        returns (uint256 orderId)
    {
        vm.startPrank(taker);
        collateral.approve(address(diamond), amountIn);
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
        selectors = MarginAccountingHarnessSelectors.production();
    }

    function _quoteEnvelopeSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](9);
        selectors[0] = IQuoteEnvelopeFacet.createQuoteEnvelope.selector;
        selectors[1] = IQuoteEnvelopeFacet.updateQuoteEnvelope.selector;
        selectors[2] = IQuoteEnvelopeFacet.cancelQuoteEnvelope.selector;
        selectors[3] = IQuoteEnvelopeFacet.cancelQuoteEnvelopes.selector;
        selectors[4] = IQuoteEnvelopeFacet.getQuoteEnvelope.selector;
        selectors[5] = IQuoteEnvelopeFacet.getOperatorQuoteEnvelopesPage.selector;
        selectors[6] = IQuoteEnvelopeFacet.getBookQuoteEnvelopesPage.selector;
        selectors[7] = IQuoteEnvelopeFacet.previewQuoteEnvelopeRisk.selector;
        selectors[8] = IQuoteEnvelopeFacet.canUpdateQuoteEnvelope.selector;
    }

    function _mloAdapterSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](5);
        selectors[0] = IMLOPredictionAdapterFacet.getMLOCurve.selector;
        selectors[1] = IMLOPredictionAdapterFacet.getMLOInventory.selector;
        selectors[2] = IMLOPredictionAdapterFacet.getMLOScenarioExposure.selector;
        selectors[3] = IMLOPredictionAdapterFacet.applyMLOAskFillState.selector;
        selectors[4] = IMLOPredictionAdapterFacet.previewMLOFunding.selector;
    }

    function _mloProfitShareSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](10);
        selectors[0] = IMLOProfitShareFacet.initializeMLOProfitSplit.selector;
        selectors[1] = IMLOProfitShareFacet.scheduleMLOProfitSplit.selector;
        selectors[2] = IMLOProfitShareFacet.cancelMLOProfitSplit.selector;
        selectors[3] = IMLOProfitShareFacet.executeMLOProfitSplit.selector;
        selectors[4] = IMLOProfitShareFacet.activeMLOProfitSplit.selector;
        selectors[5] = IMLOProfitShareFacet.pendingMLOProfitSplit.selector;
        selectors[6] = IMLOProfitShareFacet.mloBucketProfitAccount.selector;
        selectors[7] = IMLOProfitShareFacet.previewMLOProfitRelease.selector;
        selectors[8] = IMLOProfitShareFacet.mloBucketProfitReward.selector;
        selectors[9] = IMLOProfitShareFacet.claimMLOBucketProfitReward.selector;
    }

    function _seniorCapitalSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](9);
        selectors[0] = ISeniorCapitalFacet.depositSeniorCapital.selector;
        selectors[1] = ISeniorCapitalFacet.withdrawPendingSeniorCapital.selector;
        selectors[2] = ISeniorCapitalFacet.activateSeniorCapital.selector;
        selectors[3] = ISeniorCapitalFacet.requestSeniorCapitalExit.selector;
        selectors[4] = ISeniorCapitalFacet.cancelSeniorCapitalExit.selector;
        selectors[5] = ISeniorCapitalFacet.processSeniorCapitalExits.selector;
        selectors[6] = ISeniorCapitalFacet.claimSeniorCapitalFees.selector;
        selectors[7] = ISeniorCapitalFacet.donateSeniorCapitalFees.selector;
        selectors[8] = ISeniorCapitalFacet.claimSeniorCapitalExit.selector;
    }

    function _seniorCapitalViewSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](6);
        selectors[0] = ISeniorCapitalFacet.seniorCapitalState.selector;
        selectors[1] = ISeniorCapitalFacet.seniorCapitalAccount.selector;
        selectors[2] = ISeniorCapitalFacet.seniorCapitalExit.selector;
        selectors[3] = ISeniorCapitalFacet.seniorCapitalBucket.selector;
        selectors[4] = ISeniorCapitalFacet.pendingSeniorCapitalFees.selector;
        selectors[5] = ISeniorCapitalFacet.claimableSeniorCapitalExit.selector;
    }

    function _mloCurveSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = IMLOPredictionAdapterFacet.createMLOCurve.selector;
        selectors[1] = IMLOPredictionAdapterFacet.cancelMLOCurve.selector;
        selectors[2] = IMLOPredictionAdapterFacet.rebalanceMLOAskCurve.selector;
    }

    function _mloPostSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = IMLOPredictionAdapterFacet.postMLOCurve.selector;
        selectors[1] = IMLOPredictionAdapterFacet.postMLOCurvesBatch.selector;
    }

    function _mloUpdateSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = IMLOPredictionAdapterFacet.updateMLOCurve.selector;
        selectors[1] = IMLOPredictionAdapterFacet.updateMLOCurvesBatch.selector;
        selectors[2] = IMLOPredictionAdapterFacet.updateMLOCurveFromNow.selector;
        selectors[3] = IMLOPredictionAdapterFacet.updateMLOCurvesFromNowBatch.selector;
    }

    function _mloTradeSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = IMLOPredictionAdapterFacet.fillMLOAskCurve.selector;
    }

    function _mloAskRouteSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = IMLOPredictionAdapterFacet.executeMLOAskFromRoute.selector;
    }

    function _mloBidTradeSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = IMLOPredictionAdapterFacet.fillMLOBidCurve.selector;
        selectors[1] = IMLOPredictionAdapterFacet.executeMLOBidFromRoute.selector;
    }

    function _mloSettlementSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](7);
        selectors[0] = IMLOPredictionAdapterFacet.settleMLOInventory.selector;
        selectors[1] = IMLOPredictionAdapterFacet.mergeMLOCompleteSet.selector;
        selectors[2] = IMLOPredictionAdapterFacet.executeMLOAskAssetSettlement.selector;
        selectors[3] = IMLOPredictionAdapterFacet.executeMLOBidAssetSettlement.selector;
        selectors[4] = IMLOPredictionAdapterFacet.settleMLOFunding.selector;
        selectors[5] = IMLOPredictionAdapterFacet.prepareMLOAskBacking.selector;
        selectors[6] = IMLOPredictionAdapterFacet.mergeAvailableMLOCompleteSet.selector;
    }

    function _mloRecoverySelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = IMLOPredictionAdapterFacet.mloRecoveryConfig.selector;
        selectors[1] = IMLOPredictionAdapterFacet.setMLORecoveryConfig.selector;
        selectors[2] = IMLOPredictionAdapterFacet.synchronizeMLOBucketState.selector;
        selectors[3] = IMLOPredictionAdapterFacet.cleanupMLOCurves.selector;
    }

    function _bookTradeSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = IBookTradeFacet.fillBookBest.selector;
        selectors[1] = IBookTradeFacet.fillBookBestFor.selector;
    }

    function _bookSellSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = IBookTradeFacet.sellBookBest.selector;
        selectors[1] = IBookTradeFacet.sellBookBestFor.selector;
    }

    function _bookOrderSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = IBookOrderFacet.postBookCurve.selector;
        selectors[1] = IBookOrderFacet.postBookCurvesBatch.selector;
        selectors[2] = IBookOrderFacet.topUpBookCurvesBatch.selector;
        selectors[3] = IBookOrderFacet.reactivateBookCurve.selector;
    }

    function _ownershipSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = OwnershipFacet.setMarketCreationBond.selector;
    }

    function _negRiskConfigSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = NegRiskConfigFacet.setNegRiskAdapter.selector;
    }

    function _mloResolutionSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = IOBRResolutionFacet.settleMarketEarly.selector;
        selectors[1] = IOBRResolutionFacet.adminFinalizeResolution.selector;
    }

    function _marketStateSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = MarketFactoryFacet.syncMarketState.selector;
        selectors[1] = bytes4(keccak256("createMarket(string,string,string,uint64,uint64,uint128,bool)"));
    }

    function _multiOutcomeSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = IMultiOutcomeOrderbookFacet.createMultiOutcomeMarket.selector;
        selectors[1] = IMultiOutcomeOrderbookFacet.splitOutcomeSet.selector;
        selectors[2] = IMultiOutcomeOrderbookFacet.mergeOutcomeSet.selector;
        selectors[3] = IMultiOutcomeOrderbookFacet.redeemOutcome.selector;
    }

    function _multiOutcomeViewSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = IMultiOutcomeOrderbookFacet.getMultiOutcomeMarket.selector;
        selectors[1] = IMultiOutcomeOrderbookFacet.getOutcomePositionId.selector;
    }

    function _tradeRouterBookSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = ITradeRouterBook.buyBookWithCollateral.selector;
    }

    function _tradeRouterBookSellSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = ITradeRouterBook.sellBookWithCollateral.selector;
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
