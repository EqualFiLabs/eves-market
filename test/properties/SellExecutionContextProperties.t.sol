// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC1155} from "../../lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";

import {BookFacet} from "../../src/facets/BookFacet.sol";
import {BookOrderFacet} from "../../src/facets/BookOrderFacet.sol";
import {BookTradeFacet} from "../../src/facets/BookTradeFacet.sol";
import {CurveInventoryFacet} from "../../src/facets/CurveInventoryFacet.sol";
import {CurveViewFacet} from "../../src/facets/CurveViewFacet.sol";
import {IBookAdminFacet} from "../../src/interfaces/IBookAdminFacet.sol";
import {IBookOrderFacet} from "../../src/interfaces/IBookOrderFacet.sol";
import {IBookTradeFacet} from "../../src/interfaces/IBookTradeFacet.sol";
import {ICurveInventoryFacet} from "../../src/interfaces/ICurveInventoryFacet.sol";
import {ICurveViewFacet} from "../../src/interfaces/ICurveViewFacet.sol";
import {LibCLOBBook} from "../../src/libraries/LibCLOBBook.sol";
import {LibCurvePacking} from "../../src/libraries/LibCurvePacking.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {CurveCLOBTypes} from "../../src/types/CurveCLOBTypes.sol";
import {ITestStateFacet, TestBase} from "../helpers/TestBase.sol";

interface ISellExecutionContextHarnessFacet {
    function sellBookBestThroughContext(
        CurveCLOBTypes.SellBookParams calldata params,
        CurveCLOBTypes.SellExecutionContext calldata context
    ) external returns (CurveCLOBTypes.SellBookResult memory result);
}

contract SellExecutionContextHarnessFacet {
    function sellBookBestThroughContext(
        CurveCLOBTypes.SellBookParams calldata params,
        CurveCLOBTypes.SellExecutionContext calldata context
    ) external returns (CurveCLOBTypes.SellBookResult memory result) {
        result = IBookTradeFacet(address(this)).sellBookBestFor(params, context);
    }
}

