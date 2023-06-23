import { ethers } from 'hardhat'
import '@nomiclabs/hardhat-ethers'
import { run } from 'hardhat'
import { abi as rollupCreatorAbi } from '../build/contracts/src/rollup/RollupCreator.sol/RollupCreator.json'
import { rollupConfig } from './config'
import { abi as rollupCoreAbi } from '../build/contracts/src/rollup/RollupCore.sol/RollupCore.json'

interface RollupCreatedEvent {
  event: string
  address: string
  args?: {
    rollupAddress: string
    inboxAddress: string
    adminProxy: string
    sequencerInbox: string
    bridge: string
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
    // Call the createRollup function
    console.log('Calling createRollup to generate a new rollup ...')
    const createRollupTx = await rollupCreator.createRollup(rollupConfig)
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
      const adminProxy = rollupCreatedEvent.args?.adminProxy
      const sequencerInbox = rollupCreatedEvent.args?.sequencerInbox
      const bridge = rollupCreatedEvent.args?.bridge

      const rollupCore = new ethers.Contract(
        rollupAddress,
        rollupCoreAbi,
        signer
      )

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
      console.log(
        'Outbox Contract created at address:',
        await rollupCore.outbox()
      )
      console.log('AdminProxy Contract created at address:', adminProxy)
      console.log('SequencerInbox (proxy) created at address:', sequencerInbox)
      console.log('Bridge (proxy) Contract created at address:', bridge)
      console.log(
        'ValidatorUtils Contract created at address:',
        await rollupCore.validatorUtils()
      )
      console.log(
        'ValidatorWalletCreator Contract created at address:',
        await rollupCore.validatorWalletCreator()
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
