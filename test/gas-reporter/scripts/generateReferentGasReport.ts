import dotenv from 'dotenv'
import { REFERENT_REPORT_FILE_PATH, getGasSpendingRecord } from './gasReportLib'
import { writeFileSync } from 'fs'

dotenv.config()

function main() {
  /// get infura key to create RPC endpoint
  const infuraKey = process.env['INFURA_KEY'] as string
  if (!infuraKey) {
    throw new Error('INFURA_KEY env var should be set')
  }
  const mainnetRpc = `https://mainnet.infura.io/v3/${infuraKey}`

  /// get the gas record for the current implementation
  const referentGasReport = getGasSpendingRecord(mainnetRpc, false)

  /// save the referent gas report
  try {
    writeFileSync(
      REFERENT_REPORT_FILE_PATH,
      JSON.stringify(referentGasReport, null, 2)
    )
    console.log(`Referent gas report saved to ${REFERENT_REPORT_FILE_PATH}`)
  } catch (error) {
    console.error('An error occurred saving the referent gas report:', error)
  }
}

main()
