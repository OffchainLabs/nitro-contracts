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
  IReader4844__factory,
} from '../build/types'
import {
  concat,
  getCreate2Address,
  hexDataLength,
  keccak256,
} from 'ethers/lib/utils'
import { bytecode as Reader4844Bytecode } from '../out/yul/Reader4844.yul/Reader4844.json'

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
  contractPathAndName = contractPathAndName ?? {
    Bridge: 'src/bridge/Bridge.sol:Bridge',
    SequencerInbox: 'src/bridge/SequencerInbox.sol:SequencerInbox',
    Inbox: 'src/bridge/Inbox.sol:Inbox',
    Outbox: 'src/bridge/Outbox.sol:Outbox',
    ERC20Bridge: 'src/bridge/ERC20Bridge.sol:ERC20Bridge',
    ERC20Inbox: 'src/bridge/ERC20Inbox.sol:ERC20Inbox',
    ERC20Outbox: 'src/bridge/ERC20Outbox.sol:ERC20Outbox',
    RollupEventInbox: 'src/rollup/RollupEventInbox.sol:RollupEventInbox',
    ERC20RollupEventInbox:
      'src/rollup/ERC20RollupEventInbox.sol:ERC20RollupEventInbox',
    RollupAdminLogic: 'src/rollup/RollupAdminLogic.sol:RollupAdminLogic',
    RollupUserLogic: 'src/rollup/RollupUserLogic.sol:RollupUserLogic',
    BridgeCreator: 'src/rollup/BridgeCreator.sol:BridgeCreator',
    EdgeChallengeManager:
      'src/challengeV2/EdgeChallengeManager.sol:EdgeChallengeManager',
    ValidatorWalletCreator: 'src/rollup/ValidatorWalletCreator.sol:ValidatorWalletCreator',
    DeployHelper: 'src/rollup/DeployHelper.sol:DeployHelper',
    RollupProxy: 'src/rollup/RollupProxy.sol:RollupProxy',
    RollupCreator: 'src/rollup/RollupCreator.sol:RollupCreator',
    OneStepProver0: 'src/osp/OneStepProver0.sol:OneStepProver0',
    OneStepProverMemory: 'src/osp/OneStepProverMemory.sol:OneStepProverMemory',
    OneStepProverMath: 'src/osp/OneStepProverMath.sol:OneStepProverMath',
    OneStepProverHostIo: 'src/osp/OneStepProverHostIo.sol:OneStepProverHostIo',
    OneStepProofEntry: 'src/osp/OneStepProofEntry.sol:OneStepProofEntry',
  }[contractName]

  try {
    if (process.env.DISABLE_VERIFICATION === 'true') return
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
  useCreate2: boolean = false,
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

  let contract: Contract
  if (useCreate2) {
    contract = await create2(
      connectedFactory,
      constructorArgs,
      ethers.constants.HashZero,
      overrides
    )
  } else {
    contract = await connectedFactory.deploy(...deploymentArgs)
    await contract.deployTransaction.wait()
  }

  console.log(
    `* ${contractName} created at address: ${
      contract.address
    } ${constructorArgs.join(' ')}`
  )

  if (verify)
    await verifyContract(contractName, contract.address, constructorArgs)

  return contract
}

export async function create2(
  fac: ContractFactory,
  deploymentArgs: Array<any>,
  salt = ethers.constants.HashZero,
  overrides?: Overrides
): Promise<Contract> {
  if (hexDataLength(salt) !== 32) {
    throw new Error('Salt must be a 32-byte hex string')
  }

  const DEFAULT_FACTORY = '0x4e59b44847b379578588920cA78FbF26c0B4956C'
  const FACTORY = process.env.CREATE2_FACTORY ?? DEFAULT_FACTORY
  if ((await fac.signer.provider!.getCode(FACTORY)).length <= 2) {
    throw new Error(
      `Factory contract not deployed at address: ${FACTORY}${
        FACTORY.toLowerCase() === DEFAULT_FACTORY.toLowerCase()
          ? '\n(For deployment instructions, see https://github.com/Arachnid/deterministic-deployment-proxy/ )'
          : ''
      }`
    )
  }
  const data = fac.getDeployTransaction(...deploymentArgs).data
  if (!data) {
    throw new Error('No deploy data found for contract factory')
  }

  const address = getCreate2Address(FACTORY, salt, keccak256(data))
  if ((await fac.signer.provider!.getCode(address)).length > 2) {
    return fac.attach(address)
  }

  const tx = await fac.signer.sendTransaction({
    to: FACTORY,
    data: concat([salt, data]),
    ...overrides,
  })
  await tx.wait(2)

  return fac.attach(address)
}

export async function deployOneStepProofEntry(
  signer: any,
  customDAValidator: string,
  verify: boolean = true
): Promise<{
  prover0: Contract
  proverMem: Contract
  proverMath: Contract
  proverHostIo: Contract
  osp: Contract
}> {
  console.log('Deploying OneStepProver contracts...')
  const prover0 = await deployContract(
    'OneStepProver0',
    signer,
    [],
    verify,
    true
  )
  const proverMem = await deployContract(
    'OneStepProverMemory',
    signer,
    [],
    verify,
    true
  )
  const proverMath = await deployContract(
    'OneStepProverMath',
    signer,
    [],
    verify,
    true
  )
  const proverHostIo = await deployContract(
    'OneStepProverHostIo',
    signer,
    [customDAValidator],
    verify,
    true
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
    verify,
    true
  )

  return {
    prover0,
    proverMem,
    proverMath,
    proverHostIo,
    osp,
  }
}

