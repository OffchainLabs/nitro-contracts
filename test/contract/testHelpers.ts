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
import { BigNumber } from '@ethersproject/bignumber'
import { Block, TransactionReceipt } from '@ethersproject/providers'
import { expect } from 'chai'
import {
  Bridge,
  Bridge__factory,
  Inbox,
  Inbox__factory,
  MessageTester,
  RollupMock__factory,
  SequencerInbox,
  SequencerInbox__factory,
  TransparentUpgradeableProxy__factory,
} from '../../build/types'
import { applyAlias, initializeAccounts } from './utils'
import { Event } from '@ethersproject/contracts'
import { Interface } from '@ethersproject/abi'
import {
  BridgeInterface,
  MessageDeliveredEvent,
  SequencerBatchDeliveredEvent,
} from '../../build/types/src/bridge/Bridge'
import { Signer } from 'ethers'
import { Toolkit4844 } from './toolkit4844'
import {
  DelayedMsg,
  DelayedMsgDelivered,
  MaxTimeVariation,
  DelayConfig,
  ReplenishRate,
} from './types'
import { solidityPack } from 'ethers/lib/utils'
import {
  InboxInterface,
  InboxMessageDeliveredEvent,
} from '../../build/types/src/bridge/Inbox'

export const mineBlocks = async (count: number, timeDiffPerBlock = 14) => {
  const block = (await network.provider.send('eth_getBlockByNumber', [
    'latest',
    false,
  ])) as Block
  let timestamp = BigNumber.from(block.timestamp).toNumber()
  for (let i = 0; i < count; i++) {
    timestamp = timestamp + timeDiffPerBlock
    await network.provider.send('evm_mine', [timestamp])
  }
}

export const getMessageDeliveredEvents = (receipt: TransactionReceipt) => {
  const bridgeInterface = Bridge__factory.createInterface()
  return findMatchingLogs<BridgeInterface, MessageDeliveredEvent>(
    receipt,
    bridgeInterface,
    i => i.getEventTopic(i.getEvent('MessageDelivered'))
  )
}

export const getInboxMessageDeliveredEvents = (receipt: TransactionReceipt) => {
  const inboxInterface = Inbox__factory.createInterface()
  return findMatchingLogs<InboxInterface, InboxMessageDeliveredEvent>(
    receipt,
    inboxInterface,
    i => i.getEventTopic(i.getEvent('InboxMessageDelivered'))
  )
}

const findMatchingLogs = <TInterface extends Interface, TEvent extends Event>(
  receipt: TransactionReceipt,
  iFace: TInterface,
  eventTopicGen: (i: TInterface) => string
): TEvent['args'][] => {
  const logs = receipt.logs.filter(
    log => log.topics[0] === eventTopicGen(iFace)
  )
  return logs.map(l => iFace.parseLog(l).args as TEvent['args'])
}

export const getBatchSpendingReport = (
  receipt: TransactionReceipt
): DelayedMsgDelivered => {
  const res = getMessageDeliveredEvents(receipt)
  return {
    delayedMessage: {
      header: {
        kind: res[0].kind,
        sender: res[0].sender,
        blockNumber: receipt.blockNumber,
        timestamp: Number(res[0].timestamp),
        totalDelayedMessagesRead: Number(res[0].messageIndex),
        baseFee: Number(res[0].baseFeeL1),
        messageDataHash: res[0].messageDataHash,
      },
      //spendingReportMsg = abi.encodePacked(block.timestamp, batchPoster, dataHash, seqMessageIndex, block.basefee  );
      messageData: solidityPack(
        ['uint256', 'address', 'bytes32', 'uint256', 'uint256'],
        [
          res[0].timestamp,
          res[0].sender,
          res[0].messageDataHash,
          res[0].messageIndex,
          res[0].baseFeeL1,
        ]
      ),
    },
    delayedAcc: res[0].beforeInboxAcc,
    delayedCount: Number(res[0].messageIndex),
  }
}

