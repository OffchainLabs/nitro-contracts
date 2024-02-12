import { execSync } from 'child_process'
import dotenv from 'dotenv'

dotenv.config()

const FORK_BLOCK_NUMBER = 19163009

export function getGasSpendingRecord(
  rpc: string,
  useProductionCode: boolean
): Record<string, number> {
  const gasReportCmd = `FOUNDRY_PROFILE=gasreporter forge test --fork-url ${rpc} --fork-block-number ${FORK_BLOCK_NUMBER} --gas-report`
  const testFile = useProductionCode
    ? 'ProductionGasReportTest'
    : 'CurrentGasReportTest'

  let outputEth = execSync(
    gasReportCmd +
      ` --match-contract ${testFile} --mt "test_depositEth|test_withdrawEth"`
  ).toString()
  outputEth = outputEth.replace(
    'executeTransaction',
    'withdrawEth_executeTransaction'
  )
  const recordEth = _parseGasConsumption(outputEth)

  let outputToken = execSync(
    gasReportCmd + ` --match-contract ${testFile} --mt "test_withdrawToken"`
  ).toString()
  outputToken = outputToken.replace(
    'executeTransaction',
    'withdrawToken_executeTransaction'
  )
  const recordToken = _parseGasConsumption(outputToken)

  return { ...recordEth, ...recordToken }
}

export function printGasReportDiff(
  referentGasReport: Record<string, number>,
  currentImplementationGasReport: Record<string, number>
) {
  console.log('Gas diff compared to referent report:')
  for (const [functionName, referentGas] of Object.entries(referentGasReport)) {
    const currentGas = currentImplementationGasReport[functionName]
    if (currentGas === undefined) {
      continue
    } else {
      const gasDiff = currentGas - referentGas
      const gasDiffPercentage = ((gasDiff / referentGas) * 100).toFixed(2)
      console.log(
        `${functionName}: ${
          gasDiff > 0 ? '+' : ''
        }${gasDiff} (${gasDiffPercentage}%)`
      )
    }
  }
}

function _parseGasConsumption(report: string): Record<string, number> {
  const gasUsagePattern =
    /(depositEth|withdrawEth_executeTransaction|withdrawToken_executeTransaction)\s+\|\s+(\d+)/g
  const gasConsumption: Record<string, number> = {}
  let match

  while ((match = gasUsagePattern.exec(report)) !== null) {
    // match[1] is the function name, match[2] is the gas consumption
    gasConsumption[match[1]] = parseInt(match[2], 10)
  }

  return gasConsumption
}
