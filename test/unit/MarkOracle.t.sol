// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {BookFacet} from "../../src/facets/BookFacet.sol";
import {BookOrderFacet} from "../../src/facets/BookOrderFacet.sol";
import {BookTradeFacet} from "../../src/facets/BookTradeFacet.sol";
import {BookViewFacet} from "../../src/facets/BookViewFacet.sol";
import {CurveCLOBFacet} from "../../src/facets/CurveCLOBFacet.sol";
import {CurveInventoryFacet} from "../../src/facets/CurveInventoryFacet.sol";
import {CurveLifecycleFacet} from "../../src/facets/CurveLifecycleFacet.sol";
import {CurveViewFacet} from "../../src/facets/CurveViewFacet.sol";
import {MarkOracleFacet} from "../../src/facets/MarkOracleFacet.sol";
import {TradeRouterSellFacet} from "../../src/facets/TradeRouterSellFacet.sol";
import {IBookAdminFacet} from "../../src/interfaces/IBookAdminFacet.sol";
import {IBookOrderFacet} from "../../src/interfaces/IBookOrderFacet.sol";
import {IBookTradeFacet} from "../../src/interfaces/IBookTradeFacet.sol";
import {IBookViewFacet} from "../../src/interfaces/IBookViewFacet.sol";
import {ICurveInventoryFacet} from "../../src/interfaces/ICurveInventoryFacet.sol";
import {ICurveLifecycleFacet} from "../../src/interfaces/ICurveLifecycleFacet.sol";
import {ICurveTradeFacet} from "../../src/interfaces/ICurveTradeFacet.sol";
import {ICurveViewFacet} from "../../src/interfaces/ICurveViewFacet.sol";
import {IMarkOracleFacet} from "../../src/interfaces/IMarkOracleFacet.sol";
import {ITradeRouter} from "../../src/interfaces/ITradeRouter.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {LibCLOBBook} from "../../src/libraries/LibCLOBBook.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {CurveCLOBTypes} from "../../src/types/CurveCLOBTypes.sol";
import {MarkOracleTypes} from "../../src/types/MarkOracleTypes.sol";
import {MockUSDC} from "../helpers/MockUSDC.sol";
import {TestBase} from "../helpers/TestBase.sol";

