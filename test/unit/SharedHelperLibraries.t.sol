// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {Errors} from "../../src/libraries/Errors.sol";
import {LibCollateralProfile} from "../../src/libraries/LibCollateralProfile.sol";
import {LibCurveStorage} from "../../src/libraries/LibCurveStorage.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {LibFeeRouting} from "../../src/libraries/LibFeeRouting.sol";
import {LibMarketAccess} from "../../src/libraries/LibMarketAccess.sol";
import {LibSafeCast} from "../../src/libraries/LibSafeCast.sol";
import {LibSeniorCapital} from "../../src/libraries/LibSeniorCapital.sol";

contract SharedHelperHarness {
    function seedBook(bytes32 bookId, bytes32 marketId) external {
        LibEveMarket.Book storage book = LibEveMarket.store().books[bookId];
        book.bookId = bookId;
        book.marketId = marketId;
    }

    function seedMarket(bytes32 marketId, LibEveMarket.MarketState state_, uint64 tradingStartTime, uint64 expiryTime)
        external
    {
        LibEveMarket.Market storage market = LibEveMarket.store().markets[marketId];
        market.marketId = marketId;
        market.state = state_;
        market.tradingStartTime = tradingStartTime;
        market.expiryTime = expiryTime;
    }

    function requireExistingMarket(bytes32 marketId) external view returns (bytes32 storedMarketId) {
        storedMarketId = LibMarketAccess.requireExistingMarket(LibEveMarket.store(), marketId).marketId;
    }

    function requireTradingMarket(bytes32 marketId) external view returns (bytes32 storedMarketId) {
        storedMarketId = LibMarketAccess.requireTradingMarket(LibEveMarket.store(), marketId).marketId;
    }

    function requirePostableMarket(bytes32 marketId) external view returns (bytes32 storedMarketId) {
        storedMarketId = LibMarketAccess.requirePostableMarket(LibEveMarket.store(), marketId).marketId;
    }

    function storeIndexedCurve(bytes32 bookId, uint256 curveId, address maker, uint128 volume) external {
        LibCurveStorage.storeCurve(
            LibEveMarket.store().curves[curveId], bookId, maker, true, LibEveMarket.CurveSide.ASK, volume, 0, 1, curveId
        );
    }

    function storeCurveRecordOnly(bytes32 bookId, uint256 curveId, address maker, uint128 volume) external {
        LibCurveStorage.storeCurveRecord(
            LibEveMarket.store().curves[curveId],
            bookId,
            maker,
            false,
            LibEveMarket.CurveSide.BID,
            volume,
            12,
            2,
            curveId
        );
    }

    function storedCurve(uint256 curveId)
        external
        view
        returns (
            uint256 packed,
            uint128 remainingVolume,
            uint32 generation,
            bool active,
            bool isYesSide,
            LibEveMarket.CurveSide curveSide,
            address maker,
            bytes32 bookId,
            uint128 quoteEscrowRemaining
        )
    {
        LibEveMarket.StoredCurve storage curve = LibEveMarket.store().curves[curveId];
        packed = curve.packed;
        remainingVolume = curve.remainingVolume;
        generation = curve.generation;
        active = curve.active;
        isYesSide = curve.isYesSide;
        curveSide = curve.curveSide;
        maker = curve.maker;
        bookId = curve.bookId;
        quoteEscrowRemaining = curve.quoteEscrowRemaining;
    }

    function bookCurveIdsLength(bytes32 bookId) external view returns (uint256) {
        return LibEveMarket.store().bookCurveIds[bookId].length;
    }

    function bookCurveIdAt(bytes32 bookId, uint256 index) external view returns (uint256) {
        return LibEveMarket.store().bookCurveIds[bookId][index];
    }

    function setCollateralProfile(uint8 profileId, address collateralToken, bool enabled) external {
        LibEveMarket.CollateralProfile storage profile = LibEveMarket.store().collateralProfiles[profileId];
        profile.collateralToken = collateralToken;
        profile.enabled = enabled;
    }

    function requireEnabledProfile(uint8 profileId) external view returns (address collateralToken, bool enabled) {
        LibEveMarket.CollateralProfile storage profile =
            LibCollateralProfile.requireEnabled(LibEveMarket.store(), profileId);
        collateralToken = profile.collateralToken;
        enabled = profile.enabled;
    }

    function toUint128(uint256 value) external pure returns (uint128) {
        return LibSafeCast.toUint128(value);
    }

    function setSeniorRoutingState(address marginAsset, uint256 storedUnits) external {
        LibEveMarket.store().marginAsset = marginAsset;
        LibSeniorCapital.s().totalStored = storedUnits;
    }

    function canRouteSeniorPoolFee(address token) external view returns (bool) {
        return LibFeeRouting.canRouteSeniorPoolFee(token);
    }
}