// Function to handle all deployments of core contracts using deployContract function
export async function deployAllContracts(
  signer: any,
  factoryOwner: string,
  maxDataSize: BigNumber,
  verify: boolean = true
): Promise<Record<string, Contract>> {
  const isOnArb = await _isRunningOnArbitrum(signer)
  const isOnL1 = await _isRunningOnL1(signer)

  const ethBridge = await deployContract('Bridge', signer, [], verify, true)

  let reader4844: string;
  if (isOnArb) reader4844 = ethers.constants.AddressZero
  else if (!isOnL1) reader4844 = '0x000000000000000000000000000000000000dead' // dead address
  else reader4844 = (
    await create2(
      new ContractFactory(
        IReader4844__factory.abi,
        Reader4844Bytecode,
        signer
      ),
      [],
      ethers.constants.HashZero
    )
  ).address

  const ethSequencerInbox = await deployContract(
    'SequencerInbox',
    signer,
    [maxDataSize, reader4844, false, false],
    verify,
    true
  )
  const ethSequencerInboxDelayBufferable = await deployContract(
    'SequencerInbox',
    signer,
    [maxDataSize, reader4844, false, true],
    verify,
    true
  )

  const ethInbox = await deployContract(
    'Inbox',
    signer,
    [maxDataSize],
    verify,
    true
  )
  const ethRollupEventInbox = await deployContract(
    'RollupEventInbox',
    signer,
    [],
    verify,
    true
  )
  const ethOutbox = await deployContract('Outbox', signer, [], verify, true)

  const erc20Bridge = await deployContract(
    'ERC20Bridge',
    signer,
    [],
    verify,
    true
  )
  const erc20SequencerInbox = await deployContract(
    'SequencerInbox',
    signer,
    [maxDataSize, reader4844, true, false],
    verify,
    true
  )
  const erc20SequencerInboxDelayBufferable = await deployContract(
    'SequencerInbox',
    signer,
    [maxDataSize, reader4844, true, true],
    verify,
    true
  )
  const erc20Inbox = await deployContract(
    'ERC20Inbox',
    signer,
    [maxDataSize],
    verify,
    true
  )
  const erc20RollupEventInbox = await deployContract(
    'ERC20RollupEventInbox',
    signer,
    [],
    verify,
    true
  )
  const erc20Outbox = await deployContract(
    'ERC20Outbox',
    signer,
    [],
    verify,
    true
  )

  const bridgeCreator = await deployContract(
    'BridgeCreator',
    signer,
    [
      [
        ethBridge.address,
        ethSequencerInbox.address,
        ethSequencerInboxDelayBufferable.address,
        ethInbox.address,
        ethRollupEventInbox.address,
        ethOutbox.address,
      ],
      [
        erc20Bridge.address,
        erc20SequencerInbox.address,
        erc20SequencerInboxDelayBufferable.address,
        erc20Inbox.address,
        erc20RollupEventInbox.address,
        erc20Outbox.address,
      ],
    ],
    verify,
    true
  )
  const { prover0, proverMem, proverMath, proverHostIo, osp } =
    await deployOneStepProofEntry(signer, ethers.constants.AddressZero, verify)
  const challengeManager = await deployContract(
    'EdgeChallengeManager',
    signer,
    [],
    verify,
    true
  )
  const rollupAdmin = await deployContract(
    'RollupAdminLogic',
    signer,
    [],
    verify,
    true
  )
  const rollupUser = await deployContract(
    'RollupUserLogic',
    signer,
    [],
    verify,
    true
  )
  const upgradeExecutor = await create2(
    (
      await ethers.getContractFactory(
        UpgradeExecutorABI,
        UpgradeExecutorBytecode
      )
    ).connect(signer),
    []
  )
  const validatorWalletCreator = await deployContract(
    'ValidatorWalletCreator',
    signer,
    [],
    verify,
    true
  )
  const deployHelper = await deployContract(
    'DeployHelper',
    signer,
    [],
    verify,
    true
  )
  if (verify && !process.env.DISABLE_VERIFICATION) {
    // Deploy RollupProxy contract only for verification, should not be used anywhere else
    await deployContract('RollupProxy', signer, [], verify, true)
  }

  const rollupCreator = await deployContract(
    'RollupCreator',
    signer,
    [
      factoryOwner,
      bridgeCreator.address,
      osp.address,
      challengeManager.address,
      rollupAdmin.address,
      rollupUser.address,
      upgradeExecutor.address,
      validatorWalletCreator.address,
      deployHelper.address,
    ],
    verify,
    true
  )

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

// return true if running on L1 (Ethereum mainnet or Sepolia)
export async function _isRunningOnL1(signer: any): Promise<boolean> {
  const chainId = (await signer.provider.getNetwork()).chainId
  return chainId === 1 || chainId === 11155111
}