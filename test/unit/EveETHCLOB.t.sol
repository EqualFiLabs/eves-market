// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

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
import {IMarketSettlementFacet} from "../../src/interfaces/IMarketSettlementFacet.sol";
import {ITradeRouter} from "../../src/interfaces/ITradeRouter.sol";
import {OwnershipFacet} from "../../src/facets/OwnershipFacet.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {LibMarketCreation} from "../../src/libraries/LibMarketCreation.sol";
import {EveETH} from "../../src/tokens/EveETH.sol";

import {CanonicalWETH9} from "../../src/mocks/CanonicalWETH9.sol";
import {CurveTradingFixture, SettlementFeeFixture} from "../helpers/DiamondFixtures.sol";

contract EveETHCLOBTest is SettlementFeeFixture {
    uint8 internal constant EVE_ETH_PROFILE_ID = 1;

    CanonicalWETH9 internal weth;
    EveETH internal eveETH;

    function setUp() public override {
        super.setUp();

        weth = new CanonicalWETH9();
        eveETH = new EveETH(address(weth));

        vm.startPrank(owner);
        OwnershipFacet(address(diamond))
            .setCollateralProfile(EVE_ETH_PROFILE_ID, address(eveETH), address(weth), 0.0005 ether, 0, true);
        OwnershipFacet(address(diamond)).setOrderbookEntryFeeBps(100);
        OwnershipFacet(address(diamond)).setOrderbookFeeSplit(4_000, 0, 3_000, 3_000);
        vm.stopPrank();
    }

    function test_EveETHProfileMarketSupportsSplitPostFillResolveAndRedeem() public {
        (bytes32 marketId, ExpectedMarketData memory expected, uint64 expiryTime) =
            _createEveETHMarket("Will eveETH CLOB markets settle?", "crypto", 7 days);
        uint128 mergeAmount = 0.0005 ether;
        uint128 makerInventory = 0.003 ether;
        uint128 takerCollateral = 0.001 ether;

        _fundEveETH(maker, mergeAmount + makerInventory);
        _fundEveETH(taker, takerCollateral);

        _assertMergeRoundTrip(marketId, mergeAmount, mergeAmount + makerInventory);
        uint128 sharesOut = _postAndFillEveETHAsk(marketId, expected.yesPositionId, makerInventory, takerCollateral);

        _finalizeCreatorResolution(marketId, expiryTime, uint8(LibEveMarket.MarketOutcome.Yes));
        _assertPreviewAndRedeemEveETH(marketId, expected.yesPositionId, sharesOut);
    }

    function test_EveETHProfileMarketSupportsCollateralRouterBuyAndSell() public {
        (bytes32 marketId, ExpectedMarketData memory expected,) =
            _createEveETHMarket("Will eveETH router paths work?", "crypto", 7 days);
        uint128 makerInventory = 0.003 ether;
        uint128 takerCollateral = 0.001 ether;

        _fundEveETH(maker, makerInventory + takerCollateral);
        _fundEveETH(taker, takerCollateral);

        uint128 sharesBought = _buyEveETHAskWithCollateralRouter(marketId, expected.yesPositionId, makerInventory, takerCollateral);
        uint128 sharesSold = _sellEveETHBidWithCollateralRouter(marketId, expected.yesPositionId, sharesBought);

        assertEq(sharesSold, sharesBought);
        assertEq(conditionalTokens.balanceOf(taker, expected.yesPositionId), 0);
    }

    function _assertMergeRoundTrip(bytes32 marketId, uint128 mergeAmount, uint128 expectedMakerBalance) internal {
        _splitEveETH(maker, marketId, mergeAmount);
        _approvePositions(maker);

        vm.prank(maker);
        uint128 collateralOut = ICurveInventoryFacet(address(diamond)).mergeInventory(marketId, mergeAmount);
        assertEq(collateralOut, mergeAmount);
        assertEq(eveETH.balanceOf(maker), expectedMakerBalance);
    }

    function _postAndFillEveETHAsk(
        bytes32 marketId,
        uint256 yesPositionId,
        uint128 makerInventory,
        uint128 takerCollateral
    ) internal returns (uint128 sharesOut) {
        _splitEveETH(maker, marketId, makerInventory);
        _approvePositions(maker);
        uint256 curveId = _postCurveFromMaker(marketId, true, makerInventory, 500_000_000, 500_000_000, 180, 0);
        (uint128 previewShares, uint128 previewFee,,) =
            ICurveViewFacet(address(diamond)).previewCurveQuote(curveId, takerCollateral);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        vm.startPrank(taker);
        eveETH.approve(address(diamond), takerCollateral);
        sharesOut = ICurveTradeFacet(address(diamond)).fillCurve(curveId, takerCollateral, 0, generation, commitment);
        vm.stopPrank();

        assertEq(sharesOut, previewShares);
        assertEq(conditionalTokens.balanceOf(taker, yesPositionId), sharesOut);
        uint256 makerFeeShare = (uint256(previewFee) * 4_000) / 10_000;
        assertEq(eveETH.balanceOf(treasury), previewFee - makerFeeShare);
    }

    function _buyEveETHAskWithCollateralRouter(
        bytes32 marketId,
        uint256 yesPositionId,
        uint128 makerInventory,
        uint128 takerCollateral
    ) internal returns (uint128 sharesOut) {
        _splitEveETH(maker, marketId, makerInventory);
        _approvePositions(maker);
        uint256 curveId = _postCurveFromMaker(marketId, true, makerInventory, 500_000_000, 500_000_000, 180, 0);
        (uint128 previewShares,,,) = ICurveViewFacet(address(diamond)).previewCurveQuote(curveId, takerCollateral);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        uint256 takerRefundBefore = eveETH.balanceOf(taker);
        vm.prank(taker);
        CurveCLOBTypes.FillBestResult memory result = ITradeRouter(address(diamond)).buyWithCollateral(
            CurveCLOBTypes.FillBestParams({
                marketId: marketId,
                isYesSide: true,
                maxCollateralIn: takerCollateral,
                minSharesOut: previewShares,
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
        assertEq(conditionalTokens.balanceOf(taker, yesPositionId), sharesOut);
        assertEq(eveETH.balanceOf(taker), takerRefundBefore - result.collateralUsed);
    }

    function _sellEveETHBidWithCollateralRouter(bytes32 marketId, uint256 yesPositionId, uint128 sharesIn)
        internal
        returns (uint128 sharesSold)
    {
        vm.prank(maker);
        uint256 curveId = ICurveLifecycleFacet(address(diamond))
            .postBidCurve(
                marketId, true, sharesIn, 400_000_000, 400_000_000, 180, 0, LibEveMarket.PositionTokenType.CTF
            );
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        ITradeRouter.SellBestResult memory preview = ITradeRouter(address(diamond)).previewSellBest(
            ITradeRouter.SellBestParams({
                marketId: marketId,
                isYesSide: true,
                maxSharesIn: sharesIn,
                minCollateralOut: 0,
                curveIds: _singleCurveId(curveId),
                expectedGenerations: _singleGeneration(generation),
                expectedCommitments: _singleCommitment(commitment),
                receiver: taker
            })
        );

        _approvePositions(taker);
        uint256 takerBalanceBefore = eveETH.balanceOf(taker);
        vm.prank(taker);
        ITradeRouter.SellBestResult memory result = ITradeRouter(address(diamond)).sellWithCollateral(
            ITradeRouter.SellBestParams({
                marketId: marketId,
                isYesSide: true,
                maxSharesIn: sharesIn,
                minCollateralOut: preview.collateralOut,
                curveIds: _singleCurveId(curveId),
                expectedGenerations: _singleGeneration(generation),
                expectedCommitments: _singleCommitment(commitment),
                receiver: taker
            })
        );

        sharesSold = result.sharesSold;
        assertEq(sharesSold, preview.sharesSold);
        assertEq(eveETH.balanceOf(taker), takerBalanceBefore + result.collateralOut);
        assertEq(conditionalTokens.balanceOf(taker, yesPositionId), sharesIn - sharesSold);
    }

    function _assertPreviewAndRedeemEveETH(bytes32 marketId, uint256 yesPositionId, uint128 sharesOut) internal {
        (uint256 previewClaimable, uint256 yesBalance,, uint8 outcome) =
            IMarketSettlementFacet(address(diamond)).previewCTFRedemption(marketId, taker);
        assertEq(outcome, uint8(LibEveMarket.MarketOutcome.Yes));
        assertEq(yesBalance, sharesOut);
        assertEq(previewClaimable, sharesOut);

        (address collateralTokenAddress, bytes32 conditionId, uint256[] memory indexSets) =
            IMarketSettlementFacet(address(diamond)).getCTFRedemptionParams(marketId);
        uint256 takerBalanceBefore = eveETH.balanceOf(taker);

        vm.prank(taker);
        conditionalTokens.redeemPositions(IERC20(collateralTokenAddress), bytes32(0), conditionId, indexSets);

        assertEq(eveETH.balanceOf(taker), takerBalanceBefore + sharesOut);
        assertEq(conditionalTokens.balanceOf(taker, yesPositionId), 0);

        uint256 wethBalanceBefore = weth.balanceOf(taker);
        vm.prank(taker);
        uint256 wethOut = eveETH.unwrap(sharesOut, taker);

        assertEq(wethOut, sharesOut);
        assertEq(weth.balanceOf(taker), wethBalanceBefore + sharesOut);
        assertEq(eveETH.balanceOf(taker), takerBalanceBefore);
    }

    function _createEveETHMarket(string memory question, string memory category, uint64 duration)
        internal
        returns (bytes32 marketId, ExpectedMarketData memory expected, uint64 expiryTime)
    {
        uint64 tradingStartTime = uint64(block.timestamp);
        expiryTime = tradingStartTime + duration;

        vm.prank(creator);
        marketId = IMarketFactoryFacet(address(diamond))
            .createMarketWithCollateralProfile(
                EVE_ETH_PROFILE_ID, question, category, DEFAULT_RESOLUTION_SOURCE, tradingStartTime, expiryTime, 0, true
            );

        expected.marketId = LibMarketCreation.profileMarketIdFor(
            question,
            category,
            tradingStartTime,
            expiryTime,
            address(eveETH),
            EVE_ETH_PROFILE_ID,
            0.0005 ether,
            LibEveMarket.MarketType.CLOB,
            LibEveMarket.PositionTokenType.CTF
        );
        expected.questionId = LibMarketCreation.questionIdFor(question, category, tradingStartTime, expiryTime);
        expected.resolutionId = expected.questionId;
        expected.conditionId = conditionalTokens.getConditionId(address(diamond), expected.questionId, 2);
        (expected.yesPositionId, expected.noPositionId) = _positionIdsFor(address(eveETH), expected.conditionId);
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

    function _splitEveETH(address account, bytes32 marketId, uint128 amount) internal {
        vm.prank(account);
        uint128 sharesMinted = ICurveInventoryFacet(address(diamond)).splitInventory(marketId, amount);
        assertEq(sharesMinted, amount);
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
}

contract EveETHCLOBUnsupportedUSDCPathTest is CurveTradingFixture {
    function test_RevertWhen_PostBidCurveWithUSDCForEveETHProfileMarket() public {
        uint8 profileId = 1;
        CanonicalWETH9 weth = new CanonicalWETH9();
        EveETH eveETH = new EveETH(address(weth));

        vm.prank(owner);
        OwnershipFacet(address(diamond))
            .setCollateralProfile(profileId, address(eveETH), address(weth), 0.0005 ether, 0, true);

        vm.prank(creator);
        eveToken.approve(address(diamond), type(uint256).max);

        vm.prank(creator);
        bytes32 marketId = IMarketFactoryFacet(address(diamond))
            .createMarketWithCollateralProfile(
                profileId,
                "Will USDC helpers reject eveETH?",
                "crypto",
                DEFAULT_RESOLUTION_SOURCE,
                uint64(block.timestamp),
                uint64(block.timestamp + 7 days),
                0,
                true
            );

        vm.prank(maker);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.UnsupportedCollateralToken.selector, address(collateralToken), address(eveETH)
            )
        );
        ICurveLifecycleFacet(address(diamond))
            .postBidCurveWithUSDC(
                marketId, true, 0.001 ether, 500_000_000, 500_000_000, 180, 0, LibEveMarket.PositionTokenType.CTF
            );
    }
}
