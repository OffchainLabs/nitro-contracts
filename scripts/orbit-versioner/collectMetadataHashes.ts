import hre from 'hardhat'

main()
  .then(() => process.exit(0))
  .catch((error: Error) => {
    console.error(error)
  })

interface Contracts {
  Inbox: string
  Outbox: string
  Rollup: string
  SequencerInbox: string
  Bridge: string
}

/**
 * Load the referent bytecodes
 */
async function main() {
  const ethContracts = ['Inbox', 'Outbox', 'SequencerInbox', 'Bridge']
  for (const contract of ethContracts) {
    console.log(`${contract}: `, await _getMetadataHash(contract))
  }
  console.log('')

  const erc20Contracts = [
    'ERC20Inbox',
    'ERC20Outbox',
    'SequencerInbox',
    'ERC20Bridge',
  ]
  for (const contract of erc20Contracts) {
    console.log(`${contract}: `, await _getMetadataHash(contract))
  }
}

async function _getMetadataHash(contractName: string): Promise<string> {
  const artifact = await hre.artifacts.readArtifact(contractName)
  const bytecode = artifact.bytecode

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
