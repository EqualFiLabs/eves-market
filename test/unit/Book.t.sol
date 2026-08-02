// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {CurveCLOBFacet} from "../../src/facets/CurveCLOBFacet.sol";
import {CurveInventoryFacet} from "../../src/facets/CurveInventoryFacet.sol";
import {CurveLifecycleFacet} from "../../src/facets/CurveLifecycleFacet.sol";
import {CurveViewFacet} from "../../src/facets/CurveViewFacet.sol";
import {EveUSDC} from "../../src/EveUSDC.sol";
import {BookFacet} from "../../src/facets/BookFacet.sol";
import {BookOrderFacet} from "../../src/facets/BookOrderFacet.sol";
import {BookTradeFacet} from "../../src/facets/BookTradeFacet.sol";
import {BookViewFacet} from "../../src/facets/BookViewFacet.sol";
import {IBookAdminFacet} from "../../src/interfaces/IBookAdminFacet.sol";
import {IBookOrderFacet} from "../../src/interfaces/IBookOrderFacet.sol";
import {IBookTradeFacet} from "../../src/interfaces/IBookTradeFacet.sol";
import {IBookViewFacet} from "../../src/interfaces/IBookViewFacet.sol";
import {ICurveInventoryFacet} from "../../src/interfaces/ICurveInventoryFacet.sol";
import {ICurveLifecycleFacet} from "../../src/interfaces/ICurveLifecycleFacet.sol";
import {ICurveTradeFacet} from "../../src/interfaces/ICurveTradeFacet.sol";
import {ICurveViewFacet} from "../../src/interfaces/ICurveViewFacet.sol";
import {CurveCLOBTypes} from "../../src/types/CurveCLOBTypes.sol";
import {LibCLOBBook} from "../../src/libraries/LibCLOBBook.sol";
import {LibCurvePacking} from "../../src/libraries/LibCurvePacking.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {MockEveToken} from "../helpers/MockEveToken.sol";
import {MockUSDC} from "../helpers/MockUSDC.sol";
import {ITestStateFacet, TestBase} from "../helpers/TestBase.sol";

contract MockFeeOnTransferToken is ERC20 {
    uint16 internal immutable feeBps;

    constructor(uint16 feeBps_) ERC20("Fee Base", "fBASE") {
        feeBps = feeBps_;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from == address(0) || to == address(0) || value == 0 || feeBps == 0) {
            super._update(from, to, value);
            return;
        }

        uint256 fee = (value * feeBps) / 10_000;
        super._update(from, to, value - fee);
        if (fee != 0) {
            super._update(from, address(0), fee);
        }
    }
}

