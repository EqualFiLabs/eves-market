// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20Errors} from "../../lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import {Test} from "forge-std/Test.sol";

import {EveRiskShares} from "../../src/EveRiskShares.sol";
import {EveUSD} from "../../src/EveUSD.sol";
import {IEveRiskShares} from "../../src/interfaces/IEveRiskShares.sol";
import {IEveUSD} from "../../src/interfaces/IEveUSD.sol";

contract EveUSDAndEvRiskTest is Test {
    EveUSD internal eveUSD;
    EveRiskShares internal evRisk;

    address internal pool = makeAddr("pool");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal operator = makeAddr("operator");

    function setUp() public {
        eveUSD = new EveUSD(pool);
        evRisk = new EveRiskShares(pool, "");
    }

    function test_EveUSDMetadataAndPoolMatchSpec() public view {
        assertEq(eveUSD.name(), "eveUSD");
        assertEq(eveUSD.symbol(), "eveUSD");
        assertEq(eveUSD.decimals(), 18);
        assertEq(eveUSD.pool(), pool);
    }

    function test_EvRiskMetadataAndPoolMatchSpec() public view {
        assertEq(evRisk.name(), "EvRisk");
        assertEq(evRisk.symbol(), "EVRISK");
        assertEq(evRisk.pool(), pool);
        assertEq(evRisk.uri(1), "");
    }

    function test_RevertWhen_PoolIsZero() public {
        vm.expectRevert(IEveUSD.ZeroAddress.selector);
        new EveUSD(address(0));

        vm.expectRevert(IEveRiskShares.ZeroAddress.selector);
        new EveRiskShares(address(0), "");
    }

    function test_RevertWhen_UnauthorizedMintOrBurn() public {
        vm.expectRevert(abi.encodeWithSelector(IEveUSD.NotMinter.selector, alice));
        vm.prank(alice);
        eveUSD.mint(alice, 1 ether);

        vm.expectRevert(abi.encodeWithSelector(IEveRiskShares.NotPool.selector, alice));
        vm.prank(alice);
        evRisk.mint(alice, 1, 1 ether);
    }

    function test_PoolMintAndBurnSucceed() public {
        vm.startPrank(pool);
        eveUSD.mint(alice, 100 ether);
        eveUSD.burn(alice, 40 ether);
        evRisk.mint(alice, 1, 100 ether);
        evRisk.burn(alice, 1, 40 ether);
        vm.stopPrank();

        assertEq(eveUSD.balanceOf(alice), 60 ether);
        assertEq(eveUSD.totalSupply(), 60 ether);
        assertEq(evRisk.balanceOf(alice, 1), 60 ether);
    }

    function test_TransfersRemainUnrestricted() public {
        vm.startPrank(pool);
        eveUSD.mint(alice, 100 ether);
        evRisk.mint(alice, 1, 100 ether);
        vm.stopPrank();

        vm.prank(alice);
        eveUSD.transfer(bob, 30 ether);

        vm.prank(alice);
        evRisk.safeTransferFrom(alice, bob, 1, 30 ether, "");

        vm.prank(alice);
        evRisk.setApprovalForAll(operator, true);

        vm.prank(operator);
        evRisk.safeTransferFrom(alice, bob, 1, 20 ether, "");

        assertEq(eveUSD.balanceOf(alice), 70 ether);
        assertEq(eveUSD.balanceOf(bob), 30 ether);
        assertEq(evRisk.balanceOf(alice, 1), 50 ether);
        assertEq(evRisk.balanceOf(bob, 1), 50 ether);
    }

    function test_RevertWhen_EveUSDTransferExceedsBalance() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        eveUSD.transfer(bob, 1);
    }
}
