import pytest


def test_revoke_strategy_from_vault(
    chain, token, vault, strategy, amount, user, gov, RELATIVE_APPROX, steth_price_feed, underlying_token
):
    # Deposit to the vault and harvest
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})

    chain.sleep(1)
    strategy.harvest()

    (price, _) = steth_price_feed.current_price()
    assert pytest.approx(strategy.estimatedTotalAssets(),
                         rel=RELATIVE_APPROX) == price * amount / 1e18

    vault.revokeStrategy(strategy.address, {"from": gov})
    chain.sleep(1)

    tx = strategy.harvest()
    withdrawnAmount = tx.events["TokenExchange"]['tokens_bought']
    # the next line don't pass because this strategy is affected by slippage when swapping
    # assert pytest.approx(token.balanceOf(vault.address), el=RELATIVE_APPROX) == price * amount / 1e18
    assert withdrawnAmount >= amount * 0.995
    assert token.balanceOf(vault) >= amount * \
        0.995  # 0.5% max slippage
    assert underlying_token.balanceOf(strategy) <= 2


def test_revoke_strategy_from_strategy(
    chain, token, vault, strategy, amount, gov, user, RELATIVE_APPROX, steth_price_feed, underlying_token
):
    # Deposit to the vault and harvest
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})

    chain.sleep(1)
    strategy.harvest()

    (price, _) = steth_price_feed.current_price()
    assert pytest.approx(strategy.estimatedTotalAssets(),
                         rel=RELATIVE_APPROX) == price * amount / 1e18

    strategy.setEmergencyExit()
    chain.sleep(1)

    tx = strategy.harvest()
    withdrawnAmount = tx.events["TokenExchange"]['tokens_bought']

    # the next line don't pass because this strategy is affected by slippage when swapping
    # assert pytest.approx(token.balanceOf(vault.address), el=RELATIVE_APPROX) == price * amount / 1e18
    assert withdrawnAmount >= amount * 0.995
    assert token.balanceOf(vault) >= amount * \
        0.995  # 0.5% max slippage
    assert underlying_token.balanceOf(strategy) <= 2
