from pathlib import Path

from brownie import TracnheStrategy, StEthTrancheStrategy, accounts, config, network, project, web3
from eth_utils import is_checksum_address
import click

from tests.conftest import sushiswap_router

API_VERSION = config["dependencies"][0].split("@")[-1]
Vault = project.load(
    Path.home() / ".brownie" / "packages" / config["dependencies"][0]
).Vault

sushiswap_router = "0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F"


def get_address(msg: str, default: str = None) -> str:
    val = click.prompt(msg, default=default)

    # Keep asking user for click.prompt until it passes
    while True:

        if is_checksum_address(val):
            return val
        elif addr := web3.ens.address(val):
            click.echo(f"Found ENS '{val}' [{addr}]")
            return addr

        click.echo(
            f"I'm sorry, but '{val}' is not a checksummed address or valid ENS record"
        )
        # NOTE: Only display default once
        val = click.prompt(msg)


def main():
    print(f"You are using the '{network.show_active()}' network")
    dev = accounts.load(click.prompt(
        "Account", type=click.Choice(accounts.load())))
    print(f"You are using: 'dev' [{dev.address}]")

    if input("Is there a Vault for this strategy already? y/[N]: ").lower() == "y":
        vault = Vault.at(get_address("Deployed Vault: "))
        assert vault.apiVersion() == API_VERSION
    else:
        print("You should deploy one vault using scripts from Vault project")
        return  # TODO: Deploy one using scripts from Vault project

    tranche_type = input(
        "Is there a Vault for this strategy already? y/[N]: ").upper()
    assert tranche_type == "AA" or tranche_type == "BB"
    idleCDO = input("Input IdleCDO")
    print(
        f"""
    Strategy Parameters

       api: {API_VERSION}
     token: {vault.token()}
      name: '{vault.name()}'
    symbol: '{vault.symbol()}'
    """
    )
    publish_source = click.confirm("Verify source on etherscan?")
    if input("Deploy Strategy? y/[N]: ").lower() != "y":
        return

    is_AA = tranche_type == "AA"
    strategy = TracnheStrategy.deploy(vault, idleCDO, is_AA, sushiswap_router, {
        "from": dev}, publish_source=publish_source)
