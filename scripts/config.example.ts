import { ethers } from 'ethers'
import {
  AssertionStateStruct,
  RollupCreator,
} from '../build/types/src/rollup/RollupCreator'

type PartialRollupParams = Pick<
  RollupCreator.RollupDeploymentParamsStruct,
  'config' | 'validators' | 'batchPosterManager' | 'batchPosters'
>

// 90% of Geth's 128KB tx size limit, leaving ~13KB for proving
// This need to be adjusted for Orbit chains
export const maxDataSize = 117964
export const isUsingFeeToken = false
const chainId = ethers.BigNumber.from('13331370')

const genesisAssertionState: AssertionStateStruct = {
  globalState: {
    bytes32Vals: [ethers.constants.HashZero, ethers.constants.HashZero],
    u64Vals: [ethers.BigNumber.from('0'), ethers.BigNumber.from('0')],
  },
  machineStatus: 1, // FINISHED
  endHistoryRoot: ethers.constants.HashZero,
}

export const config: PartialRollupParams = {
  config: {
    confirmPeriodBlocks: ethers.BigNumber.from('45818'),
    stakeToken: process.env.STAKE_TOKEN_ADDRESS!,
    baseStake: ethers.utils.parseEther('1'),
    wasmModuleRoot:
      '0x184884e1eb9fefdc158f6c8ac912bb183bf3cf83f0090317e0bc4ac5860baa39', // Arbitrum Nitro Consensus v32
    owner: '0x1234123412341234123412341234123412341234',
    loserStakeEscrow: '0x1234123412341234123412341234123412341234', // Cannot be address(0)
    chainId: chainId,
    chainConfig: `{"chainId":${chainId.toString()},"homesteadBlock":0,"daoForkBlock":null,"daoForkSupport":true,"eip150Block":0,"eip150Hash":"0x0000000000000000000000000000000000000000000000000000000000000000","eip155Block":0,"eip158Block":0,"byzantiumBlock":0,"constantinopleBlock":0,"petersburgBlock":0,"istanbulBlock":0,"muirGlacierBlock":0,"berlinBlock":0,"londonBlock":0,"clique":{"period":0,"epoch":0},"arbitrum":{"EnableArbOS":true,"AllowDebugPrecompiles":false,"DataAvailabilityCommittee":false,"InitialArbOSVersion":32,"InitialChainOwner":"0x1234123412341234123412341234123412341234","GenesisBlockNum":0}}`,
    minimumAssertionPeriod: 75,
    validatorAfkBlocks: 201600,
    genesisAssertionState: genesisAssertionState,
    genesisInboxCount: 0,
    miniStakeValues: [
      0,
      ethers.utils.parseEther('0.5'),
      ethers.utils.parseEther('0.25'),
    ],
    layerZeroBlockEdgeHeight: 2 ** 26,
    layerZeroBigStepEdgeHeight: 2 ** 19,
    layerZeroSmallStepEdgeHeight: 2 ** 23,
    numBigStepLevel: 1,
    challengeGracePeriodBlocks: 10,
    bufferConfig: {
      threshold: ethers.BigNumber.from('600'), // Set this to 0 to disable delay buffer
      max: ethers.BigNumber.from('14400'),
      replenishRateInBasis: ethers.BigNumber.from('833'),
    },
    sequencerInboxMaxTimeVariation: {
      delayBlocks: ethers.BigNumber.from('7200'),
      futureBlocks: ethers.BigNumber.from('12'),
      delaySeconds: ethers.BigNumber.from('86400'),
      futureSeconds: ethers.BigNumber.from('3600'),
    },
    anyTrustFastConfirmer: ethers.constants.AddressZero,
  },
  validators: [
    '0x1234123412341234123412341234123412341234',
    '0x1234512345123451234512345123451234512345',
  ],
  batchPosterManager: '0x1234123412341234123412341234123412341234',
  batchPosters: ['0x1234123412341234123412341234123412341234'],
}

// These value should be defined in the env
// TODO: Consolidate configs to a single file, these env vars are used in nitro-testnode
console.log('ROLLUP_CREATOR_ADDRESS  :', process.env.ROLLUP_CREATOR_ADDRESS)
console.log('STAKE_TOKEN_ADDRESS     :', process.env.STAKE_TOKEN_ADDRESS)
if (config.config.stakeToken !== process.env.STAKE_TOKEN_ADDRESS) {
  throw new Error('STAKE_TOKEN_ADDRESS mismatch')
}
console.log('FEE_TOKEN_ADDRESS       :', process.env.FEE_TOKEN_ADDRESS)
console.log('FEE_TOKEN_PRICER_ADDRESS:', process.env.FEE_TOKEN_PRICER_ADDRESS)

console.log(config.config.chainConfig)
