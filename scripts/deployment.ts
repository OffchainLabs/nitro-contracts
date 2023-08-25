import { ethers } from 'hardhat'
import { ContractFactory, Contract } from 'ethers'
import '@nomiclabs/hardhat-ethers'
import { run } from 'hardhat'

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
      contracts.validatorUtils.address,
      contracts.validatorWalletCreator.address
    )
    console.log('Template is set on the Rollup Creator')

    const bridgeAddress = await contracts.bridgeCreator.bridgeTemplate()
    const sequencerInboxAddress =
      await contracts.bridgeCreator.sequencerInboxTemplate()
    const inboxAddress = await contracts.bridgeCreator.inboxTemplate()
    const outboxAddress = await contracts.bridgeCreator.outboxTemplate()

    console.log(
      `"bridge implementation contract" created at address:`,
      bridgeAddress
    )
    await verifyContract(
      'Bridge',
      bridgeAddress,
      [],
      'src/bridge/Bridge.sol:Bridge'
    )
    console.log(
      `"sequencerInbox implementation contract" created at address:`,
      sequencerInboxAddress
    )
    await verifyContract('SequencerInbox', sequencerInboxAddress, [])
    console.log(
      `"inbox implementation contract" created at address:`,
      inboxAddress
    )
    await verifyContract('Inbox', inboxAddress, [])
    console.log(
      `"outbox implementation contract" created at address:`,
      outboxAddress
    )
    await verifyContract('Outbox', outboxAddress, [])
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
