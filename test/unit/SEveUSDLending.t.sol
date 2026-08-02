// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {EveRiskShares} from "../../src/EveRiskShares.sol";
import {EveUSD} from "../../src/EveUSD.sol";
import {EveUSDPool} from "../../src/EveUSDPool.sol";
import {SEveUSDLending} from "../../src/SEveUSDLending.sol";
import {SEveUSDVault} from "../../src/SEveUSDVault.sol";
import {ISEveUSDCLending} from "../../src/interfaces/ISEveUSDCLending.sol";
import {CanonicalWETH9} from "../../src/mocks/CanonicalWETH9.sol";
import {MockETHUSDOracle} from "../../src/mocks/MockETHUSDOracle.sol";

contract SEveUSDLendingTest is Test {
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
    SEveUSDLending internal lending;

    address internal owner = makeAddr("owner");
    address internal feeRecipient = makeAddr("feeRecipient");
    address internal revenueNotifier = makeAddr("revenueNotifier");
    address internal alice = makeAddr("alice");
    address internal receiver = makeAddr("receiver");

    function setUp() public {
        vm.warp(1_700_000_000);
        weth = new CanonicalWETH9();
        oracle = new MockETHUSDOracle(PRICE_WAD, MAX_STALENESS);
        (eveUSD, evRisk, pool) = _deployPool();
        vault = new SEveUSDVault(address(eveUSD), owner, feeRecipient, 0, revenueNotifier);
        lending = new SEveUSDLending(address(vault), address(eveUSD), owner);

        vm.startPrank(owner);
        vault.setLendingContract(address(lending));
        lending.setLendingConfig(9_500, 100, 50, 1 days, 400 days, 1 days);
        vm.stopPrank();

        vm.deal(alice, 10 ether);
    }

    function test_BorrowAndRepayAgainstSEveUSDShares() public {
        _mintEveUSD(alice, 2 ether);

        vm.startPrank(alice);
        eveUSD.approve(address(vault), type(uint256).max);
        uint256 shares = vault.deposit(1_000e18, alice);
        vault.approve(address(lending), shares);
        uint256 loanId = lending.borrow(shares, 10 days, 400e18, receiver);
        vm.stopPrank();

        ISEveUSDCLending.Loan memory loan = lending.loanState(loanId);
        assertEq(loan.borrower, alice);
        assertEq(loan.collateralShares, shares);
        assertEq(eveUSD.balanceOf(receiver), 396e18);
        assertEq(vault.balanceOf(address(lending)), shares);
        assertEq(lending.outstandingPrincipal(), 400e18);
        assertEq(vault.outstandingPrincipal(), 400e18);

        vm.startPrank(alice);
        eveUSD.approve(address(lending), 400e18);
        lending.repay(loanId, false, alice);
        vm.stopPrank();

        assertEq(vault.balanceOf(alice), shares);
        assertEq(vault.balanceOf(address(lending)), 0);
        assertEq(lending.outstandingPrincipal(), 0);
        assertEq(vault.outstandingPrincipal(), 0);
    }

    function test_RepayCanRedeemCollateralToUnderlyingEveUSD() public {
        _mintEveUSD(alice, 2 ether);

        vm.startPrank(alice);
        eveUSD.approve(address(vault), type(uint256).max);
        uint256 shares = vault.deposit(1_000e18, alice);
        vault.approve(address(lending), shares);
        uint256 loanId = lending.borrow(shares, 10 days, 400e18, receiver);
        eveUSD.approve(address(lending), 400e18);
        lending.repay(loanId, true, alice);
        vm.stopPrank();

        assertEq(vault.balanceOf(address(lending)), 0);
        assertEq(vault.balanceOf(alice), 0);
        assertGt(eveUSD.balanceOf(alice), 0);
    }

    function test_DefaultRecoverySettlesVaultAccounting() public {
        _mintEveUSD(alice, 2 ether);

        vm.startPrank(alice);
        eveUSD.approve(address(vault), type(uint256).max);
        uint256 shares = vault.deposit(1_000e18, alice);
        vault.approve(address(lending), shares);
        uint256 loanId = lending.borrow(shares, 10 days, 400e18, receiver);
        vm.stopPrank();

        vm.warp(block.timestamp + 11 days + 1);
        lending.recoverDefaultedLoan(loanId);

        assertEq(vault.balanceOf(address(lending)), 0);
        assertEq(lending.outstandingPrincipal(), 0);
        assertEq(vault.outstandingPrincipal(), 0);
        assertTrue(lending.loanState(loanId).defaultResolved);
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
