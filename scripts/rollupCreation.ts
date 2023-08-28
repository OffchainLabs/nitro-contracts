import { ethers } from 'hardhat'
import '@nomiclabs/hardhat-ethers'
import { run } from 'hardhat'
import { abi as rollupCreatorAbi } from '../build/contracts/src/rollup/RollupCreator.sol/RollupCreator.json'
import { config } from './config'

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

async function main() {
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

  const rollupCreator = await new ethers.Contract(
    rollupCreatorAddress,
    rollupCreatorAbi,
    signer
  )

  try {
    let vals: boolean[] = []
    for (let i = 0; i < config.validators.length; i++) {
      vals.push(true)
    }
    // Call the createRollup function
    console.log('Calling createRollup to generate a new rollup ...')
    const createRollupTx = await rollupCreator.createRollup(
      config.rollupConfig,
      config.batchPoster,
      config.validators
    )
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

main()
  .then(() => process.exit(0))
  .catch((error: Error) => {
    console.error(error)
    process.exit(1)
  })
