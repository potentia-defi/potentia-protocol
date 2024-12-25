// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {UD60x18 as UD, ud, intoSD59x18 as toSD, intoUint256 as toUint} from "@prb/math/UD60x18.sol";

library PotentiaUtils {
    event PoolCreated(address indexed poolAddr, address indexed poolOp);

    event AddLiquidity(address indexed from, uint256 amount, uint256 lpAmount, uint256 x, address indexed pool);
    event RemoveLiquidity(
        address indexed from, uint256 shares, uint256 redeemedAmount, uint256 x, address indexed pool
    );
    event OpenLong(
        address indexed from,
        uint256 amount,
        uint256 longAmount,
        uint256 x,
        uint256 R,
        uint256 alpha,
        uint256 beta,
        address indexed pool,
        uint256 fee
    );
    event CloseLong(address indexed from, uint256 longAmount, uint256 redeemedAmount, uint256 x, address indexed pool);
    event OpenShort(
        address indexed from,
        uint256 amount,
        uint256 shortAmount,
        uint256 x,
        uint256 R,
        uint256 alpha,
        uint256 beta,
        address indexed pool,
        uint256 fee
    );
    event CloseShort(
        address indexed from, uint256 shortAmount, uint256 redeemedAmount, uint256 x, address indexed pool
    );
    event LongPayoffAdjusted(uint256 alpha);
    event ShortPayoffAdjusted(uint256 beta);
    event FundingApplied(
        uint256 phi,
        uint256 psi,
        uint256 newPhi,
        uint256 newPsi,
        uint256 r,
        uint256 lpTokenSupply,
        uint256 x,
        uint256 dt,
        uint256 h
    );
}

function normalizeDecimal(uint256 tokenAmount, uint256 tokenDecimal, uint256 standard) pure returns (uint256) {
    if (tokenDecimal > standard) {
        return tokenAmount / (10 ** (tokenDecimal - standard));
    } else if (tokenDecimal < standard) {
        return tokenAmount * (10 ** (standard - tokenDecimal));
    } else {
        return tokenAmount;
    }
}

/// @notice returns the normalized amount of underlying value i.e in 1e18.
function normAmt(uint256 _x, uint256 underlyingPrecision) pure returns (UD) {
    return ud(normalizeDecimal(_x, underlyingPrecision, 18));
}

/// @notice returns the denormaliza amount of `_x` (1e18) in underlying token decimals.
function denormAmt(uint256 _x, uint256 underlyingPrecision) pure returns (UD) {
    return ud(normalizeDecimal(_x, 18, underlyingPrecision));
}
