// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "../../lib/forge-std/src/Test.sol";

import {SeniorCapitalFacet} from "../../src/facets/SeniorCapitalFacet.sol";
import {SeniorCapitalViewFacet} from "../../src/facets/SeniorCapitalViewFacet.sol";
import {ISeniorCapitalFacet} from "../../src/interfaces/ISeniorCapitalFacet.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {LibSeniorCapital} from "../../src/libraries/LibSeniorCapital.sol";
import {MockEveToken} from "../helpers/MockEveToken.sol";
import {MockUSDG} from "../../src/mocks/MockUSDG.sol";

contract SeniorCapitalHarness is SeniorCapitalFacet, SeniorCapitalViewFacet {
    function setMarginAsset(address asset) external {
        LibEveMarket.store().marginAsset = asset;
    }

    function reserve(bytes32 bucketId, uint256 assets) external {
        LibSeniorCapital.reserveCapital(LibSeniorCapital.s(), bucketId, assets);
    }

    function release(bytes32 bucketId, uint256 assets) external {
        LibSeniorCapital.releaseReservedCapital(LibSeniorCapital.s(), bucketId, assets);
    }

    function deploy(bytes32 bucketId, uint256 assets) external {
        LibSeniorCapital.deployReservedCapital(LibSeniorCapital.s(), bucketId, assets);
    }

    function repay(bytes32 bucketId, uint256 assets) external {
        LibSeniorCapital.repayActiveExposure(LibSeniorCapital.s(), bucketId, assets);
    }

    function recordLoss(bytes32 bucketId, uint256 assets) external {
        LibSeniorCapital.recordRealizedLoss(LibSeniorCapital.s(), bucketId, assets);
    }
}

