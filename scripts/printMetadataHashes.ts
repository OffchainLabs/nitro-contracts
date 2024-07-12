import path from 'path'
import fs from 'fs-extra'
import hre from 'hardhat'

main()
  .then(() => process.exit(0))
  .catch((error: Error) => {
    console.error(error)
    process.exit(1)
  })

async function main() {
  const contracts: string[] = [
    'Inbox',
    'Outbox',
    'SequencerInbox',
    'Bridge',
    'ERC20Inbox',
    'ERC20Outbox',
    'SequencerInbox',
    'ERC20Bridge',
    'RollupProxy',
    'RollupAdminLogic',
    'RollupUserLogic',
    'ChallengeManager',
  ]

  console.log('HARDHAT:')
  for (const contract of contracts) {
    const hash = await _getHardhatMetadataHash(contract)
    console.log(`${contract}: ${hash}`)
  }

  console.log('\nFOUNDRY:')
  for (const contract of contracts) {
    const hash = await _getFoundryMetadataHash(contract)
    console.log(`${contract}: ${hash}`)
  }
}

async function _getHardhatMetadataHash(contractName: string): Promise<string> {
  const artifact = await hre.artifacts.readArtifact(contractName)
  return _extractMetadataHash(artifact.bytecode)
}

async function _getFoundryMetadataHash(contractName: string): Promise<string> {
  const artifactPath = path.join(
    'out',
    `${contractName}.sol`,
    `${contractName}.json`
  )
  const artifact = await fs.readJson(artifactPath)
  return _extractMetadataHash(artifact.bytecode.object)
}

function _extractMetadataHash(bytecode: string): string {
  const metadataPattern = /a264697066735822([a-fA-F0-9]{64})/
  const matches = bytecode.match(metadataPattern)

  if (matches && matches.length > 1) {
    return matches[1]
  } else {
    throw new Error('No metadata hash found in bytecode')
  }
}
