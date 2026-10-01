import { assert } from 'chai'
import { ethers, run, deployments } from 'hardhat'

describe('HashProofHelper', function () {
  it('Should produce valid proofs from full preimages', async function () {
    await run('deploy', { tags: 'HashProofHelper' })

    const hashProofHelper = await ethers.getContractAt(
      'HashProofHelper',
      (
        await deployments.get('HashProofHelper')
      ).address
    )

    for (let i = 0; i < 32; i += 1) {
      const len = Math.floor(Math.random() * 512)
      const bytes = []
      for (let j = 0; j < len; j += 1) {
        bytes.push(Math.floor(Math.random() * 256))
      }
      // offset range overlaps len so we also exercise offset >= len (empty part)
      const offset = Math.floor(Math.random() * 512)
      const hash = ethers.utils.keccak256(bytes)

      const proofTx = await hashProofHelper.proveWithFullPreimage(bytes, offset)
      const receipt = await proofTx.wait()
      const log = hashProofHelper.interface.parseLog(receipt.logs[0])
      const provenPart = await hashProofHelper.getPreimagePart(hash, offset)

      const partLen = Math.min(32, Math.max(0, len - offset))
      const expectedPart = ethers.utils.hexlify(
        bytes.slice(offset, offset + partLen)
      )
      assert.equal(log.args['fullHash'], hash)
      assert.equal(log.args['offset'], offset)
      assert.equal(log.args['part'], expectedPart)
      assert.equal(provenPart, expectedPart)
    }
  })

  it('Should produce valid proofs from split preimages', async function () {
    await run('deploy', { tags: 'HashProofHelper' })

    const hashProofHelper = await ethers.getContractAt(
      'HashProofHelper',
      (
        await deployments.get('HashProofHelper')
      ).address
    )

    for (let i = 0; i < 32; i += 1) {
      const len = Math.floor(Math.random() * 4096)
      const bytes = []
      for (let j = 0; j < len; j += 1) {
        bytes.push(Math.floor(Math.random() * 256))
      }
      // offset range overlaps len so we also exercise offset >= len (empty part)
      const offset = Math.floor(Math.random() * 4096)
      const hash = ethers.utils.keccak256(bytes)

      let provenLen = 0
      let provenPart = null
      let log = null
      while (provenPart === null) {
        // chunks of 1 to 4 keccak blocks; the final chunk takes the remainder
        let nextPartialLen = 136 * (1 + Math.floor(Math.random() * 4))
        if (nextPartialLen > len - provenLen) {
          nextPartialLen = len - provenLen
        }
        const newProvenLen = provenLen + nextPartialLen
        const isFinal = newProvenLen == len
        const proofTx = await hashProofHelper.proveWithSplitPreimage(
          bytes.slice(provenLen, newProvenLen),
          offset,
          isFinal ? 1 : 0
        )
        const receipt = await proofTx.wait()
        if (receipt.logs.length > 0) {
          log = hashProofHelper.interface.parseLog(receipt.logs[0])
          provenPart = await hashProofHelper.getPreimagePart(hash, offset)
        }
        provenLen = newProvenLen
      }

      const partLen = Math.min(32, Math.max(0, len - offset))
      const expectedPart = ethers.utils.hexlify(
        bytes.slice(offset, offset + partLen)
      )
      assert.isNotNull(log)
      assert.equal(log!.args['fullHash'], hash)
      assert.equal(log!.args['offset'], offset)
      assert.equal(log!.args['part'], expectedPart)
      assert.equal(provenPart, expectedPart)
    }
  })
})
