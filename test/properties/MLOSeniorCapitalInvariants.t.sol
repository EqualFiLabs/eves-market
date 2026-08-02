// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {StdInvariant} from "../../lib/forge-std/src/StdInvariant.sol";
import {Test} from "../../lib/forge-std/src/Test.sol";

import {SeniorCapitalFacet} from "../../src/facets/SeniorCapitalFacet.sol";
import {SeniorCapitalViewFacet} from "../../src/facets/SeniorCapitalViewFacet.sol";
import {ISeniorCapitalFacet} from "../../src/interfaces/ISeniorCapitalFacet.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {MockEveToken} from "../helpers/MockEveToken.sol";

/// @dev This narrow harness isolates the Senior index and FIFO state machine so the
/// invariant runner can explore checkpoint and cancellation orderings economically
/// impractical to reproduce through complete market settlement on every generated call.
contract MLOSeniorInvariantHarness is SeniorCapitalFacet, SeniorCapitalViewFacet {
    function setMarginAsset(address asset) external {
        LibEveMarket.store().marginAsset = asset;
    }
}

contract MLOSeniorInvariantHandler is Test {
    MLOSeniorInvariantHarness internal immutable senior;
    MockEveToken internal immutable asset;
    address[] internal actors;
    uint256[] internal exitIds;
    address internal immutable donor;

    constructor(MLOSeniorInvariantHarness senior_, MockEveToken asset_, address[] memory actors_) {
        senior = senior_;
        asset = asset_;
        donor = makeAddr("invariant-donor");
        for (uint256 index; index < actors_.length; ++index) {
            actors.push(actors_[index]);
            vm.prank(actors_[index]);
            asset.approve(address(senior_), type(uint256).max);
        }
        vm.prank(donor);
        asset.approve(address(senior_), type(uint256).max);
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function actorAt(uint256 index) external view returns (address) {
        return actors[index];
    }

    function exitCount() external view returns (uint256) {
        return exitIds.length;
    }

    function exitAt(uint256 index) external view returns (uint256) {
        return exitIds[index];
    }

    function deposit(uint256 actorSeed, uint256 assetsSeed) external {
        address actor = actors[actorSeed % actors.length];
        uint256 assets = bound(assetsSeed, 1, 1e24);
        asset.mint(actor, assets);
        vm.prank(actor);
        senior.depositSeniorCapital(assets);
    }

    function advanceAndActivate(uint256 elapsedSeed) external {
        vm.warp(block.timestamp + bound(elapsedSeed, 1, 3 days));
        for (uint256 index; index < actors.length; ++index) {
            vm.prank(actors[index]);
            try senior.activateSeniorCapital() {} catch {}
        }
    }

    function donate(uint256 assetsSeed) external {
        if (senior.seniorCapitalState().totalStored == 0) return;
        uint256 assets = bound(assetsSeed, 1, 1e24);
        asset.mint(donor, assets);
        vm.prank(donor);
        senior.donateSeniorCapitalFees(assets);
    }

    function requestExit(uint256 actorSeed, uint256 assetsSeed) external {
        address actor = actors[actorSeed % actors.length];
        uint256 effective = senior.seniorCapitalAccount(actor).effectivePrincipal;
        if (effective == 0) return;
        uint256 assets = bound(assetsSeed, 1, effective);
        vm.prank(actor);
        try senior.requestSeniorCapitalExit(assets, actor) returns (uint256 exitId, uint256, uint256) {
            exitIds.push(exitId);
        } catch {}
    }

    function cancelExit(uint256 exitSeed) external {
        if (exitIds.length == 0) return;
        uint256 exitId = exitIds[exitSeed % exitIds.length];
        ISeniorCapitalFacet.SeniorCapitalExit memory request = senior.seniorCapitalExit(exitId);
        if (request.owner == address(0) || request.storedUnits == 0) return;
        vm.prank(request.owner);
        try senior.cancelSeniorCapitalExit(exitId) {} catch {}
    }

    function processExits(uint256 countSeed) external {
        try senior.processSeniorCapitalExits(bound(countSeed, 1, 16)) {} catch {}
    }

    function claimFees(uint256 actorSeed) external {
        address actor = actors[actorSeed % actors.length];
        if (senior.pendingSeniorCapitalFees(actor) == 0) return;
        vm.prank(actor);
        try senior.claimSeniorCapitalFees(actor) {} catch {}
    }

    function claimExit(uint256 actorSeed) external {
        address actor = actors[actorSeed % actors.length];
        if (senior.claimableSeniorCapitalExit(actor) == 0) return;
        vm.prank(actor);
        try senior.claimSeniorCapitalExit(actor) {} catch {}
    }
}

contract MLOSeniorCapitalInvariantsTest is StdInvariant, Test {
    MLOSeniorInvariantHarness internal senior;
    MLOSeniorInvariantHandler internal handler;
    MockEveToken internal asset;

    function setUp() public {
        asset = new MockEveToken();
        senior = new MLOSeniorInvariantHarness();
        senior.setMarginAsset(address(asset));
        address[] memory actors = new address[](3);
        actors[0] = makeAddr("invariant-alice");
        actors[1] = makeAddr("invariant-bob");
        actors[2] = makeAddr("invariant-carol");
        handler = new MLOSeniorInvariantHandler(senior, asset, actors);
        targetContract(address(handler));
    }

    function invariant_AccountAndQueuedFeesNeverExceedReserve() public view {
        uint256 aggregateClaimable;
        for (uint256 index; index < handler.actorCount(); ++index) {
            aggregateClaimable += senior.pendingSeniorCapitalFees(handler.actorAt(index));
        }
        for (uint256 index; index < handler.exitCount(); ++index) {
            aggregateClaimable += senior.seniorCapitalExit(handler.exitAt(index)).pendingFees;
        }
        assertLe(aggregateClaimable, senior.seniorCapitalState().feeReserve);
    }

    function invariant_RecordLiabilitiesRemainBacked() public view {
        ISeniorCapitalFacet.SeniorCapitalState memory state = senior.seniorCapitalState();
        uint256 recorded = state.pendingPrincipal + state.totalPrincipal + state.feeReserve + state.exitClaims;
        assertGe(asset.balanceOf(address(senior)), recorded);
        assertLe(state.exitStored, state.totalStored);
    }
}
