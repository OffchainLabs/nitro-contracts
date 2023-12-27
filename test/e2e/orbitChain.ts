import {
  L1ToL2MessageGasEstimator,
  L1ToL2MessageStatus,
  L1TransactionReceipt,
  L2Network,
  L2TransactionReceipt,
  addCustomNetwork,
} from '@arbitrum/sdk'
import { getBaseFee } from '@arbitrum/sdk/dist/lib/utils/lib'
import { JsonRpcProvider } from '@ethersproject/providers'
import { expect } from 'chai'
import { ethers, Wallet } from '@arbitrum/sdk/node_modules/ethers'
import {
  ArbSys__factory,
  ERC20,
  ERC20Inbox__factory,
  ERC20__factory,
  EthVault__factory,
  IERC20Bridge__factory,
  IInbox__factory,
  Inbox__factory,
  RollupCore__factory,
} from '../../build/types'
import { getLocalNetworks, sleep } from '../../scripts/testSetup'
import { applyAlias } from '../contract/utils'
import { BigNumber, ContractTransaction } from 'ethers'

const LOCALHOST_L2_RPC = 'http://localhost:8547'
const LOCALHOST_L3_RPC = 'http://localhost:3347'

let l1Provider: JsonRpcProvider
let l2Provider: JsonRpcProvider

let l2Network: L2Network
let userL1Wallet: Wallet
let userL2Wallet: Wallet
let nativeToken: ERC20 | undefined
const excessFeeRefundAddress = Wallet.createRandom().address
const callValueRefundAddress = Wallet.createRandom().address

