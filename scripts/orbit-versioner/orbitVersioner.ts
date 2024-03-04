import { Provider } from '@ethersproject/providers'
import { ethers } from 'hardhat'
import metadataHashes from './referentMetadataHashes.json'
import {
  IBridge__factory,
  Inbox__factory,
  RollupCore__factory,
} from '../../build/types'
import '@nomiclabs/hardhat-ethers'

main()
  .then(() => process.exit(0))
  .catch((error: Error) => {
    console.error(error)
  })

interface ReferentMetadataHashes {
  Inbox: string
  Outbox: string
  SequencerInbox: string
  Bridge: string
}
interface MetadataHashesByNativeToken {
  eth: ReferentMetadataHashes
  erc20: ReferentMetadataHashes
}
interface MetadataHashesByVersion {
  [version: string]: MetadataHashesByNativeToken
}

/**
 * Load the referent metadata hashes
 */
const referentMetadataHashes: MetadataHashesByVersion = metadataHashes

async function main() {
  const provider = ethers.provider
  const chainId = (await provider.getNetwork()).chainId

  console.log(
    "Get the version of Orbit chain's nitro contracts, hosted on chain",
    chainId
  )

  // get all core addresses from inbox address
  const inboxAddress = process.env.INBOX_ADDRESS!
  const inbox = Inbox__factory.connect(inboxAddress, provider)
  const bridge = IBridge__factory.connect(await inbox.bridge(), provider)
  const seqInboxAddress = await bridge.sequencerInbox()
  const outboxAddress = await RollupCore__factory.connect(
    await bridge.rollup(),
    provider
  ).outbox()

  // get metadata hashes
  const metadataHashes = {
    Inbox: await _getMetadataHash(inboxAddress, provider),
    Outbox: await _getMetadataHash(outboxAddress, provider),
    SequencerInbox: await _getMetadataHash(seqInboxAddress, provider),
    Bridge: await _getMetadataHash(bridge.address, provider),
  }

  console.log('metadataHashes of deployed contracts:', metadataHashes)

  // get version
  const version = await _getVersionOfDeployedContracts(metadataHashes, 'eth')
  console.log('\nVersion of deployed contracts:', version ? version : 'unknown')
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

async function _getVersionOfDeployedContracts(
  metadataHashes: any,
  type: 'eth' | 'erc20'
): Promise<string | null> {
  for (const [version] of Object.entries(referentMetadataHashes)) {
    if (
      metadataHashes.Inbox === referentMetadataHashes[version][type].Inbox &&
      metadataHashes.Outbox === referentMetadataHashes[version][type].Outbox &&
      metadataHashes.SequencerInbox ===
        referentMetadataHashes[version][type].SequencerInbox &&
      metadataHashes.Bridge === referentMetadataHashes[version][type].Bridge
    ) {
      return version
    }
  }
  return null
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
