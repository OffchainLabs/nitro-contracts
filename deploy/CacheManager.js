const initCacheSize = 536870912 // (half a gig)
const initDecay = 10322197911 // (DAO makes $1m+ a year)
// const proxyAdminAddr = '0xdb216562328215E010F819B5aBe947bad4ca961e' // Arb1 Proxy Admin
// const proxyAdminAddr = '0xf58eA15B20983116c21b05c876cc8e6CDAe5C2b9' // Nova Proxy Admin
const proxyAdminAddr = '0x715D99480b77A8d9D603638e593a539E21345FdF' // ArbSepolia Proxy Admin

module.exports = async hre => {
  const { deployments, getNamedAccounts } = hre
  const { deploy } = deployments
  const { deployer } = await getNamedAccounts()

  // deploy behind proxy
  await deploy('CacheManager', {
    from: deployer,
    args: [],
    proxy: {
      proxyContract: 'TransparentUpgradeableProxy',
      execute: {
        init: {
          methodName: 'initialize',
          args: [initCacheSize, initDecay],
        },
      },
      owner: proxyAdminAddr,
    },
  })
}

module.exports.tags = ['CacheManager']
module.exports.dependencies = []
