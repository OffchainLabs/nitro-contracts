import dotenv from 'dotenv'
import { getGasSpendingRecord } from './gasReportLib'
import { writeFileSync } from 'fs'

dotenv.config()

const FILE_PATH = '.referentGasReport'

function main() {
  const infuraKey = process.env['INFURA_KEY'] as string
  if (!infuraKey) {
    throw new Error('INFURA_KEY env var should be set')
  }
  const mainnetRpc = `https://mainnet.infura.io/v3/${infuraKey}`

  const referentGasReport = getGasSpendingRecord(mainnetRpc, false)
  try {
    writeFileSync(FILE_PATH, JSON.stringify(referentGasReport, null, 2))
  } catch (error) {
    console.error('An error occurred saving the referent gas report:', error)
  }
}

main()
