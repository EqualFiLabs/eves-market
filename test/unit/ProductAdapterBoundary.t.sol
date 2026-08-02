// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {BookFacet} from "../../src/facets/BookFacet.sol";
import {BookOrderFacet} from "../../src/facets/BookOrderFacet.sol";
import {BookTradeFacet} from "../../src/facets/BookTradeFacet.sol";
import {BookSellFacet} from "../../src/facets/BookSellFacet.sol";
import {CurveCLOBFacet} from "../../src/facets/CurveCLOBFacet.sol";
import {CurveInventoryFacet} from "../../src/facets/CurveInventoryFacet.sol";
import {CurveLifecycleFacet} from "../../src/facets/CurveLifecycleFacet.sol";
import {CurveViewFacet} from "../../src/facets/CurveViewFacet.sol";
import {CollateralTradeRouterSellFacet} from "../../src/facets/CollateralTradeRouterSellFacet.sol";
import {CollateralTradeRouterPreviewFacet} from "../../src/facets/CollateralTradeRouterPreviewFacet.sol";
import {MLOPredictionAskRouteFacet} from "../../src/facets/MLOPredictionAskRouteFacet.sol";
import {IBookAdminFacet} from "../../src/interfaces/IBookAdminFacet.sol";
import {IBookOrderFacet} from "../../src/interfaces/IBookOrderFacet.sol";
import {IBookTradeFacet} from "../../src/interfaces/IBookTradeFacet.sol";
import {ICurveInventoryFacet} from "../../src/interfaces/ICurveInventoryFacet.sol";
import {ICurveLifecycleFacet} from "../../src/interfaces/ICurveLifecycleFacet.sol";
import {ICurveTradeFacet} from "../../src/interfaces/ICurveTradeFacet.sol";
import {ICurveViewFacet} from "../../src/interfaces/ICurveViewFacet.sol";
import {IMarginAccountFacet} from "../../src/interfaces/IMarginAccountFacet.sol";
import {IMLOPredictionAdapterFacet} from "../../src/interfaces/IMLOPredictionAdapterFacet.sol";
import {ITradeRouter} from "../../src/interfaces/ITradeRouter.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {LibCLOBBook} from "../../src/libraries/LibCLOBBook.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {CurveCLOBTypes} from "../../src/types/CurveCLOBTypes.sol";
import {ProductAdapterTypes} from "../../src/types/ProductAdapterTypes.sol";
import {MockUSDG} from "../helpers/MockUSDG.sol";
import {ProductAdapterHarnessFacet} from "../helpers/ProductAdapterHarnessFacet.sol";
import {ITestStateFacet, TestBase} from "../helpers/TestBase.sol";

