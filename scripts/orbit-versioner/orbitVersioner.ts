import { Provider } from '@ethersproject/providers'
import { ethers } from 'hardhat'
import bytecodes from './ref.json'
import {
  IBridge__factory,
  Inbox__factory,
  RollupCore__factory,
} from '../../build/types'

main()
  .then(() => process.exit(0))
  .catch((error: Error) => {
    console.error(error)
  })

interface ReferentBytecodes {
  Inbox: string[]
  Outbox: string[]
  Rollup: string[]
  SequencerInbox: string[]
  Bridge: string[]
}
interface BytecodeByNativeToken {
  eth: ReferentBytecodes
  erc20: ReferentBytecodes
}
interface BytecodeByVersion {
  [version: string]: BytecodeByNativeToken
}
interface DeployedContracts {
  Inbox: string
  Outbox: string
  Rollup: string
  SequencerInbox: string
  Bridge: string
}

/**
 * Load the referent bytecodes
 */
const referentBytecodes: BytecodeByVersion = bytecodes

async function main() {
  console.log("Get the version of Orbit chain's nitro contracts")

  const [signer] = await ethers.getSigners()
  const provider = signer.provider!

  // get all addresses from inbox
  const inboxAddress = process.env.INBOX_ADDRESS!
  const inbox = Inbox__factory.connect(inboxAddress, provider)
  const bridge = IBridge__factory.connect(await inbox.bridge(), provider)
  const seqInboxAddress = await bridge.sequencerInbox()
  const rollupAddress = await bridge.rollup()
  const outboxAddress = await RollupCore__factory.connect(
    rollupAddress,
    provider
  ).outbox()

  // get logic contracts
  const metadataHashes = {
    Inbox: await _getMetadataHash(inboxAddress, provider),
    Outbox: await _getMetadataHash(outboxAddress, provider),
    Rollup: await _getMetadataHash(rollupAddress, provider),
    SequencerInbox: await _getMetadataHash(seqInboxAddress, provider),
    Bridge: await _getMetadataHash(bridge.address, provider),
  }

  console.log('metadataHashes of deployed contracts:', metadataHashes)
}

async function _getLogicAddress(
  contractAddress: string,
  provider: Provider
): Promise<string> {
  const logic = (
    await _getAddressAtStorageSlot(
      contractAddress,
      provider,
      '0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc'
    )
  ).toLowerCase()

  if (logic == '' || logic == ethers.constants.AddressZero) {
    return contractAddress
  }

  return logic
}

async function _getAddressAtStorageSlot(
  contractAddress: string,
  provider: Provider,
  storageSlotBytes: string
): Promise<string> {
  const storageValue = await provider.getStorageAt(
    contractAddress,
    storageSlotBytes
  )

  if (!storageValue) {
    return ''
  }

  // remove excess bytes
  const formatAddress =
    storageValue.substring(0, 2) + storageValue.substring(26)

  // return address as checksum address
  return ethers.utils.getAddress(formatAddress)
}

async function _findMatchingVersion(
  deployedContracts: DeployedContracts,
  isUsingFeeToken: boolean,
  referentBytecodes: BytecodeByVersion,
  provider: Provider
): Promise<string | null> {
  const nativeTokenType = isUsingFeeToken ? 'erc20' : 'eth'

  const inbox = await provider.getCode(deployedContracts.Inbox)
  const outbox = await provider.getCode(deployedContracts.Outbox)
  const rollup = await provider.getCode(deployedContracts.Rollup)
  const seqInbox = await provider.getCode(deployedContracts.SequencerInbox)
  const bridge = await provider.getCode(deployedContracts.Bridge)

  for (const [version] of Object.entries(referentBytecodes)) {
    if (
      isMatchingVersion(inbox, version, nativeTokenType, 'Inbox') &&
      isMatchingVersion(outbox, version, nativeTokenType, 'Outbox') &&
      isMatchingVersion(rollup, version, nativeTokenType, 'Rollup') &&
      isMatchingVersion(seqInbox, version, nativeTokenType, 'SequencerInbox') &&
      isMatchingVersion(bridge, version, nativeTokenType, 'Bridge')
    ) {
      return version
    }
  }

  return null
}

function isMatchingVersion(
  deployedBytecode: string,
  version: string,
  type: 'eth' | 'erc20',
  contractName: keyof ReferentBytecodes
): boolean {
  const bytecodeToLookAt = referentBytecodes[version]?.[type]?.[contractName]

  if (!bytecodeToLookAt) {
    throw new Error(
      `No referent bytecodes found for ${contractName} in version ${version} and type ${type}.`
    )
  }
  return bytecodeToLookAt.some(
    (referentBytecode: string) => referentBytecode === deployedBytecode
  )
}

async function _getMetadataHash(
  contractAddress: string,
  provider: Provider
): Promise<string> {
  const implAddress = await _getLogicAddress(contractAddress, provider)
  const bytecode = await provider.getCode(implAddress)

  // Pattern to match the metadata prefix and the following 64 hex characters (32 bytes)
  const metadataPattern = /a264697066735822([a-fA-F0-9]{64})/
  const matches = bytecode.match(metadataPattern)

  if (matches && matches.length > 1) {
    // The actual metadata hash is in the first capturing group
    return matches[1]
  } else {
    throw new Error('No metadata hash found in bytecode')
  }
}
