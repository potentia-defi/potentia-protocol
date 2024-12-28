// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./utils/Errors.sol";
import "./utils/PotentiaUtils.sol";
import {PToken} from "./PToken.sol";
import {IERC20Decimals} from "./interfaces/IERC20Decimals.sol";
import {SD59x18 as SD, sd, intoUD60x18 as toUD} from "@prb/math/SD59x18.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {UD60x18 as UD, ud, intoSD59x18 as toSD, intoUint256 as toUint} from "@prb/math/UD60x18.sol";

contract PotentiaPool is ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20Decimals;

    uint256 public k; // Pool power
    uint256 public alpha; // Long payoff param
    uint256 public beta; // Short payoff param
    uint256 public reserve; // Pool reserve
    uint256 public underlyingPrecision; // Underlying token decimals

    UD public adjustRate; // Adjust Rate of pool
    UD public priceRefAdjusted; // Adjusted Price referecnce
    UD public lastFundingBlock; // Last funding block of pool

    // fee params
    UD public feeGrowth; // Accumulated fees
    UD public protocolFee = ud(1e16); // Protocol fee in percentage i.e 1% default
    UD public aMin; // Minimum amount of position to be opened

    UD public initLongQty; // Initial minted Long tokens
    UD public initShortQty; // Initial minted Short tokens
    UD public halfTime; // Half Time parameter

    UD public lastAdjustment; // Last moving price adjusted block
    UD public adjustPeriod = ud(3600 seconds * 1e18);

    PToken public longPToken;
    PToken public shortPToken;
    PToken public lpPToken;
    IERC20Decimals public underlying;

    address public oracle; // Oracle address
    address public protocol; // Protocol address i.e Factory deployed
    bytes32 private constant POOL_MANAGER = keccak256("POOL_MANAGER");
    bytes32 private constant PROTOCOL = keccak256("PROTOCOL");

    constructor(
        address _underlying,
        uint256 _power,
        uint256 _adjustRate,
        address _operator,
        uint256 _halfTime,
        address _oracle,
        address _protocol
    ) payable {
        k = _power;
        adjustRate = ud(_adjustRate);
        halfTime = ud(_halfTime);
        oracle = _oracle;
        underlying = IERC20Decimals(_underlying);
        underlyingPrecision = underlying.decimals();

        longPToken = new PToken("LongPToken", "LONG");
        shortPToken = new PToken("ShortPToken", "SHORT");
        lpPToken = new PToken("LpPToken", "LP");

        lastAdjustment = ud(block.timestamp * 1e18);
        lastFundingBlock = ud(block.timestamp * 1e18);

        priceRefAdjusted = oraclePrice();

        _grantRole(DEFAULT_ADMIN_ROLE, _operator);
        protocol = _protocol;
        _grantRole(PROTOCOL, protocol);
    }

    /// @notice Initializes the pool with some initial liquidity
    /// @param _initialLiq The initial liquidity to sent to the pool
    /// @dev Can only be called by the Pool operator passed in constructor
    function initializePool(uint256 _initialLiq) external payable onlyRole(DEFAULT_ADMIN_ROLE) {
        if (reserve != 0) revert Errors.PoolAlreadyInitialized();
        if (_initialLiq == 0) revert Errors.ZeroAmt();

        underlying.safeTransferFrom(msg.sender, address(this), _initialLiq);
        reserve = _initialLiq;

        initLongQty = nR() / ud(2e18);
        initShortQty = nR() / ud(2e18);

        alpha = toUint(nR() / ud(2e18));
        beta = toUint(nR() / ud(2e18));

        // mint initial LONG & SHORT tokens to the pool.
        longPToken.mint(address(this), toUint(initLongQty));
        shortPToken.mint(address(this), toUint(initShortQty));
        aMin = ud(1e18) / (protocolFee * ud(10e18).pow(ud(underlyingPrecision * 1e18)));
    }

    /// @notice Grants/Revokes the POOL_MANAGER role to an address
    /// @param poolManager The address to grant to or revoke the role
    /// @param flag True to grant the role and false to revoke the role
    /// @dev Can only be called by the DEFAULT_ADMIN_ROLE
    function grantPoolManager(address poolManager, bool flag) external payable onlyRole(DEFAULT_ADMIN_ROLE) {
        flag ? _grantRole(POOL_MANAGER, poolManager) : _revokeRole(POOL_MANAGER, poolManager);
    }

    /// @notice Grant the PROTOCOL role to a new address
    /// @param newProtocolAddress The address to grant the role
    /// @dev Can only be called by the previous PROTOCOL address
    function grantProtocol(address newProtocolAddress) external payable onlyRole(PROTOCOL) {
        _revokeRole(PROTOCOL, protocol);
        protocol = newProtocolAddress;
        _grantRole(PROTOCOL, protocol);
    }

    ///  @notice Changes the pool params i.e halfTime and adjustRate
    ///  @param _halfTime  The new halfTime of the pool
    ///  @param _adjustRate The new adjustRate of the pool
    /// @dev Can only be called by the POOL_MANAGER if set by the DEFAULT_ADMIN_ROLE
    function adjustParams(uint256 _halfTime, uint256 _adjustRate) external payable onlyRole(POOL_MANAGER) {
        halfTime = ud(_halfTime);
        adjustRate = ud(_adjustRate);
    }

    /// @notice Adjusts the protocol fee
    /// @param _pf The new Protocol Fee
    /// @dev Can only be called by the PROTOCOL role
    function adjustProtocolFee(uint256 _pf) external payable onlyRole(PROTOCOL) {
        protocolFee = ud(_pf);
    }

    /// @notice Applies the funding and adjusts the moving average
    /// @dev Can only be called by the PROTOCOL role
    function adjustPool() external payable onlyRole(PROTOCOL) {
        (UD x,) = getX();
        applyFunding(halfTime, x);
        UD price = oraclePrice();
        _adjustPriceRef(price);
    }

    /// @notice Gets the oracle price and normalizes it
    /// @return p Normalized price
    function oraclePrice() public view returns (UD p) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(oracle);
        (, int256 price,,,) = priceFeed.latestRoundData();
        p = ud(normalizeDecimal(uint256(price), 8, 18));
    }

    /// @notice Returns the scaled price on X axis in the payoff curve of the underlying price
    /// @return x Scaled Price
    function getX() public view returns (UD x, UD p) {
        p = oraclePrice();
        x = p / priceRefAdjusted;
    }

    /// @notice Returns the long condition in the payoff curve
    /// @return Long condition in UD
    function longCondition() public view returns (UD) {
        UD base = nR() / ud(2 * alpha);

        UD one_by_k = ud(1e18) / ud(k);
        return base.pow(one_by_k);
    }

    /// @notice Returns the short condition in the payoff curve
    /// @return Short Condition in UD
    function shortCondition() public view returns (UD) {
        UD base = ud(2 * beta) / (nR());

        if (k == 2e18) {
            return base.sqrt();
        }
        UD one_by_k = ud(1e18) / (ud(k));
        return base.pow(one_by_k);
    }

    /// @notice Returns the long payoff i.e Phi
    /// @return Long Payoff in UD
    function longPayoff(UD x) public view returns (UD) {
        UD R = nR();
        if (x <= longCondition()) {
            return ud(alpha) * x.pow(ud(k));
        } else {
            return R - (R.pow(ud(2e18)) / (ud(4 * alpha) * x.pow(ud(k))));
        }
    }

    /// @notice Returns the short payoff i.e Psi
    /// @return Short Payoff in UD
    function shortPayoff(UD x) public view returns (UD) {
        UD R = nR();
        if (x >= shortCondition()) {
            return ud(beta) / (x.pow(ud(k)));
        } else {
            return R - ((R.pow(ud(2e18)) * x.pow(ud(k))) / ud(4 * beta));
        }
    }

    /// @notice Returns the counter-party liquidity in the pool
    /// @return Liquidity in UD
    function liquidity(UD x) public view returns (UD) {
        UD phi = longPayoff(x);
        UD psi = shortPayoff(x);
        return nR() - phi - psi;
    }

    /// @notice Adds liquidity to the pool
    /// @param _amount The amount of liquiidy to be added in underlying asset
    /// @dev Calculates and mints the Lp Tokens to the msg.sender
    function addLiquidity(uint256 _amount) external nonReentrant {
        if (reserve == 0) revert Errors.PoolUninitialized();
        if (_amount == 0) revert Errors.ZeroAmt();

        (UD x, UD p) = getX();

        applyFunding(halfTime, x);
        _adjustPriceRef(p);

        underlying.safeTransferFrom(msg.sender, address(this), _amount);

        UD lpSupply = ud(lpPToken.totalSupply());

        UD lpAmount = lpSupply == ud(0)
            ? normAmt(_amount, underlyingPrecision)
            : normAmt(_amount, underlyingPrecision) * lpSupply / liquidity(x);

        _updateABAssertLiquidity(_amount, x, false);

        lpPToken.mint(msg.sender, toUint(lpAmount));
        emit PotentiaUtils.AddLiquidity(msg.sender, _amount, toUint(lpAmount), toUint(x), address(this));
    }

    /// @notice Removes liquidity from the pool
    /// @param _shares The number of Lp Tokens to burn
    /// @dev Calculates the amount in underlying to be redeemed & transfers to msg.sender
    /// @dev Burn the Lp Tokens
    function removeLiquidity(uint256 _shares) external nonReentrant {
        if (reserve == 0) revert Errors.PoolUninitialized();
        if (_shares == 0) revert Errors.ZeroAmt();

        (UD x, UD p) = getX();

        applyFunding(halfTime, x);
        _adjustPriceRef(p);

        UD redeemAmountUD = (ud(_shares) * liquidity(x)) / ud(lpPToken.totalSupply());

        // redeemAmount is in underlying token decimals.
        uint256 redeemAmount = toUint(denormAmt(toUint(redeemAmountUD), underlyingPrecision));

        if (redeemAmount > reserve) revert Errors.RedeemAmtGtReserve();

        _updateABAssertLiquidity(redeemAmount, x, true);

        lpPToken.burn(msg.sender, _shares);
        underlying.safeTransfer(msg.sender, redeemAmount);
        emit PotentiaUtils.RemoveLiquidity(msg.sender, _shares, redeemAmount, toUint(x), address(this));
    }

    /// @notice Opens a new position in the pool
    /// @param amt The amount of underlying to create the position
    /// @param isLong True to create a long position and False to create a short position
    function openPosition(uint256 amt, bool isLong) external nonReentrant {
        if (reserve == 0) revert Errors.PoolUninitialized();
        if (amt == 0) revert Errors.ZeroAmt();

        if (normAmt(amt, underlyingPrecision) <= aMin) {
            revert Errors.MinAmt();
        }

        (UD x, UD p) = getX();

        applyFunding(halfTime, x);
        _adjustPriceRef(p);

        underlying.safeTransferFrom(msg.sender, address(this), amt);

        UD feeScaled = (normAmt(amt, underlyingPrecision) * protocolFee);
        UD fee = denormAmt(toUint(feeScaled), underlyingPrecision);
        feeGrowth = feeGrowth + fee;
        amt -= toUint(fee);

        isLong ? _long(amt, true, fee, x) : _short(amt, true, fee, x);
    }

    /// @notice Closes an existing position in the pool
    /// @param shares The number of Long or Short tokens to be burnt
    /// @param isLong True to burn the long position and False for short position
    function closePosition(uint256 shares, bool isLong) external nonReentrant {
        if (reserve == 0) revert Errors.PoolUninitialized();
        if (shares == 0) revert Errors.ZeroAmt();

        (UD x, UD p) = getX();

        applyFunding(halfTime, x);
        _adjustPriceRef(p);

        isLong ? _long(shares, false, ud(0), x) : _short(shares, false, ud(0), x);
    }

    /// @notice Withdraw the accumulated protocol fee
    /// @dev Can only be called by the PROTOCOL role
    function withdraw() external onlyRole(PROTOCOL) nonReentrant {
        uint256 feesToWithdraw = toUint(feeGrowth);
        feeGrowth = ud(0);
        underlying.safeTransfer(protocol, feesToWithdraw);
    }

    /// @notice This function opens or closes the long position internally
    /// @param amt For opening a pos, amt is in underlying; for closing a pos, amt is the number of Long tokens
    /// @param isOpen True for opening a pos; False for closing a pos
    /// @param fee Fee to be deducted when opening a pos
    /// @dev This internally calls the functions to update alpha, beta params
    /// @dev Mints or burns the Long Tokens
    function _long(uint256 amt, bool isOpen, UD fee, UD x) internal {
        UD phi = longPayoff(x);
        uint256 a = alpha;
        uint256 b = beta;
        uint256 r = reserve;

        if (isOpen) {
            _updateABAssertLong(x, amt, true);
            uint256 longSupply = longPToken.totalSupply();
            uint256 longAmount = (longSupply == 0) ? amt : (longSupply * amt) / toUint(phi);
            longPToken.mint(msg.sender, longAmount);
            emit PotentiaUtils.OpenLong(msg.sender, amt, longAmount, toUint(x), r, a, b, address(this), toUint(fee));
        } else {
            uint256 redeemAmount = ((toUint(phi) * amt)) / longPToken.totalSupply();
            if (redeemAmount > reserve) revert Errors.RedeemAmtGtReserve();
            _updateABAssertLong(x, redeemAmount, false);
            longPToken.burn(msg.sender, amt);
            underlying.safeTransfer(msg.sender, redeemAmount);
            emit PotentiaUtils.CloseLong(msg.sender, amt, redeemAmount, toUint(x), address(this));
        }
    }

    /// @notice This function opens or closes the long position internally
    /// @param amt For opening a pos, amt is in underlying; for closing a pos, amt is the number of Short tokens
    /// @param isOpen True for opening a pos; False for closing a pos
    /// @param fee Fee to be deducted when opening a pos
    /// @dev This internally calls the functions to update alpha, beta params
    /// @dev Mints or burns the Short Tokens
    function _short(uint256 amt, bool isOpen, UD fee, UD x) internal {
        UD psi = shortPayoff(x);
        uint256 a = alpha;
        uint256 b = beta;
        uint256 r = reserve;

        if (isOpen) {
            _updateABAssertShort(x, amt, true);
            uint256 shortSupply = shortPToken.totalSupply();
            uint256 shortAmount = (shortSupply == 0) ? amt : shortSupply * amt / toUint(psi);
            shortPToken.mint(msg.sender, shortAmount);
            emit PotentiaUtils.OpenShort(msg.sender, amt, shortAmount, toUint(x), r, a, b, address(this), toUint(fee));
        } else {
            uint256 redeemAmount = (toUint(psi) * amt) / shortPToken.totalSupply();
            if (redeemAmount > reserve) revert Errors.RedeemAmtGtReserve();
            _updateABAssertShort(x, redeemAmount, false);
            shortPToken.burn(msg.sender, amt);
            underlying.safeTransfer(msg.sender, redeemAmount);
            emit PotentiaUtils.CloseShort(msg.sender, amt, redeemAmount, toUint(x), address(this));
        }
    }

    /// @notice Updates the alpha and beta params according to the long/short conditions
    /// @param deltaR The amount of liquidity to be added or removed in underlying
    /// @param x The scaled price from getX()
    /// @param isRemoveLiq True if removing liquidity, else False
    function _updateABAssertLiquidity(uint256 deltaR, UD x, bool isRemoveLiq) internal {
        UD phi = longPayoff(x);
        UD psi = shortPayoff(x);

        isRemoveLiq ? reserve -= deltaR : reserve += deltaR;

        UD R = nR();

        if (x > longCondition()) {
            alpha = toUint(R.pow(ud(2e18)) / (ud(4e18) * (R - phi) * x.pow(ud(k))));
        }
        if (x < shortCondition()) {
            beta = toUint((R.pow(ud(2e18)) * x.pow(ud(k))) / (ud(4e18) * (R - psi)));
        }

        _assertPool(phi, psi);
    }

    /// @notice Updates the long and short payoff values, i.e alpha and beta internally
    /// @param x The scaled price from getX()
    /// @param deltaR The amount of underlying to add or remove from the reserve while open/close Long position
    /// @param isOpen True if opening pos, else False
    function _updateABAssertLong(UD x, uint256 deltaR, bool isOpen) internal {
        UD phi = longPayoff(x);
        UD psi = shortPayoff(x);

        UD newPhi;
        bool isN = false;
        reserve = isOpen ? reserve + deltaR : reserve - deltaR;
        // newPhi = isOpen ? toUD(toSD(phi) + toSD(ud(deltaR))) : toUD(toSD(phi) - toSD(ud(deltaR)));
        if (isOpen) {
            newPhi = phi + ud(deltaR);
        } else {
            if (ud(deltaR) > phi) {
                isN = true;
                newPhi = ud(deltaR) - phi;
            }
            newPhi = phi - ud(deltaR);
        }

        _adjustLongPayoff(newPhi, x, isN);
        _adjustShortPayoff(psi, x, false);

        _assertPool(newPhi, psi);
    }

    /// @notice Updates the long and short payoff values, i.e alpha and beta internally
    /// @param x The scaled price from getX()
    /// @param deltaR The amount of underlying to add or remove from the reserve while open/close Short position
    /// @param isOpen True if opening pos, else False
    function _updateABAssertShort(UD x, uint256 deltaR, bool isOpen) internal {
        UD psi = shortPayoff(x);
        UD phi = longPayoff(x);

        UD newPsi;
        bool isN = false;

        reserve = isOpen ? reserve + deltaR : reserve - deltaR;
        // newPsi = isOpen ? toUD(toSD(psi) + toSD(ud(deltaR))) : toUD(toSD(psi) - toSD(ud(deltaR)));
        if (isOpen) {
            newPsi = psi + ud(deltaR);
        } else {
            if (ud(deltaR) > psi) {
                isN = true;
                newPsi = ud(deltaR) - psi;
            }
            newPsi = psi - ud(deltaR);
        }

        _adjustLongPayoff(phi, x, false);
        _adjustShortPayoff(newPsi, x, isN);

        _assertPool(phi, newPsi);
    }

    /// @notice Adjust the Long Payoff value i.e adjust the alpha
    /// @param newPhi The new long calculated payoff passed internally
    /// @param x The scaled price from getX()
    /// @param isN True if (deltaR > Long payoff value); Can only be True for Close position; else False
    function _adjustLongPayoff(UD newPhi, UD x, bool isN) internal {
        UD R = nR();
        // R - (phi +- dR) = R - phi - dR or R - phi + dR
        UD RMinusPhi = isN ? R + newPhi : R - newPhi;

        (x <= longCondition())
            ? alpha = toUint(newPhi / x.pow(ud(k)))
            : alpha = toUint((R.pow(ud(2e18)) / (ud(4e18) * (RMinusPhi) * x.pow(ud(k)))));

        emit PotentiaUtils.LongPayoffAdjusted(alpha);
    }

    /// @notice Adjust the Short Payoff value i.e adjust the beta
    /// @param newPsi The new short calculated payoff passed internally
    /// @param x The scaled price from getX()
    /// @param isN True if (deltaR > Short payoff value); Can only be True for Close position; else False
    function _adjustShortPayoff(UD newPsi, UD x, bool isN) internal {
        UD R = nR();
        UD RMinusPsi = isN ? R + newPsi : R - newPsi;
        (x >= shortCondition())
            // ? beta = toUint((newPsi / (ud(1e18)) / x.pow(ud(k))))
            ? beta = toUint(newPsi * x.pow(ud(k)))
            : beta = toUint((R.pow(ud(2e18)) * x.pow(ud(k))) / (ud(4e18) * (RMinusPsi)));

        emit PotentiaUtils.ShortPayoffAdjusted(beta);
    }

    /// @notice Checks if the pool state assertions are valid or not
    /// @param targetPhi The long payoff to cross-check the assertion
    /// @param targetPsi The short payoff to cross-check the assertion
    function _assertPool(UD targetPhi, UD targetPsi) internal {
        _assertAB();
        _assertPayoff(targetPhi, targetPsi);
    }

    /// @notice Assert the validity of the pool
    /// @dev Updates the alpha, beta if required
    function _assertAB() internal {
        UD R = nR();
        if (ud(4e18) * ud(alpha) * ud(beta) > R.pow(ud(2e18))) {
            UD coef = R / (ud(2e18) * ((ud(alpha) * ud(beta)).sqrt()));
            alpha = toUint(ud(alpha) * coef);
            beta = toUint(ud(beta) * coef);
        }
    }

    /// @notice Check if new payoffs have been correclty set
    /// @param targetPhi The long payoff to cross-check the assertion
    /// @param targetPsi The short payoff to cross-check the assertion
    function _assertPayoff(UD targetPhi, UD targetPsi) internal {
        (UD x,) = getX();
        if (targetPhi != longPayoff(x)) {
            _adjustLongPayoff(targetPhi, x, false);
        }
        if (targetPsi != shortPayoff(x)) {
            _adjustShortPayoff(targetPsi, x, false);
        }
    }

    /// @notice Adjusts the moving price
    /// @param _price The normalized price from the oracle
    /// @dev Updates the priceRefAdjusted and lastAdjustment
    function _adjustPriceRef(UD _price) internal {
        UD t = ud(block.timestamp * 1e18) - lastAdjustment;

        if (t < adjustPeriod) {
            return;
        }

        UD updateFactor = (adjustRate * t) / adjustPeriod;
        if (updateFactor > ud(1e18)) {
            updateFactor = ud(1e18);
        }
        priceRefAdjusted = (((ud(1e18) - updateFactor) * priceRefAdjusted)) + (updateFactor * _price);
        lastAdjustment = ud(block.timestamp * 1e18);
    }

    /// @notice Applies the funding rate to the pool
    /// @notice This function is called everytime an interaction is taking place in the pool
    /// @param h The half time parameter specific to the pool
    /// @dev Internally calls the calculateFunding to calculate phi, psi
    function applyFunding(UD h, UD x) public {
        UD dt = ud(block.timestamp * 1e18) - lastFundingBlock;

        if (dt == ud(0)) {
            return;
        }

        lastFundingBlock = ud(block.timestamp * 1e18);

        UD phi = longPayoff(x);
        UD psi = shortPayoff(x);
        UD r = nR();

        (UD newPhi, UD newPsi) = calculateFunding(phi, psi, dt, h);

        _adjustLongPayoff(newPhi, x, false);
        _adjustShortPayoff(newPsi, x, false);

        uint256 lpTokenSupply = lpPToken.totalSupply();

        emit PotentiaUtils.FundingApplied(
            toUint(phi),
            toUint(psi),
            toUint(newPhi),
            toUint(newPsi),
            toUint(r),
            lpTokenSupply,
            toUint(x),
            toUint(dt),
            toUint(h)
        );
    }

    /// notice This function is internally called to calculate long, short payoff after funding is applied
    /// @param phi The previous long payoff
    /// @param psi The previous short payoff
    /// @param dt The time between current timestamp and last funding block
    /// @param h The half time parameter specific to the pool
    /// @return newPhi The calculated long payoff after funding is applied
    /// @return newPsi The calculated short payoff after funding is applied
    function calculateFunding(UD phi, UD psi, UD dt, UD h) public view returns (UD newPhi, UD newPsi) {
        UD max = phi > psi ? phi : psi;

        UD premium =
            max * (ud(1e18) - ((ud(1e18) / ud(2e18)).pow(dt / h))) * (toUD((toSD(phi) - toSD(psi)).abs()) / nR());

        if (phi > psi) {
            newPhi = phi - premium;
            newPsi = psi + premium * (psi / (nR() - phi));
        } else {
            newPsi = psi - premium;
            newPhi = phi + premium * (phi / (nR() - psi));
        }
    }

    /// @notice Calculates the normalized amount of reserve
    /// @return Normalized reserve in UD
    function nR() public view returns (UD) {
        return normAmt(reserve, underlyingPrecision);
    }
}
