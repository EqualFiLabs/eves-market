// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {EveRiskShares} from "../../src/EveRiskShares.sol";
import {EveUSD} from "../../src/EveUSD.sol";
import {EveUSDPool} from "../../src/EveUSDPool.sol";
import {EveUSDRouter} from "../../src/EveUSDRouter.sol";
import {IEveUSDPool} from "../../src/interfaces/IEveUSDPool.sol";
import {IEveUSDRouter} from "../../src/interfaces/IEveUSDRouter.sol";
import {CanonicalWETH9} from "../../src/mocks/CanonicalWETH9.sol";
import {MockETHUSDOracle} from "../../src/mocks/MockETHUSDOracle.sol";

contract EveUSDRouterTest is Test {
    uint256 internal constant PRICE_WAD = 2_500e18;
    uint256 internal constant MAX_STALENESS = 1 hours;
    uint256 internal constant COLLATERAL_RATIO_BPS = 15_000;
    uint256 internal constant RECOVERY_TRIGGER_BPS = 8_000;
    uint256 internal constant WETH_PROFILE = 1;
    uint256 internal constant SERIES_ONE = 1;
    uint256 internal constant ONE_PAIR_COLLATERAL = 0.0006 ether;
    uint256 internal constant ONE_ETH_MINT = 1_666_666_666_666_666_666_666;

    CanonicalWETH9 internal weth;
    EveUSD internal eveUSD;
    EveRiskShares internal evRisk;
    MockETHUSDOracle internal oracle;
    EveUSDPool internal pool;
    EveUSDRouter internal router;

    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    address internal eveUSDReceiver = makeAddr("eveUSDReceiver");
    address internal shareReceiver = makeAddr("shareReceiver");
    address internal receiver = makeAddr("receiver");

    function setUp() public {
        vm.warp(1_700_000_000);
        weth = new CanonicalWETH9();
        oracle = new MockETHUSDOracle(PRICE_WAD, MAX_STALENESS);
        (eveUSD, evRisk, pool) = _deployPool(COLLATERAL_RATIO_BPS, RECOVERY_TRIGGER_BPS);
        router = new EveUSDRouter(address(pool), address(weth), address(eveUSD), address(evRisk), WETH_PROFILE);
        vm.deal(alice, 10 ether);
    }

    function test_ConstructorStoresImmutableWiring() public view {
        assertEq(router.pool(), address(pool));
        assertEq(router.weth(), address(weth));
        assertEq(router.eveUSD(), address(eveUSD));
        assertEq(router.evRisk(), address(evRisk));
        assertEq(router.wethProfileId(), WETH_PROFILE);
    }

    function test_DepositETHWrapsAndMintsCurrentSeriesSharesToReceivers() public {
        IEveUSDPool.DepositPreview memory preview = pool.previewDeposit(WETH_PROFILE, 1 ether);

        vm.prank(alice);
        (uint256 seriesId, uint256 eveUSDMinted, uint256 sharesMinted) =
            router.depositETH{value: 1 ether}(eveUSDReceiver, shareReceiver, preview.eveUSDMinted, preview.sharesMinted);

        assertEq(seriesId, SERIES_ONE);
        assertEq(eveUSDMinted, preview.eveUSDMinted);
        assertEq(sharesMinted, preview.sharesMinted);
        assertEq(weth.balanceOf(address(router)), 0);
        assertEq(eveUSD.balanceOf(address(router)), 0);
        assertEq(evRisk.balanceOf(address(router), SERIES_ONE), 0);
        assertEq(weth.balanceOf(address(pool)), 1 ether);
        assertEq(eveUSD.balanceOf(eveUSDReceiver), ONE_ETH_MINT);
        assertEq(evRisk.balanceOf(shareReceiver, SERIES_ONE), ONE_ETH_MINT);
    }

    function test_DepositWETHPullsCollateralAndMintsToReceivers() public {
        IEveUSDPool.DepositPreview memory preview = pool.previewDeposit(WETH_PROFILE, 2 ether);
        _wrapAndApprove(alice, 2 ether, address(router));

        vm.prank(alice);
        (uint256 seriesId, uint256 eveUSDMinted, uint256 sharesMinted) =
            router.depositWETH(2 ether, eveUSDReceiver, shareReceiver, preview.eveUSDMinted, preview.sharesMinted);

        assertEq(seriesId, SERIES_ONE);
        assertEq(eveUSDMinted, preview.eveUSDMinted);
        assertEq(sharesMinted, preview.sharesMinted);
        assertEq(weth.balanceOf(address(router)), 0);
        assertEq(weth.allowance(address(router), address(pool)), 0);
        assertEq(eveUSD.balanceOf(eveUSDReceiver), preview.eveUSDMinted);
        assertEq(evRisk.balanceOf(shareReceiver, SERIES_ONE), preview.sharesMinted);
    }

    function test_RecombineToWETHBurnsClaimsAndTransfersWETH() public {
        _depositToAliceThroughRouter(1 ether);
        _approveClaims(alice, 1e18);

        vm.prank(alice);
        uint256 wethOut = router.recombineToWETH(SERIES_ONE, 1e18, 1e18, receiver, ONE_PAIR_COLLATERAL);

        assertEq(wethOut, ONE_PAIR_COLLATERAL);
        assertEq(weth.balanceOf(receiver), ONE_PAIR_COLLATERAL);
        assertEq(weth.balanceOf(address(router)), 0);
        assertEq(eveUSD.balanceOf(address(router)), 0);
        assertEq(evRisk.balanceOf(address(router), SERIES_ONE), 0);
        assertEq(eveUSD.balanceOf(alice), ONE_ETH_MINT - 1e18);
        assertEq(evRisk.balanceOf(alice, SERIES_ONE), ONE_ETH_MINT - 1e18);
    }

    function test_RecombineToETHBurnsClaimsUnwrapsAndTransfersETH() public {
        _depositToAliceThroughRouter(1 ether);
        _approveClaims(alice, 1e18);

        vm.prank(alice);
        uint256 ethOut = router.recombineToETH(SERIES_ONE, 1e18, 1e18, receiver, ONE_PAIR_COLLATERAL);

        assertEq(ethOut, ONE_PAIR_COLLATERAL);
        assertEq(receiver.balance, ONE_PAIR_COLLATERAL);
        assertEq(address(router).balance, 0);
        assertEq(weth.balanceOf(address(pool)), 1 ether - ONE_PAIR_COLLATERAL);
        assertEq(pool.seniorLiabilities(), ONE_ETH_MINT - 1e18);
    }

    function test_RevertWhen_DepositMinimumOutputIsMissed() public {
        IEveUSDPool.DepositPreview memory preview = pool.previewDeposit(WETH_PROFILE, 1 ether);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IEveUSDRouter.OutputBelowMinimum.selector, preview.eveUSDMinted, preview.eveUSDMinted + 1
            )
        );
        router.depositETH{value: 1 ether}(alice, alice, preview.eveUSDMinted + 1, 0);
    }

    function test_RevertWhen_RecombineRequiresTooManyShares() public {
        _depositToAliceThroughRouter(1 ether);
        _approveClaims(alice, 1e18);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IEveUSDRouter.SharesAboveMaximum.selector, 1e18, 1e18 - 1));
        router.recombineToETH(SERIES_ONE, 1e18, 1e18 - 1, receiver, 0);
    }

    function test_ResidualDustDoesNotGriefRouterFlows() public {
        vm.deal(address(router), 1);
        weth.deposit{value: 1}();
        weth.transfer(address(router), 1);

        vm.prank(alice);
        router.depositETH{value: 1 ether}(alice, alice, 0, 0);

        assertEq(address(router).balance, 1);
        assertEq(weth.balanceOf(address(router)), 1);
        assertEq(eveUSD.balanceOf(alice), ONE_ETH_MINT);
        assertEq(evRisk.balanceOf(alice, SERIES_ONE), ONE_ETH_MINT);
    }

    function test_RevertWhen_UnexpectedETHIsSentDirectly() public {
        (bool ok, bytes memory data) = address(router).call{value: 1}("");

        assertFalse(ok);
        assertEq(bytes4(data), IEveUSDRouter.UnexpectedETH.selector);
    }

    function _depositToAliceThroughRouter(uint256 amount) internal {
        vm.prank(alice);
        router.depositETH{value: amount}(alice, alice, 0, 0);
    }

    function _approveClaims(address account, uint256 eveUSDAmount) internal {
        vm.startPrank(account);
        eveUSD.approve(address(router), eveUSDAmount);
        evRisk.setApprovalForAll(address(router), true);
        vm.stopPrank();
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
