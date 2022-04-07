import brownie
from brownie import *
from helpers.constants import MaxUint256
from helpers.SnapshotManager import SnapshotManager
from helpers.time import days

"""
  TODO: Put your tests here to prove the strat is good!
  See test_harvest_flow, for the basic tests
  See test_strategy_permissions, for tests at the permissions level
"""


def test_my_custom_test(deployed):
	assert True

def test_levered_deposit(deployer, vault, strategy, want, governance, gToken, gDebtToken):
    startingBalance = want.balanceOf(deployer)

    depositAmount = startingBalance // 2
    assert startingBalance >= depositAmount
    assert startingBalance >= 0
    print(f'Starting Balance : {startingBalance}')
    print(f'Deposit Amount : {depositAmount}')
    # End Setup

    # Deposit
    assert want.balanceOf(vault) == 0

    want.approve(vault, MaxUint256, {"from": deployer})
    vault.deposit(depositAmount, {"from": deployer})

    available = vault.available()
    assert available > 0

    vault.earn({"from": governance})
    print(f'Strat available :  {strategy.balanceOfPool()}')
    print(f'gToken Amount : {gToken.balanceOf(strategy)}')
    print(f'gDebtToken Amount : {gDebtToken.balanceOf(strategy)}')
    print(f'Net Deposit Amount : {gToken.balanceOf(strategy) - gDebtToken.balanceOf(strategy)}')

    week = 60 * 60 * 24 * 7
    chain.sleep(week)
    chain.mine(10)

    harvest = strategy.harvest({"from": governance})
    event = harvest.events["Debug"]
    print(f'Harvest : {event["value"]}')

    withdraw = strategy.withdraw(1639975987723341826989455, {"from": vault} )
    print(f'gToken Amount : {gToken.balanceOf(strategy)}')
    print(f'gDebtToken Amount : {gDebtToken.balanceOf(strategy)}')
    print(f'Net Deposit Amount : {gToken.balanceOf(strategy) - gDebtToken.balanceOf(strategy)}')
	
	# APR = (52 * (event["value"] / depositAmount)) * 100


