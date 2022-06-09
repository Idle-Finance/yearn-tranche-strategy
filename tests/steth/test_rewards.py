import pytest
from brownie import ZERO_ADDRESS
from util import get_estimate_total_assets


def test_operation_gauge(
    chain, accounts, token, vault, strategy, user, amount, idleCDO, gauge, steth_price_feed, gauge_reward, RELATIVE_APPROX
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
    minted_tranche = strategy.totalTranches()

    assert pytest.approx(
        strategy.estimatedTotalAssets(),
        rel=RELATIVE_APPROX) == get_estimate_total_assets(strategy, steth_price_feed, idleCDO, minted_tranche)
    assert gauge.balanceOf(strategy) == minted_tranche

    days = 14
    chain.sleep(days * 24 * 60 * 60)
    chain.mine(1)

    # claim rewards
    strategy.harvest()

    assert gauge.balanceOf(strategy) == minted_tranche
    assert gauge_reward.balanceOf(strategy) > 0
