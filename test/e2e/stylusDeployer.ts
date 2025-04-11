import { JsonRpcProvider } from '@ethersproject/providers'
import { expect } from 'chai'
import {
  ArbWasm__factory,
  ConstructorError__factory,
  NoReceiveForwarder__factory,
  ReceivingForwarder__factory,
  StylusDeployer,
  StylusDeployer__factory,
} from '../../build/types'
import { BigNumber, Wallet, constants, ethers } from 'ethers'
import fs from 'fs'
import { keccak256, parseEther } from 'ethers/lib/utils'
import { ProgramActivatedEventObject } from '../../build/types/src/precompiles/ArbWasm'
import { ContractDeployedEventObject } from '../../build/types/src/stylus/StylusDeployer'

const LOCALHOST_L2_RPC = 'http://127.0.0.1:8547'
export const l1mnemonic =
  'indoor dish desk flag debris potato excuse depart ticket judge file exit'
const iArbWasm = ArbWasm__factory.createInterface()
const arbWasmAddr = '0x0000000000000000000000000000000000000071'
const counterInterface = new ethers.utils.Interface([
  'function number() view returns (uint256)',
  'function setNumber(uint256 newNumber)',
  'function addNumber(uint256 newNumber)',
  'function mulNumber(uint256 newNumber)',
  'function increment()',
])

const getConnectedL2Wallet = async () => {
  const l2Provider = new JsonRpcProvider(LOCALHOST_L2_RPC)
  const admin = ethers.Wallet.fromMnemonic(
    l1mnemonic,
    "m/44'/60'/0'/0/0"
  ).connect(l2Provider)

  const randWallet = Wallet.createRandom().connect(l2Provider)
  await admin.sendTransaction({
    to: randWallet.address,
    value: constants.WeiPerEther.mul(10),
  })
  return randWallet
}

const getProgramActivatedEvent = (rec: ethers.ContractReceipt) => {
  return rec.events
    ?.filter(e => e.address === arbWasmAddr)
    .map(e =>
      iArbWasm.decodeEventLog(
        iArbWasm.events[
          'ProgramActivated(bytes32,bytes32,address,uint256,uint16)'
        ],
        e.data,
        e.topics
      )
    )[0] as unknown as ProgramActivatedEventObject
}

const getContractDeployedEvent = (
  rec: ethers.ContractReceipt,
  deployer: StylusDeployer
) => {
  return rec.events
    ?.filter(e => e.address === deployer.address)
    .map(e =>
      iArbWasm.decodeEventLog(
        deployer.interface.events['ContractDeployed(address)'],
        e.data,
        e.topics
      )
    )[0] as unknown as ContractDeployedEventObject
}

const getBytecode = (increment: number) => {
  const fileLocation =
    increment === 0
      ? './test/e2e/counter.txt'
      : `./test/e2e/stylusTestFiles/counter${increment}.txt`
  return fs.readFileSync(fileLocation).toString()
}

const estimateActivationCost = async (bytecode: string, wallet: Wallet) => {
  // deploy a contract but dont activate it, use that to estimate activation
  const res = await wallet.sendTransaction({
    data: bytecode,
  })
  const rec = await res.wait()
  const arbWasm = await ArbWasm__factory.connect(arbWasmAddr, wallet.provider)
  try {
    const fee = await arbWasm.callStatic.activateProgram(rec.contractAddress, {
      from: wallet.address,
      value: await wallet.getBalance(),
    })
    return fee.dataFee
  } catch (err) {
    // if we errored we may be on the correct code hash
    try {
      const version = await arbWasm.callStatic.programVersion(
        rec.contractAddress
      )
      if (version == (await arbWasm.callStatic.stylusVersion())) {
        return BigNumber.from(0)
      } else {
        throw err
      }
    } catch {
      // rethrow the original error
      throw err
    }
  }
}

