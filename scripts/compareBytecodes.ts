import { execSync } from 'child_process'
import * as fs from 'fs'
import * as path from 'path'

interface ComparisonResult {
  contract: string
  hardhatBytecode: string
  foundryBytecode: string
  match: boolean
  hardhatLength: number
  foundryLength: number
  difference: string
}

function getHardhatArtifacts(): Map<string, string> {
  const artifacts = new Map<string, string>()
  const artifactsDir = path.join(__dirname, '..', 'build', 'contracts')

  function scanDirectory(dir: string) {
    const files = fs.readdirSync(dir)

    for (const file of files) {
      const fullPath = path.join(dir, file)
      const stat = fs.statSync(fullPath)

      if (stat.isDirectory()) {
        scanDirectory(fullPath)
      } else if (file.endsWith('.json')) {
        const content = JSON.parse(fs.readFileSync(fullPath, 'utf8'))
        if (content.bytecode && content.bytecode !== '0x') {
          const contractName = file.replace('.json', '')
          artifacts.set(contractName, content.bytecode)
        }
      }
    }
  }

  if (fs.existsSync(artifactsDir)) {
    scanDirectory(artifactsDir)
  }

  return artifacts
}

function getFoundryArtifacts(): Map<string, string> {
  const artifacts = new Map<string, string>()
  const outDir = path.join(__dirname, '..', 'out')

  function scanDirectory(dir: string, basePath: string = '') {
    const files = fs.readdirSync(dir)

    for (const file of files) {
      const fullPath = path.join(dir, file)
      const stat = fs.statSync(fullPath)

      if (stat.isDirectory()) {
        // Skip test directories
        if (file === 'test' || file === 'mocks' || file === 'test-helpers') {
          continue
        }
        scanDirectory(fullPath, path.join(basePath, file))
      } else if (file.endsWith('.json')) {
        const content = JSON.parse(fs.readFileSync(fullPath, 'utf8'))
        if (
          content.bytecode &&
          content.bytecode.object &&
          content.bytecode.object !== '0x'
        ) {
          const contractName = file.replace('.json', '')
          // Include the path in the key for Foundry artifacts
          const key = basePath ? `${basePath}/${contractName}` : contractName
          artifacts.set(key, content.bytecode.object)
        }
      }
    }
  }

  if (fs.existsSync(outDir)) {
    scanDirectory(outDir)
  }

  return artifacts
}

function findMatchingContracts(
  hardhatArtifacts: Map<string, string>,
  foundryArtifacts: Map<string, string>
): ComparisonResult[] {
  const results: ComparisonResult[] = []

  // For each Hardhat artifact, try to find the corresponding Foundry artifact
  for (const [contractName, hardhatBytecode] of hardhatArtifacts) {
    let foundryBytecode = ''
    let foundryKey = ''

    // Try to find exact match first
    for (const [key, bytecode] of foundryArtifacts) {
      if (key.endsWith(`/${contractName}`) || key === contractName) {
        foundryBytecode = bytecode
        foundryKey = key
        break
      }
    }

    if (foundryBytecode) {
      // Normalize bytecodes (remove 0x prefix if present)
      const normalizedHardhat = hardhatBytecode.startsWith('0x')
        ? hardhatBytecode.slice(2)
        : hardhatBytecode
      const normalizedFoundry = foundryBytecode.startsWith('0x')
        ? foundryBytecode.slice(2)
        : foundryBytecode

      // Compare normalized bytecodes
      const match = normalizedHardhat === normalizedFoundry

      let difference = ''
      if (!match) {
        // Find the first position where they differ
        for (
          let i = 0;
          i < Math.min(normalizedHardhat.length, normalizedFoundry.length);
          i++
        ) {
          if (normalizedHardhat[i] !== normalizedFoundry[i]) {
            difference = `First difference at position ${i}`
            break
          }
        }
        if (
          !difference &&
          normalizedHardhat.length !== normalizedFoundry.length
        ) {
          difference = 'Different lengths'
        }
      }

      results.push({
        contract: contractName,
        hardhatBytecode: normalizedHardhat,
        foundryBytecode: normalizedFoundry,
        match,
        hardhatLength: normalizedHardhat.length,
        foundryLength: normalizedFoundry.length,
        difference,
      })
    }
  }

  return results
}

async function main() {
  console.log('\nBuilding with Foundry...')
  execSync('yarn build:forge:sol --force', { stdio: 'inherit' })

  console.log('\nLoading artifacts...')
  const hardhatArtifacts = getHardhatArtifacts()
  const foundryArtifacts = getFoundryArtifacts()

  console.log(`Found ${hardhatArtifacts.size} Hardhat artifacts`)
  console.log(`Found ${foundryArtifacts.size} Foundry artifacts`)

  console.log('\nComparing bytecodes...')
  const results = findMatchingContracts(hardhatArtifacts, foundryArtifacts)

  // Print summary
  console.log('\n=== BYTECODE COMPARISON SUMMARY ===')
  console.log(`Total contracts compared: ${results.length}`)

  const matching = results.filter(r => r.match)
  const different = results.filter(r => !r.match)

  console.log(`Matching bytecodes: ${matching.length}`)
  console.log(`Different bytecodes: ${different.length}`)

  if (different.length > 0) {
    console.log('\n=== CONTRACTS WITH DIFFERENT BYTECODES ===')
    for (const result of different) {
      console.log(`\n${result.contract}:`)
      console.log(`  Hardhat length: ${result.hardhatLength}`)
      console.log(`  Foundry length: ${result.foundryLength}`)
      console.log(`  Difference: ${result.difference}`)

      // Show a snippet of where they differ
      if (result.difference.startsWith('First difference at position')) {
        const pos = parseInt(result.difference.match(/\d+/)?.[0] || '0')
        const start = Math.max(0, pos - 20)
        const end = Math.min(
          pos + 20,
          Math.min(result.hardhatBytecode.length, result.foundryBytecode.length)
        )

        console.log(
          `  Hardhat snippet: ...${result.hardhatBytecode.slice(start, end)}...`
        )
        console.log(
          `  Foundry snippet: ...${result.foundryBytecode.slice(start, end)}...`
        )
      }
    }
  }

  // // Save detailed results to file
  // const outputPath = path.join(
  //   __dirname,
  //   '..',
  //   'bytecode-comparison-results.json'
  // )
  // fs.writeFileSync(outputPath, JSON.stringify(results, null, 2))
  // console.log(`\nDetailed results saved to: ${outputPath}`)

  // Return exit code based on whether all bytecodes match
  if (different.length > 0) {
    console.log(
      '\n⚠️  Some bytecodes do not match between Hardhat and Foundry builds'
    )
    process.exit(1)
  } else {
    console.log('\n✅ All bytecodes match between Hardhat and Foundry builds')
    process.exit(0)
  }
}

main().catch(error => {
  console.error('Error:', error)
  process.exit(1)
})