export const sendDelayedTx = async (
  sender: Signer,
  inbox: Inbox,
  bridge: Bridge,
  messageTester: MessageTester,
  l2Gas: number,
  l2GasPrice: number,
  nonce: number,
  destAddr: string,
  amount: BigNumber,
  data: string
) => {
  const countBefore = (
    await bridge.functions.delayedMessageCount()
  )[0].toNumber()
  const sendUnsignedTx = await inbox
    .connect(sender)
    .sendUnsignedTransaction(l2Gas, l2GasPrice, nonce, destAddr, amount, data)
  const sendUnsignedTxReceipt = await sendUnsignedTx.wait()

  const countAfter = (
    await bridge.functions.delayedMessageCount()
  )[0].toNumber()
  expect(countAfter, 'Unexpected inbox count').to.eq(countBefore + 1)

  const senderAddr = applyAlias(await sender.getAddress())

  const messageDeliveredEvent = getMessageDeliveredEvents(
    sendUnsignedTxReceipt
  )[0]
  const l1BlockNumber = sendUnsignedTxReceipt.blockNumber
  const blockL1 = await sender.provider!.getBlock(l1BlockNumber)
  const baseFeeL1 = blockL1.baseFeePerGas!.toNumber()
  const l1BlockTimestamp = blockL1.timestamp
  const delayedAcc = await bridge.delayedInboxAccs(countBefore)

  // need to hex pad the address
  const messageDataHash = ethers.utils.solidityKeccak256(
    ['uint8', 'uint256', 'uint256', 'uint256', 'uint256', 'uint256', 'bytes'],
    [
      0,
      l2Gas,
      l2GasPrice,
      nonce,
      ethers.utils.hexZeroPad(destAddr, 32),
      amount,
      data,
    ]
  )
  expect(
    messageDeliveredEvent.messageDataHash,
    'Incorrect messageDataHash'
  ).to.eq(messageDataHash)

  const messageHash = (
    await messageTester.functions.messageHash(
      3,
      senderAddr,
      l1BlockNumber,
      l1BlockTimestamp,
      countBefore,
      baseFeeL1,
      messageDataHash
    )
  )[0]

  const prevAccumulator = messageDeliveredEvent.beforeInboxAcc
  expect(prevAccumulator, 'Incorrect prev accumulator').to.eq(
    countBefore === 0
      ? ethers.utils.hexZeroPad('0x', 32)
      : await bridge.delayedInboxAccs(countBefore - 1)
  )

  const nextAcc = (
    await messageTester.functions.accumulateInboxMessage(
      prevAccumulator,
      messageHash
    )
  )[0]

  expect(delayedAcc, 'Incorrect delayed acc').to.eq(nextAcc)

  const msgData = ethers.utils.solidityPack(
    ['uint8', 'uint256', 'uint256', 'uint256', 'uint256', 'uint256', 'bytes'],
    [
      0,
      l2Gas,
      l2GasPrice,
      nonce,
      ethers.utils.hexZeroPad(destAddr, 32),
      amount,
      data,
    ]
  )

  const delayedMsg: DelayedMsg = {
    header: {
      kind: 3,
      sender: senderAddr,
      blockNumber: l1BlockNumber,
      timestamp: l1BlockTimestamp,
      totalDelayedMessagesRead: countBefore,
      baseFee: baseFeeL1,
      messageDataHash: messageDataHash,
    },
    messageData: msgData,
  }

  return {
    countBefore,
    delayedMsg,
    prevAccumulator,
    inboxAccountLength: countAfter,
  }
}

export const forceIncludeMessages = async (
  sequencerInbox: SequencerInbox,
  newTotalDelayedMessagesRead: number,
  delayedMessage: DelayedMsg,
  expectedErrorType?: string
) => {
  const inboxLengthBefore = (await sequencerInbox.batchCount()).toNumber()

  const forceInclusionTx = sequencerInbox.forceInclusion(
    newTotalDelayedMessagesRead,
    delayedMessage.header.kind,
    [delayedMessage.header.blockNumber, delayedMessage.header.timestamp],
    delayedMessage.header.baseFee,
    delayedMessage.header.sender,
    delayedMessage.header.messageDataHash
  )
  if (expectedErrorType) {
    await expect(forceInclusionTx).to.be.revertedWith(
      `reverted with custom error '${expectedErrorType}()'`
    )
  } else {
    await (await forceInclusionTx).wait()

    const totalDelayedMessagsReadAfter = (
      await sequencerInbox.totalDelayedMessagesRead()
    ).toNumber()
    expect(
      totalDelayedMessagsReadAfter,
      'Incorrect totalDelayedMessagesRead after.'
    ).to.eq(newTotalDelayedMessagesRead)
    const inboxLengthAfter = (await sequencerInbox.batchCount()).toNumber()
    expect(inboxLengthAfter - inboxLengthBefore, 'Inbox not incremented').to.eq(
      1
    )
  }
}

const maxVar: MaxTimeVariation = {
  delayBlocks: (60 * 60 * 24) / 12,
  delaySeconds: 60 * 60 * 24,
  futureBlocks: 32 * 2,
  futureSeconds: 12 * 32 * 2,
}

