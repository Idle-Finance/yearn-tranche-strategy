import pytest


def test_operation_multirewards(
    chain, accounts, token, vault, strategy, user, amount, idleCDO, multi_rewards, staking_reward, RELATIVE_APPROX
):
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
        multi_rewards.balanceOf(strategy), rel=RELATIVE_APPROX
    ) == amount * 1e18 / price

    # claim rewards
    strategy.harvest()

    assert staking_reward.balanceOf(strategy) > 0
    assert pytest.approx(
        multi_rewards.balanceOf(strategy), rel=RELATIVE_APPROX
    ) == amount * 1e18 / price


def test_operation_gauge(
    chain, accounts, token, vault, strategy, user, amount, idleCDO, multi_rewards, staking_reward, RELATIVE_APPROX
):
    pass
