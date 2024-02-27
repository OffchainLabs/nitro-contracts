import { ethers } from 'hardhat'
import { BigNumber } from '@ethersproject/bignumber'
import { data } from './batchData.json'
import { DelayedMsgDelivered } from './types'

import {
  getSequencerBatchDeliveredEvents,
  getBatchSpendingReport,
  sendDelayedTx,
  setupSequencerInbox,
  getInboxMessageDeliveredEvents,
} from './testHelpers'

describe('SequencerInboxForceInclude', async () => {
  it('can add batch', async () => {
    const { user, inbox, bridge, messageTester, sequencerInbox, batchPoster } =
      await setupSequencerInbox()
    let delayedInboxPending: DelayedMsgDelivered[] = []
    const setupOpt = await setupSequencerInbox(true)

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
    const messagesReadOpt = await setupOpt.bridge.delayedMessageCount()
    const totalDelayedMessagesRead = (
      await setupOpt.bridge.totalDelayedMessagesRead()
    ).toNumber()

    const beforeDelayedAcc =
      totalDelayedMessagesRead == 0
        ? ethers.constants.HashZero
        : await setupOpt.bridge.delayedInboxAccs(totalDelayedMessagesRead - 1)

    const seqReportedMessageSubCountOpt =
      await setupOpt.bridge.sequencerReportedSubMessageCount()

    // pass proof of the last read delayed message
    let delayedMsgLastRead = delayedInboxPending[delayedInboxPending.length - 1]
    delayedInboxPending = []
    await (
      await setupOpt.sequencerInbox
        .connect(setupOpt.batchPoster)
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

    const messagesReadOpt2 = await setupOpt.bridge.delayedMessageCount()
    const seqReportedMessageSubCountOpt2 =
      await setupOpt.bridge.sequencerReportedSubMessageCount()

    // start parole
    // pass delayed message proof
    // read 1 message
    delayedMsgLastRead = delayedInboxPending[delayedInboxPending.length - 2]
    delayedInboxPending = [delayedInboxPending[delayedInboxPending.length - 1]]
    const res3 = await (
      await setupOpt.sequencerInbox
        .connect(setupOpt.batchPoster)
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
      await setupOpt.sequencerInbox
        .connect(setupOpt.batchPoster)
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
      await setupOpt.sequencerInbox
        .connect(setupOpt.batchPoster)
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
    //console.log('renew sync', res11.gasUsed.toNumber() - res5.gasUsed.toNumber())
    //console.log('synced', res11.gasUsed.toNumber() - res4.gasUsed.toNumber())
  })
})
