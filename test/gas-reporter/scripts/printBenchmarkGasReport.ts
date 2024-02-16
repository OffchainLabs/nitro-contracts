import dotenv from 'dotenv'
import {
  REFERENT_REPORT_FILE_PATH,
  getGasSpendingRecord,
  printGasReportDiff,
} from './gasReportLib'
import { existsSync, readFileSync } from 'fs'

dotenv.config()

function main() {
  /// get infura key to create RPC endpoint
  const infuraKey = process.env['INFURA_KEY'] as string
  if (!infuraKey) {
    throw new Error('INFURA_KEY env var should be set')
  }
  const mainnetRpc = `https://mainnet.infura.io/v3/${infuraKey}`

  /// if referent gas report exists load it, else generate it by running benchmark test on production contracts
  let referentGasRecord
  let isProd = false
  if (existsSync(REFERENT_REPORT_FILE_PATH)) {
    const data = readFileSync(REFERENT_REPORT_FILE_PATH, 'utf-8')
    referentGasRecord = JSON.parse(data)
  } else {
    referentGasRecord = getGasSpendingRecord(mainnetRpc, true)
    isProd = true
  }

  /// get the gas record for the current implementation
  const currentImplementationGasRecord = getGasSpendingRecord(mainnetRpc, false)

  /// compare referent vs current implementation gas report
  let implementation = isProd ? 'production contracts' : `snapshot in ${REFERENT_REPORT_FILE_PATH}`
  console.log('Gas diff between and current implementation:')
  printGasReportDiff(referentGasRecord, currentImplementationGasRecord)
}

main()
