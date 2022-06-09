# TODO: Add tests that show proper operation of this strategy through "emergencyExit"
#       Make sure to demonstrate the "worst case losses" as well as the time it takes

from brownie import ZERO_ADDRESS
import brownie
import pytest
from util import get_estimate_total_assets


def test_vault_shutdown_can_withdraw_reverts(
    chain, token, vault, strategy, user, idleCDO, amount, RELATIVE_APPROX, steth_price_feed
):
    # Deposit in Vault
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    assert token.balanceOf(vault.address) == amount

    if token.balanceOf(user) > 0:
        token.transfer(ZERO_ADDRESS, token.balanceOf(user), {"from": user})

    # Harvest 1: Send funds through the strategy
    strategy.harvest()
    chain.sleep(3600 * 7)
    chain.mine(1)
    minted_tranche = strategy.totalTranches()

    assert (
        pytest.approx(
            strategy.estimatedTotalAssets(),
            rel=RELATIVE_APPROX
        ) == get_estimate_total_assets(strategy, steth_price_feed, idleCDO, minted_tranche)
    )
    # Set Emergency
    vault.setEmergencyShutdown(True)

    # Withdraw (does it work, do you get what you expect)
    # NOTE: This loss protection is put in place to revert if losses from
    #       withdrawing are more than what is considered acceptable.
    # with brownie.reverts():
    #     vault.withdraw({"from": user})


def test_vault_shutdown_can_withdraw(
    chain, token, vault, strategy, user, idleCDO, amount, RELATIVE_APPROX, steth_price_feed, accounts, whale
):
    # Deposit in Vault
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    assert token.balanceOf(vault.address) == amount

    if token.balanceOf(user) > 0:
        token.transfer(ZERO_ADDRESS, token.balanceOf(user), {"from": user})

    # Harvest 1: Send funds through the strategy
    strategy.harvest()
    chain.sleep(3600 * 7)
    chain.mine(1)
    minted_tranche = strategy.totalTranches()

    assert (
        pytest.approx(
            strategy.estimatedTotalAssets(),
            rel=RELATIVE_APPROX
        ) == get_estimate_total_assets(strategy, steth_price_feed, idleCDO, minted_tranche)
    )
    days = 14
    chain.sleep(days * 24 * 60 * 60)
    chain.mine(1)

    # send some steth to simulate profit. 10% apr
    rewards_amount = amount / 10 / 365 * days
    token.transfer(strategy, rewards_amount, {'from': whale})

    # Set Emergency
    vault.setEmergencyShutdown(True)

    # Withdraw (does it work, do you get what you expect)
    vault.withdraw({"from": user})

    assert token.balanceOf(user) >= (
        amount + rewards_amount) * 0.995  # 0.5% max slippage


# when steth price is lower than an acceptable price, swapping eth for steth results in an acceptable loss.
def test_basic_shutdown(
    chain, token, vault, strategy, user, strategist, idleCDO, amount, RELATIVE_APPROX, steth_price_feed, keeper, management
):
    # Deposit to the vault
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    assert token.balanceOf(vault.address) == amount

    # Harvest 1: Send funds through the strategy
    strategy.harvest()
    chain.mine(100)
    minted_tranche = strategy.totalTranches()

    assert (
        pytest.approx(
            strategy.estimatedTotalAssets(),
            rel=RELATIVE_APPROX
        ) == get_estimate_total_assets(strategy, steth_price_feed, idleCDO, minted_tranche)
    )
    # Earn interest
    chain.sleep(3600 * 24 * 1)  # Sleep 1 day
    chain.mine(1)

    # Harvest 2: Realize profit
    strategy.harvest()
    chain.sleep(3600 * 6)  # 6 hrs needed for profits to unlock
    chain.mine(1)

    #  Set emergency
    strategy.setEmergencyExit({"from": strategist})
    strategy.setDoHealthCheck(
        False, {"from": management}
    )
    strategy.harvest()  # Remove funds from strategy

    # The vault has all funds
    assert token.balanceOf(strategy) <= 2
    assert token.balanceOf(vault) >= amount * 0.995  # 0.5% max slippage
    # NOTE: May want to tweak this based on potential loss during migration
