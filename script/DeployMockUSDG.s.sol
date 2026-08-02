// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";

import {MockUSDG} from "../src/mocks/MockUSDG.sol";

contract DeployMockUSDG is Script {
    function run() external returns (MockUSDG token) {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.envAddress("MOCK_USDG_OWNER");
        address recipient = vm.envAddress("MOCK_USDG_INITIAL_RECIPIENT");
        uint256 initialSupply = vm.envUint("MOCK_USDG_INITIAL_SUPPLY");

        vm.startBroadcast(privateKey);
        token = deploy(owner, recipient, initialSupply);
        vm.stopBroadcast();

        console2.log("Mock USDG", address(token));
        console2.log("owner", owner);
        console2.log("initial recipient", recipient);
        console2.log("initial supply", initialSupply);
    }

    function deploy(address owner, address recipient, uint256 initialSupply) public returns (MockUSDG token) {
        token = new MockUSDG();
        token.mint(recipient, initialSupply);
        token.transferOwnership(owner);
    }
}
