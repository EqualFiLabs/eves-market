// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC1155Receiver} from "../../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155Receiver.sol";

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
import {Events} from "../../src/libraries/Events.sol";
import {LibCurvePacking} from "../../src/libraries/LibCurvePacking.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {LibReentrancy} from "../../src/libraries/LibReentrancy.sol";
import {MarketFactoryFacet} from "../../src/facets/MarketFactoryFacet.sol";
import {OwnershipFacet} from "../../src/facets/OwnershipFacet.sol";

import {CurveTradingFixture, ResolutionHarnessFacet, StateProbeFacet} from "../helpers/DiamondFixtures.sol";
import {MockConditionalTokens} from "../helpers/MockConditionalTokens.sol";
import {PlainGnosisCTFMock} from "../helpers/PlainGnosisCTFMock.sol";

contract ERC1155AccountingObserver is IERC1155Receiver {
    address public diamond;
    uint256 public curveId;
    bytes32 public marketId;
    bool public observed;
    bool public observedActive;
    uint128 public observedRemainingVolume;
    uint128 public observedTotalFeePool;
    uint128 public observedTotalQuoteVolume;

    function configure(address diamond_, uint256 curveId_, bytes32 marketId_) external {
        diamond = diamond_;
        curveId = curveId_;
        marketId = marketId_;
        observed = false;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external returns (bytes4) {
        _observeAccounting();
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        returns (bytes4)
    {
        _observeAccounting();
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId;
    }

    function _observeAccounting() internal {
        if (diamond == address(0)) {
            return;
        }

        (, observedRemainingVolume,,, observedActive,,,) = StateProbeFacet(diamond).getStoredCurve(curveId);
        (, observedTotalFeePool, observedTotalQuoteVolume) = StateProbeFacet(diamond).getStoredMarketTrading(marketId);
        observed = true;
    }
}

contract ERC1155ReentrantFillReceiver is IERC1155Receiver {
    IERC20 public collateralToken;
    address public diamond;
    uint256 public curveId;
    uint32 public generation;
    bytes32 public commitment;
    bytes4 public observedRevertSelector;

    function configure(
        IERC20 collateralToken_,
        address diamond_,
        uint256 curveId_,
        uint32 generation_,
        bytes32 commitment_
    ) external {
        collateralToken = collateralToken_;
        diamond = diamond_;
        curveId = curveId_;
        generation = generation_;
        commitment = commitment_;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external returns (bytes4) {
        collateralToken.approve(diamond, 1);
        try ICurveTradeFacet(diamond).fillCurve(curveId, 1, 0, generation, commitment) {}
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

contract CurveCLOBTest is CurveTradingFixture {
    struct CommitmentSnapshot {
        uint32 generation;
        bytes32 commitment;
    }

    struct BalanceSnapshot {
        uint256 makerCollateral;
        uint256 makerYes;
        uint256 makerNo;
        uint256 diamondYes;
        uint256 diamondNo;
        uint256 collateralReserve;
    }

    function test_SplitAndMergeInventoryRoundTrip() public {
        (bytes32 marketId,,) = _createTradingMarket("Split merge", "curve", 7 days);
        uint256 makerCollateralBefore = collateralToken.balanceOf(maker);

        uint128 sharesMinted = _splitFrom(maker, marketId, 250);
        assertEq(sharesMinted, 250);

        (,, uint256 yesPositionId, uint256 noPositionId) =
            IMarketFactoryFacet(address(diamond)).getMarketPositions(marketId);
        assertEq(conditionalTokens.balanceOf(maker, yesPositionId), 250);
        assertEq(conditionalTokens.balanceOf(maker, noPositionId), 250);
        assertEq(conditionalTokens.collateralBalance(IERC20(address(collateralToken))), 250);

        _approvePositions(maker);

        vm.prank(maker);
        uint128 collateralOut = ICurveInventoryFacet(address(diamond)).mergeInventory(marketId, 100);

        assertEq(collateralOut, 100);
        assertEq(conditionalTokens.balanceOf(maker, yesPositionId), 150);
        assertEq(conditionalTokens.balanceOf(maker, noPositionId), 150);
        assertEq(collateralToken.balanceOf(maker), makerCollateralBefore - 150);
        assertEq(conditionalTokens.collateralBalance(IERC20(address(collateralToken))), 150);
    }

    function test_PostCurveEscrowsQuotedInventoryAndStoresCurve() public {
        (bytes32 marketId,,) = _createTradingMarket("Post curve", "curve", 7 days);
        _splitFrom(maker, marketId, 200);
        _approvePositions(maker);

        uint256 packed = LibCurvePacking.pack(400_000_000, 600_000_000, 120, 0);

        vm.expectEmit(true, false, false, true, address(diamond));
        emit Events.CurvePosted(marketId, 0, maker, true, packed);

        uint256 curveId = _postCurveFromMaker(marketId, true, 120, 400_000_000, 600_000_000, 120, 0);

        (
            uint256 storedPacked,
            uint128 remainingVolume,,
            uint32 generation,
            bool active,
            bool isYesSide,
            address storedMaker,
            bytes32 storedMarketId
        ) = StateProbeFacet(address(diamond)).getStoredCurve(curveId);
        (,, uint256 yesPositionId, uint256 noPositionId) =
            IMarketFactoryFacet(address(diamond)).getMarketPositions(marketId);

        assertEq(storedPacked, packed);
        assertEq(remainingVolume, 120);
        assertEq(generation, 1);
        assertTrue(active);
        assertTrue(isYesSide);
        assertEq(storedMaker, maker);
        assertEq(storedMarketId, marketId);
        assertEq(conditionalTokens.balanceOf(maker, yesPositionId), 80);
        assertEq(conditionalTokens.balanceOf(address(diamond), yesPositionId), 120);
        assertEq(conditionalTokens.balanceOf(maker, noPositionId), 200);
    }

    function test_MarketSideBooksMaterializeOnFirstCurvePost() public {
        (bytes32 marketId,,) = _createTradingMarket("Lazy books", "curve", 7 days);
        bytes32 yesBookId = IBookAdminFacet(address(diamond)).getMarketSideBook(marketId, true);
        bytes32 noBookId = IBookAdminFacet(address(diamond)).getMarketSideBook(marketId, false);

        assertFalse(IBookAdminFacet(address(diamond)).isBookMaterialized(yesBookId));
        assertFalse(IBookAdminFacet(address(diamond)).isBookMaterialized(noBookId));

        vm.expectRevert(abi.encodeWithSelector(Errors.BookNotFound.selector, yesBookId));
        IBookAdminFacet(address(diamond)).getBookInfo(yesBookId);

        _splitFrom(maker, marketId, 200);
        _approvePositions(maker);
        _postCurveFromMaker(marketId, true, 120, 400_000_000, 600_000_000, 120, 0);

        assertTrue(IBookAdminFacet(address(diamond)).isBookMaterialized(yesBookId));
        assertFalse(IBookAdminFacet(address(diamond)).isBookMaterialized(noBookId));

        CurveCLOBTypes.BookInfo memory bookInfo = IBookAdminFacet(address(diamond)).getBookInfo(yesBookId);
        assertEq(bookInfo.bookId, yesBookId);
        assertEq(bookInfo.marketId, marketId);
        assertTrue(bookInfo.isYesSide);
    }

    function test_RevertWhen_PostCurveAfterExpiryBeforeResolution() public {
        (bytes32 marketId,, uint64 expiryTime) = _createTradingMarket("Late post", "curve", 7 days);

        vm.warp(expiryTime);
        MarketFactoryFacet(address(diamond)).syncMarketState(marketId);

        _splitFrom(maker, marketId, 200);
        _approvePositions(maker);

        vm.expectRevert(abi.encodeWithSelector(Errors.MarketNotTrading.selector, marketId));
        _postCurveFromMaker(marketId, true, 120, 400_000_000, 600_000_000, 120, 0);
    }

    function test_RevertWhen_FillCurveAfterExpiryBeforeResolution() public {
        (bytes32 marketId,, uint64 expiryTime) = _createTradingMarket("Late fill", "curve", 7 days);
        _splitFrom(maker, marketId, 250);
        _approvePositions(maker);

        uint256 curveId = _postCurveFromMaker(marketId, true, 200, 500_000_000, 500_000_000, 20_000, 0);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        vm.warp(expiryTime);
        MarketFactoryFacet(address(diamond)).syncMarketState(marketId);

        bytes32 yesBookId = IBookAdminFacet(address(diamond)).getMarketSideBook(marketId, true);
        (uint128 bestAskPrice,,,) = IBookViewFacet(address(diamond)).getBookTopOfBook(yesBookId);
        assertEq(bestAskPrice, 0);

        vm.startPrank(taker);
        collateralToken.approve(address(diamond), 50);
        vm.expectRevert(abi.encodeWithSelector(Errors.MarketNotTrading.selector, marketId));
        ICurveTradeFacet(address(diamond)).fillCurve(curveId, 50, 100, generation, commitment);
        vm.stopPrank();
    }

    function test_PredictionBookUsesConfiguredTickSizeForExecutionMath() public {
        (bytes32 marketId,,) = _createTradingMarket("Tick execution", "curve", 7 days);
        bytes32 yesBookId = IBookAdminFacet(address(diamond)).getMarketSideBook(marketId, true);

        StateProbeFacet(address(diamond)).materializeMarketSideBookFixture(marketId, true);
        StateProbeFacet(address(diamond))
            .setBookPricingFixture(
                yesBookId, uint256(uint8(LibEveMarket.BookPricingMode.PREDICTION_PAYOUT)), 5, 100, 0, 100
            );

        _splitFrom(maker, marketId, 250);
        _approvePositions(maker);

        uint256 curveId = _postCurveFromMaker(marketId, true, 200, 20, 20, 120, 0);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        (uint128 previewShares, uint128 previewFee, uint128 previewPrice,) =
            ICurveViewFacet(address(diamond)).previewCurveQuote(curveId, 100);

        assertEq(previewShares, 100);
        assertEq(previewFee, 0);
        assertEq(previewPrice, 100);

        vm.startPrank(taker);
        collateralToken.approve(address(diamond), 100);
        uint128 sharesOut = ICurveTradeFacet(address(diamond)).fillCurve(curveId, 100, 100, generation, commitment);
        vm.stopPrank();

        (uint96 lastTradePrice, uint128 totalFeePool, uint128 totalQuoteVolume) =
            StateProbeFacet(address(diamond)).getStoredMarketTrading(marketId);

        assertEq(sharesOut, 100);
        assertEq(lastTradePrice, 100);
        assertEq(totalFeePool, 0);
        assertEq(totalQuoteVolume, 100);
    }

    function test_GetMarketTopOfBookUsesConfiguredPredictionDenominator() public {
        (bytes32 marketId,,) = _createTradingMarket("Tick midpoint", "curve", 7 days);
        bytes32 yesBookId = IBookAdminFacet(address(diamond)).getMarketSideBook(marketId, true);
        bytes32 noBookId = IBookAdminFacet(address(diamond)).getMarketSideBook(marketId, false);

        StateProbeFacet(address(diamond)).materializeMarketSideBookFixture(marketId, true);
        StateProbeFacet(address(diamond)).materializeMarketSideBookFixture(marketId, false);
        StateProbeFacet(address(diamond))
            .setBookPricingFixture(
                yesBookId, uint256(uint8(LibEveMarket.BookPricingMode.PREDICTION_PAYOUT)), 5, 100, 0, 100
            );
        StateProbeFacet(address(diamond))
            .setBookPricingFixture(
                noBookId, uint256(uint8(LibEveMarket.BookPricingMode.PREDICTION_PAYOUT)), 5, 100, 0, 100
            );

        _splitFrom(maker, marketId, 300);
        _approvePositions(maker);

        _postCurveFromMaker(marketId, true, 150, 20, 20, 120, 0);
        _postCurveFromMaker(marketId, false, 150, 12, 12, 120, 0);

        (uint128 bestYesPrice, uint128 bestNoPrice, uint128 midpointPrice,, uint128 displayPrice) =
            ICurveViewFacet(address(diamond)).getMarketTopOfBook(marketId);

        assertEq(bestYesPrice, 100);
        assertEq(bestNoPrice, 60);
        assertEq(midpointPrice, 70);
        assertEq(displayPrice, 70);
    }

    function test_UpdateCurveRequiresOwnerAndGeneration() public {
        (bytes32 marketId,,) = _createTradingMarket("Update curve", "curve", 7 days);
        _splitFrom(maker, marketId, 250);
        _approvePositions(maker);

        uint256 curveId = _postCurveFromMaker(marketId, true, 100, 400_000_000, 600_000_000, 120, 0);
        uint256 newPacked = LibCurvePacking.pack(450_000_000, 550_000_000, 90, 1);

        vm.prank(taker);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotCurveOwner.selector, taker, maker));
        ICurveLifecycleFacet(address(diamond)).updateCurve(curveId, newPacked, 1);

        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSelector(Errors.GenerationMismatch.selector, uint32(2), uint32(1)));
        ICurveLifecycleFacet(address(diamond)).updateCurve(curveId, newPacked, 2);

        (,, uint64 originalCreatedAt,,,,,) = StateProbeFacet(address(diamond)).getStoredCurve(curveId);

        vm.prank(maker);
        ICurveLifecycleFacet(address(diamond)).updateCurve(curveId, newPacked, 1);

        (uint256 packed,, uint64 updatedCreatedAt, uint32 generation,,,,) =
            StateProbeFacet(address(diamond)).getStoredCurve(curveId);
        assertEq(packed, newPacked);
        assertEq(generation, 2);
        assertEq(updatedCreatedAt, originalCreatedAt);
    }

    function test_UpdateCurveAllowsDifferentFlatPrice() public {
        (bytes32 marketId,,) = _createTradingMarket("Flat repricing", "curve", 7 days);
        _splitFrom(maker, marketId, 5_000);
        _approvePositions(maker);

        vm.prank(owner);
        OwnershipFacet(address(diamond)).setOrderbookEntryFeeBps(0);

        uint256 curveId = _postCurveFromMaker(marketId, true, 5_000, 400_000_000, 400_000_000, 120, 0);
        (uint32 generation,) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        uint256 newPacked = LibCurvePacking.pack(650_000_000, 650_000_000, 120, 0);

        vm.expectEmit(true, false, false, true, address(diamond));
        emit Events.CurveUpdated(curveId, newPacked, generation + 1);

        vm.prank(maker);
        ICurveLifecycleFacet(address(diamond)).updateCurve(curveId, newPacked, generation);

        (uint32 newGeneration, bytes32 newCommitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        (uint128 previewShares, uint128 previewFee, uint128 previewPrice, uint128 makerTopUp) =
            ICurveViewFacet(address(diamond)).previewCurveQuote(curveId, 650);

        assertEq(newGeneration, generation + 1);
        assertEq(newCommitment, keccak256(abi.encodePacked(newPacked)));
        assertEq(previewShares, 1_000);
        assertEq(previewFee, 0);
        assertEq(previewPrice, 650_000_000);
        assertEq(makerTopUp, 0);

        vm.prank(taker);
        collateralToken.approve(address(diamond), 650);

        vm.prank(taker);
        uint128 sharesOut =
            ICurveTradeFacet(address(diamond)).fillCurve(curveId, 650, 1_000, newGeneration, newCommitment);

        (,, uint256 yesPositionId,) = IMarketFactoryFacet(address(diamond)).getMarketPositions(marketId);
        assertEq(sharesOut, 1_000);
        assertEq(conditionalTokens.balanceOf(taker, yesPositionId), 1_000);
    }

    function test_PostCurvesBatchEscrowsSideTotalsAndStoresCurves() public {
        (bytes32 marketId,,) = _createTradingMarket("Batch post", "curve", 7 days);
        _splitFrom(maker, marketId, 5_000);
        _approvePositions(maker);

        CurveCLOBTypes.CurveCreationParams[] memory creationParams = new CurveCLOBTypes.CurveCreationParams[](3);
        creationParams[0] = _curveCreationParam(true, 1_000, 400_000_000, 450_000_000, 120, 0);
        creationParams[1] = _curveCreationParam(true, 500, 500_000_000, 550_000_000, 90, 1);
        creationParams[2] = _curveCreationParam(false, 700, 600_000_000, 600_000_000, 180, 3);

        vm.prank(maker);
        uint256[] memory curveIds = ICurveLifecycleFacet(address(diamond))
            .postCurvesBatch(marketId, LibEveMarket.PositionTokenType.CTF, creationParams);

        (,, uint256 yesPositionId, uint256 noPositionId) =
            IMarketFactoryFacet(address(diamond)).getMarketPositions(marketId);
        (,,,,,,, uint256 curveCount) = StateProbeFacet(address(diamond)).getStoredMarketStatus(marketId);

        assertEq(curveIds.length, 3);
        assertEq(curveIds[0], 0);
        assertEq(curveIds[1], 1);
        assertEq(curveIds[2], 2);
        assertEq(curveCount, 3);

        _assertStoredPostedCurve(
            curveIds[0], marketId, true, 1_000, LibCurvePacking.pack(400_000_000, 450_000_000, 120, 0)
        );
        _assertStoredPostedCurve(
            curveIds[1], marketId, true, 500, LibCurvePacking.pack(500_000_000, 550_000_000, 90, 1)
        );
        _assertStoredPostedCurve(
            curveIds[2], marketId, false, 700, LibCurvePacking.pack(600_000_000, 600_000_000, 180, 3)
        );

        assertEq(conditionalTokens.balanceOf(maker, yesPositionId), 3_500);
        assertEq(conditionalTokens.balanceOf(address(diamond), yesPositionId), 1_500);
        assertEq(conditionalTokens.balanceOf(maker, noPositionId), 4_300);
        assertEq(conditionalTokens.balanceOf(address(diamond), noPositionId), 700);
    }

    function test_PostCurvesMultiMarketEscrowsInventoryAndStoresCurves() public {
        (bytes32 firstMarketId,,) = _createTradingMarket("Multi market ask one", "curve", 7 days);
        (bytes32 secondMarketId,,) = _createTradingMarket("Multi market ask two", "curve", 7 days);
        _splitFrom(maker, firstMarketId, 5_000);
        _splitFrom(maker, secondMarketId, 5_000);
        _approvePositions(maker);

        CurveCLOBTypes.MarketCurvePostParams[] memory batches = new CurveCLOBTypes.MarketCurvePostParams[](2);
        batches[0] = _marketCurvePostBatch(
            firstMarketId,
            LibEveMarket.PositionTokenType.CTF,
            _curveCreationParams(
                _curveCreationParam(true, 1_000, 400_000_000, 450_000_000, 120, 0),
                _curveCreationParam(false, 700, 600_000_000, 600_000_000, 180, 3)
            )
        );
        batches[1] = _marketCurvePostBatch(
            secondMarketId,
            LibEveMarket.PositionTokenType.CTF,
            _curveCreationParams(_curveCreationParam(true, 500, 500_000_000, 550_000_000, 90, 1))
        );

        vm.prank(maker);
        uint256[][] memory curveIds = ICurveLifecycleFacet(address(diamond)).postCurvesMultiMarket(batches);

        assertEq(curveIds.length, 2);
        assertEq(curveIds[0].length, 2);
        assertEq(curveIds[1].length, 1);
        assertEq(curveIds[0][0], 0);
        assertEq(curveIds[0][1], 1);
        assertEq(curveIds[1][0], 2);

        (,,,,,,, uint256 firstCurveCount) = StateProbeFacet(address(diamond)).getStoredMarketStatus(firstMarketId);
        (,,,,,,, uint256 secondCurveCount) = StateProbeFacet(address(diamond)).getStoredMarketStatus(secondMarketId);
        assertEq(firstCurveCount, 2);
        assertEq(secondCurveCount, 1);

        (,, uint256 firstYesPositionId, uint256 firstNoPositionId) =
            IMarketFactoryFacet(address(diamond)).getMarketPositions(firstMarketId);
        (,, uint256 secondYesPositionId,) = IMarketFactoryFacet(address(diamond)).getMarketPositions(secondMarketId);
        assertEq(conditionalTokens.balanceOf(address(diamond), firstYesPositionId), 1_000);
        assertEq(conditionalTokens.balanceOf(address(diamond), firstNoPositionId), 700);
        assertEq(conditionalTokens.balanceOf(address(diamond), secondYesPositionId), 500);
    }

    function test_PostBidCurvesMultiMarketEscrowsCollateralAndStoresCurves() public {
        (bytes32 firstMarketId,,) = _createTradingMarket("Multi market bid one", "curve", 7 days);
        (bytes32 secondMarketId,,) = _createTradingMarket("Multi market bid two", "curve", 7 days);

        CurveCLOBTypes.MarketCurvePostParams[] memory batches = new CurveCLOBTypes.MarketCurvePostParams[](2);
        batches[0] = _marketCurvePostBatch(
            firstMarketId,
            LibEveMarket.PositionTokenType.CTF,
            _curveCreationParams(
                _curveCreationParam(true, 1_000, 400_000_000, 400_000_000, 120, 0),
                _curveCreationParam(false, 500, 600_000_000, 600_000_000, 120, 0)
            )
        );
        batches[1] = _marketCurvePostBatch(
            secondMarketId,
            LibEveMarket.PositionTokenType.CTF,
            _curveCreationParams(_curveCreationParam(true, 800, 500_000_000, 500_000_000, 120, 0))
        );

        uint256 makerBalanceBefore = collateralToken.balanceOf(maker);
        uint256 diamondBalanceBefore = collateralToken.balanceOf(address(diamond));
        vm.prank(maker);
        collateralToken.approve(address(diamond), 1_100);

        vm.prank(maker);
        uint256[][] memory curveIds = ICurveLifecycleFacet(address(diamond)).postBidCurvesMultiMarket(batches);

        assertEq(curveIds.length, 2);
        assertEq(curveIds[0].length, 2);
        assertEq(curveIds[1].length, 1);
        assertEq(curveIds[0][0], 0);
        assertEq(curveIds[0][1], 1);
        assertEq(curveIds[1][0], 2);

        (,,,,,,, uint256 firstCurveCount) = StateProbeFacet(address(diamond)).getStoredMarketStatus(firstMarketId);
        (,,,,,,, uint256 secondCurveCount) = StateProbeFacet(address(diamond)).getStoredMarketStatus(secondMarketId);
        assertEq(firstCurveCount, 2);
        assertEq(secondCurveCount, 1);
        assertEq(makerBalanceBefore - collateralToken.balanceOf(maker), 1_100);
        assertEq(collateralToken.balanceOf(address(diamond)) - diamondBalanceBefore, 1_100);

        CurveCLOBTypes.CurveInfo memory firstCurve = ICurveViewFacet(address(diamond)).getCurveInfo(curveIds[0][0]);
        CurveCLOBTypes.CurveInfo memory secondCurve = ICurveViewFacet(address(diamond)).getCurveInfo(curveIds[0][1]);
        CurveCLOBTypes.CurveInfo memory thirdCurve = ICurveViewFacet(address(diamond)).getCurveInfo(curveIds[1][0]);
        assertEq(firstCurve.quoteEscrowRemaining, 400);
        assertEq(secondCurve.quoteEscrowRemaining, 300);
        assertEq(thirdCurve.quoteEscrowRemaining, 400);
    }

    function test_UpdateCurvesBatchRepricesMultipleCurves() public {
        (bytes32 marketId,,) = _createTradingMarket("Batch update", "curve", 7 days);
        _splitFrom(maker, marketId, 3_000);
        _approvePositions(maker);

        uint256 firstCurveId = _postCurveFromMaker(marketId, true, 1_200, 400_000_000, 400_000_000, 120, 0);
        uint256 secondCurveId = _postCurveFromMaker(marketId, false, 800, 600_000_000, 600_000_000, 120, 0);
        uint256 firstPacked = LibCurvePacking.pack(450_000_000, 500_000_000, 180, 1);
        uint256 secondPacked = LibCurvePacking.pack(650_000_000, 550_000_000, 240, 3);

        CurveCLOBTypes.CurveUpdateParams[] memory updateParams = new CurveCLOBTypes.CurveUpdateParams[](2);
        updateParams[0] = _curveUpdateParam(firstCurveId, firstPacked, 1);
        updateParams[1] = _curveUpdateParam(secondCurveId, secondPacked, 1);

        vm.prank(maker);
        ICurveLifecycleFacet(address(diamond)).updateCurvesBatch(updateParams);

        _assertStoredUpdatedCurve(firstCurveId, firstPacked, 2);
        _assertStoredUpdatedCurve(secondCurveId, secondPacked, 2);
    }

    function test_UpdateCurveFromNowRepricesAndResetsCreatedAt() public {
        (bytes32 marketId,,) = _createTradingMarket("Reset curve clock", "curve", 7 days);
        _splitFrom(maker, marketId, 1_000);
        _approvePositions(maker);

        uint256 curveId = _postCurveFromMaker(marketId, true, 1_000, 300_000_000, 700_000_000, 120, 0);
        (,, uint64 originalCreatedAt,,,,,) = StateProbeFacet(address(diamond)).getStoredCurve(curveId);
        uint256 newPacked = LibCurvePacking.pack(600_000_000, 800_000_000, 120, 0);

        vm.warp(block.timestamp + 30 minutes);
        uint64 resetCreatedAt = uint64(block.timestamp);

        vm.expectEmit(true, false, false, true, address(diamond));
        emit Events.CurveUpdated(curveId, newPacked, 2);
        vm.expectEmit(true, false, false, true, address(diamond));
        emit Events.CurveUpdatedFromNow(curveId, newPacked, 2, resetCreatedAt);

        vm.prank(maker);
        ICurveLifecycleFacet(address(diamond)).updateCurveFromNow(curveId, newPacked, 1);

        (uint256 packed,, uint64 createdAt, uint32 generation,,,,) =
            StateProbeFacet(address(diamond)).getStoredCurve(curveId);
        (uint128 previewShares,, uint128 previewPrice,) =
            ICurveViewFacet(address(diamond)).previewCurveQuote(curveId, 600);

        assertEq(packed, newPacked);
        assertEq(generation, 2);
        assertEq(createdAt, resetCreatedAt);
        assertGt(createdAt, originalCreatedAt);
        assertEq(previewPrice, 600_000_000);
        assertEq(previewShares, 1_000);
    }

    function test_UpdateCurvesFromNowBatchResetsCreatedAtForEachCurve() public {
        (bytes32 marketId,,) = _createTradingMarket("Batch reset clock", "curve", 7 days);
        _splitFrom(maker, marketId, 3_000);
        _approvePositions(maker);

        uint256 firstCurveId = _postCurveFromMaker(marketId, true, 1_200, 400_000_000, 500_000_000, 120, 0);
        uint256 secondCurveId = _postCurveFromMaker(marketId, false, 800, 600_000_000, 500_000_000, 120, 0);
        (,, uint64 firstOriginalCreatedAt,,,,,) = StateProbeFacet(address(diamond)).getStoredCurve(firstCurveId);
        (,, uint64 secondOriginalCreatedAt,,,,,) = StateProbeFacet(address(diamond)).getStoredCurve(secondCurveId);

        uint256 firstPacked = LibCurvePacking.pack(450_000_000, 450_000_000, 180, 0);
        uint256 secondPacked = LibCurvePacking.pack(550_000_000, 550_000_000, 180, 0);
        CurveCLOBTypes.CurveUpdateParams[] memory updateParams = new CurveCLOBTypes.CurveUpdateParams[](2);
        updateParams[0] = _curveUpdateParam(firstCurveId, firstPacked, 1);
        updateParams[1] = _curveUpdateParam(secondCurveId, secondPacked, 1);

        vm.warp(block.timestamp + 20 minutes);
        uint64 resetCreatedAt = uint64(block.timestamp);

        vm.prank(maker);
        ICurveLifecycleFacet(address(diamond)).updateCurvesFromNowBatch(updateParams);

        (uint256 firstStoredPacked,, uint64 firstCreatedAt, uint32 firstGeneration,,,,) =
            StateProbeFacet(address(diamond)).getStoredCurve(firstCurveId);
        (uint256 secondStoredPacked,, uint64 secondCreatedAt, uint32 secondGeneration,,,,) =
            StateProbeFacet(address(diamond)).getStoredCurve(secondCurveId);

        assertEq(firstStoredPacked, firstPacked);
        assertEq(secondStoredPacked, secondPacked);
        assertEq(firstGeneration, 2);
        assertEq(secondGeneration, 2);
        assertEq(firstCreatedAt, resetCreatedAt);
        assertEq(secondCreatedAt, resetCreatedAt);
        assertGt(firstCreatedAt, firstOriginalCreatedAt);
        assertGt(secondCreatedAt, secondOriginalCreatedAt);
    }

    function test_RevertWhen_UpdateCurvesBatchContainsStaleGeneration() public {
        (bytes32 marketId,,) = _createTradingMarket("Batch update guards", "curve", 7 days);
        _splitFrom(maker, marketId, 2_500);
        _approvePositions(maker);

        uint256 firstCurveId = _postCurveFromMaker(marketId, true, 1_000, 400_000_000, 500_000_000, 120, 0);
        uint256 secondCurveId = _postCurveFromMaker(marketId, true, 900, 450_000_000, 550_000_000, 120, 0);
        uint256 firstPacked = LibCurvePacking.pack(420_000_000, 520_000_000, 180, 0);
        uint256 secondPacked = LibCurvePacking.pack(430_000_000, 530_000_000, 180, 0);
        (uint256 firstOriginalPacked,,, uint32 firstOriginalGeneration,,,,) =
            StateProbeFacet(address(diamond)).getStoredCurve(firstCurveId);
        (uint256 secondOriginalPacked,,, uint32 secondOriginalGeneration,,,,) =
            StateProbeFacet(address(diamond)).getStoredCurve(secondCurveId);

        CurveCLOBTypes.CurveUpdateParams[] memory updateParams = new CurveCLOBTypes.CurveUpdateParams[](2);
        updateParams[0] = _curveUpdateParam(firstCurveId, firstPacked, 1);
        updateParams[1] = _curveUpdateParam(secondCurveId, secondPacked, 2);

        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSelector(Errors.GenerationMismatch.selector, uint32(2), uint32(1)));
        ICurveLifecycleFacet(address(diamond)).updateCurvesBatch(updateParams);

        _assertStoredUpdatedCurve(firstCurveId, firstOriginalPacked, firstOriginalGeneration);
        _assertStoredUpdatedCurve(secondCurveId, secondOriginalPacked, secondOriginalGeneration);
    }

    function test_TopUpCurvesBatchEscrowsAddedInventoryWithoutChangingGeneration() public {
        (bytes32 marketId,,) = _createTradingMarket("Batch top up", "curve", 7 days);
        _splitFrom(maker, marketId, 5_000);
        _approvePositions(maker);

        uint256 yesCurveId = _postCurveFromMaker(marketId, true, 1_000, 450_000_000, 500_000_000, 120, 0);
        uint256 noCurveId = _postCurveFromMaker(marketId, false, 800, 650_000_000, 600_000_000, 120, 0);

        BalanceSnapshot memory balancesBefore = _captureBalanceSnapshot(marketId);
        CommitmentSnapshot memory yesCommitment = _captureCurveCommitment(yesCurveId);
        CommitmentSnapshot memory noCommitment = _captureCurveCommitment(noCurveId);

        CurveCLOBTypes.CurveTopUpParams[] memory topUpParams = new CurveCLOBTypes.CurveTopUpParams[](2);
        topUpParams[0] = _curveTopUpParam(yesCurveId, 400);
        topUpParams[1] = _curveTopUpParam(noCurveId, 300);

        vm.prank(maker);
        ICurveLifecycleFacet(address(diamond)).topUpCurvesBatch(marketId, topUpParams);

        _assertCurveTopUpState(yesCurveId, 1_400, yesCommitment);
        _assertCurveTopUpState(noCurveId, 1_100, noCommitment);
        _assertBalanceSnapshot(
            marketId,
            balancesBefore.makerCollateral,
            balancesBefore.makerYes - 400,
            balancesBefore.makerNo - 300,
            balancesBefore.diamondYes + 400,
            balancesBefore.diamondNo + 300,
            balancesBefore.collateralReserve
        );
    }

    function test_SplitAndTopUpCurvesBatchAddsFreshInventoryFromCollateral() public {
        (bytes32 marketId,,) = _createTradingMarket("Split top up", "curve", 7 days);
        _splitFrom(maker, marketId, 3_000);
        _approvePositions(maker);

        uint256 yesCurveId = _postCurveFromMaker(marketId, true, 600, 450_000_000, 500_000_000, 120, 0);
        uint256 noCurveId = _postCurveFromMaker(marketId, false, 700, 650_000_000, 600_000_000, 120, 0);

        BalanceSnapshot memory balancesBefore = _captureBalanceSnapshot(marketId);
        CommitmentSnapshot memory yesCommitment = _captureCurveCommitment(yesCurveId);
        CommitmentSnapshot memory noCommitment = _captureCurveCommitment(noCurveId);

        CurveCLOBTypes.CurveTopUpParams[] memory topUpParams = new CurveCLOBTypes.CurveTopUpParams[](2);
        topUpParams[0] = _curveTopUpParam(yesCurveId, 450);
        topUpParams[1] = _curveTopUpParam(noCurveId, 450);

        vm.prank(maker);
        collateralToken.approve(address(diamond), 450);

        vm.prank(maker);
        uint128 sharesMinted = ICurveLifecycleFacet(address(diamond)).splitAndTopUpCurvesBatch(marketId, topUpParams);

        assertEq(sharesMinted, 450);
        _assertCurveTopUpState(yesCurveId, 1_050, yesCommitment);
        _assertCurveTopUpState(noCurveId, 1_150, noCommitment);
        _assertBalanceSnapshot(
            marketId,
            balancesBefore.makerCollateral - 450,
            balancesBefore.makerYes,
            balancesBefore.makerNo,
            balancesBefore.diamondYes + 450,
            balancesBefore.diamondNo + 450,
            balancesBefore.collateralReserve + 450
        );
    }

    function test_TopUpCurvesMultiMarketEscrowsAddedInventoryAcrossMarkets() public {
        (bytes32 firstMarketId,,) = _createTradingMarket("Batch top up multi one", "curve", 7 days);
        (bytes32 secondMarketId,,) = _createTradingMarket("Batch top up multi two", "curve", 8 days);
        _splitFrom(maker, firstMarketId, 3_000);
        _splitFrom(maker, secondMarketId, 3_000);
        _approvePositions(maker);

        uint256 firstYesCurveId = _postCurveFromMaker(firstMarketId, true, 900, 450_000_000, 500_000_000, 120, 0);
        uint256 firstNoCurveId = _postCurveFromMaker(firstMarketId, false, 700, 650_000_000, 600_000_000, 120, 0);
        uint256 secondYesCurveId = _postCurveFromMaker(secondMarketId, true, 800, 460_000_000, 510_000_000, 180, 0);
        uint256 secondNoCurveId = _postCurveFromMaker(secondMarketId, false, 600, 640_000_000, 590_000_000, 180, 0);

        bytes32[2] memory marketIds = [firstMarketId, secondMarketId];
        uint256[4] memory curveIds = [firstYesCurveId, firstNoCurveId, secondYesCurveId, secondNoCurveId];
        uint128[4] memory addedVolumes = [uint128(200), uint128(150), uint128(175), uint128(125)];
        BalanceSnapshot[2] memory balancesBefore = _captureBalanceSnapshots(marketIds);
        CommitmentSnapshot[4] memory commitments = _captureCurveCommitments(curveIds);
        CurveCLOBTypes.MarketCurveTopUpParams[] memory batches =
            _buildMultiMarketTopUpBatches(marketIds, curveIds, addedVolumes);

        vm.prank(maker);
        ICurveLifecycleFacet(address(diamond)).topUpCurvesMultiMarket(batches);

        _assertCurveTopUpState(firstYesCurveId, 1_100, commitments[0]);
        _assertCurveTopUpState(firstNoCurveId, 850, commitments[1]);
        _assertCurveTopUpState(secondYesCurveId, 975, commitments[2]);
        _assertCurveTopUpState(secondNoCurveId, 725, commitments[3]);
        _assertBalanceSnapshot(
            firstMarketId,
            balancesBefore[0].makerCollateral,
            balancesBefore[0].makerYes - 200,
            balancesBefore[0].makerNo - 150,
            balancesBefore[0].diamondYes + 200,
            balancesBefore[0].diamondNo + 150,
            balancesBefore[0].collateralReserve
        );
        _assertBalanceSnapshot(
            secondMarketId,
            balancesBefore[1].makerCollateral,
            balancesBefore[1].makerYes - 175,
            balancesBefore[1].makerNo - 125,
            balancesBefore[1].diamondYes + 175,
            balancesBefore[1].diamondNo + 125,
            balancesBefore[1].collateralReserve
        );
    }

    function test_SplitAndTopUpCurvesMultiMarketAddsFreshInventoryAcrossMarkets() public {
        (bytes32 firstMarketId,,) = _createTradingMarket("Split top up multi one", "curve", 7 days);
        (bytes32 secondMarketId,,) = _createTradingMarket("Split top up multi two", "curve", 8 days);
        _splitFrom(maker, firstMarketId, 2_000);
        _splitFrom(maker, secondMarketId, 2_000);
        _approvePositions(maker);

        uint256 firstYesCurveId = _postCurveFromMaker(firstMarketId, true, 600, 450_000_000, 500_000_000, 120, 0);
        uint256 firstNoCurveId = _postCurveFromMaker(firstMarketId, false, 700, 650_000_000, 600_000_000, 120, 0);
        uint256 secondYesCurveId = _postCurveFromMaker(secondMarketId, true, 550, 460_000_000, 510_000_000, 180, 0);
        uint256 secondNoCurveId = _postCurveFromMaker(secondMarketId, false, 500, 640_000_000, 590_000_000, 180, 0);

        bytes32[2] memory marketIds = [firstMarketId, secondMarketId];
        uint256[4] memory curveIds = [firstYesCurveId, firstNoCurveId, secondYesCurveId, secondNoCurveId];
        uint128[4] memory addedVolumes = [uint128(250), uint128(250), uint128(175), uint128(175)];
        uint256 makerCollateralBefore = collateralToken.balanceOf(maker);
        BalanceSnapshot[2] memory balancesBefore = _captureBalanceSnapshots(marketIds);
        CommitmentSnapshot[4] memory commitments = _captureCurveCommitments(curveIds);
        CurveCLOBTypes.MarketCurveTopUpParams[] memory batches =
            _buildMultiMarketTopUpBatches(marketIds, curveIds, addedVolumes);

        vm.prank(maker);
        collateralToken.approve(address(diamond), 600);

        vm.prank(maker);
        uint128[] memory sharesMinted = ICurveLifecycleFacet(address(diamond)).splitAndTopUpCurvesMultiMarket(batches);

        assertEq(sharesMinted.length, 2);
        assertEq(sharesMinted[0], 250);
        assertEq(sharesMinted[1], 175);
        _assertCurveTopUpState(firstYesCurveId, 850, commitments[0]);
        _assertCurveTopUpState(firstNoCurveId, 950, commitments[1]);
        _assertCurveTopUpState(secondYesCurveId, 725, commitments[2]);
        _assertCurveTopUpState(secondNoCurveId, 675, commitments[3]);
        assertEq(collateralToken.balanceOf(maker), makerCollateralBefore - 425);
        _assertBalanceSnapshot(
            firstMarketId,
            makerCollateralBefore - 425,
            balancesBefore[0].makerYes,
            balancesBefore[0].makerNo,
            balancesBefore[0].diamondYes + 250,
            balancesBefore[0].diamondNo + 250,
            balancesBefore[0].collateralReserve + 425
        );
        _assertBalanceSnapshot(
            secondMarketId,
            makerCollateralBefore - 425,
            balancesBefore[1].makerYes,
            balancesBefore[1].makerNo,
            balancesBefore[1].diamondYes + 175,
            balancesBefore[1].diamondNo + 175,
            balancesBefore[1].collateralReserve + 425
        );
    }

    function test_RevertWhen_SplitAndTopUpCurvesMultiMarketContainsUnbalancedBatch() public {
        (bytes32 firstMarketId,,) = _createTradingMarket("Split top up multi guard one", "curve", 7 days);
        (bytes32 secondMarketId,,) = _createTradingMarket("Split top up multi guard two", "curve", 8 days);
        _splitFrom(maker, firstMarketId, 2_000);
        _splitFrom(maker, secondMarketId, 2_000);
        _approvePositions(maker);

        uint256 firstYesCurveId = _postCurveFromMaker(firstMarketId, true, 600, 450_000_000, 500_000_000, 120, 0);
        uint256 firstNoCurveId = _postCurveFromMaker(firstMarketId, false, 700, 650_000_000, 600_000_000, 120, 0);
        uint256 secondYesCurveId = _postCurveFromMaker(secondMarketId, true, 550, 460_000_000, 510_000_000, 180, 0);
        uint256 secondNoCurveId = _postCurveFromMaker(secondMarketId, false, 500, 640_000_000, 590_000_000, 180, 0);

        bytes32[2] memory marketIds = [firstMarketId, secondMarketId];
        uint256[4] memory curveIds = [firstYesCurveId, firstNoCurveId, secondYesCurveId, secondNoCurveId];
        uint128[4] memory addedVolumes = [uint128(250), uint128(250), uint128(175), uint128(100)];
        CurveCLOBTypes.MarketCurveTopUpParams[] memory batches =
            _buildMultiMarketTopUpBatches(marketIds, curveIds, addedVolumes);

        vm.prank(maker);
        collateralToken.approve(address(diamond), 250);

        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSelector(Errors.CurveTopUpVolumeMismatch.selector, 175, 100));
        ICurveLifecycleFacet(address(diamond)).splitAndTopUpCurvesMultiMarket(batches);
    }

    function test_RevertWhen_SplitAndTopUpCurvesBatchIsUnbalanced() public {
        (bytes32 marketId,,) = _createTradingMarket("Split top up guards", "curve", 7 days);
        _splitFrom(maker, marketId, 3_000);
        _approvePositions(maker);

        uint256 yesCurveId = _postCurveFromMaker(marketId, true, 600, 450_000_000, 500_000_000, 120, 0);
        uint256 noCurveId = _postCurveFromMaker(marketId, false, 700, 650_000_000, 600_000_000, 120, 0);

        CurveCLOBTypes.CurveTopUpParams[] memory topUpParams = new CurveCLOBTypes.CurveTopUpParams[](2);
        topUpParams[0] = _curveTopUpParam(yesCurveId, 450);
        topUpParams[1] = _curveTopUpParam(noCurveId, 300);

        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSelector(Errors.CurveTopUpVolumeMismatch.selector, 450, 300));
        ICurveLifecycleFacet(address(diamond)).splitAndTopUpCurvesBatch(marketId, topUpParams);
    }

    function test_RevertWhen_CTFOnlyOperationsTargetParimutuelMarket() public {
        (bytes32 marketId,,) = _createTradingMarket("Parimutuel CTF-only guards", "curve", 7 days);
        _markParimutuelMarket(marketId, address(new MockConditionalTokens()));

        CurveCLOBTypes.CurveTopUpParams[] memory topUpParams = new CurveCLOBTypes.CurveTopUpParams[](1);
        topUpParams[0] = _curveTopUpParam(0, 1);
        CurveCLOBTypes.MarketCurveTopUpParams[] memory batches = new CurveCLOBTypes.MarketCurveTopUpParams[](1);
        batches[0] = _marketCurveTopUpBatch(marketId, topUpParams);

        vm.startPrank(maker);

        vm.expectRevert(_positionTokenTypeMismatch(marketId));
        ICurveInventoryFacet(address(diamond)).splitInventory(marketId, 1);

        vm.expectRevert(_positionTokenTypeMismatch(marketId));
        ICurveInventoryFacet(address(diamond)).mergeInventory(marketId, 1);

        vm.expectRevert(_positionTokenTypeMismatch(marketId));
        ICurveLifecycleFacet(address(diamond)).splitAndTopUpCurvesBatch(marketId, topUpParams);

        vm.expectRevert(_positionTokenTypeMismatch(marketId));
        ICurveLifecycleFacet(address(diamond)).splitAndTopUpCurvesMultiMarket(batches);

        vm.stopPrank();
    }

    function test_RevertWhen_PostCurveUsesWrongPositionTokenType() public {
        (bytes32 marketId,,) = _createTradingMarket("Parimutuel secondary curves", "curve", 7 days);
        MockConditionalTokens positionToken = new MockConditionalTokens();
        _markParimutuelMarket(marketId, address(positionToken));

        vm.prank(maker);
        vm.expectRevert(_positionTokenTypeMismatch(marketId));
        ICurveLifecycleFacet(address(diamond))
            .postCurve(marketId, true, 100, 500_000_000, 500_000_000, 120, 0, LibEveMarket.PositionTokenType.CTF);
    }

    function test_CancelCurvesBatchReturnsRemainingInventoryAcrossSides() public {
        (bytes32 marketId,,) = _createTradingMarket("Batch cancel", "curve", 7 days);
        _splitFrom(maker, marketId, 5_000);
        _approvePositions(maker);

        uint256 yesCurveId = _postCurveFromMaker(marketId, true, 1_500, 450_000_000, 500_000_000, 120, 0);
        uint256 noCurveId = _postCurveFromMaker(marketId, false, 1_000, 650_000_000, 600_000_000, 120, 1);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(yesCurveId);

        vm.prank(taker);
        collateralToken.approve(address(diamond), 450);

        {
            (uint128 previewShares, uint128 previewFee, uint128 previewPrice,) =
                ICurveViewFacet(address(diamond)).previewCurveQuote(yesCurveId, 450);
            uint128 exactCollateralIn = _exactCollateralIn(marketId, true, previewShares, previewPrice, previewFee);

            vm.prank(taker);
            ICurveTradeFacet(address(diamond)).fillCurve(yesCurveId, exactCollateralIn, 0, generation, commitment);
        }

        (,, uint256 yesPositionId, uint256 noPositionId) =
            IMarketFactoryFacet(address(diamond)).getMarketPositions(marketId);
        uint256 makerYesBeforeCancel = conditionalTokens.balanceOf(maker, yesPositionId);
        uint256 makerNoBeforeCancel = conditionalTokens.balanceOf(maker, noPositionId);
        (, uint128 yesEscrowBeforeCancel,,,,,,) = _storedCurveState(yesCurveId);
        (, uint128 noEscrowBeforeCancel,,,,,,) = _storedCurveState(noCurveId);

        uint256[] memory curveIds = new uint256[](2);
        curveIds[0] = yesCurveId;
        curveIds[1] = noCurveId;

        vm.prank(maker);
        ICurveLifecycleFacet(address(diamond)).cancelCurvesBatch(curveIds);

        (, uint128 yesRemaining,,, bool yesActive,,,) = _storedCurveState(yesCurveId);
        (, uint128 noRemaining,,, bool noActive,,,) = _storedCurveState(noCurveId);

        assertFalse(yesActive);
        assertFalse(noActive);
        assertEq(yesRemaining, 0);
        assertEq(noRemaining, 0);
        assertEq(conditionalTokens.balanceOf(address(diamond), yesPositionId), 0);
        assertEq(conditionalTokens.balanceOf(address(diamond), noPositionId), 0);
        assertEq(conditionalTokens.balanceOf(maker, yesPositionId), makerYesBeforeCancel + yesEscrowBeforeCancel);
        assertEq(conditionalTokens.balanceOf(maker, noPositionId), makerNoBeforeCancel + noEscrowBeforeCancel);
    }

    function test_RevertWhen_CancelCurvesBatchContainsNonOwnedCurve() public {
        (bytes32 marketId,,) = _createTradingMarket("Batch cancel guards", "curve", 7 days);
        _splitFrom(maker, marketId, 2_000);
        _splitFrom(trader, marketId, 2_000);
        _approvePositions(maker);
        _approvePositions(trader);

        uint256 makerCurveId = _postCurveFromMaker(marketId, true, 1_000, 450_000_000, 500_000_000, 120, 0);

        vm.prank(trader);
        uint256 traderCurveId = ICurveLifecycleFacet(address(diamond))
            .postCurve(marketId, false, 1_000, 650_000_000, 600_000_000, 120, 0, LibEveMarket.PositionTokenType.CTF);

        uint256[] memory curveIds = new uint256[](2);
        curveIds[0] = makerCurveId;
        curveIds[1] = traderCurveId;

        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotCurveOwner.selector, maker, trader));
        ICurveLifecycleFacet(address(diamond)).cancelCurvesBatch(curveIds);

        (, uint128 makerRemaining,, uint32 makerGeneration, bool makerActive,,,) = _storedCurveState(makerCurveId);
        (, uint128 traderRemaining,, uint32 traderGeneration, bool traderActive,,,) = _storedCurveState(traderCurveId);

        assertTrue(makerActive);
        assertTrue(traderActive);
        assertEq(makerRemaining, 1_000);
        assertEq(traderRemaining, 1_000);
        assertEq(makerGeneration, 1);
        assertEq(traderGeneration, 1);
    }

    function test_FillCurveTransfersInventoryAndAccruesFees() public {
        vm.prank(owner);
        OwnershipFacet(address(diamond)).setOrderbookEntryFeeBps(500);

        (bytes32 marketId,,) = _createTradingMarket("Fill curve", "curve", 7 days);
        _splitFrom(maker, marketId, 10_000);
        _approvePositions(maker);

        uint256 curveId = _postCurveFromMaker(marketId, true, 10_000, 500_000_000, 500_000_000, 240, 0);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        uint256 makerCollateralBefore = collateralToken.balanceOf(maker);

        vm.prank(taker);
        collateralToken.approve(address(diamond), 4_200);

        (uint128 previewShares, uint128 previewFee, uint128 previewPrice, uint128 makerTopUp) =
            ICurveViewFacet(address(diamond)).previewCurveQuote(curveId, 4_200);

        assertEq(previewShares, 8_000);
        assertEq(previewFee, 200);
        assertEq(previewPrice, 500_000_000);
        assertEq(makerTopUp, 0);

        vm.prank(taker);
        uint128 sharesOut = ICurveTradeFacet(address(diamond)).fillCurve(curveId, 4_200, 7_500, generation, commitment);

        assertEq(sharesOut, 8_000);
        _assertFilledCurveState(marketId, curveId, makerCollateralBefore);
    }

    function test_GnosisBackedMarketTradesYesInventoryThroughCLOB() public {
        PlainGnosisCTFMock plainCtf = new PlainGnosisCTFMock();

        vm.prank(owner);
        OwnershipFacet(address(diamond)).setDefaultConditionalTokens(address(plainCtf));

        (bytes32 marketId,,) = _createTradingMarket("Gnosis CLOB fill", "curve", 7 days);
        _splitFrom(maker, marketId, 1_000);

        (,, uint256 yesPositionId,) = IMarketFactoryFacet(address(diamond)).getMarketPositions(marketId);
        assertEq(plainCtf.balanceOf(maker, yesPositionId), 1_000);

        vm.prank(maker);
        plainCtf.setApprovalForAll(address(diamond), true);
        uint256 curveId = _postCurveFromMaker(marketId, true, 1_000, 500_000_000, 500_000_000, 240, 0);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        vm.startPrank(taker);
        collateralToken.approve(address(diamond), 250);
        uint128 sharesOut = ICurveTradeFacet(address(diamond)).fillCurve(curveId, 250, 500, generation, commitment);
        vm.stopPrank();

        assertEq(sharesOut, 500);
        assertEq(plainCtf.balanceOf(taker, yesPositionId), 500);
        assertEq(plainCtf.balanceOf(address(diamond), yesPositionId), 500);
    }

    function test_FillCurveRevertsOnStaleCommitmentSlippageAndExpiry() public {
        (bytes32 marketId,,) = _createTradingMarket("Fill guards", "curve", 7 days);
        _splitFrom(maker, marketId, 1_000);
        _approvePositions(maker);

        uint256 curveId = _postCurveFromMaker(marketId, true, 1_000, 500_000_000, 500_000_000, 60, 0);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        vm.prank(taker);
        collateralToken.approve(address(diamond), 500);

        vm.prank(taker);
        vm.expectRevert(abi.encodeWithSelector(Errors.GenerationMismatch.selector, uint32(2), generation));
        ICurveTradeFacet(address(diamond)).fillCurve(curveId, 500, 1, 2, commitment);

        vm.prank(taker);
        vm.expectRevert(abi.encodeWithSelector(Errors.CommitmentMismatch.selector, bytes32(uint256(1)), commitment));
        ICurveTradeFacet(address(diamond)).fillCurve(curveId, 500, 1, generation, bytes32(uint256(1)));

        (uint128 previewShares, uint128 previewFee, uint128 previewPrice,) =
            ICurveViewFacet(address(diamond)).previewCurveQuote(curveId, 500);
        uint128 exactCollateralIn = _exactCollateralIn(marketId, true, previewShares, previewPrice, previewFee);
        (uint128 exactPreviewShares,,,) =
            ICurveViewFacet(address(diamond)).previewCurveQuote(curveId, exactCollateralIn);

        vm.prank(taker);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.SlippageExceeded.selector, exactPreviewShares, uint128(exactPreviewShares + 1)
            )
        );
        ICurveTradeFacet(address(diamond))
            .fillCurve(curveId, exactCollateralIn, exactPreviewShares + 1, generation, commitment);

        vm.warp(block.timestamp + 61 minutes);

        vm.prank(taker);
        vm.expectRevert(abi.encodeWithSelector(Errors.CurveExpired.selector, curveId));
        ICurveTradeFacet(address(diamond)).fillCurve(curveId, 500, 1, generation, commitment);
    }

    function test_FillBestAggregatesAcrossCurvesAndEmitsTradeRouted() public {
        address receiver = makeAddr("fill-best-receiver");
        (bytes32 marketId,,) = _createTradingMarket("Route fills", "curve", 7 days);

        _splitFrom(maker, marketId, 3_000);
        _splitFrom(trader, marketId, 5_000);
        _approvePositions(maker);
        _approvePositions(trader);

        vm.prank(owner);
        OwnershipFacet(address(diamond)).setOrderbookEntryFeeBps(0);

        uint256 firstCurveId = _postCurveFromMaker(marketId, true, 3_000, 400_000_000, 400_000_000, 120, 0);

        vm.prank(trader);
        uint256 secondCurveId = ICurveLifecycleFacet(address(diamond))
            .postCurve(marketId, true, 5_000, 600_000_000, 600_000_000, 120, 0, LibEveMarket.PositionTokenType.CTF);

        uint256[] memory curveIds = new uint256[](2);
        uint32[] memory generations = new uint32[](2);
        bytes32[] memory commitments = new bytes32[](2);

        curveIds[0] = firstCurveId;
        curveIds[1] = secondCurveId;

        (generations[0], commitments[0]) = ICurveViewFacet(address(diamond)).getCurveCommitment(firstCurveId);
        (generations[1], commitments[1]) = ICurveViewFacet(address(diamond)).getCurveCommitment(secondCurveId);

        vm.prank(taker);
        collateralToken.approve(address(diamond), 3_000);

        CurveCLOBTypes.FillBestParams memory params = CurveCLOBTypes.FillBestParams({
            marketId: marketId,
            isYesSide: true,
            maxCollateralIn: 3_000,
            minSharesOut: 5_500,
            maxAveragePrice: 500_000_000,
            curveIds: curveIds,
            expectedGenerations: generations,
            expectedCommitments: commitments,
            payer: makeAddr("ignored-fill-best-payer"),
            receiver: receiver
        });

        vm.prank(taker);
        CurveCLOBTypes.FillBestResult memory result = ICurveTradeFacet(address(diamond)).fillBest(params);
        uint128 sharesOut = result.sharesOut;

        (,, uint256 yesPositionId,) = IMarketFactoryFacet(address(diamond)).getMarketPositions(marketId);

        assertEq(sharesOut, 6_000);
        assertEq(conditionalTokens.balanceOf(receiver, yesPositionId), 6_000);
        assertEq(conditionalTokens.balanceOf(taker, yesPositionId), 0);
        (, uint128 firstRemaining,,,,,,) = StateProbeFacet(address(diamond)).getStoredCurve(firstCurveId);
        (, uint128 secondRemaining,,,,,,) = StateProbeFacet(address(diamond)).getStoredCurve(secondCurveId);
        assertEq(firstRemaining, 0);
        assertEq(secondRemaining, 2_000);
    }

    function test_FillBestForSelectorIsNotRegistered() public view {
        (bool ok, bytes memory data) =
            address(diamond).staticcall(abi.encodeWithSignature("facetAddress(bytes4)", _fillBestForSelector()));

        assertTrue(ok);
        assertEq(abi.decode(data, (address)), address(0));
    }

    function test_CancelCurveReturnsRemainingInventory() public {
        (bytes32 marketId,,) = _createTradingMarket("Cancel curve", "curve", 7 days);
        _splitFrom(maker, marketId, 5_000);
        _approvePositions(maker);

        uint256 curveId = _postCurveFromMaker(marketId, true, 5_000, 500_000_000, 500_000_000, 120, 0);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        (uint128 previewShares,,,) = ICurveViewFacet(address(diamond)).previewCurveQuote(curveId, 1_000);
        uint128 exactCollateralIn = _exactCollateralIn(marketId, true, previewShares, 500_000_000, 0);

        vm.prank(taker);
        collateralToken.approve(address(diamond), exactCollateralIn);
        vm.prank(taker);
        ICurveTradeFacet(address(diamond)).fillCurve(curveId, exactCollateralIn, 1, generation, commitment);

        (,, uint256 yesPositionId,) = IMarketFactoryFacet(address(diamond)).getMarketPositions(marketId);
        uint256 makerYesBeforeCancel = conditionalTokens.balanceOf(maker, yesPositionId);
        (, uint128 remainingBeforeCancel,,,,,,) = _storedCurveState(curveId);

        vm.prank(maker);
        ICurveLifecycleFacet(address(diamond)).cancelCurve(curveId);

        (, uint128 remainingVolume,,, bool active,,,) = _storedCurveState(curveId);

        assertFalse(active);
        assertEq(remainingVolume, 0);
        assertEq(conditionalTokens.balanceOf(maker, yesPositionId), makerYesBeforeCancel + remainingBeforeCancel);
    }

    function test_FillUpdatesAccountingBeforeReceiverCallback() public {
        (bytes32 marketId,,) = _createTradingMarket("Fill receiver accounting", "curve", 7 days);
        _splitFrom(maker, marketId, 1_000);
        _approvePositions(maker);

        vm.prank(owner);
        OwnershipFacet(address(diamond)).setOrderbookEntryFeeBps(0);

        uint256 curveId = _postCurveFromMaker(marketId, true, 1_000, 500_000_000, 500_000_000, 120, 0);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        ERC1155AccountingObserver receiver = new ERC1155AccountingObserver();

        collateralToken.mint(address(receiver), 1_000);
        vm.prank(address(receiver));
        collateralToken.approve(address(diamond), 250);

        receiver.configure(address(diamond), curveId, marketId);

        vm.prank(address(receiver));
        ICurveTradeFacet(address(diamond)).fillCurve(curveId, 250, 0, generation, commitment);

        assertTrue(receiver.observed());
        assertTrue(receiver.observedActive());
        assertEq(receiver.observedRemainingVolume(), 500);
        assertEq(receiver.observedTotalQuoteVolume(), 250);
        assertEq(receiver.observedTotalFeePool(), 0);
    }

    function test_ReentrantReceiverCannotEnterValueMovingCLOBPath() public {
        (bytes32 marketId,,) = _createTradingMarket("Fill receiver reentrancy", "curve", 7 days);
        _splitFrom(maker, marketId, 1_000);
        _approvePositions(maker);

        uint256 curveId = _postCurveFromMaker(marketId, true, 1_000, 500_000_000, 500_000_000, 120, 0);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
        ERC1155ReentrantFillReceiver receiver = new ERC1155ReentrantFillReceiver();

        collateralToken.mint(address(receiver), 1_000);
        vm.prank(address(receiver));
        collateralToken.approve(address(diamond), 250);

        receiver.configure(IERC20(address(collateralToken)), address(diamond), curveId, generation, commitment);

        vm.prank(address(receiver));
        ICurveTradeFacet(address(diamond)).fillCurve(curveId, 250, 0, generation, commitment);

        assertEq(receiver.observedRevertSelector(), LibReentrancy.ReentrantCall.selector);
    }

    function test_CancelUpdatesCurveBeforeReceiverCallback() public {
        (bytes32 marketId,,) = _createTradingMarket("Cancel receiver accounting", "curve", 7 days);
        ERC1155AccountingObserver receiver = new ERC1155AccountingObserver();

        collateralToken.mint(address(receiver), 1_000);
        vm.prank(address(receiver));
        collateralToken.approve(address(diamond), 500);

        vm.prank(address(receiver));
        ICurveInventoryFacet(address(diamond)).splitInventory(marketId, 500);

        vm.prank(address(receiver));
        conditionalTokens.setApprovalForAll(address(diamond), true);

        vm.prank(address(receiver));
        uint256 curveId = ICurveLifecycleFacet(address(diamond))
            .postCurve(marketId, true, 300, 500_000_000, 500_000_000, 120, 0, LibEveMarket.PositionTokenType.CTF);

        receiver.configure(address(diamond), curveId, marketId);

        vm.prank(address(receiver));
        ICurveLifecycleFacet(address(diamond)).cancelCurve(curveId);

        assertTrue(receiver.observed());
        assertFalse(receiver.observedActive());
        assertEq(receiver.observedRemainingVolume(), 0);
    }

    function test_GetMarketTopOfBookAndPreviewBestExecution() public {
        (bytes32 marketId,,) = _createTradingMarket("Orderbook", "curve", 7 days);
        _splitFrom(maker, marketId, 3_000);
        _splitFrom(trader, marketId, 3_000);
        _approvePositions(maker);
        _approvePositions(trader);

        vm.prank(owner);
        OwnershipFacet(address(diamond)).setOrderbookEntryFeeBps(0);

        uint256 yesCurveId = _postCurveFromMaker(marketId, true, 2_000, 400_000_000, 400_000_000, 180, 0);

        vm.prank(trader);
        ICurveLifecycleFacet(address(diamond))
            .postCurve(marketId, false, 2_000, 700_000_000, 700_000_000, 180, 0, LibEveMarket.PositionTokenType.CTF);

        uint256[] memory path = new uint256[](1);
        path[0] = yesCurveId;

        (uint128 sharesOut, uint128 fee, uint128 averagePrice, uint128 unfilledCollateral) =
            ICurveViewFacet(address(diamond)).previewBestExecution(marketId, true, 800, path);
        (
            uint128 bestYesPrice,
            uint128 bestNoPrice,
            uint128 midpointPrice,
            uint128 lastTradePrice,
            uint128 displayPrice
        ) = ICurveViewFacet(address(diamond)).getMarketTopOfBook(marketId);

        assertEq(sharesOut, 2_000);
        assertEq(fee, 0);
        assertEq(averagePrice, 400_000_000);
        assertEq(unfilledCollateral, 0);
        assertEq(bestYesPrice, 400_000_000);
        assertEq(bestNoPrice, 700_000_000);
        assertEq(midpointPrice, 350_000_000);
        assertEq(lastTradePrice, 0);
        assertEq(displayPrice, 350_000_000);
    }

    function _markParimutuelMarket(bytes32 marketId, address positionToken) internal {
        ResolutionHarnessFacet(address(diamond))
            .setMarketTypeAndPositionToken(marketId, uint256(uint8(LibEveMarket.MarketType.PARIMUTUEL)), positionToken);
    }

    function _positionTokenTypeMismatch(bytes32 marketId) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(
            Errors.PositionTokenTypeMismatch.selector,
            marketId,
            uint8(LibEveMarket.PositionTokenType.CTF),
            uint8(LibEveMarket.PositionTokenType.PARIMUTUEL)
        );
    }

    function _storedCurveState(uint256 curveId)
        internal
        view
        returns (
            uint256 packed,
            uint128 remainingVolume,
            uint64 createdAt,
            uint32 generation,
            bool active,
            bool isYesSide,
            address storedMaker,
            bytes32 marketId
        )
    {
        return StateProbeFacet(address(diamond)).getStoredCurve(curveId);
    }

    function _assertFilledCurveState(bytes32 marketId, uint256 curveId, uint256 makerCollateralBefore) internal view {
        (,, uint256 yesPositionId,) = IMarketFactoryFacet(address(diamond)).getMarketPositions(marketId);
        (uint96 lastTradePrice, uint128 totalFeePool, uint128 totalQuoteVolume) =
            StateProbeFacet(address(diamond)).getStoredMarketTrading(marketId);
        (uint128 makerQuoteVolume, uint128 makerFeesAccrued,) =
            StateProbeFacet(address(diamond)).getStoredMakerAccounting(marketId, maker);
        (uint128 creatorFeesEscrowed, uint128 protocolFeesAccrued,,) =
            StateProbeFacet(address(diamond)).getStoredMarketFees(marketId);
        (, uint128 remainingVolume,, uint32 currentGeneration, bool active,,,) = _storedCurveState(curveId);

        assertEq(conditionalTokens.balanceOf(taker, yesPositionId), 8_000);
        assertEq(collateralToken.balanceOf(maker), makerCollateralBefore + 4_000);
        assertEq(lastTradePrice, 500_000_000);
        assertEq(totalFeePool, 200);
        assertEq(totalQuoteVolume, 4_200);
        assertEq(makerQuoteVolume, 4_200);
        assertEq(makerFeesAccrued, 170);
        assertEq(creatorFeesEscrowed, 10);
        assertEq(protocolFeesAccrued, 20);
        assertEq(remainingVolume, 2_000);
        assertEq(currentGeneration, 1);
        assertTrue(active);
    }

    function _assertStoredPostedCurve(
        uint256 curveId,
        bytes32 marketId,
        bool isYesSide,
        uint128 volume,
        uint256 expectedPacked
    ) internal view {
        (
            uint256 storedPacked,
            uint128 remainingVolume,,
            uint32 generation,
            bool active,
            bool storedIsYesSide,
            address storedMaker,
            bytes32 storedMarketId
        ) = StateProbeFacet(address(diamond)).getStoredCurve(curveId);

        assertEq(storedPacked, expectedPacked);
        assertEq(remainingVolume, volume);
        assertEq(generation, 1);
        assertTrue(active);
        assertEq(storedIsYesSide, isYesSide);
        assertEq(storedMaker, maker);
        assertEq(storedMarketId, marketId);
    }

    function _assertStoredUpdatedCurve(uint256 curveId, uint256 expectedPacked, uint32 expectedGeneration)
        internal
        view
    {
        (uint256 storedPacked,,, uint32 generation, bool active,,,) =
            StateProbeFacet(address(diamond)).getStoredCurve(curveId);

        assertEq(storedPacked, expectedPacked);
        assertEq(generation, expectedGeneration);
        assertTrue(active);
    }

    function _exactCollateralIn(bytes32 marketId, bool isYesSide, uint128 sharesOut, uint128 price, uint128 fee)
        internal
        view
        returns (uint128 collateralIn)
    {
        bytes32 bookId = IBookAdminFacet(address(diamond)).getMarketSideBook(marketId, isYesSide);
        uint128 priceDenominator = IBookAdminFacet(address(diamond)).getBookInfo(bookId).priceDenominator;
        collateralIn = uint128((uint256(sharesOut) * price) / priceDenominator) + fee;
    }

    function _curveCreationParam(
        bool isYesSide,
        uint128 volume,
        uint72 startPrice,
        uint72 endPrice,
        uint24 durationMinutes,
        uint8 profileId
    ) internal pure returns (CurveCLOBTypes.CurveCreationParams memory params) {
        params = CurveCLOBTypes.CurveCreationParams({
            isYesSide: isYesSide,
            volume: volume,
            startPrice: startPrice,
            endPrice: endPrice,
            durationMinutes: durationMinutes,
            profileId: profileId,
            tickPresetId: 0
        });
    }

    function _curveCreationParams(CurveCLOBTypes.CurveCreationParams memory first)
        internal
        pure
        returns (CurveCLOBTypes.CurveCreationParams[] memory params)
    {
        params = new CurveCLOBTypes.CurveCreationParams[](1);
        params[0] = first;
    }

    function _curveCreationParams(
        CurveCLOBTypes.CurveCreationParams memory first,
        CurveCLOBTypes.CurveCreationParams memory second
    ) internal pure returns (CurveCLOBTypes.CurveCreationParams[] memory params) {
        params = new CurveCLOBTypes.CurveCreationParams[](2);
        params[0] = first;
        params[1] = second;
    }

    function _marketCurvePostBatch(
        bytes32 marketId,
        LibEveMarket.PositionTokenType positionTokenType,
        CurveCLOBTypes.CurveCreationParams[] memory params
    ) internal pure returns (CurveCLOBTypes.MarketCurvePostParams memory batch) {
        batch = CurveCLOBTypes.MarketCurvePostParams({
            marketId: marketId, positionTokenType: positionTokenType, params: params
        });
    }

    function _curveTopUpParam(uint256 curveId, uint128 addedVolume)
        internal
        pure
        returns (CurveCLOBTypes.CurveTopUpParams memory params)
    {
        params = CurveCLOBTypes.CurveTopUpParams({curveId: curveId, addedVolume: addedVolume});
    }

    function _singleCurveFillBestParams(
        bytes32 marketId,
        bool isYesSide,
        uint128 maxCollateralIn,
        uint256 curveId,
        uint32 generation,
        bytes32 commitment,
        address payer,
        address receiver
    ) internal pure returns (CurveCLOBTypes.FillBestParams memory params) {
        uint256[] memory curveIds = new uint256[](1);
        uint32[] memory generations = new uint32[](1);
        bytes32[] memory commitments = new bytes32[](1);

        curveIds[0] = curveId;
        generations[0] = generation;
        commitments[0] = commitment;

        params = CurveCLOBTypes.FillBestParams({
            marketId: marketId,
            isYesSide: isYesSide,
            maxCollateralIn: maxCollateralIn,
            minSharesOut: 1,
            maxAveragePrice: type(uint128).max,
            curveIds: curveIds,
            expectedGenerations: generations,
            expectedCommitments: commitments,
            payer: payer,
            receiver: receiver
        });
    }

    function _marketCurveTopUpBatch(bytes32 marketId, CurveCLOBTypes.CurveTopUpParams[] memory params)
        internal
        pure
        returns (CurveCLOBTypes.MarketCurveTopUpParams memory batch)
    {
        batch = CurveCLOBTypes.MarketCurveTopUpParams({marketId: marketId, params: params});
    }

    function _buildMultiMarketTopUpBatches(
        bytes32[2] memory marketIds,
        uint256[4] memory curveIds,
        uint128[4] memory addedVolumes
    ) internal pure returns (CurveCLOBTypes.MarketCurveTopUpParams[] memory batches) {
        batches = new CurveCLOBTypes.MarketCurveTopUpParams[](2);

        CurveCLOBTypes.CurveTopUpParams[] memory firstParams = new CurveCLOBTypes.CurveTopUpParams[](2);
        firstParams[0] = _curveTopUpParam(curveIds[0], addedVolumes[0]);
        firstParams[1] = _curveTopUpParam(curveIds[1], addedVolumes[1]);
        batches[0] = _marketCurveTopUpBatch(marketIds[0], firstParams);

        CurveCLOBTypes.CurveTopUpParams[] memory secondParams = new CurveCLOBTypes.CurveTopUpParams[](2);
        secondParams[0] = _curveTopUpParam(curveIds[2], addedVolumes[2]);
        secondParams[1] = _curveTopUpParam(curveIds[3], addedVolumes[3]);
        batches[1] = _marketCurveTopUpBatch(marketIds[1], secondParams);
    }

    function _captureCurveCommitments(uint256[4] memory curveIds)
        internal
        view
        returns (CommitmentSnapshot[4] memory snapshots)
    {
        snapshots[0] = _captureCurveCommitment(curveIds[0]);
        snapshots[1] = _captureCurveCommitment(curveIds[1]);
        snapshots[2] = _captureCurveCommitment(curveIds[2]);
        snapshots[3] = _captureCurveCommitment(curveIds[3]);
    }

    function _captureBalanceSnapshots(bytes32[2] memory marketIds)
        internal
        view
        returns (BalanceSnapshot[2] memory snapshots)
    {
        snapshots[0] = _captureBalanceSnapshot(marketIds[0]);
        snapshots[1] = _captureBalanceSnapshot(marketIds[1]);
    }

    function _captureCurveCommitment(uint256 curveId) internal view returns (CommitmentSnapshot memory snapshot) {
        (snapshot.generation, snapshot.commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);
    }

    function _captureBalanceSnapshot(bytes32 marketId) internal view returns (BalanceSnapshot memory snapshot) {
        (,, uint256 yesPositionId, uint256 noPositionId) =
            IMarketFactoryFacet(address(diamond)).getMarketPositions(marketId);
        snapshot.makerCollateral = collateralToken.balanceOf(maker);
        snapshot.makerYes = conditionalTokens.balanceOf(maker, yesPositionId);
        snapshot.makerNo = conditionalTokens.balanceOf(maker, noPositionId);
        snapshot.diamondYes = conditionalTokens.balanceOf(address(diamond), yesPositionId);
        snapshot.diamondNo = conditionalTokens.balanceOf(address(diamond), noPositionId);
        snapshot.collateralReserve = conditionalTokens.collateralBalance(IERC20(address(collateralToken)));
    }

    function _assertCurveTopUpState(uint256 curveId, uint128 expectedRemaining, CommitmentSnapshot memory snapshot)
        internal
        view
    {
        (, uint128 remaining,, uint32 generation,,,,) = _storedCurveState(curveId);
        CommitmentSnapshot memory current = _captureCurveCommitment(curveId);

        assertEq(remaining, expectedRemaining);
        assertEq(generation, snapshot.generation);
        assertEq(current.generation, snapshot.generation);
        assertEq(current.commitment, snapshot.commitment);
    }

    function _assertBalanceSnapshot(
        bytes32 marketId,
        uint256 expectedMakerCollateral,
        uint256 expectedMakerYes,
        uint256 expectedMakerNo,
        uint256 expectedDiamondYes,
        uint256 expectedDiamondNo,
        uint256 expectedCollateralReserve
    ) internal view {
        BalanceSnapshot memory current = _captureBalanceSnapshot(marketId);
        assertEq(current.makerCollateral, expectedMakerCollateral);
        assertEq(current.makerYes, expectedMakerYes);
        assertEq(current.makerNo, expectedMakerNo);
        assertEq(current.diamondYes, expectedDiamondYes);
        assertEq(current.diamondNo, expectedDiamondNo);
        assertEq(current.collateralReserve, expectedCollateralReserve);
    }

    function _curveUpdateParam(uint256 curveId, uint256 newPacked, uint32 expectedGeneration)
        internal
        pure
        returns (CurveCLOBTypes.CurveUpdateParams memory params)
    {
        params = CurveCLOBTypes.CurveUpdateParams({
            curveId: curveId, newPacked: newPacked, expectedGeneration: expectedGeneration
        });
    }

    function _fillBestForSelector() internal pure returns (bytes4) {
        return bytes4(
            keccak256(
                "fillBestFor((bytes32,bool,uint128,uint128,uint128,uint256[],uint32[],bytes32[],address,address))"
            )
        );
    }
}
