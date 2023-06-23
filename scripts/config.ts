import { ethers } from 'ethers'

export const rollupConfig = {
  confirmPeriodBlocks: ethers.BigNumber.from(''),
  extraChallengeTimeBlocks: ethers.BigNumber.from(''),
  stakeToken: '',
  baseStake: ethers.utils.parseEther(''),
  wasmModuleRoot:
    '0xda4e3ad5e7feacb817c21c8d0220da7650fe9051ece68a3f0b1c5d38bbb27b21',
  owner: '',
  loserStakeEscrow: '',
  chainId: ethers.BigNumber.from(''),
  chainConfig: '',
  genesisBlockNum: ethers.BigNumber.from(''),
  sequencerInboxMaxTimeVariation: {
    delayBlocks: ethers.BigNumber.from(''),
    futureBlocks: ethers.BigNumber.from(''),
    delaySeconds: ethers.BigNumber.from(''),
    futureSeconds: ethers.BigNumber.from(''),
  },
}
