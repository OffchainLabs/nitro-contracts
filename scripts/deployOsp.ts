import { ethers } from 'hardhat'
import { deployOneStepProofEntry } from './deploymentUtils'

async function main() {
  const [deployer] = await ethers.getSigners()

  console.log('Deploying OneStepProofEntry with the following configuration:')
  console.log('Deployer:', deployer.address)
  console.log('Network:', (await ethers.provider.getNetwork()).name)

  // Deploy OneStepProofEntry and its dependencies
  const deployment = await deployOneStepProofEntry(
    deployer,
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
