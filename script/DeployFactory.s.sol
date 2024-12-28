// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";

import {WETH} from "./mocks/WETH.sol";
import {PotentiaPool} from "../src/PotentiaPool.sol";
import {PotentiaFactory} from "../src/PotentiaFactory.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract DeployPotentia is Script {
    PotentiaFactory public factory;

    WETH public weth;
    uint256 protocol = vm.envUint("POTENTIA");

    function run() public {
        vm.startBroadcast(protocol);

        weth = new WETH();
        console.log("Weth %s", address(weth));

        // deploying the factory
        factory = new PotentiaFactory();
        console.log("Factory %s", address(factory));
        vm.stopBroadcast();
    }
}
