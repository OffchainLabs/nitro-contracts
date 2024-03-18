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

    let delayBufferData = await sequencerInbox.buffer()

    // full buffers
    expect(delayBufferData.bufferBlocks).to.equal(delayConfig.maxBufferBlocks)
    expect(delayBufferData.bufferSeconds).to.equal(delayConfig.maxBufferSeconds)

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
    const unexpectedDelayBlocks =
      delayBlocks - delayConfig.thresholdBlocks.toNumber()

    const block = (await network.provider.send('eth_getBlockByNumber', [
      '0x' + txnReciept!.blockNumber.toString(16),
      false,
    ])) as Block
    const delaySeconds =
      block.timestamp - forceIncludedMsg!.delayedMessage.header.timestamp
    const unexpectedDelaySeconds =
      delaySeconds - delayConfig.thresholdSeconds.toNumber()
    expect(await sequencerInbox.totalDelayedMessagesRead()).to.equal(1)

    delayBufferData = await sequencerInbox.buffer()

    // full
    expect(delayBufferData.bufferBlocks).to.equal(delayConfig.maxBufferBlocks)
    expect(delayBufferData.bufferSeconds).to.equal(delayConfig.maxBufferSeconds)
    // prevDelay should be updated
    expect(delayBufferData.prevDelay.blockNumber).to.equal(
      forceIncludedMsg?.delayedMessage.header.blockNumber
    )
    expect(delayBufferData.prevDelay.timestamp).to.equal(
      forceIncludedMsg?.delayedMessage.header.timestamp
    )
    expect(delayBufferData.prevDelay.delayBlocks).to.equal(delayBlocks)
    expect(delayBufferData.prevDelay.delaySeconds).to.equal(delaySeconds)

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
    delayBufferData = await sequencerInbox.buffer()

    const depletedBufferBlocks =
      delayConfig.maxBufferBlocks - unexpectedDelayBlocks
    const depletedBufferSeconds =
      delayConfig.maxBufferSeconds - unexpectedDelaySeconds
    expect(delayBufferData.bufferBlocks).to.equal(depletedBufferBlocks)
    expect(delayBufferData.bufferSeconds).to.equal(depletedBufferSeconds)

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
    expect(delayBufferData.prevDelay.blockNumber).to.equal(
      forceIncludedMsg?.delayedMessage.header.blockNumber
    )
    expect(delayBufferData.prevDelay.timestamp).to.equal(
      forceIncludedMsg?.delayedMessage.header.timestamp
    )
    expect(delayBufferData.prevDelay.delayBlocks).to.equal(delayBlocks2)
    expect(delayBufferData.prevDelay.delaySeconds).to.equal(delaySeconds2)

    const deadline = await sequencerInbox.forceInclusionDeadline(
      delayBufferData.prevDelay.blockNumber,
      delayBufferData.prevDelay.timestamp
    )
    const delayBlocksDeadline =
      depletedBufferBlocks > maxDelay.delayBlocks
        ? maxDelay.delayBlocks
        : depletedBufferBlocks
    const delayTimestampDeadline =
      depletedBufferSeconds > maxDelay.delaySeconds
        ? maxDelay.delaySeconds
        : depletedBufferSeconds
    expect(deadline[0]).to.equal(
      delayBufferData.prevDelay.blockNumber.add(delayBlocksDeadline)
    )
    expect(deadline[1]).to.equal(
      delayBufferData.prevDelay.timestamp.add(delayTimestampDeadline)
    )

    const unexpectedDelayBlocks2 = delayBufferData.prevDelay.delayBlocks
      .sub(delayConfig.thresholdBlocks)
      .toNumber()
    const unexpectedDelaySecond2 = delayBufferData.prevDelay.delaySeconds
      .sub(delayConfig.thresholdSeconds)
      .toNumber()
    const futureBlock =
      forceIncludedMsg!.delayedMessage.header.blockNumber +
      delayBufferData.prevDelay.delayBlocks.toNumber()
    const futureTime =
      forceIncludedMsg!.delayedMessage.header.timestamp +
      delayBufferData.prevDelay.delaySeconds.toNumber()
    const deadline2 = await sequencerInbox.forceInclusionDeadline(
      futureBlock,
      futureTime
    )
    const calcBufferBlocks =
      depletedBufferBlocks - unexpectedDelayBlocks2 >
      delayConfig.thresholdBlocks.toNumber()
        ? depletedBufferBlocks - unexpectedDelayBlocks2
        : delayConfig.thresholdBlocks.toNumber()
    const calcBufferSeconds =
      depletedBufferSeconds - unexpectedDelaySecond2 >
      delayConfig.thresholdSeconds.toNumber()
        ? depletedBufferSeconds - unexpectedDelaySecond2
        : delayConfig.thresholdSeconds.toNumber()
    const delayBlocksDeadline2 =
      calcBufferBlocks > maxDelay.delayBlocks
        ? maxDelay.delayBlocks
        : calcBufferBlocks
    const delayTimestampDeadline2 =
      calcBufferSeconds > maxDelay.delaySeconds
        ? maxDelay.delaySeconds
        : calcBufferSeconds
    expect(deadline2[0]).to.equal(futureBlock + delayBlocksDeadline2)
    expect(deadline2[1]).to.equal(futureTime + delayTimestampDeadline2)
  })

  it('can replenish buffer', async () => {
    const { bridge, sequencerInbox, batchPoster, delayConfig } =
      await setupSequencerInbox(true)
    const delayedInboxPending: DelayedMsgDelivered[] = []
    let delayedMessageCount = await bridge.delayedMessageCount()
    let seqReportedMessageSubCount =
      await bridge.sequencerReportedSubMessageCount()
    let delayBufferData = await sequencerInbox.buffer()
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
    await mineBlocks(delayConfig.thresholdBlocks.toNumber() - 100, 12)

    await (
      await sequencerInbox
        .connect(batchPoster)
        [
          'addSequencerL2BatchFromOrigin(uint256,bytes,uint256,address,uint256,uint256,bytes32,(uint8,address,uint64,uint64,uint256,uint256,bytes32))'
        ](
          3,
          data,
          delayedMessageCount.add(1),
          ethers.constants.AddressZero,
          seqReportedMessageSubCount.add(10),
          seqReportedMessageSubCount.add(20),
          nextDelayedMsg!.delayedAcc,
          {
            kind: nextDelayedMsg!.delayedMessage.header.kind,
            sender: nextDelayedMsg!.delayedMessage.header.sender,
            blockNumber: nextDelayedMsg!.delayedMessage.header.blockNumber,
            timestamp: nextDelayedMsg!.delayedMessage.header.timestamp,
            inboxSeqNum: nextDelayedMsg!.delayedCount,
            baseFeeL1: nextDelayedMsg!.delayedMessage.header.baseFee,
            messageDataHash:
              nextDelayedMsg!.delayedMessage.header.messageDataHash,
          },
          { gasLimit: 10000000 }
        )
    )
      .wait()
      .then(res => {
        delayedInboxPending.push(getBatchSpendingReport(res))
      })
    delayBufferData = await sequencerInbox.buffer()
    nextDelayedMsg = delayedInboxPending.pop()

    await mineBlocks(delayConfig.thresholdBlocks.toNumber() - 100, 12)

    await (
      await sequencerInbox
        .connect(batchPoster)
        [
          'addSequencerL2BatchFromOrigin(uint256,bytes,uint256,address,uint256,uint256,bytes32,(uint8,address,uint64,uint64,uint256,uint256,bytes32))'
        ](
          4,
          data,
          delayedMessageCount.add(2),
          ethers.constants.AddressZero,
          seqReportedMessageSubCount.add(20),
          seqReportedMessageSubCount.add(30),
          nextDelayedMsg!.delayedAcc,
          {
            kind: nextDelayedMsg!.delayedMessage.header.kind,
            sender: nextDelayedMsg!.delayedMessage.header.sender,
            blockNumber: nextDelayedMsg!.delayedMessage.header.blockNumber,
            timestamp: nextDelayedMsg!.delayedMessage.header.timestamp,
            inboxSeqNum: nextDelayedMsg!.delayedCount,
            baseFeeL1: nextDelayedMsg!.delayedMessage.header.baseFee,
            messageDataHash:
              nextDelayedMsg!.delayedMessage.header.messageDataHash,
          },
          { gasLimit: 10000000 }
        )
    )
      .wait()
      .then(res => {
        delayedInboxPending.push(getBatchSpendingReport(res))
        return res
      })

    const delayBufferData2 = await sequencerInbox.buffer()
    const replenishBlocks = Math.floor(
      ((nextDelayedMsg!.delayedMessage.header.blockNumber -
        delayBufferData.prevDelay.blockNumber.toNumber()) /
        delayConfig.replenishRate.periodBlocks) *
        delayConfig.replenishRate.blocksPerPeriod
    )
    const replenishSeconds = Math.floor(
      ((nextDelayedMsg!.delayedMessage.header.timestamp -
        delayBufferData.prevDelay.timestamp.toNumber()) /
        delayConfig.replenishRate.periodSeconds) *
        delayConfig.replenishRate.secondsPerPeriod
    )
    const replenishRoundOffBlocks = Math.floor(
      (nextDelayedMsg!.delayedMessage.header.blockNumber -
        delayBufferData.prevDelay.blockNumber.toNumber()) %
        delayConfig.replenishRate.periodBlocks
    )
    const replenishRoundOffSeconds = Math.floor(
      (nextDelayedMsg!.delayedMessage.header.timestamp -
        delayBufferData.prevDelay.timestamp.toNumber()) %
        delayConfig.replenishRate.periodSeconds
    )
    expect(delayBufferData2.bufferBlocks.toNumber()).to.equal(
      delayBufferData.bufferBlocks.toNumber() + replenishBlocks
    )
    expect(delayBufferData2.bufferSeconds.toNumber()).to.equal(
      delayBufferData.bufferSeconds.toNumber() + replenishSeconds
    )
    expect(delayBufferData2.roundOffBlocks.toNumber()).to.equal(
      replenishRoundOffBlocks
    )
    expect(delayBufferData2.roundOffSeconds.toNumber()).to.equal(
      replenishRoundOffSeconds
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
      (await sequencerInbox.buffer()).syncExpiryBlockNumber.toNumber()
    ).greaterThanOrEqual(blockNumber)
    expect(
      (await sequencerInbox.buffer()).syncExpiryTimestamp.toNumber()
    ).greaterThanOrEqual(blockTimestamp)
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

    await mineBlocks(delayConfig.thresholdBlocks.toNumber() - 100, 12)
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
        [
          'addSequencerL2BatchFromOrigin(uint256,bytes,uint256,address,uint256,uint256,bytes32,(uint8,address,uint64,uint64,uint256,uint256,bytes32),(bytes32,bytes32,bytes32))'
        ](
          2,
          data,
          delayedMessageCount.add(2),
          ethers.constants.AddressZero,
          seqReportedMessageSubCount.add(20),
          seqReportedMessageSubCount.add(30),
          lastDelayedMsgRead!.delayedAcc,
          {
            kind: lastDelayedMsgRead!.delayedMessage.header.kind,
            sender: lastDelayedMsgRead!.delayedMessage.header.sender,
            blockNumber: lastDelayedMsgRead!.delayedMessage.header.blockNumber,
            timestamp: lastDelayedMsgRead!.delayedMessage.header.timestamp,
            inboxSeqNum: lastDelayedMsgRead!.delayedCount,
            baseFeeL1: lastDelayedMsgRead!.delayedMessage.header.baseFee,
            messageDataHash:
              lastDelayedMsgRead!.delayedMessage.header.messageDataHash,
          },
          {
            beforeAcc: batchDelivered!.beforeAcc,
            dataHash: '0x' + inboxMessageDelivered.data.slice(106, 170),
            delayedAcc: batchDelivered!.delayedAcc,
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
      (await sequencerInbox.buffer()).syncExpiryBlockNumber.toNumber()
    ).greaterThanOrEqual(blockNumber)
    expect(
      (await sequencerInbox.buffer()).syncExpiryTimestamp.toNumber()
    ).greaterThanOrEqual(blockTimestamp)
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

    await mineBlocks(delayConfig.thresholdBlocks.toNumber() - 100, 12)
    await (
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
        delayedInboxPending.pop()
        delayedInboxPending.push(getBatchSpendingReport(res))
      })

    const firstReadMsg = delayedInboxPending.pop()
    await mineBlocks(100, 12)

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
        [
          'addSequencerL2BatchFromOrigin(uint256,bytes,uint256,address,uint256,uint256,bytes32,(uint8,address,uint64,uint64,uint256,uint256,bytes32))'
        ](
          2,
          data,
          delayedMessageCount.add(2),
          ethers.constants.AddressZero,
          seqReportedMessageSubCount.add(20),
          seqReportedMessageSubCount.add(30),
          firstReadMsg!.delayedAcc,
          {
            kind: firstReadMsg!.delayedMessage.header.kind,
            sender: firstReadMsg!.delayedMessage.header.sender,
            blockNumber: firstReadMsg!.delayedMessage.header.blockNumber,
            timestamp: firstReadMsg!.delayedMessage.header.timestamp,
            inboxSeqNum: firstReadMsg!.delayedCount,
            baseFeeL1: firstReadMsg!.delayedMessage.header.baseFee,
            messageDataHash:
              firstReadMsg!.delayedMessage.header.messageDataHash,
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
        [
          'addSequencerL2BatchFromOrigin(uint256,bytes,uint256,address,uint256,uint256,bytes32,(uint8,address,uint64,uint64,uint256,uint256,bytes32))'
        ](
          0,
          data,
          messagesReadOpt,
          ethers.constants.AddressZero,
          seqReportedMessageSubCountOpt,
          seqReportedMessageSubCountOpt.add(10),
          beforeDelayedAcc,
          {
            kind: 3,
            sender: delayedMsgLastRead!.delayedMessage.header.sender,
            blockNumber: delayedMsgLastRead!.delayedMessage.header.blockNumber,
            timestamp: delayedMsgLastRead!.delayedMessage.header.timestamp,
            inboxSeqNum: delayedMsgLastRead!.delayedCount,
            baseFeeL1: delayedMsgLastRead!.delayedMessage.header.baseFee,
            messageDataHash:
              delayedMsgLastRead!.delayedMessage.header.messageDataHash,
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
        .functions[
          'addSequencerL2BatchFromOrigin(uint256,bytes,uint256,address,uint256,uint256,bytes32,(uint8,address,uint64,uint64,uint256,uint256,bytes32))'
        ](
          1,
          data,
          messagesReadOpt2.sub(1),
          ethers.constants.AddressZero,
          seqReportedMessageSubCountOpt2,
          seqReportedMessageSubCountOpt2.add(10),
          delayedMsgLastRead!.delayedAcc,
          {
            kind: delayedMsgLastRead!.delayedMessage.header.kind,
            sender: delayedMsgLastRead!.delayedMessage.header.sender,
            blockNumber: delayedMsgLastRead!.delayedMessage.header.blockNumber,
            timestamp: delayedMsgLastRead!.delayedMessage.header.timestamp,
            inboxSeqNum: delayedMsgLastRead!.delayedCount,
            baseFeeL1: delayedMsgLastRead!.delayedMessage.header.baseFee,
            messageDataHash:
              delayedMsgLastRead!.delayedMessage.header.messageDataHash,
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
        .functions[
          'addSequencerL2BatchFromOrigin(uint256,bytes,uint256,address,uint256,uint256,bytes32,(uint8,address,uint64,uint64,uint256,uint256,bytes32),(bytes32,bytes32,bytes32))'
        ](
          3,
          data,
          messagesReadOpt2.add(1),
          ethers.constants.AddressZero,
          seqReportedMessageSubCountOpt2.add(20),
          seqReportedMessageSubCountOpt2.add(30),
          lastRead!.delayedAcc,
          {
            kind: lastRead!.delayedMessage.header.kind,
            sender: lastRead!.delayedMessage.header.sender,
            blockNumber: lastRead!.delayedMessage.header.blockNumber,
            timestamp: lastRead!.delayedMessage.header.timestamp,
            inboxSeqNum: lastRead!.delayedCount,
            baseFeeL1: lastRead!.delayedMessage.header.baseFee,
            messageDataHash: lastRead!.delayedMessage.header.messageDataHash,
          },
          {
            beforeAcc: batchDelivered!.beforeAcc,
            dataHash: '0x' + inboxMessageDelivered.data.slice(106, 170),
            delayedAcc: batchDelivered!.delayedAcc,
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

    let delayBufferData = await sequencerInbox.buffer()

    // full buffers
    expect(delayBufferData.bufferBlocks).to.equal(delayConfig.maxBufferBlocks)
    expect(delayBufferData.bufferSeconds).to.equal(delayConfig.maxBufferSeconds)

    await (
      await sequencerInbox
        .connect(batchPoster)
        [
          'addSequencerL2BatchFromBlobs(uint256,uint256,address,uint256,uint256)'
        ](
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
    const unexpectedDelayBlocks =
      delayBlocks - delayConfig.thresholdBlocks.toNumber()

    const block = (await network.provider.send('eth_getBlockByNumber', [
      '0x' + txnReciept!.blockNumber.toString(16),
      false,
    ])) as Block
    const delaySeconds =
      block.timestamp - forceIncludedMsg!.delayedMessage.header.timestamp
    const unexpectedDelaySeconds =
      delaySeconds - delayConfig.thresholdSeconds.toNumber()
    expect(await sequencerInbox.totalDelayedMessagesRead()).to.equal(1)

    delayBufferData = await sequencerInbox.buffer()

    // full
    expect(delayBufferData.bufferBlocks).to.equal(delayConfig.maxBufferBlocks)
    expect(delayBufferData.bufferSeconds).to.equal(delayConfig.maxBufferSeconds)
    // prevDelay should be updated
    expect(delayBufferData.prevDelay.blockNumber).to.equal(
      forceIncludedMsg?.delayedMessage.header.blockNumber
    )
    expect(delayBufferData.prevDelay.timestamp).to.equal(
      forceIncludedMsg?.delayedMessage.header.timestamp
    )
    expect(delayBufferData.prevDelay.delayBlocks).to.equal(delayBlocks)
    expect(delayBufferData.prevDelay.delaySeconds).to.equal(delaySeconds)

    await (
      await sequencerInbox
        .connect(batchPoster)
        [
          'addSequencerL2BatchFromBlobs(uint256,uint256,address,uint256,uint256)'
        ](
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
    delayBufferData = await sequencerInbox.buffer()

    const depletedBufferBlocks =
      delayConfig.maxBufferBlocks - unexpectedDelayBlocks
    const depletedBufferSeconds =
      delayConfig.maxBufferSeconds - unexpectedDelaySeconds
    expect(delayBufferData.bufferBlocks).to.equal(depletedBufferBlocks)
    expect(delayBufferData.bufferSeconds).to.equal(depletedBufferSeconds)

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
    expect(delayBufferData.prevDelay.blockNumber).to.equal(
      forceIncludedMsg?.delayedMessage.header.blockNumber
    )
    expect(delayBufferData.prevDelay.timestamp).to.equal(
      forceIncludedMsg?.delayedMessage.header.timestamp
    )
    expect(delayBufferData.prevDelay.delayBlocks).to.equal(delayBlocks2)
    expect(delayBufferData.prevDelay.delaySeconds).to.equal(delaySeconds2)

    const deadline = await sequencerInbox.forceInclusionDeadline(
      delayBufferData.prevDelay.blockNumber,
      delayBufferData.prevDelay.timestamp
    )
    const delayBlocksDeadline =
      depletedBufferBlocks > maxDelay.delayBlocks
        ? maxDelay.delayBlocks
        : depletedBufferBlocks
    const delayTimestampDeadline =
      depletedBufferSeconds > maxDelay.delaySeconds
        ? maxDelay.delaySeconds
        : depletedBufferSeconds
    expect(deadline[0]).to.equal(
      delayBufferData.prevDelay.blockNumber.add(delayBlocksDeadline)
    )
    expect(deadline[1]).to.equal(
      delayBufferData.prevDelay.timestamp.add(delayTimestampDeadline)
    )

    const unexpectedDelayBlocks2 = delayBufferData.prevDelay.delayBlocks
      .sub(delayConfig.thresholdBlocks)
      .toNumber()
    const unexpectedDelaySecond2 = delayBufferData.prevDelay.delaySeconds
      .sub(delayConfig.thresholdSeconds)
      .toNumber()
    const futureBlock =
      forceIncludedMsg!.delayedMessage.header.blockNumber +
      delayBufferData.prevDelay.delayBlocks.toNumber()
    const futureTime =
      forceIncludedMsg!.delayedMessage.header.timestamp +
      delayBufferData.prevDelay.delaySeconds.toNumber()
    const deadline2 = await sequencerInbox.forceInclusionDeadline(
      futureBlock,
      futureTime
    )
    const calcBufferBlocks =
      depletedBufferBlocks - unexpectedDelayBlocks2 >
      delayConfig.thresholdBlocks.toNumber()
        ? depletedBufferBlocks - unexpectedDelayBlocks2
        : delayConfig.thresholdBlocks.toNumber()
    const calcBufferSeconds =
      depletedBufferSeconds - unexpectedDelaySecond2 >
      delayConfig.thresholdSeconds.toNumber()
        ? depletedBufferSeconds - unexpectedDelaySecond2
        : delayConfig.thresholdSeconds.toNumber()
    const delayBlocksDeadline2 =
      calcBufferBlocks > maxDelay.delayBlocks
        ? maxDelay.delayBlocks
        : calcBufferBlocks
    const delayTimestampDeadline2 =
      calcBufferSeconds > maxDelay.delaySeconds
        ? maxDelay.delaySeconds
        : calcBufferSeconds
    expect(deadline2[0]).to.equal(futureBlock + delayBlocksDeadline2)
    expect(deadline2[1]).to.equal(futureTime + delayTimestampDeadline2)
  })

  it('can replenish buffer', async () => {
    const { bridge, sequencerInbox, batchPoster, delayConfig } =
      await setupSequencerInbox(true, true)
    const delayedInboxPending: DelayedMsgDelivered[] = []
    let delayedMessageCount = await bridge.delayedMessageCount()
    let seqReportedMessageSubCount =
      await bridge.sequencerReportedSubMessageCount()
    let delayBufferData = await sequencerInbox.buffer()
    await (
      await sequencerInbox
        .connect(batchPoster)
        [
          'addSequencerL2BatchFromBlobs(uint256,uint256,address,uint256,uint256)'
        ](
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
        [
          'addSequencerL2BatchFromBlobs(uint256,uint256,address,uint256,uint256)'
        ](
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
      ['addSequencerL2BatchFromBlobs(uint256,uint256,address,uint256,uint256)'](
        3,
        delayedMessageCount.add(1),
        ethers.constants.AddressZero,
        seqReportedMessageSubCount.add(10),
        seqReportedMessageSubCount.add(20),
        { gasLimit: 10000000 }
      )
    await expect(tx).to.be.revertedWith('DelayProofRequired')

    let nextDelayedMsg = delayedInboxPending.pop()
    await mineBlocks(delayConfig.thresholdBlocks.toNumber() - 100, 12)

    await (
      await sequencerInbox
        .connect(batchPoster)
        [
          'addSequencerL2BatchFromBlobs(uint256,uint256,address,uint256,uint256,bytes32,(uint8,address,uint64,uint64,uint256,uint256,bytes32))'
        ](
          3,
          delayedMessageCount.add(1),
          ethers.constants.AddressZero,
          seqReportedMessageSubCount.add(10),
          seqReportedMessageSubCount.add(20),
          nextDelayedMsg!.delayedAcc,
          {
            kind: nextDelayedMsg!.delayedMessage.header.kind,
            sender: nextDelayedMsg!.delayedMessage.header.sender,
            blockNumber: nextDelayedMsg!.delayedMessage.header.blockNumber,
            timestamp: nextDelayedMsg!.delayedMessage.header.timestamp,
            inboxSeqNum: nextDelayedMsg!.delayedCount,
            baseFeeL1: nextDelayedMsg!.delayedMessage.header.baseFee,
            messageDataHash:
              nextDelayedMsg!.delayedMessage.header.messageDataHash,
          },
          { gasLimit: 10000000 }
        )
    )
      .wait()
      .then(res => {
        delayedInboxPending.push(getBatchSpendingReport(res))
      })
    delayBufferData = await sequencerInbox.buffer()
    nextDelayedMsg = delayedInboxPending.pop()

    await mineBlocks(delayConfig.thresholdBlocks.toNumber() - 100, 12)

    await (
      await sequencerInbox
        .connect(batchPoster)
        [
          'addSequencerL2BatchFromBlobs(uint256,uint256,address,uint256,uint256,bytes32,(uint8,address,uint64,uint64,uint256,uint256,bytes32))'
        ](
          4,
          delayedMessageCount.add(2),
          ethers.constants.AddressZero,
          seqReportedMessageSubCount.add(20),
          seqReportedMessageSubCount.add(30),
          nextDelayedMsg!.delayedAcc,
          {
            kind: nextDelayedMsg!.delayedMessage.header.kind,
            sender: nextDelayedMsg!.delayedMessage.header.sender,
            blockNumber: nextDelayedMsg!.delayedMessage.header.blockNumber,
            timestamp: nextDelayedMsg!.delayedMessage.header.timestamp,
            inboxSeqNum: nextDelayedMsg!.delayedCount,
            baseFeeL1: nextDelayedMsg!.delayedMessage.header.baseFee,
            messageDataHash:
              nextDelayedMsg!.delayedMessage.header.messageDataHash,
          },
          { gasLimit: 10000000 }
        )
    )
      .wait()
      .then(res => {
        delayedInboxPending.push(getBatchSpendingReport(res))
        return res
      })

    const delayBufferData2 = await sequencerInbox.buffer()
    const replenishBlocks = Math.floor(
      ((nextDelayedMsg!.delayedMessage.header.blockNumber -
        delayBufferData.prevDelay.blockNumber.toNumber()) /
        delayConfig.replenishRate.periodBlocks) *
        delayConfig.replenishRate.blocksPerPeriod
    )
    const replenishSeconds = Math.floor(
      ((nextDelayedMsg!.delayedMessage.header.timestamp -
        delayBufferData.prevDelay.timestamp.toNumber()) /
        delayConfig.replenishRate.periodSeconds) *
        delayConfig.replenishRate.secondsPerPeriod
    )
    const replenishRoundOffBlocks = Math.floor(
      (nextDelayedMsg!.delayedMessage.header.blockNumber -
        delayBufferData.prevDelay.blockNumber.toNumber()) %
        delayConfig.replenishRate.periodBlocks
    )
    const replenishRoundOffSeconds = Math.floor(
      (nextDelayedMsg!.delayedMessage.header.timestamp -
        delayBufferData.prevDelay.timestamp.toNumber()) %
        delayConfig.replenishRate.periodSeconds
    )
    expect(delayBufferData2.bufferBlocks.toNumber()).to.equal(
      delayBufferData.bufferBlocks.toNumber() + replenishBlocks
    )
    expect(delayBufferData2.bufferSeconds.toNumber()).to.equal(
      delayBufferData.bufferSeconds.toNumber() + replenishSeconds
    )
    expect(delayBufferData2.roundOffBlocks.toNumber()).to.equal(
      replenishRoundOffBlocks
    )
    expect(delayBufferData2.roundOffSeconds.toNumber()).to.equal(
      replenishRoundOffSeconds
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
      (await sequencerInbox.buffer()).syncExpiryBlockNumber.toNumber()
    ).greaterThanOrEqual(blockNumber)
    expect(
      (await sequencerInbox.buffer()).syncExpiryTimestamp.toNumber()
    ).greaterThanOrEqual(blockTimestamp)
    await (
      await sequencerInbox
        .connect(batchPoster)
        [
          'addSequencerL2BatchFromBlobs(uint256,uint256,address,uint256,uint256)'
        ](
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

    await mineBlocks(delayConfig.thresholdBlocks.toNumber() - 100, 12)
    const lastDelayedMsgRead = delayedInboxPending.pop()
    const res = await (
      await sequencerInbox
        .connect(batchPoster)
        [
          'addSequencerL2BatchFromBlobs(uint256,uint256,address,uint256,uint256)'
        ](
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
        [
          'addSequencerL2BatchFromBlobs(uint256,uint256,address,uint256,uint256,bytes32,(uint8,address,uint64,uint64,uint256,uint256,bytes32),(bytes32,bytes32,bytes32))'
        ](
          2,
          delayedMessageCount.add(2),
          ethers.constants.AddressZero,
          seqReportedMessageSubCount.add(20),
          seqReportedMessageSubCount.add(30),
          lastDelayedMsgRead!.delayedAcc,
          {
            kind: lastDelayedMsgRead!.delayedMessage.header.kind,
            sender: lastDelayedMsgRead!.delayedMessage.header.sender,
            blockNumber: lastDelayedMsgRead!.delayedMessage.header.blockNumber,
            timestamp: lastDelayedMsgRead!.delayedMessage.header.timestamp,
            inboxSeqNum: lastDelayedMsgRead!.delayedCount,
            baseFeeL1: lastDelayedMsgRead!.delayedMessage.header.baseFee,
            messageDataHash:
              lastDelayedMsgRead!.delayedMessage.header.messageDataHash,
          },
          {
            beforeAcc: batchDelivered!.beforeAcc,
            dataHash: '0x' + inboxMessageDelivered.data.slice(106, 170),
            delayedAcc: batchDelivered!.delayedAcc,
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
      (await sequencerInbox.buffer()).syncExpiryBlockNumber.toNumber()
    ).greaterThanOrEqual(blockNumber)
    expect(
      (await sequencerInbox.buffer()).syncExpiryTimestamp.toNumber()
    ).greaterThanOrEqual(blockTimestamp)
    await (
      await sequencerInbox
        .connect(batchPoster)
        [
          'addSequencerL2BatchFromBlobs(uint256,uint256,address,uint256,uint256)'
        ](
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

    await mineBlocks(delayConfig.thresholdBlocks.toNumber() - 100, 12)
    await (
      await sequencerInbox
        .connect(batchPoster)
        [
          'addSequencerL2BatchFromBlobs(uint256,uint256,address,uint256,uint256)'
        ](
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
      ['addSequencerL2BatchFromBlobs(uint256,uint256,address,uint256,uint256)'](
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
        [
          'addSequencerL2BatchFromBlobs(uint256,uint256,address,uint256,uint256,bytes32,(uint8,address,uint64,uint64,uint256,uint256,bytes32))'
        ](
          2,
          delayedMessageCount.add(2),
          ethers.constants.AddressZero,
          seqReportedMessageSubCount.add(20),
          seqReportedMessageSubCount.add(30),
          firstReadMsg!.delayedAcc,
          {
            kind: firstReadMsg!.delayedMessage.header.kind,
            sender: firstReadMsg!.delayedMessage.header.sender,
            blockNumber: firstReadMsg!.delayedMessage.header.blockNumber,
            timestamp: firstReadMsg!.delayedMessage.header.timestamp,
            inboxSeqNum: firstReadMsg!.delayedCount,
            baseFeeL1: firstReadMsg!.delayedMessage.header.baseFee,
            messageDataHash:
              firstReadMsg!.delayedMessage.header.messageDataHash,
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
        [
          'addSequencerL2BatchFromBlobs(uint256,uint256,address,uint256,uint256)'
        ](
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
        [
          'addSequencerL2BatchFromBlobs(uint256,uint256,address,uint256,uint256,bytes32,(uint8,address,uint64,uint64,uint256,uint256,bytes32))'
        ](
          0,
          messagesReadOpt,
          ethers.constants.AddressZero,
          seqReportedMessageSubCountOpt,
          seqReportedMessageSubCountOpt.add(10),
          beforeDelayedAcc,
          {
            kind: 3,
            sender: delayedMsgLastRead!.delayedMessage.header.sender,
            blockNumber: delayedMsgLastRead!.delayedMessage.header.blockNumber,
            timestamp: delayedMsgLastRead!.delayedMessage.header.timestamp,
            inboxSeqNum: delayedMsgLastRead!.delayedCount,
            baseFeeL1: delayedMsgLastRead!.delayedMessage.header.baseFee,
            messageDataHash:
              delayedMsgLastRead!.delayedMessage.header.messageDataHash,
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
          'addSequencerL2BatchFromBlobs(uint256,uint256,address,uint256,uint256)'
        ](
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
        .functions[
          'addSequencerL2BatchFromBlobs(uint256,uint256,address,uint256,uint256,bytes32,(uint8,address,uint64,uint64,uint256,uint256,bytes32))'
        ](
          1,
          messagesReadOpt2.sub(1),
          ethers.constants.AddressZero,
          seqReportedMessageSubCountOpt2,
          seqReportedMessageSubCountOpt2.add(10),
          delayedMsgLastRead!.delayedAcc,
          {
            kind: delayedMsgLastRead!.delayedMessage.header.kind,
            sender: delayedMsgLastRead!.delayedMessage.header.sender,
            blockNumber: delayedMsgLastRead!.delayedMessage.header.blockNumber,
            timestamp: delayedMsgLastRead!.delayedMessage.header.timestamp,
            inboxSeqNum: delayedMsgLastRead!.delayedCount,
            baseFeeL1: delayedMsgLastRead!.delayedMessage.header.baseFee,
            messageDataHash:
              delayedMsgLastRead!.delayedMessage.header.messageDataHash,
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
          'addSequencerL2BatchFromBlobs(uint256,uint256,address,uint256,uint256)'
        ](
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
        .functions[
          'addSequencerL2BatchFromBlobs(uint256,uint256,address,uint256,uint256,bytes32,(uint8,address,uint64,uint64,uint256,uint256,bytes32),(bytes32,bytes32,bytes32))'
        ](
          3,
          messagesReadOpt2.add(1),
          ethers.constants.AddressZero,
          seqReportedMessageSubCountOpt2.add(20),
          seqReportedMessageSubCountOpt2.add(30),
          lastRead!.delayedAcc,
          {
            kind: lastRead!.delayedMessage.header.kind,
            sender: lastRead!.delayedMessage.header.sender,
            blockNumber: lastRead!.delayedMessage.header.blockNumber,
            timestamp: lastRead!.delayedMessage.header.timestamp,
            inboxSeqNum: lastRead!.delayedCount,
            baseFeeL1: lastRead!.delayedMessage.header.baseFee,
            messageDataHash: lastRead!.delayedMessage.header.messageDataHash,
          },
          {
            beforeAcc: batchDelivered!.beforeAcc,
            dataHash: '0x' + inboxMessageDelivered.data.slice(106, 170),
            delayedAcc: batchDelivered!.delayedAcc,
          },
          { gasLimit: 10000000 }
        )
    ).wait()

    //console.log('start sync',res11.gasUsed.toNumber() - res3.gasUsed.toNumber())
    //console.log('resync', res11.gasUsed.toNumber() - res5.gasUsed.toNumber())
    //console.log('synced', res11.gasUsed.toNumber() - res4.gasUsed.toNumber())
  })
})
