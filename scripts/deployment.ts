import { ethers } from 'hardhat'
import { ContractFactory, Contract} from 'ethers'
import '@nomiclabs/hardhat-ethers'

interface RollupCreatedEvent {
  event: string;
  address: string;
  args?: {
    rollupAddress: string;
    inboxAddress: string;
    adminProxy: string;
    sequencerInbox: string;
    bridge: string;
  };
}


async function deployContract(
  contractName: string,
  signer: any
): Promise<Contract> {
  const factory: ContractFactory = await ethers.getContractFactory(contractName)
  const connectedFactory: ContractFactory = factory.connect(signer)
  const contract: Contract = await connectedFactory.deploy()
  await contract.deployTransaction.wait()
  console.log(`New ${contractName} created at address:`, contract.address)
  return contract
}

async function deployAllContracts(
  signer: any
): Promise<Record<string, Contract>> {
  const bridgeCreator = await deployContract('BridgeCreator', signer)
  const prover0 = await deployContract('OneStepProver0', signer)
  const proverMem = await deployContract('OneStepProverMemory', signer)
  const proverMath = await deployContract('OneStepProverMath', signer)
  const proverHostIo = await deployContract('OneStepProverHostIo', signer)
  const OneStepProofEntryFactory: ContractFactory =
    await ethers.getContractFactory('OneStepProofEntry')
  const OneStepProofEntryFactoryWithDeployer: ContractFactory =
    OneStepProofEntryFactory.connect(signer)
  const osp: Contract = await OneStepProofEntryFactoryWithDeployer.deploy(
    prover0.address,
    proverMem.address,
    proverMath.address,
    proverHostIo.address
  )
  await osp.deployTransaction.wait()
  console.log('New osp created at address:', osp.address)
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

    /*
     * Call setTemplates with the deployed contract addresses
     * Adding 15 million gas limit otherwise it'll be reverted with "gas exceeds block gas limit" error
     */
    console.log('Waiting for the Template to be set on the Rollup Creator')
    await contracts.rollupCreator.setTemplates(
      contracts.bridgeCreator.address,
      contracts.osp.address,
      contracts.challengeManager.address,
      contracts.rollupAdmin.address,
      contracts.rollupUser.address,
      contracts.validatorUtils.address,
      contracts.validatorWalletCreator.address,
      { gasLimit: ethers.BigNumber.from('15000000') }
    )
    console.log('Template is set on the Rollup Creator')

    // Define the configuration for the createRollup function
    const rollupConfig = {
      confirmPeriodBlocks: 20,
      extraChallengeTimeBlocks: 0,
      stakeToken: ethers.constants.AddressZero,
      baseStake: ethers.utils.parseEther('1'),
      wasmModuleRoot:
        '0xda4e3ad5e7feacb817c21c8d0220da7650fe9051ece68a3f0b1c5d38bbb27b21',
      owner: signer.address,
      loserStakeEscrow: ethers.constants.AddressZero,
      chainId: 1337,
      chainConfig: ethers.constants.HashZero,
      genesisBlockNum: 0,
      sequencerInboxMaxTimeVariation: {
        delayBlocks: 16,
        futureBlocks: 192,
        delaySeconds: 86400,
        futureSeconds: 7200,
      },
    }

    /*
     * Call the createRollup function
     * Adding 15 million gas limit otherwise it'll be reverted with "gas exceeds block gas limit" error
     */
    console.log('Calling createRollup to generate a new rollup ...')
    const createRollupTx = await contracts.rollupCreator.createRollup(
      rollupConfig,
      { gasLimit: ethers.BigNumber.from('15000000') }
    )
    const createRollupReceipt = await createRollupTx.wait()

    const rollupCreatedEvent = createRollupReceipt.events?.find(
      (event: RollupCreatedEvent) => event.event === 'RollupCreated' && event.address.toLowerCase() === contracts.rollupCreator.address.toLowerCase()
    )
    //Checking for RollupCreated event for new rollup address
    if (rollupCreatedEvent) {
      const rollupAddress = rollupCreatedEvent.args?.rollupAddress
      const inboxAddress = rollupCreatedEvent.args?.inboxAddress
      const adminProxy = rollupCreatedEvent.args?.adminProxy
      const sequencerInbox = rollupCreatedEvent.args?.sequencerInbox
      const bridge = rollupCreatedEvent.args?.bridge
      console.log("Congratulations! 🎉🎉🎉 All DONE! Here's your addresses:")
      console.log('Rollup Contract created at address:', rollupAddress)
      console.log('Inbox Contract created at address:', inboxAddress)
      console.log('Admin Proxy Contract created at address:', adminProxy)
      console.log(
        'Sequencer Contract Inbox created at address:',
        sequencerInbox
      )
      console.log('Bridge Contract created at address:', bridge)
      console.log(
        'Utils Contract created at address:',
        contracts.validatorUtils.address
      )
      console.log(
        'ValidatorWalletCreator Contract created at address:',
        contracts.validatorWalletCreator.address
      )
      console.log(
        'outbox Contract created at address:',
        await contracts.rollup.outbox()
      )

      // getting the block number
      const blockNumber = createRollupReceipt.blockNumber
      console.log('All deployed at block number:', blockNumber)
    } else {
      console.error('RollupCreated event not found')
    }
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