contract SellExecutionContextProperties is TestBase {
    uint72 internal constant MIN_PRICE = 100_000_000;
    uint72 internal constant MAX_PRICE = 900_000_000;
    uint128 internal constant MIN_SHARES = 1e6;
    uint128 internal constant MAX_SHARES = 500e6;
    uint24 internal constant FLAT_DURATION_MINUTES = 120;
    address internal receiver;

    function setUp() public override {
        super.setUp();
        receiver = makeAddr("receiver");

        vm.startPrank(owner);
        diamond.registerFacet(address(new BookFacet()), _bookSelectors());
        diamond.registerFacet(address(new BookOrderFacet()), _bookOrderSelectors());
        diamond.registerFacet(address(new BookTradeFacet()), _bookTradeSelectors());
        diamond.registerFacet(address(new CurveInventoryFacet()), _curveInventorySelectors());
        diamond.registerFacet(address(new CurveViewFacet()), _curveViewSelectors());
        diamond.registerFacet(address(new SellExecutionContextHarnessFacet()), _contextHarnessSelectors());
        vm.stopPrank();
    }

    // Feature: live-delayed-taker-order, Property 27: Immediate sell behavior is preserved under context refactor.
    function testFuzz_ImmediateSellBehaviorIsPreserved(uint72 rawPrice, uint128 rawShares) public {
        uint72 price = uint72(bound(rawPrice, MIN_PRICE, MAX_PRICE));
        uint128 shares = uint128(bound(rawShares, MIN_SHARES, MAX_SHARES));

        SellScenario memory immediate = _prepareSellScenario("immediate sell context equivalence", price, shares);
        SellScenario memory contextual = _prepareSellScenario("self-call sell context equivalence", price, shares);

        CurveCLOBTypes.SellBookResult memory immediateResult = _sellImmediate(immediate);
        CurveCLOBTypes.SellBookResult memory contextualResult = _sellThroughContext(contextual);

        _assertEquivalentResults(immediateResult, contextualResult);
        _assertEquivalentPostState(immediate, contextual, immediateResult);
    }

    struct SellScenario {
        bytes32 marketId;
        bytes32 bookId;
        uint256 curveId;
        uint256 yesPositionId;
        uint32 generation;
        bytes32 commitment;
        uint128 shares;
        uint128 expectedQuoteOut;
    }

    function _prepareSellScenario(string memory question, uint72 price, uint128 shares)
        internal
        returns (SellScenario memory scenario)
    {
        (scenario.marketId,) = _createMarketFixture(question, _expiry(7 days));
        ITestStateFacet(address(diamond)).materializeMarketSideBookFixture(scenario.marketId, true);
        scenario.bookId = LibCLOBBook.marketBookId(scenario.marketId, true);
        (,,,, scenario.yesPositionId,) = ITestStateFacet(address(diamond)).getStoredMarketCore(scenario.marketId);

        scenario.expectedQuoteOut = uint128((uint256(shares) * uint256(price)) / uint256(LibCurvePacking.PRICE_SCALE));
        scenario.shares = shares;

        vm.startPrank(maker);
        usdc.approve(address(diamond), scenario.expectedQuoteOut);
        scenario.curveId = IBookOrderFacet(address(diamond))
            .postBookCurve(
                scenario.bookId,
                LibEveMarket.CurveSide.BID,
                shares,
                price,
                price,
                FLAT_DURATION_MINUTES,
                0,
                type(uint8).max
            );
        vm.stopPrank();

        _splitToTaker(scenario.marketId, shares);
        (scenario.generation, scenario.commitment) =
            ICurveViewFacet(address(diamond)).getCurveCommitment(scenario.curveId);
    }

    function _sellImmediate(SellScenario memory scenario)
        internal
        returns (CurveCLOBTypes.SellBookResult memory result)
    {
        vm.startPrank(taker);
        IERC1155(address(conditionalTokens)).setApprovalForAll(address(diamond), true);
        result = IBookTradeFacet(address(diamond)).sellBookBest(_sellParams(scenario));
        vm.stopPrank();
    }

    function _sellThroughContext(SellScenario memory scenario)
        internal
        returns (CurveCLOBTypes.SellBookResult memory result)
    {
        vm.prank(taker);
        IERC1155(address(conditionalTokens)).setApprovalForAll(address(diamond), true);
        result = ISellExecutionContextHarnessFacet(address(diamond))
            .sellBookBestThroughContext(
                _sellParams(scenario),
                CurveCLOBTypes.SellExecutionContext({
                    source: taker, seller: taker, receiver: receiver, useEscrowedBase: false
                })
            );
    }

    function _sellParams(SellScenario memory scenario)
        internal
        view
        returns (CurveCLOBTypes.SellBookParams memory params)
    {
        params = CurveCLOBTypes.SellBookParams({
            bookId: scenario.bookId,
            maxBaseIn: scenario.shares,
            minQuoteOut: 0,
            curveIds: _singleCurve(scenario.curveId),
            expectedGenerations: _singleGeneration(scenario.generation),
            expectedCommitments: _singleCommitment(scenario.commitment),
            receiver: receiver
        });
    }

    function _assertEquivalentResults(
        CurveCLOBTypes.SellBookResult memory immediateResult,
        CurveCLOBTypes.SellBookResult memory contextualResult
    ) internal pure {
        assertEq(contextualResult.baseSold, immediateResult.baseSold);
        assertEq(contextualResult.quoteOut, immediateResult.quoteOut);
        assertEq(contextualResult.feePaid, immediateResult.feePaid);
        assertEq(contextualResult.averagePrice, immediateResult.averagePrice);
        assertEq(contextualResult.unfilledBase, immediateResult.unfilledBase);
    }

    function _assertEquivalentPostState(
        SellScenario memory immediate,
        SellScenario memory contextual,
        CurveCLOBTypes.SellBookResult memory result
    ) internal view {
        CurveCLOBTypes.CurveInfo memory immediateCurve =
            ICurveViewFacet(address(diamond)).getCurveInfo(immediate.curveId);
        CurveCLOBTypes.CurveInfo memory contextualCurve =
            ICurveViewFacet(address(diamond)).getCurveInfo(contextual.curveId);

        assertEq(usdc.balanceOf(receiver), uint256(result.quoteOut) * 2);
        assertEq(conditionalTokens.balanceOf(maker, immediate.yesPositionId), result.baseSold);
        assertEq(conditionalTokens.balanceOf(maker, contextual.yesPositionId), result.baseSold);
        assertEq(immediateCurve.remainingVolume, contextualCurve.remainingVolume);
        assertEq(immediateCurve.quoteEscrowRemaining, contextualCurve.quoteEscrowRemaining);
        assertGt(result.baseSold, 0);
        assertEq(immediateCurve.remainingVolume, result.unfilledBase);
    }

    function _splitToTaker(bytes32 marketId, uint128 amount) internal {
        vm.startPrank(taker);
        usdc.approve(address(diamond), amount);
        ICurveInventoryFacet(address(diamond)).splitInventory(marketId, amount);
        vm.stopPrank();
    }

    function _bookSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = IBookAdminFacet.getBookInfo.selector;
    }

    function _bookOrderSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = IBookOrderFacet.postBookCurve.selector;
    }

    function _bookTradeSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = IBookTradeFacet.sellBookBest.selector;
        selectors[1] = IBookTradeFacet.sellBookBestFor.selector;
    }

    function _curveInventorySelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = ICurveInventoryFacet.splitInventory.selector;
    }

    function _curveViewSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](2);
        selectors[0] = ICurveViewFacet.getCurveCommitment.selector;
        selectors[1] = ICurveViewFacet.getCurveInfo.selector;
    }

    function _contextHarnessSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = ISellExecutionContextHarnessFacet.sellBookBestThroughContext.selector;
    }

    function _singleCurve(uint256 curveId) internal pure returns (uint256[] memory curveIds) {
        curveIds = new uint256[](1);
        curveIds[0] = curveId;
    }

    function _singleGeneration(uint32 generation) internal pure returns (uint32[] memory generations) {
        generations = new uint32[](1);
        generations[0] = generation;
    }

    function _singleCommitment(bytes32 commitment) internal pure returns (bytes32[] memory commitments) {
        commitments = new bytes32[](1);
        commitments[0] = commitment;
    }

    function _expiry(uint256 duration) internal view returns (uint64) {
        return uint64(block.timestamp + duration);
    }
}
