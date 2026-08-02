// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {OwnershipFacet} from "../../src/facets/OwnershipFacet.sol";
import {ParimutuelFacet} from "../../src/facets/ParimutuelFacet.sol";
import {ParimutuelViewFacet} from "../../src/facets/ParimutuelViewFacet.sol";
import {TradeRouterFacet} from "../../src/facets/TradeRouterFacet.sol";
import {TradeRouterSellFacet} from "../../src/facets/TradeRouterSellFacet.sol";
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
import {IParimutuelFacet} from "../../src/interfaces/IParimutuelFacet.sol";
import {ITradeRouter} from "../../src/interfaces/ITradeRouter.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {LibCurvePacking} from "../../src/libraries/LibCurvePacking.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {ParimutuelShareToken} from "../../src/tokens/ParimutuelShareToken.sol";

import {CurveTradingFixture, ResolutionHarnessFacet, StateProbeFacet} from "../helpers/DiamondFixtures.sol";

contract GenericCLOBTest is CurveTradingFixture {
    ParimutuelFacet internal parimutuelFacet;
    ParimutuelShareToken internal shareToken;

    function setUp() public override {
        super.setUp();

        parimutuelFacet = new ParimutuelFacet();
        shareToken = new ParimutuelShareToken(address(diamond), "uri://parimutuel/{id}");

        _addFacet(address(parimutuelFacet), _parimutuelSelectors());
        _addFacet(address(new ParimutuelViewFacet()), _parimutuelViewSelectors());
        _addFacet(address(new TradeRouterFacet()), _tradeRouterSelectors());
        _addFacet(address(new TradeRouterSellFacet()), _tradeRouterSellSelectors());
        ResolutionHarnessFacet(address(diamond)).setParimutuelConfig(address(shareToken), 0, 1);

        vm.startPrank(owner);
        OwnershipFacet(address(diamond)).setParimutuelFeeSplit(500, 9_500, 0, 0, 0);
        OwnershipFacet(address(diamond)).setParimutuelEpochWindowCap(30 days);
        OwnershipFacet(address(diamond)).setOrderbookEntryFeeBps(0);
        vm.stopPrank();
    }

    function test_ScheduledCLOBAllowsInventoryButBlocksPostingUntilStart() public {
        uint64 tradingStartTime = uint64(block.timestamp + 1 days);
        uint64 expiryTime = uint64(tradingStartTime + 7 days);
        uint128 creationFee = StateProbeFacet(address(diamond)).marketCreationFee();

        _approveCreator(creationFee);

        vm.prank(creator);
        bytes32 marketId = IMarketFactoryFacet(address(diamond))
            .createMarket(
                "scheduled clob", "scheduled", DEFAULT_RESOLUTION_SOURCE, tradingStartTime, expiryTime, 0, true
            );

        (,,,,,, uint8 state,) = StateProbeFacet(address(diamond)).getStoredMarketStatus(marketId);
        assertEq(state, uint8(LibEveMarket.MarketState.Scheduled));

        _splitFrom(maker, marketId, 1_000);
        _approvePositions(maker);

        vm.expectRevert(abi.encodeWithSelector(Errors.MarketNotTrading.selector, marketId));
        _postCurveFromMaker(marketId, true, 1_000, 900_000_000, 100_000_000, 120, 0);

        vm.warp(tradingStartTime);

        uint256 curveId = _postCurveFromMaker(marketId, true, 1_000, 900_000_000, 100_000_000, 120, 0);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        (,, uint128 previewPrice,) = ICurveViewFacet(address(diamond)).previewCurveQuote(curveId, 90);
        assertEq(previewPrice, 900_000_000);

        vm.prank(taker);
        collateralToken.approve(address(diamond), 90);
        vm.prank(taker);
        uint128 sharesOut = ICurveTradeFacet(address(diamond)).fillCurve(curveId, 90, 0, generation, commitment);
        assertGt(sharesOut, 0);
    }

    function test_PostCurveWithParimutuelSharesEscrowsPositionToken() public {
        (bytes32 marketId, uint256 yesPositionId,) = _createParimutuelMarketWithMakerYesShares(1_000);

        vm.prank(maker);
        uint256 curveId = ICurveLifecycleFacet(address(diamond))
            .postCurve(marketId, true, 400, 500_000_000, 500_000_000, 120, 0, LibEveMarket.PositionTokenType.PARIMUTUEL);

        (, uint128 remainingVolume,,, bool active, bool isYesSide, address storedMaker, bytes32 storedMarketId) =
            StateProbeFacet(address(diamond)).getStoredCurve(curveId);

        assertEq(remainingVolume, 400);
        assertTrue(active);
        assertTrue(isYesSide);
        assertEq(storedMaker, maker);
        assertEq(storedMarketId, marketId);
        // maker had 2_000 shares (1_000 collateral * 2x), escrowed 400
        assertEq(shareToken.balanceOf(maker, yesPositionId), 1_600);
        assertEq(shareToken.balanceOf(address(diamond), yesPositionId), 400);
    }

    function test_PostCurvesBatchWithParimutuelSharesEscrowsSideTotals() public {
        (bytes32 marketId, uint256 yesPositionId, uint256 noPositionId) =
            _createParimutuelMarketWithMakerBothSides(1_000);

        CurveCLOBTypes.CurveCreationParams[] memory params = new CurveCLOBTypes.CurveCreationParams[](2);
        params[0] = CurveCLOBTypes.CurveCreationParams({
            isYesSide: true,
            volume: 250,
            startPrice: 500_000_000,
            endPrice: 500_000_000,
            durationMinutes: 120,
            profileId: 0,
            tickPresetId: 0
        });
        params[1] = CurveCLOBTypes.CurveCreationParams({
            isYesSide: false,
            volume: 300,
            startPrice: 500_000_000,
            endPrice: 500_000_000,
            durationMinutes: 120,
            profileId: 0,
            tickPresetId: 0
        });

        vm.prank(maker);
        uint256[] memory curveIds = ICurveLifecycleFacet(address(diamond))
            .postCurvesBatch(marketId, LibEveMarket.PositionTokenType.PARIMUTUEL, params);

        assertEq(curveIds.length, 2);
        // maker had 2_000 yes shares (1_000 * 2x), escrowed 250
        assertEq(shareToken.balanceOf(maker, yesPositionId), 1_750);
        assertEq(shareToken.balanceOf(address(diamond), yesPositionId), 250);
        // maker had 2_000 no shares (1_000 * 2x), escrowed 300
        assertEq(shareToken.balanceOf(maker, noPositionId), 1_700);
        assertEq(shareToken.balanceOf(address(diamond), noPositionId), 300);
    }

    function test_FillCurveTransfersParimutuelSharesToTaker() public {
        (bytes32 marketId, uint256 yesPositionId,) = _createParimutuelMarketWithMakerYesShares(1_000);

        vm.prank(maker);
        uint256 curveId = ICurveLifecycleFacet(address(diamond))
            .postCurve(marketId, true, 400, 500_000_000, 500_000_000, 120, 0, LibEveMarket.PositionTokenType.PARIMUTUEL);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        vm.prank(taker);
        collateralToken.approve(address(diamond), 200);

        vm.prank(taker);
        uint128 sharesOut = ICurveTradeFacet(address(diamond)).fillCurve(curveId, 200, 400, generation, commitment);

        assertEq(sharesOut, 400);
        assertEq(shareToken.balanceOf(taker, yesPositionId), 400);
        assertEq(shareToken.balanceOf(address(diamond), yesPositionId), 0);
    }

    function test_DirectBidCurveLetsUserSellParimutuelShares() public {
        (bytes32 marketId, uint256 yesPositionId,) = _createParimutuelMarketWithMakerYesShares(1_000);

        collateralToken.mint(taker, 800);
        vm.startPrank(taker);
        collateralToken.approve(address(diamond), 800);
        // 0% fee, epoch 0 (2x): 800 collateral → 1_600 shares
        assertEq(IParimutuelFacet(address(diamond)).buyShares(marketId, true, 800, taker, 0), 1_600);
        shareToken.setApprovalForAll(address(diamond), true);
        vm.stopPrank();

        vm.startPrank(maker);
        collateralToken.approve(address(diamond), type(uint256).max);
        uint256 curveId = ICurveLifecycleFacet(address(diamond))
            .postBidCurve(
                marketId, true, 600, 500_000_000, 500_000_000, 120, 0, LibEveMarket.PositionTokenType.PARIMUTUEL
            );
        vm.stopPrank();

        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        uint256 receiverBalanceBefore = collateralToken.balanceOf(taker);

        uint256[] memory curveIds = new uint256[](1);
        curveIds[0] = curveId;
        bytes32[] memory commitments = new bytes32[](1);
        commitments[0] = commitment;
        uint32[] memory generations = new uint32[](1);
        generations[0] = generation;

        ITradeRouter.SellBestParams memory params = ITradeRouter.SellBestParams({
            marketId: marketId,
            isYesSide: true,
            maxSharesIn: 400,
            minCollateralOut: 1,
            curveIds: curveIds,
            expectedGenerations: generations,
            expectedCommitments: commitments,
            receiver: taker
        });
        ITradeRouter.SellBestResult memory preview = ITradeRouter(address(diamond)).previewSellBest(params);
        assertEq(preview.sharesSold, 400);
        assertEq(preview.collateralOut, 200);
        assertEq(preview.feePaid, 0);
        assertEq(preview.unfilledShares, 0);

        vm.prank(taker);
        ITradeRouter.SellBestResult memory result = ITradeRouter(address(diamond)).sellWithEveUSDC(params);

        assertEq(result.sharesSold, 400);
        assertEq(result.collateralOut, 200);
        assertEq(collateralToken.balanceOf(taker), receiverBalanceBefore + 200);
        // maker had 2_000 shares, gets 400 from bid fill
        assertEq(shareToken.balanceOf(maker, yesPositionId), 2_000 + 400);
        // taker had 1_600 shares, sold 400
        assertEq(shareToken.balanceOf(taker, yesPositionId), 1_200);
    }

    function test_UpdateTopUpAndCancelWorkWithParimutuelShares() public {
        (bytes32 marketId, uint256 yesPositionId,) = _createParimutuelMarketWithMakerYesShares(1_000);

        vm.prank(maker);
        uint256 curveId = ICurveLifecycleFacet(address(diamond))
            .postCurve(marketId, true, 400, 500_000_000, 500_000_000, 120, 0, LibEveMarket.PositionTokenType.PARIMUTUEL);
        (uint32 generation,) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        collateralToken.mint(maker, 200);
        vm.startPrank(maker);
        collateralToken.approve(address(diamond), 200);
        // 0% fee, epoch 0 (2x): 200 collateral → 400 shares
        assertEq(IParimutuelFacet(address(diamond)).buyShares(marketId, true, 200, maker, 0), 400);
        vm.stopPrank();

        CurveCLOBTypes.CurveTopUpParams[] memory topUps = new CurveCLOBTypes.CurveTopUpParams[](1);
        topUps[0] = CurveCLOBTypes.CurveTopUpParams({curveId: curveId, addedVolume: 200});

        vm.prank(maker);
        ICurveLifecycleFacet(address(diamond)).topUpCurvesBatch(marketId, topUps);

        vm.prank(maker);
        ICurveLifecycleFacet(address(diamond))
            .updateCurve(curveId, LibCurvePacking.pack(500_000_000, 500_000_000, 120, 0), generation);

        vm.prank(maker);
        ICurveLifecycleFacet(address(diamond)).cancelCurve(curveId);

        assertEq(shareToken.balanceOf(address(diamond), yesPositionId), 0);
        // maker: 2_000 initial + 400 additional = 2_400 total
        assertEq(shareToken.balanceOf(maker, yesPositionId), 2_400);
    }

    function test_RevertWhen_CTFInventoryOperationsTargetParimutuelMarket() public {
        (bytes32 marketId,,) = _createParimutuelMarketWithMakerYesShares(1_000);

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.PositionTokenTypeMismatch.selector,
                marketId,
                uint8(LibEveMarket.PositionTokenType.CTF),
                uint8(LibEveMarket.PositionTokenType.PARIMUTUEL)
            )
        );
        vm.prank(maker);
        ICurveInventoryFacet(address(diamond)).splitInventory(marketId, 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.PositionTokenTypeMismatch.selector,
                marketId,
                uint8(LibEveMarket.PositionTokenType.CTF),
                uint8(LibEveMarket.PositionTokenType.PARIMUTUEL)
            )
        );
        vm.prank(maker);
        ICurveInventoryFacet(address(diamond)).mergeInventory(marketId, 1);

        CurveCLOBTypes.CurveTopUpParams[] memory topUps = new CurveCLOBTypes.CurveTopUpParams[](1);
        topUps[0] = CurveCLOBTypes.CurveTopUpParams({curveId: 0, addedVolume: 1});

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.PositionTokenTypeMismatch.selector,
                marketId,
                uint8(LibEveMarket.PositionTokenType.CTF),
                uint8(LibEveMarket.PositionTokenType.PARIMUTUEL)
            )
        );
        vm.prank(maker);
        ICurveLifecycleFacet(address(diamond)).splitAndTopUpCurvesBatch(marketId, topUps);
    }

    function test_RevertWhen_PostCurveUsesWrongPositionTokenType() public {
        (bytes32 marketId,,) = _createParimutuelMarketWithMakerYesShares(1_000);

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.PositionTokenTypeMismatch.selector,
                marketId,
                uint8(LibEveMarket.PositionTokenType.CTF),
                uint8(LibEveMarket.PositionTokenType.PARIMUTUEL)
            )
        );
        vm.prank(maker);
        ICurveLifecycleFacet(address(diamond))
            .postCurve(marketId, true, 400, 500_000_000, 500_000_000, 120, 0, LibEveMarket.PositionTokenType.CTF);
    }

    function _createParimutuelMarketWithMakerYesShares(uint128 amount)
        internal
        returns (bytes32 marketId, uint256 yesPositionId, uint256 noPositionId)
    {
        _approveCreatorWithEve(StateProbeFacet(address(diamond)).marketCreationFee(), type(uint256).max);

        vm.prank(creator);
        marketId = IParimutuelFacet(address(diamond))
            .createParimutuelMarket(
                "generic clob parimutuel",
                "generic-clob",
                DEFAULT_RESOLUTION_SOURCE,
                uint64(block.timestamp),
                uint64(block.timestamp + 7 days),
                7 days
            );

        (,,,, yesPositionId, noPositionId) = StateProbeFacet(address(diamond)).getStoredMarketCore(marketId);
        (uint8 marketType, address positionToken) =
            StateProbeFacet(address(diamond)).getStoredMarketTypeAndPositionToken(marketId);
        assertEq(marketType, uint8(LibEveMarket.MarketType.PARIMUTUEL));
        assertEq(positionToken, address(shareToken));

        // 0% fee, epoch 0 (2x multiplier): amount collateral → amount * 2 shares
        vm.startPrank(maker);
        collateralToken.approve(address(diamond), amount);
        assertEq(IParimutuelFacet(address(diamond)).buyShares(marketId, true, amount, maker, 0), amount * 2);
        shareToken.setApprovalForAll(address(diamond), true);
        vm.stopPrank();
    }

    function _createParimutuelMarketWithMakerBothSides(uint128 amount)
        internal
        returns (bytes32 marketId, uint256 yesPositionId, uint256 noPositionId)
    {
        (marketId, yesPositionId, noPositionId) = _createParimutuelMarketWithMakerYesShares(amount);

        collateralToken.mint(maker, amount);

        vm.startPrank(maker);
        collateralToken.approve(address(diamond), amount);
        assertEq(IParimutuelFacet(address(diamond)).buyShares(marketId, false, amount, maker, 0), amount * 2);
        vm.stopPrank();
    }

    function _tradeRouterSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = ITradeRouter.buyWithEveUSDC.selector;
        selectors[1] = ITradeRouter.buyWithUSDC.selector;
        selectors[2] = ITradeRouter.splitWithUSDC.selector;
        selectors[3] = ITradeRouter.buyWithCollateral.selector;
    }

    function _tradeRouterSellSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](4);
        selectors[0] = ITradeRouter.sellWithEveUSDC.selector;
        selectors[1] = ITradeRouter.sellWithUSDC.selector;
        selectors[2] = ITradeRouter.previewSellBest.selector;
        selectors[3] = ITradeRouter.sellWithCollateral.selector;
    }
}
