// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC1155Receiver} from "../../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155Receiver.sol";

import {CurveCLOBFacet} from "../../src/facets/CurveCLOBFacet.sol";
import {CurveLifecycleFacet} from "../../src/facets/CurveLifecycleFacet.sol";
import {CurveViewFacet} from "../../src/facets/CurveViewFacet.sol";
import {BookFacet} from "../../src/facets/BookFacet.sol";
import {BookOrderFacet} from "../../src/facets/BookOrderFacet.sol";
import {IBookAdminFacet} from "../../src/interfaces/IBookAdminFacet.sol";
import {IBookOrderFacet} from "../../src/interfaces/IBookOrderFacet.sol";
import {IBookTradeFacet} from "../../src/interfaces/IBookTradeFacet.sol";
import {IBookViewFacet} from "../../src/interfaces/IBookViewFacet.sol";
import {ICurveInventoryFacet} from "../../src/interfaces/ICurveInventoryFacet.sol";
import {ICurveLifecycleFacet} from "../../src/interfaces/ICurveLifecycleFacet.sol";
import {ICurveTradeFacet} from "../../src/interfaces/ICurveTradeFacet.sol";
import {ICurveViewFacet} from "../../src/interfaces/ICurveViewFacet.sol";
import {CurveCLOBTypes} from "../../src/types/CurveCLOBTypes.sol";
import {IOBRResolutionFacet} from "../../src/interfaces/IOBRResolutionFacet.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {Events} from "../../src/libraries/Events.sol";
import {LibCurvePacking} from "../../src/libraries/LibCurvePacking.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {LibReentrancy} from "../../src/libraries/LibReentrancy.sol";

import {
    CurveTradingFixture,
    ResolutionFixture,
    ResolutionHarnessFacet,
    StateProbeFacet
} from "../helpers/DiamondFixtures.sol";
import {MockUSDG} from "../helpers/MockUSDG.sol";
import {ITestStateFacet, TestBase} from "../helpers/TestBase.sol";

contract MaliciousCurveProfile {
    uint128 public overflowPrice;

    function setOverflowPrice(uint128 newPrice) external {
        overflowPrice = newPrice;
    }

    function computePrice(uint128, uint128, uint64, uint64, uint64, bytes32) external view returns (uint128) {
        return overflowPrice;
    }
}

