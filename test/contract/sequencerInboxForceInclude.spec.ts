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

import { ethers } from 'hardhat'
import { BigNumber } from '@ethersproject/bignumber'
import { expect } from 'chai'
import { data } from './batchData.json'

import {
  mineBlocks,
  forceIncludeMessages,
  sendDelayedTx,
  setupSequencerInbox,
} from './testHelpers'

describe('SequencerInboxForceInclude', async () => {
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

    await mineBlocks(maxTimeVariation[0].toNumber())

    await forceIncludeMessages(
      sequencerInbox,
      delayedTx.inboxAccountLength,
      delayedTx.delayedMsg
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
    await mineBlocks(maxTimeVariation[0].toNumber())

    await forceIncludeMessages(
      sequencerInbox,
      delayedTx.inboxAccountLength,
      delayedTx.delayedMsg
    )
    await forceIncludeMessages(
      sequencerInbox,
      delayedTx2.inboxAccountLength,
      delayedTx2.delayedMsg
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
    await mineBlocks(maxTimeVariation[0].toNumber())

    await forceIncludeMessages(
      sequencerInbox,
      delayedTx3.inboxAccountLength,
      delayedTx3.delayedMsg
    )
  })

  it('cannot include before max block delay', async () => {
    const { user, inbox, bridge, messageTester, sequencerInbox } =
      await setupSequencerInbox(false, {
        delayBlocks: 10,
        delaySeconds: 100,
        futureBlocks: 0,
        futureSeconds: 100,
      })
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
    await mineBlocks(maxTimeVariation[0].toNumber() - 1, 5)

    await forceIncludeMessages(
      sequencerInbox,
      delayedTx.inboxAccountLength,
      delayedTx.delayedMsg,
      'ForceIncludeBlockTooSoon'
    )
  })

  it('cannot include before max time delay', async () => {
    const { user, inbox, bridge, messageTester, sequencerInbox } =
      await setupSequencerInbox(false, {
        delayBlocks: 10,
        delaySeconds: 100,
        futureBlocks: 0,
        futureSeconds: 100,
      })
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
    await mineBlocks(maxTimeVariation[0].toNumber() + 1, 5)

    await forceIncludeMessages(
      sequencerInbox,
      delayedTx.inboxAccountLength,
      delayedTx.delayedMsg,
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
