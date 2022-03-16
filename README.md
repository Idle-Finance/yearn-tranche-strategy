# Yearn Tranche Strategy

## Overview



## Getting Started

Create `.env` file with the following environment variables.

```bash
ETHERSCAN_TOKEN=<Your Etherscan token>
```

To add Alchemy as RPC provider:
```bash
brownie networks add Ethereum alchemy-mainnet chainId=1 host=https://eth-mainnet.alchemyapi.io/v2/<ALCHEMY_API_KEY> explorer=https://api.etherscan.io/api muticall2=0x5BA1e12693Dc8F9c48aAD8770482f4739bEeD696
```

To set up mainnet forking :

```bash
brownie networks add development alchemy-mainnet-forking cmd=ganache-cli fork=alchemy-mainnet mnemonic=brownie port=8545 accounts=10 host=http://127.0.0.1 timeout=120
```

For specific options and more information about each command, type: 
```bash
brownie networks --help
```


## Testing

To run the tests:

```
brownie test --network alchemy-mainnet-fork
```

See the [Brownie documentation](https://eth-brownie.readthedocs.io/en/stable/tests-pytest-intro.html) for more detailed information on testing your project.

## Debugging Failed Transactions

Use the `--interactive` flag to open a console immediatly after each failing test:
```
brownie test --network alchemy-mainnet-fork --interactive
```

Examine the [`TransactionReceipt`](https://eth-brownie.readthedocs.io/en/stable/api-network.html#transactionreceipt) for the failed test to determine what went wrong. For example, to view a traceback:

```python
>>> tx = history[-1]
>>> tx.traceback()
```

To view a tree map of how the transaction executed:

```python
>>> tx.call_trace()
```

See the [Brownie documentation](https://eth-brownie.readthedocs.io/en/stable/core-transactions.html) for more detailed information on debugging failed transactions.
