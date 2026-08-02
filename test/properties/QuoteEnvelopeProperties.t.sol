// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {EveUSDC} from "../../src/EveUSDC.sol";
import {MarginAccountFacet} from "../../src/facets/MarginAccountFacet.sol";
import {QuoteEnvelopeFacet} from "../../src/facets/QuoteEnvelopeFacet.sol";
import {IMarginAccountFacet} from "../../src/interfaces/IMarginAccountFacet.sol";
import {IQuoteEnvelopeFacet} from "../../src/interfaces/IQuoteEnvelopeFacet.sol";
import {LibCLOBBook} from "../../src/libraries/LibCLOBBook.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {MarginTypes} from "../../src/types/MarginTypes.sol";
import {QuoteEnvelopeTypes} from "../../src/types/QuoteEnvelopeTypes.sol";
import {ITestStateFacet, TestBase} from "../helpers/TestBase.sol";

contract QuoteEnvelopePropertiesTest is TestBase {
    uint128 internal constant MIN_PRICE = 300_000_000;
    uint128 internal constant MAX_PRICE = 700_000_000;

    EveUSDC internal eveUSDC;
    address internal riskManager;
    bytes32 internal marketId;
    bytes32 internal bookId;
    bytes32 internal bucketId;

    function setUp() public override {
        super.setUp();

        riskManager = makeAddr("riskManager");
        eveUSDC = new EveUSDC(address(usdc), makeAddr("onramp"), makeAddr("offramp"));

        vm.startPrank(owner);
        diamond.registerFacet(address(new MarginAccountFacet()), _marginSelectors());
        diamond.registerFacet(address(new QuoteEnvelopeFacet()), _quoteEnvelopeSelectors());
        IMarginAccountFacet(address(diamond)).setMarginAsset(address(eveUSDC));
        IMarginAccountFacet(address(diamond)).setMarginRiskManager(riskManager);
        ITestStateFacet(address(diamond))
            .configure(address(conditionalTokens), address(eveUSDC), address(eveToken), treasury);
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

    function testFuzz_CreateRiskMatchesPreview(uint256 volumeSeed, uint256 maxPriceSeed) public {
        uint128 volume = uint128(bound(volumeSeed, 1e18, 250e18));
        uint128 maxPrice = uint128(bound(maxPriceSeed, MIN_PRICE, MAX_PRICE));
        QuoteEnvelopeTypes.CreateQuoteEnvelopeParams memory params =
            _envelopeParams(volume, volume, MIN_PRICE, maxPrice);
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
        _wrapEveUSDC(maker, assets / 1e12);

        bytes32 riskDomain = IMarginAccountFacet(address(diamond)).riskDomainForMarketBook(marketId, bookId);
        vm.startPrank(maker);
        eveUSDC.approve(address(diamond), assets);
        IMarginAccountFacet(address(diamond)).depositMargin(assets, maker);
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
}