const rateRepl: ReplenishRate = {
  blocksPerPeriod: 1,
  periodBlocks: 14,
  secondsPerPeriod: 1,
  periodSeconds: 12,
}

const delayConfig: DelayConfig = {
  thresholdBlocks: BigNumber.from((2 * 60 * 60) / 12),
  thresholdSeconds: BigNumber.from(2 * 60 * 60),
  maxBufferBlocks: maxVar.delayBlocks * 2,
  maxBufferSeconds: maxVar.delaySeconds * 2,
}

const configNotDelayBufferable: DelayConfig = {
  thresholdBlocks: BigNumber.from(2).pow(64).sub(1),
  thresholdSeconds: BigNumber.from(2).pow(64).sub(1),
  maxBufferBlocks: maxVar.delayBlocks * 2,
  maxBufferSeconds: maxVar.delaySeconds * 2,
}

export const getSequencerBatchDeliveredEvents = (
  receipt: TransactionReceipt
) => {
  const bridgeInterface = Bridge__factory.createInterface()
  return findMatchingLogs<BridgeInterface, SequencerBatchDeliveredEvent>(
    receipt,
    bridgeInterface,
    i => i.getEventTopic(i.getEvent('SequencerBatchDelivered'))
  )
}

export const setupSequencerInbox = async (
  isDelayBufferable = false,
  max: MaxTimeVariation = maxVar,
  rate: ReplenishRate = rateRepl,
  config: DelayConfig = delayConfig
) => {
  const accounts = await initializeAccounts()
  const admin = accounts[0]
  const adminAddr = await admin.getAddress()
  const user = accounts[1]
  const rollupOwner = accounts[2]
  const batchPoster = accounts[3]
  const batchPosterManager = accounts[4]

  const rollupMockFac = (await ethers.getContractFactory(
    'RollupMock'
  )) as RollupMock__factory
  const rollup = await rollupMockFac.deploy(await rollupOwner.getAddress())
  const inboxFac = (await ethers.getContractFactory('Inbox')) as Inbox__factory
  const inboxTemplate = await inboxFac.deploy(117964)
  const bridgeFac = (await ethers.getContractFactory(
    'Bridge'
  )) as Bridge__factory
  const bridgeTemplate = await bridgeFac.deploy()
  const transparentUpgradeableProxyFac = (await ethers.getContractFactory(
    'TransparentUpgradeableProxy'
  )) as TransparentUpgradeableProxy__factory

  const bridgeProxy = await transparentUpgradeableProxyFac.deploy(
    bridgeTemplate.address,
    adminAddr,
    '0x'
  )

  const inboxProxy = await transparentUpgradeableProxyFac.deploy(
    inboxTemplate.address,
    adminAddr,
    '0x'
  )
  const bridge = await bridgeFac.attach(bridgeProxy.address).connect(user)
  const bridgeAdmin = await bridgeFac
    .attach(bridgeProxy.address)
    .connect(rollupOwner)
  await bridge.initialize(rollup.address)

  const reader4844 = await Toolkit4844.deployReader4844(admin)

  const sequencerInboxFac = (await ethers.getContractFactory(
    'SequencerInbox'
  )) as SequencerInbox__factory
  const sequencerInbox = await sequencerInboxFac.deploy(
    bridgeProxy.address,
    max,
    rate,
    isDelayBufferable ? config : configNotDelayBufferable,
    117964,
    reader4844.address,
    false
  )

  await (
    await sequencerInbox
      .connect(rollupOwner)
      .setIsBatchPoster(await batchPoster.getAddress(), true)
  ).wait()

  await (
    await sequencerInbox
      .connect(rollupOwner)
      .setBatchPosterManager(await batchPosterManager.getAddress())
  ).wait()

  const inbox = await inboxFac.attach(inboxProxy.address).connect(user)

  await inbox.initialize(bridgeProxy.address, sequencerInbox.address)

  await bridgeAdmin.setDelayedInbox(inbox.address, true)
  await bridgeAdmin.setSequencerInbox(sequencerInbox.address)

  await (
    await sequencerInbox
      .connect(rollupOwner)
      .setIsBatchPoster(await batchPoster.getAddress(), true)
  ).wait()

  const messageTester = (await (
    await ethers.getContractFactory('MessageTester')
  ).deploy()) as MessageTester

  return {
    user,
    bridge: bridge,
    inbox: inbox,
    sequencerInbox: sequencerInbox as SequencerInbox,
    messageTester,
    inboxProxy,
    inboxTemplate,
    batchPoster,
    bridgeProxy,
    rollup,
    rollupOwner,
  }
}
