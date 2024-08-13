import { arb1 } from './arb1'
import { nova } from './nova'
import { sepolia } from './sepolia'
import { local } from './local'

export function hoursToBlocks(hours: number, blockTime = 12) {
  const x = hours * 3600 / blockTime
  if (x !== Math.floor(x)) {
    throw new Error('hours must be divisible by blockTime')
  }
  if (x === 0) {
    throw new Error('hours must be greater than 0')
  }
  return x
}

export const configs = {
  arb1,
  nova,
  sepolia,
  local,
}
