import pytest
from util import get_estimate_total_assets


def test_revoke_strategy_from_vault(
    chain, token, vault, strategy, amount, user, gov, idleCDO, RELATIVE_APPROX, steth_price_feed, underlying_token, management, keeper
):
    # Deposit to the vault and harvest
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})

    chain.sleep(1)
    strategy.harvest()
    minted_tranche = strategy.totalTranches()

    assert (
        pytest.approx(
            strategy.estimatedTotalAssets(),
            rel=RELATIVE_APPROX
        ) == get_estimate_total_assets(strategy, steth_price_feed, idleCDO, minted_tranche)
    )
    vault.revokeStrategy(strategy.address, {"from": gov})
    chain.sleep(1)

    strategy.setDoHealthCheck(
        False, {"from": management}
    )
    tx = strategy.harvest()
    withdrawnAmount = tx.events["TokenExchange"]['tokens_bought']
    # the next line don't pass because this strategy is affected by slippage when swapping
    # assert pytest.approx(token.balanceOf(vault.address), el=RELATIVE_APPROX) == price * amount / 1e18
    assert withdrawnAmount >= amount * 0.995
    assert token.balanceOf(vault) >= amount * 0.995  # 0.5% max slippage
    assert underlying_token.balanceOf(strategy) <= 2


def test_revoke_strategy_from_strategy(
    chain, token, vault, strategy, amount, gov, user, idleCDO, RELATIVE_APPROX, steth_price_feed, underlying_token, keeper, management
):
    # Deposit to the vault and harvest
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})

    chain.sleep(1)
    strategy.harvest()
    minted_tranche = strategy.totalTranches()

    assert (
        pytest.approx(
            strategy.estimatedTotalAssets(),
            rel=RELATIVE_APPROX
        ) == get_estimate_total_assets(strategy, steth_price_feed, idleCDO, minted_tranche)
    )
    strategy.setEmergencyExit()
    chain.sleep(1)

    strategy.setDoHealthCheck(
        False, {"from": management}
    )
    tx = strategy.harvest()
    withdrawnAmount = tx.events["TokenExchange"]['tokens_bought']

    # the next line don't pass because this strategy is affected by slippage when swapping
    # assert pytest.approx(token.balanceOf(vault.address), el=RELATIVE_APPROX) == price * amount / 1e18
    assert withdrawnAmount >= amount * 0.995
    assert token.balanceOf(vault) >= amount * 0.995  # 0.5% max slippage
    assert underlying_token.balanceOf(strategy) <= 2
