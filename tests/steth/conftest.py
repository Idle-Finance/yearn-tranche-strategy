import pytest
from brownie import config, Contract

STRATEGY_CONFIGS = {
    "WETH": {
        "idleCDO": {
            "address": "0x34dcd573c5de4672c8248cd12a99f875ca112ad8",  # StETH tranche IdleCDO
            "underlying_token": "0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84",  # steth
            "strat_token": "0x7f39c581f595b53c5cb19bd0b3f8da6c935e2ca0",  # wsteth
        },
        "tranche_type": "AA",
        # Axie Infinity: Ronin Bridge
        "whale": "0x1A2a1c938CE3eC39b6D47113c7955bAa9DD454F2",
        "token_address": "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",  # weth
        "amount": 100 * 1e18,  # 100 ETH
        "strategy": "StEthTrancheStrategy"  # strategy contract name
    },
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
def tranche(idleCDO, strategy_config):
    tranche_address = idleCDO.AATranche(
    ) if strategy_config['tranche_type'] == 'AA' else idleCDO.BBTranche()
    yield Contract(tranche_address)


@pytest.fixture
def steth_price_feed():
    yield Contract("0xAb55Bf4DfBf469ebfe082b7872557D1F87692Fe6")


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
def strategy(strategist, keeper, vault, idleCDO, sushiswap_router, gov, strategy_config, TrancheStrategy, StEthTrancheStrategy):
    is_AA = strategy_config['tranche_type'] == 'AA'

    if strategy_config['strategy'] == 'StEthTrancheStrategy':
        _Strategy = StEthTrancheStrategy
    else:
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