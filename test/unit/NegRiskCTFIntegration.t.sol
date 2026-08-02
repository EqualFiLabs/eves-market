// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "../../lib/forge-std/src/Test.sol";

import {EvesNegRiskAdapter} from "../../src/EvesNegRiskAdapter.sol";
import {IGnosisConditionalTokens} from "../../src/interfaces/IGnosisConditionalTokens.sol";
import {MockUSDG} from "../helpers/MockUSDG.sol";
import {PlainGnosisCTFMock} from "../helpers/PlainGnosisCTFMock.sol";

contract NegRiskCTFIntegrationTest is Test {
    uint256 internal constant AMOUNT = 300e6;
    uint256 internal constant OUTCOME_COUNT = 3;

    MockUSDG internal collateral;
    PlainGnosisCTFMock internal ctf;
    EvesNegRiskAdapter internal adapter;
    address internal alice = makeAddr("alice");
    bytes32 internal eventId;

    function setUp() public {
        collateral = new MockUSDG();
        ctf = new PlainGnosisCTFMock();
        adapter = new EvesNegRiskAdapter(address(ctf), address(collateral), address(this));
        eventId = adapter.prepareEvent(keccak256("election"), OUTCOME_COUNT);
        collateral.mint(alice, 10_000e6);
    }

    function test_HorizontalSplitAndMergeRoundTripRealCollateral() public {
        uint256 beforeBalance = collateral.balanceOf(alice);

        vm.startPrank(alice);
        collateral.approve(address(adapter), AMOUNT);
        adapter.splitEvent(eventId, AMOUNT, alice);

        for (uint256 outcome; outcome < OUTCOME_COUNT; ++outcome) {
            assertEq(ctf.balanceOf(alice, adapter.positionIdFor(eventId, outcome, true)), AMOUNT);
        }

        ctf.setApprovalForAll(address(adapter), true);
        adapter.mergeEvent(eventId, AMOUNT, alice);
        vm.stopPrank();

        assertEq(collateral.balanceOf(alice), beforeBalance);
        for (uint256 outcome; outcome < OUTCOME_COUNT; ++outcome) {
            assertEq(ctf.balanceOf(alice, adapter.positionIdFor(eventId, outcome, true)), 0);
        }
    }

    function test_NoPositionConvertsToEveryComplementaryYesPosition() public {
        bytes32 firstConditionId = adapter.conditionIdFor(eventId, 0);
        uint256 firstYes = adapter.positionIdFor(eventId, 0, true);
        uint256 firstNo = adapter.positionIdFor(eventId, 0, false);

        vm.startPrank(alice);
        collateral.approve(address(adapter), AMOUNT);
        adapter.splitPosition(firstConditionId, AMOUNT);
        assertEq(ctf.balanceOf(alice, firstYes), AMOUNT);
        assertEq(ctf.balanceOf(alice, firstNo), AMOUNT);

        ctf.setApprovalForAll(address(adapter), true);
        adapter.convertPositions(eventId, 1, AMOUNT, alice);

        assertEq(ctf.balanceOf(alice, firstNo), 0);
        for (uint256 outcome; outcome < OUTCOME_COUNT; ++outcome) {
            assertEq(ctf.balanceOf(alice, adapter.positionIdFor(eventId, outcome, true)), AMOUNT);
        }

        adapter.mergeEvent(eventId, AMOUNT, alice);
        vm.stopPrank();

        assertEq(collateral.balanceOf(alice), 10_000e6);
    }

    function test_ResolvedEventRedeemsOnlyWinningYesPosition() public {
        vm.startPrank(alice);
        collateral.approve(address(adapter), AMOUNT);
        adapter.splitEvent(eventId, AMOUNT, alice);
        ctf.setApprovalForAll(address(adapter), true);
        vm.stopPrank();

        adapter.resolveEvent(eventId, 1);

        uint256 collateralBefore = collateral.balanceOf(alice);
        uint256 totalPayout;
        for (uint256 outcome; outcome < OUTCOME_COUNT; ++outcome) {
            uint256[] memory amounts = new uint256[](2);
            amounts[0] = AMOUNT;
            bytes32 conditionId = adapter.conditionIdFor(eventId, outcome);
            vm.prank(alice);
            totalPayout += adapter.redeemPositions(conditionId, amounts, alice);
        }

        assertEq(totalPayout, AMOUNT);
        assertEq(collateral.balanceOf(alice) - collateralBefore, AMOUNT);
    }

    function test_InvalidEventDistributesOneCollateralAcrossAllYesPositions() public {
        vm.startPrank(alice);
        collateral.approve(address(adapter), AMOUNT);
        adapter.splitEvent(eventId, AMOUNT, alice);
        ctf.setApprovalForAll(address(adapter), true);
        vm.stopPrank();

        adapter.resolveEvent(eventId, adapter.INVALID_OUTCOME());

        uint256 totalPayout;
        for (uint256 outcome; outcome < OUTCOME_COUNT; ++outcome) {
            uint256[] memory amounts = new uint256[](2);
            amounts[0] = AMOUNT;
            bytes32 conditionId = adapter.conditionIdFor(eventId, outcome);
            vm.prank(alice);
            totalPayout += adapter.redeemPositions(conditionId, amounts, alice);
        }

        assertEq(totalPayout, AMOUNT);
    }

    function test_RevertWhen_NonOracleResolvesEvent() public {
        vm.prank(alice);
        vm.expectRevert(EvesNegRiskAdapter.OnlyOracle.selector);
        adapter.resolveEvent(eventId, 0);
    }
}
