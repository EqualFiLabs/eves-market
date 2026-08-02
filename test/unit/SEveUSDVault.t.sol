// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {EveRiskShares} from "../../src/EveRiskShares.sol";
import {EveUSD} from "../../src/EveUSD.sol";
import {EveUSDPool} from "../../src/EveUSDPool.sol";
import {SEveUSDVault} from "../../src/SEveUSDVault.sol";
import {ISEveUSDCVault} from "../../src/interfaces/ISEveUSDCVault.sol";
import {CanonicalWETH9} from "../../src/mocks/CanonicalWETH9.sol";
import {MockETHUSDOracle} from "../../src/mocks/MockETHUSDOracle.sol";
import {MockUSDC} from "../helpers/MockUSDC.sol";

contract SEveUSDVaultTest is Test {
    uint256 internal constant PRICE_WAD = 2_500e18;
    uint256 internal constant MAX_STALENESS = 1 hours;
    uint256 internal constant COLLATERAL_RATIO_BPS = 15_000;
    uint256 internal constant RECOVERY_TRIGGER_BPS = 8_000;
    uint256 internal constant WETH_PROFILE = 1;

    CanonicalWETH9 internal weth;
    EveUSD internal eveUSD;
    EveRiskShares internal evRisk;
    MockETHUSDOracle internal oracle;
    EveUSDPool internal pool;
    SEveUSDVault internal vault;
    MockUSDC internal usdc;

    address internal owner = makeAddr("owner");
    address internal feeRecipient = makeAddr("feeRecipient");
    address internal revenueNotifier = makeAddr("revenueNotifier");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        vm.warp(1_700_000_000);
        weth = new CanonicalWETH9();
        oracle = new MockETHUSDOracle(PRICE_WAD, MAX_STALENESS);
        (eveUSD, evRisk, pool) = _deployPool();
        vault = new SEveUSDVault(address(eveUSD), owner, feeRecipient, 0, revenueNotifier);
        usdc = new MockUSDC();
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
    }

    function test_MetadataAndAssetUseEveUSD() public view {
        assertEq(vault.name(), "sEVEUSD");
        assertEq(vault.symbol(), "sEVEUSD");
        assertEq(vault.decimals(), 18);
        assertEq(vault.asset(), address(eveUSD));
        assertEq(vault.owner(), owner);
        assertEq(vault.revenueNotifier(), revenueNotifier);
    }

    function test_DepositRedeemAndAssetSponsorshipUseEveUSD() public {
        _mintEveUSD(alice, 1 ether);

        vm.startPrank(alice);
        eveUSD.approve(address(vault), 1_500e18);
        uint256 shares = vault.deposit(1_000e18, alice);
        uint256 assetsBefore = vault.totalAssets();
        vault.sponsorAssetRevenue(100e18);
        vm.stopPrank();

        assertEq(shares, 1_000e18);
        assertEq(vault.totalAssets(), assetsBefore + 100e18);

        vm.prank(alice);
        uint256 assetsOut = vault.redeem(shares, alice, alice);

        assertApproxEqAbs(assetsOut, 1_100e18, 1);
    }

    function test_SponsoredRewardTokenIsVaultSpecificAndClaimable() public {
        _mintEveUSD(alice, 3 ether);
        _mintEveUSD(bob, 1 ether);

        vm.startPrank(alice);
        eveUSD.approve(address(vault), type(uint256).max);
        vault.deposit(100e18, alice);
        vault.registerRewardToken(address(usdc));
        vm.stopPrank();

        vm.startPrank(bob);
        eveUSD.approve(address(vault), type(uint256).max);
        vault.deposit(300e18, bob);
        vm.stopPrank();

        usdc.mint(bob, 40e6);
        vm.startPrank(bob);
        usdc.approve(address(vault), 40e6);
        vault.sponsorReward(address(usdc), 40e6);
        vm.stopPrank();

        assertEq(vault.previewRewards(alice, address(usdc)), 10e6);
        assertEq(vault.previewRewards(bob, address(usdc)), 30e6);
    }

    function test_RevertWhen_EveUSDIsSponsoredAsClaimableReward() public {
        _mintEveUSD(alice, 1 ether);

        vm.startPrank(alice);
        eveUSD.approve(address(vault), 100e18);
        vault.deposit(50e18, alice);
        vm.expectRevert(abi.encodeWithSelector(ISEveUSDCVault.AssetRewardMustUseAssetRevenue.selector, address(eveUSD)));
        vault.sponsorReward(address(eveUSD), 1e18);
        vm.stopPrank();
    }

    function _mintEveUSD(address account, uint256 wethAmount) internal {
        vm.startPrank(account);
        weth.deposit{value: wethAmount}();
        weth.approve(address(pool), wethAmount);
        pool.depositCollateral(WETH_PROFILE, wethAmount, account, account);
        vm.stopPrank();
    }

    function _deployPool()
        internal
        returns (EveUSD deployedEveUSD, EveRiskShares deployedEvRisk, EveUSDPool deployedPool)
    {
        address predictedPool = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 2);
        deployedEveUSD = new EveUSD(predictedPool);
        deployedEvRisk = new EveRiskShares(predictedPool, "");
        deployedPool = new EveUSDPool(
            address(weth),
            address(deployedEveUSD),
            address(deployedEvRisk),
            address(oracle),
            owner,
            COLLATERAL_RATIO_BPS,
            RECOVERY_TRIGGER_BPS
        );
        assertEq(address(deployedPool), predictedPool);
    }
}
