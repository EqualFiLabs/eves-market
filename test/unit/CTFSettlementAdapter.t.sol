// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "../../lib/forge-std/src/Test.sol";

import {EvesCTFSettlementAdapter} from "../../src/EvesCTFSettlementAdapter.sol";
import {MockUSDG} from "../helpers/MockUSDG.sol";
import {PlainGnosisCTFMock} from "../helpers/PlainGnosisCTFMock.sol";

contract CTFSettlementAdapterTest is Test {
    uint256 internal constant AMOUNT = 100e6;

    MockUSDG internal collateral;
    PlainGnosisCTFMock internal ctf;
    EvesCTFSettlementAdapter internal adapter;
    address internal alice = makeAddr("alice");
    bytes32 internal questionId = keccak256("binary-market");
    bytes32 internal conditionId;
    uint256 internal yesPositionId;
    uint256 internal noPositionId;

    function setUp() public {
        collateral = new MockUSDG();
        ctf = new PlainGnosisCTFMock();
        adapter = new EvesCTFSettlementAdapter(address(ctf), address(collateral));
        ctf.prepareCondition(address(this), questionId, 2);
        conditionId = ctf.getConditionId(address(this), questionId, 2);
        yesPositionId = ctf.getPositionId(collateral, ctf.getCollectionId(bytes32(0), conditionId, 1));
        noPositionId = ctf.getPositionId(collateral, ctf.getCollectionId(bytes32(0), conditionId, 2));
        collateral.mint(alice, AMOUNT);
    }

    function test_SplitAndMergeRoundTripUsesCanonicalCTFPositions() public {
        vm.startPrank(alice);
        collateral.approve(address(adapter), AMOUNT);
        adapter.splitPosition(conditionId, AMOUNT);
        assertEq(ctf.balanceOf(alice, yesPositionId), AMOUNT);
        assertEq(ctf.balanceOf(alice, noPositionId), AMOUNT);

        ctf.setApprovalForAll(address(adapter), true);
        adapter.mergePositions(conditionId, AMOUNT, alice);
        vm.stopPrank();

        assertEq(collateral.balanceOf(alice), AMOUNT);
        assertEq(ctf.balanceOf(alice, yesPositionId), 0);
        assertEq(ctf.balanceOf(alice, noPositionId), 0);
    }

    function test_PartialRedemptionDoesNotConsumeRemainingPositionBacking() public {
        vm.startPrank(alice);
        collateral.approve(address(adapter), AMOUNT);
        adapter.splitPosition(conditionId, AMOUNT);
        ctf.setApprovalForAll(address(adapter), true);
        vm.stopPrank();

        uint256[] memory payouts = new uint256[](2);
        payouts[0] = 1;
        ctf.reportPayouts(questionId, payouts);

        uint256 partialAmount = 10e6;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = partialAmount;
        vm.prank(alice);
        uint256 payout = adapter.redeemPositions(conditionId, amounts, alice);

        assertEq(payout, partialAmount);
        assertEq(collateral.balanceOf(alice), partialAmount);
        assertEq(ctf.balanceOf(alice, yesPositionId), AMOUNT - partialAmount);
        assertEq(ctf.balanceOf(alice, noPositionId), AMOUNT);
        assertEq(ctf.balanceOf(address(adapter), yesPositionId), 0);
    }
}
