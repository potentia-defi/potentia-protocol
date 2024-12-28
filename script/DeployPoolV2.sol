// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PotentiaPool} from "../src/PotentiaPool.sol";
import {PotentiaFactory} from "../src/PotentiaFactory.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployPools is Script {
    error DeployPools__FactoryAddressRequired();
    error DeployPools__TokenNotSupported(string token);

    struct PoolConfig {
        string tokenSymbol;
        uint256 power;
        uint256 initialLiquidity;
    }

    PoolConfig[] public poolsToCreate;
    uint256 constant ADDEDLIQUIDITY = 5000 ether;

    constructor() {
        // Configure the pools you want to create
        poolsToCreate.push(
            PoolConfig({
                tokenSymbol: "WETH",
                power: 2e18, // k=2
                initialLiquidity: 0.001 ether
            })
        );
        poolsToCreate.push(
            PoolConfig({
                tokenSymbol: "WETH",
                power: 8e18, // k=8
                initialLiquidity: 0.001 ether
            })
        );
        poolsToCreate.push(
            PoolConfig({
                tokenSymbol: "WBTC",
                power: 2e18, // k=2
                initialLiquidity: 0.001 ether
            })
        );
        poolsToCreate.push(
            PoolConfig({
                tokenSymbol: "WBTC",
                power: 4e18, // k=4
                initialLiquidity: 0.001 ether
            })
        );
        poolsToCreate.push(
            PoolConfig({
                tokenSymbol: "WBTC",
                power: 8e18, // k=8
                initialLiquidity: 0.001 ether
            })
        );
        poolsToCreate.push(
            PoolConfig({
                tokenSymbol: "WBTC",
                power: 16e18, // k=16
                initialLiquidity: 0.001 ether
            })
        );
    }

    function run() external {
        // Setup
        address factoryAddress = vm.envOr("FACTORY", address(0));
        if (factoryAddress == address(0)) {
            revert DeployPools__FactoryAddressRequired();
        }

        HelperConfig config = new HelperConfig();
        PotentiaFactory factory = PotentiaFactory(factoryAddress);

        uint256 operatorKey;
        if (block.chainid == 31337) {
            // Anvil chain ID
            operatorKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80; // First Anvil private key
        } else {
            string memory privateKey = vm.envString("OPERATOR_KEY");
            operatorKey = vm.parseUint(privateKey);
        }

        vm.startBroadcast(operatorKey);

        // Deploy pools based on configuration
        for (uint256 i = 0; i < poolsToCreate.length; i++) {
            PoolConfig memory poolConfig = poolsToCreate[i];

            // Get token-specific configuration
            (
                address token,
                address oracle,
                , // default power (we'll use our custom power)
                uint256 adjustRate,
                uint256 halfTime,
                uint256 defaultInitialLiq
            ) = config.getPoolParams(poolConfig.tokenSymbol);

            if (token == address(0)) {
                revert DeployPools__TokenNotSupported(poolConfig.tokenSymbol);
            }

            address sender = vm.addr(operatorKey);

            // Create pool
            PotentiaPool pool = PotentiaPool(
                factory.createPool(
                    token,
                    poolConfig.power,
                    adjustRate,
                    sender, // operator
                    halfTime,
                    oracle
                )
            );
            console2.log("Private Key  %s:", operatorKey);
            console2.log("Token Address  %s:", token);
            console2.log("Pool deployed for %s:", poolConfig.tokenSymbol);
            console2.log("- k: %s", poolConfig.power / 1e18);
            console2.log("- adjustRate: %s /1e18", adjustRate);
            console2.log("- operator: %s", sender);
            console2.log("- halfTime: %s Seconds", (halfTime / 1e18)); // Converting to days for better readability
            console2.log("- oracle: %s", oracle);
            console2.log("- pool address: %s", address(pool));
            // Handle initialization and liquidity
            uint256 initialLiq = poolConfig.initialLiquidity > 0 ? poolConfig.initialLiquidity : defaultInitialLiq;

            // Approve token usage
            IERC20(token).approve(address(pool), type(uint256).max);

            // Initialize pool
            pool.initializePool(initialLiq);
            console2.log("Pool initialized with %s initial liquidity", initialLiq);

            pool.addLiquidity(ADDEDLIQUIDITY);

            console2.log("Added Liquidity: %s", ADDEDLIQUIDITY);

            // Add additional liquidity if specified
            // if (poolConfig.initialLiquidity > initialLiq) {
            //     pool.addLiquidity(poolConfig.initialLiquidity - initialLiq);
            //     console2.log("Added %s additional liquidity", poolConfig.initialLiquidity - initialLiq);
            // }

            // // Save deployment info
            // _saveDeploymentInfo(
            //     poolConfig.tokenSymbol,
            //     poolConfig.power,
            //     address(pool),
            //     token,
            //     oracle
            // );
        }

        vm.stopBroadcast();
    }

    function _saveDeploymentInfo(string memory tokenSymbol, uint256 power, address pool, address token, address oracle)
        internal
    {
        string memory network = vm.toString(block.chainid);
        string memory powerStr = vm.toString(power);
        string memory fileName = string.concat("deployments/", network, "_pool_", tokenSymbol, "_k", powerStr, ".txt");

        string memory deploymentData = string.concat(
            "Pool: ",
            vm.toString(pool),
            "\nToken: ",
            vm.toString(token),
            "\nOracle: ",
            vm.toString(oracle),
            "\nPower: ",
            powerStr
        );

        vm.writeFile(fileName, deploymentData);
    }
}