const deploy = async (args: {
  wallet: Wallet
  deployer: StylusDeployer
  bytecode: string
  initData: string
  initVal: BigNumber
  expectActivation: boolean
  expectedInitCounter: BigNumber
  salt: string
  expectRevert?: boolean
  notEnoughForActivation?: boolean
  forwarder?: ethers.Contract
  overrideValue?: BigNumber
}) => {
  let activationFee = BigNumber.from(0)
  if (args.expectActivation) {
    activationFee = await estimateActivationCost(args.bytecode, args.wallet)
    expect(
      args.expectActivation ? !activationFee.eq(0) : activationFee.eq(0),
      'activation zero'
    ).to.be.true
  }

  let bufferedActivationFee = activationFee.mul(11).div(10)
  if (args.notEnoughForActivation === true) {
    bufferedActivationFee = bufferedActivationFee.div(2)
  }

  let rec
  let errorOccurred = false
  const txVal = args.overrideValue || bufferedActivationFee.add(args.initVal)
  try {
    if (args.forwarder) {
      const forwardData = args.deployer.interface.encodeFunctionData('deploy', [
        args.bytecode,
        args.initData,
        args.initVal,
        args.salt,
      ])
      const res = await args.forwarder.forward(
        args.deployer.address,
        forwardData,
        { value: txVal }
      )
      rec = await res.wait()
    } else {
      const res = await args.deployer.deploy(
        args.bytecode,
        args.initData,
        args.initVal,
        args.salt,
        { value: txVal }
      )
      rec = await res.wait()
    }
  } catch (err) {
    errorOccurred = true
    if (args.expectRevert === true) {
      return
    } else {
      throw err
    }
  }

  if (args.expectRevert === true && errorOccurred === false) {
    throw new Error('Expected revert but not found')
  }

  expect(rec.events?.length, 'Deploy events').eq(args.expectActivation ? 2 : 1)
  const contractDeployed = getContractDeployedEvent(rec, args.deployer)
  if (args.salt !== constants.HashZero) {
    const initSalt = await args.deployer.callStatic.initSalt(
      args.salt,
      args.initData
    )
    // calculate the epected address
    const address = ethers.utils.getCreate2Address(
      args.deployer.address,
      initSalt,
      ethers.utils.keccak256(args.bytecode)
    )
    expect(contractDeployed.deployedContract, 'Create 2 address').to.eq(address)
  }

  let dataFee = BigNumber.from(0)
  if (args.expectActivation) {
    const programActivated = getProgramActivatedEvent(rec)
    // TODO: check if this is supposed to be exact or not
    expect(programActivated.dataFee).to.closeTo(
      activationFee,
      activationFee.div(10),
      'incorrect activation fee'
    )
    dataFee = programActivated.dataFee
    expect(programActivated.program).to.eq(
      contractDeployed.deployedContract,
      'invalid contract address'
    )
  }
  expect(contractDeployed).to.not.be.undefined
  expect(contractDeployed).to.not.eq(constants.AddressZero)

  const contract = new ethers.Contract(
    contractDeployed.deployedContract,
    counterInterface,
    args.wallet.provider
  )
  const counter = (await contract.callStatic['number']()) as BigNumber
  expect(counter.eq(args.expectedInitCounter), 'unexpected init counter').to.be
    .true
  const bal = await args.wallet.provider.getBalance(
    contractDeployed.deployedContract
  )
  expect(bal.eq(args.initVal), 'unexpected init val').to.be.true

  if (args.forwarder) {
    if (args.expectActivation) {
      const remainder = txVal.sub(dataFee).sub(args.initVal)
      const currentBalance = await args.wallet.provider.getBalance(
        args.forwarder.address
      )
      expect(remainder.eq(currentBalance), 'remaining balance').to.be.true
    } else if (!txVal.eq(args.initVal)) {
      const remainder = txVal.sub(args.initVal)
      const currentBalance = await args.wallet.provider.getBalance(
        args.forwarder.address
      )
      expect(remainder.eq(currentBalance), 'remaining balance').to.be.true
    }
  }
}

