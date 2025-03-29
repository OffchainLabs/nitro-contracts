module.exports = async hre => {
  const { deployments, getNamedAccounts, ethers } = hre
  const { deploy } = deployments
  const { deployer } = await getNamedAccounts()

  const blobBasefeeReader = await ethers.getContractAt(
    'BlobBasefeeReader',
    (
      await deployments.get('BlobBasefeeReader')
    ).address
  )
  const dataHashReader = await ethers.getContractAt(
    'DataHashReader',
    (
      await deployments.get('DataHashReader')
    ).address
  )

  await deploy('SequencerInbox', { from: deployer, args: [117964] })
}

module.exports.tags = ['SequencerInbox']
module.exports.dependencies = []
