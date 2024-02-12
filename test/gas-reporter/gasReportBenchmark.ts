import dotenv from 'dotenv'
import { getGasSpendingRecord, printGasReportDiff } from './gasReportLib'

dotenv.config()

function main() {
  const infuraKey = process.env['INFURA_KEY'] as string
  if (!infuraKey) {
    throw new Error('INFURA_KEY env var should be set')
  }
  const mainnetRpc = `https://mainnet.infura.io/v3/${infuraKey}`

  const referentGasRecord = getGasSpendingRecord(mainnetRpc, true)
  const currentImplementationGasRecodrd = getGasSpendingRecord(
    mainnetRpc,
    false
  )

  printGasReportDiff(referentGasRecord, currentImplementationGasRecodrd)
}

main()
