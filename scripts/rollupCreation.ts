import { ethers } from 'hardhat'
import '@nomiclabs/hardhat-ethers'
import { run } from 'hardhat'
import { abi as rollupCreatorAbi } from '../build/contracts/src/rollup/RollupCreator.sol/RollupCreator.json'
import { config, maxDataSize } from './config'
import { BigNumber } from 'ethers'
import { IERC20__factory } from '../build/types'
import { sleep } from './testSetup'
import hre from 'hardhat'
import { promises as fs } from 'fs'

// 1 gwei
const MAX_FER_PER_GAS = BigNumber.from('1000000000')

const isDevDeployment = hre.network.name.includes('testnode')

interface RollupCreatedEvent {
  event: string
  address: string
  args?: {
    rollupAddress: string
    inboxAddress: string
    outbox: string
    rollupEventInbox: string
    challengeManager: string
    adminProxy: string
    sequencerInbox: string
    bridge: string
    validatorUtils: string
    validatorWalletCreator: string
  }
}

export async function createRollup(feeToken?: string) {
  const rollupCreatorAddress = process.env.ROLLUP_CREATOR_ADDRESS

  if (!rollupCreatorAddress) {
    console.error(
      'Please provide ROLLUP_CREATOR_ADDRESS as an environment variable.'
    )
    process.exit(1)
  }

  if (!rollupCreatorAbi) {
    throw new Error(
      'You need to first run <deployment.ts> script to deploy and compile the contracts first'
    )
  }

  const [signer] = await ethers.getSigners()

  const rollupCreator = new ethers.Contract(
    rollupCreatorAddress,
    rollupCreatorAbi,
    signer
  )

  if (!feeToken) {
    feeToken = ethers.constants.AddressZero
  }

  try {
    let vals: boolean[] = []
    for (let i = 0; i < config.validators.length; i++) {
      vals.push(true)
    }

    //// funds for deploying L2 factories

    // 0.13 ETH is enough to deploy L2 factories via retryables. Excess is refunded
    let feeCost = ethers.utils.parseEther('0.13')
    if (feeToken != ethers.constants.AddressZero) {
      // in case fees are paid via fee token, then approve rollup cretor to spend required amount
      await (
        await IERC20__factory.connect(feeToken, signer).approve(
          rollupCreator.address,
          feeCost
        )
      ).wait()
      feeCost = BigNumber.from(0)
    }

    // Call the createRollup function
    console.log('Calling createRollup to generate a new rollup ...')
    const deployParams = isDevDeployment
      ? await _getDevRollupConfig(feeToken)
      : {
          config: config.rollupConfig,
          validators: config.validators,
          maxDataSize: maxDataSize,
          nativeToken: feeToken,
          deployFactoriesToL2: true,
          maxFeePerGasForRetryables: MAX_FER_PER_GAS,
          batchPosters: [config.batchPoster],
          batchPosterManager: signer.address,
        }
    const createRollupTx = await rollupCreator.createRollup(deployParams, {
      value: feeCost,
    })
    const createRollupReceipt = await createRollupTx.wait()

    const rollupCreatedEvent = createRollupReceipt.events?.find(
      (event: RollupCreatedEvent) =>
        event.event === 'RollupCreated' &&
        event.address.toLowerCase() === rollupCreatorAddress.toLowerCase()
    )

    // Checking for RollupCreated event for new rollup address
    if (rollupCreatedEvent) {
      const rollupAddress = rollupCreatedEvent.args?.rollupAddress
      const inboxAddress = rollupCreatedEvent.args?.inboxAddress
      const outbox = rollupCreatedEvent.args?.outbox
      const rollupEventInbox = rollupCreatedEvent.args?.rollupEventInbox
      const challengeManager = rollupCreatedEvent.args?.challengeManager
      const adminProxy = rollupCreatedEvent.args?.adminProxy
      const sequencerInbox = rollupCreatedEvent.args?.sequencerInbox
      const bridge = rollupCreatedEvent.args?.bridge
      const validatorUtils = rollupCreatedEvent.args?.validatorUtils
      const validatorWalletCreator =
        rollupCreatedEvent.args?.validatorWalletCreator

      console.log("Congratulations! 🎉🎉🎉 All DONE! Here's your addresses:")
      console.log('RollupProxy Contract created at address:', rollupAddress)

      if (isDevDeployment) {
        console.log('Wait a minute before starting the contract verification')
        await sleep(1 * 60 * 1000)
        console.log(
          `Attempting to verify Rollup contract at address ${rollupAddress}...`
        )
        try {
          await run('verify:verify', {
            contract: 'src/rollup/RollupProxy.sol:RollupProxy',
            address: rollupAddress,
            constructorArguments: [],
          })
        } catch (error: any) {
          if (error.message.includes('Already Verified')) {
            console.log(`Contract RollupProxy is already verified.`)
          } else {
            console.error(
              `Verification for RollupProxy failed with the following error: ${error.message}`
            )
          }
        }
      }

      console.log('Inbox (proxy) Contract created at address:', inboxAddress)
      console.log('Outbox (proxy) Contract created at address:', outbox)
      console.log(
        'rollupEventInbox (proxy) Contract created at address:',
        rollupEventInbox
      )
      console.log(
        'challengeManager (proxy) Contract created at address:',
        challengeManager
      )
      console.log('AdminProxy Contract created at address:', adminProxy)
      console.log('SequencerInbox (proxy) created at address:', sequencerInbox)
      console.log('Bridge (proxy) Contract created at address:', bridge)
      console.log('ValidatorUtils Contract created at address:', validatorUtils)
      console.log(
        'ValidatorWalletCreator Contract created at address:',
        validatorWalletCreator
      )

      const blockNumber = createRollupReceipt.blockNumber
      console.log('All deployed at block number:', blockNumber)
    } else {
      console.error('RollupCreated event not found')
    }
  } catch (error) {
    console.error(
      'Deployment failed:',
      error instanceof Error ? error.message : error
    )
  }
}

