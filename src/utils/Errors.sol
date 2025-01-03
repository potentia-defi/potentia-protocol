// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

library Errors {
    error PoolAlreadyInitialized();
    error PoolUninitialized();
    error ZeroAmt();
    error RedeemAmtGtReserve();
    error MinAmt();
}
