// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Decimals} from "./interfaces/IERC20Decimals.sol";

contract Faucet {
    // constructor() Ownable(msg.sender) {}

    function faucetBalance(address _asset) external view returns (uint256 balance) {
        balance = IERC20Decimals(_asset).balanceOf(address(this));
    }

    function mintAsset(address _asset, address _to) external {
        require(_asset != address(0), "Invalid asset address");
        require(_to != address(0), "Invalid recipient address");

        uint8 decimals = IERC20Decimals(_asset).decimals();

        uint256 amt = 50 * (10 ** decimals);
        IERC20Decimals(_asset).transfer(_to, amt);
    }
}
