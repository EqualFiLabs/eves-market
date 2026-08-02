// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {OwnershipFacet} from "../../src/facets/OwnershipFacet.sol";
import {ComboCoreFacet} from "../../src/facets/native/ComboCoreFacet.sol";
import {ComboMarketFacet} from "../../src/facets/native/ComboMarketFacet.sol";
import {ComboSettlementFacet} from "../../src/facets/native/ComboSettlementFacet.sol";
import {BookFacet} from "../../src/facets/BookFacet.sol";
import {BookOrderFacet} from "../../src/facets/BookOrderFacet.sol";
import {BookTradeFacet} from "../../src/facets/BookTradeFacet.sol";
import {BookViewFacet} from "../../src/facets/BookViewFacet.sol";
import {DelayedOrderFacet} from "../../src/facets/DelayedOrderFacet.sol";
import {IComboCoreFacet} from "../../src/interfaces/IComboCoreFacet.sol";
import {IComboMarketFacet} from "../../src/interfaces/IComboMarketFacet.sol";
import {IComboSettlementFacet} from "../../src/interfaces/IComboSettlementFacet.sol";
import {IBookAdminFacet} from "../../src/interfaces/IBookAdminFacet.sol";
import {IBookOrderFacet} from "../../src/interfaces/IBookOrderFacet.sol";
import {IBookTradeFacet} from "../../src/interfaces/IBookTradeFacet.sol";
import {IBookViewFacet} from "../../src/interfaces/IBookViewFacet.sol";
import {ICurveInventoryFacet} from "../../src/interfaces/ICurveInventoryFacet.sol";
import {ICurveLifecycleFacet} from "../../src/interfaces/ICurveLifecycleFacet.sol";
import {ICurveTradeFacet} from "../../src/interfaces/ICurveTradeFacet.sol";
import {ICurveViewFacet} from "../../src/interfaces/ICurveViewFacet.sol";
import {CurveCLOBTypes} from "../../src/types/CurveCLOBTypes.sol";
import {IMarketFactoryFacet} from "../../src/interfaces/IMarketFactoryFacet.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {LibMarketCreation} from "../../src/libraries/LibMarketCreation.sol";
import {DelayedOrderTypes} from "../../src/types/DelayedOrderTypes.sol";
import {NativePositionTypes} from "../../src/types/NativePositionTypes.sol";
import {EvesPositionManager} from "../../src/tokens/EvesPositionManager.sol";
import {EveETH} from "../../src/tokens/EveETH.sol";

import {CanonicalWETH9} from "../../src/mocks/CanonicalWETH9.sol";
import {SettlementFeeFixture} from "../helpers/DiamondFixtures.sol";

