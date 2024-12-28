// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Script} from "forge-std/Script.sol";

contract MockERC20All is ERC20 {
    uint8 private _decimals;
    uint256 public constant MINT_AMOUNT = 1000000000 * 10 ** 18; // 1 billion tokens

    constructor(string memory name, string memory symbol, uint8 decimals_, address whom) ERC20(name, symbol) {
        _decimals = decimals_;
        // Mint initial supply to deployer
        _mint(whom, MINT_AMOUNT);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    // Function to mint tokens to any address (only for testing)
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    // Function to burn tokens from any address (only for testing)
    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}
