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
import {
  Block,
  JsonRpcProvider,
  TransactionReceipt,
} from '@ethersproject/providers'
import { expect } from 'chai'
import {
  Bridge,
  Bridge__factory,
  Inbox,
  Inbox__factory,
  MessageTester,
  MessageTester__factory,
  RollupMock__factory,
  SequencerInbox__factory,
  TransparentUpgradeableProxy__factory,
} from '../../build/types'
import { applyAlias } from './utils'
import { Event } from '@ethersproject/contracts'
import { Interface } from '@ethersproject/abi'
import {
  BridgeInterface,
  MessageDeliveredEvent,
} from '../../build/types/src/bridge/Bridge'
import { Signer, Wallet, constants, utils } from 'ethers'
import { keccak256, solidityKeccak256, solidityPack } from 'ethers/lib/utils'
import { Toolkit4844 } from './toolkit4844'
import {
  SequencerBatchDeliveredEvent,
  SequencerInbox,
} from '../../build/types/src/bridge/SequencerInbox'
import { execSync } from 'child_process'

const mineBlocks = async (
  wallet: Wallet,
  count: number,
  timeDiffPerBlock = 14
) => {
  const block = (await network.provider.send('eth_getBlockByNumber', [
    'latest',
    false,
  ])) as Block
  let timestamp = BigNumber.from(block.timestamp).toNumber()
  for (let i = 0; i < count; i++) {
    timestamp = timestamp + timeDiffPerBlock
    await (
      await wallet.sendTransaction({ to: constants.AddressZero, value: 1 })
    ).wait()
  }
}

