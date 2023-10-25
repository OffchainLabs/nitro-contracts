import { ethers } from 'hardhat'
import { ContractFactory, Contract } from 'ethers'
import '@nomiclabs/hardhat-ethers'
import { run } from 'hardhat'
import {
  abi as UpgradeExecutorABI,
  bytecode as UpgradeExecutorBytecode,
} from '@offchainlabs/upgrade-executor/build/contracts/src/UpgradeExecutor.sol/UpgradeExecutor.json'
import { maxDataSize } from './config'

// Define a verification function
async function verifyContract(
  contractName: string,
  contractAddress: string,
  constructorArguments: any[] = [],
  contractPathAndName?: string // optional
): Promise<void> {
  try {
    if (process.env.DISABLE_VERIFICATION) return
    // Define the verification options with possible 'contract' property
    const verificationOptions: {
      contract?: string
      address: string
      constructorArguments: any[]
    } = {
      address: contractAddress,
      constructorArguments: constructorArguments,
    }

    // if contractPathAndName is provided, add it to the verification options
    if (contractPathAndName) {
      verificationOptions.contract = contractPathAndName
    }

    await run('verify:verify', verificationOptions)
    console.log(`Verified contract ${contractName} successfully.`)
  } catch (error: any) {
    if (error.message.includes('Already Verified')) {
      console.log(`Contract ${contractName} is already verified.`)
    } else {
      console.error(
        `Verification for ${contractName} failed with the following error: ${error.message}`
      )
    }
  }
}

// Function to handle contract deployment
async function deployContract(
  contractName: string,
  signer: any,
  constructorArgs: any[] = [],
  verify: boolean = true
): Promise<Contract> {
  const factory: ContractFactory = await ethers.getContractFactory(contractName)
  const connectedFactory: ContractFactory = factory.connect(signer)
  const contract: Contract = await connectedFactory.deploy(...constructorArgs)
  await contract.deployTransaction.wait()
  console.log(`New ${contractName} created at address:`, contract.address)

  if (verify)
    await verifyContract(contractName, contract.address, constructorArgs)

  return contract
}

// Deploy upgrade executor from imported bytecode
async function deployUpgradeExecutor(): Promise<Contract> {
  const upgradeExecutorFac = await ethers.getContractFactory(
    UpgradeExecutorABI,
    UpgradeExecutorBytecode
  )
  const upgradeExecutor = await upgradeExecutorFac.deploy()
  return upgradeExecutor
}

// Function to handle all deployments of core contracts using deployContract function
async function deployAllContracts(
  signer: any
): Promise<Record<string, Contract>> {
  const ethBridge = await deployContract('Bridge', signer, [])
  const ethSequencerInbox = await deployContract('SequencerInbox', signer, [
    maxDataSize,
  ])
  const ethInbox = await deployContract('Inbox', signer, [maxDataSize])
  const ethRollupEventInbox = await deployContract(
    'RollupEventInbox',
    signer,
    []
  )
  const ethOutbox = await deployContract('Outbox', signer, [])

  const erc20Bridge = await deployContract('ERC20Bridge', signer, [])
  const erc20SequencerInbox = ethSequencerInbox
  const erc20Inbox = await deployContract('ERC20Inbox', signer, [maxDataSize])
  const erc20RollupEventInbox = await deployContract(
    'ERC20RollupEventInbox',
    signer,
    []
  )
  const erc20Outbox = await deployContract('ERC20Outbox', signer, [])

  const bridgeCreator = await deployContract('BridgeCreator', signer, [
    [
      ethBridge.address,
      ethSequencerInbox.address,
      ethInbox.address,
      ethRollupEventInbox.address,
      ethOutbox.address,
    ],
    [
      erc20Bridge.address,
      erc20SequencerInbox.address,
      erc20Inbox.address,
      erc20RollupEventInbox.address,
      erc20Outbox.address,
    ],
  ])
  const prover0 = await deployContract('OneStepProver0', signer)
  const proverMem = await deployContract('OneStepProverMemory', signer)
  const proverMath = await deployContract('OneStepProverMath', signer)
  const proverHostIo = await deployContract('OneStepProverHostIo', signer)
  const osp: Contract = await deployContract('OneStepProofEntry', signer, [
    prover0.address,
    proverMem.address,
    proverMath.address,
    proverHostIo.address,
  ])
  const challengeManager = await deployContract('ChallengeManager', signer)
  const rollupAdmin = await deployContract('RollupAdminLogic', signer)
  const rollupUser = await deployContract('RollupUserLogic', signer)
  const upgradeExecutor = await deployUpgradeExecutor()
  const validatorUtils = await deployContract('ValidatorUtils', signer)
  const validatorWalletCreator = await deployContract(
    'ValidatorWalletCreator',
    signer
  )
  const rollupCreator = await deployContract('RollupCreator', signer)
  const deployHelper = await deployContract('DeployHelper', signer)
  return {
    bridgeCreator,
    prover0,
    proverMem,
    proverMath,
    proverHostIo,
    osp,
    challengeManager,
    rollupAdmin,
    rollupUser,
    upgradeExecutor,
    validatorUtils,
    validatorWalletCreator,
    rollupCreator,
    deployHelper,
  }
}

async function main() {
  const [signer] = await ethers.getSigners()

  try {
    // Deploying all contracts
    const contracts = await deployAllContracts(signer)

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
