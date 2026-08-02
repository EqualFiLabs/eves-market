// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {
    DeployStaticsDollar,
    StaticsDollarLocalConfig,
    StaticsDollarStackDeployment
} from "../../lib/statics/script/dollar/DeployStaticsDollar.s.sol";
import {CoreGovernanceFacet} from "@statics/dollar/core/facets/CoreGovernanceFacet.sol";
import {IStaticsDollarCoreTypes} from "@statics/dollar/interfaces/IStaticsDollarCoreTypes.sol";
import {MockETHUSDOracle} from "@statics/dollar/mocks/MockETHUSDOracle.sol";

abstract contract StaticsDollarCoreFixture is Test {
    struct ActiveStaticsDollar {
        StaticsDollarStackDeployment deployment;
        uint256 profileId;
        MockETHUSDOracle usdcOracle;
    }

    function _deployActiveStaticsDollar(address protocolGovernor, IERC20 usdc)
        internal
        returns (ActiveStaticsDollar memory active)
    {
        StaticsDollarLocalConfig memory config;
        config.owner = protocolGovernor;
        config.profileGuardian = protocolGovernor;
        config.treasury = protocolGovernor;
        config.deployMockWeth = true;
        config.deployMockOracle = true;
        config.mockOraclePriceWad = 2_500e18;
        config.mockOracleMaxStaleness = 30 days;
        config.riskUri = "uri://statics-dollar-risk/{id}";
        active.deployment = new DeployStaticsDollar().deployLocal(config);
        active.usdcOracle = new MockETHUSDOracle(1e18, 30 days);

        CoreGovernanceFacet governance = CoreGovernanceFacet(active.deployment.core);
        vm.startPrank(protocolGovernor);
        active.profileId = governance.createPeggedCollateralProfile(
            address(usdc), address(active.usdcOracle), 0.995e18, 1.005e18, 5, 5, 10_000_000e18
        );
        governance.setProfileMode(active.profileId, IStaticsDollarCoreTypes.ProfileMode.Active);
        vm.stopPrank();
    }
}
