// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "../../lib/forge-std/src/Test.sol";

import {EveUSDC} from "../../src/EveUSDC.sol";

import {MockUSDC} from "./MockUSDC.sol";

abstract contract EveUSDCTestBase is Test {
    uint256 internal constant USDC_UNIT = 1e6;
    uint256 internal constant EVEUSDC_UNIT = 1e18;
    uint256 internal constant USDC_TO_EVEUSDC_SCALE = 1e12;

    MockUSDC internal usdc;
    EveUSDC internal eveUSDC;

    address internal onramp;
    address internal offramp;
    address internal alice;
    address internal bob;
    address internal receiver;

    function setUp() public virtual {
        onramp = makeAddr("onramp");
        offramp = makeAddr("offramp");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        receiver = makeAddr("receiver");

        usdc = new MockUSDC();
        eveUSDC = new EveUSDC(address(usdc), onramp, offramp);
    }

    function _wrapFrom(address account, uint256 amount, address to) internal returns (uint256 minted) {
        usdc.mint(account, amount);

        vm.startPrank(account);
        usdc.approve(address(eveUSDC), amount);
        minted = eveUSDC.wrap(amount, to);
        vm.stopPrank();
    }

    function _prefundAndMint(address to, uint256 amount) internal {
        uint256 backing = (amount + USDC_TO_EVEUSDC_SCALE - 1) / USDC_TO_EVEUSDC_SCALE;
        usdc.mint(address(eveUSDC), backing);

        vm.prank(onramp);
        eveUSDC.mint(to, amount);
    }

    function _assertBackingInvariant() internal view {
        assertGe(usdc.balanceOf(address(eveUSDC)) * USDC_TO_EVEUSDC_SCALE, eveUSDC.totalSupply());
    }
}
