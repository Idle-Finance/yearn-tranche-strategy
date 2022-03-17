import pytest


def test_revoke_strategy_from_vault(
    chain, token, vault, strategy, amount, user, gov, RELATIVE_APPROX, steth_price_feed
):
    # Deposit to the vault and harvest
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})

    chain.sleep(1)
    strategy.harvest()

    (price, _) = steth_price_feed.safe_price()
    assert pytest.approx(strategy.estimatedTotalAssets(),
                         rel=RELATIVE_APPROX) == price * amount / 1e18

    vault.revokeStrategy(strategy.address, {"from": gov})
    chain.sleep(1)
    strategy.harvest()
    assert pytest.approx(token.balanceOf(vault.address),
                         rel=RELATIVE_APPROX) == price * amount / 1e18


def test_revoke_strategy_from_strategy(
    chain, token, vault, strategy, amount, gov, user, RELATIVE_APPROX, steth_price_feed
):
    # Deposit to the vault and harvest
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})

    chain.sleep(1)
    strategy.harvest()

    (price, _) = steth_price_feed.safe_price()
    assert pytest.approx(strategy.estimatedTotalAssets(),
                         rel=RELATIVE_APPROX) == price * amount / 1e18

    strategy.setEmergencyExit()
    chain.sleep(1)
    strategy.harvest()
    assert pytest.approx(token.balanceOf(vault.address),
                         rel=RELATIVE_APPROX) == price * amount / 1e18
