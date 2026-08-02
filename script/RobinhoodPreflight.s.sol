// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {console2} from "forge-std/Script.sol";

import {DeployScript} from "./Deploy.s.sol";

contract RobinhoodPreflight is DeployScript {
    function run() external view override returns (FullDeployment memory deployment) {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address broadcaster = vm.addr(privateKey);

        verifyRobinhoodPreflight(_loadFullConfigFromEnv(), broadcaster);

        console2.log("Robinhood preflight passed");
        console2.log("broadcaster", broadcaster);
        console2.log("chain ID", block.chainid);
        return deployment;
    }
}
