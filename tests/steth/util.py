def get_estimate_total_assets(
    strategy, steth_price_feed, idleCDO, tranche_price_when_minted, amount
):
    steth_price, _ = steth_price_feed.current_price()
    tranche_price = idleCDO.virtualPrice(strategy.tranche())

    want_balance = strategy.wantBal()
    minted_tranche = amount * 1e18 / tranche_price_when_minted
    return (minted_tranche * tranche_price / 1e18 * steth_price / 1e18) + want_balance
