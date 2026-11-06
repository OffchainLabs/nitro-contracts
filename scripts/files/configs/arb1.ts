import { parseEther } from 'ethers/lib/utils'
import { Config } from '../../boldUpgradeCommon'
import { hoursToBlocks } from './utils'

export const arb1: Config = {
  contracts: {
    // it both the excess stake receiver and loser stake escrow
    excessStakeReceiver: '0x40Cd7D713D7ae463f95cE5d342Ea6E7F5cF7C999', // parent to child router
    rollup: '0x5eF0D09d1E6204141B4d37530808eD19f60FBa35',
    bridge: '0x8315177aB297bA92A06054cE80a67Ed4DBd7ed3a',
    sequencerInbox: '0x1c479675ad559DC151F6Ec7ed3FbF8ceE79582B6',
    rollupEventInbox: '0x57Bd336d579A51938619271a7Cc137a46D0501B1',
    outbox: '0x0B9857ae2D4A3DBe74ffE1d7DF045bb7F96E4840',
    inbox: '0x4Dbd4fc535Ac27206064B68FfCf827b0A60BAB3f',
    upgradeExecutor: '0x3ffFbAdAF827559da092217e474760E2b2c3CeDd',
  },
  proxyAdmins: {
    outbox: '0x554723262467f125ac9e1cdfa9ce15cc53822dbd',
    inbox: '0x554723262467f125ac9e1cdfa9ce15cc53822dbd',
    bridge: '0x554723262467f125ac9e1cdfa9ce15cc53822dbd',
    rei: '0x554723262467f125ac9e1cdfa9ce15cc53822dbd',
    seqInbox: '0x554723262467f125ac9e1cdfa9ce15cc53822dbd',
  },
  settings: {
    challengeGracePeriodBlocks: hoursToBlocks(48),
    confirmPeriodBlocks: 45818, // same as old rollup, ~6.4 days
    challengePeriodBlocks: 45818, // same as confirm period
    stakeToken: '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2', // WETH
    stakeAmt: parseEther('3600'),
    miniStakeAmounts: [parseEther('0'), parseEther('555'), parseEther('79')],
    chainId: 42161,
    minimumAssertionPeriod: 75,
    validatorAfkBlocks: 201600,
    disableValidatorWhitelist: true,
    blockLeafSize: 2 ** 26,
    bigStepLeafSize: 2 ** 19,
    smallStepLeafSize: 2 ** 23,
    numBigStepLevel: 1,
    maxDataSize: 117964,
    isDelayBufferable: true,
    bufferConfig: {
      max: hoursToBlocks(48), // 2 days
      threshold: hoursToBlocks(0.5), // well above typical posting frequency
      replenishRateInBasis: 500, // 5% replenishment rate
    },
  },
  // validator whitelist will be disabled
  validators: [],
}
