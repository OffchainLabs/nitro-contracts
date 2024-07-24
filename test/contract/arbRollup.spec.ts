/*
 * Copyright 2019-2020, Offchain Labs, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/* eslint-env node, mocha */
import { ethers, network } from 'hardhat'
import { Signer } from '@ethersproject/abstract-signer'
import { BigNumberish, BigNumber } from '@ethersproject/bignumber'
import { BytesLike } from '@ethersproject/bytes'
import { ContractTransaction } from '@ethersproject/contracts'
import { assert, expect } from 'chai'
import {
  Bridge__factory,
  Inbox__factory,
  RollupEventInbox__factory,
  Outbox__factory,
  ERC20Bridge__factory,
  ERC20Inbox__factory,
  ERC20RollupEventInbox__factory,
  ERC20Outbox__factory,
  BridgeCreator__factory,
  ChallengeManager,
  ChallengeManager__factory,
  DeployHelper__factory,
  OneStepProofEntry__factory,
  OneStepProver0__factory,
  OneStepProverHostIo__factory,
  OneStepProverMath__factory,
  OneStepProverMemory__factory,
  RollupAdminLogic,
  RollupAdminLogic__factory,
  RollupCreator__factory,
  RollupUserLogic,
  RollupUserLogic__factory,
  SequencerInbox,
  SequencerInbox__factory,
  Bridge,
} from '../../build/types'
import {
  abi as UpgradeExecutorABI,
  bytecode as UpgradeExecutorBytecode,
} from '@offchainlabs/upgrade-executor/build/contracts/src/UpgradeExecutor.sol/UpgradeExecutor.json'

import { initializeAccounts } from './utils'

import {
  Node,
  RollupContract,
  forceCreateNode,
  assertionEquals,
} from './common/rolluplib'
import { AssertionStruct } from '../../build/types/src/rollup/RollupCore'
import { ExecutionStateStruct } from '../../build/types/src/rollup/RollupCore'
import { keccak256 } from 'ethers/lib/utils'
import {
  ConfigStruct,
  RollupCreatedEvent,
} from '../../build/types/src/rollup/RollupCreator'
import { constants, providers } from 'ethers'
import { blockStateHash, MachineStatus } from './common/challengeLib'
import * as globalStateLib from './common/globalStateLib'
import { RollupChallengeStartedEvent } from '../../build/types/src/rollup/IRollupCore'

const zerobytes32 = ethers.constants.HashZero
const stakeRequirement = 10
const stakeToken = ethers.constants.AddressZero
const confirmationPeriodBlocks = 100
const minimumAssertionPeriod = 75
const ZERO_ADDR = ethers.constants.AddressZero
const extraChallengeTimeBlocks = 20
const wasmModuleRoot =
  '0x9900000000000000000000000000000000000000000000000000000000000010'
const dummy4844Reader = '0x0000000000000000000000000000000000000089'

// let rollup: RollupContract
let rollup: RollupContract
let batchPosterManager: Signer
let rollupUser: RollupUserLogic
let rollupAdmin: RollupAdminLogic
let bridge: Bridge
let accounts: Signer[]
let validators: Signer[]
let sequencerInbox: SequencerInbox
let admin: Signer
let sequencer: Signer
let challengeManager: ChallengeManager
let upgradeExecutor: string
// let adminproxy: string

async function getDefaultConfig(
  _confirmPeriodBlocks = confirmationPeriodBlocks
): Promise<ConfigStruct> {
  return {
    baseStake: stakeRequirement,
    chainId: stakeToken,
    chainConfig: '{}', // TODO
    confirmPeriodBlocks: _confirmPeriodBlocks,
    extraChallengeTimeBlocks: extraChallengeTimeBlocks,
    owner: await accounts[0].getAddress(),
    sequencerInboxMaxTimeVariation: {
      delayBlocks: (60 * 60 * 24) / 15,
      futureBlocks: 12,
      delaySeconds: 60 * 60 * 24,
      futureSeconds: 60 * 60,
    },
    stakeToken: stakeToken,
    wasmModuleRoot: wasmModuleRoot,
    loserStakeEscrow: ZERO_ADDR,
    genesisBlockNum: 0,
  }
}

