// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {PotentiaPool} from "../../src/PotentiaPool.sol";
import {PotentiaFactory} from "../../src/PotentiaFactory.sol";
import {normAmt, denormAmt} from "../../src/utils/PotentiaUtils.sol";
import {UD60x18 as UD, ud} from "@prb/math/UD60x18.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";
import {PotentiaFactory} from "../../src/PotentiaFactory.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Utilities} from "./../utils/Utilities.sol";
import {MockV3Aggregator} from "./../mocks/MockV3Aggregator.sol";
import {MockERC20} from "./../mocks/MockERC20.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {UD60x18 as UD, ud, intoSD59x18 as toSD, intoUint256 as toUint} from "@prb/math/UD60x18.sol";

contract LongShortFuzz is Test {
    using stdStorage for StdStorage;

    Utilities public utilities;
    address payable[] internal users;
    PotentiaPool public pool;
    PotentiaFactory public factory;
    MockERC20 public underlying;
    uint256 k = 3e18;

    address private protocol = makeAddr("PROTOCOL");

    function setUp() public {
        utilities = new Utilities();
        address payable[] memory _users = utilities.createUsers(10);
        users = _users;

        vm.startPrank(users[0]);

        underlying = new MockERC20(18);

        MockV3Aggregator priceFeed = new MockV3Aggregator(uint8(8), int256(3000e8));

        factory = new PotentiaFactory();

        underlying.mint(users[0], 10_000_000 ether);
        underlying.mint(users[1], 10_000_000 ether);
        underlying.mint(users[2], 10_000_000 ether);
        underlying.mint(users[3], 10_000_000 ether);
        underlying.mint(users[4], 10_000_000 ether);

        uint256 adjustRate = 0.25e18;

        uint256 initialLiq = 0.0001 ether;

        underlying.mint(users[0], initialLiq);

        pool = PotentiaPool(factory.createPool(address(underlying), k, adjustRate, users[0], 5e18, address(priceFeed)));

        underlying.approve(address(pool), initialLiq);
        pool.initializePool(initialLiq);

        vm.stopPrank();
    }

    function testFuzz_LongPayoff(uint256 kk, uint256 alpha, uint256 beta, uint256 adjustRate, uint256 iL) public {
        kk = bound(kk, 2e18, 100e18);
        alpha = bound(alpha, 1e15, 100e18);
        beta = bound(beta, 1e15, 100e18);
        adjustRate = bound(adjustRate, 1e15, 100e18);
        iL = bound(iL, 1 ether, 10_000 ether);

        vm.startPrank(users[0]);
        (UD x,) = pool.getX();
        UD R = pool.nR();

        // manipulat alpha and beta in the pool storage.
        stdstore.target(address(pool)).sig("alpha()").checked_write(alpha);

        uint256 expected;
        uint256 target = pool.longPayoff(x).intoUint256();
        if (x <= pool.longCondition()) {
            expected = (ud(alpha) * x.pow(ud(kk))).intoUint256();
            assertEq(target, expected);
        } else {
            expected = (R - (R.pow(ud(2e18)) / (ud(4 * alpha) * x.pow(ud(kk))))).intoUint256();
            assertEq(target, expected);
        }

        vm.stopPrank();
    }

    function testFuzz_ShortPayoff(uint256 kk, uint256 alpha, uint256 beta, uint256 adjustRate) public {
        kk = bound(kk, 2e18, 100e18);
        alpha = bound(alpha, 1e15, 100e18);
        beta = bound(beta, 1e15, 100e18);
        adjustRate = bound(adjustRate, 1e15, 100e18);

        vm.startPrank(users[0]);
        (UD x,) = pool.getX();
        UD R = pool.nR();

        // manipulat alpha and beta in the pool storage.
        stdstore.target(address(pool)).sig("beta()").checked_write(beta);

        uint256 expected;
        uint256 target = pool.shortPayoff(x).intoUint256();
        if (x >= pool.shortCondition()) {
            expected = (ud(beta) / (x.pow(ud(kk)))).intoUint256();
        } else {
            expected = (R - (R.pow(ud(2e18)) * x.pow(ud(kk)) / ud(4 * pool.beta()))).intoUint256();
        }

        assertEq(target, expected);

        vm.stopPrank();
    }

    function testFuzz_AddRemoveLiquidity(uint256 amount) public {
        amount = bound(amount, 1 ether, 10_000 ether);

        vm.startPrank(users[0]);
        (UD x,) = pool.getX();
        // UD R = pool.nR();

        UD lpSupply = ud(pool.lpPToken().totalSupply());
        uint256 underlyingPrecision = pool.underlyingPrecision();

        UD lpAmount = lpSupply == ud(0)
            ? normAmt(amount, underlyingPrecision)
            : normAmt(amount, underlyingPrecision) * lpSupply / pool.liquidity(x);
        uint256 target = lpAmount.intoUint256();

        // add liquidity
        underlying.approve(address(pool), amount);
        pool.addLiquidity(amount);

        uint256 expected = pool.lpPToken().balanceOf(users[0]);

        assertEq(target, expected);

        // fuzz for remove liquidity
        uint256 shares = expected;
        UD redeemAmountUD = (ud(shares) * pool.liquidity(x)) / ud(pool.lpPToken().totalSupply());
        uint256 redeemAmount = toUint(denormAmt(toUint(redeemAmountUD), underlyingPrecision));

        uint256 initialiBalance = underlying.balanceOf(users[0]);
        pool.lpPToken().approve(address(pool), shares);
        pool.removeLiquidity(shares);
        uint256 finalBalance = underlying.balanceOf(users[0]);

        assertEq(finalBalance - initialiBalance, redeemAmount);

        vm.stopPrank();
    }

    function testFuzz_AddRemoveLiquidityAB(uint256 amount) public {
        amount = bound(amount, 1 ether, 10_000 ether);

        vm.startPrank(users[0]);
        (UD x,) = pool.getX();
        // UD R = pool.nR();

        UD lpSupply = ud(pool.lpPToken().totalSupply());
        uint256 underlyingPrecision = pool.underlyingPrecision();

        UD lpAmount = lpSupply == ud(0)
            ? normAmt(amount, underlyingPrecision)
            : normAmt(amount, underlyingPrecision) * lpSupply / pool.liquidity(x);
        uint256 target = lpAmount.intoUint256();

        // add liquidity
        underlying.approve(address(pool), amount);
        pool.addLiquidity(amount);

        uint256 expected = pool.lpPToken().balanceOf(users[0]);

        assertEq(target, expected);

        // fuzz for remove liquidity
        uint256 shares = expected;
        UD redeemAmountUD = (ud(shares) * pool.liquidity(x)) / ud(pool.lpPToken().totalSupply());
        uint256 redeemAmount = toUint(denormAmt(toUint(redeemAmountUD), underlyingPrecision));

        uint256 initialiBalance = underlying.balanceOf(users[0]);
        pool.lpPToken().approve(address(pool), shares);
        pool.removeLiquidity(shares);
        uint256 finalBalance = underlying.balanceOf(users[0]);

        assertEq(finalBalance - initialiBalance, redeemAmount);

        vm.stopPrank();
    }

    function testFuzz_OpenLongPosition(uint256 amt) public {
        amt = bound(amt, 101, 10_000 ether);

        (UD x,) = pool.getX();
        uint256 liqInitial = toUint(pool.liquidity(x));
        console.log("liq initial %s", liqInitial);

        vm.startPrank(users[2]);
        vm.warp(2);

        UD fee = (ud(amt) * ud(1e18)) / ud(100e18);
        uint256 expectedFreeGrowth = toUint(fee);

        underlying.approve(address(pool), amt);
        pool.openPosition(amt, true);

        (x,) = pool.getX();
        uint256 liqFinal = toUint(pool.liquidity(x));
        console.log("liq final %s", liqFinal);

        uint256 longValue = _positionValue(true, pool.longPToken().balanceOf(users[2]));
        console.log("Long Value = %s\n", longValue);

        assertLt(longValue, amt);

        uint256 feeGrwth = toUint(pool.feeGrowth());
        assertEq(expectedFreeGrowth, feeGrwth);

        vm.stopPrank();

        vm.startPrank(users[0]);
        uint256 protocolBal = underlying.balanceOf(users[0]);
        pool.withdraw();
        assertEq(underlying.balanceOf(users[0]), protocolBal + expectedFreeGrowth);
        vm.stopPrank();
    }

    function _positionValue(bool flag, uint256 amt) public view returns (uint256 p) {
        if (flag) {
            (UD x,) = pool.getX();
            p = toUint(pool.longPayoff(x) * ud(amt) / ud(pool.longPToken().totalSupply()));
        } else {
            (UD x,) = pool.getX();
            console.log("INSIDE POSITION VALUE  --- ");

            console.log("short payoff ", toUint(pool.shortPayoff(x)));
            console.log("total supply ", pool.shortPToken().totalSupply());
            console.log(" amt ", amt);
            p = toUint((pool.shortPayoff(x) * ud(amt)) / ud(pool.shortPToken().totalSupply()));
        }
    }

    function _addLiq(address _user, uint256 _amt) internal {
        vm.startPrank(_user);
        underlying.approve(address(pool), _amt);
        pool.addLiquidity(_amt);
        vm.stopPrank();
    }
}
