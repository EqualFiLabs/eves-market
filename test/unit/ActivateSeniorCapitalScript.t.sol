// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ActivateSeniorCapital} from "../../script/ActivateSeniorCapital.s.sol";
import {SeniorCapitalFacet} from "../../src/facets/SeniorCapitalFacet.sol";
import {SeniorCapitalViewFacet} from "../../src/facets/SeniorCapitalViewFacet.sol";
import {LibEveMarket} from "../../src/libraries/LibEveMarket.sol";
import {MockUSDG} from "../helpers/MockUSDG.sol";

contract SeniorActivationScriptHarness is SeniorCapitalFacet, SeniorCapitalViewFacet {
    function setMarginAsset(address asset) external {
        LibEveMarket.store().marginAsset = asset;
    }
}

contract ActivateSeniorCapitalScriptTest is Test {
    uint256 internal constant PROVIDER_KEY = 0xA11CE;
    uint256 internal constant ASSETS = 100_000e6;

    SeniorActivationScriptHarness internal senior;
    MockUSDG internal asset;
    ActivateSeniorCapital internal activationScript;
    address internal provider;

    function setUp() public {
        provider = vm.addr(PROVIDER_KEY);
        senior = new SeniorActivationScriptHarness();
        asset = new MockUSDG();
        activationScript = new ActivateSeniorCapital();
        senior.setMarginAsset(address(asset));

        asset.mint(provider, ASSETS);
        vm.startPrank(provider);
        asset.approve(address(senior), ASSETS);
        senior.depositSeniorCapital(ASSETS);
        vm.stopPrank();

        vm.setEnv("PRIVATE_KEY", vm.toString(PROVIDER_KEY));
        vm.setEnv("EVE_DIAMOND", vm.toString(address(senior)));
    }

    function test_RunActivatesEligibleDeploymentBootstrap() public {
        vm.warp(senior.seniorCapitalAccount(provider).pendingSince + senior.seniorCapitalState().activationDelay);

        (uint256 principal, uint256 storedUnits) = activationScript.run();

        assertEq(principal, ASSETS);
        assertEq(storedUnits, ASSETS);
        assertEq(senior.seniorCapitalAccount(provider).pendingPrincipal, 0);
        assertEq(senior.seniorCapitalState().availableCapital, ASSETS);
    }
}
