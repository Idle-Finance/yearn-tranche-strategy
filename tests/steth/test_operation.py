import brownie
import pytest


def test_operation_reverts(
    chain, accounts, token, vault, strategy, user, strategist, amount, RELATIVE_APPROX, steth_price_feed, underlying_token
):
    # Deposit to the vault
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    assert token.balanceOf(vault.address) == amount

    # harvest
    chain.sleep(1)
    strategy.harvest()
    (price, _) = steth_price_feed.current_price()
    assert (
        pytest.approx(strategy.estimatedTotalAssets(),
                      rel=RELATIVE_APPROX) == price * amount / 1e18
    )

    # tend()
    strategy.tend()

    # withdrawal
    # NOTE: This loss protection is put in place to revert if losses from
    #       withdrawing are more than what is considered acceptable.
    with brownie.reverts():
        vault.withdraw({"from": user})


def test_operation(
    chain, accounts, token, vault, strategy, user, strategist, amount, RELATIVE_APPROX, steth_price_feed, underlying_token,
):
    # Deposit to the vault
    user_balance_before = token.balanceOf(user)
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    assert token.balanceOf(vault.address) == amount

    # harvest
    chain.sleep(1)
    strategy.harvest()
    (price, _) = steth_price_feed.current_price()
    assert (
        pytest.approx(strategy.estimatedTotalAssets(),
                      rel=RELATIVE_APPROX) == price * amount / 1e18
    )

    # tend()
    strategy.tend()
    # harvest
    strategy.harvest()
    chain.sleep(3600 * 12)  # 12 hrs needed for profits to unlock

    # withdrawal
    vault.withdraw({"from": user})

    # 0.5% max slippage
    assert (token.balanceOf(user) >= user_balance_before * 0.995)
    assert token.balanceOf(strategy) <= 2
    assert underlying_token.balanceOf(strategy) <= 2


def test_emergency_exit(
    chain, accounts, token, vault, strategy, user, strategist, amount, RELATIVE_APPROX, steth_price_feed
):
    # Deposit to the vault
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    chain.sleep(1)
    strategy.harvest()

    (price, _) = steth_price_feed.current_price()
    assert (
        pytest.approx(strategy.estimatedTotalAssets(),
                      rel=RELATIVE_APPROX) == price * amount / 1e18
    )

    # set emergency and exit
    strategy.setEmergencyExit()
    chain.sleep(1)
    strategy.harvest()

    (price, _) = steth_price_feed.current_price()
    assert strategy.estimatedTotalAssets() <= 2
    assert token.balanceOf(vault) >= amount * 0.995  # 0.5% max slippage


def test_profitable_harvest(
    chain, accounts, token, vault, strategy, user, amount, RELATIVE_APPROX, steth_price_feed, whale
):
    # Deposit to the vault
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    assert token.balanceOf(vault.address) == amount

    # Harvest 1: Send funds through the strategy
    chain.sleep(1)
    strategy.harvest()

    (price, _) = steth_price_feed.current_price()
    assert (
        pytest.approx(strategy.estimatedTotalAssets(),
                      rel=RELATIVE_APPROX) == price * amount / 1e18
    )

    # TODO: Add some code before harvest #2 to simulate earning yield
    before_pps = vault.pricePerShare()

    days = 14
    chain.sleep(days * 24 * 60 * 60)
    chain.mine(1)

    # send some steth to simulate profit. 10% apr
    rewards_amount = amount / 10 / 365 * days
    token.transfer(strategy, rewards_amount, {'from': whale})

    # Harvest 2: Realize profit
    chain.sleep(1)
    strategy.harvest()
    chain.mine(1)

    profit = token.balanceOf(vault.address)  # Profits go to vault
    # TODO: Uncomment the lines below
    assert strategy.trancheBalanceInWant() + profit > amount
    assert vault.pricePerShare() >= before_pps


def test_change_debt(
    chain, gov, token, vault, strategy, user, strategist, amount, RELATIVE_APPROX, steth_price_feed
):
    # Deposit to the vault and harvest
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    vault.updateStrategyDebtRatio(strategy.address, 5_000, {"from": gov})
    chain.sleep(1)
    strategy.harvest()
    half = int(amount / 2)

    (price, _) = steth_price_feed.current_price()
    assert pytest.approx(strategy.estimatedTotalAssets(),
                         rel=RELATIVE_APPROX) == price * half / 1e18

    vault.updateStrategyDebtRatio(strategy.address, 10_000, {"from": gov})
    chain.sleep(1)
    tx = strategy.harvest()
    (price, _) = steth_price_feed.current_price()

    # assert pytest.approx(strategy.estimatedTotalAssets(),
    #                      rel=RELATIVE_APPROX) == price * half / 1e18 + estimatedTotalAssetsBefore
    assert 0.995 * amount <= strategy.estimatedTotalAssets() <= price * \
        amount / 1e18

    # In order to pass this tests, you will need to implement prepareReturn.
    # TODO: uncomment the following lines.
    vault.updateStrategyDebtRatio(strategy.address, 5_000, {"from": gov})
    chain.sleep(1)
    tx = strategy.harvest()

    (price, _) = steth_price_feed.current_price()
    assert 0.995 * half <= strategy.estimatedTotalAssets() <= price * half / 1e18
    # assert pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX*10) == (
    #     estimatedTotalAssetsBefore - tokens_sold * price / 1e18)


def test_sweep(gov, vault, strategy, token, user, amount, dai):
    # Strategy want token doesn't work
    token.transfer(strategy, amount, {"from": user})
    assert token.address == strategy.want()
    assert token.balanceOf(strategy) > 0
    with brownie.reverts("!want"):
        strategy.sweep(token, {"from": gov})

    # Vault share token doesn't work
    with brownie.reverts("!shares"):
        strategy.sweep(vault.address, {"from": gov})

    # TODO: If you add protected tokens to the strategy.
    # Protected token doesn't work
    # with brownie.reverts("!protected"):
    #     strategy.sweep(protected_token, {"from": gov})
    dai_amount = 100 * 1e18
    before_balance = dai.balanceOf(gov)
    dai.transfer(strategy, dai_amount, {"from": user})
    assert dai.address != strategy.want()

    strategy.sweep(dai, {"from": gov})

    assert dai.balanceOf(strategy) == 0
    assert dai.balanceOf(gov) == (dai_amount + before_balance)


def test_triggers(
    chain, gov, vault, strategy, token, amount, user, strategist
):
    # Deposit to the vault and harvest
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    vault.updateStrategyDebtRatio(strategy.address, 5_000, {"from": gov})
    chain.sleep(1)
    strategy.harvest()

    strategy.harvestTrigger(0)
    strategy.tendTrigger(0)
