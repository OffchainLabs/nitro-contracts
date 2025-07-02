import { ethers } from 'hardhat'
import '@nomiclabs/hardhat-ethers'
import { deployAllContracts, _isRunningOnArbitrum } from './deploymentUtils'
import { maxDataSize as defaultMaxDataSize } from './config'

import { ArbSys__factory } from '../build/types'

async function main() {
  let signer
  if (process.env.DEPLOYER_PRIVKEY !== undefined) {
    signer = new ethers.Wallet(
      process.env.DEPLOYER_PRIVKEY as string,
      ethers.provider
    )
  } else {
    const signers = await ethers.getSigners()
    signer = signers[0]
  }

  const maxDataSize =
    process.env.MAX_DATA_SIZE !== undefined
      ? Number(process.env.MAX_DATA_SIZE)
      : defaultMaxDataSize

  console.log('Deploying contracts with maxDataSize:', maxDataSize)
  if (process.env['IGNORE_MAX_DATA_SIZE_WARNING'] !== 'true') {
    let isArbitrum = await _isRunningOnArbitrum(signer)
    if (isArbitrum && (maxDataSize as number) !== 104857) {
      throw new Error(
        'maxDataSize should be 104857 when the parent chain is Arbitrum (set IGNORE_MAX_DATA_SIZE_WARNING to ignore)'
      )
    } else if (!isArbitrum && (maxDataSize as number) !== 117964) {
      throw new Error(
        'maxDataSize should be 117964 when the parent chain is not Arbitrum (set IGNORE_MAX_DATA_SIZE_WARNING to ignore)'
      )
    }
  } else {
    console.log('Ignoring maxDataSize warning')
  }

  // Deploying all contracts
  const factoryOwner = process.env.FACTORY_OWNER
  if (!factoryOwner) {
    throw new Error('FACTORY_OWNER environment variable is not set')
  }
  await deployAllContracts(signer, factoryOwner, ethers.BigNumber.from(maxDataSize), true)
}

main()
  .then(() => process.exit(0))
  .catch((error: Error) => {
    console.error(error)
    process.exit(1)
  })
