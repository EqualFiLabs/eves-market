// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {MockCollateral} from "../helpers/MockCollateral.sol";
import {BookFacet} from "../../src/facets/BookFacet.sol";
import {BookOrderFacet} from "../../src/facets/BookOrderFacet.sol";
import {BookTradeFacet} from "../../src/facets/BookTradeFacet.sol";
import {BookSellFacet} from "../../src/facets/BookSellFacet.sol";
import {BookViewFacet} from "../../src/facets/BookViewFacet.sol";
import {CurveCLOBFacet} from "../../src/facets/CurveCLOBFacet.sol";
import {CurveInventoryFacet} from "../../src/facets/CurveInventoryFacet.sol";
import {CurveLifecycleFacet} from "../../src/facets/CurveLifecycleFacet.sol";
import {CurveViewFacet} from "../../src/facets/CurveViewFacet.sol";
import {MarginAccountFacet} from "../../src/facets/MarginAccountFacet.sol";
import {MarkOracleFacet} from "../../src/facets/MarkOracleFacet.sol";
import {QuoteEnvelopeFacet} from "../../src/facets/QuoteEnvelopeFacet.sol";
import {IBookAdminFacet} from "../../src/interfaces/IBookAdminFacet.sol";
import {IBookOrderFacet} from "../../src/interfaces/IBookOrderFacet.sol";
import {IBookTradeFacet} from "../../src/interfaces/IBookTradeFacet.sol";
import {IBookViewFacet} from "../../src/interfaces/IBookViewFacet.sol";
import {ICurveInventoryFacet} from "../../src/interfaces/ICurveInventoryFacet.sol";
import {ICurveLifecycleFacet} from "../../src/interfaces/ICurveLifecycleFacet.sol";
import {ICurveTradeFacet} from "../../src/interfaces/ICurveTradeFacet.sol";
import {ICurveViewFacet} from "../../src/interfaces/ICurveViewFacet.sol";
import {IMarkOracleFacet} from "../../src/interfaces/IMarkOracleFacet.sol";
import {IMarginAccountFacet as IProductionMarginAccountFacet} from "../../src/interfaces/IMarginAccountFacet.sol";
import {IQuoteEnvelopeFacet} from "../../src/interfaces/IQuoteEnvelopeFacet.sol";
import {LibCLOBBook} from "../../src/libraries/LibCLOBBook.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {CurveCLOBTypes} from "../../src/types/CurveCLOBTypes.sol";
import {MarginTypes} from "../../src/types/MarginTypes.sol";
import {MarkOracleTypes} from "../../src/types/MarkOracleTypes.sol";
import {QuoteEnvelopeTypes} from "../../src/types/QuoteEnvelopeTypes.sol";
import {MockUSDC} from "../helpers/MockUSDC.sol";
import {ITestStateFacet, TestBase} from "../helpers/TestBase.sol";
import {
    IMarginTestFacet as IMarginAccountFacet,
    MarginAccountingHarnessFacet,
    MarginAccountingHarnessSelectors
} from "../helpers/MarginAccountingHarnessFacet.sol";