contract MarkOracleTest is TestBase {
    uint72 internal constant TWO_USDC = 2e18;
    uint72 internal constant FORTY_CENTS = 400_000_000;
    bytes32 internal constant SPOT_SALT = keccak256("mark-oracle-spot-book");

    MockUSDC internal spotToken;

    function setUp() public override {
        super.setUp();

        spotToken = new MockUSDC();
        spotToken.mint(maker, 1_000_000e6);
        spotToken.mint(taker, 1_000_000e6);

        vm.startPrank(owner);
        diamond.registerFacet(address(new BookFacet()), _bookSelectors());
        diamond.registerFacet(address(new BookOrderFacet()), _bookOrderSelectors());
        diamond.registerFacet(address(new BookTradeFacet()), _bookTradeSelectors());
        diamond.registerFacet(address(new BookViewFacet()), _bookViewSelectors());
        diamond.registerFacet(address(new CurveInventoryFacet()), _curveInventorySelectors());
        diamond.registerFacet(address(new CurveLifecycleFacet()), _curveLifecycleSelectors());
        diamond.registerFacet(address(new CurveCLOBFacet()), _curveTradeSelectors());
        diamond.registerFacet(address(new CurveViewFacet()), _curveViewSelectors());
        diamond.registerFacet(address(new TradeRouterSellFacet()), _tradeRouterSellSelectors());
        diamond.registerFacet(address(new MarkOracleFacet()), _markOracleSelectors());
        vm.stopPrank();
    }

    function test_AskFillInitializesOracleAndConsultsMarks() public {
        bytes32 bookId = _createSpotBook(SPOT_SALT);
        uint256 curveId = _postSpotAsk(bookId, 100e6, TWO_USDC);

        _fillSpotAsk(curveId, 200e6, 100e6);
        vm.warp(block.timestamp + 10);

        MarkOracleTypes.OracleSnapshot memory snapshot = IMarkOracleFacet(address(diamond)).getMarkOracle(bookId);
        assertEq(uint8(snapshot.state), uint8(MarkOracleTypes.OracleState.Normal));
        assertEq(snapshot.lastPrice, TWO_USDC);
        assertEq(snapshot.priceDenominator, 1e18);
        assertEq(snapshot.observationCount, 1);
        assertEq(snapshot.volumeCumulative, 100e6);
        assertEq(snapshot.notionalCumulative, 200e6);

        (uint128 twapPrice, uint32 elapsedSeconds) = IMarkOracleFacet(address(diamond)).consultTwap(bookId, 30);
        (uint128 vwapPrice, uint256 volume) = IMarkOracleFacet(address(diamond)).consultVwap(bookId, 30);

        assertEq(twapPrice, TWO_USDC);
        assertEq(elapsedSeconds, 10);
        assertEq(vwapPrice, TWO_USDC);
        assertEq(volume, 100e6);
    }

    function test_BidFillUpdatesOracle() public {
        bytes32 bookId = _createSpotBook(SPOT_SALT);
        uint256 curveId = _postSpotBid(bookId, 50e6, TWO_USDC);

        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        vm.startPrank(taker);
        spotToken.approve(address(diamond), 25e6);
        IBookTradeFacet(address(diamond))
            .sellBookBest(
                CurveCLOBTypes.SellBookParams({
                    bookId: bookId,
                    maxBaseIn: 25e6,
                    minQuoteOut: 50e6,
                    curveIds: _singleCurve(curveId),
                    expectedGenerations: _singleGeneration(generation),
                    expectedCommitments: _singleCommitment(commitment),
                    receiver: taker
                })
            );
        vm.stopPrank();

        MarkOracleTypes.OracleSnapshot memory snapshot = IMarkOracleFacet(address(diamond)).getMarkOracle(bookId);
        assertEq(snapshot.lastPrice, TWO_USDC);
        assertEq(snapshot.volumeCumulative, 25e6);
        assertEq(snapshot.notionalCumulative, 50e6);
    }

    function test_ComplementSellRecordsSoldSideEffectivePrice() public {
        (bytes32 marketId,) = _createMarketFixture("Does complement selling update NO marks?", _expiry(7 days));
        uint128 shares = 100e6;

        _splitFrom(maker, marketId, shares);
        _splitFrom(taker, marketId, shares);

        vm.startPrank(maker);
        conditionalTokens.setApprovalForAll(address(diamond), true);
        uint256 curveId = ICurveLifecycleFacet(address(diamond))
            .postCurve(marketId, true, shares, FORTY_CENTS, FORTY_CENTS, 120, 0, LibEveMarket.PositionTokenType.CTF);
        vm.stopPrank();

        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        vm.startPrank(taker);
        conditionalTokens.setApprovalForAll(address(diamond), true);
        ITradeRouter(address(diamond))
            .sellWithCollateral(
                ITradeRouter.SellBestParams({
                    marketId: marketId,
                    isYesSide: false,
                    maxSharesIn: shares,
                    minCollateralOut: 60e6,
                    curveIds: _singleCurve(curveId),
                    expectedGenerations: _singleGeneration(generation),
                    expectedCommitments: _singleCommitment(commitment),
                    receiver: taker
                })
            );
        vm.stopPrank();

        bytes32 noBookId = LibCLOBBook.marketBookId(marketId, false);
        MarkOracleTypes.OracleSnapshot memory snapshot = IMarkOracleFacet(address(diamond)).getMarkOracle(noBookId);

        assertEq(snapshot.lastPrice, 600_000_000);
        assertEq(snapshot.volumeCumulative, shares);
        assertEq(snapshot.notionalCumulative, 60e6);
    }

    function test_MultipleFillsInOneBlockCoalesceObservation() public {
        bytes32 bookId = _createSpotBook(SPOT_SALT);
        uint256 curveId = _postSpotAsk(bookId, 100e6, TWO_USDC);

        _fillSpotAsk(curveId, 20e6, 10e6);
        _fillSpotAsk(curveId, 20e6, 10e6);

        MarkOracleTypes.OracleSnapshot memory snapshot = IMarkOracleFacet(address(diamond)).getMarkOracle(bookId);
        MarkOracleTypes.Observation memory observation =
            IMarkOracleFacet(address(diamond)).getMarkObservation(bookId, 0);

        assertEq(snapshot.observationCount, 1);
        assertEq(snapshot.volumeCumulative, 20e6);
        assertEq(snapshot.notionalCumulative, 40e6);
        assertEq(observation.volumeCumulative, 20e6);
        assertEq(observation.notionalCumulative, 40e6);
    }

    function test_RingBufferWrapsAtFixedCardinality() public {
        bytes32 bookId = _createSpotBook(SPOT_SALT);
        uint256 curveId = _postSpotAsk(bookId, 40e6, TWO_USDC);

        vm.startPrank(taker);
        usdc.approve(address(diamond), 80e6);
        for (uint256 index; index < 35; ++index) {
            (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
            ICurveTradeFacet(address(diamond)).fillCurve(curveId, 2e6, 1e6, generation, commitment);
            vm.roll(block.number + 1);
            vm.warp(block.timestamp + 1);
        }
        vm.stopPrank();

        MarkOracleTypes.OracleSnapshot memory snapshot = IMarkOracleFacet(address(diamond)).getMarkOracle(bookId);
        MarkOracleTypes.Observation memory oldest = IMarkOracleFacet(address(diamond)).getMarkObservation(bookId, 0);
        MarkOracleTypes.Observation memory newest = IMarkOracleFacet(address(diamond)).getMarkObservation(bookId, 31);

        assertEq(snapshot.observationCount, 32);
        assertGt(newest.blockNumber, oldest.blockNumber);
        vm.expectRevert(abi.encodeWithSelector(IMarkOracleFacet.MarkOracleObservationNotFound.selector, bookId, 32));
        IMarkOracleFacet(address(diamond)).getMarkObservation(bookId, 32);
    }

    function test_StateTransitionsAndManualOverrides() public {
        bytes32 bookId = _createSpotBook(SPOT_SALT);
        uint256 curveId = _postSpotAsk(bookId, 100e6, TWO_USDC);

        vm.prank(owner);
        IMarkOracleFacet(address(diamond)).setMarkOracleThresholds(10, 20);

        _fillSpotAsk(curveId, 20e6, 10e6);
        assertEq(
            uint8(IMarkOracleFacet(address(diamond)).oracleState(bookId)), uint8(MarkOracleTypes.OracleState.Normal)
        );

        vm.warp(block.timestamp + 11);
        assertEq(
            uint8(IMarkOracleFacet(address(diamond)).oracleState(bookId)), uint8(MarkOracleTypes.OracleState.Caution)
        );

        vm.warp(block.timestamp + 10);
        assertEq(
            uint8(IMarkOracleFacet(address(diamond)).oracleState(bookId)), uint8(MarkOracleTypes.OracleState.Stale)
        );

        vm.prank(owner);
        IMarkOracleFacet(address(diamond)).setMarkOracleManualState(bookId, MarkOracleTypes.OracleState.Paused);
        assertEq(
            uint8(IMarkOracleFacet(address(diamond)).oracleState(bookId)), uint8(MarkOracleTypes.OracleState.Paused)
        );

        vm.prank(owner);
        IMarkOracleFacet(address(diamond)).clearMarkOracleManualState(bookId);
        assertEq(
            uint8(IMarkOracleFacet(address(diamond)).oracleState(bookId)), uint8(MarkOracleTypes.OracleState.Stale)
        );
    }

    function test_RevertWhen_NonOwnerSetsOracleConfig() public {
        bytes32 bookId = _createSpotBook(SPOT_SALT);

        vm.prank(taker);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotContractOwner.selector, taker));
        IMarkOracleFacet(address(diamond)).setMarkOracleThresholds(10, 20);

        vm.prank(taker);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotContractOwner.selector, taker));
        IMarkOracleFacet(address(diamond)).setMarkOracleManualState(bookId, MarkOracleTypes.OracleState.Paused);
    }

    function test_RevertWhen_InvalidOracleConfig() public {
        bytes32 bookId = _createSpotBook(SPOT_SALT);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IMarkOracleFacet.InvalidOracleThresholds.selector, 20, 10));
        IMarkOracleFacet(address(diamond)).setMarkOracleThresholds(20, 10);

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMarkOracleFacet.InvalidOracleManualState.selector, uint8(MarkOracleTypes.OracleState.Normal)
            )
        );
        IMarkOracleFacet(address(diamond)).setMarkOracleManualState(bookId, MarkOracleTypes.OracleState.Normal);
    }

    function test_UninitializedBookStateIsExposed() public {
        bytes32 bookId = _createSpotBook(SPOT_SALT);

        MarkOracleTypes.OracleSnapshot memory snapshot = IMarkOracleFacet(address(diamond)).getMarkOracle(bookId);
        assertEq(uint8(snapshot.state), uint8(MarkOracleTypes.OracleState.Uninitialized));
        assertEq(snapshot.lastPrice, 0);
        assertEq(snapshot.observationCount, 0);
    }

    function test_RiskMarkAppliesConservativeSpotHaircutAndPremium() public {
        bytes32 bookId = _createSpotBook(SPOT_SALT);
        uint256 curveId = _postSpotAsk(bookId, 100e6, TWO_USDC);

        _fillSpotAsk(curveId, 200e6, 100e6);

        MarkOracleTypes.RiskMark memory mark = IMarkOracleFacet(address(diamond))
            .riskMarkForBook(
                bookId,
                MarkOracleTypes.RiskMarkConfig({lookbackSeconds: 0, assetHaircutBps: 2_500, liabilityPremiumBps: 1_000})
            );

        assertEq(uint8(mark.state), uint8(MarkOracleTypes.OracleState.Normal));
        assertEq(mark.displayPrice, TWO_USDC);
        assertEq(mark.assetRiskPrice, 1.5e18);
        assertEq(mark.liabilityRiskPrice, 2.2e18);
    }

    function test_RiskMarkCapsPredictionLiabilityAtPayoutUnit() public {
        (bytes32 marketId,) = _createMarketFixture("Does risk mark cap prediction liability?", _expiry(7 days));
        uint128 shares = 100e6;

        _splitFrom(maker, marketId, shares);
        _splitFrom(taker, marketId, shares);

        vm.startPrank(maker);
        conditionalTokens.setApprovalForAll(address(diamond), true);
        uint256 curveId = ICurveLifecycleFacet(address(diamond))
            .postCurve(marketId, true, shares, FORTY_CENTS, FORTY_CENTS, 120, 0, LibEveMarket.PositionTokenType.CTF);
        vm.stopPrank();

        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        vm.startPrank(taker);
        conditionalTokens.setApprovalForAll(address(diamond), true);
        ITradeRouter(address(diamond))
            .sellWithCollateral(
                ITradeRouter.SellBestParams({
                    marketId: marketId,
                    isYesSide: false,
                    maxSharesIn: shares,
                    minCollateralOut: 60e6,
                    curveIds: _singleCurve(curveId),
                    expectedGenerations: _singleGeneration(generation),
                    expectedCommitments: _singleCommitment(commitment),
                    receiver: taker
                })
            );
        vm.stopPrank();

        bytes32 noBookId = LibCLOBBook.marketBookId(marketId, false);
        MarkOracleTypes.RiskMark memory mark = IMarkOracleFacet(address(diamond))
            .riskMarkForBook(
                noBookId,
                MarkOracleTypes.RiskMarkConfig({lookbackSeconds: 0, assetHaircutBps: 0, liabilityPremiumBps: 10_000})
            );
        MarkOracleTypes.OracleSnapshot memory snapshot = IMarkOracleFacet(address(diamond)).getMarkOracle(noBookId);

        assertEq(mark.displayPrice, 600_000_000);
        assertEq(mark.liabilityRiskPrice, snapshot.priceDenominator);
    }

    function testFuzz_RiskMarkMaintainsConservativeBounds(uint16 haircutSeed, uint16 premiumSeed) public {
        uint16 haircutBps = uint16(bound(haircutSeed, 0, 10_000));
        uint16 premiumBps = uint16(bound(premiumSeed, 0, 10_000));
        bytes32 bookId = _createSpotBook(SPOT_SALT);
        uint256 curveId = _postSpotAsk(bookId, 100e6, TWO_USDC);

        _fillSpotAsk(curveId, 200e6, 100e6);

        MarkOracleTypes.RiskMark memory mark = IMarkOracleFacet(address(diamond))
            .riskMarkForBook(
                bookId,
                MarkOracleTypes.RiskMarkConfig({
                    lookbackSeconds: 0, assetHaircutBps: haircutBps, liabilityPremiumBps: premiumBps
                })
            );

        assertLe(mark.assetRiskPrice, mark.displayPrice);
        assertGe(mark.liabilityRiskPrice, mark.displayPrice);
    }

    function _createSpotBook(bytes32 salt) internal returns (bytes32 bookId) {
        vm.prank(maker);
        bookId = IBookAdminFacet(address(diamond))
            .createBook(
                LibEveMarket.BookAssetType.ERC20,
                LibEveMarket.BaseTransferMode.EXACT,
                address(spotToken),
                0,
                address(usdc),
                0,
                salt
            );
    }

    function _postSpotAsk(bytes32 bookId, uint128 volume, uint72 price) internal returns (uint256 curveId) {
        vm.startPrank(maker);
        spotToken.approve(address(diamond), volume);
        curveId = IBookOrderFacet(address(diamond))
            .postBookCurve(bookId, LibEveMarket.CurveSide.ASK, volume, price, price, 120, 0, type(uint8).max);
        vm.stopPrank();
    }

    function _postSpotBid(bytes32 bookId, uint128 volume, uint72 price) internal returns (uint256 curveId) {
        uint128 quoteEscrow = uint128((uint256(volume) * price) / 1e18);

        vm.startPrank(maker);
        usdc.approve(address(diamond), quoteEscrow);
        curveId = IBookOrderFacet(address(diamond))
            .postBookCurve(bookId, LibEveMarket.CurveSide.BID, volume, price, price, 120, 0, type(uint8).max);
        vm.stopPrank();
    }

    function _fillSpotAsk(uint256 curveId, uint128 quoteIn, uint128 minBaseOut) internal {
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        vm.startPrank(taker);
        usdc.approve(address(diamond), quoteIn);
        ICurveTradeFacet(address(diamond)).fillCurve(curveId, quoteIn, minBaseOut, generation, commitment);
        vm.stopPrank();
    }

    function _splitFrom(address account, bytes32 marketId, uint128 amount) internal {
        vm.startPrank(account);
        usdc.approve(address(diamond), amount);
        ICurveInventoryFacet(address(diamond)).splitInventory(marketId, amount);
        vm.stopPrank();
    }

    function _expiry(uint256 duration) internal view returns (uint64) {
        return uint64(block.timestamp + duration);
    }

    function _singleCurve(uint256 curveId) internal pure returns (uint256[] memory curveIds) {
        curveIds = new uint256[](1);
        curveIds[0] = curveId;
    }

    function _singleGeneration(uint32 generation) internal pure returns (uint32[] memory generations) {
        generations = new uint32[](1);
        generations[0] = generation;
    }

    function _singleCommitment(bytes32 commitment) internal pure returns (bytes32[] memory commitments) {
        commitments = new bytes32[](1);
        commitments[0] = commitment;
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
        selectors = new bytes4[](2);
        selectors[0] = ICurveInventoryFacet.splitInventory.selector;
        selectors[1] = ICurveInventoryFacet.mergeInventory.selector;
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

    function _tradeRouterSellSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = ITradeRouter.sellWithEveUSDC.selector;
        selectors[1] = ITradeRouter.sellWithUSDC.selector;
        selectors[2] = ITradeRouter.previewSellBest.selector;
        selectors[3] = ITradeRouter.sellWithCollateral.selector;
    }

    function _markOracleSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](10);
        selectors[0] = IMarkOracleFacet.getMarkOracle.selector;
        selectors[1] = IMarkOracleFacet.getMarkObservation.selector;
        selectors[2] = IMarkOracleFacet.consultTwap.selector;
        selectors[3] = IMarkOracleFacet.consultVwap.selector;
        selectors[4] = IMarkOracleFacet.oracleState.selector;
        selectors[5] = IMarkOracleFacet.markOracleConfig.selector;
        selectors[6] = IMarkOracleFacet.setMarkOracleThresholds.selector;
        selectors[7] = IMarkOracleFacet.clearMarkOracleManualState.selector;
        selectors[8] = IMarkOracleFacet.setMarkOracleManualState.selector;
        selectors[9] = IMarkOracleFacet.riskMarkForBook.selector;
    }
}
