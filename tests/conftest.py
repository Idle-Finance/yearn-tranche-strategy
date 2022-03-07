import pytest
from brownie import config
from brownie import Contract

STRATEGY_CONFIGS = {
    "STETH": {
        "idleCDO": "0x34dcd573c5de4672c8248cd12a99f875ca112ad8",
        "tranche_type": "AA",
        "whale": "0xeb9c1ce881f0bdb25eac4d74fccbacf4dd81020a",
        "token_address": "0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84",
        "amount": 100 * 10**18,  # 100 STETH
        "wstEth_address": "0x7f39c581f595b53c5cb19bd0b3f8da6c935e2ca0"
    },
    # "WETH": {
    #     "idleCDO": "",
    #     "tranche_type": "AA",
    #     # Axie Infinity: Ronin Bridge
    #     "whale": "0x1A2a1c938CE3eC39b6D47113c7955bAa9DD454F2",
    #     "token_address": "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
    #     "amount": "100"  # 100 ETH
    # },
    # "FEI": {
    #     "idleCDO": "0x77648a2661687ef3b05214d824503f6717311596",
    #     "whale": "0xba12222222228d8ba445958a75a0704d566bf2c8",
    #     "token_address": "0x956F47F50A910163D8BF957Cf5846D573E7f87CA  ",
    #     "amount": "10000"  # 10000 ** 1e18
    # },
    # "DAI": {
    #     "idleCDO": "0xd0dbcd556ca22d3f3c142e9a3220053fd7a247bc",
    #     "whale": "0x40ec5b33f54e0e8a33a975908c5ba1c14e5bbbdf",
    #     "token_address": "0x6B175474E89094C44Da98b954EedeAC495271d0F  ",
    #     "amount": "10000"  # 10000 ** 1e18
    # }
}


@pytest.fixture
def gov(accounts):
    yield accounts.at("0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52", force=True)


@pytest.fixture
def user(accounts):
    yield accounts[0]


@pytest.fixture
def rewards(accounts):
    yield accounts[1]


@pytest.fixture
def guardian(accounts):
    yield accounts[2]


@pytest.fixture
def management(accounts):
    yield accounts[3]


@pytest.fixture
def strategist(accounts):
    yield accounts[4]


@pytest.fixture
def keeper(accounts):
    yield accounts[5]


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
    yield Contract(strategy_config["idleCDO"])


@pytest.fixture
def tranche(idleCDO, strategy_config):
    tranche_address = idleCDO.AATranche(
    ) if strategy_config['tranche_type'] == 'AA' else idleCDO.BBTranche()
    yield Contract(tranche_address)


@pytest.fixture
def sushiswap_router():
    yield Contract("0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F")


@pytest.fixture
def amount(accounts, token, user, strategy_config):
    # In order to get some funds for the token you are about to use,
    # it impersonate an exchange address to use it's funds.
    reserve = accounts.at(strategy_config["whale"], force=True)
    amount = strategy_config["amount"]
    token.transfer(user, amount, {"from": reserve})
    yield amount


@pytest.fixture
def weth():
    token_address = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
    yield Contract(token_address)


@pytest.fixture
def weth_amout(user, weth):
    weth_amout = 10 ** 18
    user.transfer(weth, weth_amout)
    yield weth_amout


@pytest.fixture
def vault(pm, gov, rewards, guardian, management, token):
    Vault = pm(config["dependencies"][0]).Vault
    vault = guardian.deploy(Vault)
    vault.initialize(token, gov, rewards, "", "", guardian, management)
    vault.setDepositLimit(2 ** 256 - 1, {"from": gov})
    vault.setManagement(management, {"from": gov})
    yield vault


@pytest.fixture
def strategy(strategist, keeper, vault, idleCDO, sushiswap_router, Strategy, gov, strategy_config):
    is_AA = strategy_config['tranche_type'] == 'AA'
    # give contract factory and its constructor parammeters
    strategy = strategist.deploy(
        Strategy, vault, idleCDO, is_AA, sushiswap_router
    )
    strategy.setKeeper(keeper)
    vault.addStrategy(strategy, 10_000, 0, 2 ** 256 - 1, 1_000, {"from": gov})
    yield strategy


@pytest.fixture(scope="session")
def RELATIVE_APPROX():
    yield 1e-5
