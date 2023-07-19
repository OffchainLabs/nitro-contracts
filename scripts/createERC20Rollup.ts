import { ethers } from 'hardhat'
import '@nomiclabs/hardhat-ethers'
import { Signer } from 'ethers'
import { ERC20PresetFixedSupply__factory } from '../build/types/factories/@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply__factory'
import { createRollup } from './rollupCreation'

async function deployERC20Token(deployer: Signer): Promise<string> {
  const factory = await new ERC20PresetFixedSupply__factory(deployer).deploy(
    'FeeToken',
    'FEE',
    ethers.utils.parseEther('1000000000'),
    await deployer.getAddress()
  )
  const feeToken = await factory.deployed()

  return feeToken.address
}

async function main() {
  const [deployer] = await ethers.getSigners()
  const customFeeTokenAddress = await deployERC20Token(deployer)

  console.log('Creating new rollup with', customFeeTokenAddress, 'as fee token')
  await createRollup(customFeeTokenAddress)
}

main()
  .then(() => process.exit(0))
  .catch((error: Error) => {
    console.error(error)
    process.exit(1)
  })
