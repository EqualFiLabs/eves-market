// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "../../lib/forge-std/src/Test.sol";

import {CurveLifecycleFacet} from "../../src/facets/CurveLifecycleFacet.sol";
import {CurveViewFacet} from "../../src/facets/CurveViewFacet.sol";
import {ComboMarketFacet} from "../../src/facets/native/ComboMarketFacet.sol";
import {BookOrderFacet} from "../../src/facets/BookOrderFacet.sol";
import {BookTradeFacet} from "../../src/facets/BookTradeFacet.sol";
import {IBookAdminFacet} from "../../src/interfaces/IBookAdminFacet.sol";
import {IBookOrderFacet} from "../../src/interfaces/IBookOrderFacet.sol";
import {IBookTradeFacet} from "../../src/interfaces/IBookTradeFacet.sol";
import {IBookViewFacet} from "../../src/interfaces/IBookViewFacet.sol";
import {ICurveInventoryFacet} from "../../src/interfaces/ICurveInventoryFacet.sol";
import {ICurveLifecycleFacet} from "../../src/interfaces/ICurveLifecycleFacet.sol";
import {ICurveTradeFacet} from "../../src/interfaces/ICurveTradeFacet.sol";
import {ICurveViewFacet} from "../../src/interfaces/ICurveViewFacet.sol";
import {CurveCLOBTypes} from "../../src/types/CurveCLOBTypes.sol";
import {IComboMarketFacet} from "../../src/interfaces/IComboMarketFacet.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {LibCLOBBook} from "../../src/libraries/LibCLOBBook.sol";
import {LibCurvePacking} from "../../src/libraries/LibCurvePacking.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {LibNativePosition} from "../../src/libraries/LibNativePosition.sol";
import {NativePositionTypes} from "../../src/types/NativePositionTypes.sol";
import {EvesPositionManager} from "../../src/tokens/EvesPositionManager.sol";

import {MockUSDC} from "../helpers/MockUSDC.sol";
import {MockDiamond} from "../helpers/TestBase.sol";

contract ComboMarketHarness is ComboMarketFacet {
    struct BookSnapshot {
        bytes32 marketId;
        bool isYesSide;
        LibEveMarket.BookAssetType assetType;
        LibEveMarket.BookPricingMode pricingMode;
        address baseToken;
        uint256 baseTokenId;
        address quoteToken;
        address creator;
        uint64 expiryTime;
        uint16 entryFeeBps;
    }

    function configure(address collateralToken, address positionManager, address treasury) external {
        LibEveMarket.MarketConfig storage config = LibEveMarket.store().config;
        config.collateralToken = collateralToken;
        config.evesPositionManager = positionManager;
        config.eveTreasury = treasury;
        config.comboFeeConfig = LibEveMarket.ComboFeeConfig({
            tradeFeeBps: 100,
            makerFeeBps: 4_000,
            creatorFeeBps: 500,
            protocolFeeBps: 3_000,
            vaultFeeBps: 2_500,
            resolverFeeBps: 0,
            evRiskFeeBps: 0
        });
    }

    function setComboMarketCreationFee(uint128 fee) external {
        LibEveMarket.store().config.comboMarketCreationFee = fee;
    }

    function mintPosition(address to, uint256 positionId, uint128 amount) external {
        EvesPositionManager(LibEveMarket.store().config.evesPositionManager).mint(to, positionId, amount);
    }

    function seedMarket(bytes32 marketId, address collateralToken, uint64 expiryTime) external {
        LibEveMarket.Market storage market = LibEveMarket.store().markets[marketId];
        market.marketId = marketId;
        market.marketType = LibEveMarket.MarketType.CLOB;
        market.collateralToken = collateralToken;
        market.state = LibEveMarket.MarketState.Trading;
        market.tradingStartTime = uint64(block.timestamp);
        market.expiryTime = expiryTime;
    }

    function snapshotBook(bytes32 bookId) external view returns (BookSnapshot memory snapshot) {
        LibEveMarket.Book storage book = LibEveMarket.store().books[bookId];
        snapshot = BookSnapshot({
            marketId: book.marketId,
            isYesSide: book.isYesSide,
            assetType: book.assetType,
            pricingMode: book.pricingMode,
            baseToken: book.baseToken,
            baseTokenId: book.baseTokenId,
            quoteToken: book.quoteToken,
            creator: book.creator,
            expiryTime: book.expiryTime,
            entryFeeBps: book.feeConfig.entryFeeBps
        });
    }
}

