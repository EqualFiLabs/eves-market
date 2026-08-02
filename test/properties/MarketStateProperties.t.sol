// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IBookAdminFacet} from "../../src/interfaces/IBookAdminFacet.sol";
import {IBookOrderFacet} from "../../src/interfaces/IBookOrderFacet.sol";
import {IBookTradeFacet} from "../../src/interfaces/IBookTradeFacet.sol";
import {IBookViewFacet} from "../../src/interfaces/IBookViewFacet.sol";
import {ICurveInventoryFacet} from "../../src/interfaces/ICurveInventoryFacet.sol";
import {ICurveLifecycleFacet} from "../../src/interfaces/ICurveLifecycleFacet.sol";
import {ICurveTradeFacet} from "../../src/interfaces/ICurveTradeFacet.sol";
import {ICurveViewFacet} from "../../src/interfaces/ICurveViewFacet.sol";
import {CurveCLOBTypes} from "../../src/types/CurveCLOBTypes.sol";
import {IFeeRouterFacet} from "../../src/interfaces/IFeeRouterFacet.sol";
import {IMarketSettlementFacet} from "../../src/interfaces/IMarketSettlementFacet.sol";
import {IOBRResolutionFacet} from "../../src/interfaces/IOBRResolutionFacet.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";

import {SettlementFeeFixture, StateProbeFacet} from "../helpers/DiamondFixtures.sol";

contract MarketStatePropertiesTest is SettlementFeeFixture {
    // Feature: eve-prediction-market, Property 13: market state gating
    function testFuzz_TradingCallsRevertOutsideTradingState(
        uint64 durationSeed,
        uint128 inventorySeed,
        uint128 collateralSeed
    ) public {
        uint64 duration = _boundDuration(durationSeed);
        uint128 makerInventory = uint128(bound(uint256(inventorySeed), 20_000, 250_000));
        uint128 collateralIn = uint128(bound(uint256(collateralSeed), 1, uint256(uint128(makerInventory / 2))));

        (bytes32 marketId,, uint64 expiryTime) = _createTradingMarket("state-trading", "properties", duration);
        _splitFrom(maker, marketId, makerInventory);
        _approvePositions(maker);

        uint256 curveId =
            _postCurveFromMaker(marketId, true, makerInventory / 2, 500_000_000, 500_000_000, 45 days / 1 minutes, 0);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        _expireMarket(marketId, expiryTime);

        (,,,,,, uint8 state,) = StateProbeFacet(address(diamond)).getStoredMarketStatus(marketId);
        assertEq(state, uint8(LibEveMarket.MarketState.Pending));

        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSelector(Errors.MarketNotTrading.selector, marketId));
        ICurveLifecycleFacet(address(diamond))
            .postCurve(
                marketId, true, makerInventory / 2, 450_000_000, 450_000_000, 180, 0, LibEveMarket.PositionTokenType.CTF
            );

        uint256[] memory curveIds = new uint256[](1);
        uint32[] memory generations = new uint32[](1);
        bytes32[] memory commitments = new bytes32[](1);
        curveIds[0] = curveId;
        generations[0] = generation;
        commitments[0] = commitment;

        vm.startPrank(taker);
        collateralToken.approve(address(diamond), collateralIn);

        vm.expectRevert(abi.encodeWithSelector(Errors.MarketNotTrading.selector, marketId));
        ICurveTradeFacet(address(diamond)).fillCurve(curveId, collateralIn, 0, generation, commitment);

        vm.expectRevert(abi.encodeWithSelector(Errors.MarketNotTrading.selector, marketId));
        ICurveTradeFacet(address(diamond))
            .fillBest(
                CurveCLOBTypes.FillBestParams({
                    marketId: marketId,
                    isYesSide: true,
                    maxCollateralIn: collateralIn,
                    minSharesOut: 0,
                    maxAveragePrice: type(uint128).max,
                    curveIds: curveIds,
                    expectedGenerations: generations,
                    expectedCommitments: commitments,
                    payer: taker,
                    receiver: taker
                })
            );
        vm.stopPrank();
    }

    // Feature: eve-prediction-market, Property 13: market state gating
    function testFuzz_SettleMarketRevertsOutsidePendingState(uint64 durationSeed, uint8 outcomeSeed) public {
        uint8 outcome = _boundOutcome(outcomeSeed);

        (bytes32 tradingMarketId,,) =
            _createTradingMarket("state-settle-trading", "properties", _boundDuration(durationSeed));

        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(Errors.MarketNotExpired.selector, tradingMarketId));
        IOBRResolutionFacet(address(diamond)).settleMarket(tradingMarketId, outcome);

        (bytes32 pendingMarketId,) = _createPendingMarket("state-settle-disputed", "properties", 8 days);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(pendingMarketId, outcome);

        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(Errors.MarketNotPending.selector, pendingMarketId));
        IOBRResolutionFacet(address(diamond)).settleMarket(pendingMarketId, outcome);
    }

    // Feature: eve-prediction-market, Property 13: market state gating
    function testFuzz_RedemptionParamsAndCreatorClaimsRequireResolvedState(uint128 collateralSeed) public {
        uint128 collateralIn = uint128(bound(uint256(collateralSeed), 10_000e6, 100_000e6));
        (bytes32 marketId,,) = _createFilledMarketWithFee(
            "state-resolution-gates", "properties", 7 days, 250_000e6, 500_000_000, 500, collateralIn
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.MarketNotResolved.selector, marketId));
        IMarketSettlementFacet(address(diamond)).getCTFRedemptionParams(marketId);

        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(Errors.MarketNotResolved.selector, marketId));
        IFeeRouterFacet(address(diamond)).claimCreatorFees(marketId);
    }

    // Feature: eve-prediction-market, Property 19: market expiry halts trading
    function testFuzz_MarketExpiryTransitionsToPendingAndHaltsTrading(
        uint64 durationSeed,
        uint128 inventorySeed,
        uint128 collateralSeed
    ) public {
        uint64 duration = _boundDuration(durationSeed);
        uint128 makerInventory = uint128(bound(uint256(inventorySeed), 20_000, 250_000));
        uint128 collateralIn = uint128(bound(uint256(collateralSeed), 1, uint256(uint128(makerInventory / 3))));

        (bytes32 marketId,, uint64 expiryTime) = _createTradingMarket("state-expiry", "properties", duration);
        _splitFrom(maker, marketId, makerInventory);
        _approvePositions(maker);

        uint256 curveId =
            _postCurveFromMaker(marketId, true, makerInventory, 400_000_000, 400_000_000, 45 days / 1 minutes, 0);
        (uint32 generation, bytes32 commitment) = ICurveViewFacet(address(diamond)).getCurveCommitment(curveId);

        _expireMarket(marketId, expiryTime);

        (,,,,,, uint8 state,) = StateProbeFacet(address(diamond)).getStoredMarketStatus(marketId);
        assertEq(state, uint8(LibEveMarket.MarketState.Pending));

        vm.prank(taker);
        collateralToken.approve(address(diamond), collateralIn);

        vm.prank(taker);
        vm.expectRevert(abi.encodeWithSelector(Errors.MarketNotTrading.selector, marketId));
        ICurveTradeFacet(address(diamond)).fillCurve(curveId, collateralIn, 0, generation, commitment);
    }

    function _boundDuration(uint64 durationSeed) internal pure returns (uint64) {
        return uint64(bound(uint256(durationSeed), 1 days, 30 days));
    }

    function _boundOutcome(uint8 outcomeSeed) internal pure returns (uint8) {
        return uint8(bound(uint256(outcomeSeed), 1, 3));
    }
}
