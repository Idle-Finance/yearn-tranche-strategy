# Yearn Tranches Strategy
Idle Perpetual Yield Tranches Strategy for Yearn

### Idle Perpetual Yield Tranches

The aim of Idle Perpetual Yield Tranches is to pool capital of users (eg DAI), deposit it into a lending provider (eg Idle Finance) and split the interest received between 2 classes of users with different risk profiles.

One will gain more interest and will be more risky (BB or junior tranche) and the other will have a lower APR but more safety (AA or senior tranche). In the case of an hack or a loss of funds of the lending provider integrated (or any other protocol integrated by this provider), all funds still available will be used to refund senior tranche holders first with the aim of making them whole, and with remaining funds, if any, junior holders after.

The main contract which will be used by users is `IdleCDO` which allow to deposits underlying and mint tranche tokens (ERC20), either AA or BB, and redeem principal+interest from it.

See the [Idle Perpetual Yield Tranches README](https://github.com/Idle-Labs/idle-tranches) for more detailed information.

## Strategies
### TrancheStrategy.sol

TrancheStrategy is a base strategy contract.
This strategy is used when vault `want` is equal to `tranche` underlying.
The following methods should be overrode in parent contact.

#### Core Deposit/Withdraw Logic

The following methods can be overrode in parent contact:

- `_invest()`
- `_dinvest()`

- `_depositTranche()`
- `_withdrawTranche()`

#### Claiming Rewards

To sell claimed rewards, this contract makes use of [ySwaps](https://github.com/yearn/yswaps/blob/main/).
ySwap's idea is to give a yearn maintained swapper permissions to pull reward tokens from the strategy. The selling of tokens will be outsourced to ySwaps and the `want` will be airdropped back to the strategy asynchronously.

The following can be overrode in parent contact:

- `_claimRewards()`

#### View Functions

The following methods can be overrode when vault `want` is not equal to `tranche` underlying.

- `_wantsInTranche()`
- `_tranchesInWant()`

For example `StEthTrancheStrategy`(`want`: WETH, `tranche` underlying: stETH) overrides this methods.

### StEthTrancheStrategy.sol

Stakes WETH on Lido.fi to mint stETH which accumulates ETH 2.0 staking rewards. This strategy will buy stETH off the market if it is cheaper than staking. And then deposit the stETH to Idle StETH Perpetual Yield Tranche.

## Getting Started

Create `.env` file with the following environment variables.

```bash
ETHERSCAN_TOKEN=<Your Etherscan token>
```

To add Alchemy as RPC provider:
```bash
brownie networks add Ethereum alchemy-mainnet chainId=1 host=
https://eth-mainent.alchemyapi.io/v2/$ALCHEMY_API_KEY@$FORK_BLOCK_NUMBER explorer=https://api.etherscan.io/api muticall2=0x5BA1e12693Dc8F9c48aAD8770482f4739bEeD696
```

To set up mainnet forking :

```bash
brownie networks add development alchemy-mainnet-fork cmd=ganache-cli fork=alchemy-mainnet mnemonic=brownie port=8545 accounts=10 host=http://127.0.0.1 timeout=120
```

For specific options and more information about each command, type: 
```bash
brownie networks --help
```


## Testing

Tests for base strategy is in `tests/base`.

To run the tests:

```
brownie test tests/base --network alchemy-mainnet-fork
```

See the [Brownie documentation](https://eth-brownie.readthedocs.io/en/stable/tests-pytest-intro.html) for more detailed information on testing your project.

## Debugging Failed Transactions

Use the `--interactive` flag to open a console immediatly after each failing test:
```
brownie test --network alchemy-mainnet-fork --interactive
```

Examine the [`TransactionReceipt`](https://eth-brownie.readthedocs.io/en/stable/api-network.html#transactionreceipt) for the failed test to determine what went wrong. For example, to view a traceback:

To view how the transaction executed:

```python
>>> tx.info()
```

```python
>>> tx = history[-1]
>>> tx.traceback()
```

To view a tree map of how the transaction executed:

```python
>>> tx.call_trace()
```


See the [Brownie documentation](https://eth-brownie.readthedocs.io/en/stable/core-transactions.html) for more detailed information on debugging failed transactions.
