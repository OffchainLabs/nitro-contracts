import { parseEther } from 'ethers/lib/utils'
import { Config } from '../../boldUpgradeCommon'
import { hoursToBlocks } from './utils'

export const custom: Config = {
  contracts: {
    bridge: "0xA584795e24628D9c067A6480b033C9E96281fcA3",
    inbox: "0xDcA690902d3154886Ec259308258D10EA5450996",
    outbox: "0xda243bD61B011024FC923164db75Dde198AC6175",
    rollup: "0xA7c5B54f271844ff9cA8B5da77500180d1aD8899",
    sequencerInbox: "0x16c54EE2015CD824415c2077F4103f444E00A8cb",
    excessStakeReceiver: '0x40Cd7D713D7ae463f95cE5d342Ea6E7F5cF7C999', // receives losers' stake
    rollupEventInbox: '0xf1d4605a688ac59be02447a084bb2a35610b8deb',
    upgradeExecutor: '0x7d3bef4964410267b6531067d0751c5fe1643378',
  },
  proxyAdmins: {
    outbox: '0x1A61102c26ad3f64bA715B444C93388491fd8E68',
    inbox: '0x1A61102c26ad3f64bA715B444C93388491fd8E68',
    bridge: '0x1A61102c26ad3f64bA715B444C93388491fd8E68',
    rei: '0x1A61102c26ad3f64bA715B444C93388491fd8E68',
    seqInbox: '0x1A61102c26ad3f64bA715B444C93388491fd8E68',
  },
  settings: {
    challengeGracePeriodBlocks: hoursToBlocks(48), // 2 days for the chain owner to intervene in case of challenge
    confirmPeriodBlocks: 45818, // ~6.4 days
    challengePeriodBlocks: 45818, // same as confirm period
    stakeToken: '0xA1abD387192e3bb4e84D3109181F9f005aBaF5CA', // rollup stake token
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
