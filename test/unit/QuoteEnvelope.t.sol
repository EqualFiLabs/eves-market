// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {EveUSDC} from "../../src/EveUSDC.sol";
import {BookFacet} from "../../src/facets/BookFacet.sol";
import {BookOrderFacet} from "../../src/facets/BookOrderFacet.sol";
import {BookTradeFacet} from "../../src/facets/BookTradeFacet.sol";
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
import {IMarginAccountFacet} from "../../src/interfaces/IMarginAccountFacet.sol";
import {IMarkOracleFacet} from "../../src/interfaces/IMarkOracleFacet.sol";
import {IQuoteEnvelopeFacet} from "../../src/interfaces/IQuoteEnvelopeFacet.sol";
import {LibCLOBBook} from "../../src/libraries/LibCLOBBook.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {CurveCLOBTypes} from "../../src/types/CurveCLOBTypes.sol";
import {MarginTypes} from "../../src/types/MarginTypes.sol";
import {MarkOracleTypes} from "../../src/types/MarkOracleTypes.sol";
import {QuoteEnvelopeTypes} from "../../src/types/QuoteEnvelopeTypes.sol";
import {MockUSDC} from "../helpers/MockUSDC.sol";
import {ITestStateFacet, TestBase} from "../helpers/TestBase.sol";

contract QuoteEnvelopeTest is TestBase {
    uint128 internal constant PRICE_DENOMINATOR = 1_000_000_000;
    uint128 internal constant FORTY_CENTS = 400_000_000;
    uint128 internal constant SIXTY_CENTS = 600_000_000;
    uint128 internal constant SEVENTY_CENTS = 700_000_000;
    uint128 internal constant ONE_HUNDRED_SHARES = 100e18;
    bytes32 internal constant SPOT_SALT = keccak256("quote-envelope-spot-book");

    EveUSDC internal eveUSDC;
    MockUSDC internal spotToken;
    address internal riskManager;
    bytes32 internal marketId;
    bytes32 internal yesBookId;
    bytes32 internal bucketId;

    function setUp() public override {
        super.setUp();

        riskManager = makeAddr("riskManager");
        eveUSDC = new EveUSDC(address(usdc), makeAddr("onramp"), makeAddr("offramp"));
        spotToken = new MockUSDC();
        spotToken.mint(maker, 1_000_000e6);
        spotToken.mint(taker, 1_000_000e6);

        vm.startPrank(owner);
        diamond.registerFacet(address(new MarginAccountFacet()), _marginSelectors());
        diamond.registerFacet(address(new QuoteEnvelopeFacet()), _quoteEnvelopeSelectors());
        IMarginAccountFacet(address(diamond)).setMarginAsset(address(eveUSDC));
        IMarginAccountFacet(address(diamond)).setMarginRiskManager(riskManager);
        ITestStateFacet(address(diamond))
            .configure(address(conditionalTokens), address(eveUSDC), address(eveToken), treasury);
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
        assertEq(envelope.reservedRisk, 60e18);
        assertEq(bucket.reservedRisk, 60e18);
        assertEq(bucket.openOrderRisk, 60e18);
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
        assertEq(envelope.reservedRisk, 60e18);
        assertEq(bucket.reservedRisk, 60e18);
        assertEq(bucket.openOrderRisk, 60e18);

        vm.prank(maker);
        IQuoteEnvelopeFacet(address(diamond)).cancelQuoteEnvelope(envelopeId);

        envelope = IQuoteEnvelopeFacet(address(diamond)).getQuoteEnvelope(envelopeId);
        bucket = IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId);
        assertFalse(envelope.active);
        assertFalse(envelope.canUpdate);
        assertEq(envelope.currentVolume, 0);
        assertEq(envelope.reservedRisk, 0);
        assertEq(bucket.reservedRisk, 0);
        assertEq(bucket.openOrderRisk, 0);
    }

    function test_AskEnvelopeRiskUsesComplementOfMinimumPrice() public {
        uint256 envelopeId = _createEnvelope(LibEveMarket.CurveSide.ASK);

        QuoteEnvelopeTypes.QuoteEnvelopeView memory envelope =
            IQuoteEnvelopeFacet(address(diamond)).getQuoteEnvelope(envelopeId);
        MarginTypes.MarginBucket memory bucket = IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId);

        assertEq(envelope.reservedRisk, 60e18);
        assertEq(bucket.reservedRisk, 60e18);
        assertEq(bucket.openOrderRisk, 60e18);
    }

    function test_ConfiguredOracleGateBlocksRiskIncreasingEnvelope() public {
        bytes32 riskDomain = IMarginAccountFacet(address(diamond)).riskDomainForMarketBook(marketId, yesBookId);

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
                IMarginAccountFacet.RiskDomainOracleBlocked.selector,
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

        _wrapEveUSDC(maker, 100e6);
        vm.startPrank(maker);
        eveUSDC.approve(address(diamond), 100e18);
        IMarginAccountFacet(address(diamond)).depositMargin(100e18, maker);
        wrongBucketId = IMarginAccountFacet(address(diamond)).allocateBucketMargin(wrongDomain, 100e18);
        vm.stopPrank();

        QuoteEnvelopeTypes.CreateQuoteEnvelopeParams memory params = _defaultEnvelope(LibEveMarket.CurveSide.BID);
        params.bucketId = wrongBucketId;

        vm.expectRevert(
            abi.encodeWithSelector(
                IQuoteEnvelopeFacet.QuoteEnvelopeRiskDomainMismatch.selector,
                wrongBucketId,
                IMarginAccountFacet(address(diamond)).riskDomainForMarketBook(marketId, yesBookId),
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

    function test_UpdateRejectsOutOfBoundsAndBlockedBucket() public {
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

        vm.expectRevert(
            abi.encodeWithSelector(
                IMarginAccountFacet.BucketCannotIncreaseRisk.selector, bucketId, MarginTypes.BucketState.ReduceOnly
            )
        );
        vm.prank(maker);
        IQuoteEnvelopeFacet(address(diamond))
            .updateQuoteEnvelope(
                envelopeId,
                QuoteEnvelopeTypes.QuoteEnvelopeUpdate({volume: 50e18, startPrice: FORTY_CENTS, endPrice: SIXTY_CENTS})
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
        _wrapEveUSDC(operator, assets / 1e12);

        bytes32 riskDomain = IMarginAccountFacet(address(diamond)).riskDomainForMarketBook(marketId, yesBookId);
        vm.startPrank(operator);
        eveUSDC.approve(address(diamond), assets);
        IMarginAccountFacet(address(diamond)).depositMargin(assets, operator);
        bucketId = IMarginAccountFacet(address(diamond)).allocateBucketMargin(riskDomain, assets);
        vm.stopPrank();
    }

    function _wrapEveUSDC(address account, uint256 usdcAmount) internal {
        usdc.mint(account, usdcAmount);

        vm.startPrank(account);
        usdc.approve(address(eveUSDC), usdcAmount);
        eveUSDC.wrap(usdcAmount, account);
        vm.stopPrank();
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
        selectors[5] = IQuoteEnvelopeFacet.getOperatorQuoteEnvelopes.selector;
        selectors[6] = IQuoteEnvelopeFacet.getBookQuoteEnvelopes.selector;
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
        selectors = new bytes4[](2);
        selectors[0] = IBookTradeFacet.sellBookBest.selector;
        selectors[1] = IBookTradeFacet.fillBookBest.selector;
    }

    function _bookViewSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = IBookViewFacet.previewBookExecution.selector;
        selectors[1] = IBookViewFacet.getBookTopOfBook.selector;
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
