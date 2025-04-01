module.exports = async hre => {
  const { deployments, getNamedAccounts, ethers } = hre
  const { deployer } = await getNamedAccounts()

  const inboxDeployResult = await deployments.deploy('InboxStub', {
    from: deployer,
    args: [],
  })

  const bridge = await ethers.getContractAt(
    'BridgeStub',
    (
      await deployments.get('BridgeStub')
    ).address
  )
  const inbox = await ethers.getContractAt(
    'InboxStub',
    (
      await deployments.get('InboxStub')
    ).address
  )

  if (inboxDeployResult.newlyDeployed) {
    await bridge.setDelayedInbox(inbox.address, true)
    await inbox.initialize(bridge.address, ethers.constants.AddressZero)
  }
}

module.exports.tags = ['InboxStub', 'test']
module.exports.dependencies = ['BridgeStub']
