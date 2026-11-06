import { parseEther } from 'ethers/lib/utils'
import { Config } from '../../boldUpgradeCommon'
import { hoursToBlocks } from './utils'

export const local: Config = {
  contracts: {
    bridge: '0x5eCF728ffC5C5E802091875f96281B5aeECf6C49',
    inbox: '0x9f8c1c641336A371031499e3c362e40d58d0f254',
    outbox: '0x50143333b44Ea46255BEb67255C9Afd35551072F',
    rollup: '0xe5Ab92C74CD297F0a1F2914cE37204FC5Bc4e82D',
    sequencerInbox: '0x18d19C5d3E685f5be5b9C86E097f0E439285D216',
    rollupEventInbox: '0x0e73faf857e1ca53e700856fcf19f31f920a1e3c',
    upgradeExecutor: '0x513d9f96d4d0563debae8a0dc307ea0e46b10ed7',
    excessStakeReceiver: '0xC3124dD1FA0e5D6135c25279760DBF9d9286467B',
  },
  proxyAdmins: {
    outbox: '0x2a1f38c9097e7883570e0b02bfbe6869cc25d8a3',
    inbox: '0x2a1f38c9097e7883570e0b02bfbe6869cc25d8a3',
    bridge: '0x2a1f38c9097e7883570e0b02bfbe6869cc25d8a3',
    rei: '0x2a1f38c9097e7883570e0b02bfbe6869cc25d8a3',
    seqInbox: '0x2a1f38c9097e7883570e0b02bfbe6869cc25d8a3',
  },
  settings: {
    challengeGracePeriodBlocks: 10,
    confirmPeriodBlocks: 100,
    challengePeriodBlocks: 110,
    stakeToken: '0x43C9c3Ab961c49f8d42227628617747b1da7bcF0',
    stakeAmt: parseEther('1'),
    miniStakeAmounts: [
      parseEther('6'),
      parseEther('5'),
      parseEther('4'),
      parseEther('3'),
      parseEther('2'),
      parseEther('1'),
    ],
    chainId: 412346,
    minimumAssertionPeriod: 15,
    validatorAfkBlocks: 201600,
    disableValidatorWhitelist: true,
    blockLeafSize: 1048576,
    bigStepLeafSize: 512,
    smallStepLeafSize: 128,
    numBigStepLevel: 4,
    maxDataSize: 117964,
    isDelayBufferable: true,
    bufferConfig: {
      max: 2 ** 32, // effectively disableing and will be enabled later
      threshold: 2 ** 32, // effectively disableing and will be enabled later
      replenishRateInBasis: 500,
    },
  },
  validators: ['0x139A0b6B1Dd1e7F912361B32A09cAD89e82F29db'],
}