async function _getDevRollupConfig(feeToken: string) {
  console.log('getting dev rollup config')

  // set up owner address
  const ownerAddress =
    process.env.OWNER_ADDRESS !== undefined ? process.env.OWNER_ADDRESS : ''

  // set up max data size
  const _maxDataSize =
    process.env.MAX_DATA_SIZE !== undefined
      ? ethers.BigNumber.from(process.env.MAX_DATA_SIZE)
      : 117964

  // set up validators
  const authorizeValidators =
    process.env.AUTHORIZE_VALIDATORS !== undefined
      ? parseInt(process.env.AUTHORIZE_VALIDATORS, 0)
      : 0
  const validators: string[] = []
  for (let i = 1; i <= authorizeValidators; i++) {
    validators.push(ethers.Wallet.createRandom().address)
  }

  // get chain config
  const childChainConfigPath =
    process.env.CHILD_CHAIN_CONFIG_PATH !== undefined
      ? process.env.CHILD_CHAIN_CONFIG_PATH
      : 'l2_chain_config.json'
  const chainConfig = await fs.readFile(childChainConfigPath, {
    encoding: 'utf8',
  })

  // get wasmModuleRoot
  const wasmModuleRoot =
    process.env.WASM_MODULE_ROOT !== undefined
      ? process.env.WASM_MODULE_ROOT
      : ''

  // set up batch posters
  const sequencerAddress =
    process.env.SEQUENCER_ADDRESS !== undefined
      ? process.env.SEQUENCER_ADDRESS
      : ''
  const batchPostersString =
    process.env.BATCH_POSTERS !== undefined ? process.env.BATCH_POSTERS : ''
  let batchPosters: string[] = []
  if (batchPostersString.length == 0) {
    batchPosters.push(sequencerAddress)
  } else {
    const batchPostesArr = batchPostersString.split(',')
    for (let i = 0; i < batchPostesArr.length; i++) {
      if (ethers.utils.isAddress(batchPostesArr[i])) {
        batchPosters.push(batchPostesArr[i])
      } else {
        throw new Error('Invalid address in batch posters array')
      }
    }
  }

  // set up batch poster manager
  const batchPosterManagerEnv =
    process.env.BATCH_POSTER_MANAGER !== undefined
      ? process.env.BATCH_POSTER_MANAGER
      : ''
  let batchPosterManager = ''
  if (ethers.utils.isAddress(batchPosterManagerEnv)) {
    batchPosterManager = batchPosterManagerEnv
  } else {
    if (batchPosterManagerEnv.length == 0) {
      batchPosterManager = ownerAddress
    } else {
      throw new Error('Invalid address for batch poster manager')
    }
  }

  // set up parent chain id
  let parentChainId =
    process.env.L1_CHAIN_ID !== undefined
      ? ethers.BigNumber.from(process.env.L1_CHAIN_ID)
      : 1337

  console.log('dev rollup config:', {
    config: {
      confirmPeriodBlocks: ethers.BigNumber.from('20'),
      extraChallengeTimeBlocks: ethers.BigNumber.from('200'),
      stakeToken: ethers.constants.AddressZero,
      baseStake: ethers.utils.parseEther('1'),
      wasmModuleRoot: wasmModuleRoot,
      owner: ownerAddress,
      loserStakeEscrow: ethers.constants.AddressZero,
      chainId: parentChainId,
      chainConfig: chainConfig,
      sequencerInboxMaxTimeVariation: {
        delayBlocks: ethers.BigNumber.from('5760'),
        futureBlocks: ethers.BigNumber.from('12'),
        delaySeconds: ethers.BigNumber.from('86400'),
        futureSeconds: ethers.BigNumber.from('3600'),
      },
    },
    validators: validators,
    maxDataSize: _maxDataSize,
    nativeToken: feeToken,
    deployFactoriesToL2: true,
    maxFeePerGasForRetryables: MAX_FER_PER_GAS,
    batchPosters: batchPosters,
    batchPosterManager: batchPosterManager,
  })

  return {
    config: {
      confirmPeriodBlocks: ethers.BigNumber.from('20'),
      extraChallengeTimeBlocks: ethers.BigNumber.from('200'),
      stakeToken: ethers.constants.AddressZero,
      baseStake: ethers.utils.parseEther('1'),
      wasmModuleRoot: wasmModuleRoot,
      owner: ownerAddress,
      loserStakeEscrow: ethers.constants.AddressZero,
      chainId: parentChainId,
      chainConfig: chainConfig,
      genesisBlockNum: 0,
      sequencerInboxMaxTimeVariation: {
        delayBlocks: ethers.BigNumber.from('5760'),
        futureBlocks: ethers.BigNumber.from('12'),
        delaySeconds: ethers.BigNumber.from('86400'),
        futureSeconds: ethers.BigNumber.from('3600'),
      },
    },
    validators: validators,
    maxDataSize: _maxDataSize,
    nativeToken: feeToken,
    deployFactoriesToL2: true,
    maxFeePerGasForRetryables: MAX_FER_PER_GAS,
    batchPosters: batchPosters,
    batchPosterManager: batchPosterManager,
  }
}
