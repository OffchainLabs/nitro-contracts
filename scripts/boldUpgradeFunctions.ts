import { BigNumber, Contract, ContractFactory, ethers, Signer } from 'ethers'
import {
  BOLDUpgradeAction__factory,
  Bridge__factory,
  EdgeChallengeManager__factory,
  OneStepProofEntry__factory,
  OneStepProver0__factory,
  OneStepProverHostIo__factory,
  OneStepProverMath__factory,
  OneStepProverMemory__factory,
  Outbox__factory,
  RollupAdminLogic__factory,
  RollupEventInbox__factory,
  RollupUserLogic__factory,
  SequencerInbox__factory,
  Inbox__factory,
  StateHashPreImageLookup__factory,
  IReader4844__factory,
  IOldRollup__factory,
} from '../build/types'
import { bytecode as Reader4844Bytecode } from '../out/yul/Reader4844.yul/Reader4844.json'
import { DeployedContracts, Config } from './boldUpgradeCommon'
import { AssertionStateStruct } from '../build/types/src/challengeV2/IAssertionChain'
import { verifyContract } from './deploymentUtils'

export const deployDependencies = async (
  signer: Signer,
  maxDataSize: number,
  isUsingFeeToken: boolean,
  isDelayBufferable: boolean,
  log: boolean = false,
  verify: boolean = true
): Promise<Omit<DeployedContracts, 'boldAction' | 'preImageHashLookup'>> => {
  // const bridgeFac = new Bridge__factory(signer)
  // const bridge = await bridgeFac.deploy()
  const bridge = Bridge__factory.connect(
    '0x93e8f92327bFa8096F5F6ee5f2a49183D3B3b898',
    signer
  )
  await bridge.deployed()
  if (log) {
    console.log(`Bridge implementation deployed at: ${bridge.address}`)
  }
  // if (verify) {
  //   await bridge.deployTransaction.wait(5)
  //   await verifyContract(
  //     'Bridge',
  //     bridge.address,
  //     [],
  //     'src/bridge/Bridge.sol:Bridge'
  //   )
  // }

  // const contractFactory = new ContractFactory(
  //   IReader4844__factory.abi,
  //   Reader4844Bytecode,
  //   signer
  // )
  // const reader4844 = await contractFactory.deploy()
  const reader4844 = IReader4844__factory.connect(
    '0x15b25E3fb8419dA4848a6f193bb9b43519D0d4ca',
    signer
  )
  await reader4844.deployed()
  console.log(`Reader4844 deployed at ${reader4844.address}`)

  // const seqInboxFac = new SequencerInbox__factory(signer)
  // const seqInbox = await seqInboxFac.deploy(
  //   maxDataSize,
  //   reader4844.address,
  //   isUsingFeeToken,
  //   isDelayBufferable
  // )
  const seqInbox = SequencerInbox__factory.connect(
    '0x98a58ADAb0f8A66A1BF4544d804bc0475dff32c7',
    signer
  )
  await seqInbox.deployed()
  if (log) {
    console.log(
      `Sequencer inbox implementation deployed at: ${seqInbox.address}`
    )
  }
  // if (verify) {
  //   await seqInbox.deployTransaction.wait(5)
  //   await verifyContract('SequencerInbox', seqInbox.address, [
  //     maxDataSize,
  //     reader4844.address,
  //     isUsingFeeToken,
  //     isDelayBufferable,
  //   ])
  // }

  // const reiFac = new RollupEventInbox__factory(signer)
  // const rei = await reiFac.deploy()
  const rei = RollupEventInbox__factory.connect(
    '0x6D576E220Cb44C3E8eF75D0EfBeb1Ff041e2E4A5',
    signer
  )
  await rei.deployed()
  if (log) {
    console.log(`Rollup event inbox implementation deployed at: ${rei.address}`)
  }
  // if (verify) {
  //   await rei.deployTransaction.wait(5)
  //   await verifyContract('RollupEventInbox', rei.address, [])
  // }

  // const outboxFac = new Outbox__factory(signer)
  // const outbox = await outboxFac.deploy()
  const outbox = Outbox__factory.connect(
    '0x3FFf9BdC3ce99d3D587b0d06Aa7C4a10075193b4',
    signer
  )
  await outbox.deployed()
  if (log) {
    console.log(`Outbox implementation deployed at: ${outbox.address}`)
  }
  // if (verify) {
  //   await outbox.deployTransaction.wait(5)
  //   await verifyContract('Outbox', outbox.address, [])
  // }

  // const inboxFac = new Inbox__factory(signer)
  // const inbox = await inboxFac.deploy(maxDataSize)
  const inbox = Inbox__factory.connect(
    '0x7C058ad1D0Ee415f7e7f30e62DB1BCf568470a10',
    signer
  )
  await inbox.deployed()
  if (log) {
    console.log(`Inbox implementation deployed at: ${inbox.address}`)
  }
  // if (verify) {
  //   await inbox.deployTransaction.wait(5)
  //   await verifyContract('Inbox', inbox.address, [maxDataSize])
  // }

  // const newRollupUserFac = new RollupUserLogic__factory(signer)
  // const newRollupUser = await newRollupUserFac.deploy()
  const newRollupUser = RollupUserLogic__factory.connect(
    '0x6490bA0a60Cc7d3a59C9eeE135D9eeD24553a60d',
    signer
  )
  await newRollupUser.deployed()
  if (log) {
    console.log(`New rollup user logic deployed at: ${newRollupUser.address}`)
  }
  // if (verify) {
  //   await newRollupUser.deployTransaction.wait(5)
  //   await verifyContract('RollupUserLogic', newRollupUser.address, [])
  // }

  // const newRollupAdminFac = new RollupAdminLogic__factory(signer)
  // const newRollupAdmin = await newRollupAdminFac.deploy()
  const newRollupAdmin = RollupAdminLogic__factory.connect(
    '0x7FC126FF51183a78C5E0437467f325f661D8Df17',
    signer
  )
  await newRollupAdmin.deployed()
  if (log) {
    console.log(`New rollup admin logic deployed at: ${newRollupAdmin.address}`)
  }
  // if (verify) {
  //   await newRollupAdmin.deployTransaction.wait(5)
  //   await verifyContract('RollupAdminLogic', newRollupAdmin.address, [])
  // }

  // const challengeManagerFac = new EdgeChallengeManager__factory(signer)
  // const challengeManager = await challengeManagerFac.deploy()
  const challengeManager = EdgeChallengeManager__factory.connect(
    '0x058E1cBb62096189Bc7Cc1FE08A0859905d969Ea',
    signer
  )
  await challengeManager.deployed()
  if (log) {
    console.log(`Challenge manager deployed at: ${challengeManager.address}`)
  }
  // if (verify) {
  //   await challengeManager.deployTransaction.wait(5)
  //   await verifyContract('EdgeChallengeManager', challengeManager.address, [])
  // }

  // const prover0Fac = new OneStepProver0__factory(signer)
  // const prover0 = await prover0Fac.deploy()
  const prover0 = OneStepProver0__factory.connect(
    '0x35FBC5F03d86E88973B06Fb9C5a913D54AbdF731',
    signer
  )
  await prover0.deployed()
  if (log) {
    console.log(`Prover0 deployed at: ${prover0.address}`)
  }
  // if (verify) {
  //   await prover0.deployTransaction.wait(5)
  //   await verifyContract('OneStepProver0', prover0.address, [])
  // }

  // const proverMemFac = new OneStepProverMemory__factory(signer)
  // const proverMem = await proverMemFac.deploy()
  const proverMem = OneStepProverMemory__factory.connect(
    '0xe0ba77e0E24de5369e3B268Ea79fDe716e2EC48b',
    signer
  )
  await proverMem.deployed()
  if (log) {
    console.log(`Prover mem deployed at: ${proverMem.address}`)
  }
  // if (verify) {
  //   await proverMem.deployTransaction.wait(5)
  //   await verifyContract('OneStepProverMemory', proverMem.address, [])
  // }

  // const proverMathFac = new OneStepProverMath__factory(signer)
  // const proverMath = await proverMathFac.deploy()
  const proverMath = OneStepProverMath__factory.connect(
    '0xaB9596a0aaF28bc798c453434EC2DC0F8F0bF921',
    signer
  )
  await proverMath.deployed()
  if (log) {
    console.log(`Prover math deployed at: ${proverMath.address}`)
  }
  // if (verify) {
  //   await proverMath.deployTransaction.wait(5)
  //   await verifyContract('OneStepProverMath', proverMath.address, [])
  // }

  // const proverHostIoFac = new OneStepProverHostIo__factory(signer)
  // const proverHostIo = await proverHostIoFac.deploy()
  const proverHostIo = OneStepProverHostIo__factory.connect(
    '0xa07cD154340CC74EcF156FFB9fb378Ee29Ca71Cf',
    signer
  )
  await proverHostIo.deployed()
  if (log) {
    console.log(`Prover host io deployed at: ${proverHostIo.address}`)
  }
  // if (verify) {
  //   await proverHostIo.deployTransaction.wait(5)
  //   await verifyContract('OneStepProverHostIo', proverHostIo.address, [])
  // }

  // const proofEntryFac = new OneStepProofEntry__factory(signer)
  // const proofEntry = await proofEntryFac.deploy(
  //   prover0.address,
  //   proverMem.address,
  //   proverMath.address,
  //   proverHostIo.address
  // )
  const proofEntry = OneStepProofEntry__factory.connect(
    '0x4397fE1E959Ba81B9D5f1A9679Ddd891955A42d6',
    signer
  )
  await proofEntry.deployed()
  if (log) {
    console.log(`Proof entry deployed at: ${proofEntry.address}`)
  }
  // if (verify) {
  //   await proofEntry.deployTransaction.wait(5)
  //   await verifyContract('OneStepProofEntry', proofEntry.address, [
  //     prover0.address,
  //     proverMem.address,
  //     proverMath.address,
  //     proverHostIo.address,
  //   ])
  // }

  return {
    bridge: bridge.address,
    seqInbox: seqInbox.address,
    rei: rei.address,
    outbox: outbox.address,
    inbox: inbox.address,
    newRollupUser: newRollupUser.address,
    newRollupAdmin: newRollupAdmin.address,
    challengeManager: challengeManager.address,
    prover0: prover0.address,
    proverMem: proverMem.address,
    proverMath: proverMath.address,
    proverHostIo: proverHostIo.address,
    osp: proofEntry.address,
  }
}

export const deployBoldUpgrade = async (
  wallet: Signer,
  config: Config,
  log: boolean = false,
  verify: boolean = true
): Promise<DeployedContracts> => {
  const sequencerInbox = SequencerInbox__factory.connect(
    config.contracts.sequencerInbox,
    wallet
  )
  const isUsingFeeToken = await sequencerInbox.isUsingFeeToken()
  const deployed = await deployDependencies(
    wallet,
    config.settings.maxDataSize,
    isUsingFeeToken,
    config.settings.isDelayBufferable,
    log,
    verify
  )
  const fac = new BOLDUpgradeAction__factory(wallet)
  const boldUpgradeAction = await fac.deploy(
    { ...config.contracts, osp: deployed.osp },
    config.proxyAdmins,
    deployed,
    config.settings
  )
  if (log) {
    console.log(`BOLD upgrade action deployed at: ${boldUpgradeAction.address}`)
  }
  if (verify) {
    await boldUpgradeAction.deployTransaction.wait(5)
    await verifyContract('BOLDUpgradeAction', boldUpgradeAction.address, [
      { ...config.contracts, osp: deployed.osp },
      config.proxyAdmins,
      deployed,
      config.settings,
    ])
  }
  const deployedAndBold = {
    ...deployed,
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
