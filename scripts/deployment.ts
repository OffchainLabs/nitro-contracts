import { ethers } from 'hardhat'
import '@nomiclabs/hardhat-ethers'
import { deployAllContracts, _isRunningOnArbitrum, _isRunningOnL1 } from './deploymentUtils'
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
    let isL1 = await _isRunningOnL1(signer)
    if (!isL1 && (maxDataSize as number) !== 104857) {
      throw new Error(
        'maxDataSize should be 104857 when the parent chain is not L1 (set IGNORE_MAX_DATA_SIZE_WARNING to ignore)'
      )
    } else if (isL1 && (maxDataSize as number) !== 117964) {
      throw new Error(
        'maxDataSize should be 117964 when the parent chain is L1 (set IGNORE_MAX_DATA_SIZE_WARNING to ignore)'
      )
    }
  } else {
    console.log('Ignoring maxDataSize warning')
  }

  // Verification of contracts
  // (If undefined, default "true" is used; if anything other than "false" is set, verification is disabled)
  const verifyContracts =
    process.env.DISABLE_VERIFICATION === undefined
      ? undefined
      : process.env.DISABLE_VERIFICATION === 'false'

  // Deploying all contracts
  const factoryOwner = process.env.FACTORY_OWNER
  if (!factoryOwner) {
    throw new Error('FACTORY_OWNER environment variable is not set')
  }
  await deployAllContracts(
    signer,
    factoryOwner,
    ethers.BigNumber.from(maxDataSize),
    verifyContracts
  )
}

main()
  .then(() => process.exit(0))
  .catch((error: Error) => {
    console.error(error)
    process.exit(1)
  })