const setup = async () => {
  accounts = await initializeAccounts()
  admin = accounts[0]

  const user = accounts[1]

  const val1 = accounts[2]
  const val2 = accounts[3]
  const val3 = accounts[4]
  const val4 = accounts[5]
  sequencer = accounts[6]
  const batchPosterManager = accounts[7]

  const oneStep0Fac = (await ethers.getContractFactory(
    'OneStepProver0'
  )) as OneStepProver0__factory
  const oneStep0 = await oneStep0Fac.deploy()
  const oneStepMemoryFac = (await ethers.getContractFactory(
    'OneStepProverMemory'
  )) as OneStepProverMemory__factory
  const oneStepMemory = await oneStepMemoryFac.deploy()
  const oneStepMathFac = (await ethers.getContractFactory(
    'OneStepProverMath'
  )) as OneStepProverMath__factory
  const oneStepMath = await oneStepMathFac.deploy()
  const oneStepHostIoFac = (await ethers.getContractFactory(
    'OneStepProverHostIo'
  )) as OneStepProverHostIo__factory
  const oneStepHostIo = await oneStepHostIoFac.deploy()

  const oneStepProofEntryFac = (await ethers.getContractFactory(
    'OneStepProofEntry'
  )) as OneStepProofEntry__factory
  const oneStepProofEntry = await oneStepProofEntryFac.deploy(
    oneStep0.address,
    oneStepMemory.address,
    oneStepMath.address,
    oneStepHostIo.address
  )

  const challengeManagerTemplateFac = (await ethers.getContractFactory(
    'ChallengeManager'
  )) as ChallengeManager__factory
  const challengeManagerTemplate = await challengeManagerTemplateFac.deploy()

  const rollupAdminLogicFac = (await ethers.getContractFactory(
    'RollupAdminLogic'
  )) as RollupAdminLogic__factory
  const rollupAdminLogicTemplate = await rollupAdminLogicFac.deploy()

  const rollupUserLogicFac = (await ethers.getContractFactory(
    'RollupUserLogic'
  )) as RollupUserLogic__factory
  const rollupUserLogicTemplate = await rollupUserLogicFac.deploy()

  const upgradeExecutorLogicFac = await ethers.getContractFactory(
    UpgradeExecutorABI,
    UpgradeExecutorBytecode
  )
  const upgradeExecutorLogic = await upgradeExecutorLogicFac.deploy()

  const ethBridgeFac = (await ethers.getContractFactory(
    'Bridge'
  )) as Bridge__factory
  const ethBridge = await ethBridgeFac.deploy()

  const ethSequencerInboxFac = (await ethers.getContractFactory(
    'SequencerInbox'
  )) as SequencerInbox__factory
  const ethSequencerInbox = await ethSequencerInboxFac.deploy(
    117964,
    dummy4844Reader,
    false
  )

  const ethInboxFac = (await ethers.getContractFactory(
    'Inbox'
  )) as Inbox__factory
  const ethInbox = await ethInboxFac.deploy(117964)

  const ethRollupEventInboxFac = (await ethers.getContractFactory(
    'RollupEventInbox'
  )) as RollupEventInbox__factory
  const ethRollupEventInbox = await ethRollupEventInboxFac.deploy()

  const ethOutboxFac = (await ethers.getContractFactory(
    'Outbox'
  )) as Outbox__factory
  const ethOutbox = await ethOutboxFac.deploy()

  const erc20BridgeFac = (await ethers.getContractFactory(
    'ERC20Bridge'
  )) as ERC20Bridge__factory
  const erc20Bridge = await erc20BridgeFac.deploy()

  const erc20SequencerInboxFac = (await ethers.getContractFactory(
    'SequencerInbox'
  )) as SequencerInbox__factory
  const erc20SequencerInbox = await erc20SequencerInboxFac.deploy(
    117964,
    dummy4844Reader,
    true
  )

  const erc20InboxFac = (await ethers.getContractFactory(
    'ERC20Inbox'
  )) as ERC20Inbox__factory
  const erc20Inbox = await erc20InboxFac.deploy(117964)

  const erc20RollupEventInboxFac = (await ethers.getContractFactory(
    'ERC20RollupEventInbox'
  )) as ERC20RollupEventInbox__factory
  const erc20RollupEventInbox = await erc20RollupEventInboxFac.deploy()

  const erc20OutboxFac = (await ethers.getContractFactory(
    'ERC20Outbox'
  )) as ERC20Outbox__factory
  const erc20Outbox = await erc20OutboxFac.deploy()

  const bridgeCreatorFac = (await ethers.getContractFactory(
    'BridgeCreator'
  )) as BridgeCreator__factory
  const bridgeCreator = await bridgeCreatorFac.deploy(
    {
      bridge: ethBridge.address,
      sequencerInbox: ethSequencerInbox.address,
      inbox: ethInbox.address,
      rollupEventInbox: ethRollupEventInbox.address,
      outbox: ethOutbox.address,
    },
    {
      bridge: erc20Bridge.address,
      sequencerInbox: erc20SequencerInbox.address,
      inbox: erc20Inbox.address,
      rollupEventInbox: erc20RollupEventInbox.address,
      outbox: erc20Outbox.address,
    }
  )

  const rollupCreatorFac = (await ethers.getContractFactory(
    'RollupCreator'
  )) as RollupCreator__factory
  const rollupCreator = await rollupCreatorFac.deploy()

  const deployHelperFac = (await ethers.getContractFactory(
    'DeployHelper'
  )) as DeployHelper__factory
  const deployHelper = await deployHelperFac.deploy()

  await rollupCreator.setTemplates(
    bridgeCreator.address,
    oneStepProofEntry.address,
    challengeManagerTemplate.address,
    rollupAdminLogicTemplate.address,
    rollupUserLogicTemplate.address,
    upgradeExecutorLogic.address,
    ethers.constants.AddressZero,
    ethers.constants.AddressZero,
    deployHelper.address
  )

  const maxFeePerGas = BigNumber.from('1000000000')

  const deployParams = {
    config: await getDefaultConfig(),
    batchPosters: [await sequencer.getAddress()],
    validators: [
      await val1.getAddress(),
      await val2.getAddress(),
      await val3.getAddress(),
      await val4.getAddress(),
    ],
    maxDataSize: 117964,
    nativeToken: ethers.constants.AddressZero,
    deployFactoriesToL2: true,
    maxFeePerGasForRetryables: maxFeePerGas,
    batchPosterManager: await batchPosterManager.getAddress(),
  }

  const response = await rollupCreator.createRollup(deployParams, {
    value: ethers.utils.parseEther('0.2'),
  })

  const rec = await response.wait()

  const rollupCreatedEvent = rollupCreator.interface.parseLog(
    rec.logs[rec.logs.length - 1]
  ).args as RollupCreatedEvent['args']

  const rollupAdmin = rollupAdminLogicFac
    .attach(rollupCreatedEvent.rollupAddress)
    .connect(rollupCreator.signer)
  const rollupUser = rollupUserLogicFac
    .attach(rollupCreatedEvent.rollupAddress)
    .connect(user)
  const bridge = ethBridgeFac.attach(rollupCreatedEvent.bridge).connect(user)

  sequencerInbox = (
    (await ethers.getContractFactory(
      'SequencerInbox'
    )) as SequencerInbox__factory
  ).attach(rollupCreatedEvent.sequencerInbox)

  await sequencerInbox
    .connect(await impersonateAccount(rollupCreatedEvent.upgradeExecutor))
    .setBatchPosterManager(await batchPosterManager.getAddress())

  challengeManager = (
    (await ethers.getContractFactory(
      'ChallengeManager'
    )) as ChallengeManager__factory
  ).attach(await rollupUser.challengeManager())

  return {
    admin,
    user,

    rollupAdmin,
    rollupUser,

    validators: [val1, val2, val3, val4],

    rollupAdminLogicTemplate,
    rollupUserLogicTemplate,
    blockChallengeFactory: challengeManagerTemplateFac,
    rollupEventBridge: await rollupAdmin.rollupEventInbox(),
    outbox: rollupCreatedEvent.outbox,
    sequencerInbox: rollupCreatedEvent.sequencerInbox,
    delayedBridge: rollupCreatedEvent.bridge,
    delayedInbox: rollupCreatedEvent.inboxAddress,
    bridge,
    batchPosterManager,
    upgradeExecutorAddress: rollupCreatedEvent.upgradeExecutor,
    adminproxy: rollupCreatedEvent.adminProxy,
  }
}

async function tryAdvanceChain(blocks: number, time?: number): Promise<void> {
  try {
    if (time === undefined) {
      time = blocks * 12
    }
    if (blocks <= 0) {
      blocks = 1
    }
    if (time > 0) {
      await ethers.provider.send('evm_increaseTime', [time])
    }
    for (let i = 0; i < blocks; i++) {
      await ethers.provider.send('evm_mine', [])
    }
  } catch (e) {
    // EVM mine failed. Try advancing the chain by sending txes if the node
    // is in dev mode and mints blocks when txes are sent
    for (let i = 0; i < blocks; i++) {
      const tx = await accounts[0].sendTransaction({
        value: 0,
        to: await accounts[0].getAddress(),
      })
      await tx.wait()
    }
  }
}

