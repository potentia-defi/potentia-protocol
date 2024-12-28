// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {Errors} from "./utils/Errors.sol";
import {PotentiaPool} from "./PotentiaPool.sol";
import {PotentiaUtils} from "./utils/PotentiaUtils.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract PotentiaFactory is ReentrancyGuard {
    uint256 public poolCount; // Pool counter
    address public protocol; // Protocol address

    mapping(address => bool) public poolExists; // Checks if pool exists or not
    mapping(address => address[] pools) public poolOwnerMap; // Mapping between pool and owner

    constructor() {
        protocol = msg.sender;
    }

    /// @notice This function deploys a new Potentia Pool
    function createPool(
        address underlying,
        uint256 power,
        uint256 adjustRate,
        address operator,
        uint256 halfTime,
        address oracle
    ) external nonReentrant returns (address) {
        PotentiaPool pool = new PotentiaPool(underlying, power, adjustRate, operator, halfTime, oracle, protocol);

        address poolAddr = address(pool);

        poolExists[poolAddr] = true;
        poolCount++;
        poolOwnerMap[msg.sender].push(poolAddr);
        emit PotentiaUtils.PoolCreated(poolAddr, msg.sender);

        return poolAddr;
    }
}