describe('SequencerInbox', async () => {
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
      baseFeeL1: baseFeeL1,
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

  const fundAccounts = async (
    wallet: Wallet,
    length: number,
    amount: BigNumber
  ): Promise<Wallet[]> => {
    let key = wallet.privateKey
    const wallets: Wallet[] = []

    console.log('a10')

    for (let index = 0; index < length; index++) {
      console.log('a11', index)
      key = keccak256(key)
      const nextWallet = new Wallet(key).connect(wallet.provider)
      if ((await nextWallet.getBalance()).lt(amount)) {
        console.log('a12', index)
        await (
          await wallet.sendTransaction({
            to: nextWallet.address,
            value: amount,
          })
        ).wait()
        console.log('a13', index)
      }
      wallets.push(nextWallet)
    }

    return wallets
  }

  const connectAddreses = (
    user: Wallet,
    deployer: Wallet,
    batchPoster: Wallet,
    addresses: {
      user: string
      bridge: string
      inbox: string
      sequencerInbox: string
      messageTester: string
      batchPoster: string
    }
  ) => {
    return {
      user,
      batchPoster,
      bridge: Bridge__factory.connect(addresses.bridge, user),
      inbox: Inbox__factory.connect(addresses.inbox, user),
      sequencerInbox: SequencerInbox__factory.connect(
        addresses.sequencerInbox,
        user
      ),
      messageTester: MessageTester__factory.connect(
        addresses.messageTester,
        deployer
      ),
    }
  }

  const setupSequencerInbox = async (
    fundingWallet: Wallet,
    maxDelayBlocks = 10,
    maxDelayTime = 0
  ) => {
    console.log('a1a')
    const accounts = await fundAccounts(fundingWallet, 5, utils.parseEther('1'))
    console.log('a2')

    const admin = accounts[0]
    const adminAddr = await admin.getAddress()
    const user = accounts[1]
    const deployer = accounts[2]
    const rollupOwner = accounts[3]
    const batchPoster = accounts[4]

    // update the addresses below and uncomment to avoid redeploying
    // return connectAddreses(user, deployer, batchPoster, {
    //   user: '0x870204e93ca485a6676E264EB0d7df4cD0246203',
    //   bridge: '0x960aB1A4858a1CBd3cf75E9a6a16A3C40E1D231e',
    //   inbox: '0xe763a2bB11c38aB41735D7bB24E98a0662687478',
    //   sequencerInbox: '0xe187f8f751a4d5860d96f99c6D1e1f5c557128ac',
    //   messageTester: '0xc1D13079aaC7Bbc399ca14308206d5B87Ae8F3BA',
    //   batchPoster: '0x328375c90F01Dcb114888DA36e3832F69Ad0BB57',
    // })

    const rollupMockFac = new RollupMock__factory(deployer)
    const rollupMock = await rollupMockFac.deploy(
      await rollupOwner.getAddress()
    )
    console.log('a3')

    const sequencerInboxFac = new SequencerInbox__factory(deployer)
    const seqInboxTemplate = await sequencerInboxFac.deploy(117964)

    const inboxFac = new Inbox__factory(deployer)
    const inboxTemplate = await inboxFac.deploy(117964)

    const bridgeFac = new Bridge__factory(deployer)
    const bridgeTemplate = await bridgeFac.deploy()
    await rollupMock.deployed()
    await seqInboxTemplate.deployed()
    await inboxTemplate.deployed()
    await bridgeTemplate.deployed()

    const transparentUpgradeableProxyFac =
      new TransparentUpgradeableProxy__factory(deployer)

    const bridgeProxy = await transparentUpgradeableProxyFac.deploy(
      bridgeTemplate.address,
      adminAddr,
      '0x'
    )

    const sequencerInboxProxy = await transparentUpgradeableProxyFac.deploy(
      seqInboxTemplate.address,
      adminAddr,
      '0x'
    )

    const inboxProxy = await transparentUpgradeableProxyFac.deploy(
      inboxTemplate.address,
      adminAddr,
      '0x'
    )
    await bridgeProxy.deployed()
    await sequencerInboxProxy.deployed()
    await inboxProxy.deployed()
    const dataHashReader = await Toolkit4844.deployDataHashReader(fundingWallet)

    const bridge = await bridgeFac.attach(bridgeProxy.address).connect(user)
    const bridgeAdmin = await bridgeFac
      .attach(bridgeProxy.address)
      .connect(rollupOwner)

    const sequencerInbox = await sequencerInboxFac
      .attach(sequencerInboxProxy.address)
      .connect(user)
    const inbox = await inboxFac.attach(inboxProxy.address).connect(user)

    await (await bridgeAdmin.initialize(rollupMock.address)).wait()
    await (
      await sequencerInbox.initialize(
        bridgeProxy.address,
        {
          delayBlocks: maxDelayBlocks,
          delaySeconds: maxDelayTime,
          futureBlocks: 10,
          futureSeconds: 3000,
        },
        dataHashReader.address
      )
    ).wait()
    await (
      await sequencerInbox
        .connect(rollupOwner)
        .setIsBatchPoster(await batchPoster.getAddress(), true)
    ).wait()
    await (
      await inbox.initialize(bridgeProxy.address, sequencerInbox.address)
    ).wait()

    await (await bridgeAdmin.setDelayedInbox(inbox.address, true)).wait()

    await (await bridgeAdmin.setSequencerInbox(sequencerInbox.address)).wait()

    const messageTester = await new MessageTester__factory(deployer).deploy()
    await messageTester.deployed()

    const res = {
      user,
      bridge: bridge,
      inbox: inbox,
      sequencerInbox: sequencerInbox,
      messageTester,
      batchPoster,
    }

    // comment this in to print the addresses that can then be re-used to avoid redeployment
    // let consoleRes: { [index: string]: string } = {}
    // Object.entries(res).forEach(r => (consoleRes[r[0]] = r[1].address))
    // console.log(consoleRes)

    return res
  }

  it('can send normal batch', async () => {
    const privKey =
      'cb5790da63720727af975f42c79f69918580209889225fa7128c92402a6d3a65'
    const prov = new JsonRpcProvider('http://localhost:8545')
    const wallet = new Wallet(privKey).connect(prov)

    const { user, inbox, bridge, messageTester, sequencerInbox, batchPoster } =
      await setupSequencerInbox(wallet)

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

    const subMessageCount = await bridge.sequencerReportedSubMessageCount()
    const batchSendTx = await sequencerInbox
      .connect(batchPoster)
      [
        'addSequencerL2BatchFromOrigin(uint256,bytes,uint256,address,uint256,uint256)'
      ](
        await bridge.sequencerMessageCount(),
        '0x0142',
        await bridge.delayedMessageCount(),
        constants.AddressZero,
        subMessageCount,
        subMessageCount.add(1)
      )

    await batchSendTx.wait()
  })

  it('can send blob batch', async () => {
    const privKey =
      'cb5790da63720727af975f42c79f69918580209889225fa7128c92402a6d3a65'
    const prov = new JsonRpcProvider('http://localhost:8545')
    console.log('a')
    console.log(
      execSync(
        `curl -X POST -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","id":45678,"method":"eth_chainId","params":[]}' 'http://localhost:8545'`
      )
    )
    console.log(
      execSync(
        `curl -X POST -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","id":45678,"method":"eth_chainId","params":[]}' 'http://localhost:8547'`
      )
    )
    console.log(await prov.getNetwork())
    const wallet = new Wallet(privKey).connect(prov)

    const { user, inbox, bridge, messageTester, sequencerInbox, batchPoster } =
      await setupSequencerInbox(wallet)

    console.log('b')

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
    console.log('c')

    const subMessageCount = await bridge.sequencerReportedSubMessageCount()
    const afterDelayedMessagesRead = await bridge.delayedMessageCount()
    const sequenceNumber = await bridge.sequencerMessageCount()

    const txHash = await Toolkit4844.sendBlobTx(
      batchPoster.privateKey.substring(2),
      sequencerInbox.address,
      ['0x0142', '0x0143'],
      sequencerInbox.interface.encodeFunctionData(
        'addSequencerL2BatchFromBlob',
        [
          sequenceNumber,
          '0x04',
          afterDelayedMessagesRead,
          constants.AddressZero,
          subMessageCount,
          subMessageCount.add(1),
        ]
      )
    )
    console.log('d')

    const batchSendTx = await Toolkit4844.getTx(txHash)
    const blobHashes = (batchSendTx as any)['blobVersionedHashes'] as string[]
    const batchSendReceipt = await Toolkit4844.getTxReceipt(txHash)
    const { timestamp: blockTimestamp, number: blockNumber } =
      await wallet.provider.getBlock(batchSendReceipt.blockNumber)

    const timeBounds = await getTimeBounds(
      blockNumber,
      blockTimestamp,
      sequencerInbox
    )
    const dataHash = formDataBlobHash(
      timeBounds,
      afterDelayedMessagesRead.toNumber(),
      blobHashes
    )

    const batchDeliveredEvent = batchSendReceipt.logs
      .filter(
        (b: any) =>
          b.address.toLowerCase() === sequencerInbox.address.toLowerCase() &&
          b.topics[0] ===
            sequencerInbox.interface.getEventTopic('SequencerBatchDelivered')
      )
      .map(
        (l: any) => sequencerInbox.interface.parseLog(l).args
      )[0] as SequencerBatchDeliveredEvent['args']

    const seqMessageCountAfter = (
      await bridge.sequencerMessageCount()
    ).toNumber()
    const delayedMessageCountAfter = (
      await bridge.delayedMessageCount()
    ).toNumber()

    const beforeAcc =
      seqMessageCountAfter > 1
        ? await bridge.sequencerInboxAccs(seqMessageCountAfter - 2)
        : constants.HashZero
    expect(batchDeliveredEvent.beforeAcc, 'before acc').to.eq(beforeAcc)
    const delayedAcc =
      delayedMessageCountAfter > 0
        ? await bridge.delayedInboxAccs(delayedMessageCountAfter - 1)
        : constants.HashZero
    expect(batchDeliveredEvent.delayedAcc, 'delayed acc').to.eq(delayedAcc)
    const afterAcc = solidityKeccak256(
      ['bytes32', 'bytes32', 'bytes32'],
      [beforeAcc, dataHash, delayedAcc]
    )
    expect(batchDeliveredEvent.afterAcc, 'after acc').to.eq(afterAcc)
  })

  const getTimeBounds = async (
    blockNumber: number,
    blockTimestamp: number,
    sequencerInbox: SequencerInbox
  ): Promise<{
    maxBlock: number
    minBlocks: number
    minTimestamp: number
    maxTimestamp: number
  }> => {
    const maxTimeVariation = await sequencerInbox.maxTimeVariation()
    return {
      minBlocks:
        blockNumber > maxTimeVariation.delayBlocks.toNumber()
          ? blockNumber - maxTimeVariation.delayBlocks.toNumber()
          : 0,
      maxBlock: blockNumber + maxTimeVariation.futureBlocks.toNumber(),
      minTimestamp:
        blockTimestamp > maxTimeVariation.delaySeconds.toNumber()
          ? blockTimestamp - maxTimeVariation.delaySeconds.toNumber()
          : 0,
      maxTimestamp: blockTimestamp + maxTimeVariation.futureSeconds.toNumber(),
    }
  }

  const formDataBlobHash = (
    timeBounds: {
      maxBlock: number
      minBlocks: number
      minTimestamp: number
      maxTimestamp: number
    },
    afterDelayedMessagesRead: number,
    blobHashes: string[]
  ) => {
    const header = solidityPack(
      ['uint64', 'uint64', 'uint64', 'uint64', 'uint64'],
      [
        timeBounds.minTimestamp,
        timeBounds.maxTimestamp,
        timeBounds.minBlocks,
        timeBounds.maxBlock,
        afterDelayedMessagesRead,
      ]
    )

    return keccak256(
      solidityPack(
        ['bytes', 'bytes'],
        [header, solidityPack(['bytes32[]'], [blobHashes])]
      )
    )
  }
})
