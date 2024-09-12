import { ethers } from 'hardhat'
import { ContractFactory, Contract, Overrides, BigNumber, Wallet } from 'ethers'
import '@nomiclabs/hardhat-ethers'
import { run } from 'hardhat'
import {
  abi as UpgradeExecutorABI,
  bytecode as UpgradeExecutorBytecode,
} from '@offchainlabs/upgrade-executor/build/contracts/src/UpgradeExecutor.sol/UpgradeExecutor.json'
import { Toolkit4844 } from '../test/contract/toolkit4844'
import {
  ArbOwner__factory,
  ArbOwnerPublic__factory,
  ArbSys__factory,
  CacheManager__factory,
} from '../build/types'

const INIT_CACHE_SIZE = 536870912
const INIT_DECAY = 10322197911
const ARB_OWNER_ADDRESS = '0x0000000000000000000000000000000000000070'
const ARB_OWNER_PUBLIC_ADDRESS = '0x000000000000000000000000000000000000006b'
const ARB_SYS_ADDRESS = '0x0000000000000000000000000000000000000064'

// Define a verification function
export async function verifyContract(
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
      force: boolean
    } = {
      address: contractAddress,
      constructorArguments: constructorArguments,
      force: true,
    }

    // if contractPathAndName is provided, add it to the verification options
    if (contractPathAndName) {
      verificationOptions.contract = contractPathAndName
    }

    await run('verify:verify', verificationOptions)
    console.log(`Verified contract ${contractName} successfully.`)
  } catch (error: any) {
    if (error.message.toLowerCase().includes('already verified')) {
      console.log(`Contract ${contractName} is already verified.`)
    } else if (error.message.includes('does not have bytecode')) {
      await verifyContract(
        contractName,
        contractAddress,
        constructorArguments,
        contractPathAndName
      )
    } else {
      console.error(
        `Verification for ${contractName} failed with the following error: ${error.message}`
      )
    }
  }
}

// Function to handle contract deployment
export async function deployContract(
  contractName: string,
  signer: any,
  constructorArgs: any[] = [],
  verify: boolean = true,
  overrides?: Overrides
): Promise<Contract> {
  const factory: ContractFactory = await ethers.getContractFactory(contractName)
  const connectedFactory: ContractFactory = factory.connect(signer)

  let deploymentArgs = [...constructorArgs]
  if (overrides) {
    deploymentArgs.push(overrides)
  } else {
    // overrides = {
    //   maxFeePerGas: ethers.utils.parseUnits('5.0', 'gwei'),
    //   maxPriorityFeePerGas: ethers.utils.parseUnits('0.01', 'gwei')
    // }
    // deploymentArgs.push(overrides)
  }

  const contract: Contract = await connectedFactory.deploy(...deploymentArgs)
  await contract.deployTransaction.wait()
  console.log(
    `* New ${contractName} created at address: ${
      contract.address
    } ${constructorArgs.join(' ')}`
  )

  if (verify)
    await verifyContract(contractName, contract.address, constructorArgs)

  return contract
}

// Deploy upgrade executor from imported bytecode
export async function deployUpgradeExecutor(signer: any): Promise<Contract> {
  const upgradeExecutorFac = await ethers.getContractFactory(
    UpgradeExecutorABI,
    UpgradeExecutorBytecode
  )
  const connectedFactory: ContractFactory = upgradeExecutorFac.connect(signer)
  const upgradeExecutor = await connectedFactory.deploy()
  return upgradeExecutor
}