contract ComboMarketTest is Test {
    ComboMarketHarness internal comboMarkets;
    EvesPositionManager internal positions;
    MockUSDC internal collateral;

    address internal creator = makeAddr("creator");
    address internal treasury = makeAddr("treasury");

    bytes32 internal constant MARKET_A = bytes32(uint256(0xA));
    bytes32 internal constant MARKET_B = bytes32(uint256(0xB));
    uint64 internal earliestExpiry;

    function setUp() public {
        comboMarkets = new ComboMarketHarness();
        positions = new EvesPositionManager(address(comboMarkets), "");
        collateral = new MockUSDC();
        comboMarkets.configure(address(collateral), address(positions), treasury);

        earliestExpiry = uint64(block.timestamp + 7 days);
        comboMarkets.seedMarket(MARKET_A, address(collateral), earliestExpiry);
        comboMarkets.seedMarket(MARKET_B, address(collateral), uint64(block.timestamp + 14 days));
    }

    function test_CreateComboMarketRegistersPairedYesNoBooks() public {
        vm.prank(creator);
        IComboMarketFacet.ComboMarketPreparation memory preparation =
            comboMarkets.createComboMarket(_markets(), _yesLegs());

        assertEq(preparation.marketId, preparation.conditionId);
        assertEq(preparation.yesBookId, LibCLOBBook.marketBookId(preparation.marketId, true));
        assertEq(preparation.noBookId, LibCLOBBook.marketBookId(preparation.marketId, false));
        assertEq(comboMarkets.getComboBook(address(positions), preparation.yesPositionId), preparation.yesBookId);
        assertEq(comboMarkets.getComboBook(address(positions), preparation.noPositionId), preparation.noBookId);

        NativePositionTypes.ComboMarketView memory view_ = comboMarkets.getComboMarket(preparation.marketId);
        assertTrue(view_.exists);
        assertEq(view_.creator, creator);
        assertEq(view_.positionToken, address(positions));
        assertEq(view_.collateralToken, address(collateral));
        assertEq(view_.expiryTime, earliestExpiry);

        ComboMarketHarness.BookSnapshot memory yesBook = comboMarkets.snapshotBook(preparation.yesBookId);
        ComboMarketHarness.BookSnapshot memory noBook = comboMarkets.snapshotBook(preparation.noBookId);
        assertEq(yesBook.marketId, preparation.marketId);
        assertEq(noBook.marketId, preparation.marketId);
        assertTrue(yesBook.isYesSide);
        assertFalse(noBook.isYesSide);
        assertEq(yesBook.baseTokenId, preparation.yesPositionId);
        assertEq(noBook.baseTokenId, preparation.noPositionId);
        assertEq(uint8(yesBook.pricingMode), uint8(LibEveMarket.BookPricingMode.PREDICTION_PAYOUT));
        assertEq(yesBook.entryFeeBps, 100);
    }

    function test_CreateComboMarketChargesOneCreationFee() public {
        uint128 fee = 25e6;
        comboMarkets.setComboMarketCreationFee(fee);
        collateral.mint(creator, fee);

        vm.startPrank(creator);
        collateral.approve(address(comboMarkets), fee);
        comboMarkets.createComboMarket(_markets(), _yesLegs());
        vm.stopPrank();

        assertEq(collateral.balanceOf(treasury), fee);
    }

    function test_RevertWhen_ComboMarketAlreadyExists() public {
        vm.prank(creator);
        IComboMarketFacet.ComboMarketPreparation memory preparation =
            comboMarkets.createComboMarket(_markets(), _yesLegs());

        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(Errors.ComboMarketAlreadyExists.selector, preparation.marketId));
        comboMarkets.createComboMarket(_markets(), _yesLegs());
    }

    function _markets() internal pure returns (bytes32[] memory marketIds) {
        marketIds = new bytes32[](2);
        marketIds[0] = MARKET_A;
        marketIds[1] = MARKET_B;
    }

    function _yesLegs() internal pure returns (bool[] memory yesLegs) {
        yesLegs = new bool[](2);
        yesLegs[0] = true;
        yesLegs[1] = true;
    }
}

