import { ethers } from 'hardhat'
import { BigNumber, ContractFactory } from 'ethers'
import '@nomiclabs/hardhat-ethers'
import { NodeInterface, NodeInterface__factory } from '../build/types'
import { NODE_INTERFACE_ADDRESS } from '@arbitrum/sdk/dist/lib/dataEntities/constants'
import { maxDataSize } from './config'
import {
  abi as UpgradeExecutorABI,
  bytecode as UpgradeExecutorBytecode,
} from '@offchainlabs/upgrade-executor/build/contracts/src/UpgradeExecutor.sol/UpgradeExecutor.json'

let totalGas = BigNumber.from(0)
let totalL1Gas = BigNumber.from(0)
let totalL2Gas = BigNumber.from(0)

let l2BaseFee = BigNumber.from(0)
let l1BaseFee = BigNumber.from(0)

let totalTxFees = BigNumber.from(0)

async function estimateContractDeployment(
  contractName: string,
  nodeInterface: NodeInterface,
  constructorArgs: any[] = []
): Promise<void> {
  const factory: ContractFactory = await ethers.getContractFactory(contractName)
  const gasEstimateComponents =
    await nodeInterface.callStatic.gasEstimateComponents(
      ethers.constants.AddressZero,
      true,
      factory.getDeployTransaction(...constructorArgs).data!,
      {
        blockTag: 'latest',
      }
    )

  _handleGasEstimates(gasEstimateComponents, contractName)
}

async function estimateUpgradeExecutorDeployment(nodeInterface: NodeInterface) {
  const upgradeExecutorFac = await ethers.getContractFactory(
    UpgradeExecutorABI,
    UpgradeExecutorBytecode
  )

  const gasEstimateComponents =
    await nodeInterface.callStatic.gasEstimateComponents(
      ethers.constants.AddressZero,
      true,
      upgradeExecutorFac.getDeployTransaction().data!,
      {
        blockTag: 'latest',
      }
    )

  _handleGasEstimates(gasEstimateComponents, 'UpgradeExecutor')
}

async function estimateAll(signer: any) {
  const nodeInterface = NodeInterface__factory.connect(
    NODE_INTERFACE_ADDRESS,
    signer
  )

  await estimateContractDeployment('Bridge', nodeInterface, [])
  await estimateContractDeployment('SequencerInbox', nodeInterface, [
    maxDataSize,
  ])
  await estimateContractDeployment('Inbox', nodeInterface, [maxDataSize])
  await estimateContractDeployment('RollupEventInbox', nodeInterface, [])
  await estimateContractDeployment('Outbox', nodeInterface, [])

  await estimateContractDeployment('ERC20Bridge', nodeInterface, [])
  await estimateContractDeployment('ERC20Inbox', nodeInterface, [maxDataSize])
  await estimateContractDeployment('ERC20RollupEventInbox', nodeInterface, [])
  await estimateContractDeployment('ERC20Outbox', nodeInterface, [])

  await estimateContractDeployment('BridgeCreator', nodeInterface, [
    [
      ethers.Wallet.createRandom().address,
      ethers.Wallet.createRandom().address,
      ethers.Wallet.createRandom().address,
      ethers.Wallet.createRandom().address,
      ethers.Wallet.createRandom().address,
    ],
    [
      ethers.Wallet.createRandom().address,
      ethers.Wallet.createRandom().address,
      ethers.Wallet.createRandom().address,
      ethers.Wallet.createRandom().address,
      ethers.Wallet.createRandom().address,
    ],
  ])
  await estimateContractDeployment('OneStepProver0', nodeInterface)
  await estimateContractDeployment('OneStepProverMemory', nodeInterface)
  await estimateContractDeployment('OneStepProverMath', nodeInterface)
  await estimateContractDeployment('OneStepProverHostIo', nodeInterface)
  await estimateContractDeployment('OneStepProofEntry', nodeInterface, [
    ethers.Wallet.createRandom().address,
    ethers.Wallet.createRandom().address,
    ethers.Wallet.createRandom().address,
    ethers.Wallet.createRandom().address,
  ])
  await estimateContractDeployment('ChallengeManager', nodeInterface)
  await estimateContractDeployment('RollupAdminLogic', nodeInterface)
  await estimateContractDeployment('RollupUserLogic', nodeInterface)
  await estimateUpgradeExecutorDeployment(nodeInterface)
  await estimateContractDeployment('ValidatorUtils', nodeInterface)
  await estimateContractDeployment('ValidatorWalletCreator', nodeInterface)
  await estimateContractDeployment('RollupCreator', nodeInterface)
  await estimateContractDeployment('DeployHelper', nodeInterface)
}

