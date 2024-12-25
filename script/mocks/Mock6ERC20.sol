// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Mock6ERC20 is ERC20, Ownable {
    constructor() ERC20("US Dollar Circle", "USDC") Ownable(msg.sender) {
        _mint(msg.sender, 100_000_000 * 10 ** decimals());
    }

    function mint(address _to, uint256 _amount) external onlyOwner {
        _mint(_to, _amount);
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }
}
