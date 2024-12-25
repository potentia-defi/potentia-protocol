# Potentia Protocol

*A non-liquidable power-perpetual protocol.*

## About

The Potentia protocol is meant to do the following:

1. Enable traders to create long/short positions on power pools
2. Enable liquidity providers to earn yield off their capital 

Liquidity providers can deposit the underlying asset using `addLiquidity` and mint `lpPToken` accordingly. These `lpPToken` can be burnt using `removeLiquidity` to get back the **capital+interest** generated over time.

The state of the protocol is determined by `alpha` and `beta` i.e the long payoff parameter and the short payoff parameter respectively. These parameters are adjusted everytime an interaction takes place in the pool. The `longPayoff` is calculated using `alpha` and the `shortPayoff` is calculated using `beta`.

Traders can open/close a position using `openPosition` or `closePosition`. Upon opening a long or short position, `longPToken` or `shortPToken` are minted accordingly. They can be burned by closing a position and the amount of underlying asset can be redeemed with profit or loss if any.

There are necessary internal functions that adjust the pool params i.e `_adjustLongPayoff`, `_adjustShortPayoff` and functions to assert the state of the pool i.e `_assertPool`, `_assertAB`, `_assertPayoff`. These functions may adjust the pool parameters again in case the assertions fail the first time.

The `applyFunding` is meant to apply the funding rate in the pool. This changes the returned *longPayoff* and the *shortPayoff*. Users have to pay an addition protocol fee for opening a position that gets accumulated as `feeGrowth`.

## Usage

```
forge test
```

For fuzz tests, add the following to the `.env`

```
RPC=https://base-sepolia-rpc.publicnode.com
```

## Audit Review Details

Commit Hash: `535bd89279852abc0a3b3099d72649af5fabeb70`

### Scope

```
├ src
│   ├ interfaces
│   │   ├ IERC20Decimals.sol
│   ├ utils
│   │   ├ Errors.sol
│   │   ├  PotentiaUtils.sol
│   ├ PotentiaFactory.sol
│   ├ PotentiaPool.sol
│   ├ PToken.sol
```

- Solc version: **0.8.20**
- Chains to deploy contract: 
    - Base
    - Arbitrum
    - Ethereum (in-future)
- ERC20s
    - WETH
    - WBTC
    - USDC
    - USDT
    - ...

### Roles

- Pool Owner: Has the `DEFAULT_ADMIN_ROLE` role. The address for this role is passed in the constructor of the pool creation
- Pool Manager: Has the `POOL_MANAGER` role. The pool owner can grant this role to an address to tweak the pool params
- Protocol: Has the `PROTOCOL` role and is the deployer of the factory contract

## Updates to be done

- This version is soon to be updated with a `PDV.sol` i.e a Pool Discount Vault
- PDV would allow users to have discounts on the fees while opening positions
- The discount would be paid in native `SQL.sol` token that would be added as an update
- Extensive Fuzz tests to be added