describe('Stylus deployer', () => {
  it('create2 deploy, activate, init', async () => {
    const wall = await getConnectedL2Wallet()
    const deployer = await new StylusDeployer__factory(wall).deploy()
    const bytecode = getBytecode(1)

    await deploy({
      wallet: wall,
      bytecode,
      deployer,
      expectActivation: true,
      initData: counterInterface.encodeFunctionData('setNumber', [
        BigNumber.from(12),
      ]),
      initVal: BigNumber.from(parseEther('0.0133')),
      expectedInitCounter: BigNumber.from(12),
      salt: keccak256('0x20'),
    })

    // cant deploy again with same salt
    await deploy({
      wallet: wall,
      bytecode,
      deployer,
      expectActivation: false,
      initData: counterInterface.encodeFunctionData('setNumber', [
        BigNumber.from(12),
      ]),
      initVal: BigNumber.from(parseEther('0.0133')),
      expectedInitCounter: BigNumber.from(12),
      salt: keccak256('0x20'),
      expectRevert: true,
    })

    // deploy again with different salt
    await deploy({
      wallet: wall,
      bytecode,
      deployer,
      expectActivation: false,
      initData: counterInterface.encodeFunctionData('setNumber', [
        BigNumber.from(12),
      ]),
      initVal: BigNumber.from(parseEther('0.0133')),
      expectedInitCounter: BigNumber.from(12),
      salt: keccak256('0x21'),
    })

    // deploy again with different init data
    await deploy({
      wallet: wall,
      bytecode,
      deployer,
      expectActivation: false,
      initData: counterInterface.encodeFunctionData('setNumber', [
        BigNumber.from(11),
      ]),
      initVal: BigNumber.from(parseEther('0.0133')),
      expectedInitCounter: BigNumber.from(11),
      salt: keccak256('0x20'),
    })

    // deploy again, this time we expect no activate
    await deploy({
      wallet: wall,
      bytecode,
      deployer,
      expectActivation: false,
      initData: '0x',
      initVal: BigNumber.from(0),
      expectedInitCounter: BigNumber.from(0),
      salt: keccak256('0x20'),
    })

    // deploy with different args, this time we expect no activate, but we do expect init
    await deploy({
      wallet: wall,
      bytecode,
      deployer,
      expectActivation: false,
      initData: counterInterface.encodeFunctionData('setNumber', [
        BigNumber.from(13),
      ]),
      initVal: BigNumber.from(parseEther('0.0137')),
      expectedInitCounter: BigNumber.from(13),
      salt: keccak256('0x20'),
    })
  })

  it('create1 deploy, activate, init', async function () {
    const wall = await getConnectedL2Wallet()
    const deployer = await new StylusDeployer__factory(wall).deploy()
    const bytecode = getBytecode(2)

    await deploy({
      wallet: wall,
      bytecode,
      deployer,
      expectActivation: true,
      initData: counterInterface.encodeFunctionData('setNumber', [
        BigNumber.from(12),
      ]),
      initVal: BigNumber.from(parseEther('0.0133')),
      expectedInitCounter: BigNumber.from(12),
      salt: constants.HashZero,
    })

    // deploy again, this time we expect no activate
    await deploy({
      wallet: wall,
      bytecode,
      deployer,
      expectActivation: false,
      initData: '0x',
      initVal: BigNumber.from(0),
      expectedInitCounter: BigNumber.from(0),
      salt: constants.HashZero,
    })

    // deploy with different args, this time we expect no activate, but we do expect init
    await deploy({
      wallet: wall,
      bytecode,
      deployer,
      expectActivation: false,
      initData: counterInterface.encodeFunctionData('setNumber', [
        BigNumber.from(13),
      ]),
      initVal: BigNumber.from(parseEther('0.0137')),
      expectedInitCounter: BigNumber.from(13),
      salt: constants.HashZero,
    })
  })

  it('errors', async () => {
    const wall = await getConnectedL2Wallet()
    const deployer = await new StylusDeployer__factory(wall).deploy()
    const bytecode = getBytecode(3)
    const noReceiveForwarder = await new NoReceiveForwarder__factory(
      wall
    ).deploy()
    const constructorErrorBytecode = new ConstructorError__factory().bytecode

    // deploy a contract that will error upon construction
    await deploy({
      wallet: wall,
      bytecode: constructorErrorBytecode,
      deployer,
      expectActivation: false,
      initData: '0x',
      initVal: BigNumber.from(0),
      expectedInitCounter: BigNumber.from(0),
      salt: constants.HashZero,
      expectRevert: true,
    })
    await deploy({
      wallet: wall,
      bytecode: constructorErrorBytecode,
      deployer,
      expectActivation: false,
      initData: '0x',
      initVal: BigNumber.from(0),
      expectedInitCounter: BigNumber.from(0),
      salt: keccak256('0x56'),
      expectRevert: true,
    })

    // init value without init data
    await deploy({
      wallet: wall,
      bytecode,
      deployer,
      expectActivation: true,
      initData: '0x',
      initVal: BigNumber.from(parseEther('0.0133')),
      expectedInitCounter: BigNumber.from(0),
      salt: keccak256('0x20'),
      expectRevert: true,
    })

    // insufficent activatin value
    await deploy({
      wallet: wall,
      bytecode,
      deployer,
      expectActivation: true,
      initData: '0x',
      initVal: BigNumber.from(0),
      expectedInitCounter: BigNumber.from(0),
      salt: keccak256('0x20'),
      notEnoughForActivation: true,
      expectRevert: true,
    })

    // this forwarder cant receive value
    await deploy({
      wallet: wall,
      bytecode,
      deployer,
      expectActivation: true,
      initData: '0x',
      initVal: BigNumber.from(0),
      expectedInitCounter: BigNumber.from(0),
      salt: keccak256('0x20'),
      expectRevert: true,
      forwarder: noReceiveForwarder,
    })
  })

  it('refund checks', async () => {
    const wall = await getConnectedL2Wallet()
    const deployer = await new StylusDeployer__factory(wall).deploy()
    const bytecode = getBytecode(4)
    const forwarder1 = await new ReceivingForwarder__factory(wall).deploy()
    const forwarder2 = await new ReceivingForwarder__factory(wall).deploy()

    await deploy({
      wallet: wall,
      bytecode,
      deployer,
      expectActivation: true,
      initData: counterInterface.encodeFunctionData('setNumber', [
        BigNumber.from(12),
      ]),
      initVal: BigNumber.from(parseEther('0.0133')),
      expectedInitCounter: BigNumber.from(12),
      salt: keccak256('0x20'),
      forwarder: forwarder1,
    })

    await deploy({
      wallet: wall,
      bytecode,
      deployer,
      expectActivation: false,
      initData: counterInterface.encodeFunctionData('setNumber', [
        BigNumber.from(12),
      ]),
      initVal: BigNumber.from(parseEther('0.0133')),
      expectedInitCounter: BigNumber.from(12),
      salt: keccak256('0x21'),
      forwarder: forwarder2,
      overrideValue: parseEther('1'),
    })
  })
})
