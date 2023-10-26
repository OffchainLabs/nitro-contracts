module.exports = async hre => {
  const { deployments, getNamedAccounts, ethers } = hre
  const { deploy } = deployments
  const { deployer } = await getNamedAccounts()

  const bridge = await ethers.getContract('BridgeStub')
  const blobBasefeeReader = await ethers.getContract('BlobBasefeeReader')
  const dataHashReader = await ethers.getContract('DataHashReader')
  const maxTime = {
    delayBlocks: 10000,
    futureBlocks: 10000,
    delaySeconds: 10000,
    futureSeconds: 10000,
  }
  await deploy('SequencerInboxStub', {
    from: deployer,
    args: [
      bridge.address,
      deployer,
      maxTime,
      117964,
      dataHashReader,
      blobBasefeeReader,
    ],
  })
}

module.exports.tags = ['SequencerInboxStub', 'test']
module.exports.dependencies = ['BridgeStub']
