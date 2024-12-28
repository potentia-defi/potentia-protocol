// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {PotentiaFactory} from "../src/PotentiaFactory.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployFactoryV2 is Script {
    function run() external returns (address) {
        HelperConfig config = new HelperConfig();

        // Get deployer key - use first anvil account if on local network
        uint256 deployerKey;
        if (block.chainid == 31337) {
            // Anvil chain ID
            deployerKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80; // First Anvil private key
        } else {
            string memory privateKey = vm.envString("PRIVATE_KEY");
            deployerKey = vm.parseUint(privateKey);
        }

        vm.startBroadcast(deployerKey);

        PotentiaFactory factory = new PotentiaFactory();

        console.log("Factory deployed at: %s", address(factory));
        console.log("Deployment chain ID: %s", block.chainid);
        console.log("Is testnet: %s", config.isTestnet());

        vm.stopBroadcast();

        // // Store factory address in a file for future reference
        // string memory version = "v1";
        // string memory deploymentData = vm.toString(address(factory));
        // string memory network = vm.toString(block.chainid);
        // string memory fileName = string.concat("liveDeployments/", network, "_factory_", version, ".txt");
        // vm.writeFile(fileName, deploymentData);

        return address(factory);
    }
}
