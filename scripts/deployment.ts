import { ethers } from 'hardhat'
import { ContractFactory, Contract } from 'ethers'
import '@nomiclabs/hardhat-ethers'
import { run } from 'hardhat'
import {
  abi as UpgradeExecutorABI,
  bytecode as UpgradeExecutorBytecode,
} from '@offchainlabs/upgrade-executor/build/contracts/src/UpgradeExecutor.sol/UpgradeExecutor.json'

// Define a verification function
async function verifyContract(
  contractName: string,
  contractAddress: string,
  constructorArguments: any[] = [],
  contractPathAndName?: string // optional
): Promise<void> {
  try {
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
  constructorArgs: any[] = []
): Promise<Contract> {
  const factory: ContractFactory = await ethers.getContractFactory(contractName)
  const connectedFactory: ContractFactory = factory.connect(signer)
  const contract: Contract = await connectedFactory.deploy(...constructorArgs)
  await contract.deployTransaction.wait()
  console.log(`New ${contractName} created at address:`, contract.address)

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
  const bridgeCreator = await deployContract('BridgeCreator', signer)
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
      contracts.validatorWalletCreator.address
    )
    console.log('Template is set on the Rollup Creator')

    // get and verify ETH-based bridge contracts
    const { bridge, sequencerInbox, inbox, outbox } =
      await contracts.bridgeCreator.ethBasedTemplates()

    console.log(`"bridge implementation contract" created at address:`, bridge)
    await verifyContract('Bridge', bridge, [], 'src/bridge/Bridge.sol:Bridge')
    console.log(
      `"sequencerInbox implementation contract" created at address:`,
      sequencerInbox
    )
    await verifyContract(
      'SequencerInbox',
      sequencerInbox,
      [],
      'src/bridge/SequencerInbox.sol:SequencerInbox'
    )
    console.log(`"inbox implementation contract" created at address:`, inbox)
    await verifyContract('Inbox', inbox, [], 'src/bridge/Inbox.sol:Inbox')
    console.log(`"outbox implementation contract" created at address:`, outbox)
    await verifyContract('Outbox', outbox, [], 'src/bridge/Outbox.sol:Outbox')

    // get and verify ERC20-based bridge contracts
    const {
      bridge: erc20Bridge,
      sequencerInbox: erc20SeqInbox,
      inbox: erc20Inbox,
      outbox: erc20Outbox,
    } = await contracts.bridgeCreator.erc20BasedTemplates()

    console.log(
      `"erc20 bridge implementation contract" created at address:`,
      bridge
    )
    await verifyContract(
      'ERC20Bridge',
      erc20Bridge,
      [],
      'src/bridge/ERC20Bridge.sol:ERC20Bridge'
    )
    console.log(
      `"erc20 sequencerInbox implementation contract" created at address:`,
      erc20SeqInbox
    )
    await verifyContract(
      'SequencerInbox',
      erc20SeqInbox,
      [],
      'src/bridge/SequencerInbox.sol:SequencerInbox'
    )
    console.log(
      `"erc20 inbox implementation contract" created at address:`,
      inbox
    )
    await verifyContract(
      'ERC20Inbox',
      erc20Inbox,
      [],
      'src/bridge/ERC20Inbox.sol:ERC20Inbox'
    )
    console.log(
      `"erc20 outbox implementation contract" created at address:`,
      outbox
    )
    await verifyContract(
      'ERC20Outbox',
      erc20Outbox,
      [],
      'src/bridge/ERC20Outbox.sol:ERC20Outbox'
    )
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
