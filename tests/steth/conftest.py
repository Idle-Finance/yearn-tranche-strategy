import pytest
from brownie import config, Contract, interface

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
        # want address (weth)
        "token_address": "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
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
    yield interface.ERC20(strategy_config["token_address"])


@pytest.fixture
def idleCDO(strategy_config):
    yield Contract(strategy_config["idleCDO"]['address'])


@pytest.fixture
def stable_swap():
    yield Contract("0xDC24316b9AE028F1497c275EB9192a3Ea0f67022")


@pytest.fixture
def steth_price_feed():
    yield Contract("0xAb55Bf4DfBf469ebfe082b7872557D1F87692Fe6")


@pytest.fixture
def underlying_token(strategy_config):
    yield interface.ERC20(strategy_config["idleCDO"]['underlying_token'])


@pytest.fixture
def dai(accounts, user):
    reserve = accounts.at(
        "0x40ec5b33f54e0e8a33a975908c5ba1c14e5bbbdf", force=True)
    dai = Contract("0x6B175474E89094C44Da98b954EedeAC495271d0F")
    amount = 1000 * 1e18
    dai.transfer(
        user, amount, {"from": reserve}
    )
    yield dai


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
def whale(accounts, strategy_config):
    whale = accounts.at(strategy_config["whale"], force=True)
    yield whale


@pytest.fixture
def vault(pm, gov, rewards, guardian, management, token):
    Vault = pm(config["dependencies"][0]).Vault
    vault = guardian.deploy(Vault)
    vault.initialize(token, gov, rewards, "", "", guardian, management)
    vault.setDepositLimit(2 ** 256 - 1, {"from": gov})
    vault.setManagement(management, {"from": gov})
    yield vault


@pytest.fixture
def strategy(strategist, keeper, vault, idleCDO, sushiswap_router, gov, strategy_config, trade_factory, staking_reward, StEthTrancheStrategy, multi_rewards, ymechs_safe, healthCheck):
    is_AA = strategy_config['tranche_type'] == 'AA'

    _Strategy = StEthTrancheStrategy
    # give contract factory and its constructor parammeters
    strategy = strategist.deploy(
        _Strategy, vault, idleCDO, is_AA, sushiswap_router, [], multi_rewards, healthCheck
    )
    strategy.setKeeper(keeper)
    vault.addStrategy(strategy, 10_000, 0, 2 ** 256 - 1, 1_000, {"from": gov})
    trade_factory.grantRole(
        trade_factory.STRATEGY(), strategy, {"from": ymechs_safe}
    )
    strategy.updateTradeFactory(trade_factory, {"from": gov})
    rewards = [staking_reward]  # Example rewards
    strategy.setRewardTokens(rewards, {"from": gov})
    strategy.enableStaking({"from": gov})
    yield strategy


@pytest.fixture
def multi_rewards(MultiRewards, idleCDO, strategy_config, gov, staking_reward):
    is_AA = strategy_config['tranche_type'] == 'AA'
    multi_rewards = gov.deploy(
        MultiRewards, gov, idleCDO.AATranche() if is_AA else idleCDO.BBTranche()
    )
    staking_reward.mint(gov, 1e25)
    staking_reward.approve(multi_rewards, 1e25, {"from": gov})

    multi_rewards.addReward(staking_reward, gov,
                            3600 * 24 * 180, {"from": gov})
    multi_rewards.notifyRewardAmount(staking_reward, 1e25, {"from": gov})
    yield multi_rewards


@pytest.fixture(scope="session")
def RELATIVE_APPROX():
    yield 1e-4
