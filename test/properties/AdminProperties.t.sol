// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IMarketFactoryFacet} from "../../src/interfaces/IMarketFactoryFacet.sol";
import {IOBRResolutionFacet} from "../../src/interfaces/IOBRResolutionFacet.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {OwnershipFacet} from "../../src/facets/OwnershipFacet.sol";

import {SettlementFeeFixture, StateProbeFacet} from "../helpers/DiamondFixtures.sol";

contract AdminPropertiesTest is SettlementFeeFixture {
    uint16 internal constant OLD_ORDERBOOK_ENTRY_FEE_BPS = 100;
    uint128 internal constant OLD_L1_BOND = 0.1 ether;

    // Feature: eve-prediction-market, Property 32: owner-only configuration
    function testFuzz_NonOwnerCannotUpdateConfiguration(
        uint16 feeRateSeed,
        uint128 creationFeeSeed,
        uint64 minDurationSeed,
        uint64 maxDurationOffsetSeed,
        uint64 disputeWindowSeed,
        uint8 maxEscalationSeed
    ) public {
        uint16 feeRate = uint16(bound(uint256(feeRateSeed), 1, 10_000));
        uint128 creationFee = uint128(bound(uint256(creationFeeSeed), 1e6, 500e6));
        uint64 minDuration = uint64(bound(uint256(minDurationSeed), 1 hours, 30 days));
        uint64 maxDuration = minDuration + uint64(bound(uint256(maxDurationOffsetSeed), 1 hours, 30 days));
        uint64 disputeWindow = uint64(bound(uint256(disputeWindowSeed), 1 hours, 7 days));
        uint8 maxEscalation = uint8(bound(uint256(maxEscalationSeed), 1, 3));

        address newConditionalTokens = makeAddr("new-conditional-tokens");
        address newCollateralToken = makeAddr("new-collateral-token");
        address newEveToken = makeAddr("new-eve-token");
        address newTreasury = makeAddr("new-treasury");

        vm.startPrank(outsider);

        vm.expectRevert(abi.encodeWithSelector(Errors.NotContractOwner.selector, outsider));
        OwnershipFacet(address(diamond)).setOrderbookEntryFeeBps(feeRate);

        vm.expectRevert(abi.encodeWithSelector(Errors.NotContractOwner.selector, outsider));
        OwnershipFacet(address(diamond)).setResolutionBondConfig(address(eveToken), 1, 2);

        vm.expectRevert(abi.encodeWithSelector(Errors.NotContractOwner.selector, outsider));
        OwnershipFacet(address(diamond)).setMarketCreationFee(creationFee);

        vm.expectRevert(abi.encodeWithSelector(Errors.NotContractOwner.selector, outsider));
        OwnershipFacet(address(diamond)).setDefaultConditionalTokens(newConditionalTokens);

        vm.expectRevert(abi.encodeWithSelector(Errors.NotContractOwner.selector, outsider));
        OwnershipFacet(address(diamond)).setCollateralToken(newCollateralToken);

        vm.expectRevert(abi.encodeWithSelector(Errors.NotContractOwner.selector, outsider));
        OwnershipFacet(address(diamond)).setEveToken(newEveToken);

        vm.expectRevert(abi.encodeWithSelector(Errors.NotContractOwner.selector, outsider));
        OwnershipFacet(address(diamond)).setEveTreasury(newTreasury);

        vm.expectRevert(abi.encodeWithSelector(Errors.NotContractOwner.selector, outsider));
        OwnershipFacet(address(diamond)).setOrderbookFeeSplit(8_500, 400, 1_000, 100, 0, 0);

        vm.expectRevert(abi.encodeWithSelector(Errors.NotContractOwner.selector, outsider));
        OwnershipFacet(address(diamond)).setDurationParams(minDuration, maxDuration);

        vm.expectRevert(abi.encodeWithSelector(Errors.NotContractOwner.selector, outsider));
        OwnershipFacet(address(diamond)).setDisputeWindow(disputeWindow);

        vm.expectRevert(abi.encodeWithSelector(Errors.NotContractOwner.selector, outsider));
        OwnershipFacet(address(diamond)).setCreatorSettleGrace(disputeWindow);

        vm.expectRevert(abi.encodeWithSelector(Errors.NotContractOwner.selector, outsider));
        OwnershipFacet(address(diamond)).setOpenResolutionTimeout(disputeWindow);

        vm.expectRevert(abi.encodeWithSelector(Errors.NotContractOwner.selector, outsider));
        OwnershipFacet(address(diamond)).setMaxEscalation(maxEscalation);

        vm.expectRevert(abi.encodeWithSelector(Errors.NotContractOwner.selector, outsider));
        OwnershipFacet(address(diamond)).registerCurveProfile(9, address(curveProfile));

        vm.stopPrank();
    }

    // Feature: eve-prediction-market, Property 33: configuration changes apply prospectively
    function testFuzz_OrderbookEntryFeeBpsAppliesToSubsequentMarkets(uint16 newFeeRateSeed, uint128 collateralSeed)
        public
    {
        uint16 newFeeRate = uint16(bound(uint256(newFeeRateSeed), 1, 10_000));
        if (newFeeRate == OLD_ORDERBOOK_ENTRY_FEE_BPS) {
            unchecked {
                newFeeRate += 1;
            }
        }

        uint128 collateralIn = uint128(bound(uint256(collateralSeed), 10_000e6, 25_000e6));

        vm.prank(owner);
        OwnershipFacet(address(diamond)).setOrderbookEntryFeeBps(OLD_ORDERBOOK_ENTRY_FEE_BPS);

        (bytes32 firstMarketId,,) = _createTradingMarket("admin-fee-rate-old", "properties", 7 days);
        _splitFrom(maker, firstMarketId, 150_000e6);
        _approvePositions(maker);

        uint256 firstCurveId = _postCurveFromMaker(firstMarketId, true, 150_000e6, 500_000_000, 500_000_000, 180, 0);
        (, uint128 firstFee,) = _fillCurveFromTaker(firstCurveId, collateralIn);

        (, uint128 feePoolAfterFirst,) = StateProbeFacet(address(diamond)).getStoredMarketTrading(firstMarketId);
        assertEq(feePoolAfterFirst, firstFee);

        vm.prank(owner);
        OwnershipFacet(address(diamond)).setOrderbookEntryFeeBps(newFeeRate);

        (bytes32 secondMarketId,,) = _createTradingMarket("admin-fee-rate-new", "properties", 7 days);
        _splitFrom(maker, secondMarketId, 150_000e6);
        _approvePositions(maker);

        uint256 secondCurveId = _postCurveFromMaker(secondMarketId, true, 150_000e6, 500_000_000, 500_000_000, 180, 0);
        (, uint128 secondFee,) = _fillCurveFromTaker(secondCurveId, collateralIn);

        (, uint128 finalFeePool,) = StateProbeFacet(address(diamond)).getStoredMarketTrading(secondMarketId);

        assertEq(finalFeePool, secondFee);
        assertTrue(secondFee != firstFee);
    }

    // Feature: eve-prediction-market, Property 33: configuration changes apply prospectively
    function testFuzz_MarketCreationFeeAppliesOnlyToFutureMarkets(
        uint128 newFeeSeed,
        uint64 firstDurationSeed,
        uint64 secondDurationSeed
    ) public {
        uint128 oldCreationFee = StateProbeFacet(address(diamond)).marketCreationFee();
        uint128 newCreationFee = uint128(bound(uint256(newFeeSeed), 1e6, 500e6));
        if (newCreationFee == oldCreationFee) {
            newCreationFee += 1e6;
        }

        uint64 firstExpiry = uint64(block.timestamp) + _boundDuration(firstDurationSeed);
        uint64 secondExpiry = uint64(block.timestamp) + _boundDuration(secondDurationSeed) + 1 days;
        uint256 treasuryBalanceBefore = collateralToken.balanceOf(treasury);

        _approveCreator(uint256(oldCreationFee) + uint256(newCreationFee));

        vm.prank(creator);
        bytes32 firstMarketId = IMarketFactoryFacet(address(diamond))
            .createMarket(
                "admin-creation-one",
                "properties",
                DEFAULT_RESOLUTION_SOURCE,
                uint64(block.timestamp),
                firstExpiry,
                0,
                true
            );

        vm.prank(owner);
        OwnershipFacet(address(diamond)).setMarketCreationFee(newCreationFee);

        vm.prank(creator);
        bytes32 secondMarketId = IMarketFactoryFacet(address(diamond))
            .createMarket(
                "admin-creation-two",
                "properties",
                DEFAULT_RESOLUTION_SOURCE,
                uint64(block.timestamp),
                secondExpiry,
                0,
                true
            );

        (,,,, uint128 firstCreationFeePaid,,,) = StateProbeFacet(address(diamond)).getStoredMarketStatus(firstMarketId);
        (,,,, uint128 secondCreationFeePaid,,,) =
            StateProbeFacet(address(diamond)).getStoredMarketStatus(secondMarketId);

        assertEq(firstCreationFeePaid, oldCreationFee);
        assertEq(secondCreationFeePaid, newCreationFee);
        assertEq(collateralToken.balanceOf(treasury), treasuryBalanceBefore + oldCreationFee + newCreationFee);
    }

    // Feature: eve-prediction-market, Property 33: configuration changes apply prospectively
    function testFuzz_DisputeBondUpdatesApplyToFutureDisputes(uint128 newBondSeed) public {
        uint128 newL1Bond = uint128(bound(uint256(newBondSeed), 0.2 ether, 1 ether));

        (bytes32 firstMarketId,) = _createPendingMarket("admin-bond-one", "properties", 8 days);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(firstMarketId, 1);

        vm.prank(challengerOne);
        IOBRResolutionFacet(address(diamond)).disputeResolution(firstMarketId, 2);

        uint128 firstBonded = StateProbeFacet(address(diamond)).getBondedForMarket(firstMarketId, challengerOne);
        assertEq(firstBonded, OLD_L1_BOND);

        vm.prank(owner);
        OwnershipFacet(address(diamond)).setResolutionBondConfig(address(eveToken), newL1Bond, newL1Bond + 0.1 ether);

        firstBonded = StateProbeFacet(address(diamond)).getBondedForMarket(firstMarketId, challengerOne);
        assertEq(firstBonded, OLD_L1_BOND);

        (bytes32 secondMarketId,) = _createPendingMarket("admin-bond-two", "properties", 9 days);

        vm.prank(creator);
        IOBRResolutionFacet(address(diamond)).settleMarket(secondMarketId, 1);

        vm.prank(challengerTwo);
        IOBRResolutionFacet(address(diamond)).disputeResolution(secondMarketId, 2);

        uint128 secondBonded = StateProbeFacet(address(diamond)).getBondedForMarket(secondMarketId, challengerTwo);
        assertEq(secondBonded, newL1Bond);
    }

    function _boundDuration(uint64 durationSeed) internal pure returns (uint64) {
        return uint64(bound(uint256(durationSeed), 2 days, 30 days));
    }
}
