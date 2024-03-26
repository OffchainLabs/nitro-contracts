import { ethers } from 'hardhat'
import '@nomiclabs/hardhat-ethers'
import { deployAllContracts } from '../deploymentUtils'
import { createRollup } from '../rollupCreation'
import { promises as fs } from 'fs'
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

  console.log('Deploy RollupCreator')
  const contracts = await deployAllContracts(deployerWallet, maxDataSize, false)

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
  const chainId = (await deployerWallet.provider.getNetwork()).chainId
  const feeToken = undefined

  console.log(
    'Create rollup on top of chain',
    chainId,
    'using RollupCreator',
    contracts.rollupCreator.address
  )
  const rollupCreationResult = await createRollup(
    deployerWallet,
    true,
    contracts.rollupCreator.address,
    feeToken
  )

  if (!rollupCreationResult) {
    throw new Error('Rollup creation failed')
  }

  /// store deployment address
  // parent deployment info
  const parentDeploymentInfo =
    process.env.PARENT_DEPLOYMENT_INFO !== undefined
      ? process.env.PARENT_DEPLOYMENT_INFO
      : 'deploy.json'
  await fs.writeFile(
    parentDeploymentInfo,
    JSON.stringify(rollupCreationResult, null, 2),
    'utf8'
  )

  // get child deployment info
  const childDeploymentInfo =
    process.env.CHILD_DEPLOYMENT_INFO !== undefined
      ? process.env.CHILD_DEPLOYMENT_INFO
      : 'l2_chain_info.json'
}

main()
  .then(() => process.exit(0))
  .catch((error: Error) => {
    console.error(error)
    process.exit(1)
  })
