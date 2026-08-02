// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {EveRiskShares} from "../../src/EveRiskShares.sol";
import {EveUSD} from "../../src/EveUSD.sol";
import {EveUSDPool} from "../../src/EveUSDPool.sol";
import {IEveUSDPool} from "../../src/interfaces/IEveUSDPool.sol";
import {CanonicalWETH9} from "../../src/mocks/CanonicalWETH9.sol";
import {MockETHUSDOracle} from "../../src/mocks/MockETHUSDOracle.sol";
import {MockUSDC} from "../helpers/MockUSDC.sol";

contract EveUSDPoolTest is Test {
    uint256 internal constant PRICE_WAD = 2_500e18;
    uint256 internal constant MAX_STALENESS = 1 hours;
    uint256 internal constant COLLATERAL_RATIO_BPS = 15_000;
    uint256 internal constant RECOVERY_TRIGGER_BPS = 8_000;
    uint256 internal constant RECOVERED_COLLATERAL_RATIO_BPS = 10_001;
    uint256 internal constant WETH_PROFILE = 1;
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
        assertEq(pool.eveUSD(), address(eveUSD));
        assertEq(pool.evRisk(), address(evRisk));
        IEveUSDPool.StableCollateralProfile memory profile = pool.collateralProfile(WETH_PROFILE);
        assertEq(profile.collateralToken, address(weth));
        assertEq(profile.oracle, address(oracle));
        assertEq(profile.activeSeriesId, SERIES_ONE);
        assertEq(profile.collateralRatioBps, COLLATERAL_RATIO_BPS);
        assertEq(profile.recoveryTriggerBps, RECOVERY_TRIGGER_BPS);
        assertEq(pool.recoveryTimelock(), 7 days);
        assertEq(eveUSD.pool(), address(pool));
        assertEq(evRisk.pool(), address(pool));

        IEveUSDPool.RiskSeries memory series = pool.riskSeries(SERIES_ONE);
        assertEq(uint8(series.status), uint8(IEveUSDPool.SeriesStatus.Active));
        assertEq(series.startPriceWad, PRICE_WAD);
        assertEq(series.collateralPerPairWad, ONE_PAIR_COLLATERAL);
        assertEq(series.collateralRatioBps, COLLATERAL_RATIO_BPS);
        assertEq(series.recoveryTriggerBps, RECOVERY_TRIGGER_BPS);
    }

    function test_DepositMintsEqualEveUSDAndCurrentSeriesShares() public {
        IEveUSDPool.DepositPreview memory preview = pool.previewDeposit(WETH_PROFILE, ONE_PAIR_COLLATERAL);
        assertEq(preview.seriesId, SERIES_ONE);
        assertEq(preview.eveUSDMinted, 1e18);
        assertEq(preview.sharesMinted, 1e18);
        assertEq(preview.collateralPerPairWad, ONE_PAIR_COLLATERAL);

        (uint256 seriesId, uint256 eveUSDMinted, uint256 sharesMinted) = _depositTo(alice, ONE_PAIR_COLLATERAL);

        assertEq(seriesId, SERIES_ONE);
        assertEq(eveUSDMinted, 1e18);
        assertEq(sharesMinted, 1e18);
        assertEq(pool.totalCollateral(address(weth)), ONE_PAIR_COLLATERAL);
        assertEq(weth.balanceOf(address(pool)), ONE_PAIR_COLLATERAL);
        assertEq(eveUSD.balanceOf(alice), 1e18);
        assertEq(evRisk.balanceOf(alice, SERIES_ONE), 1e18);

        IEveUSDPool.RiskSeries memory series = pool.riskSeries(SERIES_ONE);
        assertEq(series.seniorOutstanding, 1e18);
        assertEq(series.riskSharesOutstanding, 1e18);
        assertEq(series.accountedCollateral, ONE_PAIR_COLLATERAL);
    }

    function test_DirectWETHDonationDoesNotAffectAccountedCollateralOrMinting() public {
        _wrapAndApprove(bob, 1 ether, address(pool));
        vm.prank(bob);
        weth.transfer(address(pool), 1 ether);

        assertEq(weth.balanceOf(address(pool)), 1 ether);
        assertEq(pool.totalCollateral(address(weth)), 0);

        IEveUSDPool.DepositPreview memory preview = pool.previewDeposit(WETH_PROFILE, 1 ether);
        assertEq(preview.eveUSDMinted, ONE_ETH_MINT);
        assertEq(preview.sharesMinted, ONE_ETH_MINT);

        _depositTo(alice, 1 ether);
        assertEq(pool.totalCollateral(address(weth)), 1 ether);
        assertEq(weth.balanceOf(address(pool)), 2 ether);
    }

    function test_DepositPaysInsuranceWhenReserveBelowTarget() public {
        vm.prank(owner);
        pool.setCollateralProfileInsuranceBps(WETH_PROFILE, 1_000, 500);

        IEveUSDPool.DepositPreview memory preview = pool.previewDeposit(WETH_PROFILE, ONE_PAIR_COLLATERAL);
        assertGt(preview.insuranceContribution, 0);
        assertLt(preview.eveUSDMinted, 1e18);

        _depositTo(alice, ONE_PAIR_COLLATERAL);

        IEveUSDPool.StableCollateralProfile memory profile = pool.collateralProfile(WETH_PROFILE);
        IEveUSDPool.RiskSeries memory series = pool.riskSeries(SERIES_ONE);
        assertEq(profile.insuranceReserve, preview.insuranceContribution);
        assertEq(pool.insuranceReserve(WETH_PROFILE), preview.insuranceContribution);
        assertEq(pool.totalCollateral(address(weth)), ONE_PAIR_COLLATERAL);
        assertEq(series.accountedCollateral, ONE_PAIR_COLLATERAL - preview.insuranceContribution);
        assertEq(profile.accountedCollateral, series.accountedCollateral);
        assertEq(profile.seniorOutstanding, preview.eveUSDMinted);
        assertEq(pool.profileSeniorLiabilities(WETH_PROFILE), preview.eveUSDMinted);
    }

    function test_DepositInsuranceContributionSkipsWhenReserveMeetsTarget() public {
        vm.prank(owner);
        pool.setCollateralProfileInsuranceBps(WETH_PROFILE, 1_000, 500);
        _topUpInsurance(alice, 1 ether);

        IEveUSDPool.DepositPreview memory preview = pool.previewDeposit(WETH_PROFILE, ONE_PAIR_COLLATERAL);
        assertEq(preview.insuranceContribution, 0);

        _depositTo(alice, ONE_PAIR_COLLATERAL);

        assertEq(pool.insuranceReserve(WETH_PROFILE), 1 ether);
        assertEq(pool.totalCollateral(address(weth)), 1 ether + ONE_PAIR_COLLATERAL);
        assertEq(pool.riskSeries(SERIES_ONE).accountedCollateral, ONE_PAIR_COLLATERAL);
    }

    function test_RevertWhen_FinalizationInsuranceShortfallIsNotCovered() public {
        _depositTo(alice, ONE_PAIR_COLLATERAL);
        oracle.setPriceWad(1_000e18);

        pool.startRecovery(SERIES_ONE);
        vm.warp(block.timestamp + 7 days);
        oracle.setUpdatedAt(block.timestamp);

        vm.expectRevert(
            abi.encodeWithSelector(IEveUSDPool.InsuranceInsufficient.selector, WETH_PROFILE, 0.0004 ether, uint256(0))
        );
        pool.finalizeRecovery(SERIES_ONE);
    }

    function test_FinalizationDrawsInsuranceForSeniorShortfallAndWipesJunior() public {
        _depositTo(alice, ONE_PAIR_COLLATERAL);
        _topUpInsurance(bob, 0.0004 ether);
        oracle.setPriceWad(1_000e18);

        pool.startRecovery(SERIES_ONE);
        vm.prank(alice);
        pool.returnRiskShares(SERIES_ONE, 1e18);

        vm.warp(block.timestamp + 7 days);
        oracle.setUpdatedAt(block.timestamp);
        pool.finalizeRecovery(SERIES_ONE);

        IEveUSDPool.RiskSeries memory oldSeries = pool.riskSeries(SERIES_ONE);
        IEveUSDPool.RecoveredRiskClaimPreview memory preview =
            pool.previewRecoveredRiskClaim(alice, SERIES_ONE, IEveUSDPool.RecoveryClaimMode.MorePairs);

        assertEq(pool.insuranceReserve(WETH_PROFILE), 0);
        assertEq(oldSeries.accountedCollateral, 0.001 ether);
        assertEq(preview.seniorReserveCollateral, 0.001 ether);
        assertEq(preview.juniorResidualCollateral, 0);
        assertEq(preview.sharesMinted, 0);
        assertEq(preview.eveUSDMinted, 0);
    }

    function test_RevertWhen_DepositPriceBreachesRecoveryTriggerBeforeRecoveryStarts() public {
        _depositTo(alice, ONE_PAIR_COLLATERAL);
        oracle.setPriceWad(1_900e18);

        bytes memory expectedRevert =
            abi.encodeWithSelector(IEveUSDPool.RecoveryRequired.selector, WETH_PROFILE, SERIES_ONE, 1_900e18, 2_000e18);

        vm.expectRevert(expectedRevert);
        pool.previewDeposit(WETH_PROFILE, ONE_PAIR_COLLATERAL);

        _wrapAndApprove(bob, ONE_PAIR_COLLATERAL, address(pool));
        vm.prank(bob);
        vm.expectRevert(expectedRevert);
        pool.depositCollateral(WETH_PROFILE, ONE_PAIR_COLLATERAL, bob, bob);
    }

    function test_MultipleCollateralProfilesMintSameEveUSDWithSeriesLocalClaims() public {
        MockUSDC usdc = new MockUSDC();
        MockETHUSDOracle usdcOracle = new MockETHUSDOracle(1e18, MAX_STALENESS);

        vm.prank(owner);
        (uint256 profileId, uint256 seriesId) =
            pool.createCollateralProfile(address(usdc), address(usdcOracle), COLLATERAL_RATIO_BPS, 8_500, 0, 0, true);

        assertEq(profileId, 2);
        assertEq(seriesId, SERIES_TWO);
        IEveUSDPool.StableCollateralProfile memory profile = pool.collateralProfile(profileId);
        assertEq(profile.collateralToken, address(usdc));
        assertEq(profile.decimals, 6);
        assertEq(profile.activeSeriesId, SERIES_TWO);

        _depositTo(alice, ONE_PAIR_COLLATERAL);
        usdc.mint(bob, 1_500_000);
        vm.startPrank(bob);
        usdc.approve(address(pool), 1_500_000);
        (uint256 mintedSeriesId, uint256 eveUSDMinted, uint256 sharesMinted) =
            pool.depositCollateral(profileId, 1_500_000, bob, bob);
        vm.stopPrank();

        assertEq(mintedSeriesId, SERIES_TWO);
        assertEq(eveUSDMinted, 1e18);
        assertEq(sharesMinted, 1e18);
        assertEq(eveUSD.totalSupply(), 2e18);
        assertEq(evRisk.balanceOf(alice, SERIES_ONE), 1e18);
        assertEq(evRisk.balanceOf(bob, SERIES_TWO), 1e18);
        assertEq(pool.totalCollateral(address(weth)), ONE_PAIR_COLLATERAL);
        assertEq(pool.totalCollateral(address(usdc)), 1_500_000);

        vm.prank(bob);
        uint256 usdcOut = pool.recombine(SERIES_TWO, 1e18, 1e18, bob);

        assertEq(usdcOut, 1_500_000);
        assertEq(usdc.balanceOf(bob), 1_500_000);
        assertEq(pool.totalCollateral(address(usdc)), 0);
        assertEq(pool.totalCollateral(address(weth)), ONE_PAIR_COLLATERAL);
        assertEq(eveUSD.totalSupply(), 1e18);
        assertEq(evRisk.balanceOf(alice, SERIES_ONE), 1e18);
    }

    function test_ProfileRecoveryDoesNotPauseUnrelatedCollateralProfile() public {
        MockUSDC usdc = new MockUSDC();
        MockETHUSDOracle usdcOracle = new MockETHUSDOracle(1e18, MAX_STALENESS);

        vm.prank(owner);
        (uint256 usdcProfileId, uint256 usdcSeriesId) =
            pool.createCollateralProfile(address(usdc), address(usdcOracle), COLLATERAL_RATIO_BPS, 8_500, 0, 0, true);

        _depositTo(alice, ONE_PAIR_COLLATERAL);
        usdc.mint(bob, 3_000_000);
        vm.startPrank(bob);
        usdc.approve(address(pool), 3_000_000);
        pool.depositCollateral(usdcProfileId, 1_500_000, bob, bob);
        vm.stopPrank();

        vm.prank(owner);
        pool.setCollateralProfileConfig(WETH_PROFILE, RECOVERED_COLLATERAL_RATIO_BPS, RECOVERY_TRIGGER_BPS, true);
        oracle.setPriceWad(1_900e18);

        pool.startRecovery(SERIES_ONE);
        vm.warp(block.timestamp + 7 days);
        oracle.setUpdatedAt(block.timestamp);
        uint256 wethSuccessorSeriesId = pool.finalizeRecovery(SERIES_ONE);

        assertEq(wethSuccessorSeriesId, 3);
        assertEq(pool.collateralProfile(WETH_PROFILE).activeSeriesId, wethSuccessorSeriesId);
        assertEq(pool.collateralProfile(usdcProfileId).activeSeriesId, usdcSeriesId);
        assertEq(uint8(pool.riskSeries(usdcSeriesId).status), uint8(IEveUSDPool.SeriesStatus.Active));

        usdcOracle.setUpdatedAt(block.timestamp);
        IEveUSDPool.DepositPreview memory preview = pool.previewDeposit(usdcProfileId, 1_500_000);
        assertEq(preview.seriesId, usdcSeriesId);

        vm.startPrank(bob);
        pool.depositCollateral(usdcProfileId, 1_500_000, bob, bob);
        vm.stopPrank();

        assertEq(pool.totalCollateral(address(usdc)), 3_000_000);
        assertEq(evRisk.balanceOf(bob, usdcSeriesId), 2e18);
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
        assertEq(pool.totalCollateral(address(weth)), 0);
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

    function test_RecoveryFinalizationAllowsReducedJuniorClaim() public {
        _depositTo(alice, ONE_PAIR_COLLATERAL);
        oracle.setPriceWad(1_900e18);

        pool.startRecovery(SERIES_ONE);
        vm.prank(alice);
        pool.returnRiskShares(SERIES_ONE, 1e18);

        vm.warp(block.timestamp + 7 days);
        oracle.setUpdatedAt(block.timestamp);
        pool.finalizeRecovery(SERIES_ONE);

        IEveUSDPool.RecoveredRiskClaimPreview memory preview =
            pool.previewRecoveredRiskClaim(alice, SERIES_ONE, IEveUSDPool.RecoveryClaimMode.CollateralDifference);

        assertEq(preview.seniorReserveCollateral, 526_315_789_473_685);
        assertEq(preview.juniorResidualCollateral, 73_684_210_526_315);
        assertLt(preview.sharesMinted, 1e18);
        assertEq(preview.eveUSDMinted, preview.sharesMinted);
        assertEq(preview.collateralOut, 0);
    }

    function test_RecoveryClaimWithCollateralDifferenceMintsReducedClaimWhenJuniorImpaired() public {
        _depositTo(alice, ONE_PAIR_COLLATERAL * 2);
        vm.prank(owner);
        pool.setCollateralProfileConfig(WETH_PROFILE, RECOVERED_COLLATERAL_RATIO_BPS, RECOVERY_TRIGGER_BPS, true);
        oracle.setPriceWad(1_900e18);

        pool.startRecovery(SERIES_ONE);

        vm.prank(alice);
        pool.returnRiskShares(SERIES_ONE, 0.5e18);

        vm.expectRevert(abi.encodeWithSelector(IEveUSDPool.SeriesNotActive.selector, SERIES_ONE));
        pool.previewDeposit(WETH_PROFILE, ONE_PAIR_COLLATERAL);

        vm.warp(block.timestamp + 7 days);
        oracle.setUpdatedAt(block.timestamp);
        uint256 newSeriesId = pool.finalizeRecovery(SERIES_ONE);

        assertEq(newSeriesId, SERIES_TWO);
        assertEq(pool.collateralProfile(WETH_PROFILE).activeSeriesId, SERIES_TWO);
        assertEq(uint8(pool.riskSeries(SERIES_ONE).status), uint8(IEveUSDPool.SeriesStatus.OperatorRecoverable));
        assertEq(uint8(pool.riskSeries(SERIES_TWO).status), uint8(IEveUSDPool.SeriesStatus.Active));
        assertEq(pool.riskSeries(SERIES_TWO).startPriceWad, 1_900e18);

        IEveUSDPool.RecoveredRiskClaimPreview memory preview =
            pool.previewRecoveredRiskClaim(alice, SERIES_ONE, IEveUSDPool.RecoveryClaimMode.CollateralDifference);
        assertEq(preview.returnedShares, 0.5e18);
        assertLt(preview.sharesMinted, 0.5e18);
        assertEq(preview.eveUSDMinted, preview.sharesMinted);
        assertEq(preview.collateralOut, 0);
        assertEq(preview.collateralMoved, preview.juniorResidualCollateral);

        vm.prank(alice);
        (uint256 sharesMinted, uint256 eveUSDMinted, uint256 wethOut) =
            pool.claimRecoveredRiskShares(SERIES_ONE, alice, IEveUSDPool.RecoveryClaimMode.CollateralDifference);

        assertEq(sharesMinted, preview.sharesMinted);
        assertEq(eveUSDMinted, preview.eveUSDMinted);
        assertEq(wethOut, preview.collateralOut);
        assertEq(evRisk.balanceOf(alice, SERIES_TWO), preview.sharesMinted);
        assertEq(weth.balanceOf(alice), preview.collateralOut);
        assertEq(pool.returnedShares(SERIES_ONE, alice), 0);
        assertEq(pool.riskSeries(SERIES_ONE).returnedSharesSupply, 0);
        assertEq(pool.riskSeries(SERIES_TWO).riskSharesOutstanding, preview.sharesMinted);
        assertEq(pool.riskSeries(SERIES_TWO).seniorOutstanding, preview.eveUSDMinted);
    }

    function test_RecoveryClaimWithCollateralDifferenceRoundsBaseCollateralUp() public {
        _depositTo(alice, ONE_PAIR_COLLATERAL);
        vm.prank(owner);
        pool.setCollateralProfileConfig(WETH_PROFILE, RECOVERED_COLLATERAL_RATIO_BPS, RECOVERY_TRIGGER_BPS, true);
        oracle.setPriceWad(1_900e18);

        pool.startRecovery(SERIES_ONE);

        vm.prank(alice);
        pool.returnRiskShares(SERIES_ONE, 10_000);

        vm.warp(block.timestamp + 7 days);
        oracle.setUpdatedAt(block.timestamp);
        pool.finalizeRecovery(SERIES_ONE);

        IEveUSDPool.RecoveredRiskClaimPreview memory preview =
            pool.previewRecoveredRiskClaim(alice, SERIES_ONE, IEveUSDPool.RecoveryClaimMode.CollateralDifference);

        assertEq(preview.oldClaimCollateral, 6);
        assertEq(preview.juniorResidualCollateral, 0);
        assertEq(preview.sharesMinted, 0);
        assertEq(preview.collateralOut, 0);

        vm.prank(alice);
        pool.claimRecoveredRiskShares(SERIES_ONE, alice, IEveUSDPool.RecoveryClaimMode.CollateralDifference);

        assertEq(pool.riskSeries(SERIES_TWO).accountedCollateral, 0);
        assertEq(evRisk.balanceOf(alice, SERIES_TWO), 0);
    }

    function test_RecoveryClaimWithMorePairsMintsReducedCleanPairWhenJuniorImpaired() public {
        _depositTo(alice, ONE_PAIR_COLLATERAL);
        vm.prank(owner);
        pool.setCollateralProfileConfig(WETH_PROFILE, RECOVERED_COLLATERAL_RATIO_BPS, RECOVERY_TRIGGER_BPS, true);
        oracle.setPriceWad(1_900e18);

        pool.startRecovery(SERIES_ONE);

        vm.prank(alice);
        pool.returnRiskShares(SERIES_ONE, 1e18);

        vm.warp(block.timestamp + 7 days);
        oracle.setUpdatedAt(block.timestamp);
        pool.finalizeRecovery(SERIES_ONE);

        IEveUSDPool.RecoveredRiskClaimPreview memory preview =
            pool.previewRecoveredRiskClaim(alice, SERIES_ONE, IEveUSDPool.RecoveryClaimMode.MorePairs);
        assertLt(preview.sharesMinted, 1e18);
        assertEq(preview.eveUSDMinted, preview.sharesMinted);
        assertEq(preview.collateralOut, 0);

        vm.prank(alice);
        (uint256 sharesMinted, uint256 eveUSDMinted, uint256 wethOut) =
            pool.claimRecoveredRiskShares(SERIES_ONE, alice, IEveUSDPool.RecoveryClaimMode.MorePairs);

        assertEq(sharesMinted, preview.sharesMinted);
        assertEq(eveUSDMinted, preview.eveUSDMinted);
        assertEq(wethOut, 0);
        assertEq(eveUSD.balanceOf(alice), 1e18 + preview.eveUSDMinted);
        assertEq(eveUSD.totalSupply(), 1e18 + preview.eveUSDMinted);
        assertEq(evRisk.balanceOf(alice, SERIES_TWO), preview.sharesMinted);
        assertEq(pool.riskSeries(SERIES_TWO).riskSharesOutstanding, preview.sharesMinted);
        assertEq(pool.riskSeries(SERIES_TWO).seniorOutstanding, preview.sharesMinted);
    }

    function test_OperatorRecoveryBurnsExpiredRiskAndMintsNewSeriesClaim() public {
        _depositTo(alice, ONE_PAIR_COLLATERAL * 2);
        uint256 poolWethBefore = weth.balanceOf(address(pool));
        vm.prank(owner);
        pool.setCollateralProfileConfig(WETH_PROFILE, RECOVERED_COLLATERAL_RATIO_BPS, RECOVERY_TRIGGER_BPS, true);
        oracle.setPriceWad(1_900e18);

        pool.startRecovery(SERIES_ONE);
        vm.warp(block.timestamp + 7 days);
        oracle.setUpdatedAt(block.timestamp);
        pool.finalizeRecovery(SERIES_ONE);

        IEveUSDPool.OperatorRecoveryPreview memory preview = pool.previewOperatorRecovery(alice, SERIES_ONE, 0.5e18);
        assertEq(preview.newSeriesId, SERIES_TWO);
        assertEq(preview.sharesBurned, 0.5e18);
        assertLt(preview.sharesMinted, 0.5e18);
        assertEq(preview.eveUSDMinted, preview.sharesMinted);
        assertLt(preview.collateralMoved, ONE_PAIR_COLLATERAL / 2);

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
        assertEq(pool.riskSeries(SERIES_ONE).seniorOutstanding, 2e18);
        assertEq(pool.riskSeries(SERIES_TWO).seniorOutstanding, preview.sharesMinted);
    }

    function test_NewDepositsUseActiveSeriesAfterRecovery() public {
        _depositTo(alice, ONE_PAIR_COLLATERAL);
        vm.prank(owner);
        pool.setCollateralProfileConfig(WETH_PROFILE, RECOVERED_COLLATERAL_RATIO_BPS, RECOVERY_TRIGGER_BPS, true);
        oracle.setPriceWad(1_900e18);

        pool.startRecovery(SERIES_ONE);
        vm.warp(block.timestamp + 7 days);
        oracle.setUpdatedAt(block.timestamp);
        pool.finalizeRecovery(SERIES_ONE);

        IEveUSDPool.DepositPreview memory preview = pool.previewDeposit(WETH_PROFILE, ONE_PAIR_COLLATERAL);
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
        return pool.depositCollateral(WETH_PROFILE, amount, account, account);
    }

    function _wrapAndApprove(address account, uint256 amount, address spender) internal {
        vm.prank(account);
        weth.deposit{value: amount}();

        vm.prank(account);
        weth.approve(spender, amount);
    }

    function _topUpInsurance(address account, uint256 amount) internal {
        _wrapAndApprove(account, amount, address(pool));

        vm.prank(account);
        pool.topUpInsurance(WETH_PROFILE, amount);
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