contract BookTest is TestBase {
    uint72 internal constant TWO_USDC = 2_000_000_000_000_000_000;
    uint72 internal constant ONE_POINT_EIGHT_USDC = 1_800_000_000_000_000_000;
    uint72 internal constant HALF_PAYOUT_PRICE = 500_000_000;
    bytes32 internal constant SPOT_SALT = keccak256("spot-book");
    uint8 internal constant TWENTY_UNIT_TICK_PRESET = 4;
    uint128 internal constant TWENTY_UNIT_TICK_SIZE = 20;
    uint128 internal constant MICRO_EVE_BASE_AMOUNT = 3_000e18;
    uint72 internal constant MICRO_EVE_PRICE = 270_000_000_000;
    uint128 internal constant MICRO_EVE_QUOTE_IN = 810_000_000_000_000;

    CurveCLOBFacet internal curveFacet;
    MockUSDC internal spotToken;

    function setUp() public override {
        super.setUp();

        curveFacet = new CurveCLOBFacet();
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
        diamond.registerFacet(address(curveFacet), _curveTradeSelectors());
        diamond.registerFacet(address(new CurveViewFacet()), _curveViewSelectors());
        vm.stopPrank();
    }

    function test_ERC20SpotBookAskFillTransfersBaseForQuote() public {
        bytes32 bookId = _createSpotBook();

        vm.startPrank(maker);
        spotToken.approve(address(diamond), 100e6);
        uint256 curveId = IBookOrderFacet(address(diamond))
            .postBookCurve(bookId, LibEveMarket.CurveSide.ASK, 100e6, TWO_USDC, TWO_USDC, 120, 0, type(uint8).max);
        vm.stopPrank();

        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        vm.startPrank(taker);
        usdc.approve(address(diamond), 200e6);
        uint128 baseOut = ICurveTradeFacet(address(diamond)).fillCurve(curveId, 200e6, 100e6, generation, commitment);
        vm.stopPrank();

        assertEq(baseOut, 100e6);
        assertEq(spotToken.balanceOf(taker), 1_000_100e6);
        assertEq(usdc.balanceOf(maker), 1_000_200e6);
        assertEq(spotToken.balanceOf(address(diamond)), 0);
    }

    function test_CreateSpotBookChargesConfiguredFeeToTreasury() public {
        uint128 fee = 250e6;
        vm.prank(owner);
        ITestStateFacet(address(diamond)).setSpotBookCreationFeeFixture(fee);

        uint256 makerBefore = usdc.balanceOf(maker);
        uint256 treasuryBefore = usdc.balanceOf(treasury);
        bytes32 bookId = _createSpotBook(address(spotToken), LibEveMarket.BaseTransferMode.EXACT, 0, keccak256("fee"));

        assertTrue(bookId != bytes32(0));
        assertEq(usdc.balanceOf(maker), makerBefore - fee);
        assertEq(usdc.balanceOf(treasury), treasuryBefore + fee);
    }

    function test_CreateSpotBookDoesNotChargeOwner() public {
        vm.prank(owner);
        ITestStateFacet(address(diamond)).setSpotBookCreationFeeFixture(250e6);

        uint256 treasuryBefore = usdc.balanceOf(treasury);

        vm.prank(owner);
        bytes32 bookId = IBookAdminFacet(address(diamond))
            .createBook(
                LibEveMarket.BookAssetType.ERC20,
                LibEveMarket.BaseTransferMode.EXACT,
                address(spotToken),
                0,
                address(usdc),
                0,
                keccak256("owner-fee-waiver")
            );

        assertTrue(bookId != bytes32(0));
        assertEq(usdc.balanceOf(treasury), treasuryBefore);
    }

    function test_CreateSpotBookRejectsErc1155Assets() public {
        bytes32 salt = keccak256("erc1155-is-not-spot");
        bytes32 bookId = IBookAdminFacet(address(diamond))
            .computeBookId(
                maker,
                LibEveMarket.BookAssetType.ERC1155,
                LibEveMarket.BaseTransferMode.EXACT,
                address(conditionalTokens),
                1,
                address(usdc),
                0,
                salt
            );

        vm.prank(maker);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.BookAssetTypeMismatch.selector,
                bookId,
                uint8(LibEveMarket.BookAssetType.ERC20),
                uint8(LibEveMarket.BookAssetType.ERC1155)
            )
        );
        IBookAdminFacet(address(diamond))
            .createBook(
                LibEveMarket.BookAssetType.ERC1155,
                LibEveMarket.BaseTransferMode.EXACT,
                address(conditionalTokens),
                1,
                address(usdc),
                0,
                salt
            );
    }

    function test_CreateSpotBookSetsGenericTickDefaults() public {
        bytes32 bookId = _createSpotBook();

        CurveCLOBTypes.BookInfo memory info = IBookAdminFacet(address(diamond)).getBookInfo(bookId);
        assertEq(info.pricingMode, uint8(LibEveMarket.BookPricingMode.GENERIC));
        assertEq(info.lifecycle, uint8(LibEveMarket.BookLifecycle.ACTIVE));
        assertEq(info.tickPresetId, 0);
        assertEq(info.decommissionRequestedAt, 0);
        assertEq(info.decommissionAvailableAt, 0);
        assertEq(info.tickSize, 1);
        assertEq(info.priceDenominator, LibCLOBBook.SPOT_PRICE_DENOMINATOR);
        assertEq(info.minTick, 1);
        assertEq(info.maxTick, type(uint128).max);
    }

    function test_CreateSpotBookSnapshotsSpotFeeConfig() public {
        MockUSDC secondSpotToken = new MockUSDC();
        vm.prank(owner);
        ITestStateFacet(address(diamond)).setSpotFeeConfigFixture(75, 8_500, 1_400, 100);

        bytes32 firstBookId =
            _createSpotBook(address(spotToken), LibEveMarket.BaseTransferMode.EXACT, 0, keccak256("spot-fee-a"));

        vm.prank(owner);
        ITestStateFacet(address(diamond)).setSpotFeeConfigFixture(125, 8_000, 1_900, 100);

        bytes32 secondBookId =
            _createSpotBook(address(secondSpotToken), LibEveMarket.BaseTransferMode.EXACT, 0, keccak256("spot-fee-b"));

        CurveCLOBTypes.BookInfo memory firstInfo = IBookAdminFacet(address(diamond)).getBookInfo(firstBookId);
        CurveCLOBTypes.BookInfo memory secondInfo = IBookAdminFacet(address(diamond)).getBookInfo(secondBookId);

        assertEq(firstInfo.entryFeeBps, 75);
        assertEq(firstInfo.makerFeeBps, 8_500);
        assertEq(firstInfo.creatorFeeBps, 0);
        assertEq(firstInfo.protocolFeeBps, 1_400);
        assertEq(firstInfo.vaultFeeBps, 100);

        assertEq(secondInfo.entryFeeBps, 125);
        assertEq(secondInfo.makerFeeBps, 8_000);
        assertEq(secondInfo.creatorFeeBps, 0);
        assertEq(secondInfo.protocolFeeBps, 1_900);
        assertEq(secondInfo.vaultFeeBps, 100);
    }

    function test_CreateSpotBookStoresSelectedTickPreset() public {
        bytes32 bookId = _createSpotBook(
            address(spotToken), LibEveMarket.BaseTransferMode.EXACT, TWENTY_UNIT_TICK_PRESET, keccak256("tick-preset")
        );

        CurveCLOBTypes.BookInfo memory info = IBookAdminFacet(address(diamond)).getBookInfo(bookId);
        assertEq(info.tickPresetId, TWENTY_UNIT_TICK_PRESET);
        assertEq(info.tickSize, TWENTY_UNIT_TICK_SIZE);
        assertEq(info.priceDenominator, LibCLOBBook.SPOT_PRICE_DENOMINATOR);
        assertEq(info.minTick, 1);
        assertEq(info.maxTick, type(uint128).max / TWENTY_UNIT_TICK_SIZE);
    }

    function test_CreateSpotBookRejectsInvalidTickPreset() public {
        vm.startPrank(maker);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidTickPreset.selector, uint8(30)));
        IBookAdminFacet(address(diamond))
            .createBook(
                LibEveMarket.BookAssetType.ERC20,
                LibEveMarket.BaseTransferMode.EXACT,
                address(spotToken),
                0,
                address(usdc),
                30,
                keccak256("invalid-tick-preset")
            );
        vm.stopPrank();
    }

    function test_CreateSpotBookDuplicateDoesNotChargeAgain() public {
        uint128 fee = 250e6;
        bytes32 salt = keccak256("duplicate-fee");
        vm.prank(owner);
        ITestStateFacet(address(diamond)).setSpotBookCreationFeeFixture(fee);

        bytes32 bookId = _createSpotBook(address(spotToken), LibEveMarket.BaseTransferMode.EXACT, 0, salt);
        uint256 makerBefore = usdc.balanceOf(maker);
        uint256 treasuryBefore = usdc.balanceOf(treasury);

        vm.startPrank(maker);
        usdc.approve(address(diamond), fee);
        vm.expectRevert(abi.encodeWithSelector(Errors.BookAlreadyExists.selector, bookId));
        IBookAdminFacet(address(diamond))
            .createBook(
                LibEveMarket.BookAssetType.ERC20,
                LibEveMarket.BaseTransferMode.EXACT,
                address(spotToken),
                0,
                address(usdc),
                0,
                salt
            );
        vm.stopPrank();

        assertEq(usdc.balanceOf(maker), makerBefore);
        assertEq(usdc.balanceOf(treasury), treasuryBefore);
    }

    function test_CreateSpotBookDuplicateOrderedPairRevertsAcrossCreatorsAndConfig() public {
        uint128 fee = 250e6;
        vm.prank(owner);
        ITestStateFacet(address(diamond)).setSpotBookCreationFeeFixture(fee);

        bytes32 bookId = _createSpotBook(address(spotToken), LibEveMarket.BaseTransferMode.EXACT, 0, keccak256("maker"));
        uint256 takerBefore = usdc.balanceOf(taker);
        uint256 treasuryBefore = usdc.balanceOf(treasury);

        vm.startPrank(taker);
        usdc.approve(address(diamond), fee);
        vm.expectRevert(abi.encodeWithSelector(Errors.BookAlreadyExists.selector, bookId));
        IBookAdminFacet(address(diamond))
            .createBook(
                LibEveMarket.BookAssetType.ERC20,
                LibEveMarket.BaseTransferMode.BALANCE_DELTA,
                address(spotToken),
                0,
                address(usdc),
                TWENTY_UNIT_TICK_PRESET,
                keccak256("taker")
            );
        vm.stopPrank();

        assertEq(usdc.balanceOf(taker), takerBefore);
        assertEq(usdc.balanceOf(treasury), treasuryBefore);
    }

    function test_CreateSpotBookAllowsReverseOrderedPair() public {
        bytes32 firstBookId =
            _createSpotBook(address(spotToken), LibEveMarket.BaseTransferMode.EXACT, 0, keccak256("first"));
        bytes32 secondBookId;

        vm.startPrank(maker);
        secondBookId = IBookAdminFacet(address(diamond))
            .createBook(
                LibEveMarket.BookAssetType.ERC20,
                LibEveMarket.BaseTransferMode.BALANCE_DELTA,
                address(usdc),
                0,
                address(spotToken),
                TWENTY_UNIT_TICK_PRESET,
                keccak256("reverse")
            );
        vm.stopPrank();

        assertTrue(firstBookId != secondBookId);

        CurveCLOBTypes.BookInfo memory reverseInfo = IBookAdminFacet(address(diamond)).getBookInfo(secondBookId);
        assertEq(reverseInfo.baseToken, address(usdc));
        assertEq(reverseInfo.quoteToken, address(spotToken));
        assertEq(uint8(reverseInfo.baseTransferMode), uint8(LibEveMarket.BaseTransferMode.BALANCE_DELTA));
        assertEq(reverseInfo.tickPresetId, TWENTY_UNIT_TICK_PRESET);
    }

    function test_BookCreatorCanRequestAndFinalizeDecommission() public {
        bytes32 bookId = _createSpotBook();

        vm.startPrank(maker);
        spotToken.approve(address(diamond), 20e6);
        IBookOrderFacet(address(diamond))
            .postBookCurve(bookId, LibEveMarket.CurveSide.ASK, 10e6, TWO_USDC, TWO_USDC, 120, 0, type(uint8).max);

        IBookAdminFacet(address(diamond)).requestBookDecommission(bookId);
        vm.stopPrank();

        CurveCLOBTypes.BookInfo memory pendingInfo = IBookAdminFacet(address(diamond)).getBookInfo(bookId);
        assertFalse(pendingInfo.active);
        assertEq(pendingInfo.lifecycle, uint8(LibEveMarket.BookLifecycle.DECOMMISSION_PENDING));
        assertEq(pendingInfo.decommissionRequestedAt, uint64(block.timestamp));
        assertEq(pendingInfo.decommissionAvailableAt, uint64(block.timestamp));

        vm.startPrank(maker);
        vm.expectRevert(abi.encodeWithSelector(Errors.BookNotActive.selector, bookId));
        IBookOrderFacet(address(diamond))
            .postBookCurve(bookId, LibEveMarket.CurveSide.ASK, 10e6, TWO_USDC, TWO_USDC, 120, 0, type(uint8).max);

        IBookAdminFacet(address(diamond)).finalizeBookDecommission(bookId);
        vm.stopPrank();

        CurveCLOBTypes.BookInfo memory finalInfo = IBookAdminFacet(address(diamond)).getBookInfo(bookId);
        assertFalse(finalInfo.active);
        assertEq(finalInfo.lifecycle, uint8(LibEveMarket.BookLifecycle.DECOMMISSIONED));
        assertEq(finalInfo.decommissionRequestedAt, pendingInfo.decommissionRequestedAt);
        assertEq(finalInfo.decommissionAvailableAt, pendingInfo.decommissionAvailableAt);
    }

    function test_BookDecommissionRejectsNonController() public {
        bytes32 bookId = _createSpotBook();

        vm.prank(taker);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotBookController.selector, taker, bookId));
        IBookAdminFacet(address(diamond)).requestBookDecommission(bookId);
    }

    function test_BookDecommissionRejectsMarketBooks() public {
        (bytes32 marketId,) = _createMarketFixture("Can market side books be decommissioned?", _expiry(7 days));
        bytes32 yesBookId = LibCLOBBook.marketBookId(marketId, true);

        ITestStateFacet(address(diamond)).materializeMarketSideBookFixture(marketId, true);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Errors.BookDecommissionUnsupported.selector, yesBookId));
        IBookAdminFacet(address(diamond)).requestBookDecommission(yesBookId);
    }

    function test_DiamondOwnerCanDecommissionBook() public {
        bytes32 bookId = _createSpotBook();

        vm.prank(owner);
        IBookAdminFacet(address(diamond)).requestBookDecommission(bookId);

        CurveCLOBTypes.BookInfo memory pendingInfo = IBookAdminFacet(address(diamond)).getBookInfo(bookId);
        assertEq(pendingInfo.lifecycle, uint8(LibEveMarket.BookLifecycle.DECOMMISSION_PENDING));

        vm.prank(owner);
        IBookAdminFacet(address(diamond)).finalizeBookDecommission(bookId);

        CurveCLOBTypes.BookInfo memory finalInfo = IBookAdminFacet(address(diamond)).getBookInfo(bookId);
        assertFalse(finalInfo.active);
        assertEq(finalInfo.lifecycle, uint8(LibEveMarket.BookLifecycle.DECOMMISSIONED));
    }

    function test_ComputeSpotBookIdIgnoresCreatorSaltPresetAndTransferMode() public view {
        bytes32 firstBookId = IBookAdminFacet(address(diamond))
            .computeBookId(
                maker,
                LibEveMarket.BookAssetType.ERC20,
                LibEveMarket.BaseTransferMode.EXACT,
                address(spotToken),
                0,
                address(usdc),
                0,
                keccak256("first")
            );
        bytes32 secondBookId = IBookAdminFacet(address(diamond))
            .computeBookId(
                taker,
                LibEveMarket.BookAssetType.ERC20,
                LibEveMarket.BaseTransferMode.BALANCE_DELTA,
                address(spotToken),
                0,
                address(usdc),
                TWENTY_UNIT_TICK_PRESET,
                keccak256("second")
            );
        bytes32 reverseBookId = IBookAdminFacet(address(diamond))
            .computeBookId(
                maker,
                LibEveMarket.BookAssetType.ERC20,
                LibEveMarket.BaseTransferMode.EXACT,
                address(usdc),
                0,
                address(spotToken),
                0,
                keccak256("reverse")
            );

        assertEq(firstBookId, secondBookId);
        assertTrue(firstBookId != reverseBookId);
    }

    function test_ERC20SpotBookBidFillTransfersBaseToMakerAndQuoteToSeller() public {
        bytes32 bookId = _createSpotBook();

        vm.startPrank(maker);
        usdc.approve(address(diamond), 100e6);
        uint256 curveId = IBookOrderFacet(address(diamond))
            .postBookCurve(bookId, LibEveMarket.CurveSide.BID, 50e6, TWO_USDC, TWO_USDC, 120, 0, type(uint8).max);
        vm.stopPrank();

        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        uint256 makerBaseBefore = spotToken.balanceOf(maker);
        uint256 sellerQuoteBefore = usdc.balanceOf(taker);

        uint256[] memory curveIds = _singleCurve(curveId);
        uint32[] memory generations = _singleGeneration(generation);
        bytes32[] memory commitments = _singleCommitment(commitment);

        vm.startPrank(taker);
        spotToken.approve(address(diamond), 25e6);
        CurveCLOBTypes.SellBookResult memory result = IBookTradeFacet(address(diamond))
            .sellBookBest(
                CurveCLOBTypes.SellBookParams({
                    bookId: bookId,
                    maxBaseIn: 25e6,
                    minQuoteOut: 50e6,
                    curveIds: curveIds,
                    expectedGenerations: generations,
                    expectedCommitments: commitments,
                    receiver: taker
                })
            );
        vm.stopPrank();

        assertEq(result.baseSold, 25e6);
        assertEq(result.quoteOut, 50e6);
        assertEq(spotToken.balanceOf(maker), makerBaseBefore + 25e6);
        assertEq(usdc.balanceOf(taker), sellerQuoteBefore + 50e6);
        assertEq(usdc.balanceOf(address(diamond)), 50e6);
    }

    function test_SpotBookRejectsAskSelfFill() public {
        bytes32 bookId = _createSpotBook();

        vm.startPrank(maker);
        spotToken.approve(address(diamond), 50e6);
        uint256 curveId = IBookOrderFacet(address(diamond))
            .postBookCurve(bookId, LibEveMarket.CurveSide.ASK, 50e6, TWO_USDC, TWO_USDC, 120, 0, type(uint8).max);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        usdc.approve(address(diamond), 100e6);
        CurveCLOBTypes.FillBookParams memory fillParams;
        fillParams.bookId = bookId;
        fillParams.maxQuoteIn = 100e6;
        fillParams.minBaseOut = 50e6;
        fillParams.maxAveragePrice = TWO_USDC;
        fillParams.curveIds = _singleCurve(curveId);
        fillParams.expectedGenerations = _singleGeneration(generation);
        fillParams.expectedCommitments = _singleCommitment(commitment);
        fillParams.payer = maker;
        fillParams.receiver = maker;

        vm.expectRevert(abi.encodeWithSelector(Errors.SelfFillNotAllowed.selector, curveId, maker, maker));
        IBookTradeFacet(address(diamond)).fillBookBest(fillParams);
        vm.stopPrank();
    }

    function test_DirectCurveFillRejectsSelfFill() public {
        bytes32 bookId = _createSpotBook();

        vm.startPrank(maker);
        spotToken.approve(address(diamond), 50e6);
        uint256 curveId = IBookOrderFacet(address(diamond))
            .postBookCurve(bookId, LibEveMarket.CurveSide.ASK, 50e6, TWO_USDC, TWO_USDC, 120, 0, type(uint8).max);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        usdc.approve(address(diamond), 100e6);
        vm.expectRevert(abi.encodeWithSelector(Errors.SelfFillNotAllowed.selector, curveId, maker, maker));
        ICurveTradeFacet(address(diamond)).fillCurve(curveId, 100e6, 50e6, generation, commitment);
        vm.stopPrank();
    }

    function test_SpotBookRejectsBidSelfFill() public {
        bytes32 bookId = _createSpotBook();

        vm.startPrank(maker);
        usdc.approve(address(diamond), 100e6);
        uint256 curveId = IBookOrderFacet(address(diamond))
            .postBookCurve(bookId, LibEveMarket.CurveSide.BID, 50e6, TWO_USDC, TWO_USDC, 120, 0, type(uint8).max);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        spotToken.approve(address(diamond), 10e6);
        vm.expectRevert(abi.encodeWithSelector(Errors.SelfFillNotAllowed.selector, curveId, maker, maker));
        IBookTradeFacet(address(diamond))
            .sellBookBest(
                CurveCLOBTypes.SellBookParams({
                    bookId: bookId,
                    maxBaseIn: 10e6,
                    minQuoteOut: 20e6,
                    curveIds: _singleCurve(curveId),
                    expectedGenerations: _singleGeneration(generation),
                    expectedCommitments: _singleCommitment(commitment),
                    receiver: maker
                })
            );
        vm.stopPrank();
    }

    function test_ReactivateExpiredAskCurveReusesCurveIdAndBaseEscrow() public {
        bytes32 bookId = _createSpotBook();

        vm.startPrank(maker);
        spotToken.approve(address(diamond), 100e6);
        uint256 curveId = IBookOrderFacet(address(diamond))
            .postBookCurve(bookId, LibEveMarket.CurveSide.ASK, 100e6, TWO_USDC, TWO_USDC, 1, 0, type(uint8).max);
        vm.stopPrank();

        vm.warp(block.timestamp + 2 minutes);

        uint256 makerBaseBefore = spotToken.balanceOf(maker);
        uint256 newPacked = LibCurvePacking.pack(ONE_POINT_EIGHT_USDC, ONE_POINT_EIGHT_USDC, 120, 0, 0, bytes32(0));

        vm.prank(maker);
        IBookOrderFacet(address(diamond)).reactivateBookCurve(bookId, curveId, 40e6, newPacked, 1);

        CurveCLOBTypes.CurveInfo memory info = ICurveViewFacet(address(diamond)).getCurveInfo(curveId);
        assertEq(info.remainingVolume, 40e6);
        assertEq(info.generation, 2);
        assertEq(info.packed, newPacked);
        assertEq(info.expiresAt, block.timestamp + 120 minutes);
        assertEq(spotToken.balanceOf(maker), makerBaseBefore + 60e6);
        assertEq(spotToken.balanceOf(address(diamond)), 40e6);

        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        vm.startPrank(taker);
        usdc.approve(address(diamond), 72e6);
        uint128 baseOut = ICurveTradeFacet(address(diamond)).fillCurve(curveId, 72e6, 40e6, generation, commitment);
        vm.stopPrank();

        assertEq(baseOut, 40e6);
    }

    function test_ReactivateDepletedBidCurveCollectsFreshQuoteEscrow() public {
        bytes32 bookId = _createSpotBook();

        vm.startPrank(maker);
        usdc.approve(address(diamond), 200e6);
        uint256 curveId = IBookOrderFacet(address(diamond))
            .postBookCurve(bookId, LibEveMarket.CurveSide.BID, 50e6, TWO_USDC, TWO_USDC, 120, 0, type(uint8).max);
        vm.stopPrank();

        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        vm.startPrank(taker);
        spotToken.approve(address(diamond), 50e6);
        IBookTradeFacet(address(diamond))
            .sellBookBest(
                CurveCLOBTypes.SellBookParams({
                    bookId: bookId,
                    maxBaseIn: 50e6,
                    minQuoteOut: 100e6,
                    curveIds: _singleCurve(curveId),
                    expectedGenerations: _singleGeneration(generation),
                    expectedCommitments: _singleCommitment(commitment),
                    receiver: taker
                })
            );
        vm.stopPrank();

        CurveCLOBTypes.CurveInfo memory depleted = ICurveViewFacet(address(diamond)).getCurveInfo(curveId);
        assertEq(depleted.remainingVolume, 0);
        assertEq(depleted.quoteEscrowRemaining, 0);

        uint256 newPacked = LibCurvePacking.pack(ONE_POINT_EIGHT_USDC, ONE_POINT_EIGHT_USDC, 120, 0, 0, bytes32(0));
        vm.prank(maker);
        IBookOrderFacet(address(diamond)).reactivateBookCurve(bookId, curveId, 25e6, newPacked, 1);

        CurveCLOBTypes.CurveInfo memory reactivated = ICurveViewFacet(address(diamond)).getCurveInfo(curveId);
        assertEq(reactivated.remainingVolume, 25e6);
        assertEq(reactivated.quoteEscrowRemaining, 45e6);
        assertEq(reactivated.generation, 2);
        assertEq(usdc.balanceOf(address(diamond)), 45e6);
    }

    function test_SpotBookBidExecutionUsesSelectedTickPreset() public {
        uint72 priceTick = _tickForPrice(TWO_USDC, TWENTY_UNIT_TICK_SIZE);
        bytes32 bookId = _createSpotBook(
            address(spotToken), LibEveMarket.BaseTransferMode.EXACT, TWENTY_UNIT_TICK_PRESET, keccak256("bid-preset")
        );

        vm.startPrank(maker);
        usdc.approve(address(diamond), 100e6);
        uint256 curveId = IBookOrderFacet(address(diamond))
            .postBookCurve(bookId, LibEveMarket.CurveSide.BID, 50e6, priceTick, priceTick, 120, 0, type(uint8).max);
        vm.stopPrank();

        CurveCLOBTypes.CurveInfo memory posted = ICurveViewFacet(address(diamond)).getCurveInfo(curveId);
        assertEq(posted.currentPrice, TWO_USDC);
        assertEq(posted.quoteEscrowRemaining, 100e6);

        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        vm.startPrank(taker);
        spotToken.approve(address(diamond), 25e6);
        CurveCLOBTypes.SellBookResult memory result = IBookTradeFacet(address(diamond))
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

        assertEq(result.baseSold, 25e6);
        assertEq(result.quoteOut, 50e6);
        assertEq(result.averagePrice, TWO_USDC);

        CurveCLOBTypes.CurveInfo memory filled = ICurveViewFacet(address(diamond)).getCurveInfo(curveId);
        assertEq(filled.remainingVolume, 25e6);
        assertEq(filled.quoteEscrowRemaining, 50e6);
    }

    function test_SpotBookPreviewAndTopOfBookUseSelectedTickPreset() public {
        uint72 askTick = _tickForPrice(TWO_USDC, TWENTY_UNIT_TICK_SIZE);
        uint72 bidTick = _tickForPrice(ONE_POINT_EIGHT_USDC, TWENTY_UNIT_TICK_SIZE);
        bytes32 bookId = _createSpotBook(
            address(spotToken), LibEveMarket.BaseTransferMode.EXACT, TWENTY_UNIT_TICK_PRESET, keccak256("view-preset")
        );

        vm.startPrank(maker);
        spotToken.approve(address(diamond), 100e6);
        usdc.approve(address(diamond), 90e6);
        uint256 askCurveId = IBookOrderFacet(address(diamond))
            .postBookCurve(bookId, LibEveMarket.CurveSide.ASK, 100e6, askTick, askTick, 120, 0, type(uint8).max);
        IBookOrderFacet(address(diamond))
            .postBookCurve(bookId, LibEveMarket.CurveSide.BID, 50e6, bidTick, bidTick, 120, 0, type(uint8).max);
        vm.stopPrank();

        (uint128 baseOut, uint128 fee, uint128 averagePrice, uint128 unfilledQuote) =
            IBookViewFacet(address(diamond)).previewBookExecution(bookId, 200e6, _singleCurve(askCurveId));

        assertEq(baseOut, 100e6);
        assertEq(fee, 0);
        assertEq(averagePrice, TWO_USDC);
        assertEq(unfilledQuote, 0);

        (uint128 bestAskPrice, uint128 bestBidPrice, uint128 midpointPrice,) =
            IBookViewFacet(address(diamond)).getBookTopOfBook(bookId);
        assertEq(bestAskPrice, TWO_USDC);
        assertEq(bestBidPrice, ONE_POINT_EIGHT_USDC);
        assertEq(midpointPrice, 1_900_000_000_000_000_000);
    }

    function test_SameSpotBookSupportsMixedCurveTickPresets() public {
        bytes32 bookId = _createSpotBook();
        uint72 fineTick = _tickForPrice(TWO_USDC, 1);
        uint72 coarseTick = _tickForPrice(ONE_POINT_EIGHT_USDC, TWENTY_UNIT_TICK_SIZE);

        vm.startPrank(maker);
        spotToken.approve(address(diamond), 100e6);
        uint256 fineCurveId = IBookOrderFacet(address(diamond))
            .postBookCurve(bookId, LibEveMarket.CurveSide.ASK, 50e6, fineTick, fineTick, 120, 0, 0);
        uint256 coarseCurveId = IBookOrderFacet(address(diamond))
            .postBookCurve(
                bookId, LibEveMarket.CurveSide.ASK, 50e6, coarseTick, coarseTick, 120, 0, TWENTY_UNIT_TICK_PRESET
            );
        vm.stopPrank();

        CurveCLOBTypes.CurveInfo memory fineInfo = ICurveViewFacet(address(diamond)).getCurveInfo(fineCurveId);
        CurveCLOBTypes.CurveInfo memory coarseInfo = ICurveViewFacet(address(diamond)).getCurveInfo(coarseCurveId);

        assertEq(fineInfo.tickPresetId, 0);
        assertEq(fineInfo.currentPrice, TWO_USDC);
        assertEq(coarseInfo.tickPresetId, TWENTY_UNIT_TICK_PRESET);
        assertEq(coarseInfo.currentPrice, ONE_POINT_EIGHT_USDC);
    }

    function test_FillBookBestOrdersMixedPresetsByActualAskPrice() public {
        bytes32 bookId = _createSpotBook();
        uint72 expensiveTick = _tickForPrice(TWO_USDC, 1);
        uint72 cheaperTick = _tickForPrice(ONE_POINT_EIGHT_USDC, TWENTY_UNIT_TICK_SIZE);

        vm.startPrank(maker);
        spotToken.approve(address(diamond), 100e6);
        uint256 expensiveCurveId = IBookOrderFacet(address(diamond))
            .postBookCurve(bookId, LibEveMarket.CurveSide.ASK, 50e6, expensiveTick, expensiveTick, 120, 0, 0);
        uint256 cheaperCurveId = IBookOrderFacet(address(diamond))
            .postBookCurve(
                bookId, LibEveMarket.CurveSide.ASK, 50e6, cheaperTick, cheaperTick, 120, 0, TWENTY_UNIT_TICK_PRESET
            );
        vm.stopPrank();

        uint256[] memory curveIds = _twoCurves(expensiveCurveId, cheaperCurveId);
        (uint32 expensiveGeneration, bytes32 expensiveCommitment) =
            ICurveViewFacet(address(diamond)).getCurveCommitment(expensiveCurveId);
        (uint32 cheaperGeneration, bytes32 cheaperCommitment) =
            ICurveViewFacet(address(diamond)).getCurveCommitment(cheaperCurveId);

        (uint128 previewBaseOut,, uint128 previewAveragePrice,) =
            IBookViewFacet(address(diamond)).previewBookExecution(bookId, 90e6, curveIds);
        assertEq(previewBaseOut, 50e6);
        assertEq(previewAveragePrice, ONE_POINT_EIGHT_USDC);

        vm.startPrank(taker);
        usdc.approve(address(diamond), 90e6);
        CurveCLOBTypes.FillBookParams memory fillParams;
        fillParams.bookId = bookId;
        fillParams.maxQuoteIn = 90e6;
        fillParams.minBaseOut = 50e6;
        fillParams.maxAveragePrice = ONE_POINT_EIGHT_USDC;
        fillParams.curveIds = curveIds;
        fillParams.expectedGenerations = _twoGenerations(expensiveGeneration, cheaperGeneration);
        fillParams.expectedCommitments = _twoCommitments(expensiveCommitment, cheaperCommitment);
        fillParams.payer = taker;
        fillParams.receiver = taker;
        CurveCLOBTypes.FillBestResult memory result = IBookTradeFacet(address(diamond)).fillBookBest(fillParams);
        vm.stopPrank();

        assertEq(result.sharesOut, 50e6);
        assertEq(result.averagePrice, ONE_POINT_EIGHT_USDC);
        assertEq(ICurveViewFacet(address(diamond)).getCurveInfo(cheaperCurveId).remainingVolume, 0);
        assertEq(ICurveViewFacet(address(diamond)).getCurveInfo(expensiveCurveId).remainingVolume, 50e6);
    }

    function test_UpdateCurveChangesSpotPresetInPlaceAndSyncsBidEscrow() public {
        bytes32 bookId = _createSpotBook();
        uint72 oldTick = _tickForPrice(ONE_POINT_EIGHT_USDC, 1);
        uint72 newTick = _tickForPrice(TWO_USDC, TWENTY_UNIT_TICK_SIZE);

        vm.startPrank(maker);
        usdc.approve(address(diamond), 110e6);
        uint256 curveId = IBookOrderFacet(address(diamond))
            .postBookCurve(bookId, LibEveMarket.CurveSide.BID, 50e6, oldTick, oldTick, 120, 0, 0);
        uint256 newPacked = LibCurvePacking.pack(newTick, newTick, 120, 0, TWENTY_UNIT_TICK_PRESET, bytes32(0));
        ICurveLifecycleFacet(address(diamond)).updateCurve(curveId, newPacked, 1);
        vm.stopPrank();

        CurveCLOBTypes.CurveInfo memory raised = ICurveViewFacet(address(diamond)).getCurveInfo(curveId);
        assertEq(raised.tickPresetId, TWENTY_UNIT_TICK_PRESET);
        assertEq(raised.currentPrice, TWO_USDC);
        assertEq(raised.quoteEscrowRemaining, 100e6);
        assertEq(raised.generation, 2);

        uint256 makerQuoteBefore = usdc.balanceOf(maker);
        uint256 lowerPacked = LibCurvePacking.pack(oldTick, oldTick, 120, 0, 0, bytes32(0));
        vm.prank(maker);
        ICurveLifecycleFacet(address(diamond)).updateCurve(curveId, lowerPacked, 2);

        CurveCLOBTypes.CurveInfo memory lowered = ICurveViewFacet(address(diamond)).getCurveInfo(curveId);
        assertEq(lowered.tickPresetId, 0);
        assertEq(lowered.currentPrice, ONE_POINT_EIGHT_USDC);
        assertEq(lowered.quoteEscrowRemaining, 90e6);
        assertEq(usdc.balanceOf(maker), makerQuoteBefore + 10e6);
    }

    function test_UpdateCurveFromNowChangesSpotBidAndResetsClock() public {
        bytes32 bookId = _createSpotBook();
        uint72 oldTick = _tickForPrice(ONE_POINT_EIGHT_USDC, 1);
        uint72 newTick = _tickForPrice(TWO_USDC, TWENTY_UNIT_TICK_SIZE);

        vm.startPrank(maker);
        usdc.approve(address(diamond), 110e6);
        uint256 curveId = IBookOrderFacet(address(diamond))
            .postBookCurve(bookId, LibEveMarket.CurveSide.BID, 50e6, oldTick, oldTick, 120, 0, 0);
        vm.stopPrank();

        CurveCLOBTypes.CurveInfo memory original = ICurveViewFacet(address(diamond)).getCurveInfo(curveId);
        uint256 newPacked = LibCurvePacking.pack(newTick, newTick, 120, 0, TWENTY_UNIT_TICK_PRESET, bytes32(0));

        vm.warp(block.timestamp + 15 minutes);
        uint64 resetCreatedAt = uint64(block.timestamp);

        vm.prank(maker);
        ICurveLifecycleFacet(address(diamond)).updateCurveFromNow(curveId, newPacked, 1);

        CurveCLOBTypes.CurveInfo memory updated = ICurveViewFacet(address(diamond)).getCurveInfo(curveId);
        assertEq(updated.tickPresetId, TWENTY_UNIT_TICK_PRESET);
        assertEq(updated.currentPrice, TWO_USDC);
        assertEq(updated.quoteEscrowRemaining, 100e6);
        assertEq(updated.generation, 2);
        assertEq(updated.createdAt, resetCreatedAt);
        assertGt(updated.createdAt, original.createdAt);
    }

    function test_UpdateCurvesBatchChangesSpotPresetsAcrossCurves() public {
        bytes32 bookId = _createSpotBook();
        uint72 oldTick = _tickForPrice(TWO_USDC, 1);
        uint72 newTick = _tickForPrice(TWO_USDC, TWENTY_UNIT_TICK_SIZE);

        vm.startPrank(maker);
        spotToken.approve(address(diamond), 100e6);
        uint256 firstCurveId = IBookOrderFacet(address(diamond))
            .postBookCurve(bookId, LibEveMarket.CurveSide.ASK, 50e6, oldTick, oldTick, 120, 0, 0);
        uint256 secondCurveId = IBookOrderFacet(address(diamond))
            .postBookCurve(bookId, LibEveMarket.CurveSide.ASK, 50e6, oldTick, oldTick, 120, 0, 0);

        CurveCLOBTypes.CurveUpdateParams[] memory params = new CurveCLOBTypes.CurveUpdateParams[](2);
        params[0] = CurveCLOBTypes.CurveUpdateParams({
            curveId: firstCurveId,
            newPacked: LibCurvePacking.pack(newTick, newTick, 120, 0, TWENTY_UNIT_TICK_PRESET, bytes32(0)),
            expectedGeneration: 1
        });
        params[1] = CurveCLOBTypes.CurveUpdateParams({
            curveId: secondCurveId,
            newPacked: LibCurvePacking.pack(newTick, newTick, 120, 0, TWENTY_UNIT_TICK_PRESET, bytes32(0)),
            expectedGeneration: 1
        });
        ICurveLifecycleFacet(address(diamond)).updateCurvesBatch(params);
        vm.stopPrank();

        assertEq(ICurveViewFacet(address(diamond)).getCurveInfo(firstCurveId).tickPresetId, TWENTY_UNIT_TICK_PRESET);
        assertEq(ICurveViewFacet(address(diamond)).getCurveInfo(secondCurveId).tickPresetId, TWENTY_UNIT_TICK_PRESET);
    }

    function test_ERC20SpotBookTopUpAddsBaseWithoutChangingGeneration() public {
        bytes32 bookId = _createSpotBook();

        vm.startPrank(maker);
        spotToken.approve(address(diamond), 150e6);
        uint256 curveId = IBookOrderFacet(address(diamond))
            .postBookCurve(bookId, LibEveMarket.CurveSide.ASK, 100e6, TWO_USDC, TWO_USDC, 120, 0, type(uint8).max);

        CurveCLOBTypes.CurveTopUpParams[] memory params = new CurveCLOBTypes.CurveTopUpParams[](1);
        params[0] = CurveCLOBTypes.CurveTopUpParams({curveId: curveId, addedVolume: 50e6});
        IBookOrderFacet(address(diamond)).topUpBookCurvesBatch(bookId, params);
        vm.stopPrank();

        CurveCLOBTypes.CurveInfo memory info = ICurveViewFacet(address(diamond)).getCurveInfo(curveId);
        assertEq(info.remainingVolume, 150e6);
        assertEq(info.generation, 1);
        assertEq(spotToken.balanceOf(address(diamond)), 150e6);
    }

    function test_MismatchedDecimalSpotBookPostCancelReturnsBaseEscrow() public {
        MockEveToken base18 = new MockEveToken();
        base18.mint(maker, 10e18);
        bytes32 bookId =
            _createSpotBook(address(base18), LibEveMarket.BaseTransferMode.EXACT, 0, keccak256("18-6-cancel"));

        uint256 makerBefore = base18.balanceOf(maker);
        vm.startPrank(maker);
        base18.approve(address(diamond), 1e18);
        uint256 curveId = IBookOrderFacet(address(diamond))
            .postBookCurve(bookId, LibEveMarket.CurveSide.ASK, 1e18, 2, 2, 120, 0, type(uint8).max);
        assertEq(base18.balanceOf(maker), makerBefore - 1e18);

        ICurveLifecycleFacet(address(diamond)).cancelCurve(curveId);
        vm.stopPrank();

        CurveCLOBTypes.CurveInfo memory info = ICurveViewFacet(address(diamond)).getCurveInfo(curveId);
        assertFalse(info.active);
        assertEq(base18.balanceOf(maker), makerBefore);
        assertEq(base18.balanceOf(address(diamond)), 0);
    }

    function test_EveUsdcSpotBookQuotesAndFillsMicroEvePrice() public {
        MockEveToken eveBase = new MockEveToken();
        EveUSDC microEveUSDC = new EveUSDC(address(usdc), address(this), address(this));

        eveBase.mint(maker, 10_000e18);
        usdc.mint(taker, 1e6);

        ITestStateFacet(address(diamond)).setSpotBookCreationFeeFixture(0);

        vm.prank(maker);
        bytes32 bookId = IBookAdminFacet(address(diamond))
            .createBook(
                LibEveMarket.BookAssetType.ERC20,
                LibEveMarket.BaseTransferMode.EXACT,
                address(eveBase),
                0,
                address(microEveUSDC),
                0,
                keccak256("eve-eveusdc-micro-price")
            );

        vm.startPrank(maker);
        eveBase.approve(address(diamond), MICRO_EVE_BASE_AMOUNT);
        uint256 curveId = IBookOrderFacet(address(diamond))
            .postBookCurve(
                bookId, LibEveMarket.CurveSide.ASK, MICRO_EVE_BASE_AMOUNT, MICRO_EVE_PRICE, MICRO_EVE_PRICE, 120, 0, 0
            );
        vm.stopPrank();

        uint256[] memory curveIds = _singleCurve(curveId);
        (uint128 previewBaseOut, uint128 previewFee, uint128 previewAveragePrice, uint128 unfilledQuote) =
            IBookViewFacet(address(diamond)).previewBookExecution(bookId, MICRO_EVE_QUOTE_IN, curveIds);
        assertEq(previewBaseOut, MICRO_EVE_BASE_AMOUNT);
        assertEq(previewFee, 0);
        assertEq(previewAveragePrice, MICRO_EVE_PRICE);
        assertEq(unfilledQuote, 0);

        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        vm.startPrank(taker);
        usdc.approve(address(microEveUSDC), 1e6);
        microEveUSDC.wrap(1e6, taker);
        microEveUSDC.approve(address(diamond), MICRO_EVE_QUOTE_IN);
        CurveCLOBTypes.FillBestResult memory result = _fillSingleBookCurve(
            bookId, curveId, MICRO_EVE_QUOTE_IN, MICRO_EVE_BASE_AMOUNT, MICRO_EVE_PRICE, generation, commitment
        );
        vm.stopPrank();

        assertEq(result.sharesOut, MICRO_EVE_BASE_AMOUNT);
        assertEq(result.collateralUsed, MICRO_EVE_QUOTE_IN);
        assertEq(result.averagePrice, MICRO_EVE_PRICE);
        assertEq(eveBase.balanceOf(taker), MICRO_EVE_BASE_AMOUNT);
        assertEq(microEveUSDC.balanceOf(maker), MICRO_EVE_QUOTE_IN);
    }

    function _fillSingleBookCurve(
        bytes32 bookId,
        uint256 curveId,
        uint128 quoteIn,
        uint128 baseOut,
        uint128 maxAveragePrice,
        uint32 generation,
        bytes32 commitment
    ) internal returns (CurveCLOBTypes.FillBestResult memory result) {
        CurveCLOBTypes.FillBookParams memory fillParams;
        fillParams.bookId = bookId;
        fillParams.maxQuoteIn = quoteIn;
        fillParams.minBaseOut = baseOut;
        fillParams.maxAveragePrice = maxAveragePrice;
        fillParams.curveIds = _singleCurve(curveId);
        fillParams.expectedGenerations = _singleGeneration(generation);
        fillParams.expectedCommitments = _singleCommitment(commitment);
        fillParams.payer = taker;
        fillParams.receiver = taker;
        result = IBookTradeFacet(address(diamond)).fillBookBest(fillParams);
    }

    function test_ExactModeRejectsFeeOnTransferBaseOnAskPost() public {
        MockFeeOnTransferToken feeToken = new MockFeeOnTransferToken(100);
        feeToken.mint(maker, 1_000e6);
        bytes32 bookId =
            _createSpotBook(address(feeToken), LibEveMarket.BaseTransferMode.EXACT, 0, keccak256("fot-exact"));

        vm.startPrank(maker);
        feeToken.approve(address(diamond), 100e6);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.BaseTransferDeltaMismatch.selector, address(feeToken), 100e6, 99e6)
        );
        IBookOrderFacet(address(diamond))
            .postBookCurve(bookId, LibEveMarket.CurveSide.ASK, 100e6, TWO_USDC, TWO_USDC, 120, 0, type(uint8).max);
        vm.stopPrank();
    }

    function test_BalanceDeltaModePricesActualDeliveredBaseOnAskFill() public {
        MockFeeOnTransferToken feeToken = new MockFeeOnTransferToken(100);
        feeToken.mint(maker, 1_000e6);
        bytes32 bookId =
            _createSpotBook(address(feeToken), LibEveMarket.BaseTransferMode.BALANCE_DELTA, 0, keccak256("fot-ask"));

        vm.startPrank(maker);
        feeToken.approve(address(diamond), 100e6);
        uint256 curveId = IBookOrderFacet(address(diamond))
            .postBookCurve(bookId, LibEveMarket.CurveSide.ASK, 100e6, TWO_USDC, TWO_USDC, 120, 0, type(uint8).max);
        vm.stopPrank();

        CurveCLOBTypes.CurveInfo memory posted = ICurveViewFacet(address(diamond)).getCurveInfo(curveId);
        assertEq(posted.remainingVolume, 99e6);
        assertEq(feeToken.balanceOf(address(diamond)), 99e6);

        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        uint256 takerQuoteBefore = usdc.balanceOf(taker);
        uint256 makerQuoteBefore = usdc.balanceOf(maker);

        vm.startPrank(taker);
        usdc.approve(address(diamond), 100e6);
        uint128 baseOut = ICurveTradeFacet(address(diamond)).fillCurve(curveId, 100e6, 49e6, generation, commitment);
        vm.stopPrank();

        assertEq(baseOut, 49_500_000);
        assertEq(feeToken.balanceOf(taker), 49_500_000);
        assertEq(usdc.balanceOf(maker) - makerQuoteBefore, 99e6);
        assertEq(takerQuoteBefore - usdc.balanceOf(taker), 99e6);

        CurveCLOBTypes.CurveInfo memory filled = ICurveViewFacet(address(diamond)).getCurveInfo(curveId);
        assertEq(filled.remainingVolume, 49e6);
    }

    function test_BalanceDeltaModePricesActualReceivedBaseOnBidFill() public {
        MockFeeOnTransferToken feeToken = new MockFeeOnTransferToken(100);
        feeToken.mint(taker, 1_000e6);
        bytes32 bookId =
            _createSpotBook(address(feeToken), LibEveMarket.BaseTransferMode.BALANCE_DELTA, 0, keccak256("fot-bid"));

        vm.startPrank(maker);
        usdc.approve(address(diamond), 100e6);
        uint256 curveId = IBookOrderFacet(address(diamond))
            .postBookCurve(bookId, LibEveMarket.CurveSide.BID, 50e6, TWO_USDC, TWO_USDC, 120, 0, type(uint8).max);
        vm.stopPrank();

        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        uint256 makerBaseBefore = feeToken.balanceOf(maker);
        uint256 sellerQuoteBefore = usdc.balanceOf(taker);

        vm.startPrank(taker);
        feeToken.approve(address(diamond), 10e6);
        CurveCLOBTypes.SellBookResult memory result = IBookTradeFacet(address(diamond))
            .sellBookBest(
                CurveCLOBTypes.SellBookParams({
                    bookId: bookId,
                    maxBaseIn: 10e6,
                    minQuoteOut: 19e6,
                    curveIds: _singleCurve(curveId),
                    expectedGenerations: _singleGeneration(generation),
                    expectedCommitments: _singleCommitment(commitment),
                    receiver: taker
                })
            );
        vm.stopPrank();

        assertEq(result.baseSold, 9_900_000);
        assertEq(result.quoteOut, 19_800_000);
        assertEq(feeToken.balanceOf(maker) - makerBaseBefore, 9_900_000);
        assertEq(usdc.balanceOf(taker) - sellerQuoteBefore, 19_800_000);

        CurveCLOBTypes.CurveInfo memory filled = ICurveViewFacet(address(diamond)).getCurveInfo(curveId);
        assertEq(filled.remainingVolume, 40_100_000);
        assertEq(filled.quoteEscrowRemaining, 80_200_000);
    }

    function test_BalanceDeltaModeTopUpCreditsActualReceivedBase() public {
        MockFeeOnTransferToken feeToken = new MockFeeOnTransferToken(100);
        feeToken.mint(maker, 1_000e6);
        bytes32 bookId =
            _createSpotBook(address(feeToken), LibEveMarket.BaseTransferMode.BALANCE_DELTA, 0, keccak256("fot-topup"));

        vm.startPrank(maker);
        feeToken.approve(address(diamond), 200e6);
        uint256 curveId = IBookOrderFacet(address(diamond))
            .postBookCurve(bookId, LibEveMarket.CurveSide.ASK, 100e6, TWO_USDC, TWO_USDC, 120, 0, type(uint8).max);

        CurveCLOBTypes.CurveTopUpParams[] memory params = new CurveCLOBTypes.CurveTopUpParams[](1);
        params[0] = CurveCLOBTypes.CurveTopUpParams({curveId: curveId, addedVolume: 100e6});
        IBookOrderFacet(address(diamond)).topUpBookCurvesBatch(bookId, params);
        vm.stopPrank();

        CurveCLOBTypes.CurveInfo memory info = ICurveViewFacet(address(diamond)).getCurveInfo(curveId);
        assertEq(info.remainingVolume, 198e6);
        assertEq(feeToken.balanceOf(address(diamond)), 198e6);
    }

    function test_PredictionBooksStillRejectAboveOnePrices() public {
        (bytes32 marketId,) = _createMarketFixture("Will spot books keep binary prices bounded?", _expiry(7 days));
        _splitFrom(maker, marketId, 100e6);

        vm.startPrank(maker);
        vm.expectRevert(LibCurvePacking.CurvePriceOutOfRange.selector);
        ICurveLifecycleFacet(address(diamond))
            .postCurve(marketId, true, 10e6, TWO_USDC, TWO_USDC, 120, 0, LibEveMarket.PositionTokenType.CTF);
        vm.stopPrank();
    }

    function test_PredictionBooksSetPayoutTickDefaults() public {
        (bytes32 marketId,) = _createMarketFixture("Do prediction books inherit payout ticks?", _expiry(7 days));

        bytes32 yesBookId = LibCLOBBook.marketBookId(marketId, true);
        ITestStateFacet(address(diamond)).materializeMarketSideBookFixture(marketId, true);

        CurveCLOBTypes.BookInfo memory info = IBookAdminFacet(address(diamond)).getBookInfo(yesBookId);
        assertEq(info.pricingMode, uint8(LibEveMarket.BookPricingMode.PREDICTION_PAYOUT));
        assertEq(info.lifecycle, uint8(LibEveMarket.BookLifecycle.ACTIVE));
        assertEq(info.tickPresetId, 0);
        assertEq(info.decommissionRequestedAt, 0);
        assertEq(info.decommissionAvailableAt, 0);
        assertEq(info.tickSize, 1);
        assertEq(info.priceDenominator, uint128(LibCurvePacking.PRICE_SCALE));
        assertEq(info.minTick, 1);
        assertEq(info.maxTick, uint128(LibCurvePacking.PRICE_SCALE));
    }

    function _createSpotBook() internal returns (bytes32 bookId) {
        bookId = _createSpotBook(address(spotToken), LibEveMarket.BaseTransferMode.EXACT, 0, SPOT_SALT);
    }

    function _createSpotBook(
        address baseToken,
        LibEveMarket.BaseTransferMode transferMode,
        uint8 tickPresetId,
        bytes32 salt
    ) internal returns (bytes32 bookId) {
        uint128 fee = ITestStateFacet(address(diamond)).spotBookCreationFeeFixture();
        vm.startPrank(maker);
        if (fee != 0) {
            usdc.approve(address(diamond), fee);
        }
        bookId = IBookAdminFacet(address(diamond))
            .createBook(LibEveMarket.BookAssetType.ERC20, transferMode, baseToken, 0, address(usdc), tickPresetId, salt);
        vm.stopPrank();

        CurveCLOBTypes.BookInfo memory info = IBookAdminFacet(address(diamond)).getBookInfo(bookId);
        assertEq(info.bookId, bookId);
        assertEq(uint8(info.assetType), uint8(LibEveMarket.BookAssetType.ERC20));
        assertEq(uint8(info.baseTransferMode), uint8(transferMode));
        assertEq(info.baseToken, baseToken);
        assertEq(info.quoteToken, address(usdc));
        assertEq(info.creator, maker);
        assertEq(info.marketId, bytes32(0));
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

    function _twoCurves(uint256 firstCurveId, uint256 secondCurveId) internal pure returns (uint256[] memory curveIds) {
        curveIds = new uint256[](2);
        curveIds[0] = firstCurveId;
        curveIds[1] = secondCurveId;
    }

    function _singleGeneration(uint32 generation) internal pure returns (uint32[] memory generations) {
        generations = new uint32[](1);
        generations[0] = generation;
    }

    function _twoGenerations(uint32 firstGeneration, uint32 secondGeneration)
        internal
        pure
        returns (uint32[] memory generations)
    {
        generations = new uint32[](2);
        generations[0] = firstGeneration;
        generations[1] = secondGeneration;
    }

    function _singleCommitment(bytes32 commitment) internal pure returns (bytes32[] memory commitments) {
        commitments = new bytes32[](1);
        commitments[0] = commitment;
    }

    function _twoCommitments(bytes32 firstCommitment, bytes32 secondCommitment)
        internal
        pure
        returns (bytes32[] memory commitments)
    {
        commitments = new bytes32[](2);
        commitments[0] = firstCommitment;
        commitments[1] = secondCommitment;
    }

    function _tickForPrice(uint72 price, uint128 tickSize) internal pure returns (uint72 tick) {
        tick = uint72(uint256(price) / tickSize);
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
