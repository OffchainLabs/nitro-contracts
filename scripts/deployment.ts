import { ethers } from 'hardhat'
import '@nomiclabs/hardhat-ethers'
import { deployAllContracts, _isRunningOnArbitrum } from './deploymentUtils'
import { maxDataSize } from './config'

import {
  ArbSys__factory
} from '../build/types'

async function main() {
  const [signer] = await ethers.getSigners()
  
  console.log('Deploying contracts with maxDataSize:', maxDataSize)
  if (process.env['IGNORE_MAX_DATA_SIZE_WARNING'] !== 'true') {
    let isArbitrum = await _isRunningOnArbitrum(signer)
    if (isArbitrum && maxDataSize as any !== 104857) {
      throw new Error('maxDataSize should be 104857 when the parent chain is Arbitrum (set IGNORE_MAX_DATA_SIZE_WARNING to ignore)')
    } else if (!isArbitrum && maxDataSize as any !== 117964) {
      throw new Error('maxDataSize should be 117964 when the parent chain is not Arbitrum (set IGNORE_MAX_DATA_SIZE_WARNING to ignore)')
    }
  } else {
    console.log('Ignoring maxDataSize warning')
  }

  try {
    // Deploying all contracts
    const contracts = await deployAllContracts(
      signer,
      ethers.BigNumber.from(maxDataSize),
      true
    )

    // Call setTemplates with the deployed contract addresses
    console.log('Waiting for the Template to be set on the Rollup Creator')
    await contracts.rollupCreator.setTemplates(
      contracts.bridgeCreator.address,
      contracts.osp.address,
      contracts.challengeManager.address,
      contracts.rollupAdmin.address,
      contracts.rollupUser.address,
      contracts.upgradeExecutor.address,
      contracts.validatorUtils.address,
      contracts.validatorWalletCreator.address,
      contracts.deployHelper.address
    )
    console.log('Template is set on the Rollup Creator')
  } catch (error) {
    console.error(
      'Deployment failed:',
      error instanceof Error ? error.message : error
    )
  }
}

main()
  .then(() => process.exit(0))
  .catch((error: Error) => {
    console.error(error)
    process.exit(1)
  })
