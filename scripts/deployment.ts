import { ethers, network } from 'hardhat'
import '@nomiclabs/hardhat-ethers'
import { deployAllContracts } from './deploymentUtils'
import { maxDataSize } from './config'
import fs from 'fs'

async function main() {
  const [signer] = await ethers.getSigners()
  try {
    const espressoLightClientAddress = process.env.ESPRESSO_LIGHT_CLIENT_ADDRESS

    if (!espressoLightClientAddress) {
      console.warn(
        'env var ESPRESSO_LIGHT_CLIENT_ADDRESS not set, it needs to be set to deploy the RollupCreator for the espresso integration'
      )
    }

    const contracts = await deployAllContracts(
      signer,
      ethers.BigNumber.from(maxDataSize),
      true,
      espressoLightClientAddress
    )

    const contractAddresses = {
      EthBridge: contracts.bridgeCreator.address,
      EthSequencerInbox: contracts.ethSequencerInbox.address,
      EthInbox: contracts.ethInbox.address,
      EthRollupEventInbox: contracts.ethRollupEventInbox.address,
      EthOutbox: contracts.ethOutbox.address,
      ERC20Bridge: contracts.erc20Bridge.address,
      ERC20SequencerInbox: contracts.erc20SequencerInbox.address,
      ERC20Inbox: contracts.erc20Inbox.address,
      ERC20RollupEventInbox: contracts.erc20RollupEventInbox.address,
      ERC20Outbox: contracts.erc20Outbox.address,
      BridgeCreator: contracts.bridgeCreator.address,
      OneStepProver0: contracts.prover0.address,
      OneStepProverMemory: contracts.proverMem.address,
      OneStepProverMath: contracts.proverMath.address,
      OneStepProverHostIo: contracts.proverHostIo.address,
      OneStepProofEntry: contracts.osp.address,
      ChallengeManager: contracts.challengeManager.address,
      RollupAdminLogic: contracts.rollupAdmin.address,
      RollupUserLogic: contracts.rollupUser.address,
      UpgradeExecutor: contracts.upgradeExecutor.address,
      ValidatorUtils: contracts.validatorUtils.address,
      ValidatorWalletCreator: contracts.validatorWalletCreator.address,
      RollupCreator: contracts.rollupCreator.address,
      DeployHelper: contracts.deployHelper.address,
    }

    // save the contract name to address mapping in a json file
    fs.writeFileSync(
      `./espresso-deployments/${network.name}.json`,
      JSON.stringify(contractAddresses, null, 2)
    )

    console.info('Contract addresses are saved in the deployments folder')

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
