// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {EveRiskShares} from "../../src/EveRiskShares.sol";
import {EveUSD} from "../../src/EveUSD.sol";
import {EveUSDPool} from "../../src/EveUSDPool.sol";
import {IEveUSDPool} from "../../src/interfaces/IEveUSDPool.sol";
import {CanonicalWETH9} from "../../src/mocks/CanonicalWETH9.sol";
import {MockETHUSDOracle} from "../../src/mocks/MockETHUSDOracle.sol";

contract EveUSDPoolTest is Test {
    uint256 internal constant PRICE_WAD = 2_500e18;
    uint256 internal constant MAX_STALENESS = 1 hours;
    uint256 internal constant COLLATERAL_RATIO_BPS = 15_000;
    uint256 internal constant RECOVERY_TRIGGER_BPS = 8_000;
    uint256 internal constant RECOVERED_COLLATERAL_RATIO_BPS = 10_001;
    uint256 internal constant SERIES_ONE = 1;
    uint256 internal constant SERIES_TWO = 2;
    uint256 internal constant ONE_PAIR_COLLATERAL = 0.0006 ether;
    uint256 internal constant ONE_ETH_MINT = 1_666_666_666_666_666_666_666;

    CanonicalWETH9 internal weth;
    EveUSD internal eveUSD;
    EveRiskShares internal evRisk;
    MockETHUSDOracle internal oracle;
    EveUSDPool internal pool;

    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal operator = makeAddr("operator");
    address internal receiver = makeAddr("receiver");

    function setUp() public {
        vm.warp(1_700_000_000);
        weth = new CanonicalWETH9();
        oracle = new MockETHUSDOracle(PRICE_WAD, MAX_STALENESS);
        (eveUSD, evRisk, pool) = _deployPool(COLLATERAL_RATIO_BPS, RECOVERY_TRIGGER_BPS);
        vm.deal(alice, 20 ether);
        vm.deal(bob, 20 ether);
        vm.deal(operator, 20 ether);
    }

    function test_ConstructorStoresSeriesConfig() public view {
        assertEq(pool.weth(), address(weth));
        assertEq(pool.eveUSD(), address(eveUSD));
        assertEq(pool.evRisk(), address(evRisk));
        assertEq(pool.currentRiskSeriesId(), SERIES_ONE);
        assertEq(pool.nextSeriesCollateralRatioBps(), COLLATERAL_RATIO_BPS);
        assertEq(pool.nextSeriesRecoveryTriggerBps(), RECOVERY_TRIGGER_BPS);
        assertEq(pool.recoveryTimelock(), 7 days);
        assertEq(eveUSD.pool(), address(pool));
        assertEq(evRisk.pool(), address(pool));

        IEveUSDPool.RiskSeries memory series = pool.riskSeries(SERIES_ONE);
        assertEq(uint8(series.status), uint8(IEveUSDPool.SeriesStatus.Active));
        assertEq(series.startPriceWad, PRICE_WAD);
        assertEq(series.wethPerPairWad, ONE_PAIR_COLLATERAL);
        assertEq(series.collateralRatioBps, COLLATERAL_RATIO_BPS);
        assertEq(series.recoveryTriggerBps, RECOVERY_TRIGGER_BPS);
    }

    function test_DepositMintsEqualEveUSDAndCurrentSeriesShares() public {
        IEveUSDPool.DepositPreview memory preview = pool.previewDeposit(ONE_PAIR_COLLATERAL);
        assertEq(preview.seriesId, SERIES_ONE);
        assertEq(preview.eveUSDMinted, 1e18);
        assertEq(preview.sharesMinted, 1e18);
        assertEq(preview.wethPerPairWad, ONE_PAIR_COLLATERAL);

        (uint256 seriesId, uint256 eveUSDMinted, uint256 sharesMinted) = _depositTo(alice, ONE_PAIR_COLLATERAL);

        assertEq(seriesId, SERIES_ONE);
        assertEq(eveUSDMinted, 1e18);
        assertEq(sharesMinted, 1e18);
        assertEq(pool.totalCollateral(), ONE_PAIR_COLLATERAL);
        assertEq(weth.balanceOf(address(pool)), ONE_PAIR_COLLATERAL);
        assertEq(eveUSD.balanceOf(alice), 1e18);
        assertEq(evRisk.balanceOf(alice, SERIES_ONE), 1e18);

        IEveUSDPool.RiskSeries memory series = pool.riskSeries(SERIES_ONE);
        assertEq(series.eveUSDSupply, 1e18);
        assertEq(series.sharesSupply, 1e18);
        assertEq(series.accountedCollateral, ONE_PAIR_COLLATERAL);
    }

    function test_DirectWETHDonationDoesNotAffectAccountedCollateralOrMinting() public {
        _wrapAndApprove(bob, 1 ether, address(pool));
        vm.prank(bob);
        weth.transfer(address(pool), 1 ether);

        assertEq(weth.balanceOf(address(pool)), 1 ether);
        assertEq(pool.totalCollateral(), 0);

        IEveUSDPool.DepositPreview memory preview = pool.previewDeposit(1 ether);
        assertEq(preview.eveUSDMinted, ONE_ETH_MINT);
        assertEq(preview.sharesMinted, ONE_ETH_MINT);

        _depositTo(alice, 1 ether);
        assertEq(pool.totalCollateral(), 1 ether);
        assertEq(weth.balanceOf(address(pool)), 2 ether);
    }

    function test_RecombineRequiresMatchedEveUSDAndShares() public {
        _depositTo(alice, ONE_PAIR_COLLATERAL);

        IEveUSDPool.RedemptionPreview memory preview = pool.previewRecombine(SERIES_ONE, 1e18);
        assertEq(preview.sharesBurned, 1e18);
        assertEq(preview.collateralOut, ONE_PAIR_COLLATERAL);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IEveUSDPool.InvalidShareAmount.selector, 1e18 - 1, 1e18));
        pool.recombine(SERIES_ONE, 1e18, 1e18 - 1, receiver);

        vm.prank(alice);
        uint256 wethOut = pool.recombine(SERIES_ONE, 1e18, 1e18, receiver);

        assertEq(wethOut, ONE_PAIR_COLLATERAL);
        assertEq(weth.balanceOf(receiver), ONE_PAIR_COLLATERAL);
        assertEq(pool.totalCollateral(), 0);
        assertEq(eveUSD.balanceOf(alice), 0);
        assertEq(evRisk.balanceOf(alice, SERIES_ONE), 0);
        assertEq(eveUSD.totalSupply(), 0);
    }

    function test_RecoveryCannotStartAboveSeriesTrigger() public {
        _depositTo(alice, ONE_PAIR_COLLATERAL);

        vm.expectRevert(abi.encodeWithSelector(IEveUSDPool.RecoveryNotEligible.selector, PRICE_WAD, 2_000e18));
        pool.startRecovery(SERIES_ONE);
    }

    function test_RecoveryPendingReturnedSharesCanBeReclaimedAndRecombined() public {
        _depositTo(alice, ONE_PAIR_COLLATERAL);
        oracle.setPriceWad(1_900e18);

        pool.startRecovery(SERIES_ONE);

        vm.prank(alice);
        pool.returnRiskShares(SERIES_ONE, 0.25e18);

        assertEq(evRisk.balanceOf(alice, SERIES_ONE), 0.75e18);
        assertEq(pool.returnedShares(SERIES_ONE, alice), 0.25e18);
        assertEq(pool.riskSeries(SERIES_ONE).returnedSharesSupply, 0.25e18);

        vm.prank(alice);
        uint256 reclaimed = pool.reclaimReturnedRiskShares(SERIES_ONE, alice);

        assertEq(reclaimed, 0.25e18);
        assertEq(evRisk.balanceOf(alice, SERIES_ONE), 1e18);
        assertEq(pool.returnedShares(SERIES_ONE, alice), 0);
        assertEq(pool.riskSeries(SERIES_ONE).returnedSharesSupply, 0);

        vm.prank(alice);
        uint256 wethOut = pool.recombine(SERIES_ONE, 1e18, 1e18, receiver);

        assertEq(wethOut, ONE_PAIR_COLLATERAL);
        assertEq(weth.balanceOf(receiver), ONE_PAIR_COLLATERAL);
    }

    function test_RecoveryCanCancelAndReturnedSharesCanBeReclaimed() public {
        _depositTo(alice, ONE_PAIR_COLLATERAL);
        oracle.setPriceWad(1_900e18);

        pool.startRecovery(SERIES_ONE);

        vm.prank(alice);
        pool.returnRiskShares(SERIES_ONE, 0.25e18);

        oracle.setPriceWad(2_500e18);
        pool.cancelRecovery(SERIES_ONE);

        vm.prank(alice);
        uint256 reclaimed = pool.reclaimReturnedRiskShares(SERIES_ONE, alice);

        assertEq(reclaimed, 0.25e18);
        assertEq(evRisk.balanceOf(alice, SERIES_ONE), 1e18);
        assertEq(uint8(pool.riskSeries(SERIES_ONE).status), uint8(IEveUSDPool.SeriesStatus.Active));
    }

    function test_RevertWhen_FinalizationWouldMakeReturnedClaimsValueNegative() public {
        _depositTo(alice, ONE_PAIR_COLLATERAL);
        oracle.setPriceWad(1_900e18);

        pool.startRecovery(SERIES_ONE);
        vm.warp(block.timestamp + 7 days);
        oracle.setUpdatedAt(block.timestamp);

        vm.expectRevert(
            abi.encodeWithSelector(
                IEveUSDPool.RecoveryClaimValueInsufficient.selector,
                ONE_PAIR_COLLATERAL,
                789_473_684_210_526
            )
        );
        pool.finalizeRecovery(SERIES_ONE);
    }

    function test_RecoveryClaimWithWETHDifferencePaysSurplus() public {
        _depositTo(alice, ONE_PAIR_COLLATERAL * 2);
        vm.prank(owner);
        pool.setNextSeriesConfig(RECOVERED_COLLATERAL_RATIO_BPS, RECOVERY_TRIGGER_BPS);
        oracle.setPriceWad(1_900e18);

        pool.startRecovery(SERIES_ONE);

        vm.prank(alice);
        pool.returnRiskShares(SERIES_ONE, 0.5e18);

        vm.expectRevert(abi.encodeWithSelector(IEveUSDPool.SeriesNotActive.selector, SERIES_ONE));
        pool.previewDeposit(ONE_PAIR_COLLATERAL);

        vm.warp(block.timestamp + 7 days);
        oracle.setUpdatedAt(block.timestamp);
        uint256 newSeriesId = pool.finalizeRecovery(SERIES_ONE);

        assertEq(newSeriesId, SERIES_TWO);
        assertEq(pool.currentRiskSeriesId(), SERIES_TWO);
        assertEq(uint8(pool.riskSeries(SERIES_ONE).status), uint8(IEveUSDPool.SeriesStatus.Liquidatable));
        assertEq(uint8(pool.riskSeries(SERIES_TWO).status), uint8(IEveUSDPool.SeriesStatus.Active));
        assertEq(pool.riskSeries(SERIES_TWO).startPriceWad, 1_900e18);

        IEveUSDPool.RecoveredRiskClaimPreview memory preview = pool.previewRecoveredRiskClaim(
            alice, SERIES_ONE, IEveUSDPool.RecoveryClaimMode.WETHDifference
        );
        assertEq(preview.returnedShares, 0.5e18);
        assertEq(preview.sharesMinted, 0.5e18);
        assertEq(preview.eveUSDMinted, 0);
        assertEq(preview.wethOut, preview.oldClaimWeth - preview.baseNewClaimWeth);

        vm.prank(alice);
        (uint256 sharesMinted, uint256 eveUSDMinted, uint256 wethOut) =
            pool.claimRecoveredRiskShares(SERIES_ONE, alice, IEveUSDPool.RecoveryClaimMode.WETHDifference);

        assertEq(sharesMinted, preview.sharesMinted);
        assertEq(eveUSDMinted, 0);
        assertEq(wethOut, preview.wethOut);
        assertEq(evRisk.balanceOf(alice, SERIES_TWO), 0.5e18);
        assertEq(weth.balanceOf(alice), preview.wethOut);
        assertEq(pool.returnedShares(SERIES_ONE, alice), 0);
        assertEq(pool.riskSeries(SERIES_ONE).returnedSharesSupply, 0);
        assertEq(pool.riskSeries(SERIES_TWO).sharesSupply, 0.5e18);
        assertEq(pool.riskSeries(SERIES_TWO).eveUSDSupply, 0.5e18);
    }

    function test_RecoveryClaimWithWETHDifferenceRoundsBaseCollateralUp() public {
        _depositTo(alice, ONE_PAIR_COLLATERAL);
        vm.prank(owner);
        pool.setNextSeriesConfig(RECOVERED_COLLATERAL_RATIO_BPS, RECOVERY_TRIGGER_BPS);
        oracle.setPriceWad(1_900e18);

        pool.startRecovery(SERIES_ONE);

        vm.prank(alice);
        pool.returnRiskShares(SERIES_ONE, 10_000);

        vm.warp(block.timestamp + 7 days);
        oracle.setUpdatedAt(block.timestamp);
        pool.finalizeRecovery(SERIES_ONE);

        IEveUSDPool.RecoveredRiskClaimPreview memory preview = pool.previewRecoveredRiskClaim(
            alice, SERIES_ONE, IEveUSDPool.RecoveryClaimMode.WETHDifference
        );

        assertEq(preview.oldClaimWeth, 6);
        assertEq(preview.baseNewClaimWeth, 6);
        assertEq(preview.wethOut, 0);

        vm.prank(alice);
        pool.claimRecoveredRiskShares(SERIES_ONE, alice, IEveUSDPool.RecoveryClaimMode.WETHDifference);

        assertEq(pool.riskSeries(SERIES_TWO).accountedCollateral, 6);
        assertEq(evRisk.balanceOf(alice, SERIES_TWO), 10_000);
    }

    function test_RecoveryClaimWithMorePairsMintsSurplusEveUSD() public {
        _depositTo(alice, ONE_PAIR_COLLATERAL);
        vm.prank(owner);
        pool.setNextSeriesConfig(RECOVERED_COLLATERAL_RATIO_BPS, RECOVERY_TRIGGER_BPS);
        oracle.setPriceWad(1_900e18);

        pool.startRecovery(SERIES_ONE);

        vm.prank(alice);
        pool.returnRiskShares(SERIES_ONE, 1e18);

        vm.warp(block.timestamp + 7 days);
        oracle.setUpdatedAt(block.timestamp);
        pool.finalizeRecovery(SERIES_ONE);

        IEveUSDPool.RecoveredRiskClaimPreview memory preview =
            pool.previewRecoveredRiskClaim(alice, SERIES_ONE, IEveUSDPool.RecoveryClaimMode.MorePairs);
        assertGt(preview.sharesMinted, 1e18);
        assertEq(preview.eveUSDMinted, preview.sharesMinted - 1e18);
        assertEq(preview.wethOut, 0);

        vm.prank(alice);
        (uint256 sharesMinted, uint256 eveUSDMinted, uint256 wethOut) =
            pool.claimRecoveredRiskShares(SERIES_ONE, alice, IEveUSDPool.RecoveryClaimMode.MorePairs);

        assertEq(sharesMinted, preview.sharesMinted);
        assertEq(eveUSDMinted, preview.eveUSDMinted);
        assertEq(wethOut, 0);
        assertEq(eveUSD.balanceOf(alice), 1e18 + preview.eveUSDMinted);
        assertEq(eveUSD.totalSupply(), 1e18 + preview.eveUSDMinted);
        assertEq(evRisk.balanceOf(alice, SERIES_TWO), preview.sharesMinted);
        assertEq(pool.riskSeries(SERIES_TWO).sharesSupply, preview.sharesMinted);
        assertEq(pool.riskSeries(SERIES_TWO).eveUSDSupply, preview.sharesMinted);
    }

    function test_OperatorRecoveryBurnsExpiredRiskAndMintsNewSeriesClaim() public {
        _depositTo(alice, ONE_PAIR_COLLATERAL * 2);
        uint256 poolWethBefore = weth.balanceOf(address(pool));
        vm.prank(owner);
        pool.setNextSeriesConfig(RECOVERED_COLLATERAL_RATIO_BPS, RECOVERY_TRIGGER_BPS);
        oracle.setPriceWad(1_900e18);

        pool.startRecovery(SERIES_ONE);
        vm.warp(block.timestamp + 7 days);
        oracle.setUpdatedAt(block.timestamp);
        pool.finalizeRecovery(SERIES_ONE);

        IEveUSDPool.OperatorRecoveryPreview memory preview =
            pool.previewOperatorRecovery(alice, SERIES_ONE, 0.5e18);
        assertEq(preview.newSeriesId, SERIES_TWO);
        assertEq(preview.sharesBurned, 0.5e18);
        assertGt(preview.sharesMinted, 0.5e18);
        assertEq(preview.eveUSDMinted, preview.sharesMinted - 0.5e18);
        assertEq(preview.collateralMoved, ONE_PAIR_COLLATERAL / 2);

        vm.prank(operator);
        (uint256 newSeriesId, uint256 sharesMinted, uint256 eveUSDMinted) =
            pool.recoverExpiredRisk(alice, SERIES_ONE, 0.5e18);

        assertEq(newSeriesId, SERIES_TWO);
        assertEq(sharesMinted, preview.sharesMinted);
        assertEq(eveUSDMinted, preview.eveUSDMinted);
        assertEq(evRisk.balanceOf(alice, SERIES_ONE), 1.5e18);
        assertEq(evRisk.balanceOf(operator, SERIES_TWO), preview.sharesMinted);
        assertEq(eveUSD.balanceOf(operator), preview.eveUSDMinted);
        assertEq(eveUSD.totalSupply(), 2e18 + preview.eveUSDMinted);
        assertEq(weth.balanceOf(address(pool)), poolWethBefore);
        assertEq(weth.balanceOf(operator), 0);
        assertEq(pool.riskSeries(SERIES_ONE).eveUSDSupply, 1.5e18);
        assertEq(pool.riskSeries(SERIES_TWO).eveUSDSupply, preview.sharesMinted);
    }

    function test_NewDepositsUseActiveSeriesAfterRecovery() public {
        _depositTo(alice, ONE_PAIR_COLLATERAL);
        vm.prank(owner);
        pool.setNextSeriesConfig(RECOVERED_COLLATERAL_RATIO_BPS, RECOVERY_TRIGGER_BPS);
        oracle.setPriceWad(1_900e18);

        pool.startRecovery(SERIES_ONE);
        vm.warp(block.timestamp + 7 days);
        oracle.setUpdatedAt(block.timestamp);
        pool.finalizeRecovery(SERIES_ONE);

        IEveUSDPool.DepositPreview memory preview = pool.previewDeposit(ONE_PAIR_COLLATERAL);
        _depositTo(bob, ONE_PAIR_COLLATERAL);

        assertEq(eveUSD.balanceOf(bob), preview.eveUSDMinted);
        assertEq(evRisk.balanceOf(bob, SERIES_ONE), 0);
        assertEq(evRisk.balanceOf(bob, SERIES_TWO), preview.sharesMinted);
    }

    function _depositTo(address account, uint256 amount)
        internal
        returns (uint256 seriesId, uint256 eveUSDMinted, uint256 sharesMinted)
    {
        _wrapAndApprove(account, amount, address(pool));

        vm.prank(account);
        return pool.depositWETH(amount, account, account);
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
        address predictedPool = _nextPoolAddress();
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

    function _nextPoolAddress() internal view returns (address) {
        return vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 2);
    }
}
