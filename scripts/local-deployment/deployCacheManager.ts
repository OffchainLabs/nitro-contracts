import { ethers } from 'hardhat'
import '@nomiclabs/hardhat-ethers'
import { deployAndSetCacheManager } from '../deploymentUtils'

async function main() {
  /// read env vars needed for deployment
  let chainOwnerPrivKey = process.env.CHAIN_OWNER_PRIVKEY as string
  if (!chainOwnerPrivKey) {
    throw new Error('CHAIN_OWNER_PRIVKEY not set')
  }

  const childChainRpc = process.env.CHILD_CHAIN_RPC as string
  if (!childChainRpc) {
    throw new Error('CHILD_CHAIN_RPC not set')
  }

  const chainOwnerWallet = new ethers.Wallet(
    chainOwnerPrivKey,
    new ethers.providers.JsonRpcProvider(childChainRpc)
  )

  // deploy cache manager
  const cacheManager = await deployAndSetCacheManager(chainOwnerWallet, false)
  console.log('Cache manager deployed at:', cacheManager.address)
}

main()
  .then(() => process.exit(0))
  .catch((error: Error) => {
    console.error(error)
    process.exit(1)
  })
