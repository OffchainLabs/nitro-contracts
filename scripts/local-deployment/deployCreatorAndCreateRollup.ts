import { ethers } from 'hardhat'
import '@nomiclabs/hardhat-ethers'
import { deployAllContracts } from '../deploymentUtils'
import { createRollup } from '../rollupCreation'
import { sleep } from '../testSetup'
import { BigNumber } from 'ethers'

async function main() {
  let deployerPrivKey = process.env.DEPLOYER_PRIVKEY as string
  if (!deployerPrivKey) {
    throw new Error('DEPLOYER_PRIVKEY not set')
  }

  let parentChainRpc = process.env.PARENT_CHAIN_RPC as string
  if (!parentChainRpc) {
    throw new Error('PARENT_CHAIN_RPC not set')
  }

  const deployerWallet = new ethers.Wallet(
    deployerPrivKey,
    new ethers.providers.JsonRpcProvider(parentChainRpc)
  )

  const maxDataSize =
    process.env.MAX_DATA_SIZE !== undefined
      ? ethers.BigNumber.from(process.env.MAX_DATA_SIZE)
      : ethers.BigNumber.from(117964)

  try {
    console.log('Deploy RollupCreator and templates')
    const contracts = await deployAllContracts(
      deployerWallet,
      maxDataSize,
      false
    )

    console.log('Set templates on the Rollup Creator')
    await (
      await contracts.rollupCreator.setTemplates(
        contracts.bridgeCreator.address,
        contracts.osp.address,
        contracts.challengeManager.address,
        contracts.rollupAdmin.address,
        contracts.rollupUser.address,
        contracts.upgradeExecutor.address,
        contracts.validatorUtils.address,
        contracts.validatorWalletCreator.address,
        contracts.deployHelper.address,
        { gasLimit: BigNumber.from('300000') }
      )
    ).wait()

    // Create rollup
    console.log(
      `Create rollup on top of chain ${
        (await deployerWallet.provider.getNetwork()).chainId
      } using RollupCreator ${contracts.rollupCreator.address}`
    )

    const feeToken = undefined
    await createRollup(
      deployerWallet,
      true,
      contracts.rollupCreator.address,
      feeToken
    )
    console.log('Rollup created')
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
