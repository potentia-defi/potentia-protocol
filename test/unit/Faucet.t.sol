// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import {MockERC20} from "../mocks/MockERC20.sol";
import {Utilities} from "./../utils/Utilities.sol";
import {Faucet} from "../../src/Faucet.sol";
import {Test, console, stdStorage, StdStorage} from "forge-std/Test.sol";

contract PotentiaPoolTest is Test {
    Utilities public utilities;
    address payable[] internal users;

    MockERC20 token0;
    MockERC20 token1;

    Faucet public faucet;

    function setUp() public {
        utilities = new Utilities();
        address payable[] memory _users = utilities.createUsers(10);
        users = _users;

        vm.startPrank(users[0]);

        token0 = new MockERC20(18);
        token1 = new MockERC20(8);

        token0.mint(users[0], 10_000_000e18);
        token1.mint(users[0], 10_000_000e8);

        faucet = new Faucet();

        token0.transfer(address(faucet), 1000e18);
        token1.transfer(address(faucet), 1000e8);

        vm.stopPrank();
    }

    function testFaucetBalance() external {
        uint256 token0Bal = token0.balanceOf(address(faucet));

        vm.prank(users[1]);
        faucet.mintAsset(address(token0), users[1]);

        uint256 token0Bal1 = token0.balanceOf(address(faucet));

        assertEq(token0Bal1, token0Bal - 50e18);

        uint256 token1Bal = token1.balanceOf(address(faucet));

        vm.prank(users[1]);
        faucet.mintAsset(address(token1), users[1]);

        uint256 token1Bal1 = token1.balanceOf(address(faucet));

        assertEq(token1Bal1, token1Bal - 50e8);
    }
}
