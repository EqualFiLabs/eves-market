// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {EveRiskShares} from "../../src/EveRiskShares.sol";
import {EveUSD} from "../../src/EveUSD.sol";
import {EveUSDPool} from "../../src/EveUSDPool.sol";
import {EvRiskStakingRewards} from "../../src/EvRiskStakingRewards.sol";
import {IEveUSDPool} from "../../src/interfaces/IEveUSDPool.sol";
import {IEvRiskStakingRewards} from "../../src/interfaces/IEvRiskStakingRewards.sol";
import {CanonicalWETH9} from "../../src/mocks/CanonicalWETH9.sol";
import {MockETHUSDOracle} from "../../src/mocks/MockETHUSDOracle.sol";
import {MockUSDC} from "../helpers/MockUSDC.sol";

contract EvRiskStakingRewardsTest is Test {
    uint256 internal constant PRICE_WAD = 2_500e18;
    uint256 internal constant MAX_STALENESS = 1 hours;
    uint256 internal constant COLLATERAL_RATIO_BPS = 15_000;
    uint256 internal constant RECOVERY_TRIGGER_BPS = 8_000;
    uint256 internal constant WETH_PROFILE = 1;
    uint256 internal constant SERIES_ONE = 1;
    uint256 internal constant ONE_PAIR_COLLATERAL = 0.0006 ether;

    CanonicalWETH9 internal weth;
    EveUSD internal eveUSD;
    EveRiskShares internal evRisk;
    MockETHUSDOracle internal oracle;
    EveUSDPool internal pool;
    EvRiskStakingRewards internal staking;
    MockUSDC internal rewardToken;

    address internal owner = makeAddr("owner");
    address internal treasury = makeAddr("treasury");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal feeRouter = makeAddr("feeRouter");

    function setUp() public {
        vm.warp(1_700_000_000);
        weth = new CanonicalWETH9();
        oracle = new MockETHUSDOracle(PRICE_WAD, MAX_STALENESS);
        (eveUSD, evRisk, pool) = _deployPool(COLLATERAL_RATIO_BPS, RECOVERY_TRIGGER_BPS);
        staking = new EvRiskStakingRewards(address(evRisk), address(pool), WETH_PROFILE, treasury, owner);
        rewardToken = new MockUSDC();

        vm.deal(alice, 20 ether);
        vm.deal(bob, 20 ether);
    }

    function test_StakeLocksOnlyCurrentActiveSeriesShares() public {
        _depositTo(alice, ONE_PAIR_COLLATERAL);

        vm.startPrank(alice);
        evRisk.setApprovalForAll(address(staking), true);
        uint256 seriesId = staking.stake(1e18);
        vm.stopPrank();

        assertEq(seriesId, SERIES_ONE);
        assertEq(staking.totalStaked(SERIES_ONE), 1e18);
        assertEq(staking.stakedBalance(alice, SERIES_ONE), 1e18);
        assertEq(evRisk.balanceOf(alice, SERIES_ONE), 0);
        assertEq(evRisk.balanceOf(address(staking), SERIES_ONE), 1e18);
    }

    function test_NotifyRewardSplitsByStakedEvRiskBalance() public {
        _stakeEvRisk(alice, ONE_PAIR_COLLATERAL);
        _stakeEvRisk(bob, ONE_PAIR_COLLATERAL * 3);

        _notifyReward(400e6);

        assertEq(staking.previewClaim(alice, SERIES_ONE, address(rewardToken)), 100e6);
        assertEq(staking.previewClaim(bob, SERIES_ONE, address(rewardToken)), 300e6);

        vm.prank(alice);
        assertEq(staking.claim(SERIES_ONE, address(rewardToken)), 100e6);

        vm.prank(bob);
        assertEq(staking.claim(SERIES_ONE, address(rewardToken)), 300e6);

        assertEq(rewardToken.balanceOf(alice), 100e6);
        assertEq(rewardToken.balanceOf(bob), 300e6);
    }

    function test_NotifyRewardRoutesToTreasuryWhenNoActiveStakers() public {
        _notifyReward(50e6);

        assertEq(rewardToken.balanceOf(treasury), 50e6);
        assertEq(staking.previewClaim(alice, SERIES_ONE, address(rewardToken)), 0);
    }

    function test_NotifyRewardRoutesToTreasuryWhileSeriesIsRecoveryPending() public {
        _stakeEvRisk(alice, ONE_PAIR_COLLATERAL);
        oracle.setPriceWad(1_900e18);
        pool.startRecovery(SERIES_ONE);

        _notifyReward(75e6);

        assertEq(rewardToken.balanceOf(treasury), 75e6);
        assertEq(staking.previewClaim(alice, SERIES_ONE, address(rewardToken)), 0);
    }

    function test_RevertWhen_StakeDuringRecoveryPending() public {
        _depositTo(alice, ONE_PAIR_COLLATERAL);
        oracle.setPriceWad(1_900e18);
        pool.startRecovery(SERIES_ONE);

        vm.startPrank(alice);
        evRisk.setApprovalForAll(address(staking), true);
        vm.expectRevert(abi.encodeWithSelector(IEvRiskStakingRewards.InvalidSeries.selector, SERIES_ONE));
        staking.stake(1e18);
        vm.stopPrank();
    }

    function test_UnstakeKeepsAccruedRewardsClaimable() public {
        _stakeEvRisk(alice, ONE_PAIR_COLLATERAL);
        _notifyReward(125e6);

        vm.prank(alice);
        staking.unstake(SERIES_ONE, 1e18);

        assertEq(staking.stakedBalance(alice, SERIES_ONE), 0);
        assertEq(evRisk.balanceOf(alice, SERIES_ONE), 1e18);
        assertEq(staking.previewClaim(alice, SERIES_ONE, address(rewardToken)), 125e6);

        vm.prank(alice);
        staking.claim(SERIES_ONE, address(rewardToken));

        assertEq(rewardToken.balanceOf(alice), 125e6);
    }

    function _stakeEvRisk(address account, uint256 collateralAmount) internal {
        (, uint256 eveUSDMinted,) = _depositTo(account, collateralAmount);

        vm.startPrank(account);
        evRisk.setApprovalForAll(address(staking), true);
        staking.stake(eveUSDMinted);
        vm.stopPrank();
    }

    function _notifyReward(uint256 amount) internal {
        rewardToken.mint(feeRouter, amount);

        vm.startPrank(feeRouter);
        rewardToken.approve(address(staking), amount);
        staking.notifyReward(address(rewardToken), amount);
        vm.stopPrank();
    }

    function _depositTo(address account, uint256 amount)
        internal
        returns (uint256 seriesId, uint256 eveUSDMinted, uint256 sharesMinted)
    {
        _wrapAndApprove(account, amount, address(pool));

        vm.prank(account);
        return pool.depositCollateral(WETH_PROFILE, amount, account, account);
    }

    function _wrapAndApprove(address account, uint256 amount, address spender) internal {
        vm.prank(account);
        weth.deposit{value: amount}();

        vm.prank(account);
        weth.approve(spender, amount);
    }

    function _deployPool(uint256 collateralRatioBps, uint256 recoveryTriggerBps)
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
            collateralRatioBps,
            recoveryTriggerBps
        );
        assertEq(address(deployedPool), predictedPool);
    }
}
