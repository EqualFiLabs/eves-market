// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20Metadata} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ReentrancyGuard} from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import {SEveUSDCVault} from "../../src/SEveUSDCVault.sol";
import {ISEveUSDCVault} from "../../src/interfaces/ISEveUSDCVault.sol";

import {VaultTestBase} from "../helpers/VaultTestBase.sol";

contract MockReentrantAsset is ERC20 {
    uint8 private immutable _decimals;
    address internal targetVault;
    bool internal reenterOnTransferFrom;

    constructor(uint8 decimals_) ERC20("Reentrant Asset", "rAST") {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function configureReentrancy(address vault_, bool enabled) external {
        targetVault = vault_;
        reenterOnTransferFrom = enabled;
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        if (reenterOnTransferFrom) {
            ISEveUSDCVault(targetVault).accrueAum();
        }

        return super.transferFrom(from, to, value);
    }
}

contract SEveUSDCVaultTest is VaultTestBase {
    event RevenueNotified(address indexed caller, uint256 assets);
    event RewardRevenueNotified(address indexed caller, address indexed token, uint256 amount);
    event AssetRevenueSponsored(address indexed sponsor, uint256 assets);
    event RewardSponsored(address indexed sponsor, address indexed token, uint256 amount);
    event RewardTokenRegistered(address indexed token, address indexed registrant, uint256 fee);
    event RewardTokenStatusDisabled(address indexed token);
    event RewardsClaimed(address indexed account, address indexed receiver, address indexed token, uint256 amount);
    event AumFeeBpsSet(uint16 previousFeeBps, uint16 newFeeBps);
    event FeeRecipientSet(address indexed previousFeeRecipient, address indexed newFeeRecipient);
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    function test_RevertWhen_ZeroAmountOperations() public {
        vm.expectRevert(ISEveUSDCVault.ZeroAmount.selector);
        vault.deposit(0, alice);

        vm.expectRevert(ISEveUSDCVault.ZeroAmount.selector);
        vault.mint(0, alice);

        vm.expectRevert(ISEveUSDCVault.ZeroAmount.selector);
        vault.withdraw(0, alice, alice);

        vm.expectRevert(ISEveUSDCVault.ZeroAmount.selector);
        vault.redeem(0, alice, alice);

        vm.prank(revenueNotifier);
        vm.expectRevert(ISEveUSDCVault.ZeroAmount.selector);
        vault.notifyRevenue(0);

        vm.expectRevert(ISEveUSDCVault.ZeroAmount.selector);
        vault.sponsorAssetRevenue(0);

        vm.expectRevert(ISEveUSDCVault.ZeroAmount.selector);
        vault.sponsorReward(address(usdc), 0);
    }

    function test_RevertWhen_WithdrawOrRedeemExceedsOwnerShares() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ISEveUSDCVault.InsufficientShares.selector, alice, 1, 0));
        vault.withdraw(1, receiver, alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ISEveUSDCVault.InsufficientShares.selector, alice, 1, 0));
        vault.redeem(1, receiver, alice);
    }

    function test_RevertWhen_UnauthorizedRevenueNotifierCalls() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ISEveUSDCVault.UnauthorizedRevenueNotifier.selector, alice));
        vault.notifyRevenue(1);
    }

    function test_RevertWhen_ReentrantCallbackOccurs() public {
        MockReentrantAsset reentrantAsset = new MockReentrantAsset(6);
        SEveUSDCVault reentrantVault =
            new SEveUSDCVault(address(reentrantAsset), owner, feeRecipient, DEFAULT_AUM_FEE_BPS, revenueNotifier);

        reentrantAsset.mint(alice, 10e6);
        reentrantAsset.configureReentrancy(address(reentrantVault), true);

        vm.startPrank(alice);
        reentrantAsset.approve(address(reentrantVault), 10e6);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        reentrantVault.deposit(10e6, alice);
        vm.stopPrank();
    }

    function test_FirstDepositBootstrapsOneToOne() public {
        uint256 assets = 123_456_789;
        _seedEveUSDC(alice, assets);
        _approveAsset(alice, assets);

        vm.prank(alice);
        uint256 shares = vault.deposit(assets, alice);

        assertEq(shares, assets);
        assertEq(vault.balanceOf(alice), assets);
    }

    function test_RevertWhen_PreBootstrapAssetsExist() public {
        uint256 donation = 7e6;
        _seedEveUSDC(alice, donation + 1e6);

        vm.prank(alice);
        eveUSDC.transfer(address(vault), donation);

        vm.startPrank(alice);
        eveUSDC.approve(address(vault), 1e6);
        vm.expectRevert(abi.encodeWithSelector(ISEveUSDCVault.VaultUninitializedWithAssets.selector, donation));
        vault.deposit(1e6, alice);

        vm.expectRevert(abi.encodeWithSelector(ISEveUSDCVault.VaultUninitializedWithAssets.selector, donation));
        vault.mint(1e6, alice);
        vm.stopPrank();
    }

    function test_OwnerCanRecoverPreBootstrapAssets() public {
        uint256 donation = 7e6;
        _seedEveUSDC(alice, donation);

        vm.prank(alice);
        eveUSDC.transfer(address(vault), donation);

        uint256 receiverBefore = eveUSDC.balanceOf(receiver);
        vm.prank(owner);
        uint256 recovered = vault.recoverPreBootstrapAssets(receiver);

        assertEq(recovered, donation);
        assertEq(eveUSDC.balanceOf(receiver) - receiverBefore, donation);
        assertEq(eveUSDC.balanceOf(address(vault)), 0);
    }

    function test_RevertWhen_NotifyRevenueBeforeBootstrap() public {
        uint256 assets = 100e6;
        _seedEveUSDC(revenueNotifier, assets);

        vm.startPrank(revenueNotifier);
        eveUSDC.approve(address(vault), assets);
        vm.expectRevert(ISEveUSDCVault.VaultUninitialized.selector);
        vault.notifyRevenue(assets);
        vm.stopPrank();
    }

    function test_RevertWhen_SponsorAssetRevenueBeforeBootstrap() public {
        uint256 assets = 100e6;
        _seedEveUSDC(alice, assets);

        vm.startPrank(alice);
        eveUSDC.approve(address(vault), assets);
        vm.expectRevert(ISEveUSDCVault.VaultUninitialized.selector);
        vault.sponsorAssetRevenue(assets);
        vm.stopPrank();
    }

    function test_DirectDonationDoesNotLetSeederStealLaterDeposit() public {
        vault = _deployVault(0);

        uint256 attackerDeposit = 1;
        uint256 donation = 1e6;
        uint256 victimDeposit = 1e6;

        uint256 attackerShares = _depositSeeded(alice, attackerDeposit, alice);

        _seedEveUSDC(alice, donation);
        vm.prank(alice);
        eveUSDC.transfer(address(vault), donation);

        uint256 victimShares = _depositSeeded(bob, victimDeposit, bob);

        vm.prank(alice);
        uint256 attackerAssetsOut = vault.redeem(attackerShares, alice, alice);

        vm.prank(bob);
        uint256 victimAssetsOut = vault.redeem(victimShares, bob, bob);

        assertGt(victimShares, 0);
        assertLt(attackerAssetsOut, attackerDeposit + donation);
        assertGe(victimAssetsOut, victimDeposit);
    }

    function test_RevertWhen_DonationWouldRoundDepositToZeroShares() public {
        vault = _deployVault(0);

        _depositSeeded(alice, 1, alice);

        uint256 donation = 1_000_000_000e6;
        _seedEveUSDC(alice, donation);
        vm.prank(alice);
        eveUSDC.transfer(address(vault), donation);

        _seedEveUSDC(bob, 1e6);
        _approveAsset(bob, 1e6);

        vm.prank(bob);
        vm.expectRevert(ISEveUSDCVault.ZeroShares.selector);
        vault.deposit(1e6, bob);
    }

    function test_DepositAndWithdrawEmitERC4626Events() public {
        uint256 assets = 100e6;
        _seedEveUSDC(alice, assets);
        _approveAsset(alice, assets);

        vm.prank(alice);
        vm.expectEmit(true, true, false, true, address(vault));
        emit Deposit(alice, alice, assets, assets);
        uint256 shares = vault.deposit(assets, alice);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true, address(vault));
        emit Withdraw(alice, receiver, alice, assets, shares);
        vault.redeem(shares, receiver, alice);
    }

    function test_MintAndWithdrawEmitERC4626Events() public {
        uint256 shares = 75e6;
        _seedEveUSDC(alice, shares);
        _approveAsset(alice, shares);

        vm.prank(alice);
        vm.expectEmit(true, true, false, true, address(vault));
        emit Deposit(alice, alice, shares, shares);
        uint256 assets = vault.mint(shares, alice);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true, address(vault));
        emit Withdraw(alice, receiver, alice, assets, shares);
        vault.withdraw(assets, receiver, alice);
    }

    function test_MultiEpochGapCompoundsFees() public {
        vault = _deployVault(500);
        uint256 assets = 1_000_000e6;
        _depositSeeded(alice, assets, alice);

        vm.warp(block.timestamp + 30 days);

        uint256 feeRecipientBefore = eveUSDC.balanceOf(feeRecipient);
        uint256 feeAssets = vault.accrueAum();
        uint256 theoreticalFeeAssets = _theoreticalFeeWad(assets, vault.aumFeeBps(), 30) / WAD;

        assertApproxEqAbs(feeAssets, theoreticalFeeAssets, 1);
        assertEq(eveUSDC.balanceOf(feeRecipient) - feeRecipientBefore, feeAssets);
    }

    function test_TinyBalanceRemainderCarriesForward() public {
        vault = _deployVault(10_000);
        _depositSeeded(alice, 100, alice);

        vm.warp(block.timestamp + 1 days);
        vault.accrueAum();
        assertGt(vault.feeRemainderWad(), 0);
        assertEq(eveUSDC.balanceOf(feeRecipient), 0);

        vm.warp(block.timestamp + 4 days);
        vault.accrueAum();
        assertGt(eveUSDC.balanceOf(feeRecipient), 0);
        assertLt(vault.feeRemainderWad(), 1e18);
    }

    function test_ZeroEpochAccrualIsNoOp() public {
        _depositSeeded(alice, 1_000e6, alice);

        uint64 lastAccrualBefore = vault.lastAccrualTimestamp();
        uint256 feeRecipientBefore = eveUSDC.balanceOf(feeRecipient);
        uint256 feeAssets = vault.accrueAum();

        assertEq(feeAssets, 0);
        assertEq(vault.lastAccrualTimestamp(), lastAccrualBefore);
        assertEq(eveUSDC.balanceOf(feeRecipient), feeRecipientBefore);
    }

    function test_ZeroAssetVaultAdvancesTimestampWithoutTransfer() public {
        uint64 lastAccrualBefore = vault.lastAccrualTimestamp();
        vm.warp(block.timestamp + 5 days + 17 hours);

        uint256 feeAssets = vault.accrueAum();

        assertEq(feeAssets, 0);
        assertEq(vault.lastAccrualTimestamp(), lastAccrualBefore + 5 days);
        assertEq(eveUSDC.balanceOf(feeRecipient), 0);
    }

    function test_GovernanceEventsEmit() public {
        address newFeeRecipient = makeAddr("new-fee-recipient");

        vm.prank(owner);
        vm.expectEmit(false, false, false, true, address(vault));
        emit AumFeeBpsSet(DEFAULT_AUM_FEE_BPS, 300);
        vault.setAumFeeBps(300);

        vm.prank(owner);
        vm.expectEmit(true, true, false, true, address(vault));
        emit FeeRecipientSet(feeRecipient, newFeeRecipient);
        vault.setFeeRecipient(newFeeRecipient);
    }

    function test_RevertWhen_FeeRecipientIsZero() public {
        vm.prank(owner);
        vm.expectRevert(ISEveUSDCVault.ZeroAddress.selector);
        vault.setFeeRecipient(address(0));
    }

    function test_NotifyRevenueEmitsEvent() public {
        _depositSeeded(alice, 1e6, alice);
        uint256 assets = 100e6;
        _seedEveUSDC(revenueNotifier, assets);

        vm.startPrank(revenueNotifier);
        eveUSDC.approve(address(vault), assets);
        vm.expectEmit(true, false, false, true, address(vault));
        emit RevenueNotified(revenueNotifier, assets);
        vault.notifyRevenue(assets);
        vm.stopPrank();
    }

    function test_SponsorAssetRevenueRaisesShareValueWithoutMintingShares() public {
        vault = _deployVault(0);

        uint256 aliceDeposit = 100e6;
        uint256 sponsoredAssets = 20e6;
        uint256 aliceShares = _depositSeeded(alice, aliceDeposit, alice);
        _seedEveUSDC(carol, sponsoredAssets);

        uint256 supplyBefore = vault.totalSupply();
        uint256 assetsBefore = vault.totalAssets();

        vm.startPrank(carol);
        eveUSDC.approve(address(vault), sponsoredAssets);
        vm.expectEmit(true, false, false, true, address(vault));
        emit AssetRevenueSponsored(carol, sponsoredAssets);
        vault.sponsorAssetRevenue(sponsoredAssets);
        vm.stopPrank();

        assertEq(vault.totalSupply(), supplyBefore);
        assertEq(vault.totalAssets(), assetsBefore + sponsoredAssets);

        vm.prank(alice);
        uint256 aliceAssetsOut = vault.redeem(aliceShares, alice, alice);

        assertApproxEqAbs(aliceAssetsOut, aliceDeposit + sponsoredAssets, 1_000);
    }

    function test_RegisterRewardTokenPaysRegistrationFeeToTreasury() public {
        _depositSeeded(alice, 100e6, alice);
        uint256 registrationFee = vault.rewardTokenRegistrationFee();
        _seedEveUSDC(alice, registrationFee);

        uint256 treasuryBefore = eveUSDC.balanceOf(feeRecipient);
        uint256 vaultAssetsBefore = vault.totalAssets();

        vm.startPrank(alice);
        eveUSDC.approve(address(vault), registrationFee);
        vm.expectEmit(true, true, false, true, address(vault));
        emit RewardTokenRegistered(address(usdc), alice, registrationFee);
        vault.registerRewardToken(address(usdc));
        vm.stopPrank();

        assertEq(eveUSDC.balanceOf(feeRecipient) - treasuryBefore, registrationFee);
        assertEq(vault.totalAssets(), vaultAssetsBefore);
        assertEq(eveUSDC.balanceOf(address(vault)), vaultAssetsBefore);
        assertEq(uint256(vault.rewardTokenStatus(address(usdc))), uint256(ISEveUSDCVault.RewardTokenStatus.ACTIVE));
        assertTrue(vault.isRewardTokenActive(address(usdc)));
    }

    function test_RegisteredRewardTokenRevenueIsClaimableProRata() public {
        _depositSeeded(alice, 100e6, alice);
        _depositSeeded(bob, 300e6, bob);
        _registerUsdcRewardToken(alice);

        uint256 rewardAmount = 40e6;
        usdc.mint(revenueNotifier, rewardAmount);

        vm.startPrank(revenueNotifier);
        usdc.approve(address(vault), rewardAmount);
        vm.expectEmit(true, true, false, true, address(vault));
        emit RewardRevenueNotified(revenueNotifier, address(usdc), rewardAmount);
        vault.notifyRevenue(address(usdc), rewardAmount);
        vm.stopPrank();

        assertEq(vault.previewRewards(alice, address(usdc)), 10e6);
        assertEq(vault.previewRewards(bob, address(usdc)), 30e6);

        address[] memory tokens = _singleTokenArray(address(usdc));
        uint256 aliceBefore = usdc.balanceOf(receiver);
        vm.prank(alice);
        vm.expectEmit(true, true, true, true, address(vault));
        emit RewardsClaimed(alice, receiver, address(usdc), 10e6);
        uint256[] memory amounts = vault.claimRewards(tokens, receiver);

        assertEq(amounts[0], 10e6);
        assertEq(usdc.balanceOf(receiver) - aliceBefore, 10e6);
        assertEq(vault.previewRewards(alice, address(usdc)), 0);
        assertEq(vault.rewardLiability(address(usdc)), 30e6);
    }

    function test_SponsorRewardIsPermissionlessAndClaimableProRata() public {
        _depositSeeded(alice, 100e6, alice);
        _depositSeeded(bob, 300e6, bob);
        _registerUsdcRewardToken(alice);

        uint256 rewardAmount = 40e6;
        usdc.mint(carol, rewardAmount);

        vm.startPrank(carol);
        usdc.approve(address(vault), rewardAmount);
        vm.expectEmit(true, true, false, true, address(vault));
        emit RewardSponsored(carol, address(usdc), rewardAmount);
        uint256 received = vault.sponsorReward(address(usdc), rewardAmount);
        vm.stopPrank();

        assertEq(received, rewardAmount);
        assertEq(vault.previewRewards(alice, address(usdc)), 10e6);
        assertEq(vault.previewRewards(bob, address(usdc)), 30e6);
        assertEq(vault.rewardLiability(address(usdc)), rewardAmount);
    }

    function test_RewardCheckpointingPreservesAccrualAcrossShareTransfers() public {
        _depositSeeded(alice, 100e6, alice);
        _depositSeeded(bob, 100e6, bob);
        _registerUsdcRewardToken(alice);

        _notifyUsdcReward(30e6);

        vm.prank(alice);
        vault.transfer(bob, 100e6);

        _notifyUsdcReward(30e6);

        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.balanceOf(bob), 200e6);
        assertEq(vault.previewRewards(alice, address(usdc)), 15e6);
        assertEq(vault.previewRewards(bob, address(usdc)), 45e6);

        address[] memory tokens = _singleTokenArray(address(usdc));
        vm.prank(alice);
        vault.claimRewards(tokens, alice);

        vm.prank(bob);
        vault.claimRewards(tokens, bob);

        assertEq(usdc.balanceOf(alice), 15e6);
        assertEq(usdc.balanceOf(bob), 45e6);
        assertEq(vault.rewardLiability(address(usdc)), 0);
    }

    function test_DisabledRewardTokenRejectsNewRevenueButAllowsExistingClaims() public {
        _depositSeeded(alice, 100e6, alice);
        _registerUsdcRewardToken(alice);
        _notifyUsdcReward(10e6);

        vm.prank(owner);
        vm.expectEmit(true, false, false, true, address(vault));
        emit RewardTokenStatusDisabled(address(usdc));
        vault.disableRewardToken(address(usdc));

        usdc.mint(revenueNotifier, 1e6);
        vm.startPrank(revenueNotifier);
        usdc.approve(address(vault), 1e6);
        vm.expectRevert(abi.encodeWithSelector(ISEveUSDCVault.RewardTokenDisabled.selector, address(usdc)));
        vault.notifyRevenue(address(usdc), 1e6);
        vm.stopPrank();

        address[] memory tokens = _singleTokenArray(address(usdc));
        vm.prank(alice);
        uint256[] memory amounts = vault.claimRewards(tokens, alice);

        assertEq(amounts[0], 10e6);
        assertEq(usdc.balanceOf(alice), 10e6);
    }

    function test_RevertWhen_DisabledRewardTokenIsSponsored() public {
        _depositSeeded(alice, 100e6, alice);
        _registerUsdcRewardToken(alice);

        vm.prank(owner);
        vault.disableRewardToken(address(usdc));

        usdc.mint(carol, 1e6);
        vm.startPrank(carol);
        usdc.approve(address(vault), 1e6);
        vm.expectRevert(abi.encodeWithSelector(ISEveUSDCVault.RewardTokenDisabled.selector, address(usdc)));
        vault.sponsorReward(address(usdc), 1e6);
        vm.stopPrank();
    }

    function test_RevertWhen_UnregisteredRewardTokenRevenueIsNotified() public {
        _depositSeeded(alice, 100e6, alice);
        usdc.mint(revenueNotifier, 1e6);

        vm.startPrank(revenueNotifier);
        usdc.approve(address(vault), 1e6);
        vm.expectRevert(abi.encodeWithSelector(ISEveUSDCVault.RewardTokenNotActive.selector, address(usdc)));
        vault.notifyRevenue(address(usdc), 1e6);
        vm.stopPrank();
    }

    function test_RevertWhen_UnregisteredRewardTokenIsSponsored() public {
        _depositSeeded(alice, 100e6, alice);
        usdc.mint(carol, 1e6);

        vm.startPrank(carol);
        usdc.approve(address(vault), 1e6);
        vm.expectRevert(abi.encodeWithSelector(ISEveUSDCVault.RewardTokenNotActive.selector, address(usdc)));
        vault.sponsorReward(address(usdc), 1e6);
        vm.stopPrank();
    }

    function test_RevertWhen_AssetTokenIsSponsoredAsClaimableReward() public {
        _depositSeeded(alice, 100e6, alice);
        _seedEveUSDC(carol, 1e6);

        vm.startPrank(carol);
        eveUSDC.approve(address(vault), 1e6);
        vm.expectRevert(abi.encodeWithSelector(ISEveUSDCVault.AssetRewardMustUseAssetRevenue.selector, address(eveUSDC)));
        vault.sponsorReward(address(eveUSDC), 1e6);
        vm.stopPrank();
    }

    function test_FairnessExampleAliceRevenueBob() public {
        vault = _deployVault(0);

        uint256 aliceDeposit = 100e6;
        uint256 revenueAssets = 20e6;
        uint256 bobDeposit = 100e6;

        uint256 aliceShares = _depositSeeded(alice, aliceDeposit, alice);
        _notifyRevenue(revenueAssets);

        uint256 bobShares = _depositSeeded(bob, bobDeposit, bob);

        vm.prank(alice);
        uint256 aliceAssetsOut = vault.redeem(aliceShares, receiver, alice);

        vm.prank(bob);
        uint256 bobAssetsOut = vault.redeem(bobShares, carol, bob);

        assertApproxEqAbs(aliceAssetsOut, 120e6, 1_000);
        assertApproxEqAbs(bobAssetsOut, 100e6, 1_000);
    }

    function test_ViewSurfaceMatchesSpec() public view {
        assertEq(vault.asset(), address(eveUSDC));
        assertEq(vault.owner(), owner);
        assertEq(vault.revenueNotifier(), revenueNotifier);
        assertEq(vault.feeRecipient(), feeRecipient);
        assertEq(vault.aumFeeBps(), DEFAULT_AUM_FEE_BPS);
        assertEq(vault.epochLength(), 1 days);
        assertEq(vault.decimals(), IERC20Metadata(address(eveUSDC)).decimals());
        assertEq(vault.maxDeposit(alice), type(uint256).max);
        assertEq(vault.maxMint(alice), type(uint256).max);
    }

    function test_MaxWithdrawAndMaxRedeemClampToLiquidAssets() public {
        uint256 assets = 300e6;
        uint256 debtPrincipal = 200e6;
        address borrower = makeAddr("borrower");

        _depositSeeded(alice, assets, alice);
        _setLendingContract(address(this));
        vault.reportLoan(debtPrincipal);
        vault.disburseLoan(borrower, debtPrincipal, 0);

        assertEq(vault.maxWithdraw(alice), assets - debtPrincipal);
        assertEq(vault.maxRedeem(alice), assets - debtPrincipal);
    }

    function _registerUsdcRewardToken(address registrant) internal {
        uint256 registrationFee = vault.rewardTokenRegistrationFee();
        _seedEveUSDC(registrant, registrationFee);

        vm.startPrank(registrant);
        eveUSDC.approve(address(vault), registrationFee);
        vault.registerRewardToken(address(usdc));
        vm.stopPrank();
    }

    function _notifyUsdcReward(uint256 amount) internal {
        usdc.mint(revenueNotifier, amount);

        vm.startPrank(revenueNotifier);
        usdc.approve(address(vault), amount);
        vault.notifyRevenue(address(usdc), amount);
        vm.stopPrank();
    }

    function _singleTokenArray(address token) internal pure returns (address[] memory tokens) {
        tokens = new address[](1);
        tokens[0] = token;
    }
}