contract ComboMarketLiveFlowTest is Test {
    MockDiamond internal diamond;
    EvesPositionManager internal positions;
    MockUSDC internal collateral;

    address internal owner = makeAddr("owner");
    address internal creator = makeAddr("creator");
    address internal maker = makeAddr("maker");
    address internal taker = makeAddr("taker");
    address internal treasury = makeAddr("treasury");

    bytes32 internal constant MARKET_A = bytes32(uint256(0xAA));
    bytes32 internal constant MARKET_B = bytes32(uint256(0xBB));
    uint128 internal constant INVENTORY = 10e6;
    uint72 internal constant HALF_PRICE = LibCurvePacking.PRICE_SCALE / 2;

    function setUp() public {
        diamond = new MockDiamond(owner);
        positions = new EvesPositionManager(address(diamond), "");
        collateral = new MockUSDC();

        vm.startPrank(owner);
        diamond.registerFacet(address(new ComboMarketHarness()), _comboMarketSelectors());
        diamond.registerFacet(address(new CurveLifecycleFacet()), _curveLifecycleSelectors());
        diamond.registerFacet(address(new BookOrderFacet()), _bookOrderSelectors());
        diamond.registerFacet(address(new BookTradeFacet()), _bookTradeSelectors());
        diamond.registerFacet(address(new CurveViewFacet()), _curveViewSelectors());
        vm.stopPrank();

        ComboMarketHarness(address(diamond)).configure(address(collateral), address(positions), treasury);
        ComboMarketHarness(address(diamond)).seedMarket(MARKET_A, address(collateral), uint64(block.timestamp + 7 days));
        ComboMarketHarness(address(diamond))
            .seedMarket(MARKET_B, address(collateral), uint64(block.timestamp + 14 days));
    }

    function test_ComboMarketYesBookTradesThroughBookPath() public {
        vm.prank(creator);
        IComboMarketFacet.ComboMarketPreparation memory preparation =
            IComboMarketFacet(address(diamond)).createComboMarket(_markets(), _yesLegs());
        ComboMarketHarness(address(diamond)).mintPosition(maker, preparation.yesPositionId, INVENTORY);
        collateral.mint(taker, 6e6);

        vm.startPrank(maker);
        positions.setApprovalForAll(address(diamond), true);
        uint256 curveId = IBookOrderFacet(address(diamond))
            .postBookCurve(
                preparation.yesBookId, LibEveMarket.CurveSide.ASK, INVENTORY, HALF_PRICE, HALF_PRICE, 30, 0, 0
            );
        vm.stopPrank();

        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        uint256[] memory curveIds = new uint256[](1);
        curveIds[0] = curveId;
        uint32[] memory generations = new uint32[](1);
        generations[0] = generation;
        bytes32[] memory commitments = new bytes32[](1);
        commitments[0] = commitment;

        vm.startPrank(taker);
        collateral.approve(address(diamond), 6e6);
        CurveCLOBTypes.FillBestResult memory result = IBookTradeFacet(address(diamond))
            .fillBookBest(
                CurveCLOBTypes.FillBookParams({
                    bookId: preparation.yesBookId,
                    maxQuoteIn: 6e6,
                    minBaseOut: INVENTORY,
                    maxAveragePrice: 505_000_000,
                    curveIds: curveIds,
                    expectedGenerations: generations,
                    expectedCommitments: commitments,
                    payer: taker,
                    receiver: taker
                })
            );
        vm.stopPrank();

        assertEq(result.sharesOut, INVENTORY);
        assertEq(positions.balanceOf(taker, preparation.yesPositionId), INVENTORY);
    }

    function _markets() internal pure returns (bytes32[] memory marketIds) {
        marketIds = new bytes32[](2);
        marketIds[0] = MARKET_A;
        marketIds[1] = MARKET_B;
    }

    function _yesLegs() internal pure returns (bool[] memory yesLegs) {
        yesLegs = new bool[](2);
        yesLegs[0] = true;
        yesLegs[1] = true;
    }

    function _comboMarketSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](7);
        selectors[0] = IComboMarketFacet.createComboMarket.selector;
        selectors[1] = IComboMarketFacet.computeComboBookId.selector;
        selectors[2] = IComboMarketFacet.getComboMarket.selector;
        selectors[3] = IComboMarketFacet.getComboBook.selector;
        selectors[4] = ComboMarketHarness.configure.selector;
        selectors[5] = ComboMarketHarness.seedMarket.selector;
        selectors[6] = ComboMarketHarness.mintPosition.selector;
    }

    function _curveLifecycleSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = ICurveLifecycleFacet.cancelCurve.selector;
        selectors[1] = ICurveLifecycleFacet.cancelCurvesBatch.selector;
    }

    function _bookOrderSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = IBookOrderFacet.postBookCurve.selector;
    }

    function _bookTradeSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = IBookTradeFacet.fillBookBest.selector;
        selectors[1] = IBookTradeFacet.sellBookBest.selector;
    }

    function _curveViewSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = ICurveViewFacet.getCurveCommitment.selector;
    }
}
