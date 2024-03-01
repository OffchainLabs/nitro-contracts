import { Provider } from '@ethersproject/providers'
import { ethers } from 'hardhat'
import bytecodes from './ref.json'

main()
  .then(() => process.exit(0))
  .catch((error: Error) => {
    console.error(error)
  })

interface referentBytecodes {
  Inbox: string
  Outbox: string
  Rollup: string
}

interface BytecodeByVersion {
  [version: string]: referentBytecodes
}

async function main() {
  console.log("Get the version of Orbit chain's nitro contracts")

  const [signer] = await ethers.getSigners()
  const provider = signer.provider!

  const deployedContracts = {
    Inbox: await _getLogicAddress(
      '0xCCfB5947c850aA34D3C8f290344Ee540d4608Bd6',
      provider
    ),
    Outbox: await _getLogicAddress(
      '0xCCfB5947c850aA34D3C8f290344Ee540d4608Bd6',
      provider
    ),
    Rollup: await _getLogicAddress(
      '0xCCfB5947c850aA34D3C8f290344Ee540d4608Bd6',
      provider
    ),
  }

  const referentBytecodes: BytecodeByVersion = bytecodes

  console.log('Deployed contracts:', deployedContracts)
  console.log('Contract bytecodes:', referentBytecodes)

  const version = _findMatchingVersion(deployedContracts, referentBytecodes)
  console.log('Orbit version:', version)
}

async function _getLogicAddress(
  contractAddress: string,
  provider: Provider
): Promise<string> {
  return (
    await _getAddressAtStorageSlot(
      contractAddress,
      provider,
      '0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc'
    )
  ).toLowerCase()
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

function _findMatchingVersion(
  deployedContracts: referentBytecodes,
  referentBytecodes: BytecodeByVersion
): string | undefined {
  for (const [version, versionBytecodes] of Object.entries(referentBytecodes)) {
    if (
      deployedContracts.Inbox === versionBytecodes.Inbox &&
      deployedContracts.Outbox === versionBytecodes.Outbox &&
      deployedContracts.Rollup === versionBytecodes.Rollup
    ) {
      return version // Found a matching version
    }
  }

  return undefined // No match found
}
