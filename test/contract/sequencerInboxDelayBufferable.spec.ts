import { ethers, network } from 'hardhat'
import { Block } from '@ethersproject/providers'
import { BigNumber } from '@ethersproject/bignumber'
import { data } from './batchData.json'
import { DelayedMsgDelivered } from './types'
import { expect } from 'chai'

import {
  getSequencerBatchDeliveredEvents,
  getBatchSpendingReport,
  sendDelayedTx,
  setupSequencerInbox,
  getInboxMessageDeliveredEvents,
  mineBlocks,
  forceIncludeMessages,
  getBufferUpdatedEvents,
} from './testHelpers'

describe('SequencerInboxDelayBufferable', async () => {
  it('can deplete buffer', async () => {
    const { bridge, sequencerInbox, batchPoster, delayConfig, maxDelay } =
      await setupSequencerInbox(true)
    const delayedInboxPending: DelayedMsgDelivered[] = []
    let delayedMessageCount = await bridge.delayedMessageCount()
    let seqReportedMessageSubCount =
      await bridge.sequencerReportedSubMessageCount()

    expect(delayedMessageCount).to.equal(0)
    expect(seqReportedMessageSubCount).to.equal(0)
    expect(await sequencerInbox.isDelayBufferable()).to.be.true

    let delayBufferData = await sequencerInbox.bufferData()

    // full buffers
    expect(delayBufferData.buffer).to.equal(delayConfig.max)

    await (
      await sequencerInbox
        .connect(batchPoster)
        [
          'addSequencerL2BatchFromOrigin(uint256,bytes,uint256,address,uint256,uint256)'
        ](
          0,
          data,
          delayedMessageCount,
          ethers.constants.AddressZero,
          seqReportedMessageSubCount,
          seqReportedMessageSubCount.add(10),
          { gasLimit: 10000000 }
        )
    )
      .wait()
      .then(res => {
        delayedInboxPending.push(getBatchSpendingReport(res))
      })

    delayedMessageCount = await bridge.delayedMessageCount()
    seqReportedMessageSubCount = await bridge.sequencerReportedSubMessageCount()

    expect(delayedMessageCount).to.equal(1)
    expect(seqReportedMessageSubCount).to.equal(10)
    expect(await sequencerInbox.totalDelayedMessagesRead()).to.equal(0)

    await forceIncludeMessages(
      sequencerInbox,
      delayedInboxPending[0].delayedCount + 1,
      delayedInboxPending[0].delayedMessage,
      'ForceIncludeBlockTooSoon'
    )

    await mineBlocks(7200, 12)

    const txnReciept = await forceIncludeMessages(
      sequencerInbox,
      delayedInboxPending[0].delayedCount + 1,
      delayedInboxPending[0].delayedMessage
    )

    let forceIncludedMsg = delayedInboxPending.pop()
    const delayBlocks =
      txnReciept!.blockNumber -
      forceIncludedMsg!.delayedMessage.header.blockNumber
    const unexpectedDelayBlocks = delayBlocks - delayConfig.threshold.toNumber()

    const block = (await network.provider.send('eth_getBlockByNumber', [
      '0x' + txnReciept!.blockNumber.toString(16),
      false,
    ])) as Block
    expect(await sequencerInbox.totalDelayedMessagesRead()).to.equal(1)

    delayBufferData = await sequencerInbox.bufferData()

    // full
    expect(delayBufferData.buffer).to.equal(delayConfig.max)
    // prevDelay should be updated
    expect(delayBufferData.prevBlockNumber).to.equal(
      forceIncludedMsg?.delayedMessage.header.blockNumber
    )
    expect(delayBufferData.prevDelay).to.equal(delayBlocks)

    await (
      await sequencerInbox
        .connect(batchPoster)
        [
          'addSequencerL2BatchFromOrigin(uint256,bytes,uint256,address,uint256,uint256)'
        ](
          2,
          data,
          delayedMessageCount,
          ethers.constants.AddressZero,
          seqReportedMessageSubCount,
          seqReportedMessageSubCount.add(10),
          { gasLimit: 10000000 }
        )
    )
      .wait()
      .then(res => {
        delayedInboxPending.push(getBatchSpendingReport(res))
      })

    await mineBlocks(7200, 12)

    const txnReciept2 = await forceIncludeMessages(
      sequencerInbox,
      delayedInboxPending[0].delayedCount + 1,
      delayedInboxPending[0].delayedMessage
    )
    forceIncludedMsg = delayedInboxPending.pop()
    delayBufferData = await sequencerInbox.bufferData()

    const depletedBufferBlocks = delayConfig.max - unexpectedDelayBlocks
    expect(delayBufferData.buffer).to.equal(depletedBufferBlocks)

    const delayBlocks2 =
      txnReciept2!.blockNumber -
      forceIncludedMsg!.delayedMessage.header.blockNumber

    const block2 = (await network.provider.send('eth_getBlockByNumber', [
      '0x' + txnReciept2!.blockNumber.toString(16),
      false,
    ])) as Block
    const delaySeconds2 =
      block2.timestamp - forceIncludedMsg!.delayedMessage.header.timestamp
    expect(await sequencerInbox.totalDelayedMessagesRead()).to.equal(2)
    // prevDelay should be updated
    expect(delayBufferData.prevBlockNumber).to.equal(
      forceIncludedMsg?.delayedMessage.header.blockNumber
    )
    expect(delayBufferData.prevDelay).to.equal(delayBlocks2)

    const deadline = await sequencerInbox.forceInclusionDeadline(
      delayBufferData.prevBlockNumber
    )
    const delayBlocksDeadline =
      depletedBufferBlocks > maxDelay.delayBlocks
        ? maxDelay.delayBlocks
        : depletedBufferBlocks
    expect(deadline).to.equal(
      delayBufferData.prevBlockNumber.add(delayBlocksDeadline)
    )

    const unexpectedDelayBlocks2 = delayBufferData.prevDelay
      .sub(delayConfig.threshold)
      .toNumber()
    const futureBlock =
      forceIncludedMsg!.delayedMessage.header.blockNumber +
      delayBufferData.prevDelay.toNumber()
    const deadline2 = await sequencerInbox.forceInclusionDeadline(futureBlock)
    const calcBufferBlocks =
      depletedBufferBlocks - unexpectedDelayBlocks2 >
      delayConfig.threshold.toNumber()
        ? depletedBufferBlocks - unexpectedDelayBlocks2
        : delayConfig.threshold.toNumber()
    const delayBlocksDeadline2 =
      calcBufferBlocks > maxDelay.delayBlocks
        ? maxDelay.delayBlocks
        : calcBufferBlocks
    expect(deadline2).to.equal(futureBlock + delayBlocksDeadline2)
  })

  it('can replenish buffer', async () => {
    const { bridge, sequencerInbox, batchPoster, delayConfig } =
      await setupSequencerInbox(true)
    const delayedInboxPending: DelayedMsgDelivered[] = []
    let delayedMessageCount = await bridge.delayedMessageCount()
    let seqReportedMessageSubCount =
      await bridge.sequencerReportedSubMessageCount()
    let delayBufferData = await sequencerInbox.bufferData()
    await (
      await sequencerInbox
        .connect(batchPoster)
        [
          'addSequencerL2BatchFromOrigin(uint256,bytes,uint256,address,uint256,uint256)'
        ](
          0,
          data,
          delayedMessageCount,
          ethers.constants.AddressZero,
          seqReportedMessageSubCount,
          seqReportedMessageSubCount.add(10),
          { gasLimit: 10000000 }
        )
    )
      .wait()
      .then(res => {
        delayedInboxPending.push(getBatchSpendingReport(res))
      })

    delayedMessageCount = await bridge.delayedMessageCount()
    seqReportedMessageSubCount = await bridge.sequencerReportedSubMessageCount()

    await forceIncludeMessages(
      sequencerInbox,
      delayedInboxPending[0].delayedCount + 1,
      delayedInboxPending[0].delayedMessage,
      'ForceIncludeBlockTooSoon'
    )

    await mineBlocks(7200, 12)

    await forceIncludeMessages(
      sequencerInbox,
      delayedInboxPending[0].delayedCount + 1,
      delayedInboxPending[0].delayedMessage
    )

    await (
      await sequencerInbox
        .connect(batchPoster)
        [
          'addSequencerL2BatchFromOrigin(uint256,bytes,uint256,address,uint256,uint256)'
        ](
          2,
          data,
          delayedMessageCount,
          ethers.constants.AddressZero,
          seqReportedMessageSubCount,
          seqReportedMessageSubCount.add(10),
          { gasLimit: 10000000 }
        )
    )
      .wait()
      .then(res => {
        delayedInboxPending.push(getBatchSpendingReport(res))
      })

    const tx = sequencerInbox
      .connect(batchPoster)
      [
        'addSequencerL2BatchFromOrigin(uint256,bytes,uint256,address,uint256,uint256)'
      ](
        3,
        data,
        delayedMessageCount.add(1),
        ethers.constants.AddressZero,
        seqReportedMessageSubCount.add(10),
        seqReportedMessageSubCount.add(20),
        { gasLimit: 10000000 }
      )
    await expect(tx).to.be.revertedWith('DelayProofRequired')

    let nextDelayedMsg = delayedInboxPending.pop()
    await mineBlocks(delayConfig.threshold.toNumber() - 100, 12)

    await (
      await sequencerInbox
        .connect(batchPoster)
        .addSequencerL2BatchFromOriginBufferProof(
          3,
          data,
          delayedMessageCount.add(1),
          ethers.constants.AddressZero,
          seqReportedMessageSubCount.add(10),
          seqReportedMessageSubCount.add(20),
          {
            beforeDelayedAcc: nextDelayedMsg!.delayedAcc,
            delayedMessage: {
              kind: nextDelayedMsg!.delayedMessage.header.kind,
              sender: nextDelayedMsg!.delayedMessage.header.sender,
              blockNumber: nextDelayedMsg!.delayedMessage.header.blockNumber,
              timestamp: nextDelayedMsg!.delayedMessage.header.timestamp,
              inboxSeqNum: nextDelayedMsg!.delayedCount,
              baseFeeL1: nextDelayedMsg!.delayedMessage.header.baseFee,
              messageDataHash:
                nextDelayedMsg!.delayedMessage.header.messageDataHash,
            },
            preimage: {
              beforeAcc: ethers.constants.HashZero,
              dataHash: ethers.constants.HashZero,
              delayedAcc: ethers.constants.HashZero,
            },
          },
          { gasLimit: 10000000 }
        )
    )
      .wait()
      .then(res => {
        delayedInboxPending.push(getBatchSpendingReport(res))
      })
    delayBufferData = await sequencerInbox.bufferData()
    nextDelayedMsg = delayedInboxPending.pop()

    await mineBlocks(delayConfig.threshold.toNumber() - 100, 12)

    await (
      await sequencerInbox
        .connect(batchPoster)
        .addSequencerL2BatchFromOriginBufferProof(
          4,
          data,
          delayedMessageCount.add(2),
          ethers.constants.AddressZero,
          seqReportedMessageSubCount.add(20),
          seqReportedMessageSubCount.add(30),
          {
            beforeDelayedAcc: nextDelayedMsg!.delayedAcc,
            delayedMessage: {
              kind: nextDelayedMsg!.delayedMessage.header.kind,
              sender: nextDelayedMsg!.delayedMessage.header.sender,
              blockNumber: nextDelayedMsg!.delayedMessage.header.blockNumber,
              timestamp: nextDelayedMsg!.delayedMessage.header.timestamp,
              inboxSeqNum: nextDelayedMsg!.delayedCount,
              baseFeeL1: nextDelayedMsg!.delayedMessage.header.baseFee,
              messageDataHash:
                nextDelayedMsg!.delayedMessage.header.messageDataHash,
            },
            preimage: {
              beforeAcc: ethers.constants.HashZero,
              dataHash: ethers.constants.HashZero,
              delayedAcc: ethers.constants.HashZero,
            },
          },
          { gasLimit: 10000000 }
        )
    )
      .wait()
      .then(res => {
        delayedInboxPending.push(getBatchSpendingReport(res))
        return res
      })

    const delayBufferData2 = await sequencerInbox.bufferData()
    const replenishBlocks = Math.floor(
      (nextDelayedMsg!.delayedMessage.header.blockNumber -
        delayBufferData.prevBlockNumber.toNumber()) /
        delayConfig.period
    )
    expect(delayBufferData2.buffer.toNumber()).to.equal(
      delayBufferData.buffer.toNumber() + replenishBlocks
    )
  })

  it('happy path', async () => {
    const { bridge, sequencerInbox, batchPoster, delayConfig } =
      await setupSequencerInbox(true)
    const delayedInboxPending: DelayedMsgDelivered[] = []
    const delayedMessageCount = await bridge.delayedMessageCount()
    const seqReportedMessageSubCount =
      await bridge.sequencerReportedSubMessageCount()

    const block = (await network.provider.send('eth_getBlockByNumber', [
      'latest',
      false,
    ])) as Block
    const blockNumber = Number.parseInt(block.number.toString(10))
    const blockTimestamp = Number.parseInt(block.timestamp.toString(10))
    expect(
      (await sequencerInbox.bufferData()).syncExpiry.toNumber()
    ).greaterThanOrEqual(blockNumber)
    await (
      await sequencerInbox
        .connect(batchPoster)
        [
          'addSequencerL2BatchFromOrigin(uint256,bytes,uint256,address,uint256,uint256)'
        ](
          0,
          data,
          delayedMessageCount,
          ethers.constants.AddressZero,
          seqReportedMessageSubCount,
          seqReportedMessageSubCount.add(10),
          { gasLimit: 10000000 }
        )
    )
      .wait()
      .then(res => {
        delayedInboxPending.push(getBatchSpendingReport(res))
      })

    await mineBlocks(delayConfig.threshold.toNumber() - 100, 12)
    const lastDelayedMsgRead = delayedInboxPending.pop()
    const res = await (
      await sequencerInbox
        .connect(batchPoster)
        [
          'addSequencerL2BatchFromOrigin(uint256,bytes,uint256,address,uint256,uint256)'
        ](
          1,
          data,
          delayedMessageCount.add(1),
          ethers.constants.AddressZero,
          seqReportedMessageSubCount.add(10),
          seqReportedMessageSubCount.add(20),
          { gasLimit: 10000000 }
        )
    )
      .wait()
      .then(res => {
        delayedInboxPending.push(getBatchSpendingReport(res))
        return res
      })

    const batchDelivered = getSequencerBatchDeliveredEvents(res)
    const inboxMessageDelivered = getInboxMessageDeliveredEvents(res)[0]

    await (
      await sequencerInbox
        .connect(batchPoster)
        .addSequencerL2BatchFromOriginBufferProof(
          2,
          data,
          delayedMessageCount.add(2),
          ethers.constants.AddressZero,
          seqReportedMessageSubCount.add(20),
          seqReportedMessageSubCount.add(30),
          {
            beforeDelayedAcc: lastDelayedMsgRead!.delayedAcc,
            delayedMessage: {
              kind: lastDelayedMsgRead!.delayedMessage.header.kind,
              sender: lastDelayedMsgRead!.delayedMessage.header.sender,
              blockNumber:
                lastDelayedMsgRead!.delayedMessage.header.blockNumber,
              timestamp: lastDelayedMsgRead!.delayedMessage.header.timestamp,
              inboxSeqNum: lastDelayedMsgRead!.delayedCount,
              baseFeeL1: lastDelayedMsgRead!.delayedMessage.header.baseFee,
              messageDataHash:
                lastDelayedMsgRead!.delayedMessage.header.messageDataHash,
            },
            preimage: {
              beforeAcc: batchDelivered!.beforeAcc,
              dataHash: '0x' + inboxMessageDelivered.data.slice(106, 170),
              delayedAcc: batchDelivered!.delayedAcc,
            },
          },
          { gasLimit: 10000000 }
        )
    )
      .wait()
      .then(res => {
        delayedInboxPending.push(getBatchSpendingReport(res))
      })
  })

  it('unhappy path', async () => {
    const { bridge, sequencerInbox, batchPoster, delayConfig } =
      await setupSequencerInbox(true)
    let delayedInboxPending: DelayedMsgDelivered[] = []
    const delayedMessageCount = await bridge.delayedMessageCount()
    const seqReportedMessageSubCount =
      await bridge.sequencerReportedSubMessageCount()

    const block = (await network.provider.send('eth_getBlockByNumber', [
      'latest',
      false,
    ])) as Block
    const blockNumber = Number.parseInt(block.number.toString(10))
    const blockTimestamp = Number.parseInt(block.timestamp.toString(10))
    expect(
      (await sequencerInbox.bufferData()).syncExpiry.toNumber()
    ).greaterThanOrEqual(blockNumber)
    await (
      await sequencerInbox
        .connect(batchPoster)
        [
          'addSequencerL2BatchFromOrigin(uint256,bytes,uint256,address,uint256,uint256)'
        ](
          0,
          data,
          delayedMessageCount,
          ethers.constants.AddressZero,
          seqReportedMessageSubCount,
          seqReportedMessageSubCount.add(10),
          { gasLimit: 10000000 }
        )
    )
      .wait()
      .then(res => {
        delayedInboxPending.push(getBatchSpendingReport(res))
      })

    await mineBlocks(delayConfig.threshold.toNumber() - 100, 12)
    await (
      await sequencerInbox
        .connect(batchPoster)
        [
          'addSequencerL2BatchFromOrigin(uint256,bytes,uint256,address,uint256,uint256)'
        ](
          1,
          data,
          delayedMessageCount,
          ethers.constants.AddressZero,
          seqReportedMessageSubCount.add(10),
          seqReportedMessageSubCount.add(20),
          { gasLimit: 10000000 }
        )
    )
      .wait()
      .then(res => {
        delayedInboxPending.push(getBatchSpendingReport(res))
      })

    let firstReadMsg = delayedInboxPending[0]
    await mineBlocks(101, 12)

    const txn = sequencerInbox
      .connect(batchPoster)
      [
        'addSequencerL2BatchFromOrigin(uint256,bytes,uint256,address,uint256,uint256)'
      ](
        2,
        data,
        delayedMessageCount.add(2),
        ethers.constants.AddressZero,
        seqReportedMessageSubCount.add(20),
        seqReportedMessageSubCount.add(30),
        { gasLimit: 10000000 }
      )
    await expect(txn).to.be.revertedWith('DelayProofRequired')

    await (
      await sequencerInbox
        .connect(batchPoster)
        .addSequencerL2BatchFromOriginBufferProof(
          2,
          data,
          delayedMessageCount.add(2),
          ethers.constants.AddressZero,
          seqReportedMessageSubCount.add(20),
          seqReportedMessageSubCount.add(30),
          {
            beforeDelayedAcc: firstReadMsg!.delayedAcc,
            delayedMessage: {
              kind: firstReadMsg!.delayedMessage.header.kind,
              sender: firstReadMsg!.delayedMessage.header.sender,
              blockNumber: firstReadMsg!.delayedMessage.header.blockNumber,
              timestamp: firstReadMsg!.delayedMessage.header.timestamp,
              inboxSeqNum: firstReadMsg!.delayedCount,
              baseFeeL1: firstReadMsg!.delayedMessage.header.baseFee,
              messageDataHash:
                firstReadMsg!.delayedMessage.header.messageDataHash,
            },
            preimage: {
              beforeAcc: ethers.constants.HashZero,
              dataHash: ethers.constants.HashZero,
              delayedAcc: ethers.constants.HashZero,
            },
          },
          { gasLimit: 10000000 }
        )
    )
      .wait()
      .then(async res => {
        delayedInboxPending = []
        delayedInboxPending.push(getBatchSpendingReport(res))
        await expect(getBufferUpdatedEvents(res).length).to.equal(1)
        return res
      })

    const delayBufferDataBefore = await sequencerInbox.bufferData()
    firstReadMsg = delayedInboxPending[0]
    const txnBatch = await (
      await sequencerInbox
        .connect(batchPoster)
        .addSequencerL2BatchFromOriginBufferProof(
          3,
          data,
          delayedMessageCount.add(3),
          ethers.constants.AddressZero,
          seqReportedMessageSubCount.add(30),
          seqReportedMessageSubCount.add(40),
          {
            beforeDelayedAcc: firstReadMsg!.delayedAcc,
            delayedMessage: {
              kind: firstReadMsg!.delayedMessage.header.kind,
              sender: firstReadMsg!.delayedMessage.header.sender,
              blockNumber: firstReadMsg!.delayedMessage.header.blockNumber,
              timestamp: firstReadMsg!.delayedMessage.header.timestamp,
              inboxSeqNum: firstReadMsg!.delayedCount,
              baseFeeL1: firstReadMsg!.delayedMessage.header.baseFee,
              messageDataHash:
                firstReadMsg!.delayedMessage.header.messageDataHash,
            },
            preimage: {
              beforeAcc: ethers.constants.HashZero,
              dataHash: ethers.constants.HashZero,
              delayedAcc: ethers.constants.HashZero,
            },
          },
          { gasLimit: 10000000 }
        )
    )
      .wait()
      .then(async res => {
        delayedInboxPending = []
        delayedInboxPending.push(getBatchSpendingReport(res))
        await expect(getBufferUpdatedEvents(res).length).to.equal(1)
        return res
      })

    const unexpectedDelayBlocks =
      delayBufferDataBefore.prevDelay.toNumber() -
      delayConfig.threshold.toNumber()
    const elapsed =
      firstReadMsg!.delayedMessage.header.blockNumber -
      delayBufferDataBefore.prevBlockNumber.toNumber()
    const bufferBlocksUpdate =
      delayBufferDataBefore.buffer.toNumber() -
      Math.min(unexpectedDelayBlocks, elapsed)
    expect((await sequencerInbox.bufferData()).buffer).to.equal(
      bufferBlocksUpdate
    )
  })

  it('can sync and resync (gas benchmark)', async () => {
    const { user, inbox, bridge, messageTester, sequencerInbox, batchPoster } =
      await setupSequencerInbox()
    let delayedInboxPending: DelayedMsgDelivered[] = []
    const setupBufferable = await setupSequencerInbox(true)

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
      setupBufferable.user,
      setupBufferable.inbox,
      setupBufferable.bridge,
      setupBufferable.messageTester,
      1000000,
      21000000000,
      0,
      await setupBufferable.user.getAddress(),
      BigNumber.from(10),
      '0x1011'
    ).then(res => {
      delayedInboxPending.push({
        delayedMessage: res.delayedMsg,
        delayedAcc: res.prevAccumulator,
        delayedCount: res.countBefore,
      })
    })

    // read all messages
    const messagesRead = await bridge.delayedMessageCount()
    const seqReportedMessageSubCount =
      await bridge.sequencerReportedSubMessageCount()

    await (
      await sequencerInbox
        .connect(batchPoster)
        [
          'addSequencerL2BatchFromOrigin(uint256,bytes,uint256,address,uint256,uint256)'
        ](
          0,
          data,
          messagesRead,
          ethers.constants.AddressZero,
          seqReportedMessageSubCount,
          seqReportedMessageSubCount.add(10),
          { gasLimit: 10000000 }
        )
    ).wait()

    // read all delayed messages
    const messagesReadOpt = await setupBufferable.bridge.delayedMessageCount()
    const totalDelayedMessagesRead = (
      await setupBufferable.sequencerInbox.totalDelayedMessagesRead()
    ).toNumber()

    const beforeDelayedAcc =
      totalDelayedMessagesRead == 0
        ? ethers.constants.HashZero
        : await setupBufferable.bridge.delayedInboxAccs(
            totalDelayedMessagesRead - 1
          )

    const seqReportedMessageSubCountOpt =
      await setupBufferable.bridge.sequencerReportedSubMessageCount()

    // pass proof of the last read delayed message
    let delayedMsgLastRead = delayedInboxPending[delayedInboxPending.length - 1]
    delayedInboxPending = []
    await (
      await setupBufferable.sequencerInbox
        .connect(setupBufferable.batchPoster)
        .addSequencerL2BatchFromOriginBufferProof(
          0,
          data,
          messagesReadOpt,
          ethers.constants.AddressZero,
          seqReportedMessageSubCountOpt,
          seqReportedMessageSubCountOpt.add(10),
          {
            beforeDelayedAcc: beforeDelayedAcc,
            delayedMessage: {
              kind: 3,
              sender: delayedMsgLastRead!.delayedMessage.header.sender,
              blockNumber:
                delayedMsgLastRead!.delayedMessage.header.blockNumber,
              timestamp: delayedMsgLastRead!.delayedMessage.header.timestamp,
              inboxSeqNum: delayedMsgLastRead!.delayedCount,
              baseFeeL1: delayedMsgLastRead!.delayedMessage.header.baseFee,
              messageDataHash:
                delayedMsgLastRead!.delayedMessage.header.messageDataHash,
            },
            preimage: {
              beforeAcc: ethers.constants.HashZero,
              dataHash: ethers.constants.HashZero,
              delayedAcc: ethers.constants.HashZero,
            },
          },
          { gasLimit: 10000000 }
        )
    )
      .wait()
      .then(res => {
        delayedInboxPending.push(getBatchSpendingReport(res))
      })

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
      setupBufferable.user,
      setupBufferable.inbox,
      setupBufferable.bridge,
      setupBufferable.messageTester,
      1000000,
      21000000000,
      0,
      await setupBufferable.user.getAddress(),
      BigNumber.from(10),
      '0x1011'
    ).then(res => {
      delayedInboxPending.push({
        delayedMessage: res.delayedMsg,
        delayedAcc: res.prevAccumulator,
        delayedCount: res.countBefore,
      })
    })

    // 2 delayed messages in the inbox, read 1 messages
    const messagesReadAdd1 = await bridge.delayedMessageCount()
    const seqReportedMessageSubCountAdd1 =
      await bridge.sequencerReportedSubMessageCount()

    const res11 = await (
      await sequencerInbox
        .connect(batchPoster)
        [
          'addSequencerL2BatchFromOrigin(uint256,bytes,uint256,address,uint256,uint256)'
        ](
          1,
          data,
          messagesReadAdd1.sub(1),
          ethers.constants.AddressZero,
          seqReportedMessageSubCountAdd1,
          seqReportedMessageSubCountAdd1.add(10),
          { gasLimit: 10000000 }
        )
    ).wait()

    const messagesReadOpt2 = await setupBufferable.bridge.delayedMessageCount()
    const seqReportedMessageSubCountOpt2 =
      await setupBufferable.bridge.sequencerReportedSubMessageCount()

    // start parole
    // pass delayed message proof
    // read 1 message
    delayedMsgLastRead = delayedInboxPending[delayedInboxPending.length - 2]
    delayedInboxPending = [delayedInboxPending[delayedInboxPending.length - 1]]
    const res3 = await (
      await setupBufferable.sequencerInbox
        .connect(setupBufferable.batchPoster)
        .addSequencerL2BatchFromOriginBufferProof(
          1,
          data,
          messagesReadOpt2.sub(1),
          ethers.constants.AddressZero,
          seqReportedMessageSubCountOpt2,
          seqReportedMessageSubCountOpt2.add(10),
          {
            beforeDelayedAcc: delayedMsgLastRead!.delayedAcc,
            delayedMessage: {
              kind: delayedMsgLastRead!.delayedMessage.header.kind,
              sender: delayedMsgLastRead!.delayedMessage.header.sender,
              blockNumber:
                delayedMsgLastRead!.delayedMessage.header.blockNumber,
              timestamp: delayedMsgLastRead!.delayedMessage.header.timestamp,
              inboxSeqNum: delayedMsgLastRead!.delayedCount,
              baseFeeL1: delayedMsgLastRead!.delayedMessage.header.baseFee,
              messageDataHash:
                delayedMsgLastRead!.delayedMessage.header.messageDataHash,
            },
            preimage: {
              beforeAcc: ethers.constants.HashZero,
              dataHash: ethers.constants.HashZero,
              delayedAcc: ethers.constants.HashZero,
            },
          },
          { gasLimit: 10000000 }
        )
    ).wait()
    const lastRead = delayedInboxPending.pop()

    delayedInboxPending.push(getBatchSpendingReport(res3))

    const res4 = await (
      await setupBufferable.sequencerInbox
        .connect(setupBufferable.batchPoster)
        .functions[
          'addSequencerL2BatchFromOrigin(uint256,bytes,uint256,address,uint256,uint256)'
        ](
          2,
          data,
          messagesReadOpt2,
          ethers.constants.AddressZero,
          seqReportedMessageSubCountOpt2.add(10),
          seqReportedMessageSubCountOpt2.add(20),
          { gasLimit: 10000000 }
        )
    ).wait()
    const batchSpendingReport = getBatchSpendingReport(res4)
    delayedInboxPending.push(batchSpendingReport)
    const batchDelivered = getSequencerBatchDeliveredEvents(res4)
    const inboxMessageDelivered = getInboxMessageDeliveredEvents(res4)[0]

    const res5 = await (
      await setupBufferable.sequencerInbox
        .connect(setupBufferable.batchPoster)
        .addSequencerL2BatchFromOriginBufferProof(
          3,
          data,
          messagesReadOpt2.add(1),
          ethers.constants.AddressZero,
          seqReportedMessageSubCountOpt2.add(20),
          seqReportedMessageSubCountOpt2.add(30),
          {
            beforeDelayedAcc: lastRead!.delayedAcc,
            delayedMessage: {
              kind: lastRead!.delayedMessage.header.kind,
              sender: lastRead!.delayedMessage.header.sender,
              blockNumber: lastRead!.delayedMessage.header.blockNumber,
              timestamp: lastRead!.delayedMessage.header.timestamp,
              inboxSeqNum: lastRead!.delayedCount,
              baseFeeL1: lastRead!.delayedMessage.header.baseFee,
              messageDataHash: lastRead!.delayedMessage.header.messageDataHash,
            },
            preimage: {
              beforeAcc: batchDelivered!.beforeAcc,
              dataHash: '0x' + inboxMessageDelivered.data.slice(106, 170),
              delayedAcc: batchDelivered!.delayedAcc,
            },
          },
          { gasLimit: 10000000 }
        )
    ).wait()

    //console.log('start sync',res11.gasUsed.toNumber() - res3.gasUsed.toNumber())
    //console.log('resync', res11.gasUsed.toNumber() - res5.gasUsed.toNumber())
    //console.log('synced', res11.gasUsed.toNumber() - res4.gasUsed.toNumber())
  })
})

