# TODO: Add tests that show proper migration of the strategy to a newer one
#       Use another copy of the strategy to simulate the migration
#       Show that nothing is lost!

import pytest
from util import get_estimate_total_assets


def test_migration(
    chain,
    token,
    vault,
    strategy,
    amount,
    StEthTrancheStrategy,
    strategist,
    gov,
    user,
    idleCDO,
    strategy_config,
    sushiswap_router,
    steth_price_feed,
    multi_rewards,
    RELATIVE_APPROX,
):
    # Deposit to the vault and harvest
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    tranche_price_when_minted = idleCDO.virtualPrice(strategy.tranche())

    chain.sleep(1)
    strategy.harvest()

    assert pytest.approx(
        strategy.estimatedTotalAssets(),
        rel=RELATIVE_APPROX
    ) == get_estimate_total_assets(strategy, steth_price_feed, idleCDO, tranche_price_when_minted, amount)

    # migrate to a new strategy
    is_AA = strategy_config['tranche_type'] == 'AA'
    new_strategy = strategist.deploy(
        StEthTrancheStrategy, vault, idleCDO, is_AA, sushiswap_router, [], multi_rewards)
    vault.migrateStrategy(strategy, new_strategy, {"from": gov})

    assert (
        pytest.approx(
            new_strategy.estimatedTotalAssets(),
            rel=RELATIVE_APPROX
        ) == get_estimate_total_assets(strategy, steth_price_feed, idleCDO, tranche_price_when_minted, amount)
    )
