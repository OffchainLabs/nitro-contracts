import { ethers } from 'hardhat'
import { Wallet } from 'ethers'
import fs from 'fs'
import { getConfig } from './boldUpgradeCommon'
import { templates, verifyCreatorTemplates } from './files/templatesV3.1'
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

  // Get the chain id to get the templates to update to
  const { chainId } = await l1Rpc.getNetwork()
  if (!templates[chainId]) {
    throw new Error(`Parent chain id ${chainId} not supported`)
  }
  const contractTemplates = templates[chainId]
  await verifyCreatorTemplates(l1Rpc, contractTemplates)

  const disableVerification = process.env.DISABLE_VERIFICATION === 'true'
  const deployedAndBold = await deployBoldUpgrade(
    wallet,
    config,
    contractTemplates,
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