async function advancePastAssertion(
  blockProposed: number,
  confBlocks?: number
): Promise<void> {
  if (confBlocks === undefined) {
    confBlocks = confirmationPeriodBlocks
  }
  const blockProposedBlock = await ethers.provider.getBlock(blockProposed)
  const latestBlock = await ethers.provider.getBlock('latest')
  const passedBlocks = latestBlock.number - blockProposed
  const passedTime = latestBlock.timestamp - blockProposedBlock.timestamp
  await tryAdvanceChain(confBlocks - passedBlocks, confBlocks * 12 - passedTime)
}

function newRandomExecutionState() {
  const blockHash = keccak256(ethers.utils.randomBytes(32))
  const sendRoot = keccak256(ethers.utils.randomBytes(32))
  const machineStatus = 1

  return newExecutionState(blockHash, sendRoot, 1, 0, machineStatus)
}

function newExecutionState(
  blockHash: string,
  sendRoot: string,
  inboxPosition: BigNumberish,
  positionInMessage: BigNumberish,
  machineStatus: BigNumberish
): ExecutionStateStruct {
  return {
    globalState: {
      bytes32Vals: [blockHash, sendRoot],
      u64Vals: [inboxPosition, positionInMessage],
    },
    machineStatus,
  }
}

function newRandomAssertion(
  prevExecutionState: ExecutionStateStruct
): AssertionStruct {
  return {
    beforeState: prevExecutionState,
    afterState: newRandomExecutionState(),
    numBlocks: 10,
  }
}

async function makeSimpleNode(
  rollup: RollupContract,
  sequencerInbox: SequencerInbox,
  parentNode: {
    assertion: { afterState: ExecutionStateStruct }
    nodeNum: number
    nodeHash: BytesLike
    inboxMaxCount: BigNumber
  },
  siblingNode?: Node,
  prevNode?: Node,
  stakeToAdd?: BigNumber
): Promise<{ tx: ContractTransaction; node: Node }> {
  const staker = await rollup.rollup.getStaker(
    await rollup.rollup.signer.getAddress()
  )

  const assertion = newRandomAssertion(parentNode.assertion.afterState)
  const { tx, node, expectedNewNodeHash } = await rollup.stakeOnNewNode(
    sequencerInbox,
    parentNode,
    assertion,
    siblingNode,
    stakeToAdd
  )

  expect(assertionEquals(assertion, node.assertion), 'unexpected assertion').to
    .be.true
  assert.equal(
    node.nodeNum,
    (prevNode || siblingNode || parentNode).nodeNum + 1
  )
  assert.equal(node.nodeHash, expectedNewNodeHash)

  if (stakeToAdd) {
    const stakerAfter = await rollup.rollup.getStaker(
      await rollup.rollup.signer.getAddress()
    )
    expect(stakerAfter.latestStakedNode.toNumber()).to.eq(node.nodeNum)
    expect(stakerAfter.amountStaked.toString()).to.eq(
      staker.amountStaked.add(stakeToAdd).toString()
    )
  }
  return { tx, node }
}

let prevNode: Node
const prevNodes: Node[] = []

function updatePrevNode(node: Node) {
  prevNode = node
  prevNodes.push(node)
}

const _IMPLEMENTATION_PRIMARY_SLOT =
  '0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc'
const _IMPLEMENTATION_SECONDARY_SLOT =
  '0x2b1dbce74324248c222f0ec2d5ed7bd323cfc425b336f0253c5ccfda7265546d'

const getDoubleLogicUUPSTarget = async (
  slot: 'user' | 'admin',
  provider: providers.Provider
): Promise<string> => {
  return `0x${(
    await provider.getStorageAt(
      rollupAdmin.address,
      slot === 'admin'
        ? _IMPLEMENTATION_PRIMARY_SLOT
        : _IMPLEMENTATION_SECONDARY_SLOT
    )
  )
    .substring(26)
    .toLowerCase()}`
}

const impersonateAccount = (address: string) =>
  network.provider
    .request({
      // Fund inboxMock to send transaction
      method: 'hardhat_setBalance',
      params: [address, '0xffffffffffffffffffff'],
    })
    .then(() =>
      network.provider.request({
        method: 'hardhat_impersonateAccount',
        params: [address],
      })
    )
    .then(() => ethers.getSigner(address))