describe('Orbit Chain', () => {
  // setup providers and connect deployed contracts
  before(async function () {
    const { l1Network, l2Network: coreL2Network } = await getLocalNetworks(
      LOCALHOST_L2_RPC,
      LOCALHOST_L3_RPC
    )
    l2Network = {
      ...coreL2Network,
      tokenBridge: {
        l1CustomGateway: '',
        l1ERC20Gateway: '',
        l1GatewayRouter: '',
        l1MultiCall: '',
        l1ProxyAdmin: '',
        l1Weth: '',
        l1WethGateway: '',

        l2CustomGateway: '',
        l2ERC20Gateway: '',
        l2GatewayRouter: '',
        l2Multicall: '',
        l2ProxyAdmin: '',
        l2Weth: '',
        l2WethGateway: '',
      },
    }
    addCustomNetwork({
      customL1Network: l1Network,
      customL2Network: l2Network,
    })

    l1Provider = new JsonRpcProvider(LOCALHOST_L2_RPC)
    l2Provider = new JsonRpcProvider(LOCALHOST_L3_RPC)
    userL1Wallet = new ethers.Wallet(
      ethers.utils.sha256(
        ethers.utils.toUtf8Bytes('user_token_bridge_deployer')
      ),
      l1Provider
    )
    userL2Wallet = new ethers.Wallet(userL1Wallet.privateKey, l2Provider)

    const nativeTokenAddress = await _getFeeToken(
      l2Network.ethBridge.inbox,
      l1Provider
    )
    nativeToken =
      nativeTokenAddress === ethers.constants.AddressZero
        ? undefined
        : ERC20__factory.connect(nativeTokenAddress, l1Provider)
  })

  it('should have deployed bridge contracts', async function () {
    // get rollup as entry point
    const rollup = RollupCore__factory.connect(
      l2Network.ethBridge.rollup,
      l1Provider
    )

    // check contract refs are properly set
    expect(rollup.address).to.be.eq(l2Network.ethBridge.rollup)
    expect((await rollup.sequencerInbox()).toLowerCase()).to.be.eq(
      l2Network.ethBridge.sequencerInbox
    )
    expect(await rollup.outbox()).to.be.eq(l2Network.ethBridge.outbox)
    expect((await rollup.inbox()).toLowerCase()).to.be.eq(
      l2Network.ethBridge.inbox
    )
    expect((await rollup.bridge()).toLowerCase()).to.be.eq(
      l2Network.ethBridge.bridge
    )
  })

  it('can deposit native asset to L2', async function () {
    // snapshot state before deposit
    const userL2Balance = await l2Provider.getBalance(userL2Wallet.address)
    let userL1NativeAssetBalance: BigNumber
    let bridgeL1NativeAssetBalance: BigNumber

    if (nativeToken) {
      userL1NativeAssetBalance = await nativeToken.balanceOf(
        userL1Wallet.address
      )
      bridgeL1NativeAssetBalance = await nativeToken.balanceOf(
        l2Network.ethBridge.bridge
      )
    } else {
      userL1NativeAssetBalance = await l1Provider.getBalance(
        userL1Wallet.address
      )
      bridgeL1NativeAssetBalance = await l1Provider.getBalance(
        l2Network.ethBridge.bridge
      )
    }

    /// bridge native asset
    const amountToDeposit = ethers.utils.parseEther('0.35')

    let depositTx
    if (nativeToken) {
      await (
        await nativeToken
          .connect(userL1Wallet)
          .approve(l2Network.ethBridge.inbox, amountToDeposit)
      ).wait()
      depositTx = await ERC20Inbox__factory.connect(
        l2Network.ethBridge.inbox,
        userL1Wallet
      ).depositERC20(amountToDeposit)
    } else {
      depositTx = await Inbox__factory.connect(
        l2Network.ethBridge.inbox,
        userL1Wallet
      )['depositEth()']({ value: amountToDeposit })
    }

    // wait for deposit to be processed
    const depositRec = await L1TransactionReceipt.monkeyPatchEthDepositWait(
      depositTx
    ).wait()
    const l2Result = await depositRec.waitForL2(l2Provider)
    expect(l2Result.complete).to.be.true

    // check user balance increased on L2 and decreased on L1
    let userL1NativeAssetBalanceAfter: BigNumber
    if (nativeToken) {
      userL1NativeAssetBalanceAfter = await nativeToken.balanceOf(
        userL1Wallet.address
      )
    } else {
      userL1NativeAssetBalanceAfter = await l1Provider.getBalance(
        userL1Wallet.address
      )
    }
    expect(
      userL1NativeAssetBalance.sub(userL1NativeAssetBalanceAfter)
    ).to.be.gte(amountToDeposit)

    const userL2BalanceAfter = await l2Provider.getBalance(userL2Wallet.address)
    expect(userL2BalanceAfter.sub(userL2Balance)).to.be.eq(amountToDeposit)

    let bridgeL1NativeAssetBalanceAfter
    if (nativeToken) {
      bridgeL1NativeAssetBalanceAfter = await nativeToken.balanceOf(
        l2Network.ethBridge.bridge
      )
    } else {
      bridgeL1NativeAssetBalanceAfter = await l1Provider.getBalance(
        l2Network.ethBridge.bridge
      )
    }

    // bridge escrow increased
    expect(
      bridgeL1NativeAssetBalanceAfter.sub(bridgeL1NativeAssetBalance)
    ).to.be.eq(amountToDeposit)
  })

  it('can issue retryable ticket (no calldata)', async function () {
    // snapshot state before deposit
    const userL2Balance = await l2Provider.getBalance(userL2Wallet.address)
    const aliasL2Balance = await l2Provider.getBalance(
      applyAlias(userL2Wallet.address)
    )
    const excessFeeReceiverBalance = await l2Provider.getBalance(
      excessFeeRefundAddress
    )
    const callValueRefundReceiverBalance = await l2Provider.getBalance(
      callValueRefundAddress
    )

    let userL1NativeAssetBalance: BigNumber
    let bridgeL1NativeAssetBalance: BigNumber
    if (nativeToken) {
      userL1NativeAssetBalance = await nativeToken.balanceOf(
        userL1Wallet.address
      )
      bridgeL1NativeAssetBalance = await nativeToken.balanceOf(
        l2Network.ethBridge.bridge
      )
    } else {
      userL1NativeAssetBalance = await l1Provider.getBalance(
        userL1Wallet.address
      )
      bridgeL1NativeAssetBalance = await l1Provider.getBalance(
        l2Network.ethBridge.bridge
      )
    }

    //// retryables params

    const to = userL1Wallet.address
    const l2CallValue = ethers.utils.parseEther('0.21')
    const data = '0x'

    const l1ToL2MessageGasEstimate = new L1ToL2MessageGasEstimator(l2Provider)
    const retryableParams = await l1ToL2MessageGasEstimate.estimateAll(
      {
        from: userL1Wallet.address,
        to: to,
        l2CallValue: l2CallValue,
        excessFeeRefundAddress: excessFeeRefundAddress,
        callValueRefundAddress: callValueRefundAddress,
        data: data,
      },
      await getBaseFee(l1Provider),
      l1Provider
    )

    const tokenTotalFeeAmount = retryableParams.deposit
    const gasLimit = retryableParams.gasLimit
    const maxFeePerGas = retryableParams.maxFeePerGas
    const maxSubmissionCost = retryableParams.maxSubmissionCost

    /// deposit 37 tokens using retryable
    let retryableTx: ContractTransaction
    if (nativeToken) {
      await (
        await nativeToken
          .connect(userL1Wallet)
          .approve(l2Network.ethBridge.inbox, tokenTotalFeeAmount)
      ).wait()

      retryableTx = await ERC20Inbox__factory.connect(
        l2Network.ethBridge.inbox,
        userL1Wallet
      )
        .connect(userL1Wallet)
        .createRetryableTicket(
          to,
          l2CallValue,
          maxSubmissionCost,
          excessFeeRefundAddress,
          callValueRefundAddress,
          gasLimit,
          maxFeePerGas,
          tokenTotalFeeAmount,
          data
        )
    } else {
      retryableTx = await Inbox__factory.connect(
        l2Network.ethBridge.inbox,
        userL1Wallet
      )
        .connect(userL1Wallet)
        .createRetryableTicket(
          to,
          l2CallValue,
          maxSubmissionCost,
          excessFeeRefundAddress,
          callValueRefundAddress,
          gasLimit,
          maxFeePerGas,
          data,
          { value: retryableParams.deposit }
        )
    }

    // wait for L2 msg to be executed
    await waitOnL2Msg(retryableTx)

    // check balances after retryable is processed
    let userL1TokenAfter, bridgeL1TokenAfter: BigNumber
    if (nativeToken) {
      userL1TokenAfter = await nativeToken.balanceOf(userL1Wallet.address)

      bridgeL1TokenAfter = await nativeToken.balanceOf(
        l2Network.ethBridge.bridge
      )
    } else {
      userL1TokenAfter = await l1Provider.getBalance(userL1Wallet.address)

      bridgeL1TokenAfter = await l1Provider.getBalance(
        l2Network.ethBridge.bridge
      )
    }
    expect(userL1NativeAssetBalance.sub(userL1TokenAfter)).to.be.gte(
      tokenTotalFeeAmount
    )
    expect(bridgeL1TokenAfter.sub(bridgeL1NativeAssetBalance)).to.be.eq(
      tokenTotalFeeAmount
    )

    const userL2After = await l2Provider.getBalance(userL2Wallet.address)
    expect(userL2After.sub(userL2Balance)).to.be.eq(l2CallValue)

    const aliasL2BalanceAfter = await l2Provider.getBalance(
      applyAlias(userL2Wallet.address)
    )
    expect(aliasL2BalanceAfter).to.be.eq(aliasL2Balance)

    const excessFeeReceiverBalanceAfter = await l2Provider.getBalance(
      excessFeeRefundAddress
    )
    expect(excessFeeReceiverBalanceAfter).to.be.gte(excessFeeReceiverBalance)

    const callValueRefundReceiverBalanceAfter = await l2Provider.getBalance(
      callValueRefundAddress
    )
    expect(callValueRefundReceiverBalanceAfter).to.be.eq(
      callValueRefundReceiverBalance
    )
  })

  it('can issue retryable ticket', async function () {
    // deploy contract on L2 which will be retryable's target
    const ethVaultContract = await new EthVault__factory(
      userL2Wallet.connect(l2Provider)
    ).deploy()
    await ethVaultContract.deployed()

    // snapshot state before retryable
    let userL1NativeAssetBalance, bridgeL1NativeAssetBalance: BigNumber
    if (nativeToken) {
      userL1NativeAssetBalance = await nativeToken.balanceOf(
        userL1Wallet.address
      )
      bridgeL1NativeAssetBalance = await nativeToken.balanceOf(
        l2Network.ethBridge.bridge
      )
    } else {
      userL1NativeAssetBalance = await l1Provider.getBalance(
        userL1Wallet.address
      )
      bridgeL1NativeAssetBalance = await l1Provider.getBalance(
        l2Network.ethBridge.bridge
      )
    }

    const userL2Balance = await l2Provider.getBalance(userL2Wallet.address)
    const aliasL2Balance = await l2Provider.getBalance(
      applyAlias(userL2Wallet.address)
    )

    const excessFeeReceiverBalance = await l2Provider.getBalance(
      excessFeeRefundAddress
    )
    const callValueRefundReceiverBalance = await l2Provider.getBalance(
      callValueRefundAddress
    )

    //// retryables params

    const to = ethVaultContract.address
    const l2CallValue = ethers.utils.parseEther('0.27')
    // calldata -> change 'version' field to 11
    const newValue = 11
    const data = new ethers.utils.Interface([
      'function setVersion(uint256 _version)',
    ]).encodeFunctionData('setVersion', [newValue])

    const l1ToL2MessageGasEstimate = new L1ToL2MessageGasEstimator(l2Provider)
    const retryableParams = await l1ToL2MessageGasEstimate.estimateAll(
      {
        from: userL1Wallet.address,
        to: to,
        l2CallValue: l2CallValue,
        excessFeeRefundAddress: excessFeeRefundAddress,
        callValueRefundAddress: callValueRefundAddress,
        data: data,
      },
      await getBaseFee(l1Provider),
      l1Provider
    )

    const tokenTotalFeeAmount = retryableParams.deposit
    const gasLimit = retryableParams.gasLimit
    const maxFeePerGas = retryableParams.maxFeePerGas
    const maxSubmissionCost = retryableParams.maxSubmissionCost

    /// execute retryable
    let retryableTx: ContractTransaction
    if (nativeToken) {
      await (
        await nativeToken
          .connect(userL1Wallet)
          .approve(l2Network.ethBridge.inbox, tokenTotalFeeAmount)
      ).wait()

      retryableTx = await ERC20Inbox__factory.connect(
        l2Network.ethBridge.inbox,
        userL1Wallet
      )
        .connect(userL1Wallet)
        .createRetryableTicket(
          to,
          l2CallValue,
          maxSubmissionCost,
          excessFeeRefundAddress,
          callValueRefundAddress,
          gasLimit,
          maxFeePerGas,
          tokenTotalFeeAmount,
          data
        )
    } else {
      retryableTx = await Inbox__factory.connect(
        l2Network.ethBridge.inbox,
        userL1Wallet
      )
        .connect(userL1Wallet)
        .createRetryableTicket(
          to,
          l2CallValue,
          maxSubmissionCost,
          excessFeeRefundAddress,
          callValueRefundAddress,
          gasLimit,
          maxFeePerGas,
          data,
          { value: retryableParams.deposit }
        )
    }

    // wait for L2 msg to be executed
    await waitOnL2Msg(retryableTx)

    // check balances after retryable is processed
    let userL1TokenAfter, bridgeL1TokenAfter: BigNumber
    if (nativeToken) {
      userL1TokenAfter = await nativeToken.balanceOf(userL1Wallet.address)

      bridgeL1TokenAfter = await nativeToken.balanceOf(
        l2Network.ethBridge.bridge
      )
    } else {
      userL1TokenAfter = await l1Provider.getBalance(userL1Wallet.address)

      bridgeL1TokenAfter = await l1Provider.getBalance(
        l2Network.ethBridge.bridge
      )
    }
    expect(userL1NativeAssetBalance.sub(userL1TokenAfter)).to.be.gte(
      tokenTotalFeeAmount
    )
    expect(bridgeL1TokenAfter.sub(bridgeL1NativeAssetBalance)).to.be.eq(
      tokenTotalFeeAmount
    )

    const userL2After = await l2Provider.getBalance(userL2Wallet.address)
    expect(userL2After).to.be.eq(userL2Balance)

    const ethVaultBalanceAfter = await l2Provider.getBalance(
      ethVaultContract.address
    )
    expect(ethVaultBalanceAfter).to.be.eq(l2CallValue)

    const ethVaultVersion = await ethVaultContract.version()
    expect(ethVaultVersion).to.be.eq(newValue)

    const aliasL2BalanceAfter = await l2Provider.getBalance(
      applyAlias(userL1Wallet.address)
    )
    expect(aliasL2BalanceAfter).to.be.eq(aliasL2Balance)

    const excessFeeReceiverBalanceAfter = await l2Provider.getBalance(
      excessFeeRefundAddress
    )
    expect(excessFeeReceiverBalanceAfter).to.be.gte(excessFeeReceiverBalance)

    const callValueRefundReceiverBalanceAfter = await l2Provider.getBalance(
      callValueRefundAddress
    )
    expect(callValueRefundReceiverBalanceAfter).to.be.eq(
      callValueRefundReceiverBalance
    )
  })

  xit('can withdraw funds from L2 to L1', async function () {
    // snapshot state before issuing retryable
    let userL1NativeAssetBalance: BigNumber
    let bridgeL1NativeAssetBalance: BigNumber
    if (nativeToken) {
      userL1NativeAssetBalance = await nativeToken.balanceOf(
        userL1Wallet.address
      )
      bridgeL1NativeAssetBalance = await nativeToken.balanceOf(
        l2Network.ethBridge.bridge
      )
    } else {
      userL1NativeAssetBalance = await l1Provider.getBalance(
        userL1Wallet.address
      )
      bridgeL1NativeAssetBalance = await l1Provider.getBalance(
        l2Network.ethBridge.bridge
      )
    }

    const userL2Balance = await l2Provider.getBalance(userL2Wallet.address)

    /// send L2 to L1 TX
    const arbSys = ArbSys__factory.connect(
      '0x0000000000000000000000000000000000000064',
      l2Provider
    )
    const withdrawAmount = ethers.utils.parseEther('0.11')
    const withdrawTx = await arbSys
      .connect(userL2Wallet)
      .sendTxToL1(userL1Wallet.address, '0x', {
        value: withdrawAmount,
      })
    const withdrawReceipt = await withdrawTx.wait()
    const l2Receipt = new L2TransactionReceipt(withdrawReceipt)

    // wait until dispute period passes and withdrawal is ready for execution
    await sleep(5 * 1000)

    const messages = await l2Receipt.getL2ToL1Messages(userL1Wallet)
    const l2ToL1Msg = messages[0]
    const timeToWaitMs = 60 * 1000
    await l2ToL1Msg.waitUntilReadyToExecute(l2Provider, timeToWaitMs)

    // execute
    await (await l2ToL1Msg.execute(l2Provider)).wait()

    // check balances after withdrawal is processed
    let userL1TokenAfter, bridgeL1TokenAfter: BigNumber
    if (nativeToken) {
      userL1TokenAfter = await nativeToken.balanceOf(userL1Wallet.address)

      bridgeL1TokenAfter = await nativeToken.balanceOf(
        l2Network.ethBridge.bridge
      )
    } else {
      userL1TokenAfter = await l1Provider.getBalance(userL1Wallet.address)

      bridgeL1TokenAfter = await l1Provider.getBalance(
        l2Network.ethBridge.bridge
      )
    }
    expect(userL1NativeAssetBalance.sub(userL1TokenAfter)).to.be.eq(
      withdrawAmount
    )
    expect(bridgeL1TokenAfter.sub(bridgeL1NativeAssetBalance)).to.be.eq(
      withdrawAmount
    )

    const userL2BalanceAfter = await l2Provider.getBalance(userL2Wallet.address)
    expect(userL2BalanceAfter).to.be.lte(userL2Balance.sub(withdrawAmount))
  })
})

async function waitOnL2Msg(tx: ethers.ContractTransaction) {
  const retryableReceipt = await tx.wait()
  const l1TxReceipt = new L1TransactionReceipt(retryableReceipt)
  const messages = await l1TxReceipt.getL1ToL2Messages(l2Provider)

  // 1 msg expected
  const messageResult = await messages[0].waitForStatus()
  const status = messageResult.status
  expect(status).to.be.eq(L1ToL2MessageStatus.REDEEMED)
}

async function _getFeeToken(
  inbox: string,
  l1Provider: ethers.providers.Provider
): Promise<string> {
  const bridge = await IInbox__factory.connect(inbox, l1Provider).bridge()
  let feeToken = ethers.constants.AddressZero
  try {
    feeToken = await IERC20Bridge__factory.connect(
      bridge,
      l1Provider
    ).nativeToken()
  } catch {
    feeToken = ethers.constants.AddressZero
  }

  return feeToken
}
