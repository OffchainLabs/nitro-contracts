import hre from 'hardhat'
import path from 'path'
import fs from 'fs'

main()
  .then(() => process.exit(0))
  .catch((error: Error) => {
    console.error(error)
  })

/**
 * Load the referent bytecodes
 */
async function main() {
  const ethContracts = ['Inbox', 'Outbox', 'SequencerInbox', 'Bridge']
  for (const contract of ethContracts) {
    console.log(
      `${contract}:`,
      `\n\t Hardhat: ${await _getMetadataHash(contract)} `,
      `\n\t Foundry: ${_getMetadataHashFromFoundryBuild(contract)} `
    )
  }
  console.log('')

  const erc20Contracts = [
    'ERC20Inbox',
    'ERC20Outbox',
    'SequencerInbox',
    'ERC20Bridge',
  ]
  for (const contract of erc20Contracts) {
    console.log(
      `${contract}:`,
      `\n\t Hardhat: ${await _getMetadataHash(contract)} `,
      `\n\t Foundry: ${_getMetadataHashFromFoundryBuild(contract)} `
    )
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

function _getMetadataHashFromFoundryBuild(contractName: string): string {
  const buildFilePath = path.join(
    'out/',
    `${contractName}.sol`,
    `${contractName}.json`
  )
  const fileContent = fs.readFileSync(buildFilePath, { encoding: 'utf8' })
  const buildJson = JSON.parse(fileContent)
  const bytecode = buildJson.bytecode.object

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
