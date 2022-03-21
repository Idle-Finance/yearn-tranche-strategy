from brownie import brownie


def test_update(
    chain, token, vault, strategy, user, keeper
):
    strategy.setMaxSlippage(0, {"from": keeper})
    assert strategy.maximumSlippage() == 0

    strategy.setMaxSlippage(50, {"from": keeper})
    assert strategy.maximumSlippage() == 50

    with brownie.reverts():
        strategy.setMaxSlippage(100_000, {"from": keeper})

    with brownie.reverts():
        strategy.setMaxSlippage(50, {"from": user})
