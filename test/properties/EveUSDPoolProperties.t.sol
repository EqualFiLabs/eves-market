// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {EveRiskShares} from "../../src/EveRiskShares.sol";
import {EveUSD} from "../../src/EveUSD.sol";
import {EveUSDPool} from "../../src/EveUSDPool.sol";
import {IETHUSDOracle} from "../../src/interfaces/IETHUSDOracle.sol";
import {IUsdOracle} from "../../src/interfaces/IUsdOracle.sol";
import {IEveUSDPool} from "../../src/interfaces/IEveUSDPool.sol";
import {CanonicalWETH9} from "../../src/mocks/CanonicalWETH9.sol";
import {MockETHUSDOracle} from "../../src/mocks/MockETHUSDOracle.sol";

contract EveUSDPoolPropertiesTest is Test {
    uint256 internal constant PRICE_WAD = 2_500e18;
    uint256 internal constant MAX_STALENESS = 1 hours;
    uint256 internal constant COLLATERAL_RATIO_BPS = 15_000;
    uint256 internal constant RECOVERY_TRIGGER_BPS = 8_000;
    uint256 internal constant RECOVERED_COLLATERAL_RATIO_BPS = 10_001;
    uint256 internal constant WETH_PROFILE = 1;
    uint256 internal constant SERIES_ONE = 1;
    uint256 internal constant SERIES_TWO = 2;
    uint256 internal constant ONE_PAIR_COLLATERAL = 0.0006 ether;

    CanonicalWETH9 internal weth;
    EveUSD internal eveUSD;
    EveRiskShares internal evRisk;
    MockETHUSDOracle internal oracle;
    EveUSDPool internal pool;

    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal operator = makeAddr("operator");

    function setUp() public {
        vm.warp(1_700_000_000);
        weth = new CanonicalWETH9();
        oracle = new MockETHUSDOracle(PRICE_WAD, MAX_STALENESS);
        (eveUSD, evRisk, pool) = _deployPool(COLLATERAL_RATIO_BPS, RECOVERY_TRIGGER_BPS);
    }

    function testFuzz_DepositMintsEqualPairedClaimsAndBackedSupply(uint96 amountSeed, uint96 priceSeed) public {
        uint256 amount = bound(uint256(amountSeed), ONE_PAIR_COLLATERAL, 1_000 ether);
        uint256 price = bound(uint256(priceSeed), 2_001e18, 5_000e18);
        oracle.setPriceWad(price);

        IEveUSDPool.DepositPreview memory preview = pool.previewDeposit(WETH_PROFILE, amount);
        (uint256 seriesId, uint256 eveUSDMinted, uint256 sharesMinted) = _depositTo(alice, amount);

        assertEq(seriesId, SERIES_ONE);
        assertEq(eveUSDMinted, preview.eveUSDMinted);
        assertEq(sharesMinted, preview.sharesMinted);
        assertEq(eveUSDMinted, sharesMinted);
        assertEq(pool.totalCollateral(address(weth)), amount);
        assertEq(eveUSD.totalSupply(), eveUSDMinted);
        assertEq(evRisk.balanceOf(alice, SERIES_ONE), sharesMinted);

        IEveUSDPool.RiskSeries memory series = pool.riskSeries(SERIES_ONE);
        assertEq(series.seniorOutstanding, eveUSDMinted);
        assertEq(series.riskSharesOutstanding, sharesMinted);
        assertEq(series.accountedCollateral, amount);
        assertEq(series.seniorOutstanding, eveUSD.totalSupply());
    }

    function test_PriceDropDoesNotCreateOneSidedRedemptionPath() public {
        _depositTo(alice, ONE_PAIR_COLLATERAL);
        oracle.setPriceWad(1_900e18);

        pool.startRecovery(SERIES_ONE);

        vm.prank(alice);
        uint256 wethOut = pool.recombine(SERIES_ONE, 1e18, 1e18, alice);

        assertEq(wethOut, ONE_PAIR_COLLATERAL);
        assertEq(eveUSD.totalSupply(), 0);
        assertEq(evRisk.balanceOf(alice, SERIES_ONE), 0);
        assertEq(pool.totalCollateral(address(weth)), 0);
    }

    function testFuzz_RecombinationIsDeterministicAndPreservesAccounting(uint96 pairSeed) public {
        _depositTo(alice, ONE_PAIR_COLLATERAL * 10);
        IEveUSDPool.RiskSeries memory beforeSeries = pool.riskSeries(SERIES_ONE);
        uint256 eveUSDAmount = bound(uint256(pairSeed), 1e18, beforeSeries.seniorOutstanding);

        IEveUSDPool.RedemptionPreview memory preview = pool.previewRecombine(SERIES_ONE, eveUSDAmount);
        uint256 requiredShares = pool.requiredSharesForRecombine(SERIES_ONE, eveUSDAmount);

        vm.prank(alice);
        uint256 wethOut = pool.recombine(SERIES_ONE, eveUSDAmount, requiredShares, alice);

        assertEq(requiredShares, preview.sharesBurned);
        assertEq(wethOut, preview.collateralOut);
        assertEq(eveUSD.totalSupply(), beforeSeries.seniorOutstanding - eveUSDAmount);
        assertEq(evRisk.balanceOf(alice, SERIES_ONE), beforeSeries.riskSharesOutstanding - requiredShares);
        assertEq(pool.totalCollateral(address(weth)), beforeSeries.accountedCollateral - wethOut);

        IEveUSDPool.RiskSeries memory afterSeries = pool.riskSeries(SERIES_ONE);
        assertEq(afterSeries.seniorOutstanding, eveUSD.totalSupply());
        assertEq(afterSeries.riskSharesOutstanding, evRisk.balanceOf(alice, SERIES_ONE));
    }

    function test_OracleFailureModesRevertPoolPreviewsAndRecoveryChecks() public {
        _depositTo(alice, ONE_PAIR_COLLATERAL);

        oracle.setStalePrice(true);
        bytes memory stalePrice =
            abi.encodeWithSelector(IUsdOracle.StalePrice.selector, uint256(1_700_000_000), uint256(MAX_STALENESS));

        vm.expectRevert(stalePrice);
        pool.previewDeposit(WETH_PROFILE, ONE_PAIR_COLLATERAL);

        vm.expectRevert(stalePrice);
        pool.previewRecombine(SERIES_ONE, 1e18);

        vm.expectRevert(stalePrice);
        pool.startRecovery(SERIES_ONE);

        oracle.setStalePrice(false);
        oracle.setInvalidPrice(true);

        vm.expectRevert(IUsdOracle.InvalidPrice.selector);
        pool.previewDeposit(WETH_PROFILE, ONE_PAIR_COLLATERAL);
    }

    function test_DirectDonationDoesNotChangeAccountedCollateral() public {
        _depositTo(alice, ONE_PAIR_COLLATERAL);
        uint256 accountedBefore = pool.totalCollateral(address(weth));

        _wrapAndApprove(bob, 1 ether, address(pool));
        vm.prank(bob);
        weth.transfer(address(pool), 1 ether);

        assertEq(pool.totalCollateral(address(weth)), accountedBefore);
        assertEq(weth.balanceOf(address(pool)), accountedBefore + 1 ether);
    }

    function test_RecoveryMovesVoluntaryAndExpiredClaimsThroughSelectedModes() public {
        _depositTo(alice, ONE_PAIR_COLLATERAL * 4);
        uint256 totalSupplyBefore = eveUSD.totalSupply();
        uint256 poolWethBefore = weth.balanceOf(address(pool));
        vm.prank(owner);
        pool.setCollateralProfileConfig(WETH_PROFILE, RECOVERED_COLLATERAL_RATIO_BPS, RECOVERY_TRIGGER_BPS, true);
        oracle.setPriceWad(1_900e18);

        pool.startRecovery(SERIES_ONE);

        vm.prank(alice);
        pool.returnRiskShares(SERIES_ONE, 1e18);

        vm.warp(block.timestamp + 7 days);
        oracle.setUpdatedAt(block.timestamp);
        pool.finalizeRecovery(SERIES_ONE);

        IEveUSDPool.RecoveredRiskClaimPreview memory voluntaryPreview =
            pool.previewRecoveredRiskClaim(alice, SERIES_ONE, IEveUSDPool.RecoveryClaimMode.CollateralDifference);
        vm.prank(alice);
        pool.claimRecoveredRiskShares(SERIES_ONE, alice, IEveUSDPool.RecoveryClaimMode.CollateralDifference);

        vm.prank(operator);
        (, uint256 operatorSharesMinted, uint256 operatorEveUSDMinted) =
            pool.recoverExpiredRisk(alice, SERIES_ONE, 1e18);

        assertEq(eveUSD.totalSupply(), totalSupplyBefore + voluntaryPreview.eveUSDMinted + operatorEveUSDMinted);
        assertEq(weth.balanceOf(address(pool)), poolWethBefore - voluntaryPreview.collateralOut);
        assertEq(weth.balanceOf(alice), voluntaryPreview.collateralOut);
        assertEq(weth.balanceOf(operator), 0);
        assertEq(evRisk.balanceOf(alice, SERIES_TWO), voluntaryPreview.sharesMinted);
        assertEq(evRisk.balanceOf(operator, SERIES_TWO), operatorSharesMinted);

        IEveUSDPool.RiskSeries memory oldSeries = pool.riskSeries(SERIES_ONE);
        IEveUSDPool.RiskSeries memory newSeries = pool.riskSeries(SERIES_TWO);
        assertEq(oldSeries.seniorOutstanding + newSeries.seniorOutstanding, eveUSD.totalSupply());
        assertEq(oldSeries.accountedCollateral + newSeries.accountedCollateral, pool.totalCollateral(address(weth)));
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
        vm.deal(account, amount);

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
