module.exports = async hre => {
  const { deployments, getNamedAccounts } = hre
  const { deploy } = deployments
  const { deployer } = await getNamedAccounts()

  await deploy('ExpressLaneAuction', {
    from: deployer,
    args: [],
    proxy: {
      proxyContract: 'TransparentUpgradeableProxy',
      execute: {
        init: {
          methodName: 'initialize',
          args: [{
            _auctioneer: "0xeee584DA928A94950E177235EcB9A99bb655c7A0",
            _biddingToken: "0x980B62Da83eFf3D4576C647993b0c1D7faf17c73", // WETH
            _beneficiary: "0xeee584DA928A94950E177235EcB9A99bb655c7A0",
            _roundTimingInfo: {
              offsetTimestamp: 1727870000,
              roundDurationSeconds: 60,
              auctionClosingSeconds: 15,
              reserveSubmissionSeconds: 15
            },
            _minReservePrice: ethers.utils.parseEther("0.00001"),
            _auctioneerAdmin: "0xeee584DA928A94950E177235EcB9A99bb655c7A0",
            _minReservePriceSetter: "0xeee584DA928A94950E177235EcB9A99bb655c7A0",
            _reservePriceSetter: "0xeee584DA928A94950E177235EcB9A99bb655c7A0", 
            _reservePriceSetterAdmin: "0xeee584DA928A94950E177235EcB9A99bb655c7A0",
            _beneficiarySetter: "0xeee584DA928A94950E177235EcB9A99bb655c7A0",
            _roundTimingSetter: "0xeee584DA928A94950E177235EcB9A99bb655c7A0",
            _masterAdmin: "0xeee584DA928A94950E177235EcB9A99bb655c7A0"
          }],
        },
      },
      owner: deployer,
    },
  })
}

module.exports.tags = ['ExpressLaneAuction']
module.exports.dependencies = []