describe('ArbRollup', () => {
  it('should initialize', async function () {
    const {
      rollupAdmin: rollupAdminContract,
      rollupUser: rollupUserContract,
      bridge: bridgeContract,
      admin: adminI,
      validators: validatorsI,
      batchPosterManager: batchPosterManagerI,
      upgradeExecutorAddress,
    } = await setup()
    rollupAdmin = rollupAdminContract
    rollupUser = rollupUserContract
    bridge = bridgeContract
    admin = adminI
    validators = validatorsI
    upgradeExecutor = upgradeExecutorAddress
    // adminproxy = adminproxyAddress
    rollup = new RollupContract(rollupUser.connect(validators[0]))
    batchPosterManager = batchPosterManagerI
  })

  it('should only initialize once', async function () {
    await expect(
      rollupAdmin
        .connect(await impersonateAccount(upgradeExecutor))
        .initialize(await getDefaultConfig(), {
          challengeManager: constants.AddressZero,
          bridge: constants.AddressZero,
          inbox: constants.AddressZero,
          outbox: constants.AddressZero,
          rollupAdminLogic: constants.AddressZero,
          rollupEventInbox: constants.AddressZero,
          rollupUserLogic: constants.AddressZero,
          sequencerInbox: constants.AddressZero,
          validatorUtils: constants.AddressZero,
          validatorWalletCreator: constants.AddressZero,
        })
    ).to.be.revertedWith('Initializable: contract is already initialized')
  })

  it('should place stake on new node', async function () {
    await tryAdvanceChain(minimumAssertionPeriod)

    const initNode: {
      assertion: { afterState: ExecutionStateStruct }
      nodeNum: number
      nodeHash: BytesLike
      inboxMaxCount: BigNumber
    } = {
      assertion: {
        afterState: {
          globalState: {
            bytes32Vals: [zerobytes32, zerobytes32],
            u64Vals: [0, 0],
          },
          machineStatus: MachineStatus.FINISHED,
        },
      },
      inboxMaxCount: BigNumber.from(1),
      nodeHash: zerobytes32,
      nodeNum: 0,
    }

    const stake = await rollup.currentRequiredStake()
    const { node } = await makeSimpleNode(
      rollup,
      sequencerInbox,
      initNode,
      undefined,
      undefined,
      stake
    )
    updatePrevNode(node)
  })

  it('should let a new staker place on existing node', async function () {
    const stake = await rollup.currentRequiredStake()
    await rollupUser
      .connect(validators[2])
      .newStakeOnExistingNode(1, prevNode.nodeHash, { value: stake })
    await rollupUser
      .connect(validators[3])
      .newStakeOnExistingNode(1, prevNode.nodeHash, { value: stake })
  })

  it('should move stake to a new node', async function () {
    await tryAdvanceChain(minimumAssertionPeriod)
    const { node } = await makeSimpleNode(rollup, sequencerInbox, prevNode)
    updatePrevNode(node)
  })

  it('should let the second staker place on the new node', async function () {
    await rollup
      .connect(validators[2])
      .stakeOnExistingNode(2, prevNode.nodeHash)
  })

  it('should confirm node', async function () {
    await tryAdvanceChain(confirmationPeriodBlocks * 2)

    await rollup.confirmNextNode(prevNodes[0])
  })

  it('should confirm next node', async function () {
    await tryAdvanceChain(minimumAssertionPeriod)
    await rollup.confirmNextNode(prevNodes[1])
  })

  let challengedNode: Node
  let validNode: Node
  it('should let the first staker make another node', async function () {
    await tryAdvanceChain(minimumAssertionPeriod)
    const { node } = await makeSimpleNode(rollup, sequencerInbox, prevNode)
    challengedNode = node
    validNode = node
  })

  let challengerNode: Node
  it('should let the second staker make a conflicting node', async function () {
    await tryAdvanceChain(minimumAssertionPeriod)
    const { node } = await makeSimpleNode(
      rollup.connect(validators[2]),
      sequencerInbox,
      prevNode,
      validNode
    )
    challengerNode = node
  })

  it('should fail to confirm first staker node', async function () {
    await advancePastAssertion(challengerNode.proposedBlock)
    await expect(rollup.confirmNextNode(validNode)).to.be.revertedWith(
      'NOT_ALL_STAKED'
    )
  })

  let challengeIndex: number
  let challengeCreatedAt: number
  it('should initiate a challenge', async function () {
    const tx = rollup.createChallenge(
      await validators[0].getAddress(),
      await validators[2].getAddress(),
      challengedNode,
      challengerNode
    )
    const receipt = await (await tx).wait()
    const ev = rollup.rollup.interface.parseLog(
      receipt.logs![receipt.logs!.length - 1]
    )
    expect(ev.name).to.equal('RollupChallengeStarted')

    const parsedEv = ev.args as RollupChallengeStartedEvent['args']
    challengeIndex = parsedEv.challengeIndex.toNumber()
    challengeCreatedAt = receipt.blockNumber
  })

  it('should make a new node', async function () {
    const { node } = await makeSimpleNode(
      rollup,
      sequencerInbox,
      validNode,
      undefined,
      challengerNode
    )
    challengedNode = node
  })

  it('new staker should make a conflicting node', async function () {
    const stake = await rollup.currentRequiredStake()
    await rollup.rollup
      .connect(validators[1])
      .newStakeOnExistingNode(3, validNode.nodeHash, {
        value: stake.add(50),
      })

    const { node } = await makeSimpleNode(
      rollup.connect(validators[1]),
      sequencerInbox,
      validNode,
      challengedNode
    )
    challengerNode = node
  })

  it('timeout should not occur early', async function () {
    const challengeCreatedAtTime = (
      await ethers.provider.getBlock(challengeCreatedAt)
    ).timestamp
    // This is missing the extraChallengeTimeBlocks
    const notQuiteChallengeDuration =
      challengedNode.proposedBlock -
      validNode.proposedBlock +
      confirmationPeriodBlocks
    const elapsedTime =
      (await ethers.provider.getBlock('latest')).timestamp -
      challengeCreatedAtTime
    await tryAdvanceChain(1, notQuiteChallengeDuration - elapsedTime)
    const isTimedOut = await challengeManager
      .connect(validators[0])
      .isTimedOut(challengeIndex)
    expect(isTimedOut).to.be.false
  })

  it('asserter should win via timeout', async function () {
    await tryAdvanceChain(extraChallengeTimeBlocks)
    await challengeManager.connect(validators[0]).timeout(challengeIndex)
  })

  it('confirm first staker node', async function () {
    await rollup.confirmNextNode(validNode)
  })

  it('should reject out of order second node', async function () {
    await rollup.rejectNextNode(stakeToken)
  })

  it('should initiate another challenge', async function () {
    const tx = rollup.createChallenge(
      await validators[0].getAddress(),
      await validators[1].getAddress(),
      challengedNode,
      challengerNode
    )
    const receipt = await (await tx).wait()
    const ev = rollup.rollup.interface.parseLog(
      receipt.logs![receipt.logs!.length - 1]
    )
    expect(ev.name).to.equal('RollupChallengeStarted')
    const parsedEv = ev.args as RollupChallengeStartedEvent['args']
    challengeIndex = parsedEv.challengeIndex.toNumber()

    await expect(
      rollup.rollup.completeChallenge(
        challengeIndex,
        await sequencer.getAddress(),
        await validators[3].getAddress()
      )
    ).to.be.revertedWith('WRONG_SENDER')
  })

  it('challenger should reply in challenge', async function () {
    const seg0 = blockStateHash(
      BigNumber.from(challengerNode.assertion.beforeState.machineStatus),
      globalStateLib.hash(challengerNode.assertion.beforeState.globalState)
    )

    const seg1 = blockStateHash(
      BigNumber.from(challengedNode.assertion.afterState.machineStatus),
      globalStateLib.hash(challengedNode.assertion.afterState.globalState)
    )
    await challengeManager.connect(validators[1]).bisectExecution(
      challengeIndex,
      {
        challengePosition: BigNumber.from(0),
        oldSegments: [seg0, seg1],
        oldSegmentsLength: BigNumber.from(challengedNode.assertion.numBlocks),
        oldSegmentsStart: 0,
      },
      [
        seg0,
        zerobytes32,
        zerobytes32,
        zerobytes32,
        zerobytes32,
        zerobytes32,
        zerobytes32,
        zerobytes32,
        zerobytes32,
        zerobytes32,
        zerobytes32,
      ]
    )
  })

  it('challenger should win via timeout', async function () {
    const challengeDuration =
      confirmationPeriodBlocks +
      extraChallengeTimeBlocks +
      (challengerNode.proposedBlock - validNode.proposedBlock)
    await advancePastAssertion(challengerNode.proposedBlock, challengeDuration)
    await challengeManager.timeout(challengeIndex)
  })

  it('should reject out of order second node', async function () {
    await rollup.rejectNextNode(await validators[1].getAddress())
  })

  it('confirm next node', async function () {
    await tryAdvanceChain(confirmationPeriodBlocks)
    await rollup.confirmNextNode(challengerNode)
  })

  it('allow force refund staker with pending node', async function () {
    await rollupAdmin.connect(await impersonateAccount(upgradeExecutor)).pause()
    await (
      await rollupAdmin
        .connect(await impersonateAccount(upgradeExecutor))
        .forceRefundStaker([await validators[3].getAddress()])
    ).wait()

    await expect(
      rollup.rollup.connect(validators[3]).withdrawStakerFunds()
    ).to.be.revertedWith('PAUSED_AND_ACTIVE')
    // staker can only withdraw if rollup address changed when paused
    await bridge
      .connect(await impersonateAccount(rollup.rollup.address))
      .updateRollupAddress(ethers.constants.AddressZero)

    await (
      await rollup.rollup.connect(validators[3]).withdrawStakerFunds()
    ).wait()
    await rollupAdmin
      .connect(await impersonateAccount(upgradeExecutor))
      .resume()

    // restore rollup address
    await bridge
      .connect(await impersonateAccount(ethers.constants.AddressZero))
      .updateRollupAddress(rollupUser.address)

    const postWithdrawablefunds = await rollup.rollup.withdrawableFunds(
      await validators[3].getAddress()
    )
    expect(postWithdrawablefunds, 'withdrawable funds').to.equal(0)
    const stake = await rollup.rollup.amountStaked(
      await validators[3].getAddress()
    )
    expect(stake, 'amount staked').to.equal(0)
  })

  it('should add and remove stakes correctly', async function () {
    /*
      RollupUser functions that alter stake and their respective Core logic

      user: newStake
      core: createNewStake

      user: addToDeposit
      core: increaseStakeBy

      user: reduceDeposit
      core: reduceStakeTo

      user: returnOldDeposit
      core: withdrawStaker

      user: withdrawStakerFunds
      core: withdrawFunds
    */

    const initialStake = await rollup.rollup.amountStaked(
      await validators[1].getAddress()
    )

    await rollup.connect(validators[1]).reduceDeposit(initialStake)

    await expect(
      rollup.connect(validators[1]).reduceDeposit(initialStake.add(1))
    ).to.be.revertedWith('TOO_LITTLE_STAKE')

    await rollup
      .connect(validators[1])
      .addToDeposit(await validators[1].getAddress(), { value: 5 })

    await rollup.connect(validators[1]).reduceDeposit(5)

    const prevBalance = await validators[1].getBalance()
    const prevWithdrawablefunds = await rollup.rollup.withdrawableFunds(
      await validators[1].getAddress()
    )

    const tx = await rollup.rollup.connect(validators[1]).withdrawStakerFunds()
    const receipt = await tx.wait()
    const gasPaid = receipt.gasUsed.mul(receipt.effectiveGasPrice)

    const postBalance = await validators[1].getBalance()
    const postWithdrawablefunds = await rollup.rollup.withdrawableFunds(
      await validators[1].getAddress()
    )

    expect(postWithdrawablefunds).to.equal(0)
    expect(postBalance.add(gasPaid)).to.equal(
      prevBalance.add(prevWithdrawablefunds)
    )

    // this gets deposit and removes staker
    await rollup.rollup
      .connect(validators[1])
      .returnOldDeposit(await validators[1].getAddress())
    // all stake is now removed
  })

  it('should allow removing zombies', async function () {
    const zombieCount = (
      await rollup.rollup.connect(validators[2]).zombieCount()
    ).toNumber()
    for (let i = 0; i < zombieCount; i++) {
      await rollup.rollup.connect(validators[2]).removeZombie(0, 1024)
    }
  })

  it('should pause the contracts then resume', async function () {
    const prevIsPaused = await rollup.rollup.paused()
    expect(prevIsPaused).to.equal(false)

    await rollupAdmin.connect(await impersonateAccount(upgradeExecutor)).pause()

    const postIsPaused = await rollup.rollup.paused()
    expect(postIsPaused).to.equal(true)

    await expect(
      rollup
        .connect(validators[1])
        .addToDeposit(await validators[1].getAddress(), { value: 5 })
    ).to.be.revertedWith('Pausable: paused')

    await rollupAdmin
      .connect(await impersonateAccount(upgradeExecutor))
      .resume()
  })

  it('should allow admin to alter rollup while paused', async function () {
    const prevLatestConfirmed = await rollup.rollup.latestConfirmed()
    expect(prevLatestConfirmed.toNumber()).to.equal(6)
    // prevNode is prevLatestConfirmed
    prevNode = challengerNode

    const stake = await rollup.currentRequiredStake()

    const { node: node1 } = await makeSimpleNode(
      rollup,
      sequencerInbox,
      prevNode,
      undefined,
      undefined,
      stake
    )
    const node1Num = await rollup.rollup.latestNodeCreated()
    expect(node1Num.toNumber(), 'node1num').to.eq(node1.nodeNum)

    await tryAdvanceChain(minimumAssertionPeriod)

    const { node: node2 } = await makeSimpleNode(
      rollup.connect(validators[2]),
      sequencerInbox,
      prevNode,
      node1,
      undefined,
      stake
    )
    const node2Num = await rollup.rollup.latestNodeCreated()
    expect(node2Num.toNumber(), 'node2num').to.eq(node2.nodeNum)

    const tx = await rollup.createChallenge(
      await validators[0].getAddress(),
      await validators[2].getAddress(),
      node1,
      node2
    )
    const receipt = await tx.wait()
    const ev = rollup.rollup.interface.parseLog(
      receipt.logs![receipt.logs!.length - 1]
    )
    expect(ev.name).to.equal('RollupChallengeStarted')
    const parsedEv = ev.args as RollupChallengeStartedEvent['args']
    challengeIndex = parsedEv.challengeIndex.toNumber()

    expect(
      await challengeManager.currentResponder(challengeIndex),
      'turn challenger'
    ).to.eq(await validators[2].getAddress())

    await expect(
      rollupAdmin
        .connect(await impersonateAccount(upgradeExecutor))
        .forceResolveChallenge(
          [await validators[0].getAddress()],
          [await validators[2].getAddress()]
        ),
      'force resolve'
    ).to.be.revertedWith('Pausable: not paused')

    await expect(
      rollup.createChallenge(
        await validators[0].getAddress(),
        await validators[2].getAddress(),
        node1,
        node2
      ),
      'create challenge'
    ).to.be.revertedWith('IN_CHAL')

    await rollupAdmin.connect(await impersonateAccount(upgradeExecutor)).pause()

    await rollupAdmin
      .connect(await impersonateAccount(upgradeExecutor))
      .forceResolveChallenge(
        [await validators[0].getAddress()],
        [await validators[2].getAddress()]
      )

    // challenge should have been destroyed
    expect(
      await challengeManager.currentResponder(challengeIndex),
      'turn reset'
    ).to.equal(constants.AddressZero)

    const challengeA = await rollupAdmin.currentChallenge(
      await validators[0].getAddress()
    )
    const challengeB = await rollupAdmin.currentChallenge(
      await validators[2].getAddress()
    )

    expect(challengeA).to.equal(ZERO_ADDR)
    expect(challengeB).to.equal(ZERO_ADDR)

    await rollupAdmin
      .connect(await impersonateAccount(upgradeExecutor))
      .forceRefundStaker([
        await validators[0].getAddress(),
        await validators[2].getAddress(),
      ])

    const adminAssertion = newRandomAssertion(prevNode.assertion.afterState)
    const { node: forceCreatedNode1 } = await forceCreateNode(
      rollupAdmin.connect(await impersonateAccount(upgradeExecutor)),
      sequencerInbox,
      prevNode,
      adminAssertion,
      node2
    )
    expect(
      assertionEquals(forceCreatedNode1.assertion, adminAssertion),
      'assertion error'
    ).to.be.true

    const adminNodeNum = await rollup.rollup.latestNodeCreated()
    const midLatestConfirmed = await rollup.rollup.latestConfirmed()
    expect(midLatestConfirmed.toNumber()).to.equal(6)

    expect(adminNodeNum.toNumber()).to.equal(node2Num.toNumber() + 1)

    const adminAssertion2 = newRandomAssertion(prevNode.assertion.afterState)
    const { node: forceCreatedNode2 } = await forceCreateNode(
      rollupAdmin.connect(await impersonateAccount(upgradeExecutor)),
      sequencerInbox,
      prevNode,
      adminAssertion2,
      forceCreatedNode1
    )

    const postLatestCreated = await rollup.rollup.latestNodeCreated()

    await rollupAdmin
      .connect(await impersonateAccount(upgradeExecutor))
      .forceConfirmNode(
        adminNodeNum,
        adminAssertion.afterState.globalState.bytes32Vals[0],
        adminAssertion.afterState.globalState.bytes32Vals[1]
      )

    const postLatestConfirmed = await rollup.rollup.latestConfirmed()
    expect(postLatestCreated).to.equal(adminNodeNum.add(1))
    expect(postLatestConfirmed).to.equal(adminNodeNum)

    await rollupAdmin
      .connect(await impersonateAccount(upgradeExecutor))
      .resume()

    // should create node after resuming

    prevNode = forceCreatedNode1

    await tryAdvanceChain(minimumAssertionPeriod)

    await expect(
      makeSimpleNode(
        rollup.connect(validators[2]),
        sequencerInbox,
        prevNode,
        undefined,
        forceCreatedNode2,
        stake
      )
    ).to.be.revertedWith('STAKER_IS_ZOMBIE')

    await expect(
      makeSimpleNode(rollup.connect(validators[2]), sequencerInbox, prevNode)
    ).to.be.revertedWith('NOT_STAKED')

    await rollup.rollup.connect(validators[2]).removeOldZombies(0)

    await makeSimpleNode(
      rollup.connect(validators[2]),
      sequencerInbox,
      prevNode,
      undefined,
      forceCreatedNode2,
      stake
    )
  })

  it('should initialize a fresh rollup', async function () {
    const {
      rollupAdmin: rollupAdminContract,
      rollupUser: rollupUserContract,
      admin: adminI,
      validators: validatorsI,
      batchPosterManager: batchPosterManagerI,
      upgradeExecutorAddress,
    } = await setup()
    rollupAdmin = rollupAdminContract
    rollupUser = rollupUserContract
    admin = adminI
    validators = validatorsI
    upgradeExecutor = upgradeExecutorAddress
    rollup = new RollupContract(rollupUser.connect(validators[0]))
    batchPosterManager = batchPosterManagerI
  })

  it('should stake on initial node again', async function () {
    await tryAdvanceChain(minimumAssertionPeriod)

    const initNode: {
      assertion: { afterState: ExecutionStateStruct }
      nodeNum: number
      nodeHash: BytesLike
      inboxMaxCount: BigNumber
    } = {
      assertion: {
        afterState: {
          globalState: {
            bytes32Vals: [zerobytes32, zerobytes32],
            u64Vals: [0, 0],
          },
          machineStatus: MachineStatus.FINISHED,
        },
      },
      inboxMaxCount: BigNumber.from(1),
      nodeHash: zerobytes32,
      nodeNum: 0,
    }

    const stake = await rollup.currentRequiredStake()
    const { node } = await makeSimpleNode(
      rollup,
      sequencerInbox,
      initNode,
      undefined,
      undefined,
      stake
    )
    updatePrevNode(node)
  })

  it('should only allow admin to upgrade primary logic', async function () {
    const user = rollupUser.signer

    // store the current implementation addresses
    const proxyPrimaryTarget0 = await getDoubleLogicUUPSTarget(
      'admin',
      user.provider!
    )
    const proxySecondaryTarget0 = await getDoubleLogicUUPSTarget(
      'user',
      user.provider!
    )

    // deploy a new admin logic
    const rollupAdminLogicFac = (await ethers.getContractFactory(
      'RollupAdminLogic'
    )) as RollupAdminLogic__factory
    const newAdminLogicImpl = await rollupAdminLogicFac.deploy()

    // attempt to upgrade as user, should revert
    await expect(rollupAdmin.connect(user).upgradeTo(newAdminLogicImpl.address))
      .to.be.reverted
    // upgrade as admin
    await expect(
      rollupAdmin
        .connect(await impersonateAccount(upgradeExecutor))
        .upgradeTo(newAdminLogicImpl.address)
    ).to.emit(rollupAdmin, 'Upgraded')

    // check the new implementation address is set
    const proxyPrimaryTarget = await getDoubleLogicUUPSTarget(
      'admin',
      user.provider!
    )
    await expect(proxyPrimaryTarget).to.not.eq(proxyPrimaryTarget0)
    await expect(proxyPrimaryTarget).to.eq(
      newAdminLogicImpl.address.toLowerCase()
    )

    // check the other implementation address is unchanged
    const proxySecondaryTarget = await getDoubleLogicUUPSTarget(
      'user',
      user.provider!
    )
    await expect(proxySecondaryTarget).to.eq(proxySecondaryTarget0)
  })

  it('should only allow admin to upgrade secondary logic', async function () {
    const user = rollupUser.signer

    // store the current implementation addresses
    const proxyPrimaryTarget0 = await getDoubleLogicUUPSTarget(
      'admin',
      user.provider!
    )
    const proxySecondaryTarget0 = await getDoubleLogicUUPSTarget(
      'user',
      user.provider!
    )

    // deploy a new user logic
    const rollupUserLogicFac = (await ethers.getContractFactory(
      'RollupUserLogic'
    )) as RollupUserLogic__factory
    const newUserLogicImpl = await rollupUserLogicFac.deploy()

    // attempt to upgrade as user, should revert
    await expect(
      rollupAdmin.connect(user).upgradeSecondaryTo(newUserLogicImpl.address)
    ).to.be.reverted
    // upgrade as admin
    await expect(
      rollupAdmin
        .connect(await impersonateAccount(upgradeExecutor))
        .upgradeSecondaryTo(newUserLogicImpl.address)
    ).to.emit(rollupAdmin, 'UpgradedSecondary')

    // check the new implementation address is set
    const proxySecondaryTarget = await getDoubleLogicUUPSTarget(
      'user',
      user.provider!
    )
    await expect(proxySecondaryTarget).to.not.eq(proxySecondaryTarget0)
    await expect(proxySecondaryTarget).to.eq(
      newUserLogicImpl.address.toLowerCase()
    )

    // check the other implementation address is unchanged
    const proxyPrimaryTarget = await getDoubleLogicUUPSTarget(
      'admin',
      user.provider!
    )
    await expect(proxyPrimaryTarget).to.eq(proxyPrimaryTarget0)
  })

  it('should allow admin to upgrade primary logic and call', async function () {
    const rollupAdminLogicFac = (await ethers.getContractFactory(
      'RollupAdminLogic'
    )) as RollupAdminLogic__factory
    const newAdminLogicImpl = await rollupAdminLogicFac.deploy()
    // first pause the contract so we can unpause after upgrade
    await rollupAdmin.connect(await impersonateAccount(upgradeExecutor)).pause()
    // 0x046f7da2 - resume()
    await expect(
      rollupAdmin
        .connect(await impersonateAccount(upgradeExecutor))
        .upgradeToAndCall(newAdminLogicImpl.address, '0x046f7da2')
    ).to.emit(rollupAdmin, 'Unpaused')
  })

  it('should allow admin to upgrade secondary logic and call', async function () {
    const rollupUserLogicFac = (await ethers.getContractFactory(
      'RollupUserLogic'
    )) as RollupUserLogic__factory
    const newUserLogicImpl = await rollupUserLogicFac.deploy()
    // this call should revert since the user logic don't have a fallback
    await expect(
      rollupAdmin
        .connect(await impersonateAccount(upgradeExecutor))
        .upgradeSecondaryToAndCall(newUserLogicImpl.address, '0x')
    ).to.revertedWith('Address: low-level delegate call failed')
    // 0x8da5cb5b - owner() (some random function that will not revert)
    await expect(
      rollupAdmin
        .connect(await impersonateAccount(upgradeExecutor))
        .upgradeSecondaryToAndCall(newUserLogicImpl.address, '0x8da5cb5b')
    ).to.emit(rollupAdmin, 'UpgradedSecondary')
  })

  it('should fail upgrade to unsafe primary logic', async function () {
    const rollupUserLogicFac = (await ethers.getContractFactory(
      'RollupUserLogic'
    )) as RollupUserLogic__factory
    const newUserLogicImpl = await rollupUserLogicFac.deploy()
    await expect(
      rollupAdmin
        .connect(await impersonateAccount(upgradeExecutor))
        .upgradeTo(newUserLogicImpl.address)
    ).to.revertedWith('ERC1967Upgrade: unsupported proxiableUUID')
  })

  it('should fail upgrade to unsafe secondary logic', async function () {
    const rollupAdminLogicFac = (await ethers.getContractFactory(
      'RollupAdminLogic'
    )) as RollupAdminLogic__factory
    const newAdminLogicImpl = await rollupAdminLogicFac.deploy()
    await expect(
      rollupAdmin
        .connect(await impersonateAccount(upgradeExecutor))
        .upgradeSecondaryTo(newAdminLogicImpl.address)
    ).to.revertedWith('ERC1967Upgrade: unsupported secondary proxiableUUID')
  })

  it('should fail upgrade to proxy primary logic', async function () {
    await expect(
      rollupAdmin
        .connect(await impersonateAccount(upgradeExecutor))
        .upgradeTo(rollupAdmin.address)
    ).to.revertedWith('ERC1967Upgrade: new implementation is not UUPS')
  })

  it('should fail upgrade to proxy secondary logic', async function () {
    await expect(
      rollupAdmin
        .connect(await impersonateAccount(upgradeExecutor))
        .upgradeSecondaryTo(rollupAdmin.address)
    ).to.revertedWith(
      'ERC1967Upgrade: new secondary implementation is not UUPS'
    )
  })

  it('should fail to init rollupAdminLogic without proxy', async function () {
    const user = rollupUser.signer
    const rollupAdminLogicFac = (await ethers.getContractFactory(
      'RollupAdminLogic'
    )) as RollupAdminLogic__factory
    const proxyPrimaryTarget = await getDoubleLogicUUPSTarget(
      'admin',
      user.provider!
    )
    const proxyPrimaryImpl = rollupAdminLogicFac.attach(proxyPrimaryTarget)
    await expect(
      proxyPrimaryImpl.initialize(await getDefaultConfig(), {
        challengeManager: constants.AddressZero,
        bridge: constants.AddressZero,
        inbox: constants.AddressZero,
        outbox: constants.AddressZero,
        rollupAdminLogic: constants.AddressZero,
        rollupEventInbox: constants.AddressZero,
        rollupUserLogic: constants.AddressZero,
        sequencerInbox: constants.AddressZero,
        validatorUtils: constants.AddressZero,
        validatorWalletCreator: constants.AddressZero,
      })
    ).to.be.revertedWith('Function must be called through delegatecall')
  })

  it('should fail to init rollupUserLogic without proxy', async function () {
    const user = rollupUser.signer
    const rollupUserLogicFac = (await ethers.getContractFactory(
      'RollupUserLogic'
    )) as RollupUserLogic__factory
    const proxySecondaryTarget = await getDoubleLogicUUPSTarget(
      'user',
      user.provider!
    )
    const proxySecondaryImpl = rollupUserLogicFac.attach(proxySecondaryTarget)
    await expect(
      proxySecondaryImpl.interface.functions['initialize(address)']
        .stateMutability
    ).to.eq('view')
  })

  it('can set is sequencer', async function () {
    const testAddress = await accounts[9].getAddress()
    expect(await sequencerInbox.isSequencer(testAddress)).to.be.false
    await expect(sequencerInbox.setIsSequencer(testAddress, true))
      .to.revertedWith(`NotBatchPosterManager`)
      .withArgs(await sequencerInbox.signer.getAddress())
    expect(await sequencerInbox.isSequencer(testAddress)).to.be.false

    await (
      await sequencerInbox
        .connect(batchPosterManager)
        .setIsSequencer(testAddress, true)
    ).wait()

    expect(await sequencerInbox.isSequencer(testAddress)).to.be.true

    await (
      await sequencerInbox
        .connect(batchPosterManager)
        .setIsSequencer(testAddress, false)
    ).wait()

    expect(await sequencerInbox.isSequencer(testAddress)).to.be.false
  })

  it('can set a batch poster', async function () {
    const testAddress = await accounts[9].getAddress()
    expect(await sequencerInbox.isBatchPoster(testAddress)).to.be.false
    await expect(sequencerInbox.setIsBatchPoster(testAddress, true))
      .to.revertedWith(`NotBatchPosterManager`)
      .withArgs(await sequencerInbox.signer.getAddress())
    expect(await sequencerInbox.isBatchPoster(testAddress)).to.be.false

    await (
      await sequencerInbox
        .connect(batchPosterManager)
        .setIsBatchPoster(testAddress, true)
    ).wait()

    expect(await sequencerInbox.isBatchPoster(testAddress)).to.be.true

    await (
      await sequencerInbox
        .connect(batchPosterManager)
        .setIsBatchPoster(testAddress, false)
    ).wait()

    expect(await sequencerInbox.isBatchPoster(testAddress)).to.be.false
  })

  it('can set batch poster manager', async function () {
    const testManager = await accounts[8].getAddress()
    expect(await sequencerInbox.batchPosterManager()).to.eq(
      await batchPosterManager.getAddress()
    )
    await expect(
      sequencerInbox.connect(accounts[8]).setBatchPosterManager(testManager)
    )
      .to.revertedWith('NotOwner')
      .withArgs(testManager, upgradeExecutor)
    expect(await sequencerInbox.batchPosterManager()).to.eq(
      await batchPosterManager.getAddress()
    )

    await (
      await sequencerInbox
        .connect(await impersonateAccount(upgradeExecutor))
        .setBatchPosterManager(testManager)
    ).wait()

    expect(await sequencerInbox.batchPosterManager()).to.eq(testManager)
  })

  it('should fail the chainid fork check', async function () {
    await expect(sequencerInbox.removeDelayAfterFork()).to.revertedWith(
      'NotForked'
    )
  })

  it('should fail the batch poster check', async function () {
    await expect(
      sequencerInbox.addSequencerL2Batch(
        0,
        '0x',
        0,
        ethers.constants.AddressZero,
        0,
        0
      )
    ).to.revertedWith('NotBatchPoster')
  })

  it('should fail the onlyValidator check', async function () {
    await expect(rollupUser.withdrawStakerFunds()).to.revertedWith(
      'NOT_VALIDATOR'
    )
  })

  it('should fail to call removeWhitelistAfterFork', async function () {
    await expect(rollupUser.removeWhitelistAfterFork()).to.revertedWith(
      'CHAIN_ID_NOT_CHANGED'
    )
  })

  it('should fail to call removeWhitelistAfterValidatorAfk', async function () {
    await expect(rollupUser.removeWhitelistAfterValidatorAfk()).to.revertedWith(
      'VALIDATOR_NOT_AFK'
    )
  })
})

