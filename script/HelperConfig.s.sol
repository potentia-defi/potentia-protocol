// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "./mocks/MockV3Aggregator.sol";
import {MockERC20All} from "./mocks/MockERC20All.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        // Asset addresses
        address weth;
        address usdc;
        address wbtc;
        // Oracle addresses
        address ethUsdOracle;
        address btcUsdOracle;
        address usdcUsdOracle;
        // Pool parameters
        uint256 defaultPower; // k parameter
        uint256 defaultAdjustRate; // Adjust rate
        uint256 defaultHalfTime; // Half time parameter
        uint256 defaultInitialLiq; // Initial liquidity amount
    }

    struct TokenConfig {
        string name;
        string symbol;
        uint8 decimals;
        address addr;
        address oracle;
    }

    address public FAUCET_ADDRESS = address(vm.envAddress("FAUCET_ADDRESS"));
    uint256 public constant FAUCET_AMOUNT = 100_000_000 * 1e18;

    NetworkConfig public activeNetworkConfig;
    mapping(string => TokenConfig) public tokenConfigs;
    uint256 public constant MAINNET_CHAIN_ID = 1;
    uint256 public constant BASE_CHAIN_ID = 8453;
    uint256 public constant SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant BASE_SEPOLIA_CHAIN_ID = 84532;

    constructor() {
        if (block.chainid == MAINNET_CHAIN_ID) {
            activeNetworkConfig = getMainnetConfig();
        } else if (block.chainid == BASE_CHAIN_ID) {
            activeNetworkConfig = getBaseConfig();
        } else if (block.chainid == SEPOLIA_CHAIN_ID) {
            activeNetworkConfig = getSepoliaConfig();
        } else if (block.chainid == BASE_SEPOLIA_CHAIN_ID) {
            activeNetworkConfig = getBaseSepoliaConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilConfig();
        }
        _initializeTokenConfigs();
    }

    function getMainnetConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            // Asset addresses
            weth: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            usdc: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
            wbtc: 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599,
            // Oracle addresses
            ethUsdOracle: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419,
            btcUsdOracle: 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c,
            usdcUsdOracle: 0xb2A824043730FE05F3DA2efaFa1CBbe83fa548D6,
            // Pool parameters
            defaultPower: 2e18,
            defaultAdjustRate: 0.001e18,
            defaultHalfTime: 2592000e18, // 30 days
            defaultInitialLiq: 0.1 ether
        });
    }

    function getBaseConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            // Asset addresses
            weth: 0x4200000000000000000000000000000000000006, //1_1
            usdc: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913, //1_1
            wbtc: 0x236aa50979D5f3De3Bd1Eeb40E81137F22ab794b,
            // Oracle addresses
            ethUsdOracle: 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70,
            btcUsdOracle: 0x64c911996D3c6aC71f9b455B1E8E7266BcbD848F,
            usdcUsdOracle: 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B,
            // Pool parameters
            defaultPower: 2e18,
            defaultAdjustRate: 0.001e18,
            defaultHalfTime: 2592000e18, // 30 days
            defaultInitialLiq: 0.1 ether
        });
    }

    function getSepoliaConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            // Asset addresses - Sepolia testnet
            weth: 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9,
            usdc: 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8,
            wbtc: 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599,
            // Oracle addresses - Sepolia testnet
            ethUsdOracle: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            btcUsdOracle: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            usdcUsdOracle: 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E, //1_1
            // Pool parameters
            defaultPower: 2e18,
            defaultAdjustRate: 0.001e18,
            defaultHalfTime: 2592000e18, // 30 days
            defaultInitialLiq: 0.1 ether
        });
    }

    function getBaseSepoliaConfig() public returns (NetworkConfig memory) {
        vm.startBroadcast();

        // Deploy mock tokens with appropriate decimals
        MockERC20All mockWeth = new MockERC20All("Wrapped Ether", "WETH", 18, FAUCET_ADDRESS);
        MockERC20All mockUsdc = new MockERC20All("USD Coin", "USDC", 6, FAUCET_ADDRESS);
        MockERC20All mockWbtc = new MockERC20All("Wrapped Bitcoin", "WBTC", 8, FAUCET_ADDRESS);

        // // Mint tokens to faucet address
        // mockWeth.mint(FAUCET_ADDRESS, FAUCET_AMOUNT);
        // mockUsdc.mint(FAUCET_ADDRESS, FAUCET_AMOUNT / 1e12); // Adjust for 6 decimals
        // mockWbtc.mint(FAUCET_ADDRESS, FAUCET_AMOUNT / 1e10); // Adjust for 8 decimals

        vm.stopBroadcast();
        return NetworkConfig({
            // Asset addresses - Base Sepolia testnet
            weth: address(mockWeth),
            usdc: address(mockUsdc),
            wbtc: address(mockWbtc),
            // Oracle addresses - Base Sepolia testnet
            ethUsdOracle: 0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1, //1_1
            btcUsdOracle: 0x0FB99723Aee6f420beAD13e6bBB79b7E6F034298, // 1_1
            usdcUsdOracle: 0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165, //1_1
            // Pool parameters
            defaultPower: 2e18,
            defaultAdjustRate: 0.001e18,
            defaultHalfTime: 2592000e18, // 30 days
            defaultInitialLiq: 0.0001 ether
        });
    }

    function getOrCreateAnvilConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.weth != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();

        // Deploy mock tokens
        MockERC20All mockWeth = new MockERC20All("Wrapped Ether", "WETH", 18, address(msg.sender));
        MockERC20All mockUsdc = new MockERC20All("USD Coin", "USDC", 6, address(msg.sender));
        MockERC20All mockWbtc = new MockERC20All("Wrapped Bitcoin", "WBTC", 8, address(msg.sender));

        // Deploy mock price feeds
        MockV3Aggregator ethUsdFeed = new MockV3Aggregator(8, 2000e8); // $2000
        MockV3Aggregator btcUsdFeed = new MockV3Aggregator(8, 40000e8); // $40000
        MockV3Aggregator usdcUsdFeed = new MockV3Aggregator(8, 1e8); // $1

        vm.stopBroadcast();

        return NetworkConfig({
            // Mock asset addresses
            weth: address(mockWeth),
            usdc: address(mockUsdc),
            wbtc: address(mockWbtc),
            // Mock oracle addresses
            ethUsdOracle: address(ethUsdFeed),
            btcUsdOracle: address(btcUsdFeed),
            usdcUsdOracle: address(usdcUsdFeed),
            // Pool parameters
            defaultPower: 2e18,
            defaultAdjustRate: 0.001e18,
            defaultHalfTime: 2592000e18, // 30 days
            defaultInitialLiq: 0.1 ether
        });
    }

    function _initializeTokenConfigs() internal {
        // WETH Configuration
        tokenConfigs["WETH"] = TokenConfig({
            name: "Wrapped Ether",
            symbol: "WETH",
            decimals: 18,
            addr: activeNetworkConfig.weth,
            oracle: activeNetworkConfig.ethUsdOracle
        });

        // USDC Configuration
        tokenConfigs["USDC"] = TokenConfig({
            name: "USD Coin",
            symbol: "USDC",
            decimals: 6,
            addr: activeNetworkConfig.usdc,
            oracle: activeNetworkConfig.usdcUsdOracle
        });

        // WBTC Configuration
        tokenConfigs["WBTC"] = TokenConfig({
            name: "Wrapped Bitcoin",
            symbol: "WBTC",
            decimals: 8,
            addr: activeNetworkConfig.wbtc,
            oracle: activeNetworkConfig.btcUsdOracle
        });
    }

    // Helper functions to get token configurations
    function getTokenConfig(string memory symbol) public view returns (TokenConfig memory) {
        return tokenConfigs[symbol];
    }

    // Helper function to check if we're on a testnet
    function isTestnet() public view returns (bool) {
        return block.chainid == SEPOLIA_CHAIN_ID || block.chainid == BASE_SEPOLIA_CHAIN_ID || block.chainid == 31337; // Anvil
    }

    // Helper function to get default pool parameters for a specific token
    function getPoolParams(string memory tokenSymbol)
        public
        view
        returns (address token, address oracle, uint256 power, uint256 adjustRate, uint256 halfTime, uint256 initialLiq)
    {
        TokenConfig memory tokenConfig = getTokenConfig(tokenSymbol);
        return (
            tokenConfig.addr,
            tokenConfig.oracle,
            activeNetworkConfig.defaultPower,
            activeNetworkConfig.defaultAdjustRate,
            activeNetworkConfig.defaultHalfTime,
            activeNetworkConfig.defaultInitialLiq
        );
    }
}
