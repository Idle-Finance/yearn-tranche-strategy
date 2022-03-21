import pytest
from brownie import config, Contract

STRATEGY_CONFIGS = {
    "DAI": {
        "idleCDO": {
            "address": "0xd0dbcd556ca22d3f3c142e9a3220053fd7a247bc"
        },
        "tranche_type": "AA",
        "whale": "0x40ec5b33f54e0e8a33a975908c5ba1c14e5bbbdf",
        "token_address": "0x6B175474E89094C44Da98b954EedeAC495271d0F  ",
        "amount": 10000 * 1e18,
        "strategy": "TrancheStrategy"
    },
    # "FEI": {
    #     "idleCDO": {
    #         "address": "0x77648a2661687ef3b05214d824503f6717311596"
    #     },
    #     "tranche_type": "AA",
    #     "whale": "0xba12222222228d8ba445958a75a0704d566bf2c8",
    #     "token_address": "0x956F47F50A910163D8BF957Cf5846D573E7f87CA  ",
    #     "amount": 10000 * 1e18
    #     "strategy": "TrancheStrategy"
    # },
}


@pytest.fixture(params=list(STRATEGY_CONFIGS.keys()))
def strategy_config(request):
    if STRATEGY_CONFIGS[request.param]["tranche_type"] != "AA" and STRATEGY_CONFIGS[request.param]["tranche_type"] != "BB":
        assert False  # invalid tranche type
    # STRATEGY_CONFIGS
    yield STRATEGY_CONFIGS[request.param]


@pytest.fixture
def token(strategy_config):
    # this should be the address of the ERC-20 used by the strategy/vault (DAI)
    yield Contract(strategy_config["token_address"])


@pytest.fixture
def idleCDO(strategy_config):
    yield Contract(strategy_config["idleCDO"]['address'])


@pytest.fixture
def amount(accounts, token, user, strategy_config):
    # In order to get some funds for the token you are about to use,
    # it impersonate an exchange address to use it's funds.
    reserve = accounts.at(strategy_config["whale"], force=True)
    amount = strategy_config["amount"]
    token.transfer(
        user, amount, {"from": reserve}
    )
    yield amount


@pytest.fixture
def vault(pm, gov, rewards, guardian, management, token):
    Vault = pm(config["dependencies"][0]).Vault
    vault = guardian.deploy(Vault)
    vault.initialize(token, gov, rewards, "", "", guardian, management)
    vault.setDepositLimit(2 ** 256 - 1, {"from": gov})
    vault.setManagement(management, {"from": gov})
    yield vault


@pytest.fixture
def strategy(strategist, keeper, vault, idleCDO, sushiswap_router, gov, strategy_config, TrancheStrategy):
    is_AA = strategy_config['tranche_type'] == 'AA'

    _Strategy = TrancheStrategy
    # give contract factory and its constructor parammeters
    strategy = strategist.deploy(
        _Strategy, vault, idleCDO, is_AA, sushiswap_router
    )
    strategy.setKeeper(keeper)
    vault.addStrategy(strategy, 10_000, 0, 2 ** 256 - 1, 1_000, {"from": gov})
    yield strategy


@pytest.fixture(scope="session")
def RELATIVE_APPROX():
    yield 1e-5
