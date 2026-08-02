// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {MockCollateral} from "../helpers/MockCollateral.sol";
import {MarginAccountFacet} from "../../src/facets/MarginAccountFacet.sol";
import {QuoteEnvelopeFacet} from "../../src/facets/QuoteEnvelopeFacet.sol";
import {IQuoteEnvelopeFacet} from "../../src/interfaces/IQuoteEnvelopeFacet.sol";
import {LibCLOBBook} from "../../src/libraries/LibCLOBBook.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {MarginTypes} from "../../src/types/MarginTypes.sol";
import {QuoteEnvelopeTypes} from "../../src/types/QuoteEnvelopeTypes.sol";
import {ITestStateFacet, TestBase} from "../helpers/TestBase.sol";
import {
    IMarginTestFacet as IMarginAccountFacet,
    MarginAccountingHarnessFacet,
    MarginAccountingHarnessSelectors
} from "../helpers/MarginAccountingHarnessFacet.sol";

contract QuoteEnvelopePropertiesTest is TestBase {
    uint128 internal constant MIN_PRICE = 300_000_000;
    uint128 internal constant MAX_PRICE = 700_000_000;

    MockCollateral internal collateral;
    address internal riskManager;
    bytes32 internal marketId;
    bytes32 internal bookId;
    bytes32 internal bucketId;

    function setUp() public override {
        super.setUp();

        riskManager = makeAddr("riskManager");
        collateral = new MockCollateral();

        vm.startPrank(owner);
        diamond.registerFacet(address(new MarginAccountFacet()), _marginSelectors());
        diamond.registerFacet(address(new MarginAccountingHarnessFacet()), MarginAccountingHarnessSelectors.harness());
        diamond.registerFacet(address(new QuoteEnvelopeFacet()), _quoteEnvelopeSelectors());
        IMarginAccountFacet(address(diamond)).setMarginAsset(address(collateral));
        ITestStateFacet(address(diamond))
            .configure(address(conditionalTokens), address(collateral), address(eveToken), treasury);
        vm.stopPrank();

        (marketId,) = _createMarketFixture("Do quote envelope properties hold?", _expiry(7 days));
        ITestStateFacet(address(diamond)).materializeMarketSideBookFixture(marketId, true);
        bookId = LibCLOBBook.marketBookId(marketId, true);

        _depositAndAllocate(1_000e18);
    }

    function testFuzz_UpdateKeepsEnvelopeInsideOriginalBounds(uint256 volumeSeed, uint256 startSeed, uint256 endSeed)
        public
    {
        uint256 envelopeId = _createEnvelope(100e18, 60e18, MIN_PRICE, MAX_PRICE);
        uint128 volume = uint128(bound(volumeSeed, 1, 100e18));
        uint128 startPrice = uint128(bound(startSeed, MIN_PRICE, MAX_PRICE));
        uint128 endPrice = uint128(bound(endSeed, MIN_PRICE, MAX_PRICE));

        vm.prank(maker);
        IQuoteEnvelopeFacet(address(diamond))
            .updateQuoteEnvelope(
                envelopeId,
                QuoteEnvelopeTypes.QuoteEnvelopeUpdate({volume: volume, startPrice: startPrice, endPrice: endPrice})
            );

        QuoteEnvelopeTypes.QuoteEnvelopeView memory envelope =
            IQuoteEnvelopeFacet(address(diamond)).getQuoteEnvelope(envelopeId);
        MarginTypes.MarginBucket memory bucket = IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId);

        assertLe(envelope.currentVolume, envelope.maxVolume);
        assertGe(envelope.currentStartPrice, envelope.minPrice);
        assertLe(envelope.currentStartPrice, envelope.maxPrice);
        assertGe(envelope.currentEndPrice, envelope.minPrice);
        assertLe(envelope.currentEndPrice, envelope.maxPrice);
        assertEq(bucket.reservedRisk, envelope.reservedRisk);
        assertEq(bucket.openOrderRisk, envelope.reservedRisk);
    }

    function testFuzz_CancelReleasesExactlyReservedRisk(uint256 firstVolumeSeed, uint256 secondVolumeSeed) public {
        uint128 firstVolume = uint128(bound(firstVolumeSeed, 1e18, 300e18));
        uint128 secondVolume = uint128(bound(secondVolumeSeed, 1e18, 300e18));
        uint256 firstEnvelopeId = _createEnvelope(firstVolume, firstVolume, MIN_PRICE, MAX_PRICE);
        uint256 secondEnvelopeId = _createEnvelope(secondVolume, secondVolume, MIN_PRICE, MAX_PRICE);

        QuoteEnvelopeTypes.QuoteEnvelopeView memory firstEnvelope =
            IQuoteEnvelopeFacet(address(diamond)).getQuoteEnvelope(firstEnvelopeId);
        QuoteEnvelopeTypes.QuoteEnvelopeView memory secondEnvelope =
            IQuoteEnvelopeFacet(address(diamond)).getQuoteEnvelope(secondEnvelopeId);

        MarginTypes.MarginBucket memory bucket = IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId);
        assertEq(bucket.reservedRisk, firstEnvelope.reservedRisk + secondEnvelope.reservedRisk);
        assertEq(bucket.openOrderRisk, firstEnvelope.reservedRisk + secondEnvelope.reservedRisk);

        vm.prank(maker);
        IQuoteEnvelopeFacet(address(diamond)).cancelQuoteEnvelope(firstEnvelopeId);

        bucket = IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId);
        assertEq(bucket.reservedRisk, secondEnvelope.reservedRisk);
        assertEq(bucket.openOrderRisk, secondEnvelope.reservedRisk);

        vm.prank(maker);
        IQuoteEnvelopeFacet(address(diamond)).cancelQuoteEnvelope(secondEnvelopeId);

        bucket = IMarginAccountFacet(address(diamond)).getMarginBucket(bucketId);
        assertEq(bucket.reservedRisk, 0);
        assertEq(bucket.openOrderRisk, 0);
    }

    function testFuzz_CreateRiskMatchesPreview(uint256 initialVolumeSeed, uint256 maxVolumeSeed, uint256 maxPriceSeed)
        public
    {
        uint128 initialVolume = uint128(bound(initialVolumeSeed, 1e18, 250e18));
        uint128 maxVolume = uint128(bound(maxVolumeSeed, initialVolume, 300e18));
        uint128 maxPrice = uint128(bound(maxPriceSeed, MIN_PRICE, MAX_PRICE));
        QuoteEnvelopeTypes.CreateQuoteEnvelopeParams memory params =
            _envelopeParams(maxVolume, initialVolume, MIN_PRICE, maxPrice);
        uint256 previewed = IQuoteEnvelopeFacet(address(diamond)).previewQuoteEnvelopeRisk(params);

        vm.prank(maker);
        uint256 envelopeId = IQuoteEnvelopeFacet(address(diamond)).createQuoteEnvelope(params);

        QuoteEnvelopeTypes.QuoteEnvelopeView memory envelope =
            IQuoteEnvelopeFacet(address(diamond)).getQuoteEnvelope(envelopeId);
        assertEq(envelope.reservedRisk, previewed);
    }

    function _createEnvelope(uint128 maxVolume, uint128 initialVolume, uint128 minPrice, uint128 maxPrice)
        internal
        returns (uint256 envelopeId)
    {
        QuoteEnvelopeTypes.CreateQuoteEnvelopeParams memory params =
            _envelopeParams(maxVolume, initialVolume, minPrice, maxPrice);
        vm.prank(maker);
        envelopeId = IQuoteEnvelopeFacet(address(diamond)).createQuoteEnvelope(params);
    }

    function _envelopeParams(uint128 maxVolume, uint128 initialVolume, uint128 minPrice, uint128 maxPrice)
        internal
        view
        returns (QuoteEnvelopeTypes.CreateQuoteEnvelopeParams memory params)
    {
        params = QuoteEnvelopeTypes.CreateQuoteEnvelopeParams({
            bucketId: bucketId,
            bookId: bookId,
            side: uint8(LibEveMarket.CurveSide.BID),
            maxVolume: maxVolume,
            minPrice: minPrice,
            maxPrice: maxPrice,
            initialVolume: initialVolume,
            initialStartPrice: minPrice,
            initialEndPrice: maxPrice,
            expiresAt: uint64(block.timestamp + 1 hours)
        });
    }

    function _depositAndAllocate(uint256 assets) internal {
        _fundCollateral(maker, assets / 1e12);

        bytes32 riskDomain = IMarginAccountFacet(address(diamond)).riskDomainForMarket(marketId);
        vm.startPrank(maker);
        collateral.approve(address(diamond), assets);
        IMarginAccountFacet(address(diamond)).depositMargin(assets, maker);
        bucketId = IMarginAccountFacet(address(diamond)).allocateBucketMargin(riskDomain, assets, 1);
        vm.stopPrank();
    }

    function _fundCollateral(address account, uint256 usdcAmount) internal {
        collateral.mint(account, usdcAmount * 1e12);
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
}
