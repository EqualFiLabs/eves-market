// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {DeployScript} from "../../script/Deploy.s.sol";
import {MockConditionalTokens} from "../helpers/MockConditionalTokens.sol";

contract RobinhoodTestnetDeployHarness is DeployScript {
    function resolveConditionalTokens(address configuredAddress) external returns (address) {
        return _resolveConditionalTokens(configuredAddress, DEFAULT_CONDITIONAL_TOKENS_ARTIFACT_PATH);
    }
}

contract RobinhoodTestnetDeploymentTest is Test {
    RobinhoodTestnetDeployHarness private harness;

    function setUp() public {
        harness = new RobinhoodTestnetDeployHarness();
        vm.chainId(46630);
    }

    function testRequiresExplicitConditionalTokensDeployment() public {
        vm.expectRevert(DeployScript.RobinhoodTestnetConditionalTokensRequired.selector);
        harness.resolveConditionalTokens(address(0));
    }

    function testAcceptsExplicitConditionalTokensDeployment() public {
        MockConditionalTokens conditionalTokens = new MockConditionalTokens();

        assertEq(harness.resolveConditionalTokens(address(conditionalTokens)), address(conditionalTokens));
    }
}