contract ComboCollateralTest is SettlementFeeFixture {
    uint8 internal constant EVE_ETH_PROFILE_ID = 1;
    uint128 internal constant EVE_ETH_PAYOUT_UNIT = 0.0005 ether;
    uint72 internal constant HALF_PRICE = 500_000_000;

    CanonicalWETH9 internal weth;
    EveETH internal eveETH;
    EvesPositionManager internal comboPositions;

    function setUp() public override {
        super.setUp();

        weth = new CanonicalWETH9();
        eveETH = new EveETH(address(weth));
        comboPositions = new EvesPositionManager(address(diamond), "");

        _addFacet(address(ownershipFacet), _evesPositionManagerSelector());
        _addFacet(address(new ComboCoreFacet()), _comboCoreSelectors());
        _addFacet(address(new ComboMarketFacet()), _comboMarketSelectors());
        _addFacet(address(new ComboSettlementFacet()), _comboSettlementSelectors());
        _addFacet(address(new BookFacet()), _bookSelectors());
        _addFacet(address(new BookOrderFacet()), _bookOrderSelectors());
        _addFacet(address(new BookTradeFacet()), _bookTradeSelectors());
        _addFacet(address(new BookViewFacet()), _bookViewSelectors());
        _addFacet(address(new DelayedOrderFacet()), _delayedOrderSelectors());

        vm.startPrank(owner);
        OwnershipFacet(address(diamond)).setEvesPositionManager(address(comboPositions));
        OwnershipFacet(address(diamond))
            .setCollateralProfile(EVE_ETH_PROFILE_ID, address(eveETH), address(weth), EVE_ETH_PAYOUT_UNIT, 0, true);
        OwnershipFacet(address(diamond)).setOrderbookEntryFeeBps(100);
        OwnershipFacet(address(diamond)).setOrderbookFeeSplit(4_000, 0, 3_000, 3_000, 0, 0);
        OwnershipFacet(address(diamond)).setDelayedOrderConfig(2, 10, 180);
        OwnershipFacet(address(diamond)).setDelayedOrderProcessing(uint8(LibEveMarket.ProcessingMode.Permissionless), 0);
        vm.stopPrank();
    }

    function test_EveETHComboMarketTradesAndRedeemsWithDerivedCollateral() public {
        (bytes32 firstMarketId, uint64 firstExpiry) = _createEveETHMarket("Will combo eveETH leg one win?");
        (bytes32 secondMarketId, uint64 secondExpiry) = _createEveETHMarket("Will combo eveETH leg two win?");
        uint128 mergeAmount = EVE_ETH_PAYOUT_UNIT;
        uint128 makerInventory = 0.002 ether;
        uint128 takerCollateral = 0.001 ether;

        _fundEveETH(maker, mergeAmount + makerInventory);
        _fundEveETH(taker, takerCollateral);

        IComboMarketFacet.ComboMarketPreparation memory preparation = _createComboMarket(firstMarketId, secondMarketId);
        _assertComboCollateral(preparation.marketId, preparation.yesBookId, address(eveETH));
        _assertEveETHSplitAndMerge(
            preparation.conditionId, preparation.yesPositionId, preparation.noPositionId, mergeAmount
        );
        uint128 sharesOut = _postAndFillEveETHComboAsk(
            preparation.yesBookId, preparation.yesPositionId, makerInventory, takerCollateral
        );

        _finalizeCreatorResolution(firstMarketId, firstExpiry, uint8(LibEveMarket.MarketOutcome.Yes));
        _finalizeCreatorResolution(secondMarketId, secondExpiry, uint8(LibEveMarket.MarketOutcome.Yes));

        uint256 takerBalanceBefore = eveETH.balanceOf(taker);
        vm.prank(taker);
        uint128 collateralOut =
            IComboSettlementFacet(address(diamond)).redeemCombo(preparation.yesPositionId, sharesOut, taker);

        assertEq(collateralOut, sharesOut);
        assertEq(eveETH.balanceOf(taker), takerBalanceBefore + sharesOut);
        assertEq(comboPositions.balanceOf(taker, preparation.yesPositionId), 0);
    }

    function test_DefaultComboMarketPreservesEveUSDCollateral() public {
        (bytes32 firstMarketId,,) = _createTradingMarket("Will default combo leg one win?", "combo", 7 days);
        (bytes32 secondMarketId,,) = _createTradingMarket("Will default combo leg two win?", "combo", 8 days);
        uint128 amount = 1_000e6;

        IComboMarketFacet.ComboMarketPreparation memory preparation = _createComboMarket(firstMarketId, secondMarketId);
        _assertComboCollateral(preparation.marketId, preparation.yesBookId, address(collateralToken));

        collateralToken.mint(maker, amount);
        uint256 balanceBefore = collateralToken.balanceOf(maker);
        vm.startPrank(maker);
        collateralToken.approve(address(diamond), amount);
        IComboCoreFacet(address(diamond)).splitCombo(preparation.conditionId, amount, maker, maker);
        comboPositions.setApprovalForAll(address(diamond), true);
        uint128 collateralOut = IComboCoreFacet(address(diamond)).mergeCombo(preparation.conditionId, amount, maker);
        vm.stopPrank();

        assertEq(collateralOut, amount);
        assertEq(collateralToken.balanceOf(maker), balanceBefore);
        assertEq(comboPositions.balanceOf(maker, preparation.yesPositionId), 0);
        assertEq(comboPositions.balanceOf(maker, preparation.noPositionId), 0);
    }

    function test_EveETHComboBookSupportsDelayedMarketBuy() public {
        (bytes32 firstMarketId,) = _createEveETHMarket("Will delayed combo leg one win?");
        (bytes32 secondMarketId,) = _createEveETHMarket("Will delayed combo leg two win?");
        uint128 makerInventory = 0.002 ether;
        uint128 takerCollateral = 0.001 ether;

        _fundEveETH(maker, makerInventory);
        _fundEveETH(taker, takerCollateral);
        IComboMarketFacet.ComboMarketPreparation memory preparation = _createComboMarket(firstMarketId, secondMarketId);
        uint256 curveId = _splitAndPostEveETHComboAsk(preparation.conditionId, preparation.yesBookId, makerInventory);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        vm.prank(owner);
        OwnershipFacet(address(diamond)).setBookDelayedExecution(preparation.yesBookId, true);

        vm.prank(taker);
        uint256 orderId = DelayedOrderFacet(address(diamond))
            .submitDelayedOrder(
                DelayedOrderTypes.SubmitDelayedOrderParams({
                    bookId: preparation.yesBookId,
                    kind: LibEveMarket.DelayedOrderKind.MarketBuy,
                    amountIn: takerCollateral,
                    limitPrice: 0,
                    minOut: 0,
                    maxAveragePrice: type(uint128).max,
                    curveIds: _singleCurveId(curveId),
                    expectedGenerations: _singleGeneration(generation),
                    expectedCommitments: _singleCommitment(commitment)
                })
            );

        vm.roll(block.number + 2);
        DelayedOrderTypes.DelayedOrderRoute[] memory routes = new DelayedOrderTypes.DelayedOrderRoute[](1);
        routes[0] = DelayedOrderTypes.DelayedOrderRoute({
            curveIds: _singleCurveId(curveId),
            expectedGenerations: _singleGeneration(generation),
            expectedCommitments: _singleCommitment(commitment)
        });
        DelayedOrderFacet(address(diamond)).processDelayedOrders(preparation.yesBookId, 1, routes);

        DelayedOrderTypes.DelayedOrderView memory order = DelayedOrderFacet(address(diamond)).getDelayedOrder(orderId);
        assertTrue(
            order.status == LibEveMarket.DelayedOrderStatus.Filled
                || order.status == LibEveMarket.DelayedOrderStatus.PartiallyFilled
        );
        assertGt(comboPositions.balanceOf(taker, preparation.yesPositionId), 0);
    }

    function test_RevertWhen_ComboMarketMixesCollateralProfiles() public {
        (bytes32 defaultMarketId,,) = _createTradingMarket("Will mixed default leg win?", "combo", 7 days);
        (bytes32 eveETHMarketId,) = _createEveETHMarket("Will mixed eveETH leg win?");

        vm.prank(creator);
        vm.expectPartialRevert(Errors.ComboCollateralMismatch.selector);
        IComboMarketFacet(address(diamond)).createComboMarket(_pair(defaultMarketId, eveETHMarketId), _yesLegs());
    }

    function _assertEveETHSplitAndMerge(
        bytes32 conditionId,
        uint256 yesPositionId,
        uint256 noPositionId,
        uint128 amount
    ) internal {
        uint256 balanceBefore = eveETH.balanceOf(maker);

        vm.startPrank(maker);
        eveETH.approve(address(diamond), amount);
        IComboCoreFacet(address(diamond)).splitCombo(conditionId, amount, maker, maker);
        comboPositions.setApprovalForAll(address(diamond), true);
        uint128 collateralOut = IComboCoreFacet(address(diamond)).mergeCombo(conditionId, amount, maker);
        vm.stopPrank();

        assertEq(collateralOut, amount);
        assertEq(eveETH.balanceOf(maker), balanceBefore);
        assertEq(comboPositions.balanceOf(maker, yesPositionId), 0);
        assertEq(comboPositions.balanceOf(maker, noPositionId), 0);
    }

    function _postAndFillEveETHComboAsk(
        bytes32 yesBookId,
        uint256 yesPositionId,
        uint128 makerInventory,
        uint128 takerCollateral
    ) internal returns (uint128 sharesOut) {
        CurveCLOBTypes.BookInfo memory yesBook = IBookAdminFacet(address(diamond)).getBookInfo(yesBookId);
        NativePositionTypes.ComboMarketView memory comboMarket =
            IComboMarketFacet(address(diamond)).getComboMarket(yesBook.marketId);
        uint256 curveId = _splitAndPostEveETHComboAsk(comboMarket.conditionId, yesBookId, makerInventory);

        sharesOut = _fillEveETHComboAsk(yesBookId, yesPositionId, curveId, takerCollateral);
    }

    function _splitAndPostEveETHComboAsk(bytes32 conditionId, bytes32 yesBookId, uint128 makerInventory)
        internal
        returns (uint256 curveId)
    {
        vm.startPrank(maker);
        eveETH.approve(address(diamond), makerInventory);
        IComboCoreFacet(address(diamond)).splitCombo(conditionId, makerInventory, maker, maker);
        comboPositions.setApprovalForAll(address(diamond), true);
        curveId = IBookOrderFacet(address(diamond))
            .postBookCurve(yesBookId, LibEveMarket.CurveSide.ASK, makerInventory, HALF_PRICE, HALF_PRICE, 180, 0, 0);
        vm.stopPrank();
    }

    function _fillEveETHComboAsk(bytes32 yesBookId, uint256 yesPositionId, uint256 curveId, uint128 takerCollateral)
        internal
        returns (uint128 sharesOut)
    {
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        (uint128 previewShares,,,) = ICurveViewFacet(address(diamond)).previewCurveQuote(curveId, takerCollateral);
        uint256 takerBalanceBefore = eveETH.balanceOf(taker);

        vm.prank(taker);
        CurveCLOBTypes.FillBestResult memory result = IBookTradeFacet(address(diamond))
            .fillBookBest(
                CurveCLOBTypes.FillBookParams({
                    bookId: yesBookId,
                    maxQuoteIn: takerCollateral,
                    minBaseOut: previewShares,
                    maxAveragePrice: type(uint128).max,
                    curveIds: _singleCurveId(curveId),
                    expectedGenerations: _singleGeneration(generation),
                    expectedCommitments: _singleCommitment(commitment),
                    payer: taker,
                    receiver: taker
                })
            );

        sharesOut = result.sharesOut;
        assertEq(sharesOut, previewShares);
        assertEq(comboPositions.balanceOf(taker, yesPositionId), previewShares);
        assertEq(eveETH.balanceOf(taker), takerBalanceBefore - result.collateralUsed);
    }

    function _assertComboCollateral(bytes32 comboMarketId, bytes32 yesBookId, address expectedCollateral)
        internal
        view
    {
        NativePositionTypes.ComboMarketView memory comboMarket =
            IComboMarketFacet(address(diamond)).getComboMarket(comboMarketId);
        CurveCLOBTypes.BookInfo memory yesBook = IBookAdminFacet(address(diamond)).getBookInfo(yesBookId);

        assertTrue(comboMarket.exists);
        assertEq(comboMarket.collateralToken, expectedCollateral);
        assertEq(yesBook.quoteToken, expectedCollateral);
    }

    function _createComboMarket(bytes32 firstMarketId, bytes32 secondMarketId)
        internal
        returns (IComboMarketFacet.ComboMarketPreparation memory preparation)
    {
        vm.prank(creator);
        preparation =
            IComboMarketFacet(address(diamond)).createComboMarket(_pair(firstMarketId, secondMarketId), _yesLegs());
    }

    function _createEveETHMarket(string memory question) internal returns (bytes32 marketId, uint64 expiryTime) {
        uint64 tradingStartTime = uint64(block.timestamp);
        expiryTime = tradingStartTime + 7 days;

        vm.prank(creator);
        eveToken.approve(address(diamond), type(uint256).max);

        vm.prank(creator);
        marketId = IMarketFactoryFacet(address(diamond))
            .createMarketWithCollateralProfile(
                EVE_ETH_PROFILE_ID, question, "combo", DEFAULT_RESOLUTION_SOURCE, tradingStartTime, expiryTime, 0, true
            );

        bytes32 expectedMarketId = LibMarketCreation.profileMarketIdFor(
            question,
            "combo",
            tradingStartTime,
            expiryTime,
            address(eveETH),
            EVE_ETH_PROFILE_ID,
            EVE_ETH_PAYOUT_UNIT,
            LibEveMarket.MarketType.CLOB,
            LibEveMarket.PositionTokenType.CTF
        );
        assertEq(marketId, expectedMarketId);
    }

    function _fundEveETH(address account, uint256 amount) internal {
        vm.deal(account, amount);
        vm.startPrank(account);
        weth.deposit{value: amount}();
        weth.approve(address(eveETH), amount);
        eveETH.wrap(amount, account);
        eveETH.approve(address(diamond), type(uint256).max);
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

    function _singleCurveId(uint256 curveId) internal pure returns (uint256[] memory values) {
        values = new uint256[](1);
        values[0] = curveId;
    }

    function _singleGeneration(uint32 generation) internal pure returns (uint32[] memory values) {
        values = new uint32[](1);
        values[0] = generation;
    }

    function _singleCommitment(bytes32 commitment) internal pure returns (bytes32[] memory values) {
        values = new bytes32[](1);
        values[0] = commitment;
    }

    function _evesPositionManagerSelector() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = OwnershipFacet.setEvesPositionManager.selector;
    }

    function _comboCoreSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](6);
        selectors[0] = IComboCoreFacet.prepareComboCondition.selector;
        selectors[1] = IComboCoreFacet.splitCombo.selector;
        selectors[2] = IComboCoreFacet.mergeCombo.selector;
        selectors[3] = IComboCoreFacet.wrapCombo.selector;
        selectors[4] = IComboCoreFacet.unwrapCombo.selector;
        selectors[5] = IComboCoreFacet.getComboCondition.selector;
    }

    function _comboMarketSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = IComboMarketFacet.createComboMarket.selector;
        selectors[1] = IComboMarketFacet.computeComboBookId.selector;
        selectors[2] = IComboMarketFacet.getComboMarket.selector;
        selectors[3] = IComboMarketFacet.getComboBook.selector;
    }

    function _comboSettlementSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = IComboSettlementFacet.compressCombo.selector;
        selectors[1] = IComboSettlementFacet.redeemCombo.selector;
        selectors[2] = IComboSettlementFacet.getComboPayout.selector;
    }

    function _bookSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](7);
        selectors[0] = IBookAdminFacet.createBook.selector;
        selectors[1] = IBookAdminFacet.computeBookId.selector;
        selectors[2] = IBookAdminFacet.getBookInfo.selector;
        selectors[3] = IBookAdminFacet.isBookMaterialized.selector;
        selectors[4] = IBookAdminFacet.getMarketSideBook.selector;
        selectors[5] = IBookAdminFacet.requestBookDecommission.selector;
        selectors[6] = IBookAdminFacet.finalizeBookDecommission.selector;
    }

    function _bookOrderSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = IBookOrderFacet.postBookCurve.selector;
        selectors[1] = IBookOrderFacet.postBookCurvesBatch.selector;
        selectors[2] = IBookOrderFacet.topUpBookCurvesBatch.selector;
        selectors[3] = IBookOrderFacet.reactivateBookCurve.selector;
    }

    function _bookTradeSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = IBookTradeFacet.fillBookBest.selector;
        selectors[1] = IBookTradeFacet.fillBookBestFor.selector;
        selectors[2] = IBookTradeFacet.sellBookBest.selector;
    }

    function _bookViewSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = IBookViewFacet.previewBookExecution.selector;
        selectors[1] = IBookViewFacet.getBookTopOfBook.selector;
    }

    function _delayedOrderSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = DelayedOrderFacet.submitDelayedOrder.selector;
        selectors[1] = DelayedOrderFacet.processDelayedOrders.selector;
        selectors[2] = DelayedOrderFacet.getDelayedOrder.selector;
        selectors[3] = DelayedOrderFacet.getQuoteCredit.selector;
    }
}
