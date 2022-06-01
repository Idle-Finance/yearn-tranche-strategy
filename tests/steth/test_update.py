from re import T
import brownie


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


def test_set_approval_unsafe_price(
    chain, token, vault, strategy, user, keeper, management
):
    strategy.setApprovalUnsafePrice(True, {"from": management})
    assert strategy.isAllowedUnsafePrice() is True

    strategy.setApprovalUnsafePrice(False, {"from": management})
    assert strategy.isAllowedUnsafePrice() is False

    with brownie.reverts():
        strategy.setApprovalUnsafePrice(True, {"from": user})

    with brownie.reverts():
        strategy.setApprovalUnsafePrice(False, {"from": user})
