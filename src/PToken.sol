// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract PToken is ERC20, Ownable {
    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) Ownable(msg.sender) {}

    function mint(address _to, uint256 _amt) external virtual onlyOwner {
        _mint(_to, _amt);
    }

    function burn(address _from, uint256 _amt) external virtual onlyOwner {
        _burn(_from, _amt);
    }
}
