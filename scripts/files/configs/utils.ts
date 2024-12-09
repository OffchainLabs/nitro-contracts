export function hoursToBlocks(hours: number, blockTime = 12) {
  const x = (hours * 3600) / blockTime
  if (x !== Math.floor(x)) {
    throw new Error('hours must be divisible by blockTime')
  }
  if (x === 0) {
    throw new Error('hours must be greater than 0')
  }
  return x
}