// Function to handle all deployments of core contracts using deployContract function
export async function deployAllContracts(
  signer: any,
  maxDataSize: BigNumber,
  verify: boolean = true
): Promise<Record<string, Contract>> {
  const isOnArb = await _isRunningOnArbitrum(signer)

  const ethBridge = await deployContract('Bridge', signer, [], verify)
  const reader4844 = isOnArb
    ? ethers.constants.AddressZero
    : (await Toolkit4844.deployReader4844(signer)).address

  const ethSequencerInbox = await deployContract(
    'SequencerInbox',
    signer,
    [maxDataSize, reader4844, false],
    verify
  )

  const ethInbox = await deployContract('Inbox', signer, [maxDataSize], verify)
  const ethRollupEventInbox = await deployContract(
    'RollupEventInbox',
    signer,
    [],
    verify
  )
  const ethOutbox = await deployContract('Outbox', signer, [], verify)

  const erc20Bridge = await deployContract('ERC20Bridge', signer, [], verify)
  const erc20SequencerInbox = await deployContract(
    'SequencerInbox',
    signer,
    [maxDataSize, reader4844, true],
    verify
  )
  const erc20Inbox = await deployContract(
    'ERC20Inbox',
    signer,
    [maxDataSize],
    verify
  )
  const erc20RollupEventInbox = await deployContract(
    'ERC20RollupEventInbox',
    signer,
    [],
    verify
  )
  const erc20Outbox = await deployContract('ERC20Outbox', signer, [], verify)

  const bridgeCreator = await deployContract(
    'BridgeCreator',
    signer,
    [
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
    ],
    verify
  )
  const prover0 = await deployContract('OneStepProver0', signer, [], verify)
  const proverMem = await deployContract(
    'OneStepProverMemory',
    signer,
    [],
    verify
  )
  const proverMath = await deployContract(
    'OneStepProverMath',
    signer,
    [],
    verify
  )
  const proverHostIo = await deployContract(
    'OneStepProverHostIo',
    signer,
    [],
    verify
  )
  const osp: Contract = await deployContract(
    'OneStepProofEntry',
    signer,
    [
      prover0.address,
      proverMem.address,
      proverMath.address,
      proverHostIo.address,
    ],
    verify
  )
  const challengeManager = await deployContract(
    'ChallengeManager',
    signer,
    [],
    verify
  )
  const rollupAdmin = await deployContract(
    'RollupAdminLogic',
    signer,
    [],
    verify
  )
  const rollupUser = await deployContract('RollupUserLogic', signer, [], verify)
  const upgradeExecutor = await deployUpgradeExecutor(signer)
  await upgradeExecutor.deployTransaction.wait()
  const validatorUtils = await deployContract(
    'ValidatorUtils',
    signer,
    [],
    verify
  )
  const validatorWalletCreator = await deployContract(
    'ValidatorWalletCreator',
    signer,
    [],
    verify
  )
  const rollupCreator = await deployContract(
    'RollupCreator',
    signer,
    [],
    verify
  )
  const deployHelper = await deployContract('DeployHelper', signer, [], verify)
  if (verify && !process.env.DISABLE_VERIFICATION) {
    // Deploy RollupProxy contract only for verification, should not be used anywhere else
    await deployContract(
      'RollupProxy',
      signer,
      [],
      verify
    )
  }
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

export async function deployAndSetCacheManager(
  chainOwnerWallet: Wallet,
  verify: boolean = true
) {
  // deploy CacheManager
  const cacheManagerLogic = await deployContract(
    'CacheManager',
    chainOwnerWallet,
    [],
    verify
  )
  const proxyAdmin = await deployContract(
    'ProxyAdmin',
    chainOwnerWallet,
    [],
    verify
  )
  const cacheManagerProxy = await deployContract(
    'TransparentUpgradeableProxy',
    chainOwnerWallet,
    [cacheManagerLogic.address, proxyAdmin.address, '0x'],
    verify
  )

  // initialize CacheManager
  const cacheManager = CacheManager__factory.connect(
    cacheManagerProxy.address,
    chainOwnerWallet
  )
  await (await cacheManager.initialize(INIT_CACHE_SIZE, INIT_DECAY)).wait()

  /// add CacheManager to ArbOwner
  const arbOwnerAccount = (
    await ArbOwnerPublic__factory.connect(
      ARB_OWNER_PUBLIC_ADDRESS,
      chainOwnerWallet
    ).getAllChainOwners()
  )[0]

  const arbOwnerPrecompile = ArbOwner__factory.connect(
    ARB_OWNER_ADDRESS,
    chainOwnerWallet
  )
  if ((await chainOwnerWallet.provider.getCode(arbOwnerAccount)) === '0x') {
    // arb owner is EOA, add cache manager directly
    await (
      await arbOwnerPrecompile.addWasmCacheManager(cacheManagerProxy.address)
    ).wait()
  } else {
    // assume upgrade executor is arb owner
    const upgradeExecutor = new ethers.Contract(
      arbOwnerAccount,
      UpgradeExecutorABI,
      chainOwnerWallet
    )
    const data = arbOwnerPrecompile.interface.encodeFunctionData(
      'addWasmCacheManager',
      [cacheManagerProxy.address]
    )
    await (await upgradeExecutor.executeCall(ARB_OWNER_ADDRESS, data)).wait()
  }

  return cacheManagerProxy
}

// Check if we're deploying to an Arbitrum chain
export async function _isRunningOnArbitrum(signer: any): Promise<boolean> {
  const arbSys = ArbSys__factory.connect(ARB_SYS_ADDRESS, signer)
  try {
    await arbSys.arbOSVersion()
    return true
  } catch (error) {
    return false
  }
}
