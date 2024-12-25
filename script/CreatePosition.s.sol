// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";

import {WETH} from "./mocks/WETH.sol";
import {PotentiaPool} from "../src/PotentiaPool.sol";
import {PotentiaFactory} from "../src/PotentiaFactory.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract DeployPotentia is Script {
    address Weth = vm.envAddress("WETH");
    uint256 PoolOperator = vm.envUint("PO");
    address Factory = vm.envAddress("FACTORY");
    address Weth2Pool = vm.envAddress("WETH2POOL");

    WETH public weth = WETH(Weth);
    PotentiaPool public pool = PotentiaPool(Weth2Pool);

    uint256 Luke = vm.envUint("LUKE");
    uint256 Potentia = vm.envUint("POTENTIA");

    function run() public {
        vm.startBroadcast(Luke);

        weth.approve(address(pool), 10 ether);
        pool.openPosition(10 ether, true);
        vm.stopBroadcast();
    }
}
