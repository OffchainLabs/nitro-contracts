import { ethers } from 'hardhat'
import '@nomiclabs/hardhat-ethers'
import { createRollup } from './rollupCreation'

async function main() {
  const rollupCreatorAddress = process.env.ROLLUP_CREATOR_ADDRESS
  if (!rollupCreatorAddress) {
    throw new Error('ROLLUP_CREATOR_ADDRESS not set')
  }

  let feeToken = process.env.FEE_TOKEN_ADDRESS as string
  // if fee token is not set, then use address(0) to have ETH as fee token
  if (!feeToken) {
    feeToken = ethers.constants.AddressZero
  }
  const [signer] = await ethers.getSigners()

  await createRollup(signer, false, rollupCreatorAddress, feeToken)
}

main()
  .then(() => process.exit(0))
  .catch((error: Error) => {
    console.error(error)
    process.exit(1)
  })
