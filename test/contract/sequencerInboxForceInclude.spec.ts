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
  SequencerInboxOpt,
  SequencerInbox__factory,
  TransparentUpgradeableProxy__factory,
} from '../../build/types'
import { applyAlias, initializeAccounts } from './utils'
import { Event } from '@ethersproject/contracts'
import { Interface } from '@ethersproject/abi'
import {
  BridgeInterface,
  MessageDeliveredEvent,
} from '../../build/types/src/bridge/Bridge'
import { Signer } from 'ethers'
import { data } from './batchData.json'
import { solidityKeccak256 } from 'ethers/lib/utils'
import { SequencerBatchDeliveredEvent } from '../../build/types/src/bridge/AbsBridge'

const mineBlocks = async (count: number, timeDiffPerBlock = 14) => {
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

describe('SequencerInboxForceInclude', async () => {
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

  const getMessageDeliveredEvents = (receipt: TransactionReceipt) => {
    const bridgeInterface = Bridge__factory.createInterface()
    return findMatchingLogs<BridgeInterface, MessageDeliveredEvent>(
      receipt,
      bridgeInterface,
      i => i.getEventTopic(i.getEvent('MessageDelivered'))
    )
  }

  const sendDelayedTx = async (
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

    return {
      countBefore,
      baseFeeL1: baseFeeL1,
      messageDataHash,
      deliveredMessageEvent: messageDeliveredEvent,
      l1BlockNumber,
      l1BlockTimestamp,
      delayedAcc,
      l2Gas,
      l2GasPrice,
      nonce,
      destAddr,
      amount,
      data,
      senderAddr,
      inboxAccountLength: countAfter,
    }
  }

  const forceIncludeMessages = async (
    sequencerInbox: SequencerInbox,
    newTotalDelayedMessagesRead: number,
    kind: number,
    l1blockNumber: number,
    l1Timestamp: number,
    l1BaseFee: number,
    senderAddr: string,
    messageDataHash: string,
    expectedErrorType?: string
  ) => {
    const inboxLengthBefore = (await sequencerInbox.batchCount()).toNumber()

    const forceInclusionTx = sequencerInbox.forceInclusion(
      newTotalDelayedMessagesRead,
      kind,
      [l1blockNumber, l1Timestamp],
      l1BaseFee,
      senderAddr,
      messageDataHash
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
      expect(
        inboxLengthAfter - inboxLengthBefore,
        'Inbox not incremented'
      ).to.eq(1)
    }
  }

  const setupSequencerInbox = async (
    maxDelayBlocks = 10,
    maxDelayTime = 0,
    deployOpt = false
  ) => {
    const accounts = await initializeAccounts()
    const admin = accounts[0]
    const adminAddr = await admin.getAddress()
    const user = accounts[1]
    const rollupOwner = accounts[2]
    const batchPoster = accounts[3]

    const rollupMockFac = (await ethers.getContractFactory(
      'RollupMock'
    )) as RollupMock__factory
    const rollup = await rollupMockFac.deploy(await rollupOwner.getAddress())
    const inboxFac = (await ethers.getContractFactory(
      'Inbox'
    )) as Inbox__factory
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

    const sequencerInboxFac = (await ethers.getContractFactory(
      deployOpt ? 'SequencerInboxOpt' : 'SequencerInbox'
    )) as SequencerInbox__factory
    const sequencerInbox = await sequencerInboxFac.deploy(
      bridgeProxy.address,
      {
        delayBlocks: maxDelayBlocks,
        delaySeconds: maxDelayTime,
        futureBlocks: 10,
        futureSeconds: 3000,
      },
      117964
    )

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
      bridgeProxy,
      rollup,
      rollupOwner,
      batchPoster,
    }
  }

  it.only('can add batch', async () => {
    const { user, inbox, bridge, messageTester, sequencerInbox, batchPoster } =
      await setupSequencerInbox()

    const setupOpt = await setupSequencerInbox(10, 0, true)

    // const data = '0x0242'

    await sendDelayedTx(
      user,
      inbox,
      bridge,
      messageTester,
      1000000,
      21000000000,
      0,
      await user.getAddress(),
      BigNumber.from(10),
      '0x1010'
    )
    const {
      senderAddr,
      l1BlockNumber,
      l1BlockTimestamp,
      countBefore,
      baseFeeL1,
      messageDataHash,
    } = await sendDelayedTx(
      setupOpt.user,
      setupOpt.inbox,
      setupOpt.bridge,
      setupOpt.messageTester,
      1000000,
      21000000000,
      0,
      await setupOpt.user.getAddress(),
      BigNumber.from(10),
      '0x1011'
    )

    // const maxTimeVariation = await sequencerInbox.maxTimeVariation()
    // await mineBlocks(maxTimeVariation.delayBlocks.toNumber())

    const messagesRead = await bridge.delayedMessageCount()
    const seqReportedMessageSubCount =
      await bridge.sequencerReportedSubMessageCount()
    const res1 = await (
      await sequencerInbox
        .connect(batchPoster)
        .addSequencerL2BatchFromOrigin(
          0,
          data,
          messagesRead,
          ethers.constants.AddressZero,
          seqReportedMessageSubCount,
          seqReportedMessageSubCount.add(10),
          { gasLimit: 10000000 }
        )
    ).wait()
    await sendDelayedTx(
      user,
      inbox,
      bridge,
      messageTester,
      1000000,
      21000000000,
      0,
      await user.getAddress(),
      BigNumber.from(10),
      '0x1010'
    )
    const messagesReadAdd1 = await bridge.delayedMessageCount()
    const seqReportedMessageSubCountAdd1 =
      await bridge.sequencerReportedSubMessageCount()
    const res11 = await (
      await sequencerInbox
        .connect(batchPoster)
        .addSequencerL2BatchFromOrigin(
          1,
          data,
          messagesReadAdd1,
          ethers.constants.AddressZero,
          seqReportedMessageSubCountAdd1,
          seqReportedMessageSubCountAdd1.add(10),
          { gasLimit: 10000000 }
        )
    ).wait()

    const messagesReadOpt = await setupOpt.bridge.delayedMessageCount()
    const sequencerMessageCount = (
      await setupOpt.bridge.sequencerMessageCount()
    ).toNumber()

    const beforeAccBeforeAcc =
      sequencerMessageCount == 0
        ? ethers.constants.HashZero
        : await setupOpt.bridge.sequencerInboxAccs(sequencerMessageCount - 1)
    const beforeAccDelayedAcc = await setupOpt.bridge.delayedInboxAccs(
      (await setupOpt.bridge.delayedMessageCount()).sub(1)
    )

    const seqReportedMessageSubCountOpt =
      await setupOpt.bridge.sequencerReportedSubMessageCount()
    console.log('ho')
    const res2 = await (
      await (setupOpt.sequencerInbox as unknown as SequencerInboxOpt)
        .connect(setupOpt.batchPoster)
        .functions.addSequencerL2BatchFromOrigin(
          0,
          data,
          messagesReadOpt,
          ethers.constants.AddressZero,
          seqReportedMessageSubCountOpt,
          seqReportedMessageSubCountOpt.add(10),
          {
            beforeAccBeforeAcc: beforeAccBeforeAcc,
            beforeAccDataHash: solidityKeccak256(['string'], ['face']),
            beforeAccDelayedAcc: beforeAccDelayedAcc,
            kind: 3,
            sender: senderAddr,
            blockNumber: l1BlockNumber,
            blockTimestamp: l1BlockTimestamp,
            count: countBefore,
            baseFeeL1: baseFeeL1,
            messageDataHash: messageDataHash,
          },
          { gasLimit: 10000000 }
        )
    ).wait()
    console.log('hi')

    const batchLog = res2.logs
      .filter(
        l =>
          l.topics[0] ===
          bridge.interface.getEventTopic('SequencerBatchDelivered')
      )
      .map(l => bridge.interface.parseLog(l).args)[0] as SequencerBatchDeliveredEvent["args"]
    console.log(batchLog.timeBounds)
    console.log(batchLog.afterDelayedMessagesRead)
    const packed = ethers.utils.solidityPack(
      ['uint64', 'uint64', 'uint64', 'uint64', 'uint64'],
      [
        batchLog.timeBounds.minTimestamp,
        batchLog.timeBounds.maxTimestamp,
        batchLog.timeBounds.minBlockNumber,
        batchLog.timeBounds.maxBlockNumber,
        batchLog.afterDelayedMessagesRead,
      ]
    )
    const dataHash = solidityKeccak256(['bytes', 'bytes'], [packed, data])

    await sendDelayedTx(
      setupOpt.user,
      setupOpt.inbox,
      setupOpt.bridge,
      setupOpt.messageTester,
      1000000,
      21000000000,
      0,
      await setupOpt.user.getAddress(),
      BigNumber.from(10),
      '0x1011'
    )

    const messagesReadOpt2 = await setupOpt.bridge.delayedMessageCount()
    const seqReportedMessageSubCountOpt2 =
      await setupOpt.bridge.sequencerReportedSubMessageCount()
    console.log('b')
    const res3 = await (
      await (setupOpt.sequencerInbox as unknown as SequencerInboxOpt)
        .connect(setupOpt.batchPoster)
        .addSequencerL2BatchFromOrigin(
          1,
          data,
          messagesReadOpt2,
          ethers.constants.AddressZero,
          seqReportedMessageSubCountOpt2,
          seqReportedMessageSubCountOpt2.add(10),
          {
            beforeAccBeforeAcc: beforeAccBeforeAcc,
            beforeAccDataHash: dataHash,
            beforeAccDelayedAcc: beforeAccDelayedAcc,
            kind: 3,
            sender: senderAddr,
            blockNumber: l1BlockNumber,
            blockTimestamp: l1BlockTimestamp,
            count: countBefore,
            baseFeeL1: baseFeeL1,
            messageDataHash: messageDataHash,
          },
          { gasLimit: 10000000 }
        )
    ).wait()

    console.log('saved', res11.gasUsed.toNumber() - res3.gasUsed.toNumber())
  })

  it('can add batch', async () => {
    const { user, inbox, bridge, messageTester, sequencerInbox, batchPoster } =
      await setupSequencerInbox()

    await sendDelayedTx(
      user,
      inbox,
      bridge,
      messageTester,
      1000000,
      21000000000,
      0,
      await user.getAddress(),
      BigNumber.from(10),
      '0x1010'
    )

    const messagesRead = await bridge.delayedMessageCount()
    const seqReportedMessageSubCount =
      await bridge.sequencerReportedSubMessageCount()
    await (
      await sequencerInbox
        .connect(batchPoster)
        .addSequencerL2BatchFromOrigin(
          0,
          data,
          messagesRead,
          ethers.constants.AddressZero,
          seqReportedMessageSubCount,
          seqReportedMessageSubCount.add(10),
          { gasLimit: 10000000 }
        )
    ).wait()
  })

  it('can force-include', async () => {
    const { user, inbox, bridge, messageTester, sequencerInbox } =
      await setupSequencerInbox()

    const delayedTx = await sendDelayedTx(
      user,
      inbox,
      bridge,
      messageTester,
      1000000,
      21000000000,
      0,
      await user.getAddress(),
      BigNumber.from(10),
      '0x1010'
    )
    const maxTimeVariation = await sequencerInbox.maxTimeVariation()

    await mineBlocks(maxTimeVariation.delayBlocks.toNumber())

    await forceIncludeMessages(
      sequencerInbox,
      delayedTx.inboxAccountLength,
      delayedTx.deliveredMessageEvent.kind,
      delayedTx.l1BlockNumber,
      delayedTx.l1BlockTimestamp,
      delayedTx.baseFeeL1,
      delayedTx.senderAddr,
      delayedTx.deliveredMessageEvent.messageDataHash
    )
  })

  it('can force-include one after another', async () => {
    const { user, inbox, bridge, messageTester, sequencerInbox } =
      await setupSequencerInbox()
    const delayedTx = await sendDelayedTx(
      user,
      inbox,
      bridge,
      messageTester,
      1000000,
      21000000000,
      0,
      await user.getAddress(),
      BigNumber.from(10),
      '0x1010'
    )

    const delayedTx2 = await sendDelayedTx(
      user,
      inbox,
      bridge,
      messageTester,
      1000000,
      21000000000,
      1,
      await user.getAddress(),
      BigNumber.from(10),
      '0xdeadface'
    )

    const maxTimeVariation = await sequencerInbox.maxTimeVariation()
    await mineBlocks(maxTimeVariation.delayBlocks.toNumber())

    await forceIncludeMessages(
      sequencerInbox,
      delayedTx.inboxAccountLength,
      delayedTx.deliveredMessageEvent.kind,
      delayedTx.l1BlockNumber,
      delayedTx.l1BlockTimestamp,
      delayedTx.baseFeeL1,
      delayedTx.senderAddr,
      delayedTx.deliveredMessageEvent.messageDataHash
    )
    await forceIncludeMessages(
      sequencerInbox,
      delayedTx2.inboxAccountLength,
      delayedTx2.deliveredMessageEvent.kind,
      delayedTx2.l1BlockNumber,
      delayedTx2.l1BlockTimestamp,
      delayedTx2.baseFeeL1,
      delayedTx2.senderAddr,
      delayedTx2.deliveredMessageEvent.messageDataHash
    )
  })

  it('can force-include three at once', async () => {
    const { user, inbox, bridge, messageTester, sequencerInbox } =
      await setupSequencerInbox()
    await sendDelayedTx(
      user,
      inbox,
      bridge,
      messageTester,
      1000000,
      21000000000,
      0,
      await user.getAddress(),
      BigNumber.from(10),
      '0x1010'
    )
    await sendDelayedTx(
      user,
      inbox,
      bridge,
      messageTester,
      1000000,
      21000000000,
      1,
      await user.getAddress(),
      BigNumber.from(10),
      '0x101010'
    )
    const delayedTx3 = await sendDelayedTx(
      user,
      inbox,
      bridge,
      messageTester,
      1000000,
      21000000000,
      10,
      await user.getAddress(),
      BigNumber.from(10),
      '0x10101010'
    )

    const maxTimeVariation = await sequencerInbox.maxTimeVariation()
    await mineBlocks(maxTimeVariation.delayBlocks.toNumber())

    await forceIncludeMessages(
      sequencerInbox,
      delayedTx3.inboxAccountLength,
      delayedTx3.deliveredMessageEvent.kind,
      delayedTx3.l1BlockNumber,
      delayedTx3.l1BlockTimestamp,
      delayedTx3.baseFeeL1,
      delayedTx3.senderAddr,
      delayedTx3.deliveredMessageEvent.messageDataHash
    )
  })

  it('cannot include before max block delay', async () => {
    const { user, inbox, bridge, messageTester, sequencerInbox } =
      await setupSequencerInbox(10, 100)
    const delayedTx = await sendDelayedTx(
      user,
      inbox,
      bridge,
      messageTester,
      1000000,
      21000000000,
      0,
      await user.getAddress(),
      BigNumber.from(10),
      '0x1010'
    )

    const maxTimeVariation = await sequencerInbox.maxTimeVariation()
    await mineBlocks(maxTimeVariation.delayBlocks.toNumber() - 1, 5)

    await forceIncludeMessages(
      sequencerInbox,
      delayedTx.inboxAccountLength,
      delayedTx.deliveredMessageEvent.kind,
      delayedTx.l1BlockNumber,
      delayedTx.l1BlockTimestamp,
      delayedTx.baseFeeL1,
      delayedTx.senderAddr,
      delayedTx.deliveredMessageEvent.messageDataHash,
      'ForceIncludeBlockTooSoon'
    )
  })

  it('cannot include before max time delay', async () => {
    const { user, inbox, bridge, messageTester, sequencerInbox } =
      await setupSequencerInbox(10, 100)
    const delayedTx = await sendDelayedTx(
      user,
      inbox,
      bridge,
      messageTester,
      1000000,
      21000000000,
      0,
      await user.getAddress(),
      BigNumber.from(10),
      '0x1010'
    )

    const maxTimeVariation = await sequencerInbox.maxTimeVariation()
    // mine a lot of blocks - but use a short time per block
    // this should mean enough blocks have passed, but not enough time
    await mineBlocks(maxTimeVariation.delayBlocks.toNumber() + 1, 5)

    await forceIncludeMessages(
      sequencerInbox,
      delayedTx.inboxAccountLength,
      delayedTx.deliveredMessageEvent.kind,
      delayedTx.l1BlockNumber,
      delayedTx.l1BlockTimestamp,
      delayedTx.baseFeeL1,
      delayedTx.senderAddr,
      delayedTx.deliveredMessageEvent.messageDataHash,
      'ForceIncludeTimeTooSoon'
    )
  })

  it('should fail to call sendL1FundedUnsignedTransactionToFork', async function () {
    const { inbox } = await setupSequencerInbox()
    await expect(
      inbox.sendL1FundedUnsignedTransactionToFork(
        0,
        0,
        0,
        ethers.constants.AddressZero,
        '0x'
      )
    ).to.revertedWith('NotForked()')
  })

  it('should fail to call sendUnsignedTransactionToFork', async function () {
    const { inbox } = await setupSequencerInbox()
    await expect(
      inbox.sendUnsignedTransactionToFork(
        0,
        0,
        0,
        ethers.constants.AddressZero,
        0,
        '0x'
      )
    ).to.revertedWith('NotForked()')
  })

  it('should fail to call sendWithdrawEthToFork', async function () {
    const { inbox } = await setupSequencerInbox()
    await expect(
      inbox.sendWithdrawEthToFork(0, 0, 0, 0, ethers.constants.AddressZero)
    ).to.revertedWith('NotForked()')
  })

  it('can upgrade Inbox', async () => {
    const { inboxProxy, inboxTemplate, bridgeProxy } =
      await setupSequencerInbox()

    const currentStorage = []
    for (let i = 0; i < 1024; i++) {
      currentStorage[i] = await inboxProxy.provider!.getStorageAt(
        inboxProxy.address,
        i
      )
    }

    await expect(
      inboxProxy.upgradeToAndCall(
        inboxTemplate.address,
        (
          await inboxTemplate.populateTransaction.postUpgradeInit(
            bridgeProxy.address
          )
        ).data!
      )
    ).to.emit(inboxProxy, 'Upgraded')

    for (let i = 0; i < currentStorage.length; i++) {
      await expect(
        await inboxProxy.provider!.getStorageAt(inboxProxy.address, i)
      ).to.equal(currentStorage[i])
    }
  })
})
