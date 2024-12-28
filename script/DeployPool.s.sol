// SPDX-License-Identifier: BUSL-1.1
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

    PotentiaPool public pool;
    address public WethUsdcOracle = 0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1;
    PotentiaFactory public factory = PotentiaFactory(Factory);

    function run() public {
        vm.startBroadcast(PoolOperator);

        // setup the params
        uint256 k = 2e18;
        uint256 adjustRate = 0.001e18;
        uint256 halfTime = 2592000e18;

        WETH weth = WETH(Weth);
        AggregatorV3Interface priceFeed = AggregatorV3Interface(WethUsdcOracle);

        // deploy the potentia pool #1
        pool = PotentiaPool(
            factory.createPool(
                address(weth), k, adjustRate, 0x780Ba1B742512aB21a6209eEAf41f4B2F3233f6f, halfTime, address(priceFeed)
            )
        );

        console.log("Weth Pool %s", address(pool));

        uint256 initialLiq = 0.0001 ether;

        // approve pool to use weth #2
        weth.approve(address(pool), 1000 ether);

        // initialize pool #3
        pool.initializePool(initialLiq);

        // add liq
        pool.addLiquidity(800 ether);

        vm.stopBroadcast();
    }
}
