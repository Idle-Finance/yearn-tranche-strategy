import pytest
from brownie import ZERO_ADDRESS


def test_operation_gauge(
    chain, accounts, token, vault, strategy, user, amount, idleCDO, gauge, staking_reward, RELATIVE_APPROX
):
    if gauge == ZERO_ADDRESS:
        return
    # Deposit to the vault
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    assert token.balanceOf(vault.address) == amount

    # harvest
    chain.sleep(1)
    strategy.harvest()

    price = idleCDO.virtualPrice(strategy.tranche())
    assert pytest.approx(
        strategy.estimatedTotalAssets(),
        rel=RELATIVE_APPROX) == amount

    days = 14
    chain.sleep(days * 24 * 60 * 60)
    chain.mine(1)

    assert staking_reward.balanceOf(strategy) == 0
    assert pytest.approx(
        gauge.balanceOf(strategy), rel=RELATIVE_APPROX
    ) == amount * 1e18 / price

    # claim rewards
    strategy.harvest()

    assert staking_reward.balanceOf(strategy) > 0
    assert pytest.approx(
        gauge.balanceOf(strategy), rel=RELATIVE_APPROX
    ) == amount * 1e18 / price
