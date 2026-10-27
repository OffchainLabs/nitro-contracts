import { ethers } from 'hardhat'
import '@nomiclabs/hardhat-ethers'
import { promises as fs } from 'fs'
import { AbsBridge__factory, BridgeCreator__factory, OneStepProofEntry__factory, Ownable__factory, RollupCore__factory, RollupCreator__factory, SequencerInbox__factory, ValidatorWalletCreator__factory } from '../build/types';
import { BigNumber } from 'ethers';
import { execSync } from 'child_process';

// Types
type Alloc = {
  [key: string]: {
    code: `0x${string}`,
    nonce: number,
    balance: string
    storage?: { [key: `0x${string}`]: `0x${string}` }
  }
};

// Check environment variables
const parentChainRpc = process.env.PARENT_CHAIN_RPC as string
if (!parentChainRpc) {
  throw new Error('PARENT_CHAIN_RPC not set')
}
const parentChainProvider = new ethers.providers.JsonRpcProvider(parentChainRpc);

const rollupCreatorAddress = process.env.ROLLUP_CREATOR_ADDRESS as `0x${string}`
if (!rollupCreatorAddress) {
  throw new Error('ROLLUP_CREATOR_ADDRESS not set')
}

// Helper function to get contract code and nonce
async function getAccountInformation(address: `0x${string}`, contractPath?: string, excludeStorageEntries?: string[]) {
  const code = await parentChainProvider.getCode(address)
  const nonce = await parentChainProvider.getTransactionCount(address)
  const balance = await parentChainProvider.getBalance(address);
  let storage = {};
  if (contractPath) {
    storage = await getStorageLayout(address, contractPath, excludeStorageEntries);
  }
  return { code: code as `0x${string}`, nonce, balance: balance.toString(), storage }
}

// Helper function and types to get the storage layout
type ForgeStorageEntry = {
  astId: number;
  contract: string;
  label: string;
  offset: number;
  slot: string;   // note: string, we’ll convert to bigint
  type: string;
  bytes: string;
};

type ForgeTypeInfo = {
  label: string;
  encoding: "inplace" | "mapping" | "dynamic_array" | string;
  numberOfBytes: string;
  base?: string;
  key?: string;
  value?: string;
  members?: any[];
};

type ForgeStorageLayout = {
  storage: ForgeStorageEntry[];
  types: Record<string, any>;
};

function isMapping(type: string): boolean {
  return type.startsWith("t_mapping");
}

function isArrayType(type: string): boolean {
  return type.startsWith("t_array");
}

// crude: fixed vs dynamic array from type name
function parseArrayInfo(type: string): { baseType: string; length?: number } {
  // examples:
  //   t_array(t_address)dyn_storage
  //   t_array(t_uint256)40_storage
  const m = type.match(/^t_array\(([^)]+)\)([^_]*)_storage$/);
  if (!m) return { baseType: type };

  const baseType = m[1];
  const lenPart = m[2]; // "dyn" or "40"
  if (lenPart === "dyn") {
    return { baseType };
  }

  const length = Number(lenPart);
  return { baseType, length };
}

// pad slot -> 32-byte for keccak
function slotToPaddedHex(slot: bigint): string {
  return ethers.utils.hexZeroPad(ethers.utils.hexlify(slot), 32);
}

async function getStorageLayout(address: `0x${string}`, contractPath: string, excludeStorageEntries?: string[]) {
  // Get Storage layout from contract code
  const rawStorageLayout = execSync(
    `forge inspect ${contractPath} storage --json`,
    { encoding: "utf8" } // so we get a string instead of Buffer
  );
  const layout: ForgeStorageLayout = JSON.parse(rawStorageLayout);
  const entries = layout.storage;

  // Read storage entries in contract
  const storage: Record<string, string> = {};
  const simpleSlots = new Set<bigint>();
  
  for (const entry of entries) {
    const slot = BigInt(entry.slot);
    const type = entry.type;
    if (excludeStorageEntries && excludeStorageEntries.includes(entry.label)) {
      continue;
    }

    // Mappings
    if (isMapping(type)) {
      // skip mappings: need explicit keys
      continue;
    }

    // Arrays
    if (isArrayType(type)) {
      const { length } = parseArrayInfo(type);

      if (length !== undefined) {
        // fixed-length array: contiguous slots
        for (let i = 0; i < length; i++) {
          simpleSlots.add(slot + BigInt(i));
        }
      } else {
        // dynamic array: slot holds length; data at keccak(slot) + i
        const lenWord = await parentChainProvider.getStorageAt(address, slot);
        storage[ethers.utils.hexlify(slot)] = lenWord;

        const arrLength = Number(BigInt(lenWord));
        const dataStart = ethers.utils.keccak256(slotToPaddedHex(slot));
        const base = BigInt(dataStart);

        for (let i = 0; i < arrLength; i++) {
          const elemSlot = base + BigInt(i);
          const elemValue = await parentChainProvider.getStorageAt(address, elemSlot);
          storage[ethers.utils.hexlify(elemSlot)] = elemValue;
        }
      }

      continue;
    }

    // For all other types, read number of slots based on size
    //    This covers:
    //    - scalar vars (bytes <= 32 → 1 word)
    //    - structs (ex., bytes=192 → 6 words)
    const typeInfo = layout.types[entry.type];
    const bytes = Number(typeInfo.numberOfBytes);
    const nWords = Math.max(1, Math.ceil(bytes / 32));
    for (let i = 0; i < nWords; i++) {
      simpleSlots.add(slot + BigInt(i));
    }
  }

  // Parallel fetch of simple slots
  await Promise.all(
    Array.from(simpleSlots).map(async (slot) => {
      const value = await parentChainProvider.getStorageAt(address, slot);
      storage[ethers.utils.hexlify(slot)] = value;
    })
  );

  return storage;
}

