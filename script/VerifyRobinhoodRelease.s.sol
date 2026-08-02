// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {console2} from "forge-std/Script.sol";

import {DeployScript} from "./Deploy.s.sol";

contract VerifyRobinhoodRelease is DeployScript {
    function run() external view override returns (FullDeployment memory deployment) {
        string memory manifestPath = vm.envString("DEPLOYMENT_MANIFEST_PATH");

        (deployment,) = verifyFullDeploymentManifestFromFile(manifestPath);

        console2.log("Robinhood release manifest verified");
        console2.log("Eve Market Diamond", deployment.market.diamond);
        console2.log("Statics Dollar", deployment.staticsDollar);
        console2.log("Statics Diamond", deployment.staticsDiamond);
    }
}
