import { parseEther } from 'ethers/lib/utils'
import { Config } from '../../boldUpgradeCommon'
import { hoursToBlocks } from './utils'

export const custom: Config = {
  contracts: {
    bridge: '',
    inbox: '',
    outbox: '',
    rollup: '',
    sequencerInbox: '',
    excessStakeReceiver: '', // receives losers' stake
    rollupEventInbox: '',
    upgradeExecutor: '',
  },
  proxyAdmins: {
    outbox: '', // e.g. the address of the proxy admin for the outbox
    inbox: '',
    bridge: '',
    rei: '',
    seqInbox: '',
  },
  settings: {
    challengeGracePeriodBlocks: hoursToBlocks(48), // 2 days for the chain owner to intervene in case of challenge
    confirmPeriodBlocks: 50400, // 7 days in terms of the parent chain's block.number timing
    challengePeriodBlocks: 50400, // same as confirm period
    stakeToken: '', // rollup stake token
    stakeAmt: parseEther('1'), // assertion stake amount
    miniStakeAmounts: [parseEther('0'), parseEther('1'), parseEther('1')], // subchallenge stake amounts (0 first level recommended)
    chainId: 42161, // child chain id
    minimumAssertionPeriod: 75, // minimum number of blocks between assertions
    validatorAfkBlocks: 201600, // number of blocks before validator whitelist is dropped due to inactivity
    disableValidatorWhitelist: false, // keep or disable validator whitelist
    blockLeafSize: 2 ** 26, // do not change unless you know what you're doing
    bigStepLeafSize: 2 ** 19, // do not change unless you know what you're doing
    smallStepLeafSize: 2 ** 23, // do not change unless you know what you're doing
    numBigStepLevel: 1, // do not change unless you know what you're doing
    maxDataSize: 117964, // if you're an L3, this should be set to 104857
    isDelayBufferable: true, // it is recommended to keep this as true, even if you don't use the feature
    bufferConfig: {
      max: 2 ** 32 - 1, // maximum buffer size, set artificially high to disable
      threshold: 2 ** 32 - 1, // keep above typical posting frequency. set artificially high to disable
      replenishRateInBasis: 500, // 5% replenishment rate
    },
  },
  // validators to be whitelisted on the new rollup
  validators: [],
}
