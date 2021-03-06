# TODO: Add tests that show proper migration of the strategy to a newer one
#       Use another copy of the strategy to simulate the migration
#       Show that nothing is lost!

from brownie import Contract, ZERO_ADDRESS
import pytest


def test_migration(
    chain,
    token,
    vault,
    rewards,
    keeper,
    strategy,
    amount,
    TrancheStrategy,
    strategist,
    gov,
    user,
    idleCDO,
    strategy_config,
    sushiswap_router,
    multi_rewards,
    gauge,
    healthCheck,
    RELATIVE_APPROX,
):
    # Deposit to the vault and harvest
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    chain.sleep(1)
    strategy.harvest()
    assert pytest.approx(strategy.estimatedTotalAssets(),
                         rel=RELATIVE_APPROX) == amount

    # migrate to a new strategy
    is_AA = strategy_config['tranche_type'] == 'AA'
    new_strategy = strategist.deploy(
        TrancheStrategy, vault, strategist, rewards, keeper, idleCDO, is_AA, sushiswap_router, [
        ], ZERO_ADDRESS, ZERO_ADDRESS, healthCheck
    )
    vault.migrateStrategy(strategy, new_strategy, {"from": gov})
    assert (
        pytest.approx(new_strategy.estimatedTotalAssets(),
                      rel=RELATIVE_APPROX) == amount
    )


def test_staked_migration(
    chain,
    token,
    vault,
    rewards,
    keeper,
    strategy,
    amount,
    TrancheStrategy,
    strategist,
    gov,
    user,
    idleCDO,
    strategy_config,
    sushiswap_router,
    gauge,
    healthCheck,
    RELATIVE_APPROX,
):
    # Deposit to the vault and harvest
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})

    chain.sleep(1)
    strategy.harvest()

    assert pytest.approx(
        strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX
    ) == amount

    strategy.setCheckStakedBeforeMigrating(False, {"from": gov})
    # manually divesting to make sure it's not staked
    strategy.divest(strategy.totalTranches(), {"from": gov})

    # migrate to a new strategy
    is_AA = strategy_config['tranche_type'] == 'AA'
    new_strategy = strategist.deploy(
        TrancheStrategy, vault, strategist, rewards, keeper, idleCDO, is_AA, sushiswap_router, [
        ], ZERO_ADDRESS, ZERO_ADDRESS, healthCheck
    )
    vault.migrateStrategy(strategy, new_strategy, {"from": gov})

    assert pytest.approx(
        new_strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX
    ) == amount
