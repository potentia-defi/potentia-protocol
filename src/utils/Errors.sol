// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

library Errors {
    error PoolAlreadyInitialized();
    error PoolUninitialized();
    error ZeroAmt();
    error RedeemAmtGtReserve();
    error MinAmt();
}
