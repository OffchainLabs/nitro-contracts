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
    // For non-CREATE2 deployments, use nonce manager only in parallel mode
    const useSerialDeployment = process.env.NO_PARALLEL_DEPLOYMENT === 'true'

    if (!useSerialDeployment) {
      // Parallel mode: use nonce manager
      const nonce = await getNextNonce(signer)
      const deployOverrides = { ...overrides, nonce }

      // Update deployment args with overrides
      if (overrides) {
        deploymentArgs[deploymentArgs.length - 1] = deployOverrides
      } else {
        deploymentArgs.push(deployOverrides)
      }
    }

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

// Nonce manager for parallel deployments
let nonceManager: { [key: string]: number } = {}
let nonceLock = Promise.resolve()

async function getNextNonce(signer: any): Promise<number> {
  const address = await signer.getAddress()
  await nonceLock

  let resolveNonceLock: () => void
  nonceLock = new Promise(resolve => {
    resolveNonceLock = resolve
  })

  try {
    if (!(address in nonceManager)) {
      nonceManager[address] = await signer.getTransactionCount()
    }
    const nonce = nonceManager[address]
    nonceManager[address]++
    return nonce
  } finally {
    resolveNonceLock!()
  }
}

// Helper function to handle both parallel and serial deployments
async function deployBatch<T>(
  deployFunctions: (() => Promise<T>)[]
): Promise<T[]> {
  const isSerialDeployment = process.env.NO_PARALLEL_DEPLOYMENT === 'true'

  if (isSerialDeployment) {
    // Serial deployment: execute one by one using the nonce lock as mutex
    const results: T[] = []
    for (const deployFn of deployFunctions) {
      await nonceLock
      let resolveNonceLock: () => void
      nonceLock = new Promise(resolve => {
        resolveNonceLock = resolve
      })

      try {
        const result = await deployFn()
        results.push(result)
      } finally {
        resolveNonceLock!()
      }
    }
    return results
  } else {
    // Parallel deployment
    return Promise.all(deployFunctions.map(fn => fn()))
  }
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

  const isSerialDeployment = process.env.NO_PARALLEL_DEPLOYMENT === 'true'

  const txParams: any = {
    to: FACTORY,
    data: concat([salt, data]),
    ...overrides,
  }

  if (!isSerialDeployment) {
    // Only use nonce manager in parallel mode
    const nonce = await getNextNonce(fac.signer)
    txParams.nonce = nonce
  }

  const tx = await fac.signer.sendTransaction(txParams)
  await tx.wait()

  return fac.attach(address)
}

// Function to handle all deployments of core contracts using deployContract function
export async function deployAllContracts(
  signer: any,
  factoryOwner: string,
  maxDataSize: BigNumber,
  verify: boolean = true
): Promise<Record<string, Contract>> {
  // Reset nonce manager for fresh deployment
  nonceManager = {}

  const isSerialDeployment = process.env.NO_PARALLEL_DEPLOYMENT === 'true'
  if (isSerialDeployment) {
    console.log('Using serial deployment mode (NO_PARALLEL_DEPLOYMENT=true)')
  }

  const isOnArb = await _isRunningOnArbitrum(signer)

  // Deploy Reader4844 first if not on Arbitrum
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

  console.log(
    `Deploying bridge templates${
      isSerialDeployment ? ' in serial mode' : ' in parallel'
    }...`
  )

  const [
    ethBridge,
    ethSequencerInbox,
    ethSequencerInboxDelayBufferable,
    ethInbox,
    ethRollupEventInbox,
    ethOutbox,
    erc20Bridge,
    erc20SequencerInbox,
    erc20SequencerInboxDelayBufferable,
    erc20Inbox,
    erc20RollupEventInbox,
    erc20Outbox,
  ] = await deployBatch([
    () => deployContract('Bridge', signer, [], verify, true),
    () =>
      deployContract(
        'SequencerInbox',
        signer,
        [maxDataSize, reader4844, false, false],
        verify,
        true
      ),
    () =>
      deployContract(
        'SequencerInbox',
        signer,
        [maxDataSize, reader4844, false, true],
        verify,
        true
      ),
    () => deployContract('Inbox', signer, [maxDataSize], verify, true),
    () => deployContract('RollupEventInbox', signer, [], verify, true),
    () => deployContract('Outbox', signer, [], verify, true),
    () => deployContract('ERC20Bridge', signer, [], verify, true),
    () =>
      deployContract(
        'SequencerInbox',
        signer,
        [maxDataSize, reader4844, true, false],
        verify,
        true
      ),
    () =>
      deployContract(
        'SequencerInbox',
        signer,
        [maxDataSize, reader4844, true, true],
        verify,
        true
      ),
    () => deployContract('ERC20Inbox', signer, [maxDataSize], verify, true),
    () => deployContract('ERC20RollupEventInbox', signer, [], verify, true),
    () => deployContract('ERC20Outbox', signer, [], verify, true),
  ])

  console.log('Deploying OneStepProver contracts and OneStepProofEntry...')
  const ospDeployment = await deployOneStepProofEntry(
    signer,
    verify,
    isSerialDeployment
  )
  const { prover0, proverMem, proverMath, proverHostIo, osp } = ospDeployment

  console.log(
    `Deploying core contracts${
      isSerialDeployment ? ' in serial mode' : ' in parallel'
    }...`
  )

  const [
    challengeManager,
    rollupAdmin,
    rollupUser,
    upgradeExecutor,
    validatorWalletCreator,
    deployHelper,
  ] = await deployBatch([
    () => deployContract('EdgeChallengeManager', signer, [], verify, true),
    () => deployContract('RollupAdminLogic', signer, [], verify, true),
    () => deployContract('RollupUserLogic', signer, [], verify, true),
    async () =>
      create2(
        (
          await ethers.getContractFactory(
            UpgradeExecutorABI,
            UpgradeExecutorBytecode
          )
        ).connect(signer),
        []
      ),
    () => deployContract('ValidatorWalletCreator', signer, [], verify, true),
    () => deployContract('DeployHelper', signer, [], verify, true),
  ])

  console.log('Deploying bridgeCreator...')
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

  console.log('Deploying RollupProxy for verification if needed...')
  // Deploy RollupProxy for verification if needed
  if (verify && !process.env.DISABLE_VERIFICATION) {
    await deployContract('RollupProxy', signer, [], verify, true)
  }

  console.log('Deploying RollupCreator...')
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

export async function deployOneStepProofEntry(
  signer: any,
  verify: boolean = true,
  isSerialDeployment: boolean = false
): Promise<{
  prover0: Contract
  proverMem: Contract
  proverMath: Contract
  proverHostIo: Contract
  osp: Contract
}> {
  console.log(
    `Deploying OneStepProver contracts${
      isSerialDeployment ? ' in serial mode' : ''
    }...`
  )

  const [prover0, proverMem, proverMath, proverHostIo] = await deployBatch([
    () => deployContract('OneStepProver0', signer, [], verify, true),
    () => deployContract('OneStepProverMemory', signer, [], verify, true),
    () => deployContract('OneStepProverMath', signer, [], verify, true),
    () => deployContract('OneStepProverHostIo', signer, [], verify, true),
  ])

  console.log('Deploying OneStepProofEntry...')
  const osp = await deployContract(
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
