# TODO: Add tests that show proper migration of the strategy to a newer one
#       Use another copy of the strategy to simulate the migration
#       Show that nothing is lost!

import pytest


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
    RELATIVE_APPROX,
):
    # Deposit to the vault and harvest
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    chain.sleep(1)
    strategy.harvest()

    (price, _) = steth_price_feed.current_price()
    assert pytest.approx(strategy.estimatedTotalAssets(),
                         rel=RELATIVE_APPROX) == price * amount / 1e18

    # migrate to a new strategy
    is_AA = strategy_config['tranche_type'] == 'AA'
    new_strategy = strategist.deploy(
        StEthTrancheStrategy, vault, idleCDO, is_AA, sushiswap_router)
    vault.migrateStrategy(strategy, new_strategy, {"from": gov})
    assert (
        pytest.approx(new_strategy.estimatedTotalAssets(),
                      rel=RELATIVE_APPROX) == price * amount / 1e18
    )