const fastConfirmerAddr = '0x000000000000000000000000000000000000fa51'
describe.only('ArbRollupFastConfirm', () => {
  it('should initialize', async function () {
    const {
      rollupAdmin: rollupAdminContract,
      rollupUser: rollupUserContract,
      bridge: bridgeContract,
      admin: adminI,
      validators: validatorsI,
      batchPosterManager: batchPosterManagerI,
      upgradeExecutorAddress,
    } = await setup()
    rollupAdmin = rollupAdminContract
    rollupUser = rollupUserContract
    bridge = bridgeContract
    admin = adminI
    validators = validatorsI
    upgradeExecutor = upgradeExecutorAddress
    // adminproxy = adminproxyAddress
    rollup = new RollupContract(rollupUser.connect(validators[0]))
    batchPosterManager = batchPosterManagerI
  })
  it('should set fast confirmer', async function () {
    await (
      await rollupAdmin
        .connect(await impersonateAccount(upgradeExecutor))
        .setAnyTrustFastConfirmer(fastConfirmerAddr)
    ).wait()
    await expect(await rollup.rollup.anyTrustFastConfirmer()).to.eq(
      fastConfirmerAddr
    )
  })
  it('should place stake on new node', async function () {
    await tryAdvanceChain(minimumAssertionPeriod)

    const initNode: {
      assertion: { afterState: ExecutionStateStruct }
      nodeNum: number
      nodeHash: BytesLike
      inboxMaxCount: BigNumber
    } = {
      assertion: {
        afterState: {
          globalState: {
            bytes32Vals: [zerobytes32, zerobytes32],
            u64Vals: [0, 0],
          },
          machineStatus: MachineStatus.FINISHED,
        },
      },
      inboxMaxCount: BigNumber.from(1),
      nodeHash: zerobytes32,
      nodeNum: 0,
    }

    const stake = await rollup.currentRequiredStake()
    const { node } = await makeSimpleNode(
      rollup,
      sequencerInbox,
      initNode,
      undefined,
      undefined,
      stake
    )
    updatePrevNode(node)
  })
  it('should fail to confirm before deadline', async function () {
    await expect(rollup.confirmNextNode(prevNodes[0])).to.be.revertedWith(
      'BEFORE_DEADLINE'
    )
  })
  it('should fail to fast confirm if not fast confirmer', async function () {
    await expect(
      rollup.fastConfirmNextNode(prevNodes[0], ethers.constants.HashZero)
    ).to.be.revertedWith('NFC')
  })
  it('should fail to fast confirm if not validator', async function () {
    await expect(
      rollup
        .connect(await impersonateAccount(fastConfirmerAddr))
        .fastConfirmNextNode(prevNodes[0], prevNodes[0].nodeHash)
    ).to.be.revertedWith('NOT_VALIDATOR')
  })
  it('should be able to set fast confirmer as validator', async function () {
    await (
      await rollupAdmin
        .connect(await impersonateAccount(upgradeExecutor))
        .setValidator([fastConfirmerAddr], [true])
    ).wait()
  })
  it('should fail to fast confirm if wrong nodehash', async function () {
    await expect(
      rollup
        .connect(await impersonateAccount(fastConfirmerAddr))
        .fastConfirmNextNode(prevNodes[0], ethers.constants.HashZero)
    ).to.be.revertedWith('WH')
  })
  it('should fast confirm', async function () {
    await rollup
      .connect(await impersonateAccount(fastConfirmerAddr))
      .fastConfirmNextNode(prevNodes[0], prevNodes[0].nodeHash)
  })
})