describe('SequencerInboxDelayBufferableBlobMock', async () => {
  it('can deplete buffer', async () => {
    const { bridge, sequencerInbox, batchPoster, delayConfig, maxDelay } =
      await setupSequencerInbox(true, true)
    const delayedInboxPending: DelayedMsgDelivered[] = []
    let delayedMessageCount = await bridge.delayedMessageCount()
    let seqReportedMessageSubCount =
      await bridge.sequencerReportedSubMessageCount()

    expect(delayedMessageCount).to.equal(0)
    expect(seqReportedMessageSubCount).to.equal(0)
    expect(await sequencerInbox.isDelayBufferable()).to.be.true

    let delayBufferData = await sequencerInbox.bufferData()

    // full buffer
    expect(delayBufferData.buffer).to.equal(delayConfig.max)

    await (
      await sequencerInbox
        .connect(batchPoster)
        .addSequencerL2BatchFromBlobs(
          0,
          delayedMessageCount,
          ethers.constants.AddressZero,
          seqReportedMessageSubCount,
          seqReportedMessageSubCount.add(10),
          { gasLimit: 10000000 }
        )
    )
      .wait()
      .then(res => {
        delayedInboxPending.push(getBatchSpendingReport(res))
      })

    delayedMessageCount = await bridge.delayedMessageCount()
    seqReportedMessageSubCount = await bridge.sequencerReportedSubMessageCount()

    expect(delayedMessageCount).to.equal(1)
    expect(seqReportedMessageSubCount).to.equal(10)
    expect(await sequencerInbox.totalDelayedMessagesRead()).to.equal(0)

    await forceIncludeMessages(
      sequencerInbox,
      delayedInboxPending[0].delayedCount + 1,
      delayedInboxPending[0].delayedMessage,
      'ForceIncludeBlockTooSoon'
    )

    await mineBlocks(7200, 12)

    const txnReciept = await forceIncludeMessages(
      sequencerInbox,
      delayedInboxPending[0].delayedCount + 1,
      delayedInboxPending[0].delayedMessage
    )

    let forceIncludedMsg = delayedInboxPending.pop()
    const delayBlocks =
      txnReciept!.blockNumber -
      forceIncludedMsg!.delayedMessage.header.blockNumber
    const unexpectedDelayBlocks = delayBlocks - delayConfig.threshold.toNumber()

    const block = (await network.provider.send('eth_getBlockByNumber', [
      '0x' + txnReciept!.blockNumber.toString(16),
      false,
    ])) as Block
    expect(await sequencerInbox.totalDelayedMessagesRead()).to.equal(1)

    delayBufferData = await sequencerInbox.bufferData()

    // full
    expect(delayBufferData.buffer).to.equal(delayConfig.max)
    // prevDelay should be updated
    expect(delayBufferData.prevBlockNumber).to.equal(
      forceIncludedMsg?.delayedMessage.header.blockNumber
    )

    expect(delayBufferData.prevDelay).to.equal(delayBlocks)

    await (
      await sequencerInbox
        .connect(batchPoster)
        .addSequencerL2BatchFromBlobs(
          2,
          delayedMessageCount,
          ethers.constants.AddressZero,
          seqReportedMessageSubCount,
          seqReportedMessageSubCount.add(10),
          { gasLimit: 10000000 }
        )
    )
      .wait()
      .then(res => {
        delayedInboxPending.push(getBatchSpendingReport(res))
      })

    await mineBlocks(7200, 12)

    const txnReciept2 = await forceIncludeMessages(
      sequencerInbox,
      delayedInboxPending[0].delayedCount + 1,
      delayedInboxPending[0].delayedMessage
    )
    forceIncludedMsg = delayedInboxPending.pop()
    delayBufferData = await sequencerInbox.bufferData()

    const depletedBufferBlocks = delayConfig.max - unexpectedDelayBlocks
    expect(delayBufferData.buffer).to.equal(depletedBufferBlocks)

    const delayBlocks2 =
      txnReciept2!.blockNumber -
      forceIncludedMsg!.delayedMessage.header.blockNumber

    const block2 = (await network.provider.send('eth_getBlockByNumber', [
      '0x' + txnReciept2!.blockNumber.toString(16),
      false,
    ])) as Block
    const delaySeconds2 =
      block2.timestamp - forceIncludedMsg!.delayedMessage.header.timestamp
    expect(await sequencerInbox.totalDelayedMessagesRead()).to.equal(2)
    // prevDelay should be updated
    expect(delayBufferData.prevBlockNumber).to.equal(
      forceIncludedMsg?.delayedMessage.header.blockNumber
    )
    expect(delayBufferData.prevDelay).to.equal(delayBlocks2)

    const deadline = await sequencerInbox.forceInclusionDeadline(
      delayBufferData.prevBlockNumber
    )
    const delayBlocksDeadline =
      depletedBufferBlocks > maxDelay.delayBlocks
        ? maxDelay.delayBlocks
        : depletedBufferBlocks
    expect(deadline).to.equal(
      delayBufferData.prevBlockNumber.add(delayBlocksDeadline)
    )

    const unexpectedDelayBlocks2 = delayBufferData.prevDelay
      .sub(delayConfig.threshold)
      .toNumber()
    const futureBlock =
      forceIncludedMsg!.delayedMessage.header.blockNumber +
      delayBufferData.prevDelay.toNumber()
    const deadline2 = await sequencerInbox.forceInclusionDeadline(futureBlock)
    const calcBufferBlocks =
      depletedBufferBlocks - unexpectedDelayBlocks2 >
      delayConfig.threshold.toNumber()
        ? depletedBufferBlocks - unexpectedDelayBlocks2
        : delayConfig.threshold.toNumber()
    const delayBlocksDeadline2 =
      calcBufferBlocks > maxDelay.delayBlocks
        ? maxDelay.delayBlocks
        : calcBufferBlocks
    expect(deadline2).to.equal(futureBlock + delayBlocksDeadline2)
  })

  it('can replenish buffer', async () => {
    const { bridge, sequencerInbox, batchPoster, delayConfig } =
      await setupSequencerInbox(true, true)
    const delayedInboxPending: DelayedMsgDelivered[] = []
    let delayedMessageCount = await bridge.delayedMessageCount()
    let seqReportedMessageSubCount =
      await bridge.sequencerReportedSubMessageCount()
    let delayBufferData = await sequencerInbox.bufferData()
    await (
      await sequencerInbox
        .connect(batchPoster)
        .addSequencerL2BatchFromBlobs(
          0,
          delayedMessageCount,
          ethers.constants.AddressZero,
          seqReportedMessageSubCount,
          seqReportedMessageSubCount.add(10),
          { gasLimit: 10000000 }
        )
    )
      .wait()
      .then(res => {
        delayedInboxPending.push(getBatchSpendingReport(res))
      })

    delayedMessageCount = await bridge.delayedMessageCount()
    seqReportedMessageSubCount = await bridge.sequencerReportedSubMessageCount()

    await forceIncludeMessages(
      sequencerInbox,
      delayedInboxPending[0].delayedCount + 1,
      delayedInboxPending[0].delayedMessage,
      'ForceIncludeBlockTooSoon'
    )

    await mineBlocks(7200, 12)

    await forceIncludeMessages(
      sequencerInbox,
      delayedInboxPending[0].delayedCount + 1,
      delayedInboxPending[0].delayedMessage
    )

    await (
      await sequencerInbox
        .connect(batchPoster)
        .addSequencerL2BatchFromBlobs(
          2,
          delayedMessageCount,
          ethers.constants.AddressZero,
          seqReportedMessageSubCount,
          seqReportedMessageSubCount.add(10),
          { gasLimit: 10000000 }
        )
    )
      .wait()
      .then(res => {
        delayedInboxPending.push(getBatchSpendingReport(res))
      })

    const tx = sequencerInbox
      .connect(batchPoster)
      .addSequencerL2BatchFromBlobs(
        3,
        delayedMessageCount.add(1),
        ethers.constants.AddressZero,
        seqReportedMessageSubCount.add(10),
        seqReportedMessageSubCount.add(20),
        { gasLimit: 10000000 }
      )
    await expect(tx).to.be.revertedWith('DelayProofRequired')

    let nextDelayedMsg = delayedInboxPending.pop()
    await mineBlocks(delayConfig.threshold.toNumber() - 100, 12)

    await (
      await sequencerInbox
        .connect(batchPoster)
        .addSequencerL2BatchFromBlobsBufferProof(
          3,
          delayedMessageCount.add(1),
          ethers.constants.AddressZero,
          seqReportedMessageSubCount.add(10),
          seqReportedMessageSubCount.add(20),
          {
            beforeDelayedAcc: nextDelayedMsg!.delayedAcc,
            delayedMessage: {
              kind: nextDelayedMsg!.delayedMessage.header.kind,
              sender: nextDelayedMsg!.delayedMessage.header.sender,
              blockNumber: nextDelayedMsg!.delayedMessage.header.blockNumber,
              timestamp: nextDelayedMsg!.delayedMessage.header.timestamp,
              inboxSeqNum: nextDelayedMsg!.delayedCount,
              baseFeeL1: nextDelayedMsg!.delayedMessage.header.baseFee,
              messageDataHash:
                nextDelayedMsg!.delayedMessage.header.messageDataHash,
            },
            preimage: {
              beforeAcc: ethers.constants.HashZero,
              dataHash: ethers.constants.HashZero,
              delayedAcc: ethers.constants.HashZero,
            },
          },
          { gasLimit: 10000000 }
        )
    )
      .wait()
      .then(res => {
        delayedInboxPending.push(getBatchSpendingReport(res))
      })
    delayBufferData = await sequencerInbox.bufferData()
    nextDelayedMsg = delayedInboxPending.pop()

    await mineBlocks(delayConfig.threshold.toNumber() - 100, 12)

    await (
      await sequencerInbox
        .connect(batchPoster)
        .connect(batchPoster)
        .addSequencerL2BatchFromBlobsBufferProof(
          4,
          delayedMessageCount.add(2),
          ethers.constants.AddressZero,
          seqReportedMessageSubCount.add(20),
          seqReportedMessageSubCount.add(30),
          {
            beforeDelayedAcc: nextDelayedMsg!.delayedAcc,
            delayedMessage: {
              kind: nextDelayedMsg!.delayedMessage.header.kind,
              sender: nextDelayedMsg!.delayedMessage.header.sender,
              blockNumber: nextDelayedMsg!.delayedMessage.header.blockNumber,
              timestamp: nextDelayedMsg!.delayedMessage.header.timestamp,
              inboxSeqNum: nextDelayedMsg!.delayedCount,
              baseFeeL1: nextDelayedMsg!.delayedMessage.header.baseFee,
              messageDataHash:
                nextDelayedMsg!.delayedMessage.header.messageDataHash,
            },
            preimage: {
              beforeAcc: ethers.constants.HashZero,
              dataHash: ethers.constants.HashZero,
              delayedAcc: ethers.constants.HashZero,
            },
          },
          { gasLimit: 10000000 }
        )
    )
      .wait()
      .then(res => {
        delayedInboxPending.push(getBatchSpendingReport(res))
        return res
      })

    const delayBufferData2 = await sequencerInbox.bufferData()
    const replenishBlocks = Math.floor(
      (nextDelayedMsg!.delayedMessage.header.blockNumber -
        delayBufferData.prevBlockNumber.toNumber()) /
        delayConfig.period
    )
    expect(delayBufferData2.buffer.toNumber()).to.equal(
      delayBufferData.buffer.toNumber() + replenishBlocks
    )
  })

  it('happy path', async () => {
    const { bridge, sequencerInbox, batchPoster, delayConfig } =
      await setupSequencerInbox(true, true)
    const delayedInboxPending: DelayedMsgDelivered[] = []
    const delayedMessageCount = await bridge.delayedMessageCount()
    const seqReportedMessageSubCount =
      await bridge.sequencerReportedSubMessageCount()

    const block = (await network.provider.send('eth_getBlockByNumber', [
      'latest',
      false,
    ])) as Block
    const blockNumber = Number.parseInt(block.number.toString(10))
    const blockTimestamp = Number.parseInt(block.timestamp.toString(10))
    expect(
      (await sequencerInbox.bufferData()).syncExpiry.toNumber()
    ).greaterThanOrEqual(blockNumber)
    await (
      await sequencerInbox
        .connect(batchPoster)
        .addSequencerL2BatchFromBlobs(
          0,
          delayedMessageCount,
          ethers.constants.AddressZero,
          seqReportedMessageSubCount,
          seqReportedMessageSubCount.add(10),
          { gasLimit: 10000000 }
        )
    )
      .wait()
      .then(res => {
        delayedInboxPending.push(getBatchSpendingReport(res))
      })

    await mineBlocks(delayConfig.threshold.toNumber() - 100, 12)
    const lastDelayedMsgRead = delayedInboxPending.pop()
    const res = await (
      await sequencerInbox
        .connect(batchPoster)
        .addSequencerL2BatchFromBlobs(
          1,
          delayedMessageCount.add(1),
          ethers.constants.AddressZero,
          seqReportedMessageSubCount.add(10),
          seqReportedMessageSubCount.add(20),
          { gasLimit: 10000000 }
        )
    )
      .wait()
      .then(res => {
        delayedInboxPending.push(getBatchSpendingReport(res))
        return res
      })

    const batchDelivered = getSequencerBatchDeliveredEvents(res)
    const inboxMessageDelivered = getInboxMessageDeliveredEvents(res)[0]

    await (
      await sequencerInbox
        .connect(batchPoster)
        .addSequencerL2BatchFromBlobsBufferProof(
          2,
          delayedMessageCount.add(2),
          ethers.constants.AddressZero,
          seqReportedMessageSubCount.add(20),
          seqReportedMessageSubCount.add(30),
          {
            beforeDelayedAcc: lastDelayedMsgRead!.delayedAcc,
            delayedMessage: {
              kind: lastDelayedMsgRead!.delayedMessage.header.kind,
              sender: lastDelayedMsgRead!.delayedMessage.header.sender,
              blockNumber:
                lastDelayedMsgRead!.delayedMessage.header.blockNumber,
              timestamp: lastDelayedMsgRead!.delayedMessage.header.timestamp,
              inboxSeqNum: lastDelayedMsgRead!.delayedCount,
              baseFeeL1: lastDelayedMsgRead!.delayedMessage.header.baseFee,
              messageDataHash:
                lastDelayedMsgRead!.delayedMessage.header.messageDataHash,
            },
            preimage: {
              beforeAcc: batchDelivered!.beforeAcc,
              dataHash: '0x' + inboxMessageDelivered.data.slice(106, 170),
              delayedAcc: batchDelivered!.delayedAcc,
            },
          },
          { gasLimit: 10000000 }
        )
    )
      .wait()
      .then(res => {
        delayedInboxPending.push(getBatchSpendingReport(res))
      })
  })

  it('unhappy path', async () => {
    const { bridge, sequencerInbox, batchPoster, delayConfig } =
      await setupSequencerInbox(true, true)
    const delayedInboxPending: DelayedMsgDelivered[] = []
    const delayedMessageCount = await bridge.delayedMessageCount()
    const seqReportedMessageSubCount =
      await bridge.sequencerReportedSubMessageCount()

    const block = (await network.provider.send('eth_getBlockByNumber', [
      'latest',
      false,
    ])) as Block
    const blockNumber = Number.parseInt(block.number.toString(10))
    const blockTimestamp = Number.parseInt(block.timestamp.toString(10))
    expect(
      (await sequencerInbox.bufferData()).syncExpiry.toNumber()
    ).greaterThanOrEqual(blockNumber)
    await (
      await sequencerInbox
        .connect(batchPoster)
        .addSequencerL2BatchFromBlobs(
          0,
          delayedMessageCount,
          ethers.constants.AddressZero,
          seqReportedMessageSubCount,
          seqReportedMessageSubCount.add(10),
          { gasLimit: 10000000 }
        )
    )
      .wait()
      .then(res => {
        delayedInboxPending.push(getBatchSpendingReport(res))
      })

    await mineBlocks(delayConfig.threshold.toNumber() - 100, 12)
    await (
      await sequencerInbox
        .connect(batchPoster)
        .addSequencerL2BatchFromBlobs(
          1,
          delayedMessageCount.add(1),
          ethers.constants.AddressZero,
          seqReportedMessageSubCount.add(10),
          seqReportedMessageSubCount.add(20),
          { gasLimit: 10000000 }
        )
    )
      .wait()
      .then(res => {
        delayedInboxPending.pop()
        delayedInboxPending.push(getBatchSpendingReport(res))
      })

    const firstReadMsg = delayedInboxPending.pop()
    await mineBlocks(100, 12)

    const txn = sequencerInbox
      .connect(batchPoster)
      .addSequencerL2BatchFromBlobs(
        2,
        delayedMessageCount.add(2),
        ethers.constants.AddressZero,
        seqReportedMessageSubCount.add(20),
        seqReportedMessageSubCount.add(30),
        { gasLimit: 10000000 }
      )
    await expect(txn).to.be.revertedWith('DelayProofRequired')

    await (
      await sequencerInbox
        .connect(batchPoster)
        .addSequencerL2BatchFromBlobsBufferProof(
          2,
          delayedMessageCount.add(2),
          ethers.constants.AddressZero,
          seqReportedMessageSubCount.add(20),
          seqReportedMessageSubCount.add(30),
          {
            beforeDelayedAcc: firstReadMsg!.delayedAcc,
            delayedMessage: {
              kind: firstReadMsg!.delayedMessage.header.kind,
              sender: firstReadMsg!.delayedMessage.header.sender,
              blockNumber: firstReadMsg!.delayedMessage.header.blockNumber,
              timestamp: firstReadMsg!.delayedMessage.header.timestamp,
              inboxSeqNum: firstReadMsg!.delayedCount,
              baseFeeL1: firstReadMsg!.delayedMessage.header.baseFee,
              messageDataHash:
                firstReadMsg!.delayedMessage.header.messageDataHash,
            },
            preimage: {
              beforeAcc: ethers.constants.HashZero,
              dataHash: ethers.constants.HashZero,
              delayedAcc: ethers.constants.HashZero,
            },
          },
          { gasLimit: 10000000 }
        )
    )
      .wait()
      .then(res => {
        delayedInboxPending.push(getBatchSpendingReport(res))
      })
  })

  it('can sync and resync (gas benchmark)', async () => {
    const { user, inbox, bridge, messageTester, sequencerInbox, batchPoster } =
      await setupSequencerInbox(false, true)
    let delayedInboxPending: DelayedMsgDelivered[] = []
    const setupBufferable = await setupSequencerInbox(true, true)

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
      setupBufferable.user,
      setupBufferable.inbox,
      setupBufferable.bridge,
      setupBufferable.messageTester,
      1000000,
      21000000000,
      0,
      await setupBufferable.user.getAddress(),
      BigNumber.from(10),
      '0x1011'
    ).then(res => {
      delayedInboxPending.push({
        delayedMessage: res.delayedMsg,
        delayedAcc: res.prevAccumulator,
        delayedCount: res.countBefore,
      })
    })

    // read all messages
    const messagesRead = await bridge.delayedMessageCount()
    const seqReportedMessageSubCount =
      await bridge.sequencerReportedSubMessageCount()

    await (
      await sequencerInbox
        .connect(batchPoster)
        .addSequencerL2BatchFromBlobs(
          0,
          messagesRead,
          ethers.constants.AddressZero,
          seqReportedMessageSubCount,
          seqReportedMessageSubCount.add(10),
          { gasLimit: 10000000 }
        )
    ).wait()

    // read all delayed messages
    const messagesReadOpt = await setupBufferable.bridge.delayedMessageCount()
    const totalDelayedMessagesRead = (
      await setupBufferable.sequencerInbox.totalDelayedMessagesRead()
    ).toNumber()

    const beforeDelayedAcc =
      totalDelayedMessagesRead == 0
        ? ethers.constants.HashZero
        : await setupBufferable.bridge.delayedInboxAccs(
            totalDelayedMessagesRead - 1
          )

    const seqReportedMessageSubCountOpt =
      await setupBufferable.bridge.sequencerReportedSubMessageCount()

    // pass proof of the last read delayed message
    let delayedMsgLastRead = delayedInboxPending[delayedInboxPending.length - 1]
    delayedInboxPending = []
    await (
      await setupBufferable.sequencerInbox
        .connect(setupBufferable.batchPoster)
        .addSequencerL2BatchFromBlobsBufferProof(
          0,
          messagesReadOpt,
          ethers.constants.AddressZero,
          seqReportedMessageSubCountOpt,
          seqReportedMessageSubCountOpt.add(10),
          {
            beforeDelayedAcc: beforeDelayedAcc,
            delayedMessage: {
              kind: 3,
              sender: delayedMsgLastRead!.delayedMessage.header.sender,
              blockNumber:
                delayedMsgLastRead!.delayedMessage.header.blockNumber,
              timestamp: delayedMsgLastRead!.delayedMessage.header.timestamp,
              inboxSeqNum: delayedMsgLastRead!.delayedCount,
              baseFeeL1: delayedMsgLastRead!.delayedMessage.header.baseFee,
              messageDataHash:
                delayedMsgLastRead!.delayedMessage.header.messageDataHash,
            },
            preimage: {
              beforeAcc: ethers.constants.HashZero,
              dataHash: ethers.constants.HashZero,
              delayedAcc: ethers.constants.HashZero,
            },
          },
          { gasLimit: 10000000 }
        )
    )
      .wait()
      .then(res => {
        delayedInboxPending.push(getBatchSpendingReport(res))
      })

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
      setupBufferable.user,
      setupBufferable.inbox,
      setupBufferable.bridge,
      setupBufferable.messageTester,
      1000000,
      21000000000,
      0,
      await setupBufferable.user.getAddress(),
      BigNumber.from(10),
      '0x1011'
    ).then(res => {
      delayedInboxPending.push({
        delayedMessage: res.delayedMsg,
        delayedAcc: res.prevAccumulator,
        delayedCount: res.countBefore,
      })
    })

    // 2 delayed messages in the inbox, read 1 messages
    const messagesReadAdd1 = await bridge.delayedMessageCount()
    const seqReportedMessageSubCountAdd1 =
      await bridge.sequencerReportedSubMessageCount()

    const res11 = await (
      await sequencerInbox
        .connect(batchPoster)
        .addSequencerL2BatchFromBlobs(
          1,
          messagesReadAdd1.sub(1),
          ethers.constants.AddressZero,
          seqReportedMessageSubCountAdd1,
          seqReportedMessageSubCountAdd1.add(10),
          { gasLimit: 10000000 }
        )
    ).wait()

    const messagesReadOpt2 = await setupBufferable.bridge.delayedMessageCount()
    const seqReportedMessageSubCountOpt2 =
      await setupBufferable.bridge.sequencerReportedSubMessageCount()

    // start parole
    // pass delayed message proof
    // read 1 message
    delayedMsgLastRead = delayedInboxPending[delayedInboxPending.length - 2]
    delayedInboxPending = [delayedInboxPending[delayedInboxPending.length - 1]]
    const res3 = await (
      await setupBufferable.sequencerInbox
        .connect(setupBufferable.batchPoster)
        .addSequencerL2BatchFromBlobsBufferProof(
          1,
          messagesReadOpt2.sub(1),
          ethers.constants.AddressZero,
          seqReportedMessageSubCountOpt2,
          seqReportedMessageSubCountOpt2.add(10),
          {
            beforeDelayedAcc: delayedMsgLastRead!.delayedAcc,
            delayedMessage: {
              kind: delayedMsgLastRead!.delayedMessage.header.kind,
              sender: delayedMsgLastRead!.delayedMessage.header.sender,
              blockNumber:
                delayedMsgLastRead!.delayedMessage.header.blockNumber,
              timestamp: delayedMsgLastRead!.delayedMessage.header.timestamp,
              inboxSeqNum: delayedMsgLastRead!.delayedCount,
              baseFeeL1: delayedMsgLastRead!.delayedMessage.header.baseFee,
              messageDataHash:
                delayedMsgLastRead!.delayedMessage.header.messageDataHash,
            },
            preimage: {
              beforeAcc: ethers.constants.HashZero,
              dataHash: ethers.constants.HashZero,
              delayedAcc: ethers.constants.HashZero,
            },
          },
          { gasLimit: 10000000 }
        )
    ).wait()
    const lastRead = delayedInboxPending.pop()

    delayedInboxPending.push(getBatchSpendingReport(res3))

    const res4 = await (
      await setupBufferable.sequencerInbox
        .connect(setupBufferable.batchPoster)
        .addSequencerL2BatchFromBlobs(
          2,
          messagesReadOpt2,
          ethers.constants.AddressZero,
          seqReportedMessageSubCountOpt2.add(10),
          seqReportedMessageSubCountOpt2.add(20),
          { gasLimit: 10000000 }
        )
    ).wait()
    const batchSpendingReport = getBatchSpendingReport(res4)
    delayedInboxPending.push(batchSpendingReport)
    const batchDelivered = getSequencerBatchDeliveredEvents(res4)
    const inboxMessageDelivered = getInboxMessageDeliveredEvents(res4)[0]

    const res5 = await (
      await setupBufferable.sequencerInbox
        .connect(setupBufferable.batchPoster)
        .addSequencerL2BatchFromBlobsBufferProof(
          3,
          messagesReadOpt2.add(1),
          ethers.constants.AddressZero,
          seqReportedMessageSubCountOpt2.add(20),
          seqReportedMessageSubCountOpt2.add(30),
          {
            beforeDelayedAcc: lastRead!.delayedAcc,
            delayedMessage: {
              kind: lastRead!.delayedMessage.header.kind,
              sender: lastRead!.delayedMessage.header.sender,
              blockNumber: lastRead!.delayedMessage.header.blockNumber,
              timestamp: lastRead!.delayedMessage.header.timestamp,
              inboxSeqNum: lastRead!.delayedCount,
              baseFeeL1: lastRead!.delayedMessage.header.baseFee,
              messageDataHash: lastRead!.delayedMessage.header.messageDataHash,
            },
            preimage: {
              beforeAcc: batchDelivered!.beforeAcc,
              dataHash: '0x' + inboxMessageDelivered.data.slice(106, 170),
              delayedAcc: batchDelivered!.delayedAcc,
            },
          },
          { gasLimit: 10000000 }
        )
    ).wait()

    //console.log('start sync',res11.gasUsed.toNumber() - res3.gasUsed.toNumber())
    //console.log('resync', res11.gasUsed.toNumber() - res5.gasUsed.toNumber())
    //console.log('synced', res11.gasUsed.toNumber() - res4.gasUsed.toNumber())
  })
})
