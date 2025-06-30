import { ethers } from 'hardhat'
import {
  ContractFactory,
  Contract,
  Overrides,
  BigNumber,
  Wallet,
  Signer,
} from 'ethers'
import '@nomiclabs/hardhat-ethers'
import { run } from 'hardhat'
import {
  abi as UpgradeExecutorABI,
  bytecode as UpgradeExecutorBytecode,
} from '@offchainlabs/upgrade-executor/build/contracts/src/UpgradeExecutor.sol/UpgradeExecutor.json'
import {
  ArbOwner__factory,
  ArbOwnerPublic__factory,
  ArbSys__factory,
  CacheManager__factory,
  IReader4844__factory,
  Bridge__factory,
  Inbox__factory,
  RollupEventInbox__factory,
  Outbox__factory,
  ERC20Bridge__factory,
  SequencerInbox__factory,
  ERC20Inbox__factory,
  ERC20RollupEventInbox__factory,
  ERC20Outbox__factory,
  BridgeCreator__factory,
  OneStepProver0__factory,
  OneStepProverMemory__factory,
  OneStepProverMath__factory,
  OneStepProverHostIo__factory,
  OneStepProofEntry__factory,
  EdgeChallengeManager__factory,
  RollupAdminLogic__factory,
  RollupUserLogic__factory,
  ValidatorWalletCreator__factory,
  ImplementationsRegistry,
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
const CREATE2_FACTORY_ADDRESS = '0x4e59b44847b379578588920cA78FbF26c0B4956C'

// Define a verification function
export async function verifyContract(
  contractName: string,
  contractAddress: string,
  constructorArguments: any[] = [],
  contractPathAndName?: string // optional
): Promise<void> {
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

  if (
    (await fac.signer.provider!.getCode(CREATE2_FACTORY_ADDRESS)).length <= 2
  ) {
    throw new Error(
      'Factory contract not deployed at address: ' + CREATE2_FACTORY_ADDRESS
    )
  }
  const data = fac.getDeployTransaction(...deploymentArgs).data
  if (!data) {
    throw new Error('No deploy data found for contract factory')
  }

  const address = getCreate2Address(
    CREATE2_FACTORY_ADDRESS,
    salt,
    keccak256(data)
  )
  if ((await fac.signer.provider!.getCode(address)).length > 2) {
    return fac.attach(address)
  }

  const tx = await fac.signer.sendTransaction({
    to: CREATE2_FACTORY_ADDRESS,
    data: concat([salt, data]),
    ...overrides,
  })
  await tx.wait()

  return fac.attach(address)
}

function deployImplementationsRegistry(signer: Signer, verify: boolean) {
  return deployContract(
    'ImplementationsRegistry',
    signer,
    [
      CREATE2_FACTORY_ADDRESS,
      ethers.constants.HashZero,
      [
        'Bridge',
        'Inbox',
        'RollupEventInbox',
        'Outbox',
        'ERC20Bridge',
        'SequencerInbox',
        'ERC20Inbox',
        'ERC20RollupEventInbox',
        'ERC20Outbox',
        'BridgeCreator',
        'OneStepProver0',
        'OneStepProverMemory',
        'OneStepProverMath',
        'OneStepProverHostIo',
        'OneStepProofEntry',
        'EdgeChallengeManager',
        'RollupAdminLogic',
        'RollupUserLogic',
        'ValidatorWalletCreator',
        'Reader4844',
        'UpgradeExecutor',
      ],
      [
        keccak256(Bridge__factory.bytecode),
        keccak256(Inbox__factory.bytecode),
        keccak256(RollupEventInbox__factory.bytecode),
        keccak256(Outbox__factory.bytecode),
        keccak256(ERC20Bridge__factory.bytecode),
        keccak256(SequencerInbox__factory.bytecode),
        keccak256(ERC20Inbox__factory.bytecode),
        keccak256(ERC20RollupEventInbox__factory.bytecode),
        keccak256(ERC20Outbox__factory.bytecode),
        keccak256(BridgeCreator__factory.bytecode),
        keccak256(OneStepProver0__factory.bytecode),
        keccak256(OneStepProverMemory__factory.bytecode),
        keccak256(OneStepProverMath__factory.bytecode),
        keccak256(OneStepProverHostIo__factory.bytecode),
        keccak256(OneStepProofEntry__factory.bytecode),
        keccak256(EdgeChallengeManager__factory.bytecode),
        keccak256(RollupAdminLogic__factory.bytecode),
        keccak256(RollupUserLogic__factory.bytecode),
        keccak256(ValidatorWalletCreator__factory.bytecode),
        keccak256(Reader4844Bytecode.object),
        keccak256(UpgradeExecutorBytecode),
      ],
    ],
    verify,
    true
  ) as Promise<ImplementationsRegistry>
}

async function deployContractWithRegistry(
  implsRegistry: ImplementationsRegistry,
  contractName: string,
  signer: Signer,
  constructorArgs: any[] = [],
  verify: boolean = true
) {
  const factory: ContractFactory = await ethers.getContractFactory(contractName)
  const connectedFactory: ContractFactory = factory.connect(signer)

  const contract = await create2(connectedFactory, constructorArgs)
  const encodedConstructorArgs = ethers.utils.defaultAbiCoder.encode(
    factory.interface.deploy.inputs,
    constructorArgs
  )

  if (
    (await implsRegistry.getAddressWithArgs(
      contractName,
      keccak256(encodedConstructorArgs)
    )) !== ethers.constants.AddressZero
  ) {
    return contract
  }

  await (
    await implsRegistry
      .connect(signer)
      .registerHashWithArgs(
        contractName,
        factory.bytecode,
        encodedConstructorArgs
      )
  ).wait()

  const expectedAddress = await implsRegistry.getAddressWithArgs(
    contractName,
    keccak256(constructorArgs)
  )
  if (expectedAddress !== contract.address) {
    throw new Error(
      `Invalid address for ${contractName}. Expected: ${expectedAddress}, got: ${contract.address}`
    )
  }

  if (verify)
    await verifyContract(contractName, contract.address, constructorArgs)

  return contract
}

// Function to handle all deployments of core contracts using deployContract function
export async function deployAllContracts(
  signer: any,
  maxDataSize: BigNumber,
  verify: boolean = true
): Promise<Record<string, Contract>> {
  const FACTORY_OWNER = process.env.FACTORY_OWNER
  if (!FACTORY_OWNER) {
    throw new Error('FACTORY_OWNER environment variable is not set')
  }

  const isOnArb = await _isRunningOnArbitrum(signer)

  const implsRegistry = await deployImplementationsRegistry(signer, verify)

  const ethBridge = await deployContractWithRegistry(
    implsRegistry,
    'Bridge',
    signer,
    [],
    verify
  )

  const reader4844 = isOnArb
    ? ethers.constants.AddressZero
    : (
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
  if (
    !isOnArb &&
    reader4844 !== (await implsRegistry.getAddress('Reader4844'))
  ) {
    throw new Error(
      `Reader4844 not deployed at expected address: ${reader4844}`
    )
  }

  const ethSequencerInbox = await deployContractWithRegistry(
    implsRegistry,
    'SequencerInbox',
    signer,
    [maxDataSize, reader4844, false, false],
    verify
  )
  const ethSequencerInboxDelayBufferable = await deployContractWithRegistry(
    implsRegistry,
    'SequencerInbox',
    signer,
    [maxDataSize, reader4844, false, true],
    verify
  )

  const ethInbox = await deployContractWithRegistry(
    implsRegistry,
    'Inbox',
    signer,
    [maxDataSize],
    verify
  )
  const ethRollupEventInbox = await deployContractWithRegistry(
    implsRegistry,
    'RollupEventInbox',
    signer,
    [],
    verify
  )
  const ethOutbox = await deployContractWithRegistry(
    implsRegistry,
    'Outbox',
    signer,
    [],
    verify
  )

  const erc20Bridge = await deployContractWithRegistry(
    implsRegistry,
    'ERC20Bridge',
    signer,
    [],
    verify
  )
  const erc20SequencerInbox = await deployContractWithRegistry(
    implsRegistry,
    'SequencerInbox',
    signer,
    [maxDataSize, reader4844, true, false],
    verify
  )
  const erc20SequencerInboxDelayBufferable = await deployContractWithRegistry(
    implsRegistry,
    'SequencerInbox',
    signer,
    [maxDataSize, reader4844, true, true],
    verify
  )
  const erc20Inbox = await deployContractWithRegistry(
    implsRegistry,
    'ERC20Inbox',
    signer,
    [maxDataSize],
    verify
  )
  const erc20RollupEventInbox = await deployContractWithRegistry(
    implsRegistry,
    'ERC20RollupEventInbox',
    signer,
    [],
    verify
  )
  const erc20Outbox = await deployContractWithRegistry(
    implsRegistry,
    'ERC20Outbox',
    signer,
    [],
    verify
  )

  const bridgeCreator = await deployContract(
    'BridgeCreator',
    signer,
    [
      FACTORY_OWNER,
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
  const prover0 = await deployContractWithRegistry(
    implsRegistry,
    'OneStepProver0',
    signer,
    [],
    verify
  )
  const proverMem = await deployContractWithRegistry(
    implsRegistry,
    'OneStepProverMemory',
    signer,
    [],
    verify
  )
  const proverMath = await deployContractWithRegistry(
    implsRegistry,
    'OneStepProverMath',
    signer,
    [],
    verify
  )
  const proverHostIo = await deployContractWithRegistry(
    implsRegistry,
    'OneStepProverHostIo',
    signer,
    [],
    verify
  )
  const osp: Contract = await deployContractWithRegistry(
    implsRegistry,
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
  const challengeManager = await deployContractWithRegistry(
    implsRegistry,
    'EdgeChallengeManager',
    signer,
    [],
    verify
  )
  const rollupAdmin = await deployContractWithRegistry(
    implsRegistry,
    'RollupAdminLogic',
    signer,
    [],
    verify
  )
  const rollupUser = await deployContractWithRegistry(
    implsRegistry,
    'RollupUserLogic',
    signer,
    [],
    verify
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
  if (
    (await implsRegistry.getAddress('UpgradeExecutor')) !==
    upgradeExecutor.address
  ) {
    throw new Error(
      `UpgradeExecutor not deployed at expected address: ${upgradeExecutor.address}`
    )
  }
  const validatorWalletCreator = await deployContractWithRegistry(
    implsRegistry,
    'ValidatorWalletCreator',
    signer,
    [],
    verify
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
      FACTORY_OWNER,
      {
        bridgeCreator: bridgeCreator.address,
        osp: osp.address,
        challengeManagerLogic: challengeManager.address,
        rollupAdminLogic: rollupAdmin.address,
        rollupUserLogic: rollupUser.address,
        upgradeExecutorLogic: upgradeExecutor.address,
        validatorWalletCreator: validatorWalletCreator.address,
        l2FactoriesDeployer: deployHelper.address,
      },
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
