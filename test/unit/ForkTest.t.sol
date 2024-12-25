// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IWETH9} from "./../interfaces/IWETH9.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {Errors} from "../../src/utils/Errors.sol";
import {Utilities} from "./../utils/Utilities.sol";
import {UD60x18 as UD, ud} from "@prb/math/UD60x18.sol";
import {PotentiaPool} from "../../src/PotentiaPool.sol";
import {PotentiaFactory} from "../../src/PotentiaFactory.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {Test, console, stdStorage, StdStorage} from "forge-std/Test.sol";
import {SD59x18 as SD, sd, intoUD60x18 as toUD} from "@prb/math/SD59x18.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {UD60x18 as UD, ud, intoSD59x18 as toSD, intoUint256 as toUint} from "@prb/math/UD60x18.sol";

contract ForkTest is Test {
    using stdStorage for StdStorage;

    Utilities public utilities;
    address payable[] internal users;
    PotentiaPool public pool;
    PotentiaFactory public factory;

    MockERC20 public underlying;

    MockV3Aggregator priceFeed;

    // address public wethOracleSepolia = 0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1;
    uint256 k = 3e18;

    address private protocol = makeAddr("PROTOCOL");

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("eth"));
        utilities = new Utilities();
        address payable[] memory _users = utilities.createUsers(4);
        users = _users;

        vm.startPrank(users[0]);

        underlying = new MockERC20(18);

        priceFeed = new MockV3Aggregator(uint8(8), int256(2500e8));

        factory = new PotentiaFactory();

        underlying.mint(users[0], 10_000_000 ether);
        underlying.mint(users[1], 10_000_000 ether);
        underlying.mint(users[2], 10_000_000 ether);
        underlying.mint(users[3], 10_000_000 ether);
        vm.stopPrank();

        vm.startPrank(users[1]);

        // uint256 adjustRate = 0.25e18;
        uint256 adjustRate = 0.001e18;

        uint256 initialLiq = 0.0001 ether;
        uint256 halfTime = 2592000e18;

        // AggregatorV3Interface priceFeed = AggregatorV3Interface(wethOracleSepolia);
        pool =
            PotentiaPool(factory.createPool(address(underlying), k, adjustRate, users[1], halfTime, address(priceFeed)));

        underlying.approve(address(pool), initialLiq);
        pool.initializePool(initialLiq);

        vm.stopPrank();
    }

    function test_FactorySanity() external view {
        assertEq(factory.poolCount(), 1);
        assertEq(factory.poolExists(address(pool)), true);
        address aPool = factory.poolOwnerMap(users[1], 0);
        assertEq(aPool, address(pool));
    }

    function test_PoolSanity() external view {
        assertEq(pool.alpha(), 0.00005 ether);
        assertEq(pool.beta(), 0.00005 ether);
        assertEq(pool.reserve(), 0.0001 ether);
        assertEq(toUint(pool.initLongQty()), 0.00005 ether);
        assertEq(toUint(pool.initShortQty()), 0.00005 ether);
        assertEq(pool.hasRole(DEFAULT_ADMIN_ROLE, users[1]), true);
        assertEq(underlying.balanceOf(address(pool)), 0.0001 ether);
        assertEq(pool.lpPToken().balanceOf(users[0]), 0);
        assertEq(pool.longPToken().balanceOf(address(pool)), 0.00005 ether);
        assertEq(pool.shortPToken().balanceOf(address(pool)), 0.00005 ether);
    }

    function test_ProtocolRole() external {
        address newProtocol = makeAddr("NEW_PROTOCOL");
        vm.startPrank(users[1]);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, users[1], keccak256("PROTOCOL")
            )
        );
        pool.grantProtocol(newProtocol);
        vm.stopPrank();

        vm.startPrank(users[0]);
        assertEq(pool.protocol(), users[0]);
        pool.grantProtocol(newProtocol);
        assertEq(pool.protocol(), newProtocol);

        vm.stopPrank();
    }

    function test_LongCondition() public view returns (UD longCondition) {
        UD R = _normAmt(pool.reserve());
        uint256 a = pool.alpha();
        UD base = R / ud(2 * a);
        UD one_by_k = ud(1e18) / ud(k);
        longCondition = base.pow(one_by_k);
        assertEq(toUint(pool.longCondition()), toUint(longCondition));
    }

    function test_ShortCondition() external view returns (UD shortCondition) {
        UD R = _normAmt(pool.reserve());
        uint256 b = pool.beta();
        UD base = ud(2 * b) / R;
        UD one_by_k = ud(1e18) / ud(k);
        shortCondition = base.pow(one_by_k);
        assertEq(toUint(pool.shortCondition()), toUint(shortCondition));
    }

    function test_LongPayoff() public view returns (UD expectedLongPayoff) {
        (UD x,) = pool.getX();
        UD R = _normAmt(pool.reserve());
        uint256 a = pool.alpha();
        UD longCondition = test_LongCondition();

        if (x <= longCondition) {
            expectedLongPayoff = ud(a) * x.pow(ud(k));
        } else {
            expectedLongPayoff = R - (R.pow(ud(2e18)) / (ud(4 * a) * x.pow(ud(k))));
        }

        assertEq(toUint(pool.longPayoff(x)), toUint(expectedLongPayoff));
    }

    function test_ShortPayoff() public view returns (UD expectedShortPayoff) {
        (UD x,) = pool.getX();
        UD R = _normAmt(pool.reserve());
        uint256 b = pool.beta();
        UD shortCondition = pool.shortCondition();

        if (x >= shortCondition) {
            expectedShortPayoff = ud(b) / x.pow(ud(k));
        } else {
            expectedShortPayoff = R - ((R.pow(ud(2e18)) * x.pow(ud(k))) / ud(4 * b));
        }

        assertEq(toUint(pool.shortPayoff(x)), toUint(expectedShortPayoff));
    }

    function test_Liquidity() public view returns (UD liquidity) {
        UD R = _normAmt(pool.reserve());
        UD longPayoff = test_LongPayoff();
        UD shortPayoff = test_ShortPayoff();
        liquidity = R - longPayoff - shortPayoff;
        console.log("liq = %s", toUint(liquidity));
        (UD x,) = pool.getX();
        assertEq(toUint(pool.liquidity(x)), toUint(liquidity));
    }

    function test_AddLiquidityFork() public {
        uint256 initialReserve = pool.reserve();
        uint256 initialLpTokenSupply = pool.lpPToken().totalSupply();
        uint256 initialLpTokenBalance = pool.lpPToken().balanceOf(users[1]);

        uint256 amt = 5 ether;

        vm.startPrank(users[1]);
        underlying.approve(address(pool), amt);
        pool.addLiquidity(amt);
        vm.stopPrank();

        uint256 finalReserve = pool.reserve();
        uint256 finalLpTokenSupply = pool.lpPToken().totalSupply();
        uint256 finalLpTokenBalance = pool.lpPToken().balanceOf(users[1]);

        UD mintedLpToken = _normAmt(amt);

        assertEq(finalReserve, initialReserve + amt);
        assertEq(finalLpTokenSupply, initialLpTokenSupply + toUint(mintedLpToken));
        assertEq(finalLpTokenBalance, initialLpTokenBalance + toUint(mintedLpToken));
    }

    function test_RemoveLiquidity() public {
        _addLiq(users[1], 5 ether);

        uint256 initialReserve = pool.reserve();
        uint256 initialUnderlyingBalance = underlying.balanceOf(users[1]);
        uint256 initialLpShares = pool.lpPToken().balanceOf(users[1]);
        UD redeemAmt = ud(initialLpShares) * test_Liquidity() / ud(pool.lpPToken().totalSupply());

        vm.startPrank(users[1]);
        pool.removeLiquidity(initialLpShares);
        vm.stopPrank();

        uint256 finalReserve = pool.reserve();
        uint256 finalUnderlyingBalance = underlying.balanceOf(users[1]);
        uint256 finalLpShares = pool.lpPToken().balanceOf(users[1]);

        assertEq(finalLpShares, 0);
        assertEq(initialReserve, finalReserve + toUint(redeemAmt));
        assertEq(finalUnderlyingBalance, initialUnderlyingBalance + toUint(redeemAmt));
    }

    // function test_MiscTest() public {
    //     UD x = pool.getX();
    //     console.log("nR %s", toUint(pool.nR()));
    //     console.log("alpha %s", pool.alpha());
    //     console.log("beta %s", pool.beta());
    //     console.log("long payoff %s", toUint(pool.longPayoff(x)));
    //     console.log("short payoff %s", toUint(pool.shortPayoff(x)));
    //     console.log("long supply %s", pool.longPToken().totalSupply());
    //     console.log("short supply %s", pool.shortPToken().totalSupply());
    //     console.log("long token price %s", _positionValue(true, 1e18));
    //     console.log("short token price %s \n", _positionValue(false, 1e18));

    //     console.log("###### going into the future by 10000 seconds and changing the time from $2500 to $3000 ###### \n");
    //     vm.warp(10000);
    //     priceFeed.updateAnswer(int256(3000e8));

    //     console.log("Open a 50 ether long position\n");

    //     vm.startPrank(users[2]);
    //     underlying.approve(address(pool), 50 ether);
    //     pool.openPosition(50 ether, true);
    //     vm.stopPrank();

    //     // x = pool.getX();
    //     // console.log("nR %s", toUint(pool.nR()));
    //     // console.log("alpha %s", pool.alpha());
    //     // console.log("beta %s", pool.beta());
    //     // console.log("long payoff %s", toUint(pool.longPayoff(x)));
    //     // console.log("short payoff %s", toUint(pool.shortPayoff(x)));
    //     // console.log("long supply %s", pool.longPToken().totalSupply());
    //     // console.log("short supply %s", pool.shortPToken().totalSupply());
    //     // console.log("long token price %s", _positionValue(true, 1e18));
    //     // console.log("short token price %s \n", _positionValue(false, 1e18));

    //     // console.log("after price change\n");
    //     // x = pool.getX();
    //     // console.log("nR %s", toUint(pool.nR()));
    //     // console.log("alpha %s", pool.alpha());
    //     // console.log("beta %s", pool.beta());
    //     // console.log("long payoff %s", toUint(pool.longPayoff(x)));
    //     // console.log("short payoff %s", toUint(pool.shortPayoff(x)));
    //     // console.log("long supply %s", pool.longPToken().totalSupply());
    //     // console.log("short supply %s", pool.shortPToken().totalSupply());
    //     // console.log("long token price %s", _positionValue(true, 1e18));
    //     // console.log("short token price %s \n", _positionValue(false, 1e18));
    // }

    function test_OpenSingleLongPosition() public {
        vm.startPrank(users[2]);
        vm.warp(1753597518);

        console.log("---OPEN A 10 ETHER LONG POSITION---\n");

        underlying.approve(address(pool), 10 ether);

        uint256 initialGas = gasleft();
        pool.openPosition(10 ether, true);
        uint256 finalGas = gasleft();
        vm.stopPrank();

        console.log("gas used %s", initialGas - finalGas);
    }

    function test_OpenLongPosition() public {
        (UD x,) = pool.getX();
        uint256 liqInitial = toUint(pool.liquidity(x));
        uint256 phi = toUint(pool.longPayoff(x));
        uint256 psi = toUint(pool.shortPayoff(x));
        console.log("long condition = %s", toUint(pool.longCondition()));
        console.log("short condition = %s", toUint(pool.shortCondition()));

        console.log("Liquidity = %s, phi = %s, psi = %s\n", liqInitial, phi, psi);

        _addLiq(users[1], 8 ether);

        (x,) = pool.getX();
        liqInitial = toUint(pool.liquidity(x));
        phi = toUint(pool.longPayoff(x));
        psi = toUint(pool.shortPayoff(x));

        console.log("long condition = %s", toUint(pool.longCondition()));
        console.log("short condition = %s", toUint(pool.shortCondition()));
        console.log("Liquidity = %s, phi = %s, psi = %s\n", liqInitial, phi, psi);

        vm.startPrank(users[2]);
        vm.warp(1753597518);

        UD fee = (ud(10 ether) * ud(1e18)) / ud(100e18);
        uint256 expectedFreeGrowth = toUint(fee);

        console.log("---OPEN A 10 ETHER LONG POSITION---\n");

        underlying.approve(address(pool), 10 ether);
        pool.openPosition(10 ether, true);

        (x,) = pool.getX();
        uint256 liqFinal = toUint(pool.liquidity(x));
        phi = toUint(pool.longPayoff(x));
        psi = toUint(pool.shortPayoff(x));
        console.log("Liquidity = %s, phi = %s, psi = %s\n", liqFinal, phi, psi);

        uint256 longValue = _positionValue(true, pool.longPToken().balanceOf(users[2]));
        console.log("Long Value = %s\n", longValue);

        assertLt(longValue, 10 ether);

        uint256 feeGrwth = toUint(pool.feeGrowth());
        assertEq(expectedFreeGrowth, feeGrwth);

        vm.warp(1753683918);

        underlying.approve(address(pool), 10 ether);
        pool.openPosition(10 ether, true);

        (x,) = pool.getX();
        liqFinal = toUint(pool.liquidity(x));
        phi = toUint(pool.longPayoff(x));
        psi = toUint(pool.shortPayoff(x));
        console.log("Liquidity = %s, phi = %s, psi = %s\n", liqFinal, phi, psi);

        longValue = _positionValue(true, pool.longPToken().balanceOf(users[2]));
        console.log("Long Value = %s\n", longValue);

        vm.stopPrank();

        vm.startPrank(users[0]);
        uint256 protocolBal = underlying.balanceOf(users[0]);
        pool.withdraw();
        assertEq(underlying.balanceOf(users[0]), protocolBal + 0.2 ether);
        vm.stopPrank();
    }

    function test_OpenAnotherLongPos() public {
        vm.startPrank(users[2]);

        uint256 longTokenSupply = pool.longPToken().totalSupply();
        console.log("long token supply %s", longTokenSupply);

        vm.warp(1753597518);

        underlying.approve(address(pool), 10 ether);
        pool.openPosition(10 ether, true);

        uint256 longValue = _positionValue(true, pool.longPToken().balanceOf(users[2]));
        console.log("Long Value = %s\n", longValue);

        assertLt(longValue, 10 ether);

        vm.stopPrank();
    }

    function test_OpenLongMinPos() public {
        vm.startPrank(users[2]);

        uint256 longTokenSupply = pool.longPToken().totalSupply();
        console.log("long supply %s", longTokenSupply);

        vm.warp(1753597518);

        underlying.approve(address(pool), 101);
        vm.expectRevert(Errors.MinAmt.selector);
        pool.openPosition(100, true);

        pool.openPosition(101, true);

        uint256 longValue = _positionValue(true, pool.longPToken().balanceOf(users[2]));
        console.log("Long Value = %s\n", longValue);

        assertLt(longValue, 101);

        UD feeGrowth = pool.feeGrowth();
        console.log(toUint(feeGrowth));

        vm.stopPrank();
    }

    function test_CloseLongPosition() public {
        test_OpenLongPosition();

        (UD x,) = pool.getX();
        uint256 phi = toUint(pool.longPayoff(x));

        vm.warp(1753770318);

        vm.startPrank(users[2]);

        uint256 initialLongBalance = pool.longPToken().balanceOf(users[2]);
        uint256 initialLongSupply = pool.longPToken().totalSupply();
        uint256 initialUnderlyingBalance = underlying.balanceOf(users[2]);

        uint256 redeemAmt = (phi * initialLongBalance) / initialLongSupply;

        pool.closePosition(initialLongBalance, true);

        uint256 finalLongBalance = pool.longPToken().balanceOf(users[2]);
        uint256 finalLongSupply = pool.longPToken().totalSupply();
        uint256 finalUnderlyingBalance = underlying.balanceOf(users[2]);

        assertLe(finalUnderlyingBalance, initialUnderlyingBalance + redeemAmt);
        assertEq(finalLongSupply, initialLongSupply - initialLongBalance);
        assertEq(finalLongBalance, 0);

        vm.stopPrank();
    }

    function test_OpenShortPosition() public {
        (UD x,) = pool.getX();
        console.log("Initial long payoff: %s", toUint(pool.longPayoff(x)));
        console.log("Initial short payoff: %s", toUint(pool.shortPayoff(x)));
        console.log("timestamp %s", block.timestamp);

        vm.warp(1753424718);
        _addLiq(users[1], 10 ether);

        (x,) = pool.getX();
        console.log("Initial phi: %s", toUint(pool.longPayoff(x)));
        console.log("Initial psi: %s", toUint(pool.shortPayoff(x)));

        (x,) = pool.getX();
        uint256 lpValue = toUint(pool.liquidity(x));
        console.log("liquidity %s", lpValue);
        uint256 phi = toUint(pool.longPayoff(x));
        uint256 psi = toUint(pool.shortPayoff(x));
        console.log("phi = %s, psi = %s", phi, psi);
        console.log("long condition %s", toUint(pool.longCondition()));
        console.log("short condition = %s", toUint(pool.shortCondition()));

        vm.startPrank(users[2]);

        vm.warp(1753511118);

        console.log("OPENING A SHORT POSITION \n\n");

        UD fee = (ud(5 ether) * ud(1e18)) / ud(100e18);
        uint256 expectedFreeGrowth = toUint(fee);
        console.log("feeGrowth %s", expectedFreeGrowth);

        underlying.approve(address(pool), 5 ether);
        pool.openPosition(5 ether, false);

        console.log("long condition %s", toUint(pool.longCondition()));
        console.log("short condition = %s", toUint(pool.shortCondition()));

        (x,) = pool.getX();
        uint256 lpValue1 = toUint(pool.liquidity(x));
        console.log("liquidity %s", lpValue1);

        phi = toUint(pool.longPayoff(x));
        psi = toUint(pool.shortPayoff(x));
        console.log("phi = %s, psi = %s", phi, psi);

        uint256 user2Bal = pool.shortPToken().balanceOf(users[2]);
        console.log("NUMBER OF SHORT TOKENS USER2 RECEIVED = %s", user2Bal);

        uint256 shortValue = _positionValue(false, pool.shortPToken().balanceOf(users[2]));
        console.log("shortValue = %s", shortValue);

        assertLt(shortValue, 5 ether);
        assertEq(expectedFreeGrowth, toUint(pool.feeGrowth()));

        vm.stopPrank();

        vm.startPrank(users[0]);
        uint256 protocolBal = underlying.balanceOf(users[0]);
        pool.withdraw();
        assertEq(underlying.balanceOf(users[0]), protocolBal + expectedFreeGrowth);
        vm.stopPrank();
    }

    function test_CloseShortPosition() public {
        test_OpenShortPosition();

        console.log("Closing the Short Position\n");

        (UD x,) = pool.getX();
        uint256 liqInitial = toUint(pool.liquidity(x));
        uint256 phi = toUint(pool.longPayoff(x));
        uint256 psi = toUint(pool.shortPayoff(x));
        uint256 r = toUint(pool.nR());
        console.log("Reserve = %s", r);
        console.log("Liquidity = %s, phi = %s, psi = %s", liqInitial, phi, psi);

        vm.warp(1753597518);

        vm.startPrank(users[2]);

        uint256 initialShortBalance = pool.shortPToken().balanceOf(users[2]);
        uint256 initialShortSupply = pool.shortPToken().totalSupply();
        uint256 initialUnderlyingBalance = underlying.balanceOf(users[2]);

        uint256 redeemAmt = (psi * initialShortBalance) / initialShortSupply;
        console.log("REDEEM AMT = %s", redeemAmt);

        console.log("---CLOSE A 100 ETHER SHORT POSITION---\n");
        pool.closePosition(initialShortBalance, false);

        uint256 finalShortBalance = pool.shortPToken().balanceOf(users[2]);
        uint256 finalShortSupply = pool.shortPToken().totalSupply();
        uint256 finalUnderlyingBalance = underlying.balanceOf(users[2]);

        (x,) = pool.getX();
        phi = toUint(pool.longPayoff(x));
        psi = toUint(pool.shortPayoff(x));
        r = toUint(pool.nR());
        console.log("Reserve = %s", r);
        console.log("Liquidity = %s, phi = %s, psi = %s", liqInitial, phi, psi);

        assertLe(finalUnderlyingBalance, initialUnderlyingBalance + redeemAmt);
        assertEq(finalShortSupply, initialShortSupply - initialShortBalance);
        assertEq(finalShortBalance, 0);

        vm.stopPrank();
    }

    function _addLiq(address _user, uint256 _amt) internal {
        vm.startPrank(_user);
        underlying.approve(address(pool), _amt);
        pool.addLiquidity(_amt);
        vm.stopPrank();
    }

    function _normalizeDecimal(uint256 tokenAmount, uint256 tokenDecimal, uint256 standard)
        internal
        pure
        returns (uint256)
    {
        if (tokenDecimal > standard) {
            return tokenAmount / (10 ** (tokenDecimal - standard));
        } else if (tokenDecimal < standard) {
            return tokenAmount * (10 ** (standard - tokenDecimal));
        } else {
            return tokenAmount;
        }
    }

    function _normAmt(uint256 _x) internal pure returns (UD) {
        return ud(_normalizeDecimal(_x, 18, 18));
    }

    function _positionValue(bool flag, uint256 amt) public view returns (uint256 p) {
        (UD x,) = pool.getX();
        if (flag) {
            p = toUint(pool.longPayoff(x) * ud(amt) / ud(pool.longPToken().totalSupply()));
        } else {
            p = toUint((pool.shortPayoff(x) * ud(amt)) / ud(pool.shortPToken().totalSupply()));
        }
    }
}
