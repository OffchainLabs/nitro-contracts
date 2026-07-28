module.exports = async hre => {
  const { deployments, getNamedAccounts, ethers } = hre
  const { deploy } = deployments
  const { deployer } = await getNamedAccounts()

  await deploy('OneStepProverHostIo', {
    from: deployer,
    args: [
      ethers.constants.AddressZero,
      (await deployments.get('HashProofHelper')).address,
    ],
  })
}

module.exports.tags = ['OneStepProverHostIo']
module.exports.dependencies = ['HashProofHelper']
