// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Ownable} from "../../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {Test} from "../../lib/forge-std/src/Test.sol";
import {MockUSDG} from "../helpers/MockUSDG.sol";

contract MockUSDGTest is Test {
    MockUSDG private token;
    address private stranger = makeAddr("stranger");

    function setUp() public {
        token = new MockUSDG();
    }

    function testOwnerControlsTestnetSupplyAndRiskFlags() public {
        token.mint(address(this), 1_000_000e6);
        token.setBlacklisted(stranger, true);
        token.setPaused(true);

        assertEq(token.totalSupply(), 1_000_000e6);
        assertTrue(token.isBlacklisted(stranger));
        assertTrue(token.paused());
    }

    function testNonOwnerCannotMintPauseOrBlacklist() public {
        vm.startPrank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        token.mint(stranger, 1e6);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        token.setPaused(true);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        token.setBlacklisted(address(this), true);
        vm.stopPrank();
    }
}
