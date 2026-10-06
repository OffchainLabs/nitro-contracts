import { BigNumber } from '@ethersproject/bignumber'
import { solidityKeccak256 } from 'ethers/lib/utils'

export enum MachineStatus {
  RUNNING = 0,
  YIELDED = 1,
  ERRORED = 2,
  TOO_FAR = 3, // Unused
  FINISHED = 4,
}

export function machineHash(machineStatus: BigNumber, globalStateHash: string) {
  const machineStatusNum = machineStatus.toNumber()
  if (machineStatusNum === MachineStatus.YIELDED) {
    return solidityKeccak256(
      ['string', 'bytes32'],
      ['Machine yielded:', globalStateHash]
    )
  } else if (machineStatusNum === MachineStatus.FINISHED) {
    return solidityKeccak256(
      ['string', 'bytes32'],
      ['Machine finished:', globalStateHash]
    )
  } else if (machineStatusNum === MachineStatus.ERRORED) {
    return solidityKeccak256(
      ['string', 'bytes32'],
      ['Machine errored:', globalStateHash]
    )
  } else {
    console.log(machineStatus.toNumber())
    throw new Error('BAD_BLOCK_STATUS')
  }
}