async function main() {
  // Initialize alloc object
  const alloc: Alloc = {};

  // Create2 proxy
  const create2ProxyAddress = '0x4e59b44847b379578588920cA78FbF26c0B4956C' as `0x${string}`;
  alloc[create2ProxyAddress] = await getAccountInformation(create2ProxyAddress);

  // RollupCreator
  alloc[rollupCreatorAddress] = await getAccountInformation(rollupCreatorAddress, 'src/rollup/RollupCreator.sol:RollupCreator');

  // BridgeCreator
  const rollupCreator = RollupCreator__factory.connect(
    rollupCreatorAddress,
    parentChainProvider
  );
  const bridgeCreatorAddress = (await rollupCreator.bridgeCreator()) as `0x${string}`;
  alloc[bridgeCreatorAddress] = await getAccountInformation(bridgeCreatorAddress, 'src/rollup/BridgeCreator.sol:BridgeCreator');

  // Bridge contracts
  const bridgeCreator = BridgeCreator__factory.connect(
    bridgeCreatorAddress,
    parentChainProvider
  );
  const ethBasedTemplates = await bridgeCreator.ethBasedTemplates();
  for (const templateAddress of Object.values(ethBasedTemplates)) {
    alloc[templateAddress as `0x${string}`] = await getAccountInformation(templateAddress as `0x${string}`);
  }
  const erc20BasedTemplates = await bridgeCreator.erc20BasedTemplates();
  for (const templateAddress of Object.values(erc20BasedTemplates)) {
    alloc[templateAddress as `0x${string}`] = await getAccountInformation(templateAddress as `0x${string}`);
  }

  // Reader4844
  // (Note: all SequencerInboxes share the same Reader4844 contract)
  const sequencerInbox = SequencerInbox__factory.connect(
    ethBasedTemplates.sequencerInbox as `0x${string}`,
    parentChainProvider
  );
  const reader4844Address = (await sequencerInbox.reader4844()) as `0x${string}`;
  alloc[reader4844Address] = await getAccountInformation(reader4844Address);

  // OneStepProof contracts
  const ospAddress = (await rollupCreator.osp()) as `0x${string}`;
  alloc[ospAddress] = await getAccountInformation(ospAddress, 'src/osp/OneStepProofEntry.sol:OneStepProofEntry');
  const osp = OneStepProofEntry__factory.connect(
    ospAddress,
    parentChainProvider
  );

  const prover0 = (await osp.prover0()) as `0x${string}`;
  alloc[prover0] = await getAccountInformation(prover0);
  const proverMem = (await osp.proverMem()) as `0x${string}`;
  alloc[proverMem] = await getAccountInformation(proverMem);
  const proverMath = (await osp.proverMath()) as `0x${string}`;
  alloc[proverMath] = await getAccountInformation(proverMath);
  const proverHostIo = (await osp.proverHostIo()) as `0x${string}`;
  alloc[proverHostIo] = await getAccountInformation(proverHostIo);

  // Rollup and challenge manager contracts
  const challengeManagerAddress = (await rollupCreator.challengeManagerTemplate()) as `0x${string}`;
  alloc[challengeManagerAddress] = await getAccountInformation(challengeManagerAddress);
  const rollupAdminLogicAddress = (await rollupCreator.rollupAdminLogic()) as `0x${string}`;
  alloc[rollupAdminLogicAddress] = await getAccountInformation(rollupAdminLogicAddress);
  const rollupUserLogicAddress = (await rollupCreator.rollupUserLogic()) as `0x${string}`;
  alloc[rollupUserLogicAddress] = await getAccountInformation(rollupUserLogicAddress);

  // UpdgradeExecutor and ValidatorWallet
  const upgradeExecutorLogicAddress = (await rollupCreator.upgradeExecutorLogic()) as `0x${string}`;
  alloc[upgradeExecutorLogicAddress] = await getAccountInformation(upgradeExecutorLogicAddress);
  const validatorWalletCreatorAddress = (await rollupCreator.validatorWalletCreator()) as `0x${string}`;
  alloc[validatorWalletCreatorAddress] = await getAccountInformation(validatorWalletCreatorAddress, 'src/rollup/ValidatorWalletCreator.sol:ValidatorWalletCreator');
  const validatorWalletCreator = ValidatorWalletCreator__factory.connect(
    validatorWalletCreatorAddress,
    parentChainProvider
  );
  const validatorWalletTemplateAddress = (await validatorWalletCreator.template()) as `0x${string}`;
  alloc[validatorWalletTemplateAddress] = await getAccountInformation(validatorWalletTemplateAddress);

  // DeployHelper
  const deployHelperAddress = (await rollupCreator.l2FactoriesDeployer()) as `0x${string}`;
  alloc[deployHelperAddress] = await getAccountInformation(deployHelperAddress);

  /*
  // Rollup contracts (if specified)
  const rollupAddress = process.env.ROLLUP_ADDRESS as `0x${string}` | undefined;
  if (rollupAddress && ethers.utils.isAddress(rollupAddress)) {
    alloc[rollupAddress] = await getAccountInformation(rollupAddress);

    const rollup = RollupCore__factory.connect(
      rollupAddress,
      parentChainProvider
    );

    // Bridge
    const bridgeAddress = (await rollup.bridge()) as `0x${string}`;
    alloc[bridgeAddress] = await getAccountInformation(bridgeAddress);
    // Add mappings
    // Add implementation slot and admin slot for all contracts behind proxies

    // SequencerInbox
    const sequencerInboxAddress = (await rollup.sequencerInbox()) as `0x${string}`;
    alloc[sequencerInboxAddress] = await getAccountInformation(sequencerInboxAddress);
    
    // Inbox
    const delayedInboxAddress = (await rollup.inbox()) as `0x${string}`;
    alloc[delayedInboxAddress] = await getAccountInformation(delayedInboxAddress);

    // RollupEventInbox
    const rollupEventInboxAddress = (await rollup.rollupEventInbox()) as `0x${string}`;
    alloc[rollupEventInboxAddress] = await getAccountInformation(rollupEventInboxAddress);

    // Outbox
    const outboxAddress = (await rollup.outbox()) as `0x${string}`;
    alloc[outboxAddress] = await getAccountInformation(outboxAddress);

    // ChallengeManager
    const challengeManagerAddress = (await rollup.challengeManager()) as `0x${string}`;
    alloc[challengeManagerAddress] = await getAccountInformation(challengeManagerAddress);

    // ValidatorWalletCreator
    const validatorWalletCreatorAddress = (await rollup.validatorWalletCreator()) as `0x${string}`;
    alloc[validatorWalletCreatorAddress] = await getAccountInformation(validatorWalletCreatorAddress);

    // UpgradeExecutor
    const rollupOwnable = Ownable__factory.connect(
      rollupAddress,
      parentChainProvider
    );
    const upgradeExecutorAddress = (await rollupOwnable.owner()) as `0x${string}`;
    alloc[upgradeExecutorAddress] = await getAccountInformation(upgradeExecutorAddress);

    // ProxyAdmin
    const rawProxyAdminAddress = (await parentChainProvider.getStorageAt(delayedInboxAddress, BigNumber.from("0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103"))) as `0x${string}`;
    const proxyAdminAddress = ethers.utils.getAddress(ethers.utils.hexDataSlice(rawProxyAdminAddress, 12)) as `0x${string}`;
    alloc[proxyAdminAddress] = await getAccountInformation(proxyAdminAddress);
  }

  // Deployer address (if specified)
  const deployerAddress = process.env.DEPLOYER_ADDRESS as `0x${string}` | undefined;
  if (deployerAddress && ethers.utils.isAddress(deployerAddress)) {
    alloc[deployerAddress] = await getAccountInformation(deployerAddress);
  }
  */

  // Craft file
  const allocPath =
    process.env.LOCAL_DEPLOYMENT_ALLOC_PATH !== undefined
      ? process.env.LOCAL_DEPLOYMENT_ALLOC_PATH
      : 'local_deployment_alloc.json'

  await fs.writeFile(allocPath, JSON.stringify(alloc, null, 2), 'utf8')
}

main()
  .then(() => process.exit(0))
  .catch((error: Error) => {
    console.error(error)
    process.exit(1)
  })
