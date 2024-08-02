import { parseEther } from 'ethers/lib/utils'
import { Config } from '../../boldUpgradeCommon'
import { hoursToBlocks } from '.'

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
    anyTrustFastConfirmer: '0x0000000000000000000000000000000000000000',
    disableValidatorWhitelist: true,
    blockLeafSize: 2**26,
    bigStepLeafSize: 2**19,
    smallStepLeafSize: 2**23,
    numBigStepLevel: 1,
    maxDataSize: 117964,
    isDelayBufferable: true,
    // TODO: align
    bufferConfig: {
      max: hoursToBlocks(48),
      threshold: hoursToBlocks(1),
      replenishRateInBasis: 500,
    },
  },
  // current validators
  // TODO: we should probably leave this empty
  validators: [
    '0x83215480dB2C6A7E56f9E99EF93AB9B36F8A3DD5',
    '0x7CF3d537733F6Ba4183A833c9B021265716cE9d0',
    '0x56D83349c2B8DCF74d7E92D5b6B33d0BADD52D78',
    '0x758C6bB08B3ea5889B5cddbdeF9A45b3a983c398',
    '0x6Fb914de4653eC5592B7c15F4d9466Cbd03F2104',
    '0xf59caf75e8A4bFBA4e6e07aD86C7E498E4d2519b',
    '0xB0CB1384e3f4a9a9b2447e39b05e10631E1D34B0',
    '0x54c0D3d6C101580dB3be8763A2aE2c6bb9dc840c',
    '0x0fF813f6BD577c3D1cDbE435baC0621BE6aE34B4',
    '0xAB1A39332e934300eBCc57B5f95cA90631a347FF',
    '0xdDf2F71Ab206C0138A8eceEb54386567D5abF01E',
    '0x610Aa279989F440820e14248BD3879B148717974',
    '0xF8D3E1cF58386c92B27710C6a0D8A54c76BC6ab5'
  ]
}
