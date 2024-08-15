import { parseEther } from 'ethers/lib/utils'
import { Config } from '../../boldUpgradeCommon'
import { hoursToBlocks } from './utils'

export const sepolia: Config = {
  contracts: {
    excessStakeReceiver: '0x391611E7bba966000AC6c78aFc673C4AE46f8BCa', // chain owner multisig
    rollup: '0xd80810638dbDF9081b72C1B33c65375e807281C8',
    bridge: '0x38f918D0E9F1b721EDaA41302E399fa1B79333a9',
    sequencerInbox: '0x6c97864CE4bEf387dE0b3310A44230f7E3F1be0D',
    rollupEventInbox: '0xD5B196dd7EC4D823ff5F695536c61f7c8E642B94',
    outbox: '0x65f07C7D521164a4d5DaC6eB8Fac8DA067A3B78F',
    inbox: '0xaAe29B0366299461418F5324a79Afc425BE5ae21',
    upgradeExecutor: '0x5FEe78FE9AD96c1d8557C6D6BB22Eb5A61eeD315',
  },
  proxyAdmins: {
    outbox: '0xdd63bcaa89d7c3199ef220c1dd59c49f821078b8',
    inbox: '0xdd63bcaa89d7c3199ef220c1dd59c49f821078b8',
    bridge: '0xdd63bcaa89d7c3199ef220c1dd59c49f821078b8',
    rei: '0xdd63bcaa89d7c3199ef220c1dd59c49f821078b8',
    seqInbox: '0xdd63bcaa89d7c3199ef220c1dd59c49f821078b8',
  },
  settings: {
    // TODO: confirm that we want 20/20
    challengeGracePeriodBlocks: 20,
    confirmPeriodBlocks: 20, // current is 20 blocks, 45818 is arb1 config
    challengePeriodBlocks: 45818, // same as arb1 // TODO: do we want to shorten this given validators are whitelisted?
    stakeToken: '0xefb383126640fe4a760010c6e59c397d2b6c7141', // WETH
    stakeAmt: parseEther('36'), // 1/100th of arb1, same for mini stakes
    miniStakeAmounts: [
      parseEther('0'),
      parseEther('5.5'),
      parseEther('0.79'),
    ],
    chainId: 421614,
    anyTrustFastConfirmer: '0x0000000000000000000000000000000000000000',
    disableValidatorWhitelist: false,
    blockLeafSize: 2**26, // leaf sizes same as arb1
    bigStepLeafSize: 2**19,
    smallStepLeafSize: 2**23,
    numBigStepLevel: 1,
    maxDataSize: 117964,
    isDelayBufferable: true,
    bufferConfig: {
      max: hoursToBlocks(24*365), // 365 days, effectively disableing and will be enabled later
      threshold: hoursToBlocks(24*365), // 365 days, effectively disableing and will be enabled later
      replenishRateInBasis: 500, // 5% replenishment rate
    },
  },
  // validators will be set later by BOLDUpgradeAction.perform(address[])
  validators: [],
}
