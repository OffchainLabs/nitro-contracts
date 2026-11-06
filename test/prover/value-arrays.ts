import { ethers, run, deployments } from 'hardhat'

describe('ValueArray', function () {
  it('Should pass ValueArrayTester', async function () {
    await run('deploy', { tags: 'ValueArrayTester' })

    const valueArrayTester = await ethers.getContractAt(
      'ValueArrayTester',
      (
        await deployments.get('ValueArrayTester')
      ).address
    )

    await valueArrayTester.test()
  })
})