contract QuoteEnvelopeTest is TestBase {
    uint128 internal constant PRICE_DENOMINATOR = 1_000_000_000;
    uint128 internal constant FORTY_CENTS = 400_000_000;
    uint128 internal constant SIXTY_CENTS = 600_000_000;
    uint128 internal constant SEVENTY_CENTS = 700_000_000;
    uint128 internal constant ONE_HUNDRED_SHARES = 100e18;
    bytes32 internal constant SPOT_SALT = keccak256("quote-envelope-spot-book");

    MockCollateral internal collateral;
    MockUSDC internal spotToken;
    address internal riskManager;
    bytes32 internal marketId;
    bytes32 internal yesBookId;
    bytes32 internal bucketId;

    function setUp() public override {
        super.setUp();

        riskManager = makeAddr("riskManager");
        collateral = new MockCollateral();
        spotToken = new MockUSDC();
        spotToken.mint(maker, 1_000_000e6);
        spotToken.mint(taker, 1_000_000e6);

        vm.startPrank(owner);
        diamond.registerFacet(address(new MarginAccountFacet()), _marginSelectors());
        diamond.registerFacet(address(new MarginAccountingHarnessFacet()), MarginAccountingHarnessSelectors.harness());
        diamond.registerFacet(address(new QuoteEnvelopeFacet()), _quoteEnvelopeSelectors());
        IMarginAccountFacet(address(diamond)).setMarginAsset(address(collateral));
        ITestStateFacet(address(diamond))
            .configure(address(conditionalTokens), address(collateral), address(eveToken), treasury);
        vm.stopPrank();

        (marketId,) = _createMarketFixture("Does quote envelope reserve risk?", _expiry(7 days));
        ITestStateFacet(address(diamond)).materializeMarketSideBookFixture(marketId, true);
        yesBookId = LibCLOBBook.marketBookId(marketId, true);

        _depositAndAllocate(maker, 250e18);
    }

    function test_CreateUpdateAndCancelEnvelope() public {
        uint256 envelopeId = _createEnvelope(LibEveMarket.CurveSide.BID);

        QuoteEnvelopeTypes.QuoteEnvelopeView memory envelope =
            IQuoteEnvelopeFacet(address(diamond)).getQuoteEnvelope(envelopeId);
        MarginTypes.MarginBucket memory bucket = IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId);

        assertEq(envelope.operator, maker);
        assertEq(envelope.bucketId, bucketId);
        assertEq(envelope.bookId, yesBookId);
        assertEq(envelope.maxVolume, ONE_HUNDRED_SHARES);
        assertEq(envelope.reservedRisk, 30e18);
        assertEq(envelope.remainingRiskVolume, 50e18);
        assertEq(bucket.reservedRisk, 30e18);
        assertEq(bucket.openOrderRisk, 30e18);
        assertTrue(envelope.canUpdate);

        vm.prank(maker);
        uint32 generation = IQuoteEnvelopeFacet(address(diamond))
            .updateQuoteEnvelope(
                envelopeId,
                QuoteEnvelopeTypes.QuoteEnvelopeUpdate({volume: 80e18, startPrice: FORTY_CENTS, endPrice: SIXTY_CENTS})
            );
        assertEq(generation, 2);

        envelope = IQuoteEnvelopeFacet(address(diamond)).getQuoteEnvelope(envelopeId);
        bucket = IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId);
        assertEq(envelope.currentVolume, 80e18);
        assertEq(envelope.currentStartPrice, FORTY_CENTS);
        assertEq(envelope.currentEndPrice, SIXTY_CENTS);
        assertEq(envelope.reservedRisk, 48e18);
        assertEq(envelope.remainingRiskVolume, 80e18);
        assertEq(bucket.reservedRisk, 48e18);
        assertEq(bucket.openOrderRisk, 48e18);

        vm.prank(maker);
        IQuoteEnvelopeFacet(address(diamond)).cancelQuoteEnvelope(envelopeId);

        envelope = IQuoteEnvelopeFacet(address(diamond)).getQuoteEnvelope(envelopeId);
        bucket = IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId);
        assertFalse(envelope.active);
        assertFalse(envelope.canUpdate);
        assertEq(envelope.currentVolume, 0);
        assertEq(envelope.reservedRisk, 0);
        assertEq(envelope.remainingRiskVolume, 0);
        assertEq(bucket.reservedRisk, 0);
        assertEq(bucket.openOrderRisk, 0);
    }

    function test_AskEnvelopeRiskUsesComplementOfMinimumPrice() public {
        uint256 envelopeId = _createEnvelope(LibEveMarket.CurveSide.ASK);

        QuoteEnvelopeTypes.QuoteEnvelopeView memory envelope =
            IQuoteEnvelopeFacet(address(diamond)).getQuoteEnvelope(envelopeId);
        MarginTypes.MarginBucket memory bucket = IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId);

        assertEq(envelope.reservedRisk, 30e18);
        assertEq(bucket.reservedRisk, 30e18);
        assertEq(bucket.openOrderRisk, 30e18);
    }

    function test_PreviewAndCreateRejectInitialVolumeAboveMaximum() public {
        QuoteEnvelopeTypes.CreateQuoteEnvelopeParams memory params = _defaultEnvelope(LibEveMarket.CurveSide.BID);
        params.initialVolume = ONE_HUNDRED_SHARES + 1;
        bytes memory expected = abi.encodeWithSelector(
            IQuoteEnvelopeFacet.InvalidQuoteEnvelopeVolume.selector, params.initialVolume, params.maxVolume
        );

        vm.expectRevert(expected);
        IQuoteEnvelopeFacet(address(diamond)).previewQuoteEnvelopeRisk(params);

        vm.prank(maker);
        vm.expectRevert(expected);
        IQuoteEnvelopeFacet(address(diamond)).createQuoteEnvelope(params);
    }

    function test_PreviewAndCreateRejectZeroInitialVolume() public {
        QuoteEnvelopeTypes.CreateQuoteEnvelopeParams memory params = _defaultEnvelope(LibEveMarket.CurveSide.BID);
        params.initialVolume = 0;
        bytes memory expected = abi.encodeWithSelector(
            IQuoteEnvelopeFacet.InvalidQuoteEnvelopeVolume.selector, params.initialVolume, params.maxVolume
        );

        vm.expectRevert(expected);
        IQuoteEnvelopeFacet(address(diamond)).previewQuoteEnvelopeRisk(params);

        vm.prank(maker);
        vm.expectRevert(expected);
        IQuoteEnvelopeFacet(address(diamond)).createQuoteEnvelope(params);
    }

    function test_PreviewAndCreateAcceptInitialVolumeAtMaximum() public {
        QuoteEnvelopeTypes.CreateQuoteEnvelopeParams memory params = _defaultEnvelope(LibEveMarket.CurveSide.BID);
        params.initialVolume = params.maxVolume;

        uint256 previewedRisk = IQuoteEnvelopeFacet(address(diamond)).previewQuoteEnvelopeRisk(params);
        vm.prank(maker);
        uint256 envelopeId = IQuoteEnvelopeFacet(address(diamond)).createQuoteEnvelope(params);

        QuoteEnvelopeTypes.QuoteEnvelopeView memory envelope =
            IQuoteEnvelopeFacet(address(diamond)).getQuoteEnvelope(envelopeId);
        assertEq(envelope.currentVolume, envelope.maxVolume);
        assertEq(envelope.reservedRisk, previewedRisk);
    }

    function test_EnvelopeHistoryReadsArePaginatedAndBounded() public {
        uint256 first = _createEnvelope(LibEveMarket.CurveSide.ASK);
        uint256 second = _createEnvelope(LibEveMarket.CurveSide.BID);

        (uint256[] memory firstPage, uint256 nextCursor, uint256 total) =
            IQuoteEnvelopeFacet(address(diamond)).getOperatorQuoteEnvelopesPage(maker, 0, 1);
        assertEq(firstPage.length, 1);
        assertEq(firstPage[0], first);
        assertEq(nextCursor, 1);
        assertEq(total, 2);

        (uint256[] memory secondPage, uint256 finalCursor, uint256 bookTotal) =
            IQuoteEnvelopeFacet(address(diamond)).getBookQuoteEnvelopesPage(yesBookId, nextCursor, 1);
        assertEq(secondPage.length, 1);
        assertEq(secondPage[0], second);
        assertEq(finalCursor, 2);
        assertEq(bookTotal, 2);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidPageSize.selector, 0, 128));
        IQuoteEnvelopeFacet(address(diamond)).getOperatorQuoteEnvelopesPage(maker, 0, 0);
    }

    function test_ScenarioRequirementControlsMarginRelease() public {
        _createEnvelope(LibEveMarket.CurveSide.ASK);

        vm.prank(maker);
        IMarginAccountFacet(address(diamond)).releaseBucketMargin(bucketId, 220e18);
        assertEq(IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId).marginAllocated, 30e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                IProductionMarginAccountFacet.BucketBelowInitialMargin.selector, bucketId, 29e18, 30e18
            )
        );
        vm.prank(maker);
        IMarginAccountFacet(address(diamond)).releaseBucketMargin(bucketId, 1e18);
    }

    function test_RevertWhen_GenericScalarMutationTargetsScenarioBucket() public {
        _createEnvelope(LibEveMarket.CurveSide.ASK);

        vm.expectRevert(abi.encodeWithSelector(IProductionMarginAccountFacet.ScenarioManagedBucket.selector, bucketId));
        vm.prank(riskManager);
        IMarginAccountFacet(address(diamond)).increaseOpenOrderRisk(bucketId, 1e18);
    }

    function test_RevertWhen_EnvelopeUsesNonMLOBucket() public {
        _fundCollateral(taker, 100e6);
        bytes32 riskDomain = IMarginAccountFacet(address(diamond)).riskDomainForMarket(marketId);
        vm.startPrank(taker);
        collateral.approve(address(diamond), 100e18);
        IMarginAccountFacet(address(diamond)).depositMargin(100e18, taker);
        bytes32 genericBucket = IMarginAccountFacet(address(diamond))
            .allocateBucketMarginWithKind(riskDomain, 100e18, MarginTypes.BucketKind.PredictionTrader, 0);
        QuoteEnvelopeTypes.CreateQuoteEnvelopeParams memory params = _defaultEnvelope(LibEveMarket.CurveSide.ASK);
        params.bucketId = genericBucket;
        vm.expectRevert(
            abi.encodeWithSelector(
                IQuoteEnvelopeFacet.QuoteEnvelopeBucketKindMismatch.selector,
                genericBucket,
                MarginTypes.BucketKind.PredictionTrader
            )
        );
        IQuoteEnvelopeFacet(address(diamond)).createQuoteEnvelope(params);
        vm.stopPrank();
    }

    function test_ConfiguredOracleGateBlocksRiskIncreasingEnvelope() public {
        bytes32 riskDomain = IMarginAccountFacet(address(diamond)).riskDomainForMarket(marketId);

        vm.startPrank(owner);
        diamond.registerFacet(address(new MarkOracleFacet()), _markOracleSelectors());
        IMarginAccountFacet(address(diamond))
            .setRiskDomainOracleConfig(riskDomain, MarginTypes.RiskDomainOracleKind.BookMark, yesBookId);
        IMarkOracleFacet(address(diamond)).setMarkOracleManualState(yesBookId, MarkOracleTypes.OracleState.Paused);
        vm.stopPrank();

        assertFalse(IMarginAccountFacet(address(diamond)).canBucketIncreaseRiskForBook(bucketId, yesBookId));

        QuoteEnvelopeTypes.CreateQuoteEnvelopeParams memory params = _defaultEnvelope(LibEveMarket.CurveSide.BID);
        vm.expectRevert(
            abi.encodeWithSelector(
                IProductionMarginAccountFacet.RiskDomainOracleBlocked.selector,
                riskDomain,
                yesBookId,
                MarginTypes.RiskDomainOracleKind.BookMark,
                uint8(MarkOracleTypes.OracleState.Paused)
            )
        );
        vm.prank(maker);
        IQuoteEnvelopeFacet(address(diamond)).createQuoteEnvelope(params);
    }

    function test_CreateRejectsWrongOperatorAndWrongRiskDomain() public {
        bytes32 wrongDomain = IMarginAccountFacet(address(diamond)).riskDomainForBook(yesBookId);
        bytes32 wrongBucketId;

        _fundCollateral(maker, 100e6);
        vm.startPrank(maker);
        collateral.approve(address(diamond), 100e18);
        IMarginAccountFacet(address(diamond)).depositMargin(100e18, maker);
        wrongBucketId = IMarginAccountFacet(address(diamond)).allocateBucketMargin(wrongDomain, 100e18, 1);
        vm.stopPrank();

        QuoteEnvelopeTypes.CreateQuoteEnvelopeParams memory params = _defaultEnvelope(LibEveMarket.CurveSide.BID);
        params.bucketId = wrongBucketId;

        vm.expectRevert(
            abi.encodeWithSelector(
                IQuoteEnvelopeFacet.QuoteEnvelopeRiskDomainMismatch.selector,
                wrongBucketId,
                IMarginAccountFacet(address(diamond)).riskDomainForMarket(marketId),
                wrongDomain
            )
        );
        vm.prank(maker);
        IQuoteEnvelopeFacet(address(diamond)).createQuoteEnvelope(params);

        params.bucketId = bucketId;
        vm.expectRevert(abi.encodeWithSelector(IQuoteEnvelopeFacet.NotQuoteEnvelopeOperator.selector, taker, maker));
        vm.prank(taker);
        IQuoteEnvelopeFacet(address(diamond)).createQuoteEnvelope(params);
    }

    function test_UpdateRejectsOutOfBoundsAndOnlyBlocksRiskIncrease() public {
        uint256 envelopeId = _createEnvelope(LibEveMarket.CurveSide.BID);

        vm.expectRevert(
            abi.encodeWithSelector(IQuoteEnvelopeFacet.InvalidQuoteEnvelopeVolume.selector, 101e18, ONE_HUNDRED_SHARES)
        );
        vm.prank(maker);
        IQuoteEnvelopeFacet(address(diamond))
            .updateQuoteEnvelope(
                envelopeId,
                QuoteEnvelopeTypes.QuoteEnvelopeUpdate({volume: 101e18, startPrice: FORTY_CENTS, endPrice: SIXTY_CENTS})
            );

        vm.expectRevert(
            abi.encodeWithSelector(
                IQuoteEnvelopeFacet.QuoteEnvelopePriceOutOfBounds.selector, SEVENTY_CENTS, FORTY_CENTS, SIXTY_CENTS
            )
        );
        vm.prank(maker);
        IQuoteEnvelopeFacet(address(diamond))
            .updateQuoteEnvelope(
                envelopeId,
                QuoteEnvelopeTypes.QuoteEnvelopeUpdate({
                    volume: 50e18, startPrice: SEVENTY_CENTS, endPrice: SIXTY_CENTS
                })
            );

        vm.prank(riskManager);
        IMarginAccountFacet(address(diamond)).setBucketState(bucketId, MarginTypes.BucketState.ReduceOnly);

        vm.prank(maker);
        IQuoteEnvelopeFacet(address(diamond))
            .updateQuoteEnvelope(
                envelopeId,
                QuoteEnvelopeTypes.QuoteEnvelopeUpdate({volume: 40e18, startPrice: FORTY_CENTS, endPrice: SIXTY_CENTS})
            );
        assertEq(IQuoteEnvelopeFacet(address(diamond)).getQuoteEnvelope(envelopeId).remainingRiskVolume, 40e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                IProductionMarginAccountFacet.BucketCannotIncreaseRisk.selector,
                bucketId,
                MarginTypes.BucketState.ReduceOnly
            )
        );
        vm.prank(maker);
        IQuoteEnvelopeFacet(address(diamond))
            .updateQuoteEnvelope(
                envelopeId,
                QuoteEnvelopeTypes.QuoteEnvelopeUpdate({volume: 80e18, startPrice: FORTY_CENTS, endPrice: SIXTY_CENTS})
            );
    }

    function test_CancelRejectsNonOperatorAndInactiveEnvelope() public {
        uint256 envelopeId = _createEnvelope(LibEveMarket.CurveSide.BID);

        vm.expectRevert(abi.encodeWithSelector(IQuoteEnvelopeFacet.NotQuoteEnvelopeOperator.selector, taker, maker));
        vm.prank(taker);
        IQuoteEnvelopeFacet(address(diamond)).cancelQuoteEnvelope(envelopeId);

        vm.prank(maker);
        IQuoteEnvelopeFacet(address(diamond)).cancelQuoteEnvelope(envelopeId);

        vm.expectRevert(abi.encodeWithSelector(IQuoteEnvelopeFacet.QuoteEnvelopeInactive.selector, envelopeId));
        vm.prank(maker);
        IQuoteEnvelopeFacet(address(diamond)).cancelQuoteEnvelope(envelopeId);
    }

    function test_RejectsGenericSpotBookAndExistingCLOBStillFills() public {
        vm.startPrank(owner);
        diamond.registerFacet(address(new BookFacet()), _bookSelectors());
        diamond.registerFacet(address(new BookOrderFacet()), _bookOrderSelectors());
        diamond.registerFacet(address(new BookTradeFacet()), _bookTradeSelectors());
        diamond.registerFacet(address(new BookSellFacet()), _bookSellSelectors());
        diamond.registerFacet(address(new BookViewFacet()), _bookViewSelectors());
        diamond.registerFacet(address(new CurveInventoryFacet()), _curveInventorySelectors());
        diamond.registerFacet(address(new CurveLifecycleFacet()), _curveLifecycleSelectors());
        diamond.registerFacet(address(new CurveCLOBFacet()), _curveTradeSelectors());
        diamond.registerFacet(address(new CurveViewFacet()), _curveViewSelectors());
        vm.stopPrank();

        bytes32 spotBookId = _createSpotBook();
        QuoteEnvelopeTypes.CreateQuoteEnvelopeParams memory params = _defaultEnvelope(LibEveMarket.CurveSide.BID);
        params.bookId = spotBookId;

        vm.expectRevert(abi.encodeWithSelector(IQuoteEnvelopeFacet.UnsupportedQuoteEnvelopeBook.selector, spotBookId));
        vm.prank(maker);
        IQuoteEnvelopeFacet(address(diamond)).createQuoteEnvelope(params);

        uint256 curveId = _postSpotAsk(spotBookId, 100e6, 2e18);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        vm.startPrank(taker);
        usdc.approve(address(diamond), 200e6);
        uint128 baseOut = ICurveTradeFacet(address(diamond)).fillCurve(curveId, 200e6, 100e6, generation, commitment);
        vm.stopPrank();

        assertEq(baseOut, 100e6);
        assertEq(spotToken.balanceOf(taker), 1_000_100e6);
        assertEq(usdc.balanceOf(maker), 1_000_200e6);
    }

    function _createEnvelope(LibEveMarket.CurveSide side) internal returns (uint256 envelopeId) {
        QuoteEnvelopeTypes.CreateQuoteEnvelopeParams memory params = _defaultEnvelope(side);
        vm.prank(maker);
        envelopeId = IQuoteEnvelopeFacet(address(diamond)).createQuoteEnvelope(params);
    }

    function _defaultEnvelope(LibEveMarket.CurveSide side)
        internal
        view
        returns (QuoteEnvelopeTypes.CreateQuoteEnvelopeParams memory params)
    {
        params = QuoteEnvelopeTypes.CreateQuoteEnvelopeParams({
            bucketId: bucketId,
            bookId: yesBookId,
            side: uint8(side),
            maxVolume: ONE_HUNDRED_SHARES,
            minPrice: FORTY_CENTS,
            maxPrice: SIXTY_CENTS,
            initialVolume: 50e18,
            initialStartPrice: FORTY_CENTS,
            initialEndPrice: SIXTY_CENTS,
            expiresAt: uint64(block.timestamp + 1 hours)
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

    function _fundCollateral(address account, uint256 usdcAmount) internal {
        collateral.mint(account, usdcAmount * 1e12);
    }

    function _createSpotBook() internal returns (bytes32 bookId) {
        vm.prank(maker);
        bookId = IBookAdminFacet(address(diamond))
            .createBook(
                LibEveMarket.BookAssetType.ERC20,
                LibEveMarket.BaseTransferMode.EXACT,
                address(spotToken),
                0,
                address(usdc),
                0,
                SPOT_SALT
            );
    }

    function _postSpotAsk(bytes32 bookId, uint128 volume, uint72 price) internal returns (uint256 curveId) {
        vm.startPrank(maker);
        spotToken.approve(address(diamond), volume);
        curveId = IBookOrderFacet(address(diamond))
            .postBookCurve(bookId, LibEveMarket.CurveSide.ASK, volume, price, price, 120, 0, type(uint8).max);
        vm.stopPrank();
    }

    function _expiry(uint256 duration) internal view returns (uint64) {
        return uint64(block.timestamp + duration);
    }

    function _marginSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = MarginAccountingHarnessSelectors.production();
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

    function _bookSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](5);
        selectors[0] = IBookAdminFacet.createBook.selector;
        selectors[1] = IBookAdminFacet.computeBookId.selector;
        selectors[2] = IBookAdminFacet.getBookInfo.selector;
        selectors[3] = IBookAdminFacet.requestBookDecommission.selector;
        selectors[4] = IBookAdminFacet.finalizeBookDecommission.selector;
    }

    function _bookOrderSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = IBookOrderFacet.postBookCurve.selector;
        selectors[1] = IBookOrderFacet.topUpBookCurvesBatch.selector;
        selectors[2] = IBookOrderFacet.reactivateBookCurve.selector;
    }

    function _bookTradeSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = IBookTradeFacet.fillBookBest.selector;
    }

    function _bookSellSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = IBookTradeFacet.sellBookBest.selector;
    }

    function _bookViewSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = IBookViewFacet.previewBookExecution.selector;
        selectors[1] = IBookViewFacet.getBookCurveIdsPage.selector;
        selectors[2] = IBookViewFacet.getActiveBookCurveIdsPage.selector;
        selectors[3] = IBookViewFacet.getBookTopOfBookPage.selector;
    }

    function _curveInventorySelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = ICurveInventoryFacet.splitInventory.selector;
    }

    function _curveLifecycleSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](6);
        selectors[0] = ICurveLifecycleFacet.postCurve.selector;
        selectors[1] = ICurveLifecycleFacet.cancelCurve.selector;
        selectors[2] = ICurveLifecycleFacet.updateCurve.selector;
        selectors[3] = ICurveLifecycleFacet.updateCurvesBatch.selector;
        selectors[4] = ICurveLifecycleFacet.updateCurveFromNow.selector;
        selectors[5] = ICurveLifecycleFacet.updateCurvesFromNowBatch.selector;
    }

    function _curveTradeSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = ICurveTradeFacet.fillCurve.selector;
    }

    function _curveViewSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = ICurveViewFacet.getCurveCommitment.selector;
        selectors[1] = ICurveViewFacet.getCurveInfo.selector;
    }
}
