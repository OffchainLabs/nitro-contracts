import { ethers } from 'hardhat'
import '@nomiclabs/hardhat-ethers'
import { deployAllContracts } from '../deploymentUtils'
import { createRollup } from '../rollupCreation'
import { promises as fs } from 'fs'
import { BigNumber } from 'ethers'

async function main() {
  /// read env vars needed for deployment
  let childChainName = process.env.CHILD_CHAIN_NAME as string
  if (!childChainName) {
    throw new Error('CHILD_CHAIN_NAME not set')
  }

  let deployerPrivKey = process.env.DEPLOYER_PRIVKEY as string
  if (!deployerPrivKey) {
    throw new Error('DEPLOYER_PRIVKEY not set')
  }

  let parentChainRpc = process.env.PARENT_CHAIN_RPC as string
  if (!parentChainRpc) {
    throw new Error('PARENT_CHAIN_RPC not set')
  }

  if (!process.env.PARENT_CHAIN_ID) {
    throw new Error('PARENT_CHAIN_ID not set')
  }

  const deployerWallet = new ethers.Wallet(
    deployerPrivKey,
    new ethers.providers.JsonRpcProvider(parentChainRpc)
  )

  const maxDataSize =
    process.env.MAX_DATA_SIZE !== undefined
      ? ethers.BigNumber.from(process.env.MAX_DATA_SIZE)
      : ethers.BigNumber.from(117964)

  /// get fee token address, if undefined use address(0) to have ETH as fee token
  let feeToken = process.env.FEE_TOKEN_ADDRESS as string
  if (!feeToken) {
    feeToken = ethers.constants.AddressZero
  }
  let feeTokenPricer = process.env.FEE_TOKEN_PRICER_ADDRESS as string
  if (!feeTokenPricer) {
    feeTokenPricer = ethers.constants.AddressZero
  }

  /// get stake token address, if undefined deploy WETH and set it as stake token
  let stakeToken = process.env.STAKE_TOKEN_ADDRESS as string
  if (!stakeToken) {
    console.log('Deploying WETH')
    const wethFactory = (await ethers.getContractFactory('TestWETH9')).connect(
      deployerWallet
    )
    const weth = await wethFactory.deploy('Wrapped Ether', 'WETH')
    await weth.deployTransaction.wait()
    await weth.deployed()
    stakeToken = weth.address
    console.log('WETH deployed at', stakeToken)
  }

  let customOsp = process.env.CUSTOM_OSP_ADDRESS as string
  if (!customOsp) {
    customOsp = ethers.constants.AddressZero
  }

  const factoryCode = await deployerWallet.provider.getCode(
    '0x4e59b44847b379578588920ca78fbf26c0b4956c'
  )
  if (factoryCode.length <= 2) {
    console.log('Deploying CREATE2 factory')
    const fundingTx = await deployerWallet.sendTransaction({
      to: '0x3fab184622dc19b6109349b94811493bf2a45362',
      value: ethers.utils.parseEther('0.01'),
    })
    await fundingTx.wait()
    const create2SignedTx =
      '0xf8a58085174876e800830186a08080b853604580600e600039806000f350fe7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf31ba02222222222222222222222222222222222222222222222222222222222222222a02222222222222222222222222222222222222222222222222222222222222222'
    const create2DeployTx = await deployerWallet.provider.sendTransaction(
      create2SignedTx
    )
    await create2DeployTx.wait()
  }

  /// deploy templates and rollup creator
  console.log('Deploy RollupCreator')
  const contracts = await deployAllContracts(
    deployerWallet,
    deployerWallet.address,
    maxDataSize,
    false
  )

  console.log('Set templates on the Rollup Creator')
  await (
    await contracts.rollupCreator.setTemplates(
      contracts.bridgeCreator.address,
      contracts.osp.address,
      contracts.challengeManager.address,
      contracts.rollupAdmin.address,
      contracts.rollupUser.address,
      contracts.upgradeExecutor.address,
      contracts.validatorWalletCreator.address,
      contracts.deployHelper.address,
      { gasLimit: BigNumber.from('300000') }
    )
  ).wait()

  /// Create rollup
  const chainId = (await deployerWallet.provider.getNetwork()).chainId
  console.log(
    'Create rollup on top of chain',
    chainId,
    'using RollupCreator',
    contracts.rollupCreator.address
  )
  const result = await createRollup(
    deployerWallet,
    true,
    contracts.rollupCreator.address,
    feeToken,
    feeTokenPricer,
    stakeToken,
    customOsp
  )

  if (!result) {
    throw new Error('Rollup creation failed')
  }

  const { rollupCreationResult, chainInfo } = result

  /// store deployment address
  // chain deployment info
  const chainDeploymentInfo =
    process.env.CHAIN_DEPLOYMENT_INFO !== undefined
      ? process.env.CHAIN_DEPLOYMENT_INFO
      : 'deploy.json'
  await fs.writeFile(
    chainDeploymentInfo,
    JSON.stringify(rollupCreationResult, null, 2),
    'utf8'
  )

  // child chain info
  chainInfo['chain-name'] = childChainName
  const childChainInfo =
    process.env.CHILD_CHAIN_INFO !== undefined
      ? process.env.CHILD_CHAIN_INFO
      : 'l2_chain_info.json'
  await fs.writeFile(
    childChainInfo,
    JSON.stringify([chainInfo], null, 2),
    'utf8'
  )
}

main()
  .then(() => process.exit(0))
  .catch((error: Error) => {
    console.error(error)
    process.exit(1)
  })
