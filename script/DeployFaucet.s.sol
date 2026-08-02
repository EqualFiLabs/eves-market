// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script, console2} from "../lib/forge-std/src/Script.sol";

import {Faucet} from "../src/Faucet.sol";

interface IMintableERC20 {
    function mint(address account, uint256 amount) external;
}

contract DeployFaucetScript is Script {
    struct Config {
        uint256 privateKey;
        address owner;
        address usdc;
        address eve;
        uint256 usdcClaimAmount;
        uint256 eveClaimAmount;
        bool mintTokens;
        uint256 usdcMintAmount;
        uint256 eveMintAmount;
    }

    struct Deployment {
        address faucet;
    }

    function run() external returns (Deployment memory deployment) {
        Config memory config = _loadConfig();

        vm.startBroadcast(config.privateKey);

        Faucet faucet = new Faucet(config.owner);
        faucet.setToken(config.usdc, config.usdcClaimAmount, true);
        faucet.setToken(config.eve, config.eveClaimAmount, true);

        if (config.mintTokens) {
            IMintableERC20(config.usdc).mint(address(faucet), config.usdcMintAmount);
            IMintableERC20(config.eve).mint(address(faucet), config.eveMintAmount);
        }

        vm.stopBroadcast();

        deployment.faucet = address(faucet);

        console2.log("faucet", deployment.faucet);
        console2.log("owner", config.owner);
        console2.log("mUSDC", config.usdc);
        console2.log("mEVE", config.eve);
        console2.log("mUSDC claim amount", config.usdcClaimAmount);
        console2.log("mEVE claim amount", config.eveClaimAmount);
    }

    function _loadConfig() private view returns (Config memory config) {
        config.privateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(config.privateKey);

        config.owner = vm.envOr("FAUCET_OWNER", deployer);
        config.usdc = vm.envAddress("FAUCET_USDC_TOKEN");
        config.eve = vm.envAddress("FAUCET_EVE_TOKEN");
        config.usdcClaimAmount = vm.envOr("FAUCET_USDC_CLAIM_AMOUNT", uint256(1_000e6));
        config.eveClaimAmount = vm.envOr("FAUCET_EVE_CLAIM_AMOUNT", uint256(10_000e18));
        config.mintTokens = vm.envOr("FAUCET_MINT_TOKENS", false);
        config.usdcMintAmount = vm.envOr("FAUCET_USDC_MINT_AMOUNT", uint256(1_000_000e6));
        config.eveMintAmount = vm.envOr("FAUCET_EVE_MINT_AMOUNT", uint256(10_000_000e18));
    }
}
