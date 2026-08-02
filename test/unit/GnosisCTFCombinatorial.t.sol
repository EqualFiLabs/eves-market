// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "../../lib/forge-std/src/Test.sol";
import {ERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import {MockUSDG} from "../helpers/MockUSDG.sol";
import {PlainGnosisCTFMock} from "../helpers/PlainGnosisCTFMock.sol";

contract GnosisCTFCombinatorialTest is Test {
    PlainGnosisCTFMock internal ctf;
    MockUSDG internal collateral;

    address internal trader = makeAddr("trader");

    function setUp() public {
        ctf = new PlainGnosisCTFMock();
        collateral = new MockUSDG();
        collateral.mint(trader, 1_000e6);
    }

    function test_NestedSplitMergeAndResolvedLegCompression() public {
        bytes32 conditionA = _prepareCondition("A");
        bytes32 conditionB = _prepareCondition("B");
        uint256[] memory partition = _binaryPartition();

        bytes32 yesACollection = ctf.getCollectionId(bytes32(0), conditionA, 1);
        uint256 yesAPositionId = ctf.getPositionId(ERC20(address(collateral)), yesACollection);
        uint256 noAPositionId =
            ctf.getPositionId(ERC20(address(collateral)), ctf.getCollectionId(bytes32(0), conditionA, 2));
        uint256 yesAYesBPositionId =
            ctf.getPositionId(ERC20(address(collateral)), ctf.getCollectionId(yesACollection, conditionB, 1));
        uint256 yesANoBPositionId =
            ctf.getPositionId(ERC20(address(collateral)), ctf.getCollectionId(yesACollection, conditionB, 2));

        vm.startPrank(trader);
        collateral.approve(address(ctf), 100e6);
        ctf.splitPosition(ERC20(address(collateral)), bytes32(0), conditionA, partition, 100e6);
        ctf.splitPosition(ERC20(address(collateral)), yesACollection, conditionB, partition, 100e6);

        assertEq(ctf.balanceOf(trader, yesAPositionId), 0);
        assertEq(ctf.balanceOf(trader, yesAYesBPositionId), 100e6);
        assertEq(ctf.balanceOf(trader, yesANoBPositionId), 100e6);

        ctf.mergePositions(ERC20(address(collateral)), yesACollection, conditionB, partition, 40e6);

        assertEq(ctf.balanceOf(trader, yesAPositionId), 40e6);
        assertEq(ctf.balanceOf(trader, yesAYesBPositionId), 60e6);
        assertEq(ctf.balanceOf(trader, yesANoBPositionId), 60e6);
        vm.stopPrank();

        uint256[] memory yesPayout = new uint256[](2);
        yesPayout[0] = 1;
        yesPayout[1] = 0;
        ctf.reportPayouts(keccak256("B"), yesPayout);

        uint256[] memory yesOnly = new uint256[](1);
        yesOnly[0] = 1;
        vm.prank(trader);
        ctf.redeemPositions(ERC20(address(collateral)), yesACollection, conditionB, yesOnly);

        assertEq(ctf.balanceOf(trader, yesAPositionId), 100e6);
        assertEq(ctf.balanceOf(trader, yesAYesBPositionId), 0);
        assertEq(ctf.balanceOf(trader, yesANoBPositionId), 60e6);

        uint256[] memory noOnly = new uint256[](1);
        noOnly[0] = 2;
        vm.prank(trader);
        ctf.redeemPositions(ERC20(address(collateral)), yesACollection, conditionB, noOnly);

        assertEq(ctf.balanceOf(trader, yesAPositionId), 100e6);
        assertEq(ctf.balanceOf(trader, yesANoBPositionId), 0);

        vm.prank(trader);
        ctf.mergePositions(ERC20(address(collateral)), bytes32(0), conditionA, partition, 100e6);

        assertEq(ctf.balanceOf(trader, yesAPositionId), 0);
        assertEq(ctf.balanceOf(trader, noAPositionId), 0);
        assertEq(collateral.balanceOf(trader), 1_000e6);
    }

    function _prepareCondition(string memory label) internal returns (bytes32 conditionId) {
        bytes32 questionId = keccak256(bytes(label));
        ctf.prepareCondition(address(this), questionId, 2);
        conditionId = ctf.getConditionId(address(this), questionId, 2);
    }

    function _binaryPartition() internal pure returns (uint256[] memory partition) {
        partition = new uint256[](2);
        partition[0] = 1;
        partition[1] = 2;
    }
}
