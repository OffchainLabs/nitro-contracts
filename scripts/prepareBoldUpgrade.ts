import { ethers } from 'hardhat'
import { Wallet } from 'ethers'
import fs from 'fs'
import { getConfig, rollupCreators } from './boldUpgradeCommon'
import { deployBoldUpgrade } from './boldUpgradeFunctions'
import dotenv from 'dotenv'
import path from 'path'

dotenv.config()

async function main() {
  const l1Rpc = ethers.provider

  const l1PrivKey = process.env.L1_PRIV_KEY
  if (!l1PrivKey) {
    throw new Error('L1_PRIV_KEY env variable not set')
  }
  const wallet = new Wallet(l1PrivKey, l1Rpc)

  const configNetworkName = process.env.CONFIG_NETWORK_NAME
  if (!configNetworkName) {
    throw new Error('CONFIG_NETWORK_NAME env variable not set')
  }
  const config = await getConfig(configNetworkName, l1Rpc)

  const deployedContractsDir = process.env.DEPLOYED_CONTRACTS_DIR
  if (!deployedContractsDir) {
    throw new Error('DEPLOYED_CONTRACTS_DIR env variable not set')
  }
  const deployedContractsLocation = path.join(
    deployedContractsDir,
    configNetworkName + 'DeployedContracts.json'
  )

  // Needed to get the addresses of the logic contracts to update
  let rollupCreatorAddress
  if (process.env.TESTNODE_MODE && process.env.ROLLUP_CREATOR_ADDRESS) {
    console.log(
      'Using ROLLUP_CREATOR_ADDRESS from env:',
      process.env.ROLLUP_CREATOR_ADDRESS
    )
    rollupCreatorAddress = process.env.ROLLUP_CREATOR_ADDRESS
  } else {
    const { chainId } = await l1Rpc.getNetwork()
    if (!rollupCreators[chainId]) {
      throw new Error(`Chain id ${chainId} not supported`)
    }
    rollupCreatorAddress = rollupCreators[chainId]
  }

  const disableVerification = process.env.DISABLE_VERIFICATION === 'true'
  const deployedAndBold = await deployBoldUpgrade(
    wallet,
    config,
    rollupCreatorAddress,
    true,
    !disableVerification
  )

  console.log(`Deployed contracts written to: ${deployedContractsLocation}`)
  fs.writeFileSync(
    deployedContractsLocation,
    JSON.stringify({ ...deployedAndBold }, null, 2)
  )
}

main().then(() => console.log('Done.'))
