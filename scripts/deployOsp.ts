import { ethers } from 'hardhat'
import { deployOneStepProofEntry } from './deploymentUtils'

async function main() {
  const [deployer] = await ethers.getSigners()

  // Get custom DA validator address from environment variable
  const customDAValidator =
    process.env.CUSTOM_DA_VALIDATOR || ethers.constants.AddressZero

  console.log('Deploying OneStepProofEntry with the following configuration:')
  console.log('Deployer:', deployer.address)
  console.log('Custom DA Validator:', customDAValidator)
  console.log('Network:', (await ethers.provider.getNetwork()).name)

  // Validate the custom DA validator address if provided
  if (customDAValidator !== ethers.constants.AddressZero) {
    // Check if the address has code deployed
    const code = await ethers.provider.getCode(customDAValidator)
    if (code === '0x') {
      console.warn('WARNING: Custom DA validator address has no code deployed')
    }
  }

  // Deploy OneStepProofEntry and its dependencies
  const deployment = await deployOneStepProofEntry(
    deployer,
    customDAValidator,
    process.env.DISABLE_VERIFICATION !== 'true'
  )

  console.log('\nDeployment completed successfully!')
  console.log('OneStepProver0:', deployment.prover0.address)
  console.log('OneStepProverMemory:', deployment.proverMem.address)
  console.log('OneStepProverMath:', deployment.proverMath.address)
  console.log('OneStepProverHostIo:', deployment.proverHostIo.address)
  console.log('OneStepProofEntry:', deployment.osp.address)
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
