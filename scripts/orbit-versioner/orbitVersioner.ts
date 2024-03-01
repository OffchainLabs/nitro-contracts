import { Provider } from '@ethersproject/providers'
import { ethers } from 'hardhat'
import bytecodes from './ref.json'
import { IBridge__factory, Inbox__factory } from '../../build/types'

main()
  .then(() => process.exit(0))
  .catch((error: Error) => {
    console.error(error)
  })

interface ReferentBytecodes {
  Inbox: string
  Outbox: string
  Rollup: string
  SequencerInbox: string
  Bridge: string
}
interface BytecodeByNativeToken {
  eth: ReferentBytecodes
  erc20: ReferentBytecodes
}
interface BytecodeByVersion {
  [version: string]: BytecodeByNativeToken
}

async function main() {
  console.log("Get the version of Orbit chain's nitro contracts")

  const [signer] = await ethers.getSigners()
  const provider = signer.provider!

  // get all addresses from inbox
  const inboxAddress = process.env.INBOX_ADDRESS!
  const inbox = Inbox__factory.connect(inboxAddress, provider)
  const bridge = IBridge__factory.connect(await inbox.bridge(), provider)
  const seqInboxAddress = await bridge.sequencerInbox()
  const outboxAddress = await bridge.activeOutbox()
  const rollupAddress = await bridge.rollup()

  // get logic contracts
  const deployedContracts = {
    Inbox: await _getLogicAddress(inboxAddress, provider),
    Outbox: await _getLogicAddress(outboxAddress, provider),
    Rollup: await _getLogicAddress(rollupAddress, provider),
    SequencerInbox: await _getLogicAddress(seqInboxAddress, provider),
    Bridge: await _getLogicAddress(bridge.address, provider),
  }

  // load referent bytecodes
  const referentBytecodes: BytecodeByVersion = bytecodes

  // find version
  const version = await _findMatchingVersion(
    deployedContracts,
    false,
    referentBytecodes,
    provider
  )
  console.log('nitro-contracts version:', version)
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
  deployedContracts: ReferentBytecodes,
  isUsingFeeToken: boolean,
  referentBytecodes: BytecodeByVersion,
  provider: Provider
): Promise<string | undefined> {
  for (const [version, versionBytecodes] of Object.entries(referentBytecodes)) {
    const nativeTokenType = isUsingFeeToken ? 'erc20' : 'eth'
    if (
      (await provider.getCode(deployedContracts.Inbox)) ===
        versionBytecodes[nativeTokenType].Inbox &&
      (await provider.getCode(deployedContracts.Outbox)) ===
        versionBytecodes[nativeTokenType].Outbox &&
      (await provider.getCode(deployedContracts.Rollup)) ===
        versionBytecodes[nativeTokenType].Rollup &&
      (await provider.getCode(deployedContracts.SequencerInbox)) ===
        versionBytecodes[nativeTokenType].SequencerInbox &&
      (await provider.getCode(deployedContracts.Bridge)) ===
        versionBytecodes[nativeTokenType].Bridge
    ) {
      return version
    }
  }

  return undefined
}
