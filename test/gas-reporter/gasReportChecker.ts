import { execSync } from 'child_process'
import dotenv from 'dotenv'

dotenv.config()

async function main() {
  const infuraKey = process.env['INFURA_KEY'] as string
  if (!infuraKey) {
    throw new Error('INFURA_KEY env var should be set')
  }
  const mainnetRpc = `https://mainnet.infura.io/v3/${infuraKey}`

  const [referentGasReport, currentImplementationGasReport] =
    _getGasReports(mainnetRpc)

  _printGasReportDiff(referentGasReport, currentImplementationGasReport)
}

function _getGasReports(
  rpc: string
): [Record<string, number>, Record<string, number>] {
  const gasReportCmd = `FOUNDRY_PROFILE=gasreporter forge test --fork-url ${rpc} --fork-block-number 19140521 --gas-report`

  const referentGasReportOutput = execSync(
    gasReportCmd + ` --match-contract GasSpendingReferentReportTest`
  ).toString()
  const referentGasReport = _parseGasConsumption(referentGasReportOutput)

  const currentImplementationGasReportOutput = execSync(
    gasReportCmd + ` --match-contract GasSpendingReportTest`
  ).toString()
  const currentImplementationGasReport = _parseGasConsumption(
    currentImplementationGasReportOutput
  )

  return [referentGasReport, currentImplementationGasReport]
}

function _parseGasConsumption(report: string): Record<string, number> {
  const gasUsagePattern = /(depositEth|executeTransaction)\s+\|\s+(\d+)/g
  const gasConsumption: Record<string, number> = {}
  let match

  while ((match = gasUsagePattern.exec(report)) !== null) {
    // match[1] is the function name, match[2] is the gas consumption
    gasConsumption[match[1]] = parseInt(match[2], 10)
  }

  return gasConsumption
}

function _printGasReportDiff(
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

main().then(() => console.log('Done.'))
