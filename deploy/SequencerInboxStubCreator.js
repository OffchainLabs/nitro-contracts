module.exports = async hre => {
  const { deployments, getNamedAccounts } = hre
  const { deployer } = await getNamedAccounts()

  const bridge = await deployments.get('BridgeStub')
  const maxTime = {
    delayBlocks: 10000,
    futureBlocks: 10000,
    delaySeconds: 10000,
    futureSeconds: 10000,
  }
  await deployments.deploy('SequencerInboxStub', {
    from: deployer,
    args: [bridge.address, deployer, maxTime, 117964, false, true],
  })
}

module.exports.tags = ['SequencerInboxStub', 'test']
module.exports.dependencies = ['BridgeStub']
