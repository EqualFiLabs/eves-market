// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20Errors} from "../../lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";

import {IVaultRouter} from "../../src/interfaces/IVaultRouter.sol";
import {OwnershipFacet} from "../../src/facets/OwnershipFacet.sol";
import {VaultRouterFacet} from "../../src/facets/VaultRouterFacet.sol";
import {LibRouter} from "../../src/libraries/LibRouter.sol";
import {CanonicalWETH9} from "../../src/mocks/CanonicalWETH9.sol";

import {VaultTestBase} from "../helpers/VaultTestBase.sol";

contract VaultRouterTest is VaultTestBase {
    function test_RevertWhen_WrapAndDepositAmountIsZero() public {
        vm.prank(alice);
        vm.expectRevert(IVaultRouter.ZeroAmount.selector);
        router.wrapAndDeposit(0, alice);
    }

    function test_RevertWhen_RedeemAndUnwrapSharesIsZero() public {
        vm.prank(alice);
        vm.expectRevert(IVaultRouter.ZeroAmount.selector);
        router.redeemAndUnwrap(0, alice);
    }

    function test_RevertWhen_WrapETHToEveETHAmountIsZero() public {
        vm.prank(alice);
        vm.expectRevert(IVaultRouter.ZeroAmount.selector);
        router.wrapETHToEveETH(EVE_ETH_PROFILE_ID, alice);
    }

    function test_RevertWhen_WrapETHToEveETHReceiverIsZero() public {
        vm.deal(alice, 1 ether);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IVaultRouter.InvalidReceiver.selector, address(0)));
        router.wrapETHToEveETH{value: 1 ether}(EVE_ETH_PROFILE_ID, address(0));
    }

    function test_RevertWhen_WrapAndDepositLacksUsdcApproval() public {
        uint256 amount = 100e6;
        usdc.mint(alice, amount);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(diamond), 0, amount)
        );
        router.wrapAndDeposit(amount, alice);
    }

    function test_RevertWhen_RedeemAndUnwrapLacksShareApproval() public {
        uint256 amount = 100e6;

        usdc.mint(alice, amount);
        vm.startPrank(alice);
        usdc.approve(address(diamond), amount);
        uint256 shares = router.wrapAndDeposit(amount, alice);
        vm.stopPrank();

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(diamond), 0, shares)
        );
        router.redeemAndUnwrap(shares, alice);
    }

    function test_WrapETHToEveETHMintsToReceiverInOneCall() public {
        uint256 amount = 2 ether;
        vm.deal(alice, amount);

        vm.prank(alice);
        uint256 minted = router.wrapETHToEveETH{value: amount}(EVE_ETH_PROFILE_ID, receiver);

        assertEq(minted, amount);
        assertEq(eveETH.balanceOf(receiver), amount);
        assertEq(weth.balanceOf(address(eveETH)), amount);
        assertEq(alice.balance, 0);
        _assertRouterBalancesZero();
    }

    function test_RevertWhen_WrapETHToEveETHProfileIsMissing() public {
        uint8 missingProfileId = 2;
        uint256 amount = 1 ether;
        vm.deal(alice, amount);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IVaultRouter.CollateralProfileNotFound.selector, missingProfileId));
        router.wrapETHToEveETH{value: amount}(missingProfileId, receiver);
    }

    function test_RevertWhen_WrapETHToEveETHProfileIsDisabled() public {
        vm.prank(owner);
        OwnershipFacet(address(diamond)).setCollateralProfileEnabled(EVE_ETH_PROFILE_ID, false);

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IVaultRouter.CollateralProfileDisabled.selector, EVE_ETH_PROFILE_ID));
        router.wrapETHToEveETH{value: 1 ether}(EVE_ETH_PROFILE_ID, receiver);
    }

    function test_RevertWhen_WrapETHToEveETHProfileWrapperIsMissing() public {
        uint8 missingWrapperProfileId = 2;

        vm.prank(owner);
        OwnershipFacet(address(diamond))
            .setCollateralProfile(missingWrapperProfileId, address(eveETH), address(0), uint128(WAD), 0, true);

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IVaultRouter.CollateralProfileWrapperMissing.selector, missingWrapperProfileId)
        );
        router.wrapETHToEveETH{value: 1 ether}(missingWrapperProfileId, receiver);
    }

    function test_RevertWhen_WrapETHToEveETHProfileWrapperDoesNotMatchEveETH() public {
        CanonicalWETH9 otherWeth = new CanonicalWETH9();
        uint8 mismatchProfileId = 2;

        vm.prank(owner);
        OwnershipFacet(address(diamond))
            .setCollateralProfile(mismatchProfileId, address(eveETH), address(otherWeth), uint128(WAD), 0, true);

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IVaultRouter.CollateralProfileWrapperMismatch.selector,
                mismatchProfileId,
                address(weth),
                address(otherWeth)
            )
        );
        router.wrapETHToEveETH{value: 1 ether}(mismatchProfileId, receiver);
    }

    function test_RouterLeavesNoResidualBalancesAfterRoundTrip() public {
        uint256 amount = 250e6;

        usdc.mint(alice, amount);
        vm.startPrank(alice);
        usdc.approve(address(diamond), amount);
        uint256 shares = router.wrapAndDeposit(amount, alice);
        vault.approve(address(diamond), shares);
        uint256 usdcOut = router.redeemAndUnwrap(shares, alice);
        vm.stopPrank();

        assertEq(usdcOut, amount);
        _assertRouterBalancesZero();
    }

    function test_WrapAndDepositScalesUsdcIntoEighteenDecimalVaultAssets() public {
        uint256 amount = 1e6;

        usdc.mint(alice, amount);

        vm.startPrank(alice);
        usdc.approve(address(diamond), amount);
        uint256 shares = router.wrapAndDeposit(amount, alice);
        vm.stopPrank();

        assertEq(shares, 1e18);
        assertEq(vault.totalAssets(), 1e18);
        _assertRouterBalancesZero();
    }

    function test_RevertWhen_VaultRouterResidualBalanceCheckFails() public {
        VaultRouterResidualHarness harness = new VaultRouterResidualHarness();
        usdc.mint(address(harness), 1);

        vm.expectRevert(abi.encodeWithSelector(IVaultRouter.ResidualRouterBalance.selector, address(usdc), 0, 1));
        harness.exposedAssertBalanceRestored(address(usdc), 0);
    }
}

contract VaultRouterResidualHarness is VaultRouterFacet {
    function exposedAssertBalanceRestored(address token, uint256 balanceBefore) external view {
        LibRouter.assertBalanceRestored(token, balanceBefore);
    }
}