contract UpdateCurveReentrantReceiver is IERC1155Receiver {
    address public diamond;
    uint256 public curveId;
    uint256 public newPacked;
    uint32 public generation;
    bytes4 public observedRevertSelector;
    bool public useBatch;

    function configure(address diamond_, uint256 curveId_, uint256 newPacked_, uint32 generation_, bool useBatch_)
        external
    {
        diamond = diamond_;
        curveId = curveId_;
        newPacked = newPacked_;
        generation = generation_;
        useBatch = useBatch_;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external returns (bytes4) {
        try this.triggerReentrantUpdate() {}
        catch (bytes memory reason) {
            if (reason.length >= 4) {
                bytes4 selector;
                assembly {
                    selector := mload(add(reason, 32))
                }
                observedRevertSelector = selector;
            }
        }
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function triggerReentrantUpdate() external {
        if (!useBatch) {
            ICurveLifecycleFacet(diamond).updateCurve(curveId, newPacked, generation);
            return;
        }

        CurveCLOBTypes.CurveUpdateParams[] memory params = new CurveCLOBTypes.CurveUpdateParams[](1);
        params[0] =
            CurveCLOBTypes.CurveUpdateParams({curveId: curveId, newPacked: newPacked, expectedGeneration: generation});
        ICurveLifecycleFacet(diamond).updateCurvesBatch(params);
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId;
    }
}

contract ProtocolSecuritySpotBookTest is TestBase {
    uint72 internal constant TWO_USDC = 2_000_000_000_000_000_000;
    uint8 internal constant TWENTY_UNIT_TICK_PRESET = 4;
    uint72 internal constant TWO_USDC_TICK_PRESET_4 = TWO_USDC / 20;
    uint128 internal constant EXTREME_PRICE_FILL_COLLATERAL = type(uint96).max;
    bytes32 internal constant SPOT_SALT = keccak256("security-regression-spot-book");

    CurveCLOBFacet internal curveFacet;
    MaliciousCurveProfile internal maliciousProfile;
    MockUSDG internal spotToken;

    function setUp() public override {
        super.setUp();

        curveFacet = new CurveCLOBFacet();
        maliciousProfile = new MaliciousCurveProfile();
        spotToken = new MockUSDG();
        spotToken.mint(maker, 1_000_000e6);
        spotToken.mint(taker, 1_000_000e6);
        usdc.mint(taker, uint256(type(uint128).max));

        vm.startPrank(owner);
        diamond.registerFacet(address(new BookFacet()), _bookSelectors());
        diamond.registerFacet(address(new BookOrderFacet()), _bookOrderSelectors());
        diamond.registerFacet(address(curveFacet), _curveTradeSelectors());
        diamond.registerFacet(address(new CurveLifecycleFacet()), _curveLifecycleSelectors());
        diamond.registerFacet(address(new CurveViewFacet()), _curveViewSelectors());
        vm.stopPrank();
    }

    function test_RevertWhen_BookFillReceivesPriceAboveUint96Max() public {
        ITestStateFacet(address(diamond)).registerCurveProfileFixture(3, address(maliciousProfile));

        bytes32 bookId = _createSpotBook(address(spotToken), LibEveMarket.BaseTransferMode.EXACT, SPOT_SALT);

        vm.startPrank(maker);
        spotToken.approve(address(diamond), 100e6);
        uint256 curveId = IBookOrderFacet(address(diamond))
            .postBookCurve(bookId, LibEveMarket.CurveSide.ASK, 100e6, TWO_USDC, TWO_USDC, 120, 3, type(uint8).max);
        vm.stopPrank();

        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        maliciousProfile.setOverflowPrice(uint128(type(uint96).max) + 1);

        vm.startPrank(taker);
        usdc.approve(address(diamond), type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidAmount.selector, uint256(uint128(type(uint96).max) + 1)));
        ICurveTradeFacet(address(diamond)).fillCurve(curveId, EXTREME_PRICE_FILL_COLLATERAL, 0, generation, commitment);
        vm.stopPrank();
    }

    function test_BookFillSucceedsWithPriceAtUint96Max() public {
        ITestStateFacet(address(diamond)).registerCurveProfileFixture(3, address(maliciousProfile));

        bytes32 bookId = _createSpotBook(address(spotToken), LibEveMarket.BaseTransferMode.EXACT, SPOT_SALT);

        vm.startPrank(maker);
        spotToken.approve(address(diamond), 100e6);
        uint256 curveId = IBookOrderFacet(address(diamond))
            .postBookCurve(bookId, LibEveMarket.CurveSide.ASK, 100e6, TWO_USDC, TWO_USDC, 120, 3, type(uint8).max);
        vm.stopPrank();

        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        uint128 priceAtLimit = uint128(type(uint96).max);
        maliciousProfile.setOverflowPrice(priceAtLimit);

        vm.startPrank(taker);
        usdc.approve(address(diamond), type(uint256).max);
        uint128 baseOut = ICurveTradeFacet(address(diamond))
            .fillCurve(curveId, EXTREME_PRICE_FILL_COLLATERAL, 0, generation, commitment);
        vm.stopPrank();

        assertEq(baseOut, 100e6);

        CurveCLOBTypes.BookInfo memory info = IBookAdminFacet(address(diamond)).getBookInfo(bookId);
        assertEq(info.lastTradePrice, uint128(uint96(priceAtLimit)));
    }

    function test_RevertWhen_CustomProfileReturnsTickAbovePresetBoundsAtFillTime() public {
        ITestStateFacet(address(diamond)).registerCurveProfileFixture(3, address(maliciousProfile));

        bytes32 bookId = _createSpotBook(
            address(spotToken), LibEveMarket.BaseTransferMode.EXACT, TWENTY_UNIT_TICK_PRESET, SPOT_SALT
        );

        vm.startPrank(maker);
        spotToken.approve(address(diamond), 100e6);
        uint256 curveId = IBookOrderFacet(address(diamond))
            .postBookCurve(
                bookId,
                LibEveMarket.CurveSide.ASK,
                100e6,
                TWO_USDC_TICK_PRESET_4,
                TWO_USDC_TICK_PRESET_4,
                120,
                3,
                type(uint8).max
            );
        vm.stopPrank();

        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        maliciousProfile.setOverflowPrice(type(uint128).max);

        vm.startPrank(taker);
        usdc.approve(address(diamond), type(uint256).max);
        vm.expectRevert(LibCurvePacking.CurvePriceOutOfRange.selector);
        ICurveTradeFacet(address(diamond)).fillCurve(curveId, EXTREME_PRICE_FILL_COLLATERAL, 0, generation, commitment);
        vm.stopPrank();
    }

    function _createSpotBook(address baseToken, LibEveMarket.BaseTransferMode transferMode, bytes32 salt)
        internal
        returns (bytes32 bookId)
    {
        return _createSpotBook(baseToken, transferMode, 0, salt);
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
    }

    function _bookSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = IBookAdminFacet.createBook.selector;
        selectors[1] = IBookAdminFacet.getBookInfo.selector;
        selectors[2] = IBookAdminFacet.requestBookDecommission.selector;
        selectors[3] = IBookAdminFacet.finalizeBookDecommission.selector;
    }

    function _bookOrderSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = IBookOrderFacet.postBookCurve.selector;
    }

    function _curveTradeSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = ICurveTradeFacet.fillCurve.selector;
    }

    function _curveLifecycleSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = ICurveLifecycleFacet.updateCurve.selector;
    }

    function _curveViewSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = ICurveViewFacet.getCurveCommitment.selector;
    }
}