function _handleGasEstimates(
  gasEstimateComponents: [BigNumber, BigNumber, BigNumber, BigNumber] & {
    gasEstimate: BigNumber
    gasEstimateForL1: BigNumber
    baseFee: BigNumber
    l1BaseFeeEstimate: BigNumber
  },
  contractName: string
) {
  totalGas = totalGas.add(gasEstimateComponents.gasEstimate)
  totalL1Gas = totalL1Gas.add(gasEstimateComponents.gasEstimateForL1)
  totalL2Gas = totalL2Gas.add(
    gasEstimateComponents.gasEstimate.sub(
      gasEstimateComponents.gasEstimateForL1
    )
  )
  l2BaseFee = gasEstimateComponents.baseFee
  l1BaseFee = gasEstimateComponents.l1BaseFeeEstimate

  const P = l2BaseFee
  const L1P = l1BaseFee.mul(16)
  const l1Size = gasEstimateComponents.gasEstimateForL1.mul(P).div(L1P)
  const L1C = L1P.mul(l1Size)
  const B = L1C.div(P)
  const G = gasEstimateComponents.gasEstimate
    .sub(gasEstimateComponents.gasEstimateForL1)
    .add(B)
  const TXFEES = P.mul(G)

  totalTxFees = totalTxFees.add(TXFEES)

  _printInfo(contractName, gasEstimateComponents, L1P, l1Size, TXFEES)
}

function _printInfo(
  contractName: String,
  gasEstimateComponents: [BigNumber, BigNumber, BigNumber, BigNumber] & {
    gasEstimate: BigNumber
    gasEstimateForL1: BigNumber
    baseFee: BigNumber
    l1BaseFeeEstimate: BigNumber
  },
  L1P: BigNumber,
  l1Size: BigNumber,
  TXFEES: BigNumber
) {
  console.log(contractName)
  console.log('  L1 gas: ' + gasEstimateComponents.gasEstimateForL1)
  console.log(
    '  L2 gas: ' +
      gasEstimateComponents.gasEstimate.sub(
        gasEstimateComponents.gasEstimateForL1
      )
  )
  console.log(
    '  L1P (L1 calldata price per byte):',
    ethers.utils.formatUnits(L1P, 'gwei'),
    ' gwei'
  )
  console.log('  L1S (L1 Calldata size in bytes):', l1Size.toString(), 'bytes')
  console.log(
    '  Estimated fees to pay:',
    ethers.utils.formatEther(TXFEES),
    ' ETH'
  )
}

async function main() {
  const [signer] = await ethers.getSigners()

  await estimateAll(signer)

  console.log('\n==========================================')
  console.log('Total gas:' + totalGas)
  console.log('  L1:' + totalL1Gas)
  console.log('  L2:' + totalL2Gas)

  console.log(
    'l1BaseFee: ' + ethers.utils.formatUnits(l1BaseFee, 'gwei'),
    'gwei'
  )
  console.log(
    'l2BaseFee: ' + ethers.utils.formatUnits(l2BaseFee, 'gwei'),
    'gwei'
  )

  console.log('Total TX fees = ', ethers.utils.formatEther(totalTxFees), 'ETH')
}

main()
  .then(() => process.exit(0))
  .catch((error: Error) => {
    console.error(error)
    process.exit(1)
  })