contract SeniorCapitalFacetTest is Test {
    SeniorCapitalHarness internal senior;
    MockEveToken internal asset;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal donor = makeAddr("donor");
    bytes32 internal bucketId = keccak256("senior-bucket");

    function setUp() public {
        asset = new MockEveToken();
        senior = new SeniorCapitalHarness();
        senior.setMarginAsset(address(asset));
    }

    function test_DepositStaysPendingUntilActivationGate() public {
        _deposit(alice, 100e18);

        ISeniorCapitalFacet.SeniorCapitalAccount memory account = senior.seniorCapitalAccount(alice);
        assertEq(account.pendingPrincipal, 100e18);
        assertEq(account.effectivePrincipal, 0);
        assertEq(senior.seniorCapitalState().availableCapital, 0);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISeniorCapitalFacet.SeniorCapitalActivationPending.selector, block.timestamp + 15 minutes
            )
        );
        senior.activateSeniorCapital();

        vm.warp(block.timestamp + 15 minutes);
        vm.prank(alice);
        (uint256 principal, uint256 stored) = senior.activateSeniorCapital();

        assertEq(principal, 100e18);
        assertEq(stored, 100e18);
        assertEq(senior.seniorCapitalState().availableCapital, 100e18);
    }

    function test_WeightedPendingAgeDoesNotResetEarlierCapital() public {
        _deposit(alice, 100e18);
        vm.warp(block.timestamp + 10 minutes);
        uint256 secondDepositAt = block.timestamp;
        _deposit(alice, 100e18);

        ISeniorCapitalFacet.SeniorCapitalAccount memory account = senior.seniorCapitalAccount(alice);
        assertEq(account.pendingSince, secondDepositAt - 5 minutes);
    }

    function test_PendingCapitalCanBeWithdrawnWithoutBecomingRiskBearing() public {
        _deposit(alice, 100e18);

        vm.prank(alice);
        senior.withdrawPendingSeniorCapital(40e18, bob);

        assertEq(asset.balanceOf(bob), 40e18);
        assertEq(senior.seniorCapitalAccount(alice).pendingPrincipal, 60e18);
        assertEq(senior.seniorCapitalState().totalPrincipal, 0);
    }

    function test_FeeIndexPaysExistingCapitalAndIgnoresDirectTransfers() public {
        _depositAndActivate(alice, 100e18);
        _mintAndApprove(donor, 30e18);

        vm.prank(donor);
        senior.donateSeniorCapitalFees(20e18);
        vm.prank(donor);
        asset.transfer(address(senior), 10e18);

        assertEq(senior.pendingSeniorCapitalFees(alice), 20e18);
        assertEq(senior.seniorCapitalState().feeReserve, 20e18);

        vm.prank(alice);
        uint256 claimed = senior.claimSeniorCapitalFees(alice);
        assertEq(claimed, 20e18);
        assertEq(asset.balanceOf(alice), 20e18);
        assertEq(senior.seniorCapitalState().feeReserve, 0);
    }

    function test_AdditionalActivationCannotEarnHistoricalFees() public {
        _deposit(alice, 100e18);
        _deposit(bob, 100e18);
        vm.warp(block.timestamp + 15 minutes);
        vm.prank(alice);
        senior.activateSeniorCapital();
        vm.prank(bob);
        senior.activateSeniorCapital();

        _deposit(alice, 100e18);
        vm.warp(uint256(senior.seniorCapitalAccount(alice).pendingSince) + 15 minutes);
        _mintAndApprove(donor, 200e18);
        vm.prank(donor);
        senior.donateSeniorCapitalFees(200e18);
        vm.prank(alice);
        senior.activateSeniorCapital();

        assertEq(senior.pendingSeniorCapitalFees(alice), 100e18);
        assertEq(senior.pendingSeniorCapitalFees(bob), 100e18);
        vm.prank(alice);
        uint256 aliceClaim = senior.claimSeniorCapitalFees(alice);
        vm.prank(bob);
        uint256 bobClaim = senior.claimSeniorCapitalFees(bob);
        assertEq(aliceClaim + bobClaim, 200e18);
        assertEq(senior.seniorCapitalState().feeReserve, 0);
    }

    function test_FullExitCancellationPreservesSettledCheckpoint() public {
        _depositAndActivate(alice, 100e18);
        _depositAndActivate(bob, 100e18);
        vm.prank(alice);
        (uint256 exitId,,) = senior.requestSeniorCapitalExit(100e18, alice);

        _mintAndApprove(donor, 20e18);
        vm.prank(donor);
        senior.donateSeniorCapitalFees(20e18);
        vm.prank(alice);
        senior.cancelSeniorCapitalExit(exitId);

        assertEq(senior.pendingSeniorCapitalFees(alice), 10e18);
        assertEq(senior.pendingSeniorCapitalFees(bob), 10e18);
        vm.prank(bob);
        uint256 bobClaim = senior.claimSeniorCapitalFees(bob);
        vm.prank(alice);
        uint256 aliceClaim = senior.claimSeniorCapitalFees(alice);
        assertEq(aliceClaim + bobClaim, 20e18);
        assertEq(senior.seniorCapitalState().feeReserve, 0);
    }

    function test_RevertingExitReceiverCannotBlockLaterClaims() public {
        MockUSDG selectiveAsset = new MockUSDG();
        SeniorCapitalHarness selectiveSenior = new SeniorCapitalHarness();
        selectiveSenior.setMarginAsset(address(selectiveAsset));
        selectiveAsset.mint(alice, 100e18);
        selectiveAsset.mint(bob, 100e18);
        vm.prank(alice);
        selectiveAsset.approve(address(selectiveSenior), 100e18);
        vm.prank(bob);
        selectiveAsset.approve(address(selectiveSenior), 100e18);
        vm.prank(alice);
        selectiveSenior.depositSeniorCapital(100e18);
        vm.prank(bob);
        selectiveSenior.depositSeniorCapital(100e18);
        vm.warp(block.timestamp + 15 minutes);
        vm.prank(alice);
        selectiveSenior.activateSeniorCapital();
        vm.prank(bob);
        selectiveSenior.activateSeniorCapital();

        address blockedReceiver = makeAddr("blocked-receiver");
        selectiveAsset.setBlacklisted(blockedReceiver, true);
        vm.prank(alice);
        selectiveSenior.requestSeniorCapitalExit(100e18, blockedReceiver);
        vm.prank(bob);
        selectiveSenior.requestSeniorCapitalExit(100e18, bob);

        selectiveSenior.processSeniorCapitalExits(2);
        assertEq(selectiveSenior.claimableSeniorCapitalExit(alice), 100e18);
        assertEq(selectiveSenior.claimableSeniorCapitalExit(bob), 100e18);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MockUSDG.AccountBlacklisted.selector, blockedReceiver));
        selectiveSenior.claimSeniorCapitalExit(blockedReceiver);
        vm.prank(bob);
        selectiveSenior.claimSeniorCapitalExit(bob);
        assertEq(selectiveAsset.balanceOf(bob), 100e18);
        assertEq(selectiveSenior.claimableSeniorCapitalExit(alice), 100e18);
    }

    function test_RealizedLossScalesAllAccountsProRata() public {
        _depositAndActivate(alice, 100e18);
        _depositAndActivate(bob, 100e18);
        senior.reserve(bucketId, 200e18);
        senior.deploy(bucketId, 200e18);

        senior.recordLoss(bucketId, 50e18);

        assertEq(senior.seniorCapitalAccount(alice).effectivePrincipal, 75e18);
        assertEq(senior.seniorCapitalAccount(bob).effectivePrincipal, 75e18);
        assertEq(senior.seniorCapitalState().totalPrincipal, 150e18);
    }

    function test_ExitQueueIsFifoAndPartiallyWaitsForReleasedCapital() public {
        _depositAndActivate(alice, 100e18);
        _depositAndActivate(bob, 100e18);

        vm.prank(alice);
        (uint256 aliceExit,,) = senior.requestSeniorCapitalExit(50e18, alice);
        senior.reserve(bucketId, 150e18);
        vm.prank(bob);
        (uint256 bobExit,,) = senior.requestSeniorCapitalExit(50e18, bob);

        senior.processSeniorCapitalExits(10);
        vm.prank(alice);
        senior.claimSeniorCapitalExit(alice);
        assertEq(asset.balanceOf(alice), 50e18);
        assertEq(asset.balanceOf(bob), 0);
        assertEq(senior.seniorCapitalExit(aliceExit).storedUnits, 0);
        assertEq(senior.seniorCapitalExit(bobExit).storedUnits, 50e18);

        senior.release(bucketId, 50e18);
        senior.processSeniorCapitalExits(10);
        vm.prank(bob);
        senior.claimSeniorCapitalExit(bob);
        assertEq(asset.balanceOf(bob), 50e18);
        assertEq(senior.seniorCapitalExit(bobExit).storedUnits, 0);
    }

    function test_QueuedCapitalEarnsFeesAndCanBeCancelled() public {
        _depositAndActivate(alice, 100e18);
        vm.prank(alice);
        (uint256 exitId,,) = senior.requestSeniorCapitalExit(40e18, alice);
        _mintAndApprove(donor, 10e18);
        vm.prank(donor);
        senior.donateSeniorCapitalFees(10e18);

        assertEq(senior.seniorCapitalExit(exitId).pendingFees, 4e18);
        vm.prank(alice);
        uint256 restored = senior.cancelSeniorCapitalExit(exitId);

        assertEq(restored, 40e18);
        assertEq(senior.seniorCapitalAccount(alice).effectivePrincipal, 100e18);
        assertEq(senior.pendingSeniorCapitalFees(alice), 10e18);
        assertEq(senior.seniorCapitalState().availableCapital, 100e18);
    }

    function test_FullLossRollsEpochButPreservesEarnedFees() public {
        _depositAndActivate(alice, 100e18);
        _mintAndApprove(donor, 10e18);
        vm.prank(donor);
        senior.donateSeniorCapitalFees(10e18);
        senior.reserve(bucketId, 100e18);
        senior.deploy(bucketId, 100e18);

        senior.recordLoss(bucketId, 100e18);

        assertEq(senior.seniorCapitalState().epoch, 1);
        assertEq(senior.seniorCapitalAccount(alice).effectivePrincipal, 0);
        assertEq(senior.pendingSeniorCapitalFees(alice), 10e18);

        vm.prank(alice);
        senior.claimSeniorCapitalFees(alice);
        assertEq(asset.balanceOf(alice), 10e18);
        assertEq(senior.seniorCapitalState().feeReserve, 0);
    }

    function testFuzz_RealizedLossConservesEffectivePrincipal(uint96 aliceRaw, uint96 bobRaw, uint96 lossRaw) public {
        uint256 alicePrincipal = bound(uint256(aliceRaw), 1e6, 1e24);
        uint256 bobPrincipal = bound(uint256(bobRaw), 1e6, 1e24);
        _deposit(alice, alicePrincipal);
        _deposit(bob, bobPrincipal);
        vm.warp(block.timestamp + 15 minutes);
        vm.prank(alice);
        senior.activateSeniorCapital();
        vm.prank(bob);
        senior.activateSeniorCapital();

        uint256 total = alicePrincipal + bobPrincipal;
        uint256 loss = bound(uint256(lossRaw), 1, total - 1);
        senior.reserve(bucketId, total);
        senior.deploy(bucketId, total);
        senior.recordLoss(bucketId, loss);

        uint256 effective =
            senior.seniorCapitalAccount(alice).effectivePrincipal + senior.seniorCapitalAccount(bob).effectivePrincipal;
        assertEq(senior.seniorCapitalState().totalPrincipal, total - loss);
        assertLe(effective, total - loss);
        assertLe((total - loss) - effective, 2);
    }

    function testFuzz_FeeClaimsConserveDonation(uint96 aliceRaw, uint96 bobRaw, uint96 donationRaw) public {
        uint256 alicePrincipal = bound(uint256(aliceRaw), 1e6, 1e24);
        uint256 bobPrincipal = bound(uint256(bobRaw), 1e6, 1e24);
        uint256 donation = bound(uint256(donationRaw), 1, 1e24);
        _deposit(alice, alicePrincipal);
        _deposit(bob, bobPrincipal);
        vm.warp(block.timestamp + 15 minutes);
        vm.prank(alice);
        senior.activateSeniorCapital();
        vm.prank(bob);
        senior.activateSeniorCapital();
        _mintAndApprove(donor, donation);
        vm.prank(donor);
        senior.donateSeniorCapitalFees(donation);

        vm.prank(alice);
        uint256 aliceClaim = senior.claimSeniorCapitalFees(alice);
        vm.prank(bob);
        uint256 bobClaim = senior.claimSeniorCapitalFees(bob);

        vm.prank(alice);
        senior.requestSeniorCapitalExit(alicePrincipal, alice);
        vm.prank(bob);
        senior.requestSeniorCapitalExit(bobPrincipal, bob);
        (,,, uint256 exitFees) = senior.processSeniorCapitalExits(2);

        assertEq(aliceClaim + bobClaim + exitFees, donation);
        assertEq(senior.seniorCapitalState().feeReserve, 0);
    }

    function testFuzz_ActivationAndExitCancellationKeepFeeReserveSolvent(
        uint96 aliceRaw,
        uint96 bobRaw,
        uint96 topUpRaw,
        uint96 donationRaw,
        bool aliceClaimsFirst
    ) public {
        uint256 alicePrincipal = bound(uint256(aliceRaw), 1e12, 1e24);
        uint256 bobPrincipal = bound(uint256(bobRaw), 1e12, 1e24);
        uint256 topUp = bound(uint256(topUpRaw), 1e12, 1e24);
        uint256 donation = bound(uint256(donationRaw), 1e12, 1e24);
        _deposit(alice, alicePrincipal);
        _deposit(bob, bobPrincipal);
        vm.warp(block.timestamp + 15 minutes);
        vm.prank(alice);
        senior.activateSeniorCapital();
        vm.prank(bob);
        senior.activateSeniorCapital();

        _deposit(alice, topUp);
        vm.warp(uint256(senior.seniorCapitalAccount(alice).pendingSince) + 15 minutes);
        _mintAndApprove(donor, donation * 3);
        vm.prank(donor);
        senior.donateSeniorCapitalFees(donation);
        vm.prank(alice);
        senior.activateSeniorCapital();

        for (uint256 cycle; cycle < 2; ++cycle) {
            vm.prank(alice);
            (uint256 exitId,,) = senior.requestSeniorCapitalExit(alicePrincipal + topUp, alice);
            vm.prank(donor);
            senior.donateSeniorCapitalFees(donation);
            vm.prank(alice);
            senior.cancelSeniorCapitalExit(exitId);
        }

        uint256 reserveBefore = senior.seniorCapitalState().feeReserve;
        uint256 alicePending = senior.pendingSeniorCapitalFees(alice);
        uint256 bobPending = senior.pendingSeniorCapitalFees(bob);
        assertLe(alicePending + bobPending, reserveBefore);

        uint256 firstClaim;
        uint256 secondClaim;
        if (aliceClaimsFirst) {
            vm.prank(alice);
            firstClaim = senior.claimSeniorCapitalFees(alice);
            vm.prank(bob);
            secondClaim = senior.claimSeniorCapitalFees(bob);
        } else {
            vm.prank(bob);
            firstClaim = senior.claimSeniorCapitalFees(bob);
            vm.prank(alice);
            secondClaim = senior.claimSeniorCapitalFees(alice);
        }
        assertEq(firstClaim + secondClaim + senior.seniorCapitalState().feeReserve, reserveBefore);
    }

    function testFuzz_ExitQueueAndClaimsConservePrincipal(uint96 aliceRaw, uint96 bobRaw, uint96 reserveRaw) public {
        uint256 alicePrincipal = bound(uint256(aliceRaw), 1e12, 1e24);
        uint256 bobPrincipal = bound(uint256(bobRaw), 1e12, 1e24);
        uint256 total = alicePrincipal + bobPrincipal;
        uint256 reserved = bound(uint256(reserveRaw), 0, total);
        _deposit(alice, alicePrincipal);
        _deposit(bob, bobPrincipal);
        vm.warp(block.timestamp + 15 minutes);
        vm.prank(alice);
        senior.activateSeniorCapital();
        vm.prank(bob);
        senior.activateSeniorCapital();
        if (reserved != 0) senior.reserve(bucketId, reserved);

        vm.prank(alice);
        senior.requestSeniorCapitalExit(alicePrincipal, alice);
        vm.prank(bob);
        senior.requestSeniorCapitalExit(bobPrincipal, bob);
        senior.processSeniorCapitalExits(2);
        uint256 firstClaims = senior.claimableSeniorCapitalExit(alice) + senior.claimableSeniorCapitalExit(bob);
        assertEq(firstClaims + senior.seniorCapitalState().totalPrincipal, total);

        if (reserved != 0) senior.release(bucketId, reserved);
        senior.processSeniorCapitalExits(2);
        uint256 finalClaims = senior.claimableSeniorCapitalExit(alice) + senior.claimableSeniorCapitalExit(bob);
        assertEq(finalClaims, total);
        assertEq(senior.seniorCapitalState().totalPrincipal, 0);
        assertEq(senior.seniorCapitalState().exitClaims, total);
    }

    function _deposit(address account, uint256 assets) internal {
        _mintAndApprove(account, assets);
        vm.prank(account);
        senior.depositSeniorCapital(assets);
    }

    function _depositAndActivate(address account, uint256 assets) internal {
        _deposit(account, assets);
        vm.warp(block.timestamp + 15 minutes);
        vm.prank(account);
        senior.activateSeniorCapital();
    }

    function _mintAndApprove(address account, uint256 assets) internal {
        asset.mint(account, assets);
        vm.prank(account);
        asset.approve(address(senior), assets);
    }
}
