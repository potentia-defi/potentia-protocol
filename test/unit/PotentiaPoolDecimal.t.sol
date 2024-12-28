// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import {IWETH9} from "./../interfaces/IWETH9.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {Errors} from "../../src/utils/Errors.sol";
import {Utilities} from "./../utils/Utilities.sol";
import {UD60x18 as UD, ud} from "@prb/math/UD60x18.sol";
import {PotentiaPool} from "../../src/PotentiaPool.sol";
import {PotentiaFactory} from "../../src/PotentiaFactory.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {Test, console, stdStorage, StdStorage} from "forge-std/Test.sol";
import {SD59x18 as SD, sd, intoUD60x18 as toUD} from "@prb/math/SD59x18.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {UD60x18 as UD, ud, intoSD59x18 as toSD, intoUint256 as toUint, floor} from "@prb/math/UD60x18.sol";

contract PotentiaPoolDecimalTest is Test {
    using stdStorage for StdStorage;

    Utilities public utilities;
    address payable[] internal users;
    PotentiaPool public pool;
    PotentiaFactory public factory;

    MockERC20 public underlying;
    uint256 k = 3e18;

    address private protocol = makeAddr("PROTOCOL");

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 private constant POOL_MANAGER = keccak256("POOL_MANAGER");

    MockV3Aggregator priceFeed;

    function setUp() public {
        utilities = new Utilities();
        address payable[] memory _users = utilities.createUsers(10);
        users = _users;

        vm.startPrank(users[0]);

        underlying = new MockERC20(8);

        priceFeed = new MockV3Aggregator(uint8(8), int256(3000e8));

        factory = new PotentiaFactory();

        underlying.mint(users[0], 10_000_000e8);
        underlying.mint(users[1], 10_000_000e8);
        underlying.mint(users[2], 10_000_000e8);
        underlying.mint(users[3], 10_000_000e8);
        underlying.mint(users[4], 10_000_000e8);

        uint256 adjustRate = 0.25e18;
        uint256 halfTime = 2592000e18;

        uint256 initialLiq = 0.0001e8;

        underlying.mint(users[0], initialLiq);

        vm.stopPrank();

        vm.startPrank(users[1]);
        vm.warp(0);

        pool =
            PotentiaPool(factory.createPool(address(underlying), k, adjustRate, users[1], halfTime, address(priceFeed)));

        underlying.approve(address(pool), initialLiq);
        pool.initializePool(initialLiq);

        vm.stopPrank();
    }

    function test_PoolAlreadyInitialized() external {
        uint256 initialLiq = 0.0001e8;
        vm.startPrank(users[1]);
        vm.warp(1);
        underlying.approve(address(pool), initialLiq);

        vm.expectRevert(Errors.PoolAlreadyInitialized.selector);
        pool.initializePool(initialLiq);
        vm.stopPrank();
    }

    function test_PoolZeroAmtInitialize() external {
        vm.startPrank(users[1]);
        vm.warp(0);
        MockV3Aggregator priceFeed0 = new MockV3Aggregator(uint8(8), int256(3000e8));
        PotentiaPool pool0 =
            PotentiaPool(factory.createPool(address(underlying), k, 0.25e18, users[1], 40000e18, address(priceFeed0)));

        underlying.approve(address(pool), 1 ether);

        vm.expectRevert(Errors.ZeroAmt.selector);
        pool0.initializePool(0);

        vm.stopPrank();
    }

    function test_PoolUnintialized() external {
        vm.startPrank(users[1]);
        vm.warp(0);
        MockV3Aggregator priceFeed0 = new MockV3Aggregator(uint8(8), int256(3000e8));
        PotentiaPool pool0 =
            PotentiaPool(factory.createPool(address(underlying), k, 0.25e18, users[1], 40000e18, address(priceFeed0)));

        underlying.approve(address(pool), 1 ether);

        vm.expectRevert(Errors.PoolUninitialized.selector);
        pool0.addLiquidity(1 ether);
        vm.stopPrank();
    }

    function test_GrantPoolManager() external {
        assertEq(pool.hasRole(POOL_MANAGER, users[2]), false);

        vm.prank(users[1]);
        pool.grantPoolManager(users[2], true);
        assertEq(pool.hasRole(POOL_MANAGER, users[2]), true);
    }

    function test_AdjustParams() external {
        vm.startPrank(users[1]);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, users[1], keccak256("POOL_MANAGER")
            )
        );
        pool.adjustParams(5e18, 0.21e18);
        vm.stopPrank();

        vm.prank(users[1]);
        pool.grantPoolManager(users[2], true);

        vm.prank(users[2]);
        pool.adjustParams(5e18, 0.21e18);

        assertEq(toUint(pool.halfTime()), 5e18);
        assertEq(toUint(pool.adjustRate()), 0.21e18);
    }

    function test_SetProtocolFee() external {
        vm.prank(users[1]);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, users[1], keccak256("PROTOCOL")
            )
        );
        pool.adjustProtocolFee(2e16);

        vm.startPrank(users[0]);
        pool.adjustProtocolFee(2e16);

        assertEq(toUint(pool.protocolFee()), 2e16);

        vm.stopPrank();
    }

    function test_AdjustPool() external {
        vm.warp(500);

        vm.prank(users[0]);
        pool.adjustPool();

        assertEq(toUint(pool.lastFundingBlock()), 500e18);
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
        assertEq(pool.reserve(), 0.0001e8);
        assertEq(toUint(pool.initLongQty()), 0.00005 ether);
        assertEq(toUint(pool.initShortQty()), 0.00005 ether);
        assertEq(pool.hasRole(DEFAULT_ADMIN_ROLE, users[1]), true);
        assertEq(underlying.balanceOf(address(pool)), 0.0001e8);
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

    function test_AddLiquidity() public {
        uint256 initialReserve = pool.reserve();
        uint256 initialLpTokenSupply = pool.lpPToken().totalSupply();
        uint256 initialLpTokenBalance = pool.lpPToken().balanceOf(users[1]);

        uint256 amt = 100e8;

        vm.startPrank(users[1]);

        underlying.approve(address(pool), amt);

        vm.expectRevert(Errors.ZeroAmt.selector);
        pool.addLiquidity(0);

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
        _addLiq(users[1], 100e8);

        uint256 initialReserve = pool.reserve();
        uint256 initialUnderlyingBalance = underlying.balanceOf(users[1]);
        uint256 initialLpShares = pool.lpPToken().balanceOf(users[1]);
        UD r = ud(initialLpShares) * test_Liquidity() / ud(pool.lpPToken().totalSupply());
        UD redeemAmt = (_denormAmt(toUint(r), uint256(underlying.decimals())));

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

    function test_OpenLongPosition() public {
        (UD x,) = pool.getX();
        uint256 liq0 = toUint(pool.liquidity(x));
        uint256 phi = toUint(pool.longPayoff(x));
        uint256 psi = toUint(pool.shortPayoff(x));
        console.log("LC = %s", toUint(pool.longCondition()));
        console.log("SC = %s", toUint(pool.shortCondition()));
        console.log("Liq = %s, Phi = %s, Psi = %s\n", liq0, phi, psi);

        // Add 50 ether LP
        vm.warp(2);
        _addLiq(users[1], 50e8);

        console.log("Params after adding 50 ether liquidity");
        (x,) = pool.getX();
        liq0 = toUint(pool.liquidity(x));
        phi = toUint(pool.longPayoff(x));
        psi = toUint(pool.shortPayoff(x));
        console.log("LC = %s", toUint(pool.longCondition()));
        console.log("SC = %s", toUint(pool.shortCondition()));
        console.log("Liq = %s, Phi = %s, Psi = %s\n", liq0, phi, psi);

        vm.startPrank(users[2]);
        vm.warp(4);

        uint256 positionSize = 10e8;

        UD fee = (ud(positionSize) * ud(1e18)) / ud(100e18);
        uint256 expectedFreeGrowth = toUint(fee);

        // Take 10e8 Long Position
        underlying.approve(address(pool), positionSize);
        pool.openPosition(positionSize, true);

        console.log("Params after taking 10e8 Long Position at t=2");
        (x,) = pool.getX();
        liq0 = toUint(pool.liquidity(x));
        phi = toUint(pool.longPayoff(x));
        psi = toUint(pool.shortPayoff(x));
        uint256 longValue = _positionValue(true, pool.longPToken().balanceOf(users[2]));
        console.log("LC = %s", toUint(pool.longCondition()));
        console.log("SC = %s", toUint(pool.shortCondition()));
        console.log("Liq = %s, Phi = %s, Psi = %s", liq0, phi, psi);
        console.log("Long Value = %s\n", longValue);

        assertLe(longValue, positionSize);

        uint256 feeGrwth = toUint(pool.feeGrowth());
        assertEq(expectedFreeGrowth, feeGrwth);

        vm.warp(100);

        // Take another 10 ether Long Position
        underlying.approve(address(pool), 10e8);
        pool.openPosition(10e8, true);

        console.log("Params after taking 10 ether Long Position at t=100");
        (x,) = pool.getX();
        liq0 = toUint(pool.liquidity(x));
        phi = toUint(pool.longPayoff(x));
        psi = toUint(pool.shortPayoff(x));
        longValue = _positionValue(true, pool.longPToken().balanceOf(users[2]));
        console.log("LC = %s", toUint(pool.longCondition()));
        console.log("SC = %s", toUint(pool.shortCondition()));
        console.log("Liq = %s, Phi = %s, Psi = %s", liq0, phi, psi);
        console.log("Long Value = %s\n", longValue);

        vm.warp(5000);

        // Take another 10e8 Long Position
        underlying.approve(address(pool), 10e8);
        pool.openPosition(10e8, true);

        console.log("Params after taking 10e8 Long Position at t=5000");
        (x,) = pool.getX();
        liq0 = toUint(pool.liquidity(x));
        phi = toUint(pool.longPayoff(x));
        psi = toUint(pool.shortPayoff(x));
        longValue = _positionValue(true, pool.longPToken().balanceOf(users[2]));
        console.log("LC = %s", toUint(pool.longCondition()));
        console.log("SC = %s", toUint(pool.shortCondition()));
        console.log("Liq = %s, Phi = %s, Psi = %s", liq0, phi, psi);
        console.log("Long Value = %s\n", longValue);

        assertLe(longValue, 30e8);

        vm.stopPrank();

        vm.startPrank(users[0]);
        uint256 protocolBal = underlying.balanceOf(users[0]);
        pool.withdraw();
        assertEq(underlying.balanceOf(users[0]), protocolBal + 0.3e8);
        vm.stopPrank();
    }

    function test_OpenAnotherLongPos() public {
        vm.startPrank(users[2]);

        uint256 longTokenSupply = pool.longPToken().totalSupply();
        console.log("long token supply %s", longTokenSupply);

        vm.warp(2);

        underlying.approve(address(pool), 10e8);
        pool.openPosition(10e8, true);

        uint256 longValue = _positionValue(true, pool.longPToken().balanceOf(users[2]));
        console.log("Long Value = %s\n", longValue);

        assertLt(longValue, 10e8);

        vm.stopPrank();
    }

    function test_OpenLongMinPos() public {
        vm.startPrank(users[2]);

        uint256 longTokenSupply = pool.longPToken().totalSupply();
        console.log("long supply %s", longTokenSupply);

        vm.warp(2);

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

        vm.warp(10000);

        vm.startPrank(users[2]);

        uint256 initialLongBalance = pool.longPToken().balanceOf(users[2]);
        uint256 initialLongSupply = pool.longPToken().totalSupply();
        uint256 initialUnderlyingBalance = underlying.balanceOf(users[2]);

        uint256 redeemAmt = (phi * initialLongBalance) / initialLongSupply;

        pool.closePosition(initialLongBalance, true);

        uint256 finalLongBalance = pool.longPToken().balanceOf(users[2]);
        uint256 finalLongSupply = pool.longPToken().totalSupply();
        uint256 finalUnderlyingBalance = underlying.balanceOf(users[2]);

        (x,) = pool.getX();
        phi = toUint(pool.longPayoff(x));
        uint256 psi = toUint(pool.shortPayoff(x));
        console.log(" --- after closing position ---");
        console.log("phi %s", phi);
        console.log("psi %s", psi);

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

        vm.warp(2);
        _addLiq(users[1], 50e8);
        (x,) = pool.getX();
        console.log("Initial phi: %s", toUint(pool.longPayoff(x)));
        console.log("Initial psi: %s", toUint(pool.shortPayoff(x)));

        uint256 lpValue = toUint(pool.liquidity(x));
        console.log("liquidity %s", lpValue);
        uint256 phi = toUint(pool.longPayoff(x));
        uint256 psi = toUint(pool.shortPayoff(x));
        console.log("phi = %s, psi = %s", phi, psi);
        console.log("long condition %s", toUint(pool.longCondition()));
        console.log("short condition = %s", toUint(pool.shortCondition()));

        vm.startPrank(users[2]);

        vm.warp(100);

        console.log("OPENING A SHORT POSITION \n\n");

        UD fee = (ud(100e8) * ud(1e18)) / ud(100e18);
        uint256 expectedFreeGrowth = toUint(fee);
        console.log("feeGrowth %s", expectedFreeGrowth);

        underlying.approve(address(pool), 100e8);
        pool.openPosition(100e8, false);

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

        assertLe(shortValue, 100e8);
        assertEq(expectedFreeGrowth, toUint(pool.feeGrowth()));

        vm.warp(500);

        underlying.approve(address(pool), 200e8);
        pool.openPosition(200e8, false);

        (x,) = pool.getX();
        phi = toUint(pool.longPayoff(x));
        psi = toUint(pool.shortPayoff(x));
        console.log("phi = %s, psi = %s", phi, psi);

        vm.stopPrank();

        vm.startPrank(users[0]);
        uint256 protocolBal = underlying.balanceOf(users[0]);
        pool.withdraw();
        assertEq(underlying.balanceOf(users[0]), protocolBal + 3e8);
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

        vm.warp(700);

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

    // function test_MultiplePosition() external {
    //     address ALICE = makeAddr("ALICE");
    //     address BOB = makeAddr("BOB");
    //     address NICK = makeAddr("NICK");
    //     address BRAD = makeAddr("BRAD");
    //     vm.startPrank(users[2]);
    //     underlying.transfer(ALICE, 200 ether);
    //     underlying.transfer(BOB, 200 ether);
    //     underlying.transfer(NICK, 200 ether);
    //     underlying.transfer(BRAD, 200 ether);
    //     vm.stopPrank();

    //     vm.warp(2);
    //     _addLiq(users[1], 50 ether);

    //     console.log("AFTER ADDING LIQ");
    //     UD phi0 = pool.longPayoff(pool.getX());
    //     UD psi0 = pool.shortPayoff(pool.getX());
    //     console.log("phi %s, psi %s\n", toUint(phi0), toUint(psi0));

    //     vm.warp(50);

    //     vm.startPrank(ALICE);
    //     underlying.approve(address(pool), 10 ether);
    //     pool.openPosition(10 ether, true);
    //     vm.stopPrank();

    //     console.log("AFTER OPENING 10 ETHER LONG POSITION");
    //     phi0 = pool.longPayoff(pool.getX());
    //     psi0 = pool.shortPayoff(pool.getX());
    //     console.log("phi %s, psi %s\n", toUint(phi0), toUint(psi0));

    //     vm.warp(100);
    //     priceFeed.updateAnswer(int256(3500e8));

    //     vm.startPrank(BOB);
    //     underlying.approve(address(pool), 10 ether);
    //     pool.openPosition(10 ether, false);
    //     vm.stopPrank();

    //     console.log("AFTER OPENING 10 ETHER SHORT POSITION");
    //     phi0 = pool.longPayoff(pool.getX());
    //     psi0 = pool.shortPayoff(pool.getX());
    //     console.log("phi %s, psi %s\n", toUint(phi0), toUint(psi0));
    // }

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
        return ud(_normalizeDecimal(_x, 8, 18));
    }

    function _denormAmt(uint256 _x, uint256 d) internal pure returns (UD) {
        return ud(_normalizeDecimal(_x, 18, d));
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
