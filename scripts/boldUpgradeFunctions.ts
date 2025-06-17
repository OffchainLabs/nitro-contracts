import { BigNumber, ethers, Signer } from 'ethers'
import {
  BOLDUpgradeAction__factory,
  SequencerInbox__factory,
  StateHashPreImageLookup__factory,
  IOldRollup__factory,
} from '../build/types'
import { DeployedContracts, Config } from './boldUpgradeCommon'
import { AssertionStateStruct } from '../build/types/src/challengeV2/IAssertionChain'
import { verifyContract } from './deploymentUtils'
import { CreatorTemplates } from './files/templatesV3.1'

export const deployBoldUpgrade = async (
  wallet: Signer,
  config: Config,
  contractTemplates: CreatorTemplates,
  log: boolean = false,
  verify: boolean = true
): Promise<DeployedContracts> => {
  const sequencerInbox = SequencerInbox__factory.connect(
    config.contracts.sequencerInbox,
    wallet
  )
  const isUsingFeeToken = await sequencerInbox.isUsingFeeToken()

  // Bridge, SequencerInbox, DelayBufferableSequencerInbox, Inbox, RollupEventInbox, Outbox
  const bridgeContractTemplates = isUsingFeeToken
    ? contractTemplates.erc20
    : contractTemplates.eth

  const templates: Omit<
    DeployedContracts,
    'boldAction' | 'preImageHashLookup'
  > = {
    bridge: bridgeContractTemplates.bridge,
    seqInbox: config.settings.isDelayBufferable
      ? bridgeContractTemplates.delayBufferableSequencerInbox
      : bridgeContractTemplates.sequencerInbox,
    rei: bridgeContractTemplates.rollupEventInbox,
    outbox: bridgeContractTemplates.outbox,
    inbox: bridgeContractTemplates.inbox,
    newRollupUser: contractTemplates.rollupUserLogic,
    newRollupAdmin: contractTemplates.rollupAdminLogic,
    challengeManager: contractTemplates.challengeManagerTemplate,
    osp: contractTemplates.osp,
  }

  // Deploying BoLDUpgradeAction
  const fac = new BOLDUpgradeAction__factory(wallet)
  const boldUpgradeAction = await fac.deploy(
    { ...config.contracts, osp: templates.osp },
    config.proxyAdmins,
    templates,
    config.settings
  )
  if (log) {
    console.log(`BOLD upgrade action deployed at: ${boldUpgradeAction.address}`)
  }
  if (verify) {
    await boldUpgradeAction.deployTransaction.wait(5)
    await verifyContract('BOLDUpgradeAction', boldUpgradeAction.address, [
      { ...config.contracts, osp: templates.osp },
      config.proxyAdmins,
      templates,
      config.settings,
    ])
  }

  // Final result
  const deployedAndBold = {
    ...templates,
    boldAction: boldUpgradeAction.address,
    preImageHashLookup: await boldUpgradeAction.PREIMAGE_LOOKUP(),
  }

  return deployedAndBold
}

export const populateLookup = async (
  wallet: Signer,
  rollupAddr: string,
  preImageHashLookupAddr: string
) => {
  const oldRollup = IOldRollup__factory.connect(rollupAddr, wallet)

  const latestConfirmed = await oldRollup.latestConfirmed()
  let latestConfirmedLog
  let toBlock = await wallet.provider!.getBlockNumber()
  for (let i = 0; i < 100; i++) {
    latestConfirmedLog = await wallet.provider!.getLogs({
      address: rollupAddr,
      fromBlock: toBlock >= 1000 ? toBlock - 1000 : 0,
      toBlock: toBlock,
      topics: [
        oldRollup.interface.getEventTopic('NodeCreated'),
        ethers.utils.hexZeroPad(ethers.utils.hexlify(latestConfirmed), 32),
      ],
    })
    if (latestConfirmedLog.length == 1) break
    if (toBlock == 0) {
      throw new Error('Could not find latest confirmed node')
    }
    toBlock -= 1000
    if (toBlock < 0) {
      toBlock = 0
    }
  }

  if (!latestConfirmedLog || latestConfirmedLog.length != 1) {
    throw new Error('Could not find latest confirmed node')
  }
  const latestConfirmedEvent = oldRollup.interface.parseLog(
    latestConfirmedLog[0]
  ).args
  const afterState: AssertionStateStruct =
    latestConfirmedEvent.assertion.afterState
  const inboxCount: BigNumber = latestConfirmedEvent.inboxMaxCount

  const lookup = StateHashPreImageLookup__factory.connect(
    preImageHashLookupAddr,
    wallet
  )

  const node = await oldRollup.getNode(latestConfirmed)
  const stateHash = await lookup.stateHash(afterState, inboxCount)
  if (node.stateHash != stateHash) {
    throw new Error(`State hash mismatch ${node.stateHash} != ${stateHash}}`)
  }

  await lookup.set(stateHash, afterState, inboxCount)
}
