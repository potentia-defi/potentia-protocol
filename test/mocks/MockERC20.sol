// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MockERC20 is ERC20, Ownable {
    uint8 public d = 18;

    constructor(uint8 _d) ERC20("MyToken", "MTK") Ownable(msg.sender) {
        d = _d;
        _mint(msg.sender, 1000000 * 10 ** decimals());
    }

    function mint(address _to, uint256 _amount) external onlyOwner {
        _mint(_to, _amount);
    }

    function decimals() public view override returns (uint8) {
        return d;
    }
}