contract ProtocolSecurityReentrancyTest is CurveTradingFixture {
    function test_RevertWhen_UpdateCurveCalledDuringReentrantFill() public {
        (UpdateCurveReentrantReceiver receiver, uint256 curveId, uint32 generation, bytes32 commitment) =
            _prepareReentrantFillReceiver(false);

        vm.prank(address(receiver));
        ICurveTradeFacet(address(diamond)).fillCurve(curveId, 250, 0, generation, commitment);

        assertEq(receiver.observedRevertSelector(), LibReentrancy.ReentrantCall.selector);
    }

    function test_RevertWhen_UpdateCurvesBatchCalledDuringReentrantFill() public {
        (UpdateCurveReentrantReceiver receiver, uint256 curveId, uint32 generation, bytes32 commitment) =
            _prepareReentrantFillReceiver(true);

        vm.prank(address(receiver));
        ICurveTradeFacet(address(diamond)).fillCurve(curveId, 250, 0, generation, commitment);

        assertEq(receiver.observedRevertSelector(), LibReentrancy.ReentrantCall.selector);
    }

    function _prepareReentrantFillReceiver(bool useBatch)
        internal
        returns (UpdateCurveReentrantReceiver receiver, uint256 curveId, uint32 generation, bytes32 commitment)
    {
        (bytes32 marketId,,) = _createTradingMarket("UpdateCurve reentrancy", "security-regression", 7 days);
        _splitFrom(maker, marketId, 1_000);
        _approvePositions(maker);

        curveId = _postCurveFromMaker(marketId, true, 1_000, 500_000_000, 500_000_000, 120, 0);
        (generation, commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        receiver = new UpdateCurveReentrantReceiver();

        uint256 newPacked = LibCurvePacking.pack(400_000_000, 600_000_000, 120, 0);
        receiver.configure(address(diamond), curveId, newPacked, generation + 1, useBatch);

        collateralToken.mint(address(receiver), 1_000);
        vm.prank(address(receiver));
        collateralToken.approve(address(diamond), 250);
    }
}
