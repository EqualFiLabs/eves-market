// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Ownable} from "../../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {Test} from "../../lib/forge-std/src/Test.sol";

import {Faucet} from "../../src/Faucet.sol";
import {MockEveToken} from "../helpers/MockEveToken.sol";
import {MockUSDC} from "../helpers/MockUSDC.sol";

contract FaucetTest is Test {
    Faucet internal faucet;
    MockEveToken internal eve;
    MockUSDC internal usdc;

    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    address internal treasury = makeAddr("treasury");

    uint256 internal constant USDC_CLAIM_AMOUNT = 1_000e6;
    uint256 internal constant EVE_CLAIM_AMOUNT = 10_000e18;

    event TokenConfigured(address indexed token, uint256 amount, bool enabled);
    event Claimed(address indexed user, uint256 timestamp);
    event TokenClaimed(address indexed user, address indexed token, uint256 amount);
    event Withdrawn(address indexed token, address indexed to, uint256 amount);

    function setUp() public {
        faucet = new Faucet(owner);
        eve = new MockEveToken();
        usdc = new MockUSDC();

        eve.mint(address(faucet), 100_000e18);
        usdc.mint(address(faucet), 20_000e6);
    }

    function test_OwnerConfiguresTokensAndUserClaimsAllEnabledAmounts() public {
        _configureDefaultTokens();

        vm.expectEmit(true, true, false, true, address(faucet));
        emit TokenClaimed(alice, address(usdc), USDC_CLAIM_AMOUNT);
        vm.expectEmit(true, true, false, true, address(faucet));
        emit TokenClaimed(alice, address(eve), EVE_CLAIM_AMOUNT);
        vm.expectEmit(true, false, false, true, address(faucet));
        emit Claimed(alice, block.timestamp);

        vm.prank(alice);
        faucet.claim();

        assertEq(usdc.balanceOf(alice), USDC_CLAIM_AMOUNT);
        assertEq(eve.balanceOf(alice), EVE_CLAIM_AMOUNT);
        assertEq(faucet.lastClaimAt(alice), block.timestamp);
        assertEq(faucet.nextClaimAt(alice), block.timestamp + faucet.CLAIM_INTERVAL());
    }

    function test_RevertWhen_ClaimingBeforeCooldownExpires() public {
        _configureDefaultTokens();

        vm.prank(alice);
        faucet.claim();

        uint256 nextAllowed = block.timestamp + faucet.CLAIM_INTERVAL();
        vm.expectRevert(abi.encodeWithSelector(Faucet.FaucetClaimTooSoon.selector, nextAllowed));
        vm.prank(alice);
        faucet.claim();

        vm.warp(nextAllowed);
        vm.prank(alice);
        faucet.claim();

        assertEq(usdc.balanceOf(alice), USDC_CLAIM_AMOUNT * 2);
        assertEq(eve.balanceOf(alice), EVE_CLAIM_AMOUNT * 2);
    }

    function test_DisabledTokenIsSkipped() public {
        _configureDefaultTokens();

        vm.prank(owner);
        faucet.setTokenEnabled(address(eve), false);

        vm.prank(alice);
        faucet.claim();

        assertEq(usdc.balanceOf(alice), USDC_CLAIM_AMOUNT);
        assertEq(eve.balanceOf(alice), 0);
    }

    function test_RevertWhen_NoEnabledTokensExist() public {
        vm.expectRevert(Faucet.FaucetNoEnabledTokens.selector);
        vm.prank(alice);
        faucet.claim();
    }

    function test_RevertWhen_FaucetBalanceCannotCoverClaim() public {
        uint256 faucetBalance = usdc.balanceOf(address(faucet));

        vm.prank(owner);
        faucet.setToken(address(usdc), faucetBalance + 1, true);

        vm.expectRevert(
            abi.encodeWithSelector(
                Faucet.FaucetInsufficientBalance.selector, address(usdc), faucetBalance + 1, faucetBalance
            )
        );
        vm.prank(alice);
        faucet.claim();
    }

    function test_OwnerCanUpdateAmountsAndWithdraw() public {
        _configureDefaultTokens();

        vm.expectEmit(true, false, false, true, address(faucet));
        emit TokenConfigured(address(usdc), 500e6, true);
        vm.prank(owner);
        faucet.setTokenAmount(address(usdc), 500e6);

        vm.expectEmit(true, true, false, true, address(faucet));
        emit Withdrawn(address(usdc), treasury, 100e6);
        vm.prank(owner);
        faucet.withdraw(address(usdc), treasury, 100e6);

        assertEq(usdc.balanceOf(treasury), 100e6);
    }

    function test_RevertWhen_NonOwnerConfiguresOrWithdraws() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        faucet.setToken(address(usdc), USDC_CLAIM_AMOUNT, true);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        faucet.withdraw(address(usdc), alice, 1);
    }

    function test_RevertWhen_ConfiguringZeroToken() public {
        vm.expectRevert(abi.encodeWithSelector(Faucet.FaucetInvalidToken.selector, address(0)));
        vm.prank(owner);
        faucet.setToken(address(0), USDC_CLAIM_AMOUNT, true);
    }

    function test_GetTokensAndConfigExposeConfiguredAssets() public {
        _configureDefaultTokens();

        address[] memory tokens = faucet.getTokens();
        assertEq(tokens.length, 2);
        assertEq(tokens[0], address(usdc));
        assertEq(tokens[1], address(eve));

        (uint256 amount, bool enabled, bool exists) = faucet.getTokenConfig(address(usdc));
        assertEq(amount, USDC_CLAIM_AMOUNT);
        assertTrue(enabled);
        assertTrue(exists);
    }

    function _configureDefaultTokens() internal {
        vm.startPrank(owner);
        faucet.setToken(address(usdc), USDC_CLAIM_AMOUNT, true);
        faucet.setToken(address(eve), EVE_CLAIM_AMOUNT, true);
        vm.stopPrank();
    }
}
