import { parseEther } from 'ethers/lib/utils'
import { Config } from '../../boldUpgradeCommon'
import { hoursToBlocks } from './utils'

export const custom: Config = {
  contracts: {
    bridge: "0x547Ac55A060EF2Bf81A119822F87084BE37723D6",
    inbox: "0x5b3d95051bD1Ce4a042Fb2187B66e759d52eD324",
    outbox: "0xB50fAdd4c4dF6cA77B81D388B1421b3160b65A6D",
    rollup: "0xA05236b65432C3F7923390A0B2287b7938c0Dc93",
    sequencerInbox: "0x2D74Ad0986D15C0D86e56cF852c988846C70C77B",
    excessStakeReceiver: '0x40Cd7D713D7ae463f95cE5d342Ea6E7F5cF7C999', // receives losers' stake
    rollupEventInbox: '0x0a34f47A69183f8b6A3463E2c1D5237e61E4610d',
    upgradeExecutor: '0x45dc1ca4eB99eD50Bc013Ea01f97aF43Dfdb9491',
  },
  proxyAdmins: {
    outbox: '0xad68484E86fEC30D8ae6269cEC48b9Fa2782d6A8',
    inbox: '0xad68484E86fEC30D8ae6269cEC48b9Fa2782d6A8',
    bridge: '0xad68484E86fEC30D8ae6269cEC48b9Fa2782d6A8',
    rei: '0xad68484E86fEC30D8ae6269cEC48b9Fa2782d6A8',
    seqInbox: '0xad68484E86fEC30D8ae6269cEC48b9Fa2782d6A8',
  },
  settings: {
    challengeGracePeriodBlocks: hoursToBlocks(48), // 2 days for the chain owner to intervene in case of challenge
    confirmPeriodBlocks: 45818, // ~6.4 days
    challengePeriodBlocks: 45818, // same as confirm period
    stakeToken: '0x980B62Da83eFf3D4576C647993b0c1D7faf17c73', // rollup stake token
    stakeAmt: parseEther('3600'), // assertion stake amount
    miniStakeAmounts: [parseEther('0'), parseEther('555'), parseEther('79')], // subchallenge stake amounts (0 first level recommended)
    chainId: 42161, // child chain id
    minimumAssertionPeriod: 75, // minimum number of blocks between assertions
    validatorAfkBlocks: 201600, // number of blocks before validator whitelist is dropped due to inactivity
    disableValidatorWhitelist: true, // keep or disable validator whitelist
    blockLeafSize: 2 ** 26, // do not change unless you know what you're doing
    bigStepLeafSize: 2 ** 19, // do not change unless you know what you're doing
    smallStepLeafSize: 2 ** 23, // do not change unless you know what you're doing
    numBigStepLevel: 1, // do not change unless you know what you're doing
    maxDataSize: 117964, // do not change unless you know what you're doing
    isDelayBufferable: true, // whether to enable the delay buffer feature
    bufferConfig: {
      max: hoursToBlocks(48), // 2 days
      threshold: hoursToBlocks(0.5), // keep above typical posting frequency
      replenishRateInBasis: 500, // 5% replenishment rate
    },
  },
  // validators to be whitelisted on the new rollup
  validators: [],
}
