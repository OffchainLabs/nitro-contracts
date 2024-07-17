module.exports = async hre => {
  const { deployments, getNamedAccounts, ethers } = hre
  const { deploy } = deployments
  const { deployer } = await getNamedAccounts()

  await deploy('ChallengeManager', { from: deployer, args: [] })
}

module.exports.tags = ['ChallengeManager']
module.exports.dependencies = []