contract SharedHelperLibrariesTest is Test {
    SharedHelperHarness internal harness;

    address internal token = makeAddr("token");

    function setUp() public {
        vm.warp(30 days);
        harness = new SharedHelperHarness();
    }

    function test_SafeCastAllowsUint128Max() public view {
        assertEq(harness.toUint128(type(uint128).max), type(uint128).max);
    }

    function test_RevertWhen_SafeCastOverflowsUint128() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidAmount.selector, uint256(type(uint128).max) + 1));
        harness.toUint128(uint256(type(uint128).max) + 1);
    }

    function test_CollateralProfileRequiresExistingEnabledProfile() public {
        harness.setCollateralProfile(7, token, true);

        (address collateralToken, bool enabled) = harness.requireEnabledProfile(7);

        assertEq(collateralToken, token);
        assertTrue(enabled);
    }

    function test_RevertWhen_CollateralProfileMissing() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.CollateralProfileNotFound.selector, uint8(8)));
        harness.requireEnabledProfile(8);
    }

    function test_RevertWhen_CollateralProfileDisabled() public {
        harness.setCollateralProfile(9, token, false);

        vm.expectRevert(abi.encodeWithSelector(Errors.CollateralProfileDisabled.selector, uint8(9)));
        harness.requireEnabledProfile(9);
    }

    function test_FeeRoutingReturnsSeniorPoolAssetEligibility() public {
        harness.setSeniorRoutingState(token, 1);

        assertTrue(harness.canRouteSeniorPoolFee(token));
        assertFalse(harness.canRouteSeniorPoolFee(makeAddr("inactive")));
    }

    function test_FeeRoutingRequiresConfiguredAssetAndActivePrincipal() public {
        assertFalse(harness.canRouteSeniorPoolFee(token));
        harness.setSeniorRoutingState(token, 0);
        assertFalse(harness.canRouteSeniorPoolFee(token));
        harness.setSeniorRoutingState(address(0), 1);
        assertFalse(harness.canRouteSeniorPoolFee(token));
    }

    function test_CurveStorageIndexedPathStoresAndIndexesCurve() public {
        bytes32 bookId = keccak256("book");
        address maker = makeAddr("maker");
        harness.seedBook(bookId, keccak256("market"));

        harness.storeIndexedCurve(bookId, 42, maker, 100);

        (
            uint256 packed,
            uint128 remainingVolume,
            uint32 generation,
            bool active,
            bool isYesSide,
            LibEveMarket.CurveSide curveSide,
            address storedMaker,
            bytes32 storedBookId,
            uint128 quoteEscrowRemaining
        ) = harness.storedCurve(42);

        assertEq(packed, 1);
        assertEq(remainingVolume, 100);
        assertEq(generation, 1);
        assertTrue(active);
        assertTrue(isYesSide);
        assertEq(uint8(curveSide), uint8(LibEveMarket.CurveSide.ASK));
        assertEq(storedMaker, maker);
        assertEq(storedBookId, bookId);
        assertEq(quoteEscrowRemaining, 0);
        assertEq(harness.bookCurveIdsLength(bookId), 1);
        assertEq(harness.bookCurveIdAt(bookId, 0), 42);
    }

    function test_CurveStorageRecordOnlyPathDoesNotIndexCurve() public {
        bytes32 bookId = keccak256("record-only-book");
        address maker = makeAddr("record-maker");
        harness.seedBook(bookId, keccak256("record-market"));

        harness.storeCurveRecordOnly(bookId, 77, maker, 200);

        (
            uint256 packed,
            uint128 remainingVolume,
            uint32 generation,
            bool active,
            bool isYesSide,
            LibEveMarket.CurveSide curveSide,
            address storedMaker,
            bytes32 storedBookId,
            uint128 quoteEscrowRemaining
        ) = harness.storedCurve(77);

        assertEq(packed, 2);
        assertEq(remainingVolume, 200);
        assertEq(generation, 1);
        assertTrue(active);
        assertFalse(isYesSide);
        assertEq(uint8(curveSide), uint8(LibEveMarket.CurveSide.BID));
        assertEq(storedMaker, maker);
        assertEq(storedBookId, bookId);
        assertEq(quoteEscrowRemaining, 12);
        assertEq(harness.bookCurveIdsLength(bookId), 0);
    }

    function test_MarketAccessRequiresExistingMarket() public {
        bytes32 marketId = keccak256("existing-market");
        harness.seedMarket(
            marketId, LibEveMarket.MarketState.Trading, uint64(block.timestamp), uint64(block.timestamp + 1 days)
        );

        assertEq(harness.requireExistingMarket(marketId), marketId);
    }

    function test_RevertWhen_MarketAccessMissingMarket() public {
        bytes32 marketId = keccak256("missing-market");

        vm.expectRevert(abi.encodeWithSelector(Errors.MarketNotFound.selector, marketId));
        harness.requireExistingMarket(marketId);
    }

    function test_MarketAccessDistinguishesPostableAndExecutableScheduledMarkets() public {
        bytes32 marketId = keccak256("scheduled-market");
        harness.seedMarket(
            marketId,
            LibEveMarket.MarketState.Scheduled,
            uint64(block.timestamp + 1 hours),
            uint64(block.timestamp + 1 days)
        );

        assertEq(harness.requirePostableMarket(marketId), marketId);

        vm.expectRevert(abi.encodeWithSelector(Errors.MarketNotTrading.selector, marketId));
        harness.requireTradingMarket(marketId);
    }

    function test_RevertWhen_MarketAccessScheduledMarketExpired() public {
        bytes32 marketId = keccak256("expired-scheduled-market");
        harness.seedMarket(
            marketId,
            LibEveMarket.MarketState.Scheduled,
            uint64(block.timestamp - 2 days),
            uint64(block.timestamp - 1 days)
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.MarketNotTrading.selector, marketId));
        harness.requirePostableMarket(marketId);

        vm.expectRevert(abi.encodeWithSelector(Errors.MarketNotTrading.selector, marketId));
        harness.requireTradingMarket(marketId);
    }
}