contract ProductAdapterBoundaryTest is TestBase {
    uint72 internal constant TWO_USDC = 2e18;
    uint72 internal constant FORTY_CENTS = 400_000_000;
    bytes32 internal constant SPOT_SALT = keccak256("adapter-boundary-spot-book");
    bytes32 internal constant BUCKET_ID = keccak256("adapter-boundary-bucket");
    bytes32 internal constant RISK_DOMAIN_ID = keccak256("adapter-boundary-risk-domain");
    bytes32 internal constant ADAPTER_DATA_KEY = keccak256("adapter-boundary-data");

    MockUSDG internal spotToken;

    function setUp() public override {
        super.setUp();

        spotToken = new MockUSDG();
        spotToken.mint(maker, 1_000_000e6);
        spotToken.mint(taker, 1_000_000e6);

        vm.startPrank(owner);
        diamond.registerFacet(address(new BookFacet()), _bookSelectors());
        diamond.registerFacet(address(new BookOrderFacet()), _bookOrderSelectors());
        diamond.registerFacet(address(new BookTradeFacet()), _bookTradeSelectors());
        diamond.registerFacet(address(new BookSellFacet()), _bookSellSelectors());
        diamond.registerFacet(address(new CurveInventoryFacet()), _curveInventorySelectors());
        diamond.registerFacet(address(new CurveLifecycleFacet()), _curveLifecycleSelectors());
        diamond.registerFacet(address(new CurveCLOBFacet()), _curveTradeSelectors());
        diamond.registerFacet(address(new CurveViewFacet()), _curveViewSelectors());
        diamond.registerFacet(address(new CollateralTradeRouterSellFacet()), _tradeRouterSellSelectors());
        diamond.registerFacet(address(new CollateralTradeRouterPreviewFacet()), _tradeRouterPreviewSelectors());
        diamond.registerFacet(address(new MLOPredictionAskRouteFacet()), _mloAskRouteSelectors());
        diamond.registerFacet(address(new ProductAdapterHarnessFacet()), _adapterHarnessSelectors());
        vm.stopPrank();
    }

    function test_EscrowCurveMetadataDefaultsToEscrow() public {
        bytes32 bookId = _createSpotBook();
        uint256 curveId = _postSpotAsk(bookId, 100e6, TWO_USDC);

        CurveCLOBTypes.CurveInfo memory info = ICurveViewFacet(address(diamond)).getCurveInfo(curveId);

        assertEq(uint8(info.backingKind), uint8(ProductAdapterTypes.CurveBackingKind.Escrow));
        assertEq(uint8(info.adapterKind), uint8(ProductAdapterTypes.ProductAdapterKind.None));
        assertEq(info.adapterBucketId, bytes32(0));
        assertFalse(info.adapterActive);
    }

    function test_AdapterMetadataIsExposedAndCanBeDisabled() public {
        bytes32 bookId = _createSpotBook();
        uint256 curveId = _postAdapterCurve(bookId, LibEveMarket.CurveSide.ASK, 100e6, 0, TWO_USDC);

        CurveCLOBTypes.CurveInfo memory info = ICurveViewFacet(address(diamond)).getCurveInfo(curveId);

        assertEq(uint8(info.backingKind), uint8(ProductAdapterTypes.CurveBackingKind.Adapter));
        assertEq(uint8(info.adapterKind), uint8(ProductAdapterTypes.ProductAdapterKind.MLOPrediction));
        assertEq(info.adapterBucketId, BUCKET_ID);
        assertEq(info.adapterRiskDomainId, RISK_DOMAIN_ID);
        assertEq(info.adapterDataKey, ADAPTER_DATA_KEY);
        assertTrue(info.adapterActive);

        ProductAdapterHarnessFacet(address(diamond)).disableAdapterCurveFixture(curveId);
        info = ICurveViewFacet(address(diamond)).getCurveInfo(curveId);
        assertFalse(info.adapterActive);

        vm.expectRevert(abi.encodeWithSelector(Errors.AdapterCurveInactive.selector, curveId));
        ProductAdapterHarnessFacet(address(diamond)).requireActiveAdapterCurveFixture(curveId);
    }

    function test_AdapterBackedAskRoutesAwayFromEscrowBuySettlement() public {
        bytes32 bookId = _createSpotBook();
        uint256 curveId = _postAdapterCurve(bookId, LibEveMarket.CurveSide.ASK, 100e6, 0, TWO_USDC);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        vm.startPrank(taker);
        usdc.approve(address(diamond), 200e6);
        vm.expectRevert(abi.encodeWithSelector(IMLOPredictionAdapterFacet.MLOAdapterCurveNotFound.selector, curveId));
        ICurveTradeFacet(address(diamond)).fillCurve(curveId, 200e6, 100e6, generation, commitment);
        vm.stopPrank();
    }

    function test_AdapterBackedBidRoutesAwayFromEscrowSellSettlement() public {
        bytes32 bookId = _createSpotBook();
        uint256 curveId = _postAdapterCurve(bookId, LibEveMarket.CurveSide.BID, 100e6, 200e6, TWO_USDC);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        vm.startPrank(taker);
        spotToken.approve(address(diamond), 100e6);
        vm.expectRevert(abi.encodeWithSelector(IMarginAccountFacet.MarginBucketNotFound.selector, BUCKET_ID));
        IBookTradeFacet(address(diamond))
            .sellBookBest(
                CurveCLOBTypes.SellBookParams({
                    bookId: bookId,
                    maxBaseIn: 100e6,
                    minQuoteOut: 1,
                    curveIds: _singleCurve(curveId),
                    expectedGenerations: _singleGeneration(generation),
                    expectedCommitments: _singleCommitment(commitment),
                    receiver: taker
                })
            );
        vm.stopPrank();
    }

    function test_AdapterBackedComplementSellRoutesAwayFromEscrowSettlement() public {
        (bytes32 marketId,) = _createMarketFixture("Does adapter complement sell stay isolated?", _expiry(7 days));
        ITestStateFacet(address(diamond)).materializeMarketSideBookFixture(marketId, true);
        bytes32 yesBookId = LibCLOBBook.marketBookId(marketId, true);
        uint128 shares = 100e6;

        _splitFrom(taker, marketId, shares);

        uint256 curveId = _postAdapterCurve(yesBookId, LibEveMarket.CurveSide.ASK, shares, 0, FORTY_CENTS);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        vm.startPrank(taker);
        conditionalTokens.setApprovalForAll(address(diamond), true);
        vm.expectRevert(abi.encodeWithSelector(IMarginAccountFacet.MarginBucketNotFound.selector, BUCKET_ID));
        ITradeRouter(address(diamond))
            .sellWithCollateral(
                ITradeRouter.SellBestParams({
                    marketId: marketId,
                    isYesSide: false,
                    maxSharesIn: shares,
                    minCollateralOut: 1,
                    curveIds: _singleCurve(curveId),
                    expectedGenerations: _singleGeneration(generation),
                    expectedCommitments: _singleCommitment(commitment),
                    receiver: taker
                })
            );
        vm.stopPrank();
    }

    function test_AdapterBackedCurveCannotUseEscrowLifecyclePaths() public {
        bytes32 bookId = _createSpotBook();
        uint256 curveId = _postAdapterCurve(bookId, LibEveMarket.CurveSide.ASK, 100e6, 0, TWO_USDC);
        CurveCLOBTypes.CurveInfo memory info = ICurveViewFacet(address(diamond)).getCurveInfo(curveId);

        vm.startPrank(maker);
        vm.expectRevert(_backingMismatch(curveId));
        ICurveLifecycleFacet(address(diamond)).updateCurve(curveId, info.packed, info.generation);

        CurveCLOBTypes.CurveTopUpParams[] memory topUps = new CurveCLOBTypes.CurveTopUpParams[](1);
        topUps[0] = CurveCLOBTypes.CurveTopUpParams({curveId: curveId, addedVolume: 1e6});
        vm.expectRevert(_backingMismatch(curveId));
        IBookOrderFacet(address(diamond)).topUpBookCurvesBatch(bookId, topUps);

        vm.expectRevert(_backingMismatch(curveId));
        ICurveLifecycleFacet(address(diamond)).cancelCurve(curveId);
        vm.stopPrank();
    }

    function test_GenerationMismatchStillPrecedesAdapterSettlementGuard() public {
        bytes32 bookId = _createSpotBook();
        uint256 curveId = _postAdapterCurve(bookId, LibEveMarket.CurveSide.ASK, 100e6, 0, TWO_USDC);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        vm.startPrank(taker);
        usdc.approve(address(diamond), 200e6);
        vm.expectRevert(abi.encodeWithSelector(Errors.GenerationMismatch.selector, generation + 1, generation));
        ICurveTradeFacet(address(diamond)).fillCurve(curveId, 200e6, 100e6, generation + 1, commitment);
        vm.stopPrank();
    }

    function _backingMismatch(uint256 curveId) internal pure returns (bytes memory revertData) {
        revertData = abi.encodeWithSelector(
            Errors.CurveBackingMismatch.selector,
            curveId,
            uint8(ProductAdapterTypes.CurveBackingKind.Escrow),
            uint8(ProductAdapterTypes.CurveBackingKind.Adapter)
        );
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

    function _postAdapterCurve(
        bytes32 bookId,
        LibEveMarket.CurveSide side,
        uint128 volume,
        uint128 quoteEscrow,
        uint72 price
    ) internal returns (uint256 curveId) {
        curveId = ProductAdapterHarnessFacet(address(diamond))
            .postAdapterCurveFixture(
                ProductAdapterHarnessFacet.AdapterCurveFixtureParams({
                    bookId: bookId,
                    maker: maker,
                    curveSide: uint8(side),
                    volume: volume,
                    quoteEscrow: quoteEscrow,
                    price: price,
                    durationMinutes: 120,
                    bucketId: BUCKET_ID,
                    riskDomainId: RISK_DOMAIN_ID,
                    adapterDataKey: ADAPTER_DATA_KEY
                })
            );
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
        selectors = new bytes4[](4);
        selectors[0] = IBookOrderFacet.postBookCurve.selector;
        selectors[1] = IBookOrderFacet.postBookCurvesBatch.selector;
        selectors[2] = IBookOrderFacet.topUpBookCurvesBatch.selector;
        selectors[3] = IBookOrderFacet.reactivateBookCurve.selector;
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

    function _curveInventorySelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = ICurveInventoryFacet.splitInventory.selector;
        selectors[1] = ICurveInventoryFacet.mergeInventory.selector;
    }

    function _curveLifecycleSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](16);
        selectors[0] = ICurveLifecycleFacet.postCurve.selector;
        selectors[1] = ICurveLifecycleFacet.postBidCurve.selector;
        selectors[2] = ICurveLifecycleFacet.postCurvesBatch.selector;
        selectors[3] = ICurveLifecycleFacet.postBidCurvesBatch.selector;
        selectors[4] = ICurveLifecycleFacet.postCurvesMultiMarket.selector;
        selectors[5] = ICurveLifecycleFacet.postBidCurvesMultiMarket.selector;
        selectors[6] = ICurveLifecycleFacet.updateCurve.selector;
        selectors[7] = ICurveLifecycleFacet.updateCurvesBatch.selector;
        selectors[8] = ICurveLifecycleFacet.updateCurveFromNow.selector;
        selectors[9] = ICurveLifecycleFacet.updateCurvesFromNowBatch.selector;
        selectors[10] = ICurveLifecycleFacet.topUpCurvesBatch.selector;
        selectors[11] = ICurveLifecycleFacet.topUpCurvesMultiMarket.selector;
        selectors[12] = ICurveLifecycleFacet.splitAndTopUpCurvesBatch.selector;
        selectors[13] = ICurveLifecycleFacet.splitAndTopUpCurvesMultiMarket.selector;
        selectors[14] = ICurveLifecycleFacet.cancelCurve.selector;
        selectors[15] = ICurveLifecycleFacet.cancelCurvesBatch.selector;
    }

    function _curveTradeSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = ICurveTradeFacet.fillCurve.selector;
        selectors[1] = ICurveTradeFacet.fillBest.selector;
    }

    function _curveViewSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = ICurveViewFacet.getCurveCommitment.selector;
        selectors[1] = ICurveViewFacet.getCurveInfo.selector;
        selectors[2] = ICurveViewFacet.previewCurveQuote.selector;
        selectors[3] = ICurveViewFacet.previewBestExecution.selector;
    }

    function _tradeRouterSellSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = ITradeRouter.sellWithCollateral.selector;
    }

    function _tradeRouterPreviewSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = ITradeRouter.previewSellBest.selector;
        selectors[1] = ITradeRouter.executeExactRouterTransfer.selector;
    }

    function _mloAskRouteSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = IMLOPredictionAdapterFacet.executeMLOAskFromRoute.selector;
    }

    function _adapterHarnessSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = ProductAdapterHarnessFacet.postAdapterCurveFixture.selector;
        selectors[1] = ProductAdapterHarnessFacet.disableAdapterCurveFixture.selector;
        selectors[2] = ProductAdapterHarnessFacet.requireActiveAdapterCurveFixture.selector;
    }
}
