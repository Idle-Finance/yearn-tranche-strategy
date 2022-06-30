from brownie import ZERO_ADDRESS, Contract
import brownie


def test_enable_disable_staking(
    chain, token, vault, strategy, user, management
):
    if strategy.gauge() == ZERO_ADDRESS:
        with brownie.reverts():
            strategy.enableStaking({"from": management})
    else:
        strategy.enableStaking({"from": management})
        assert strategy.enabledStake() is True

    strategy.disableStaking({"from": management})
    assert strategy.enabledStake() is False

    with brownie.reverts():
        strategy.enableStaking({"from": user})


def test_update_reward_tokens(
    chain, token, vault, strategy, user, management, trade_factory, gov
):
    ldo = "0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32"
    rewards = [ldo]  # Example rewards

    with brownie.reverts():
        strategy.setRewardTokens(rewards, {"from": user})

    strategy.setRewardTokens(rewards, {"from": management})
    assert strategy.getRewardTokens() == rewards


def test_update_trade_factory(
    chain, token, vault, strategy, user, gov, management, trade_factory
):
    # initial setup
    ldo = "0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32"
    rewards = [ldo]  # Example rewards

    strategy.setRewardTokens(rewards, {"from": management})
    assert strategy.getRewardTokens() == rewards

    # check
    strategy.updateTradeFactory(ZERO_ADDRESS, {"from": gov})
    assert strategy.getRewardTokens() == rewards
    assert strategy.tradeFactory() == ZERO_ADDRESS

    with brownie.reverts():
        strategy.updateTradeFactory(trade_factory, {"from": user})
    assert strategy.tradeFactory() == ZERO_ADDRESS


def test_set_dp(
    chain, token, vault, strategy, user, gov, distributor_proxy
):
    dp = distributor_proxy
    if dp == ZERO_ADDRESS:
        return
    strategy.setDistributorProxy(dp, {"from": gov})
    assert strategy.distributorProxy() == dp

    with brownie.reverts():
        strategy.setDistributorProxy(dp, {"from": user})


def test_set_gauge(
    chain, token, vault, strategy, user, gov, gauge
):
    if gauge == ZERO_ADDRESS:
        return
    strategy.setGauge(gauge, {"from": gov})
    assert strategy.gauge() == gauge

    with brownie.reverts():
        strategy.setGauge(gauge, {"from": user})


def test_check_staked_before_migrating(
    chain, token, vault, strategy, user, gov, management, amount
):
    # default
    assert strategy.checkStakedBeforeMigrating() is True

    # only authorized address can call this function
    with brownie.reverts():
        strategy.setCheckStakedBeforeMigrating(False, {"from": user})

    # tranches can not be transferred when checkStakedBeforeMigrating is True
    assert strategy.checkStakedBeforeMigrating() is True
    with brownie.reverts():
        strategy.sweep(strategy.tranche(), {"from": gov})

    strategy.setCheckStakedBeforeMigrating(False, {"from": gov})
    assert strategy.checkStakedBeforeMigrating() is False

    # tranches can not be transferred when checkStakedBeforeMigrating is False
    total_tranches = strategy.totalTranches()
    strategy.sweep(strategy.tranche(), {"from": gov})
    assert Contract(strategy.tranche()).balanceOf(gov) == total_tranches
